#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
DB_DIR="$ROOT/doc/reference/upstream/mime-db"
DB_JSON="$DB_DIR/db.json"
DB_PACKAGE="$DB_DIR/package.json"
OUT_GLEAM="$ROOT/src/mimetype/internal/db.gleam"
OUT_ERL="$ROOT/src/mimetype/internal/mimetype_db_ffi.erl"
OUT_MJS="$ROOT/src/mimetype/internal/db_ffi.mjs"

. "$ROOT/scripts/lib/mise_bootstrap.sh"

mimetype_require_tool jq
mimetype_require_tool git
mimetype_require_tool gleam

if [ ! -f "$DB_JSON" ]; then
  cat >&2 <<EOF
error: $DB_JSON was not found.

Clone the upstream references first, for example:

    git clone https://github.com/jshttp/mime-db.git doc/reference/upstream/mime-db
EOF
  exit 1
fi

if [ ! -f "$DB_PACKAGE" ]; then
  echo "error: $DB_PACKAGE was not found." >&2
  exit 1
fi

version="$(jq -er '.version | strings | select(length > 0)' "$DB_PACKAGE")"
commit="$(git -C "$DB_DIR" rev-parse --short HEAD)"

tmp_dir="$(mktemp -d)"
tmp_gleam="$tmp_dir/db.gleam"
tmp_erl="$tmp_dir/mimetype_db_ffi.erl"
tmp_mjs="$tmp_dir/db_ffi.mjs"
validate_dir="$tmp_dir/project"
trap 'rm -rf "$tmp_dir"' EXIT

cat > "$tmp_gleam" <<EOF
// This file contains data derived from jshttp/mime-db.
// Upstream: https://github.com/jshttp/mime-db
// Generated from jshttp/mime-db $version ($commit).
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
EOF

{
  cat <<EOF
% This file contains data derived from jshttp/mime-db.
% Upstream: https://github.com/jshttp/mime-db
% Generated from jshttp/mime-db $version ($commit).
% Regenerate with: bash scripts/generate_mime_db.sh
% See THIRD_PARTY_NOTICES.md for the packaged notice text.
%
% (The MIT License)
%
% Copyright (c) 2014 Jonathan Ong <me@jongleberry.com>
% Copyright (c) 2015-2022 Douglas Christopher Wilson <doug@somethingdoug.com>
%
% Permission is hereby granted, free of charge, to any person obtaining
% a copy of this software and associated documentation files (the
% 'Software'), to deal in the Software without restriction, including
% without limitation the rights to use, copy, modify, merge, publish,
% distribute, sublicense, and/or sell copies of the Software, and to
% permit persons to whom the Software is furnished to do so, subject to
% the following conditions:
%
% The above copyright notice and this permission notice shall be
% included in all copies or substantial portions of the Software.
%
% THE SOFTWARE IS PROVIDED 'AS IS', WITHOUT WARRANTY OF ANY KIND,
% EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
% MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
% IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
% CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
% TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
% SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

-module(mimetype_db_ffi).
-export([extension_to_mime_type/1, mime_type_to_extensions/1]).

-define(EXTENSION_TO_MIME_KEY, {?MODULE, extension_to_mime_table}).
-define(MIME_TO_EXTENSIONS_KEY, {?MODULE, mime_type_to_extensions_table}).

extension_to_mime_type(Extension) ->
    case maps:find(Extension, get_extension_to_mime_table()) of
        {ok, MimeType} -> {ok, MimeType};
        error -> {error, nil}
    end.

mime_type_to_extensions(MimeType) ->
    case maps:find(MimeType, get_mime_type_to_extensions_table()) of
        {ok, Extensions} -> {ok, Extensions};
        error -> {error, nil}
    end.

get_extension_to_mime_table() ->
    case persistent_term:get(?EXTENSION_TO_MIME_KEY, undefined) of
        undefined ->
            Map = extension_to_mime_table(),
            persistent_term:put(?EXTENSION_TO_MIME_KEY, Map),
            Map;
        Map ->
            Map
    end.

get_mime_type_to_extensions_table() ->
    case persistent_term:get(?MIME_TO_EXTENSIONS_KEY, undefined) of
        undefined ->
            Map = mime_type_to_extensions_table(),
            persistent_term:put(?MIME_TO_EXTENSIONS_KEY, Map),
            Map;
        Map ->
            Map
    end.

extension_to_mime_table() ->
    #{
EOF
  jq -r '
    to_entries
    | map(select(.value.extensions != null) | {
        mime: .key,
        source: (.value.source // "custom"),
        extensions: .value.extensions
      })
    | map(.extensions[] as $ext | {
        ext: $ext,
        mime: .mime,
        source: .source
      })
    | sort_by(.ext, .mime)
    | group_by(.ext)
    | map(
        sort_by(
          (if .source == "iana" then 0
           elif .source == "apache" then 1
           elif .source == "nginx" then 2
           else 3
           end),
          .mime
        )[0]
      )
    | sort_by(.ext)
    | map(
        "        <<"
        + (.ext | @json)
        + "/utf8>> => <<"
        + (.mime | @json)
        + "/utf8>>"
      )
    | join(",\n")
  ' "$DB_JSON"
  cat <<EOF
    }.

mime_type_to_extensions_table() ->
    #{
EOF
  jq -r '
    to_entries
    | map(select(.value.extensions != null))
    | sort_by(.key)
    | map(
        "        <<"
        + (.key | @json)
        + "/utf8>> => ["
        + (.value.extensions
          | map("<<" + (. | @json) + "/utf8>>")
          | join(", "))
        + "]"
      )
    | join(",\n")
  ' "$DB_JSON"
  cat <<EOF
    }.
