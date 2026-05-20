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

/// A media type that callers can safely treat as text: the `text/*`
/// family plus a curated set of `application/*` types whose payload is
/// inherently text-encoded.
///
/// Recognises `application/json` (RFC 8259 §8.1 mandates UTF-8 / UTF-16
/// / UTF-32 encoding), `application/javascript` /
/// `application/ecmascript`, the SQL family
/// (`application/sql`, `application/x-sql`), and every RFC 6839 §3.1
/// `+json` / `+xml` structured-syntax-suffix type. Callers that want a
/// strictly `text/*` check should use `starts_with(essence_of(mt),
/// "text/")` directly.
pub fn is_text_essence(essence: String) -> Bool {
  string.starts_with(essence, "text/")
  || essence == "application/json"
  || essence == "application/xml"
  || essence == "application/javascript"
  || essence == "application/ecmascript"
  || essence == "application/sql"
  || essence == "application/x-sql"
  || string.ends_with(essence, "+json")
  || string.ends_with(essence, "+xml")
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
///
/// Also recognises the RFC 6839 §3.1 structured-syntax suffix
/// hierarchy: a `*+xml` type is treated as a child of
/// `application/xml` (and `text/xml`), a `*+json` type as a child of
/// `application/json`, and so on. The static-hierarchy table still
/// wins when both apply, so `image/svg+xml` continues to inherit
/// from `text/xml` via the explicit entry.
pub fn is_a(mime: String, parent: String) -> Bool {
  use <- bool.guard(when: mime == "", return: False)
  use <- bool.guard(when: parent == "", return: False)
  is_a_loop(mime, parent)
}

/// Return the chain of ancestor essences for `mime`, from immediate
/// parent up to the root. Excludes `mime` itself; empty input or
/// roots return `[]`.
///
/// Walks both the static hierarchy table and the RFC 6839 §3.1
/// structured-syntax suffix mapping, so e.g. `application/xhtml+xml`
/// returns `["application/xml"]`.
pub fn ancestors(mime: String) -> List(String) {
  use <- bool.guard(when: mime == "", return: [])
  ancestors_loop(mime, [])
}

fn is_a_loop(mime: String, parent: String) -> Bool {
  use <- bool.lazy_guard(when: mime == parent, return: fn() { True })
  case effective_parent(mime) {
    Ok(next) -> is_a_loop(next, parent)
    Error(Nil) -> False
  }
}

fn ancestors_loop(mime: String, acc: List(String)) -> List(String) {
  case effective_parent(mime) {
    Ok(parent) -> ancestors_loop(parent, [parent, ..acc])
    Error(Nil) -> list.reverse(acc)
  }
}

/// Resolve the immediate parent of `mime` by consulting the static
/// hierarchy table first, then the RFC 6839 structured-syntax suffix
/// mapping. The explicit table wins on collisions so callers that
/// added a custom parent for a `+suffix` type still see it.
fn effective_parent(mime: String) -> Result(String, Nil) {
  case hierarchy.parent_of(mime) {
    Ok(parent) -> Ok(parent)
    Error(Nil) -> suffix_parent_of(mime)
  }
}

/// Map an RFC 6839 §3.1 structured-syntax suffix to its canonical
/// parent media type. Recognises `+xml`, `+json`, `+zip`, and
/// `+cbor` — the four suffixes registered in the IANA registry that
/// have an obvious universally-supported parent type.
fn suffix_parent_of(mime: String) -> Result(String, Nil) {
  use <- bool.lazy_guard(when: string.ends_with(mime, "+xml"), return: fn() {
    Ok("application/xml")
  })
  use <- bool.lazy_guard(when: string.ends_with(mime, "+json"), return: fn() {
    Ok("application/json")
  })
  use <- bool.lazy_guard(when: string.ends_with(mime, "+zip"), return: fn() {
    Ok("application/zip")
  })
  use <- bool.lazy_guard(when: string.ends_with(mime, "+cbor"), return: fn() {
    Ok("application/cbor")
  })
  Error(Nil)
}
