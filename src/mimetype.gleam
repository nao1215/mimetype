//// MIME type lookup and byte-signature detection for Gleam.
////
//// The public API intentionally separates:
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

/// Fallback MIME type used when neither metadata nor byte signatures
/// provide a more specific answer.
pub const default_mime_type = db.default_mime_type

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

/// Look up a MIME type from a file extension.
///
/// The input may include a leading dot and is normalized to lowercase
/// before lookup. Unknown extensions fall back to
/// `application/octet-stream`.
pub fn extension_to_mime_type(extension: String) -> String {
  // The generated db module expects already-normalized keys.
  case extension_to_mime_type_strict(extension) {
    Ok(mime_type) -> mime_type
    Error(Nil) -> default_mime_type
  }
}

/// Look up a MIME type from a file extension.
///
/// This strict variant returns `Error(Nil)` when the normalized
/// extension is not present in the generated database.
pub fn extension_to_mime_type_strict(extension: String) -> Result(String, Nil) {
  db.extension_to_mime_type(normalize_extension(extension))
}

/// Return all known extensions for a MIME type.
///
/// The input is trimmed, lowercased, and stripped of any MIME
/// parameters (such as `; charset=utf-8`) before lookup. Unknown MIME
/// types return the empty list.
pub fn mime_type_to_extensions(mime_type: String) -> List(String) {
  // The generated db module expects already-normalized keys.
  case mime_type_to_extensions_strict(mime_type) {
    Ok(extensions) -> extensions
    Error(Nil) -> []
  }
}

/// Return all known extensions for a MIME type.
///
/// This strict variant returns `Error(Nil)` when the normalized MIME
/// type is not present in the generated database.
pub fn mime_type_to_extensions_strict(
  mime_type: String,
) -> Result(List(String), Nil) {
  mime_type |> essence |> db.mime_type_to_extensions
}

/// Return the bare MIME type without any parameters.
///
/// This trims surrounding whitespace, lowercases the media type, and
/// strips anything after the first `;`.
pub fn essence(mime_type: String) -> String {
  mime_type
  |> string.trim
  |> string.lowercase
  |> split_head(on: ";")
  |> string.trim
}

/// Return `True` when the MIME type's top-level media type is `image`.
pub fn is_image(mime_type: String) -> Bool {
  string.starts_with(essence(mime_type), "image/")
}

/// Return `True` when the MIME type's top-level media type is `text`.
pub fn is_text(mime_type: String) -> Bool {
  string.starts_with(essence(mime_type), "text/")
}

/// Return `True` when the MIME type's top-level media type is `audio`.
pub fn is_audio(mime_type: String) -> Bool {
  string.starts_with(essence(mime_type), "audio/")
}

/// Return `True` when the MIME type's top-level media type is `video`.
pub fn is_video(mime_type: String) -> Bool {
  string.starts_with(essence(mime_type), "video/")
}

/// Return `True` when `mime` is `parent` or transitively inherits from
/// `parent` in the static subtype tree.
///
/// The relation is reflexive (`is_a(x, x)` is always `True` for any
/// non-empty `x`) and transitive (if `a` inherits from `b` and `b`
/// inherits from `c`, then `is_a(a, c)` is `True`).
///
/// Both arguments are normalized via `essence` so parameters and case
/// differences are ignored.
pub fn is_a(mime: String, parent: String) -> Bool {
  let mime_essence = essence(mime)
  let parent_essence = essence(parent)
  use <- bool.guard(when: mime_essence == "", return: False)
  use <- bool.guard(when: parent_essence == "", return: False)
  is_a_loop(mime_essence, parent_essence)
}

fn is_a_loop(mime: String, parent: String) -> Bool {
  use <- bool.lazy_guard(when: mime == parent, return: fn() { True })
  case hierarchy.parent_of(mime) {
    Ok(next) -> is_a_loop(next, parent)
    Error(Nil) -> False
  }
}

/// Return `True` when `mime` is, or inherits from, `application/zip`.
///
/// Convenience wrapper for `is_a(mime, "application/zip")`. Returns
/// `True` for `.docx` / `.xlsx` / `.epub` / `.apk` and other ZIP-based
/// container formats.
pub fn is_zip_based(mime: String) -> Bool {
  is_a(mime, "application/zip")
}

