//// Look up MIME types by file extension and detect them from the leading
//// bytes of a file.
////
//// Every lookup and detection function returns a `MimeType`. Build one
//// from a string with `parse`, and turn it back into a header value with
//// `to_string`. Content negotiation for `Accept` headers lives in
//// `mimetype/accept`.

import gleam/bit_array
import gleam/bool
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import mimetype/internal/charset as charset_internal
import mimetype/internal/lookup as lookup_internal
import mimetype/internal/magic
import mimetype/internal/parse as parse_internal
import mimetype/internal/predicates as predicates_internal

/// A MIME type such as `text/html; charset=utf-8`.
///
/// The type and subtype are lowercase, and every parameter has a valid
/// name and value. Values come from `parse`, `octet_stream`, `ancestors`
/// and the lookup and detection functions.
pub opaque type MimeType {
  // `essence` is trimmed, lowercased and matches `type/subtype`.
  // Parameter names are lowercased tokens; values hold no control bytes.
  MimeType(essence: String, parameters: List(#(String, String)))
}

/// The reason `parse` or `parse_strict` rejected a string.
pub type ParseError {
  /// The input was empty or only whitespace.
  EmptyMimeType
  /// The part before the first `;` is not a `type/subtype` pair. Holds
  /// the whole input.
  InvalidMimeType(String)
  /// A parameter name is not an HTTP token, for example because it
  /// contains a space.
  InvalidParameterName(name: String)
  /// A parameter value contains a control byte (0x00 to 0x1F other than
  /// tab, or 0x7F). Holds the parameter name and the byte.
  InvalidParameterValue(parameter: String, byte: Int)
  /// A `;`-separated segment is not `name=value`. Only `parse_strict`
  /// returns this.
  MalformedParameter(segment: String)
}

/// `application/octet-stream`, the type for bytes of unknown format.
///
/// Use it as the fallback when a lookup or detection fails:
///
/// ```gleam
/// mimetype.detect(bytes) |> result.unwrap(mimetype.octet_stream)
/// ```
///
pub const octet_stream: MimeType =
  MimeType(essence: "application/octet-stream", parameters: [])

// Detection looks at no more than this many leading bytes. Every
// signature in `internal/magic` fits inside it.
const detection_limit = 3072

// ---------------------------------------------------------------------------
// Parsing and serialising
// ---------------------------------------------------------------------------

/// Parses a MIME type such as a `Content-Type` header value.
///
/// The type and subtype are lowercased and parameter names are
/// lowercased; parameter values keep their case, and quoted values are
/// unquoted. Empty segments such as a trailing `;` are dropped. Use
/// `parse_strict` to reject them instead.
///
/// ## Examples
///
/// ```gleam
/// let assert Ok(html) = mimetype.parse("Text/HTML; Charset=UTF-8")
/// mimetype.to_string(html)
/// // -> "text/html; charset=UTF-8"
/// ```
///
/// ```gleam
/// mimetype.parse("html")
/// // -> Error(InvalidMimeType("html"))
/// ```
///
pub fn parse(input: String) -> Result(MimeType, ParseError) {
  parse_internal.parse_string(input) |> map_parse_result
}

/// Parses a MIME type like `parse`, but returns
/// `Error(MalformedParameter(segment))` for a segment that is not
/// `name=value`, such as a trailing `;` or `;charset`.
///
/// ## Examples
///
/// ```gleam
/// mimetype.parse_strict("text/plain;")
/// // -> Error(MalformedParameter(""))
/// ```
///
pub fn parse_strict(input: String) -> Result(MimeType, ParseError) {
  parse_internal.parse_string_strict(input) |> map_parse_result
}

fn map_parse_result(
  result: Result(
    #(String, List(#(String, String))),
    parse_internal.ParseFailure,
  ),
) -> Result(MimeType, ParseError) {
  case result {
    Ok(#(essence, parameters)) -> Ok(MimeType(essence:, parameters:))
    Error(parse_internal.Empty) -> Error(EmptyMimeType)
    Error(parse_internal.InvalidEssence(original)) ->
      Error(InvalidMimeType(original))
    Error(parse_internal.InvalidParameterName(name:)) ->
      Error(InvalidParameterName(name:))
    Error(parse_internal.InvalidParameterValue(parameter:, byte:)) ->
      Error(InvalidParameterValue(parameter:, byte:))
    Error(parse_internal.MalformedParameter(segment:)) ->
      Error(MalformedParameter(segment:))
  }
}

/// Converts a `MimeType` to a header value.
///
/// Parameters are joined with `"; "`. A value that is not an HTTP token,
/// such as one with a space or an empty value, is written as a quoted
/// string. The result parses back to the same `MimeType`.
///
/// ## Examples
///
/// ```gleam
/// let assert Ok(mime) = mimetype.parse("text/plain;title=\"a b\"")
/// mimetype.to_string(mime)
/// // -> "text/plain; title=\"a b\""
/// ```
///
pub fn to_string(mime: MimeType) -> String {
  parse_internal.serialise(mime.essence, mime.parameters)
}

// ---------------------------------------------------------------------------
// Reading a MIME type
// ---------------------------------------------------------------------------

/// Returns the `type/subtype` part without parameters.
///
/// ## Examples
///
/// ```gleam
/// let assert Ok(html) = mimetype.parse("text/html; charset=utf-8")
/// mimetype.essence(html)
/// // -> "text/html"
/// ```
///
pub fn essence(mime: MimeType) -> String {
  mime.essence
}

/// Returns the value of the named parameter.
///
/// The name is matched without regard to case. If the parameter appears
/// more than once, the first one wins. Returns `Error(Nil)` when the
/// parameter is missing or its value is empty.
///
/// ## Examples
///
/// ```gleam
/// let assert Ok(form) = mimetype.parse("multipart/form-data; boundary=xyz")
/// mimetype.parameter(form, "Boundary")
/// // -> Ok("xyz")
/// ```
///
/// ```gleam
/// mimetype.parameter(form, "charset")
/// // -> Error(Nil)
/// ```
///
pub fn parameter(mime: MimeType, name: String) -> Result(String, Nil) {
  let name = name |> string.trim |> string.lowercase
  use <- bool.guard(when: name == "", return: Error(Nil))
  list.find_map(mime.parameters, fn(parameter) {
    case parameter {
      #(key, value) if key == name && value != "" -> Ok(value)
      _ -> Error(Nil)
    }
  })
}

/// Returns the `charset` parameter, lowercased.
///
/// ## Examples
///
/// ```gleam
/// let assert Ok(html) = mimetype.parse("text/html; charset=UTF-8")
/// mimetype.charset(html)
/// // -> Ok("utf-8")
/// ```
///
pub fn charset(mime: MimeType) -> Result(String, Nil) {
  parameter(mime, "charset") |> result.map(string.lowercase)
}

/// Returns `True` when the top-level type is `image`.
///
pub fn is_image(mime: MimeType) -> Bool {
  predicates_internal.is_image_essence(mime.essence)
}

/// Returns `True` for types whose content is text: every `text/*` type,
/// `application/json`, `application/xml`, `application/javascript`,
/// `application/ecmascript`, `application/sql`, `application/x-sql`, and
/// every type ending in `+json` or `+xml`.
///
/// For a check on the top-level type alone, use
/// `string.starts_with(mimetype.essence(mime), "text/")`.
///
pub fn is_text(mime: MimeType) -> Bool {
  predicates_internal.is_text_essence(mime.essence)
}

/// Returns `True` when the top-level type is `audio`.
///
pub fn is_audio(mime: MimeType) -> Bool {
  predicates_internal.is_audio_essence(mime.essence)
}

/// Returns `True` when the top-level type is `video`.
///
pub fn is_video(mime: MimeType) -> Bool {
  predicates_internal.is_video_essence(mime.essence)
}

/// Returns `True` when `mime` is `parent` or a kind of `parent`.
///
/// Parameters are ignored. The relation comes from a built-in table
/// (`.docx` is a kind of `application/zip`, `image/svg+xml` of
/// `text/xml`) and from the `+xml`, `+json`, `+zip` and `+cbor`
/// suffixes.
///
/// ## Examples
///
/// ```gleam
/// let assert Ok(epub) = mimetype.parse("application/epub+zip")
/// let assert Ok(zip) = mimetype.parse("application/zip")
/// mimetype.is_a(epub, zip)
/// // -> True
/// ```
///
pub fn is_a(mime: MimeType, parent: MimeType) -> Bool {
  predicates_internal.is_a(mime.essence, parent.essence)
}

/// Returns `True` for `application/zip` and the formats stored as ZIP
/// archives, such as `.docx`, `.epub`, `.jar` and `.apk`.
///
pub fn is_zip_based(mime: MimeType) -> Bool {
  predicates_internal.is_a(mime.essence, "application/zip")
}

/// Returns `True` for `text/xml`, `application/xml` and the types built
/// on them, such as `image/svg+xml` and `application/atom+xml`.
///
pub fn is_xml_based(mime: MimeType) -> Bool {
  predicates_internal.is_a(mime.essence, "text/xml")
  || predicates_internal.is_a(mime.essence, "application/xml")
}

/// Returns the types `mime` is a kind of, nearest first. See `is_a`.
///
/// ## Examples
///
/// ```gleam
/// let assert Ok(docx) =
///   mimetype.parse(
///     "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
///   )
/// mimetype.ancestors(docx) |> list.map(mimetype.to_string)
/// // -> ["application/zip"]
/// ```
///
pub fn ancestors(mime: MimeType) -> List(MimeType) {
  predicates_internal.ancestors(mime.essence)
  |> list.map(fn(essence) { MimeType(essence:, parameters: []) })
}

// ---------------------------------------------------------------------------
// Extensions and filenames
// ---------------------------------------------------------------------------

/// Looks up the MIME type for a file extension.
///
/// A leading dot, surrounding whitespace and case are ignored. Returns
/// `Error(Nil)` for an empty or unknown extension. The table comes from
/// `jshttp/mime-db`.
///
/// ## Examples
///
/// ```gleam
/// mimetype.extension_to_mime_type(".JSON") |> result.map(mimetype.to_string)
/// // -> Ok("application/json")
/// ```
///
/// ```gleam
/// mimetype.extension_to_mime_type("nosuch")
/// // -> Error(Nil)
/// ```
///
pub fn extension_to_mime_type(extension: String) -> Result(MimeType, Nil) {
  let extension = lookup_internal.normalize_extension(extension)
  use <- bool.guard(when: extension == "", return: Error(Nil))
  lookup_internal.essence_for_extension(extension) |> result.map(from_table)
}

/// Looks up the MIME type for the last extension in a path or file name.
///
/// Directories, a `?query` and a `#fragment` are ignored, and both `/`
/// and `\` separate directories. Returns `Error(Nil)` when the name has
/// no extension (`README`, `.gitignore`) or the extension is unknown.
///
/// ## Examples
///
/// ```gleam
/// mimetype.filename_to_mime_type("photos/IMG_0001.JPG")
/// |> result.map(mimetype.to_string)
/// // -> Ok("image/jpeg")
/// ```
///
/// ```gleam
/// mimetype.filename_to_mime_type(".gitignore")
/// // -> Error(Nil)
/// ```
///
pub fn filename_to_mime_type(path: String) -> Result(MimeType, Nil) {
  case lookup_internal.extension_from_filename(path) {
    Some(extension) -> extension_to_mime_type(extension)
    None -> Error(Nil)
  }
}

/// Returns the known extensions for a MIME type, without dots. The
/// first one is the usual choice. Parameters are ignored, and an
/// unknown type gives `[]`.
///
/// ## Examples
///
/// ```gleam
/// let assert Ok(jpeg) = mimetype.parse("image/jpeg")
/// mimetype.mime_type_to_extensions(jpeg)
/// // -> ["jpg", "jpeg", "jpe"]
/// ```
///
pub fn mime_type_to_extensions(mime: MimeType) -> List(String) {
  lookup_internal.extensions_for_essence(mime.essence) |> result.unwrap([])
}

// ---------------------------------------------------------------------------
// Detection from bytes
// ---------------------------------------------------------------------------

/// Detects the MIME type from the first bytes of a file.
///
/// Only the first 3072 bytes are read. Input made only of printable
/// ASCII is reported as `text/plain`. Returns `Error(Nil)` for empty
/// input and for bytes that match no signature. The supported formats
/// are listed on the "Supported formats" page.
///
/// ## Examples
///
/// ```gleam
/// mimetype.detect(<<0x89, "PNG":utf8, 0x0D, 0x0A, 0x1A, 0x0A>>)
/// |> result.map(mimetype.to_string)
/// // -> Ok("image/png")
/// ```
///
/// ```gleam
/// mimetype.detect(<<0xFF, 0x00, 0xFE>>)
/// // -> Error(Nil)
/// ```
///
pub fn detect(bytes: BitArray) -> Result(MimeType, Nil) {
  detect_with(bytes, magic.detect)
}

/// Detects the MIME type like `detect`, but returns `Error(Nil)` for
/// plain ASCII text instead of `text/plain`.
///
/// Use it when another hint, such as a file name, should decide what
/// a text file is.
///
/// ## Examples
///
/// ```gleam
/// mimetype.detect_signature_only(<<"a,b\n1,2\n":utf8>>)
/// // -> Error(Nil)
/// ```
///
pub fn detect_signature_only(bytes: BitArray) -> Result(MimeType, Nil) {
  detect_with(bytes, magic.detect_signature)
}

fn detect_with(
  bytes: BitArray,
  detector: fn(BitArray) -> option.Option(String),
) -> Result(MimeType, Nil) {
  use <- bool.guard(when: bytes == <<>>, return: Error(Nil))
  let head = case bit_array.byte_size(bytes) > detection_limit {
    True -> bit_array.slice(bytes, 0, detection_limit) |> result.unwrap(bytes)
    False -> bytes
  }
  head |> detector |> option.to_result(Nil) |> result.map(from_table)
}

/// Detects the MIME type from bytes and a file extension.
///
/// A binary signature (PNG, ZIP, PDF, ...) or a recognised structure
/// (JSON, HTML, XML, SVG) wins over the extension. Otherwise the
/// extension is used when it names a text type (see `is_text`), so CSV
/// data with a `csv` extension is `text/csv`. An extension that names a
/// binary type is used only when the bytes do not look like text, so
/// plain text uploaded as `photo.png` is not reported as an image.
/// Returns `Error(Nil)` when neither the bytes nor the extension give
/// a type.
///
/// ## Examples
///
/// ```gleam
/// mimetype.detect_with_extension(<<"a,b\n1,2\n":utf8>>, "csv")
/// |> result.map(mimetype.to_string)
/// // -> Ok("text/csv")
/// ```
///
/// ```gleam
/// mimetype.detect_with_extension(<<"hello":utf8>>, "png")
/// |> result.map(mimetype.to_string)
/// // -> Ok("text/plain")
/// ```
///
pub fn detect_with_extension(
  bytes: BitArray,
  extension: String,
) -> Result(MimeType, Nil) {
  detect_with_hint(bytes, extension_to_mime_type(extension))
}

/// Detects the MIME type from bytes and a file name, with the same
/// rules as `detect_with_extension`.
///
/// ## Examples
///
/// ```gleam
/// mimetype.detect_with_filename(<<"# Title\n":utf8>>, "notes.md")
/// |> result.map(mimetype.to_string)
/// // -> Ok("text/markdown")
/// ```
///
pub fn detect_with_filename(
  bytes: BitArray,
  filename: String,
) -> Result(MimeType, Nil) {
  detect_with_hint(bytes, filename_to_mime_type(filename))
}

fn detect_with_hint(
  bytes: BitArray,
  hint: Result(MimeType, Nil),
) -> Result(MimeType, Nil) {
  use <- result.lazy_or(detect_signature_only(bytes))
  // Without a signature, the bytes can only say "text/plain". A text
  // hint is more specific, so it wins. A binary hint on text-shaped
  // bytes is not trusted: the extension usually comes from the user.
  case hint {
    Ok(hint) ->
      case is_text(hint) {
        True -> Ok(hint)
        False -> detect(bytes) |> result.or(Ok(hint))
      }
    Error(Nil) -> detect(bytes)
  }
}

/// Detects the character encoding of text.
///
/// The checks run in this order: a byte order mark (UTF-8, UTF-16 and
/// UTF-32), the `encoding` of an XML declaration, an HTML
/// `<meta charset>` in the first 1024 bytes, and last a scan that gives
/// `us-ascii` for 7-bit input and `utf-8` for valid UTF-8. Names are
/// lowercase. Returns `Error(Nil)` for empty input and for anything else,
/// such as Latin-1 or Shift_JIS text without a declaration.
///
/// ## Examples
///
/// ```gleam
/// mimetype.detect_charset(<<"こんにちは":utf8>>)
/// // -> Ok("utf-8")
/// ```
///
/// ```gleam
/// mimetype.detect_charset(<<0x48, 0x69, 0xC0, 0x20>>)
/// // -> Error(Nil)
/// ```
///
pub fn detect_charset(bytes: BitArray) -> Result(String, Nil) {
  use <- bool.guard(when: bytes == <<>>, return: Error(Nil))
  charset_internal.detect(bytes)
}

// Builds a `MimeType` from a string in the extension or signature
// tables. Those strings are well formed, so the fallback branch is only
// reached if the generated tables are broken.
fn from_table(value: String) -> MimeType {
  case parse_internal.parse_string(value) {
    Ok(#(essence, parameters)) -> MimeType(essence:, parameters:)
    Error(parse_internal.Empty)
    | Error(parse_internal.InvalidEssence(_))
    | Error(parse_internal.InvalidParameterName(_))
    | Error(parse_internal.InvalidParameterValue(_, _))
    | Error(parse_internal.MalformedParameter(_)) ->
      MimeType(
        essence: value |> string.trim |> string.lowercase,
        parameters: [],
      )
  }
}
