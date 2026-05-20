//// MIME type lookup and byte-signature detection for Gleam.
////
//// The public API is built around the opaque `MimeType` value: every
//// detection / lookup function returns a `MimeType` (or
//// `Result(MimeType, _)`), and predicates / accessors operate on
//// `MimeType` rather than ad-hoc strings. Use `parse/1` to construct a
//// `MimeType` from a wire-format string and `to_string/1` to serialise
//// one back out (e.g. for an HTTP `Content-Type` header).
////
//// The library intentionally separates:
//// - extension / filename lookup, which is cheap and deterministic
//// - magic-number detection, which inspects the leading bytes
//// - combined helpers, which prefer content-based detection and fall
////   back to metadata when the byte signature is unknown

import gleam/bool
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import mimetype/internal/detect as detect_internal
import mimetype/internal/lookup as lookup_internal
import mimetype/internal/parse as parse_internal
import mimetype/internal/predicates as predicates_internal

/// A normalised, validated MIME type.
///
/// Construct one with `parse/1` (from a wire-format string), or via the
/// detection / lookup helpers (`detect/1`, `extension_to_mime_type/1`,
/// `filename_to_mime_type/1`, ...). Inspect with `essence_of/1`,
/// `parameter_of/2`, `charset_of_type/1`, `is_image/1`, `is_a/2`, and
/// the rest of the predicate / accessor family. Serialise back to a
/// string with `to_string/1`.
pub opaque type MimeType {
  MimeType(essence: String, parameters: List(#(String, String)))
}

/// Why `parse/1` rejected a string.
pub type ParseError {
  /// The input was empty or contained only whitespace.
  EmptyMimeType
  /// The input did not match the `type/subtype` essence shape required
  /// by RFC 6838. The original input is carried so the caller can
  /// render it without re-parsing.
  InvalidMimeType(String)
  /// A parameter name was not a valid RFC 9110 §5.6.6 / RFC 7230
  /// §3.2.6 `token`. Most commonly this means the name contained
  /// whitespace (SP, HTAB) or another non-tchar codepoint —
  /// `"chars et"`, `"cha\tarset"`, etc. Carries the trimmed but
  /// non-case-folded name so callers can render an actionable error
  /// like "parameter name 'chars et' contains whitespace".
  /// Round-tripping such a name through `to_string` would otherwise
  /// emit a malformed `Content-Type` header that RFC-strict HTTP
  /// receivers drop the parameter from.
  InvalidParameterName(name: String)
  /// A parameter value contained an ASCII control byte that is valid
  /// in neither `token` nor `quoted-string` per RFC 7231 §3.1.1.1.
  /// Carries the parameter name and the offending codepoint so the
  /// caller can render an actionable error like
  /// "parameter 'charset' contains forbidden control byte 0x01".
  /// Allowed: HTAB (0x09) and every byte at or above 0x20 except DEL
  /// (0x7F). Rejected: 0x00-0x08, 0x0A-0x1F, 0x7F.
  InvalidParameterValue(parameter: String, byte: Int)
}

/// Reasons the strict detection family can return `Error(_)`.
///
/// The error is structured so callers can distinguish "no signature
/// matched" from "the reader itself failed before any bytes could be
/// inspected" from "the supplied filename / extension is not in the
/// database" from "the input was empty" — useful for HTTP upload
/// pipelines that want to render each case differently. `read_error`
/// is the type the supplied `Reader` produces; it flows through
/// unchanged when the reader fails. Strict functions that do not take
/// a reader use `DetectionError(Nil)`; the `SimpleDetectionError`
/// alias below is the recommended name for that shape at non-reader
/// call sites.
pub type DetectionError(read_error) {
  /// No signature matched the bytes that were inspected, and no
  /// filename / extension hint resolved.
  NoMatch
  /// The supplied filename or extension is not present in the MIME
  /// database. Carries the normalised extension so callers can render
  /// "we don't recognise the `.xyz` extension" without re-parsing.
  UnknownExtension(String)
  /// The input was empty: a zero-byte `BitArray`, an empty extension
  /// string, or a filename whose path component carries no usable
  /// extension. Distinguished from `NoMatch` so callers can render
  /// "you didn't give us anything to look at" differently from "we
  /// looked and didn't find a match".
  EmptyInput
  /// The reader returned an error before any bytes could be inspected.
  ReaderError(read_error)
}

/// Convenience alias for the non-reader detection error shape:
/// `SimpleDetectionError = DetectionError(Nil)`. Use this name when
/// `detect_strict` and the other non-reader functions appear in
/// caller signatures — the `Nil` slot is structurally unreachable
/// for code that does not use the `Reader` family, so naming it
/// explicitly at every call site is noise. Reader callers continue
/// to use `DetectionError(read_error)` directly.
pub type SimpleDetectionError =
  DetectionError(Nil)

/// A callback that reads up to the requested number of bytes from an
/// input source. Returns `Ok(bits)` with the bytes actually read, or
/// `Error(reason)` if the read fails. A reader that returns fewer bytes
/// than requested signals end-of-input.
///
/// The error type is generic so JS-side readers (FileReader,
/// ReadableStream) and BEAM-side readers (file handles, HTTP clients)
/// can preserve their richer error shapes through `detect_reader_strict`.
pub type Reader(read_error) =
  fn(Int) -> Result(BitArray, read_error)

/// Fallback `MimeType` returned by lenient detection / lookup helpers
/// when no more specific answer is available. Equivalent to
/// `application/octet-stream` with no parameters.
pub const default_mime_type: MimeType = MimeType(
  essence: "application/octet-stream",
  parameters: [],
)

/// Default upper bound on the number of leading bytes inspected by
/// `detect` and `detect_strict`.
///
/// 3072 bytes is large enough for every signature this library ships
/// (the largest fixed-offset check is `application/x-tar` at offset
/// 257, plus envelope formats like ZIP central-directory inspection
/// reach into the first few KB) and matches the default used by Go's
/// `gabriel-vasile/mimetype` library. Pass an explicit limit via
/// `detect_with_limit` / `detect_with_limit_strict` to override.
pub const default_detection_limit = 3072

// ---------------------------------------------------------------------------
// Construction and serialisation
// ---------------------------------------------------------------------------

/// Parse a MIME type string into a `MimeType` value.
///
/// The essence (`type/subtype`) is trimmed and lowercased, and any
/// `; key=value` parameters are parsed and stored on the value so
/// later accessors don't have to re-parse. Returns:
///
/// - `Error(EmptyMimeType)` for empty / whitespace-only input.
/// - `Error(InvalidMimeType(original))` when the essence does not
///   match the `type/subtype` shape required by RFC 6838.
/// - `Error(InvalidParameterName(name))` when a parameter name is not
///   a valid RFC 9110 §5.6.6 / RFC 7230 §3.2.6 `token` (most often
///   because it contains whitespace or another non-tchar codepoint).
/// - `Error(InvalidParameterValue(parameter, byte))` when a parameter
///   value contains an ASCII control byte that is valid in neither
///   `token` nor `quoted-string` per RFC 7231 §3.1.1.1 (0x00-0x1F
///   except HTAB `0x09`, and DEL `0x7F`). These bytes would produce
///   a malformed `Content-Type` header on the wire.
pub fn parse(input: String) -> Result(MimeType, ParseError) {
  case parse_internal.parse_string(input) {
    Ok(#(essence, parameters)) ->
      Ok(MimeType(essence: essence, parameters: parameters))
    Error(parse_internal.Empty) -> Error(EmptyMimeType)
    Error(parse_internal.InvalidEssence(original)) ->
      Error(InvalidMimeType(original))
    Error(parse_internal.InvalidParameterName(name:)) ->
      Error(InvalidParameterName(name: name))
    Error(parse_internal.InvalidParameterValue(parameter:, byte:)) ->
      Error(InvalidParameterValue(parameter: parameter, byte: byte))
  }
}

/// Serialise a `MimeType` back to its wire-format string. The output
/// always normalises whitespace ("`type/subtype; key=value`" with a
/// single space after each semicolon) and is round-trippable through
/// `parse/1`.
///
/// Parameter values that are not a valid `token` per RFC 7230 §3.2.6
/// (including the empty string and any value containing whitespace,
/// `;`, `,`, `"`, etc.) are wrapped in a quoted-string with inner
/// `"` and `\` backslash-escaped. Token-valid values pass through
/// unchanged so the common case (`charset=utf-8`, `boundary=abc123`)
/// stays unquoted.
pub fn to_string(mt: MimeType) -> String {
  parse_internal.serialise(mt.essence, mt.parameters)
}

// ---------------------------------------------------------------------------
// Accessors
// ---------------------------------------------------------------------------

/// Return the bare essence (`type/subtype`) of a `MimeType`, with all
/// parameters stripped. The result is already trimmed and lowercased.
pub fn essence_of(mt: MimeType) -> String {
  mt.essence
}

/// Look up a parameter value on a `MimeType`. Returns `None` for
/// missing parameters and for an empty / whitespace-only `key`.
///
/// ## Parameter handling
///
/// - **Duplicate names**: when the input string carries the same
///   parameter name twice (e.g. `text/plain; charset=utf-8; charset=ascii`),
///   the *first* occurrence wins. RFC 7231 does not define a winner,
///   so this lookup commits to a deterministic rule rather than letting
///   the result depend on `parse/1`'s storage order.
/// - **Case-insensitive lookup**: both the `key` argument and the
///   stored parameter names are normalised to lowercase, so
///   `parameter_of(parse("text/plain; CHARSET=UTF-8"), "CharSet")`
///   returns `Some("UTF-8")`. Names are case-insensitive per the spec;
///   values are returned with their original case preserved.
/// - **Whitespace on values**: surrounding whitespace is stripped from
///   the stored value (`text/plain; charset=  utf-8` → `Some("utf-8")`).
///   Whitespace *inside* a quoted-string is part of the value and is
///   preserved verbatim (`text/plain; description="hello world"` →
///   `Some("hello world")`).
/// - **Empty values**: an empty parameter value (e.g.
///   `text/plain; charset=`) is collapsed to `None`. RFC 9110 / RFC 7230
///   define `parameter-value` as `token / quoted-string`, both of which
///   require at least one octet, so `Some("")` would imply a value that
///   the grammar does not actually permit. Callers reading `Some(_)` can
///   then assume the wrapped string carries information.
pub fn parameter_of(mt: MimeType, key: String) -> Option(String) {
  let requested = key |> string.trim |> string.lowercase
  use <- bool.lazy_guard(when: requested == "", return: fn() { None })
  mt.parameters
  |> list.find_map(fn(p) {
    let #(name, value) = p
    case name == requested && value != "" {
      True -> Ok(value)
      False -> Error(Nil)
    }
  })
  |> option.from_result
}

/// Return the `charset` parameter from a `MimeType` (lowercased), if
/// present. Equivalent to `parameter_of(mt, "charset")` followed by
/// `string.lowercase`.
pub fn charset_of_type(mt: MimeType) -> Option(String) {
  case parameter_of(mt, "charset") {
    Some(value) -> Some(string.lowercase(value))
    None -> None
  }
}

// ---------------------------------------------------------------------------
// Family predicates
// ---------------------------------------------------------------------------

/// Return `True` when the MIME type's top-level media type is `image`.
pub fn is_image(mt: MimeType) -> Bool {
  predicates_internal.is_image_essence(mt.essence)
}

/// Return `True` when the MIME type's top-level media type is `text`.
pub fn is_text(mt: MimeType) -> Bool {
  predicates_internal.is_text_essence(mt.essence)
}

/// Return `True` when the MIME type's top-level media type is `audio`.
pub fn is_audio(mt: MimeType) -> Bool {
  predicates_internal.is_audio_essence(mt.essence)
}

/// Return `True` when the MIME type's top-level media type is `video`.
pub fn is_video(mt: MimeType) -> Bool {
  predicates_internal.is_video_essence(mt.essence)
}

/// Return `True` when `mime` is `parent` or transitively inherits from
/// `parent` in the static subtype tree.
///
/// The relation is reflexive (`is_a(x, x)` is always `True` for any
/// non-empty `x`) and transitive (if `a` inherits from `b` and `b`
/// inherits from `c`, then `is_a(a, c)` is `True`).
pub fn is_a(mime: MimeType, parent: MimeType) -> Bool {
  predicates_internal.is_a(mime.essence, parent.essence)
}

/// Return `True` when `mime` is, or inherits from, `application/zip`.
///
/// Convenience wrapper for `is_a(mime, parse("application/zip"))`.
/// Returns `True` for `.docx` / `.xlsx` / `.epub` / `.apk` and other
/// ZIP-based container formats.
pub fn is_zip_based(mime: MimeType) -> Bool {
  predicates_internal.is_a(mime.essence, "application/zip")
}

/// Return `True` when `mime` is, or inherits from, an XML media type.
///
/// Both `text/xml` and `application/xml` are accepted as XML roots,
/// in line with RFC 7303 which permits both. Returns `True` for
/// `image/svg+xml` and any other `*+xml` types added to the hierarchy.
pub fn is_xml_based(mime: MimeType) -> Bool {
  predicates_internal.is_a(mime.essence, "text/xml")
  || predicates_internal.is_a(mime.essence, "application/xml")
}

/// Return the chain of ancestors of `mime`, ordered from immediate
/// parent to root.
///
/// Empty input or roots return `[]`. The returned list does not
/// include `mime` itself; use `is_a(mime, mime)` (always `True`) if
/// you need reflexive membership.
pub fn ancestors(mime: MimeType) -> List(MimeType) {
  predicates_internal.ancestors(mime.essence)
  |> list.map(from_essence)
}

// ---------------------------------------------------------------------------
// Charset detection from raw bytes
// ---------------------------------------------------------------------------

/// Detect the character encoding (charset) of a `BitArray`.
///
/// Returns `Ok(charset)` when one of the following signals fires
/// (in priority order):
///
///   1. A Unicode BOM (UTF-8 / UTF-16 LE/BE / UTF-32 LE/BE).
///   2. An XML prolog `<?xml ... encoding="..." ?>`.
///   3. An HTML `<meta charset="...">` (or `<meta http-equiv=... content=...>`)
///      tag in the first 1 KB.
///   4. A UTF-8 validity scan: `utf-8` for input that contains valid
///      multi-byte UTF-8 sequences, `us-ascii` for input that is
///      entirely 0x00–0x7F.
///
/// Returns `Error(EmptyInput)` for the zero-byte `BitArray`, and
/// `Error(NoMatch)` for inputs whose encoding cannot be determined
/// (typically non-UTF-8 high-byte content like Latin-1 or Shift_JIS
/// without an in-document declaration). Charset names are returned in
/// lowercase, matching the convention used by IANA's charset registry.
///
/// The result is a charset name (e.g. `"utf-8"`), not a `MimeType`,
/// because the caller typically pairs it with a separately determined
/// media type via `parameter_of` / `charset_of_type` rather than as a
/// standalone MIME value.
pub fn charset_of(bytes: BitArray) -> Result(String, SimpleDetectionError) {
  detect_internal.charset_of(bytes) |> result.map_error(detect_failure_to_error)
}

// ---------------------------------------------------------------------------
// Lookup: extension → MIME
// ---------------------------------------------------------------------------

/// Look up a `MimeType` from a file extension.
///
/// The input may include a leading dot and is normalised to lowercase
/// before lookup. Unknown / empty inputs fall back to
/// `default_mime_type`.
pub fn extension_to_mime_type(extension: String) -> MimeType {
  extension_to_mime_type_strict(extension)
  |> result.unwrap(default_mime_type)
}

/// Look up a `MimeType` from a file extension.
///
/// Returns `Error(EmptyInput)` when the input normalises to the empty
/// string (e.g. `""`, `"."`, `"   "`). Returns
/// `Error(UnknownExtension(ext))` when the normalised extension is
/// not present in the generated database, carrying the lookup key so
/// the caller can render it without re-parsing.
pub fn extension_to_mime_type_strict(
  extension: String,
) -> Result(MimeType, SimpleDetectionError) {
  let normalized = lookup_internal.normalize_extension(extension)
  use <- bool.guard(when: normalized == "", return: Error(EmptyInput))
  case lookup_internal.essence_for_extension(normalized) {
    Ok(s) -> Ok(from_internal(s))
    Error(Nil) -> Error(UnknownExtension(normalized))
  }
}

// ---------------------------------------------------------------------------
// Lookup: MIME → extensions
// ---------------------------------------------------------------------------

/// Return all known extensions for a `MimeType`. Unknown MIME types
/// return the empty list.
pub fn mime_type_to_extensions(mt: MimeType) -> List(String) {
  mime_type_to_extensions_strict(mt) |> result.unwrap([])
}

/// Return all known extensions for a `MimeType`.
///
/// Strict variant; returns `Error(Nil)` when the essence is not in the
/// generated database.
pub fn mime_type_to_extensions_strict(mt: MimeType) -> Result(List(String), Nil) {
  lookup_internal.extensions_for_essence(mt.essence)
}

// ---------------------------------------------------------------------------
// Lookup: filename → MIME
// ---------------------------------------------------------------------------

/// Look up a `MimeType` from the last extension component of a path
/// or filename.
///
/// Query strings and URL fragments are ignored. Hidden files without
/// a real extension, such as `.gitignore`, fall back to
/// `default_mime_type`.
pub fn filename_to_mime_type(path: String) -> MimeType {
  filename_to_mime_type_strict(path) |> result.unwrap(default_mime_type)
}

/// Look up a `MimeType` from the last extension component of a path
/// or filename.
///
/// Returns `Error(EmptyInput)` when the path does not contain a
/// usable extension (e.g. `"README"`, `".gitignore"`, `""`). Returns
/// `Error(UnknownExtension(ext))` when the path has an extension but
/// the normalised extension is not in the database.
pub fn filename_to_mime_type_strict(
  path: String,
) -> Result(MimeType, SimpleDetectionError) {
  case lookup_internal.extension_from_filename(path) {
    Some(extension) -> extension_to_mime_type_strict(extension)
    None -> Error(EmptyInput)
  }
}

// ---------------------------------------------------------------------------
// Detection: bytes → MIME
// ---------------------------------------------------------------------------

/// Detect a `MimeType` from the leading bytes of a blob.
///
/// Returns `default_mime_type` (`application/octet-stream`) when the
/// input carries no recognisable magic bytes — including the empty
/// `BitArray`. The fallback is silent: a caller that needs to
/// distinguish "no signature matched" from "signature matched but
/// produced `application/octet-stream`" should use `detect_strict/1`,
/// which returns `Error(EmptyInput)` for the zero-byte input and
/// `Error(NoMatch)` for the no-match case.
pub fn detect(bytes: BitArray) -> MimeType {
  detect_with_limit(bytes, default_detection_limit)
}

/// Detect a `MimeType` from the leading bytes of a blob.
///
/// Returns `Error(EmptyInput)` for the zero-byte `BitArray`, and
/// `Error(NoMatch)` when no supported magic-number signature matches
/// non-empty input. Prefer this variant when the
/// `application/octet-stream` fallback would be ambiguous; use
/// `detect/1` when an unconditional `MimeType` is more convenient.
pub fn detect_strict(bytes: BitArray) -> Result(MimeType, SimpleDetectionError) {
  detect_with_limit_strict(bytes, default_detection_limit)
}

/// Detect a `MimeType` from the leading bytes of a blob, examining
/// at most `limit` bytes from the start of the input.
///
/// A non-positive `limit` is treated as zero, in which case no
/// signature can match and `default_mime_type` is returned. Limits
/// larger than the input are clamped to the input length.
pub fn detect_with_limit(bytes: BitArray, limit: Int) -> MimeType {
  detect_with_limit_strict(bytes, limit) |> result.unwrap(default_mime_type)
}

/// Detect a `MimeType` from at most `limit` leading bytes.
///
/// Strict variant; returns `Error(EmptyInput)` for the zero-byte
/// `BitArray` and `Error(NoMatch)` when no supported signature
/// matches within the limit.
pub fn detect_with_limit_strict(
  bytes: BitArray,
  limit: Int,
) -> Result(MimeType, SimpleDetectionError) {
  detect_internal.detect_essence_with_limit(bytes, limit)
  |> result.map(from_internal)
  |> result.map_error(detect_failure_to_error)
}

/// Detect a `MimeType` from a genuine binary or structural signature
/// only.
///
/// Like `detect_strict` but excludes the printable-ASCII heuristic
/// that otherwise classifies every plain-ASCII payload as
/// `text/plain`. Returns `Ok(mime_type)` for byte magic numbers (PNG,
/// JPEG, ZIP, `text/plain; charset=utf-*` BOMs, ...) and structural
/// sniffs that inspect bytes (JSON, HTML, XML, SVG). Returns
/// `Error(EmptyInput)` for the zero-byte `BitArray` and
/// `Error(NoMatch)` for arbitrary printable-ASCII text — letting the
/// caller defer to a stronger out-of-band hint such as a filename
/// extension.
pub fn detect_signature_only(
  bytes: BitArray,
) -> Result(MimeType, SimpleDetectionError) {
  detect_signature_only_with_limit(bytes, default_detection_limit)
}

/// `detect_signature_only` with an explicit byte budget.
pub fn detect_signature_only_with_limit(
  bytes: BitArray,
  limit: Int,
) -> Result(MimeType, SimpleDetectionError) {
  detect_internal.detect_signature_only_with_limit(bytes, limit)
  |> result.map(from_internal)
  |> result.map_error(detect_failure_to_error)
}

/// Detect a `MimeType` by pulling at most `limit` leading bytes
/// through a caller-supplied reader.
///
/// The reader is called once with `limit` as the requested byte
/// count. If the reader returns an error, `default_mime_type` is
/// returned.
pub fn detect_reader(read: Reader(read_error), limit: Int) -> MimeType {
  detect_reader_strict(read, limit) |> result.unwrap(default_mime_type)
}

/// Detect a `MimeType` by pulling at most `limit` leading bytes
/// through a caller-supplied reader.
///
/// Returns `Error(ReaderError(e))` when the reader itself failed, or
/// `Error(NoMatch)` when the reader produced bytes but no supported
/// magic-number signature matched within them. The reader's own
/// error type flows through `ReaderError(_)` unchanged so callers
/// can render it however they wish.
pub fn detect_reader_strict(
  read: Reader(read_error),
  limit: Int,
) -> Result(MimeType, DetectionError(read_error)) {
  detect_internal.detect_essence_via_reader(read, limit)
  |> result.map(from_internal)
  |> result.map_error(detect_failure_to_error)
}

/// Detect a `MimeType` from bytes, consulting an explicit extension
/// hint when the byte signature alone is not specific enough.
///
/// Genuine binary signatures (PNG, JPEG, ZIP, BOM-tagged text, ...)
/// and structural sniffs (JSON, HTML, XML, SVG) win over the
/// extension hint. The extension takes priority when the only thing
/// the byte side could say was the printable-ASCII fallback
/// `text/plain` — a `.csv` extension is a stronger signal for
/// plain-ASCII payloads than the byte-level fact "this looks
/// textish". The printable-ASCII fallback is still used as a last
/// resort when neither the byte signature nor the extension is
/// recognisable.
pub fn detect_with_extension(bytes: BitArray, extension: String) -> MimeType {
  detect_with_extension_strict(bytes, extension)
  |> result.unwrap(default_mime_type)
}

/// Detect a `MimeType` from bytes, consulting an explicit extension
/// hint when the byte signature alone is not specific enough.
///
/// Returns `Error(EmptyInput)` only when both the bytes and the
/// extension carry no information (zero-byte input *and* an
/// extension that normalises to empty). Returns `Error(NoMatch)`
/// when neither the byte signature, the normalised extension, nor
/// the printable-ASCII fallback succeed.
pub fn detect_with_extension_strict(
  bytes: BitArray,
  extension: String,
) -> Result(MimeType, SimpleDetectionError) {
  detect_signature_only(bytes)
  |> result.lazy_or(fn() { extension_to_mime_type_strict(extension) })
  |> result.lazy_or(fn() { detect_strict(bytes) })
}

/// Detect a `MimeType` from bytes, consulting the filename extension
/// when the byte signature alone is not specific enough.
///
/// Genuine binary signatures (PNG, JPEG, ZIP, BOM-tagged text, ...)
/// and structural sniffs (JSON, HTML, XML, SVG) win over the
/// filename. The filename takes priority when the only thing the
/// byte side could say was the printable-ASCII fallback `text/plain`
/// — a `report.csv` filename is a stronger signal for plain-ASCII
/// payloads than the byte-level fact "this looks textish". The
/// printable-ASCII fallback is still used as a last resort when
/// neither the byte signature nor the filename's extension is
/// recognisable.
pub fn detect_with_filename(bytes: BitArray, filename: String) -> MimeType {
  detect_with_filename_strict(bytes, filename)
  |> result.unwrap(default_mime_type)
}

/// Detect a `MimeType` from bytes, consulting the filename extension
/// when the byte signature alone is not specific enough.
///
/// Returns `Error(EmptyInput)` when the bytes are empty and the
/// filename has no usable extension. Returns `Error(NoMatch)` when
/// neither the byte signature, the filename extension, nor the
/// printable-ASCII fallback succeed.
pub fn detect_with_filename_strict(
  bytes: BitArray,
  filename: String,
) -> Result(MimeType, SimpleDetectionError) {
  detect_signature_only(bytes)
  |> result.lazy_or(fn() { filename_to_mime_type_strict(filename) })
  |> result.lazy_or(fn() { detect_strict(bytes) })
}

// ---------------------------------------------------------------------------
// Internal helpers (facade-only, depend on the opaque MimeType)
// ---------------------------------------------------------------------------

/// Build a `MimeType` from a string produced by an internal source
/// (the magic table, the extension DB, ...) that is expected to be
/// well-formed. Falls back to a single-essence record if `parse/1`
/// rejects the input — this should only happen if the data tables
/// drift, in which case returning a `MimeType` with the raw essence
/// is more useful than panicking at a detection site.
fn from_internal(s: String) -> MimeType {
  case parse_internal.parse_string(s) {
    Ok(#(essence, parameters)) ->
      MimeType(essence: essence, parameters: parameters)
    Error(parse_internal.Empty) ->
      MimeType(essence: s |> string.trim |> string.lowercase, parameters: [])
    Error(parse_internal.InvalidEssence(_)) ->
      MimeType(essence: s |> string.trim |> string.lowercase, parameters: [])
    // Internal sources (the magic table, the extension DB) never
    // include non-token bytes in parameter names or values; falling
    // back to the bare essence here is the conservative path if the
    // data tables ever drift.
    Error(parse_internal.InvalidParameterName(_)) ->
      MimeType(essence: s |> string.trim |> string.lowercase, parameters: [])
    Error(parse_internal.InvalidParameterValue(_, _)) ->
      MimeType(essence: s |> string.trim |> string.lowercase, parameters: [])
  }
}

/// Build a `MimeType` carrying just an essence (no parameters). Used
/// by `ancestors` to rebuild parent values from the static hierarchy
/// table, which only stores essences.
fn from_essence(essence_value: String) -> MimeType {
  MimeType(essence: essence_value, parameters: [])
}

/// Translate an `internal/detect` failure into the public
/// `DetectionError` shape.
fn detect_failure_to_error(
  failure: detect_internal.DetectFailure(read_error),
) -> DetectionError(read_error) {
  case failure {
    detect_internal.Empty -> EmptyInput
    detect_internal.NoSignatureMatch -> NoMatch
    detect_internal.ReadFailed(e) -> ReaderError(e)
  }
}