/// Return `True` when `mime` is, or inherits from, an XML media type.
///
/// Both `text/xml` and `application/xml` are accepted as XML roots, in
/// line with RFC 7303 which permits both. Returns `True` for
/// `image/svg+xml` and any other `*+xml` types added to the hierarchy.
pub fn is_xml_based(mime: String) -> Bool {
  is_a(mime, "text/xml") || is_a(mime, "application/xml")
}

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
/// Returns `Error(Nil)` for inputs whose encoding cannot be determined
/// (typically non-UTF-8 high-byte content like Latin-1 or Shift_JIS
/// without an in-document declaration). Charset names are returned in
/// lowercase, matching the convention used by IANA's charset registry.
pub fn charset_of(bytes: BitArray) -> Result(String, Nil) {
  charset_internal.detect(bytes)
}

/// Return the chain of ancestors of `mime`, ordered from immediate
/// parent to root.
///
/// Empty input or roots return `[]`. The returned list does not include
/// `mime` itself; use `is_a(mime, mime)` (always `True`) if you need
/// reflexive membership.
pub fn ancestors(mime: String) -> List(String) {
  let mime_essence = essence(mime)
  use <- bool.guard(when: mime_essence == "", return: [])
  ancestors_loop(mime_essence, [])
}

fn ancestors_loop(mime: String, acc: List(String)) -> List(String) {
  case hierarchy.parent_of(mime) {
    Ok(parent) -> ancestors_loop(parent, [parent, ..acc])
    Error(Nil) -> list.reverse(acc)
  }
}

/// Look up a parameter value from a MIME type string.
///
/// Parameter names are matched case-insensitively. This returns
/// `Error(Nil)` when the key is empty or the parameter is missing.
pub fn parameter(mime_type: String, key: String) -> Result(String, Nil) {
  let requested = key |> string.trim |> string.lowercase

  use <- bool.guard(when: requested == "", return: Error(Nil))

  case string.split(mime_type, ";") {
    [] -> Error(Nil)
    [_] -> Error(Nil)
    [_essence, ..parameters] -> find_parameter(parameters, requested)
  }
}

/// Return the `charset` parameter from a MIME type string.
///
/// Charset values are normalized to lowercase for convenience.
pub fn charset(mime_type: String) -> Result(String, Nil) {
  case parameter(mime_type, "charset") {
    Ok(value) -> Ok(string.lowercase(value))
    Error(Nil) -> Error(Nil)
  }
}

/// Look up a MIME type from the last extension component of a path or
/// filename.
///
/// Query strings and URL fragments are ignored. Hidden files without a
/// real extension, such as `.gitignore`, fall back to
/// `application/octet-stream`.
pub fn filename_to_mime_type(path: String) -> String {
  case filename_to_mime_type_strict(path) {
    Ok(mime_type) -> mime_type
    Error(Nil) -> default_mime_type
  }
}

/// Look up a MIME type from the last extension component of a path or
/// filename.
///
/// This strict variant returns `Error(Nil)` when the path does not
/// contain a usable extension or the extension is unknown.
pub fn filename_to_mime_type_strict(path: String) -> Result(String, Nil) {
  case extension_from_filename(path) {
    Some(extension) -> extension_to_mime_type_strict(extension)
    None -> Error(Nil)
  }
}

/// Detect a MIME type from the leading bytes of a blob.
///
/// This checks a curated set of common magic-number signatures.
/// Currently supported MIME types are:
/// `application/pdf`, `application/zip`, `application/gzip`,
/// `application/x-bzip2`, `application/x-xz`,
/// `application/x-7z-compressed`, `application/x-rar-compressed`,
/// `application/vnd.ms-cab-compressed`, `application/x-tar`,
/// `application/zstd`, `application/vnd.sqlite3`,
/// `application/vnd.apache.parquet`, `application/ogg`,
/// `application/wasm`, `application/x-elf`, `audio/wav`,
/// `audio/aiff`, `audio/mpeg`, `audio/flac`, `audio/midi`,
/// `audio/mp4`, `image/png`, `image/jpeg`, `image/gif`,
/// `image/bmp`, `image/tiff`, `image/x-icon`, `image/webp`,
/// `image/avif`, `image/heic`, `video/x-msvideo`, `video/webm`,
/// `video/quicktime`, and `video/mp4`.
///
/// If no signature matches, the default fallback MIME type is
/// returned.
pub fn detect(bytes: BitArray) -> String {
  detect_with_limit(bytes, default_detection_limit)
}

