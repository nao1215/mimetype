//// Static MIME-type subtype tree.
////
//// Each entry is a `#(child, parent)` pair. The relation is "is-a-kind-of":
//// for example `application/vnd.openxmlformats-officedocument.wordprocessingml.document`
//// is-a `application/zip` because a `.docx` file is, structurally, a ZIP
//// archive. Lookups walk the parent chain, so a child indirectly inherits
//// from every ancestor.
////
//// The tree mirrors the design of Go's `gabriel-vasile/mimetype` library:
//// each child has at most one parent. Single-parent inheritance keeps the
//// data shape simple and avoids ambiguity in `ancestors/1`.

const parents: List(#(String, String)) = [
  // OOXML formats — DOCX/XLSX/PPTX are ZIP archives containing XML parts.
  #(
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    "application/zip",
  ),
  #(
    "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
    "application/zip",
  ),
  #(
    "application/vnd.openxmlformats-officedocument.presentationml.presentation",
    "application/zip",
  ),
  // OpenDocument formats — also ZIP archives.
  #("application/vnd.oasis.opendocument.text", "application/zip"),
  #("application/vnd.oasis.opendocument.spreadsheet", "application/zip"),
  #("application/vnd.oasis.opendocument.presentation", "application/zip"),
  // ePub, JAR, APK — all ZIP underneath.
  #("application/epub+zip", "application/zip"),
  #("application/java-archive", "application/zip"),
  #("application/vnd.android.package-archive", "application/zip"),
  // Legacy MS Office formats — built on the OLE Compound File Binary
  // structure (a.k.a. CFB / "structured storage").
  #("application/msword", "application/x-ole-storage"),
  #("application/vnd.ms-excel", "application/x-ole-storage"),
  #("application/vnd.ms-powerpoint", "application/x-ole-storage"),
  // SVG is XML.
  #("image/svg+xml", "text/xml"),
]

/// Look up the immediate parent of `mime`, or `Error(Nil)` if `mime` is a
/// root in the hierarchy.
pub fn parent_of(mime: String) -> Result(String, Nil) {
  parent_lookup(parents, mime)
}

fn parent_lookup(
  entries: List(#(String, String)),
  mime: String,
) -> Result(String, Nil) {
  case entries {
    [] -> Error(Nil)
    [#(child, parent), ..rest] ->
      case child == mime {
        True -> Ok(parent)
        False -> parent_lookup(rest, mime)
      }
  }
}
