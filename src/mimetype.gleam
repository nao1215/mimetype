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

import gleam/bit_array
import gleam/bool
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import mimetype/internal/charset as charset_internal
import mimetype/internal/db
import mimetype/internal/hierarchy
import mimetype/internal/magic

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
/// a reader use `DetectionError(Nil)`.
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
/// later accessors don't have to re-parse. Returns
/// `Error(EmptyMimeType)` for empty / whitespace-only input and
/// `Error(InvalidMimeType(original))` when the essence does not have
/// the `type/subtype` shape required by RFC 6838.
pub fn parse(input: String) -> Result(MimeType, ParseError) {
  let trimmed = string.trim(input)
  use <- bool.guard(when: trimmed == "", return: Error(EmptyMimeType))
  case string.split(trimmed, on: ";") {
    [] -> Error(EmptyMimeType)
    [head, ..rest] -> {
      let essence_value = head |> string.trim |> string.lowercase
      use <- bool.guard(
        when: !valid_essence(essence_value),
        return: Error(InvalidMimeType(input)),
      )
      Ok(MimeType(essence: essence_value, parameters: parse_parameters(rest)))
    }
  }
}

/// Serialise a `MimeType` back to its wire-format string. The output
/// always normalises whitespace ("`type/subtype; key=value`" with a
/// single space after each semicolon) and is round-trippable through
/// `parse/1`.
pub fn to_string(mt: MimeType) -> String {
  let MimeType(essence_value, parameters) = mt
  case parameters {
    [] -> essence_value
    _ -> {
      let serialised_parameters =
        parameters
        |> list.map(fn(p) {
          let #(k, v) = p
          k <> "=" <> v
        })
        |> string.join("; ")
      essence_value <> "; " <> serialised_parameters
    }
  }
}

// ---------------------------------------------------------------------------
// Accessors
// ---------------------------------------------------------------------------

/// Return the bare essence (`type/subtype`) of a `MimeType`, with all
/// parameters stripped. The result is already trimmed and lowercased.
pub fn essence_of(mt: MimeType) -> String {
  let MimeType(essence_value, _) = mt
  essence_value
}

