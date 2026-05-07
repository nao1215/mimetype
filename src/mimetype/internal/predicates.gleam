//// Family predicates and ancestor-chain helpers.
////
//// All functions take essence strings (`"image/png"`,
//// `"application/zip"`) rather than `MimeType` values so this module
//// stays free of the opaque type. The facade (`mimetype`) decomposes
//// `MimeType` arguments before forwarding here.

import gleam/bool
import gleam/list
import gleam/string
import mimetype/internal/hierarchy

/// Top-level type prefix check: `is_image_essence("image/png")` is
/// `True`, `is_image_essence("text/html")` is `False`.
pub fn is_image_essence(essence: String) -> Bool {
  string.starts_with(essence, "image/")
}

pub fn is_text_essence(essence: String) -> Bool {
  string.starts_with(essence, "text/")
}

pub fn is_audio_essence(essence: String) -> Bool {
  string.starts_with(essence, "audio/")
}

pub fn is_video_essence(essence: String) -> Bool {
  string.starts_with(essence, "video/")
}

/// Reflexive + transitive subtype check on the static hierarchy.
///
/// Empty inputs are not equal even to themselves; the facade is
/// responsible for the empty-essence guard before forwarding here.
pub fn is_a(mime: String, parent: String) -> Bool {
  use <- bool.guard(when: mime == "", return: False)
  use <- bool.guard(when: parent == "", return: False)
  is_a_loop(mime, parent)
}

/// Return the chain of ancestor essences for `mime`, from immediate
/// parent up to the root. Excludes `mime` itself; empty input or
/// roots return `[]`.
pub fn ancestors(mime: String) -> List(String) {
  use <- bool.guard(when: mime == "", return: [])
  ancestors_loop(mime, [])
}

fn is_a_loop(mime: String, parent: String) -> Bool {
  use <- bool.lazy_guard(when: mime == parent, return: fn() { True })
  case hierarchy.parent_of(mime) {
    Ok(next) -> is_a_loop(next, parent)
    Error(Nil) -> False
  }
}

fn ancestors_loop(mime: String, acc: List(String)) -> List(String) {
  case hierarchy.parent_of(mime) {
    Ok(parent) -> ancestors_loop(parent, [parent, ..acc])
    Error(Nil) -> list.reverse(acc)
  }
}