EOF
} > "$tmp_erl"

{
  cat <<EOF
// This file contains data derived from jshttp/mime-db.
// Upstream: https://github.com/jshttp/mime-db
// Generated from jshttp/mime-db $version ($commit).
// Regenerate with: bash scripts/generate_mime_db.sh
// See THIRD_PARTY_NOTICES.md for the packaged notice text.
//
// (The MIT License)
//
// Copyright (c) 2014 Jonathan Ong <me@jongleberry.com>
// Copyright (c) 2015-2022 Douglas Christopher Wilson <doug@somethingdoug.com>
//
// Permission is hereby granted, free of charge, to any person obtaining
// a copy of this software and associated documentation files (the
// 'Software'), to deal in the Software without restriction, including
// without limitation the rights to use, copy, modify, merge, publish,
// distribute, sublicense, and/or sell copies of the Software, and to
// permit persons to whom the Software is furnished to do so, subject to
// the following conditions:
//
// The above copyright notice and this permission notice shall be
// included in all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED 'AS IS', WITHOUT WARRANTY OF ANY KIND,
// EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
// IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
// CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
// TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
// SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

import { Result\$Error, Result\$Ok, toList } from "../../gleam.mjs";

const missing = /* @__PURE__ */ Result\$Error(undefined);

const extensionToMime = /* @__PURE__ */ new Map([
EOF
  jq -r '
    to_entries
    | map(select(.value.extensions != null) | {
        mime: .key,
        source: (.value.source // "custom"),
        extensions: .value.extensions
      })
    | map(.extensions[] as $ext | {
        ext: $ext,
        mime: .mime,
        source: .source
      })
    | sort_by(.ext, .mime)
    | group_by(.ext)
    | map(
        sort_by(
          (if .source == "iana" then 0
           elif .source == "apache" then 1
           elif .source == "nginx" then 2
           else 3
           end),
          .mime
        )[0]
      )
    | .[]
    | "  [" + (.ext | @json) + ", " + (.mime | @json) + "],"
  ' "$DB_JSON"
  cat <<EOF
]);

const mimeTypeToExtensionsMap = /* @__PURE__ */ new Map([
EOF
  jq -r '
    to_entries
    | map(select(.value.extensions != null))
    | sort_by(.key)
    | .[]
    | "  [" + (.key | @json) + ", toList(" + (.value.extensions | @json) + ")],"
  ' "$DB_JSON"
  cat <<EOF
]);

export function extensionToMimeType(extension) {
  return extensionToMime.has(extension)
    ? Result\$Ok(extensionToMime.get(extension))
    : missing;
}

export function mimeTypeToExtensions(mimeType) {
  return mimeTypeToExtensionsMap.has(mimeType)
    ? Result\$Ok(mimeTypeToExtensionsMap.get(mimeType))
    : missing;
}
EOF
} > "$tmp_mjs"

mkdir -p "$validate_dir"
cp "$ROOT/gleam.toml" "$validate_dir/gleam.toml"
cp "$ROOT/manifest.toml" "$validate_dir/manifest.toml"
cp -R "$ROOT/src" "$validate_dir/src"
cp "$tmp_gleam" "$validate_dir/src/mimetype/internal/db.gleam"
cp "$tmp_erl" "$validate_dir/src/mimetype/internal/mimetype_db_ffi.erl"
cp "$tmp_mjs" "$validate_dir/src/mimetype/internal/db_ffi.mjs"

(
  cd "$validate_dir"
  gleam format src/mimetype/internal/db.gleam
  gleam format --check src/mimetype/internal/db.gleam
  gleam check
  gleam build --warnings-as-errors --target erlang
  gleam build --warnings-as-errors --target javascript
)

mv "$tmp_gleam" "$OUT_GLEAM"
mv "$tmp_erl" "$OUT_ERL"
mv "$tmp_mjs" "$OUT_MJS"
printf 'wrote %s\n' "$OUT_GLEAM"
printf 'wrote %s\n' "$OUT_ERL"
printf 'wrote %s\n' "$OUT_MJS"