/// Look up a parameter value on a `MimeType`. Returns `None` for
/// missing parameters and for an empty / whitespace-only `key`.
/// Parameter names are matched case-insensitively; values are
/// returned with surrounding whitespace stripped but case preserved.
pub fn parameter_of(mt: MimeType, key: String) -> Option(String) {
  let requested = key |> string.trim |> string.lowercase
  use <- bool.lazy_guard(when: requested == "", return: fn() { None })
  let MimeType(_, parameters) = mt
  parameters
  |> list.find_map(fn(p) {
    let #(name, value) = p
    case name == requested {
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
  string.starts_with(essence_of(mt), "image/")
}

/// Return `True` when the MIME type's top-level media type is `text`.
pub fn is_text(mt: MimeType) -> Bool {
  string.starts_with(essence_of(mt), "text/")
}

/// Return `True` when the MIME type's top-level media type is `audio`.
pub fn is_audio(mt: MimeType) -> Bool {
  string.starts_with(essence_of(mt), "audio/")
}

/// Return `True` when the MIME type's top-level media type is `video`.
pub fn is_video(mt: MimeType) -> Bool {
  string.starts_with(essence_of(mt), "video/")
}

/// Return `True` when `mime` is `parent` or transitively inherits from
/// `parent` in the static subtype tree.
///
/// The relation is reflexive (`is_a(x, x)` is always `True` for any
/// non-empty `x`) and transitive (if `a` inherits from `b` and `b`
/// inherits from `c`, then `is_a(a, c)` is `True`).
pub fn is_a(mime: MimeType, parent: MimeType) -> Bool {
  let mime_essence = essence_of(mime)
  let parent_essence = essence_of(parent)
  use <- bool.guard(when: mime_essence == "", return: False)
  use <- bool.guard(when: parent_essence == "", return: False)
  is_a_loop(mime_essence, parent_essence)
}

/// Return `True` when `mime` is, or inherits from, `application/zip`.
///
/// Convenience wrapper for `is_a(mime, parse("application/zip"))`.
/// Returns `True` for `.docx` / `.xlsx` / `.epub` / `.apk` and other
/// ZIP-based container formats.
pub fn is_zip_based(mime: MimeType) -> Bool {
  is_a_loop(essence_of(mime), "application/zip")
}

/// Return `True` when `mime` is, or inherits from, an XML media type.
///
/// Both `text/xml` and `application/xml` are accepted as XML roots,
/// in line with RFC 7303 which permits both. Returns `True` for
/// `image/svg+xml` and any other `*+xml` types added to the hierarchy.
pub fn is_xml_based(mime: MimeType) -> Bool {
  let mime_essence = essence_of(mime)
  is_a_loop(mime_essence, "text/xml")
  || is_a_loop(mime_essence, "application/xml")
}

/// Return the chain of ancestors of `mime`, ordered from immediate
/// parent to root.
///
/// Empty input or roots return `[]`. The returned list does not
/// include `mime` itself; use `is_a(mime, mime)` (always `True`) if
/// you need reflexive membership.
pub fn ancestors(mime: MimeType) -> List(MimeType) {
  let mime_essence = essence_of(mime)
  use <- bool.guard(when: mime_essence == "", return: [])
  ancestors_loop(mime_essence, [])
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
pub fn charset_of(bytes: BitArray) -> Result(String, DetectionError(Nil)) {
  use <- bool.guard(
    when: bit_array.byte_size(bytes) == 0,
    return: Error(EmptyInput),
  )
  case charset_internal.detect(bytes) {
    Ok(charset) -> Ok(charset)
    Error(Nil) -> Error(NoMatch)
  }
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
  case extension_to_mime_type_strict(extension) {
    Ok(mt) -> mt
    Error(NoMatch) -> default_mime_type
    Error(UnknownExtension(_)) -> default_mime_type
    Error(EmptyInput) -> default_mime_type
    Error(ReaderError(_)) -> default_mime_type
  }
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
) -> Result(MimeType, DetectionError(Nil)) {
  let normalized = normalize_extension(extension)
  use <- bool.guard(when: normalized == "", return: Error(EmptyInput))
  case db.extension_to_mime_type(normalized) {
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
  case mime_type_to_extensions_strict(mt) {
    Ok(extensions) -> extensions
    Error(Nil) -> []
  }
}

/// Return all known extensions for a `MimeType`.
///
/// Strict variant; returns `Error(Nil)` when the essence is not in the
/// generated database.
pub fn mime_type_to_extensions_strict(mt: MimeType) -> Result(List(String), Nil) {
  db.mime_type_to_extensions(essence_of(mt))
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
  case filename_to_mime_type_strict(path) {
    Ok(mt) -> mt
    Error(NoMatch) -> default_mime_type
    Error(UnknownExtension(_)) -> default_mime_type
    Error(EmptyInput) -> default_mime_type
    Error(ReaderError(_)) -> default_mime_type
  }
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
) -> Result(MimeType, DetectionError(Nil)) {
  case extension_from_filename(path) {
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
pub fn detect_strict(bytes: BitArray) -> Result(MimeType, DetectionError(Nil)) {
  detect_with_limit_strict(bytes, default_detection_limit)
}

/// Detect a `MimeType` from the leading bytes of a blob, examining
/// at most `limit` bytes from the start of the input.
///
/// A non-positive `limit` is treated as zero, in which case no
/// signature can match and `default_mime_type` is returned. Limits
/// larger than the input are clamped to the input length.
pub fn detect_with_limit(bytes: BitArray, limit: Int) -> MimeType {
  case detect_with_limit_strict(bytes, limit) {
    Ok(mt) -> mt
    Error(NoMatch) -> default_mime_type
    Error(UnknownExtension(_)) -> default_mime_type
    Error(EmptyInput) -> default_mime_type
    Error(ReaderError(_)) -> default_mime_type
  }
}

/// Detect a `MimeType` from at most `limit` leading bytes.
///
/// Strict variant; returns `Error(EmptyInput)` for the zero-byte
/// `BitArray` and `Error(NoMatch)` when no supported signature
/// matches within the limit.
pub fn detect_with_limit_strict(
  bytes: BitArray,
  limit: Int,
) -> Result(MimeType, DetectionError(Nil)) {
  use <- bool.guard(
    when: bit_array.byte_size(bytes) == 0,
    return: Error(EmptyInput),
  )
  case magic.detect(truncate_to_limit(bytes, limit)) {
    Some(s) -> Ok(from_internal(s))
    None -> Error(NoMatch)
  }
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
) -> Result(MimeType, DetectionError(Nil)) {
  detect_signature_only_with_limit(bytes, default_detection_limit)
}

/// `detect_signature_only` with an explicit byte budget.
pub fn detect_signature_only_with_limit(
  bytes: BitArray,
  limit: Int,
) -> Result(MimeType, DetectionError(Nil)) {
  use <- bool.guard(
    when: bit_array.byte_size(bytes) == 0,
    return: Error(EmptyInput),
  )
  case magic.detect_signature(truncate_to_limit(bytes, limit)) {
    Some(s) -> Ok(from_internal(s))
    None -> Error(NoMatch)
  }
}

/// Detect a `MimeType` by pulling at most `limit` leading bytes
/// through a caller-supplied reader.
///
/// The reader is called once with `limit` as the requested byte
/// count. If the reader returns an error, `default_mime_type` is
/// returned.
pub fn detect_reader(read: Reader(read_error), limit: Int) -> MimeType {
  case detect_reader_strict(read, limit) {
    Ok(mt) -> mt
    Error(NoMatch) -> default_mime_type
    Error(UnknownExtension(_)) -> default_mime_type
    Error(EmptyInput) -> default_mime_type
    Error(ReaderError(_)) -> default_mime_type
  }
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
  let safe_limit = case limit < 1 {
    True -> 0
    False -> limit
  }
  case read(safe_limit) {
    Ok(bytes) ->
      case detect_with_limit_strict(bytes, safe_limit) {
        Ok(mt) -> Ok(mt)
        Error(EmptyInput) -> Error(EmptyInput)
        Error(NoMatch) -> Error(NoMatch)
        Error(UnknownExtension(extension)) -> Error(UnknownExtension(extension))
        // Unreachable: detect_with_limit_strict never produces ReaderError.
        Error(ReaderError(_)) -> Error(NoMatch)
      }
    Error(read_error) -> Error(ReaderError(read_error))
  }
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
  case detect_with_extension_strict(bytes, extension) {
    Ok(mt) -> mt
    Error(NoMatch) -> default_mime_type
    Error(UnknownExtension(_)) -> default_mime_type
    Error(EmptyInput) -> default_mime_type
    Error(ReaderError(_)) -> default_mime_type
  }
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
) -> Result(MimeType, DetectionError(Nil)) {
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
  case detect_with_filename_strict(bytes, filename) {
    Ok(mt) -> mt
    Error(NoMatch) -> default_mime_type
    Error(UnknownExtension(_)) -> default_mime_type
    Error(EmptyInput) -> default_mime_type
    Error(ReaderError(_)) -> default_mime_type
  }
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
) -> Result(MimeType, DetectionError(Nil)) {
  detect_signature_only(bytes)
  |> result.lazy_or(fn() { filename_to_mime_type_strict(filename) })
  |> result.lazy_or(fn() { detect_strict(bytes) })
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

fn valid_essence(essence: String) -> Bool {
  case string.split_once(essence, on: "/") {
    Ok(#(t, sub)) -> t != "" && sub != "" && !string.contains(sub, "/")
    Error(Nil) -> False
  }
}

fn parse_parameters(segments: List(String)) -> List(#(String, String)) {
  segments
  |> list.filter_map(fn(seg) {
    case string.split_once(seg, on: "=") {
      Ok(#(name, value)) -> {
        let normalized_name = name |> string.trim |> string.lowercase
        let normalized_value = value |> string.trim |> unquote_value
        case normalized_name {
          "" -> Error(Nil)
          _ -> Ok(#(normalized_name, normalized_value))
        }
      }
      Error(Nil) -> Error(Nil)
    }
  })
}

/// Unwrap a parameter value from RFC 7230 §3.2.6 quoted-string form.
///
/// If `value` is delimited by surrounding `"`, strip them and decode any
/// backslash escapes inside (`\X` → `X`). Values that are not delimited
/// (token form per RFC 7230 §3.2.6) pass through unchanged. Malformed
/// inputs — a leading `"` without a matching trailing `"`, or a trailing
/// `\` with nothing after it — also pass through unchanged so the parser
/// remains tolerant of off-spec wire input.
fn unquote_value(value: String) -> String {
  use <- bool.guard(
    when: !{ string.starts_with(value, "\"") && string.ends_with(value, "\"") },
    return: value,
  )
  // Reject the lone `"` case (length 1: starts AND ends match the
  // same character, so the slice is empty but we'd otherwise
  // discard the original character).
  use <- bool.guard(when: string.length(value) < 2, return: value)
  let inner = value |> string.drop_start(1) |> string.drop_end(1)
  unescape_quoted(inner, "")
}

fn unescape_quoted(remaining: String, acc: String) -> String {
  case string.pop_grapheme(remaining) {
    Error(Nil) -> acc
    Ok(#("\\", rest)) ->
      case string.pop_grapheme(rest) {
        Ok(#(escaped, after)) -> unescape_quoted(after, acc <> escaped)
        // Trailing lone backslash: keep it as-is.
        Error(Nil) -> acc <> "\\"
      }
    Ok(#(other, rest)) -> unescape_quoted(rest, acc <> other)
  }
}

/// Build a `MimeType` from a string produced by an internal source
/// (the magic table, the extension DB, ...) that is expected to be
/// well-formed. Falls back to a single-essence record if `parse/1`
/// rejects the input — this should only happen if the data tables
/// drift, in which case returning a `MimeType` with the raw essence
/// is more useful than panicking at a detection site.
fn from_internal(s: String) -> MimeType {
  case parse(s) {
    Ok(mt) -> mt
    Error(EmptyMimeType) ->
      MimeType(essence: s |> string.trim |> string.lowercase, parameters: [])
    Error(InvalidMimeType(_)) ->
      MimeType(essence: s |> string.trim |> string.lowercase, parameters: [])
  }
}

/// Build a `MimeType` carrying just an essence (no parameters). Used
/// by `ancestors` to rebuild parent values from the static hierarchy
/// table, which only stores essences.
fn from_essence(essence_value: String) -> MimeType {
  MimeType(essence: essence_value, parameters: [])
}

fn is_a_loop(mime: String, parent: String) -> Bool {
  use <- bool.lazy_guard(when: mime == parent, return: fn() { True })
  case hierarchy.parent_of(mime) {
    Ok(next) -> is_a_loop(next, parent)
    Error(Nil) -> False
  }
}

fn ancestors_loop(mime: String, acc: List(MimeType)) -> List(MimeType) {
  case hierarchy.parent_of(mime) {
    Ok(parent) -> ancestors_loop(parent, [from_essence(parent), ..acc])
    Error(Nil) -> list.reverse(acc)
  }
}

fn truncate_to_limit(bytes: BitArray, limit: Int) -> BitArray {
  let size = bit_array.byte_size(bytes)
  let safe_limit = case limit < 0, limit > size {
    True, _ -> 0
    False, True -> size
    False, False -> limit
  }
  bit_array.slice(bytes, 0, safe_limit) |> result.unwrap(<<>>)
}

fn normalize_extension(extension: String) -> String {
  extension |> string.trim |> strip_leading_dots |> string.lowercase
}

fn strip_leading_dots(value: String) -> String {
  use <- bool.lazy_guard(when: string.starts_with(value, "."), return: fn() {
    strip_leading_dots(string.drop_start(value, 1))
  })
  value
}

fn extension_from_filename(path: String) -> Option(String) {
  let name = basename(path)
  case list.reverse(string.split(name, ".")) {
    [] -> None
    [_single] -> None
    ["", ..] -> None
    [extension, ..rest] ->
      case rest {
        [""] -> None
        _ -> Some(normalize_extension(extension))
      }
  }
}

fn basename(path: String) -> String {
  let without_fragment = split_head(path, on: "#")
  let without_query = split_head(without_fragment, on: "?")
  let normalized = string.replace(without_query, "\\", "/")
  case list.reverse(string.split(normalized, "/")) {
    [name, ..] -> name
    [] -> normalized
  }
}

fn split_head(value: String, on marker: String) -> String {
  case string.split_once(value, on: marker) {
    Ok(#(head, _)) -> head
    Error(Nil) -> value
  }
}
