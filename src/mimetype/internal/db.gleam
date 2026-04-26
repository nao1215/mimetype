// This file contains data derived from jshttp/mime-db.
// Upstream: https://github.com/jshttp/mime-db
// Generated from jshttp/mime-db 1.54.0 (c03ddfc).
// Regenerate with: bash scripts/generate_mime_db.sh
// See THIRD_PARTY_NOTICES.md for the packaged notice text.

pub const default_mime_type = "application/octet-stream"

// The MIME-DB data tables themselves live in the FFI source files
// (mimetype_db_ffi.erl and db_ffi.mjs); see THIRD_PARTY_NOTICES.md for the
// licensing notice that applies to that data.

// Keys are normalized by the public mimetype module before lookup.
@external(erlang, "mimetype_db_ffi", "extension_to_mime_type")
@external(javascript, "./db_ffi.mjs", "extensionToMimeType")
pub fn extension_to_mime_type(extension: String) -> Result(String, Nil)

// Keys are normalized by the public mimetype module before lookup.
@external(erlang, "mimetype_db_ffi", "mime_type_to_extensions")
@external(javascript, "./db_ffi.mjs", "mimeTypeToExtensions")
pub fn mime_type_to_extensions(mime_type: String) -> Result(List(String), Nil)