/// Detect a MIME type from the leading bytes of a blob.
///
/// This strict variant returns `Error(Nil)` when no supported
/// magic-number signature matches.
pub fn detect_strict(bytes: BitArray) -> Result(String, Nil) {
  detect_with_limit_strict(bytes, default_detection_limit)
}

/// Detect a MIME type from the leading bytes of a blob, examining at
/// most `limit` bytes from the start of the input.
///
/// A non-positive `limit` is treated as zero, in which case no
/// signature can match and the fallback MIME type is returned.
/// Limits larger than the input are clamped to the input length.
pub fn detect_with_limit(bytes: BitArray, limit: Int) -> String {
  case detect_with_limit_strict(bytes, limit) {
    Ok(mime_type) -> mime_type
    Error(Nil) -> default_mime_type
  }
}

/// Detect a MIME type from at most `limit` leading bytes.
///
/// Strict variant; returns `Error(Nil)` when no supported signature
/// matches within the limit.
pub fn detect_with_limit_strict(
  bytes: BitArray,
  limit: Int,
) -> Result(String, Nil) {
  result_from_option(magic.detect(truncate_to_limit(bytes, limit)))
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

/// Detect a MIME type from bytes, falling back to an explicit
/// extension when the content signature is unknown.
///
/// This helper prefers the byte signature over the extension if the
/// two disagree.
pub fn detect_with_extension(bytes: BitArray, extension: String) -> String {
  case detect_with_extension_strict(bytes, extension) {
    Ok(mime_type) -> mime_type
    Error(Nil) -> default_mime_type
  }
}

/// Detect a MIME type from bytes, falling back to an explicit
/// extension when the content signature is unknown.
///
/// This strict variant returns `Error(Nil)` only when neither the byte
/// signature nor the normalized extension are known.
pub fn detect_with_extension_strict(
  bytes: BitArray,
  extension: String,
) -> Result(String, Nil) {
  case detect_strict(bytes) {
    Ok(mime_type) -> Ok(mime_type)
    Error(Nil) -> extension_to_mime_type_strict(extension)
  }
}

/// Detect a MIME type from bytes, falling back to the filename
/// extension when the content signature is unknown.
///
/// This helper prefers the byte signature over the filename if the two
/// disagree.
pub fn detect_with_filename(bytes: BitArray, filename: String) -> String {
  case detect_with_filename_strict(bytes, filename) {
    Ok(mime_type) -> mime_type
    Error(Nil) -> default_mime_type
  }
}

/// Detect a MIME type from bytes, falling back to the filename
/// extension when the content signature is unknown.
///
/// This strict variant returns `Error(Nil)` only when neither the byte
/// signature nor the filename extension are known.
pub fn detect_with_filename_strict(
  bytes: BitArray,
  filename: String,
) -> Result(String, Nil) {
  case detect_strict(bytes) {
    Ok(mime_type) -> Ok(mime_type)
    Error(Nil) -> filename_to_mime_type_strict(filename)
  }
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

fn find_parameter(
  parameters: List(String),
  requested: String,
) -> Result(String, Nil) {
  parameters
  |> list.find_map(fn(parameter_segment) {
    case string.split_once(parameter_segment, "=") {
      Ok(#(name, value)) -> {
        let normalized_name = name |> string.trim |> string.lowercase

        use <- bool.guard(
          when: normalized_name == requested,
          return: Ok(string.trim(value)),
        )

        Error(Nil)
      }
      _ -> Error(Nil)
    }
  })
}

fn result_from_option(value: Option(a)) -> Result(a, Nil) {
  case value {
    Some(inner) -> Ok(inner)
    None -> Error(Nil)
  }
}
