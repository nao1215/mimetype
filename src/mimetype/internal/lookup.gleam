//// Filename / extension lookup helpers.
////
//// These operate on plain strings (extensions, paths) and surface the
//// result as `Option(String)` / `Result(String, Nil)` of essence
//// names. The facade (`mimetype`) wraps the essence into a `MimeType`.

import gleam/bool
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import mimetype/internal/db

/// Look up the essence string for a normalised file extension.
///
/// `Error(Nil)` means the extension was not in the generated database.
/// The caller is responsible for normalising (`normalize_extension`)
/// before calling this — `lookup` does not do it for you.
pub fn essence_for_extension(normalized: String) -> Result(String, Nil) {
  db.extension_to_mime_type(normalized)
}

/// Return all known extensions for an essence. `Error(Nil)` means the
/// essence is not in the generated database.
///
/// Common community-standard aliases (e.g. `audio/mp3` for the IANA
/// `audio/mpeg`) are canonicalised before the lookup so both spellings
/// yield the same extension set. The DB itself is regenerated from
/// upstream `jshttp/mime-db`, so aliases live here rather than in the
/// FFI tables.
pub fn extensions_for_essence(essence: String) -> Result(List(String), Nil) {
  db.mime_type_to_extensions(canonical_essence(essence))
}

/// Map widely-used but non-IANA media-type spellings onto their
/// IANA-registered canonical form for downstream lookups. `audio/mp3`
/// is the only entry today (the MP3 file format's IANA name is
/// `audio/mpeg`; `audio/mp3` is community-standard but kept here so
/// every caller sees the same extension set). New aliases must be
/// genuinely interchangeable — same payload format, same extension
/// set — not merely related types.
fn canonical_essence(essence: String) -> String {
  case essence {
    "audio/mp3" -> "audio/mpeg"
    _ -> essence
  }
}

/// Trim, drop any leading dots, and lowercase a raw extension string.
///
/// `"  .JPG  "` → `"jpg"`. The result is the empty string when the
/// caller passed something that contained nothing useful (`""`,
/// `"."`, `"...."`, `"   "`, ...).
pub fn normalize_extension(extension: String) -> String {
  extension |> string.trim |> strip_leading_dots |> string.lowercase
}

fn strip_leading_dots(value: String) -> String {
  use <- bool.lazy_guard(when: string.starts_with(value, "."), return: fn() {
    strip_leading_dots(string.drop_start(value, 1))
  })
  value
}

/// Extract the last extension component of a path / filename.
///
/// Returns `None` when the path contains no usable extension —
/// hidden-but-extension-less files (`.gitignore`), bare basenames
/// (`README`), and the empty string. Returns `Some(normalised)` when
/// an extension is present, with `normalize_extension` already
/// applied.
pub fn extension_from_filename(path: String) -> Option(String) {
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
