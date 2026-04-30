#!/bin/sh
# generate_supported_formats.sh -- Regenerate the supported-format
# bullet list inside README.md from the MIME type strings declared in
# src/mimetype/internal/magic.gleam. The generated content sits
# between the BEGIN_SUPPORTED_FORMATS / END_SUPPORTED_FORMATS HTML
# comments. Run with --check to verify the file is in sync without
# rewriting it (used by CI).

set -eu

MAGIC=src/mimetype/internal/magic.gleam
README=README.md
BEGIN_MARKER="<!-- BEGIN_SUPPORTED_FORMATS -->"
END_MARKER="<!-- END_SUPPORTED_FORMATS -->"

mode=write
case "${1-}" in
  --check) mode=check ;;
  "") ;;
  *)
    echo "usage: $0 [--check]" >&2
    exit 2
    ;;
esac

if [ ! -f "$MAGIC" ]; then
  echo "error: $MAGIC not found (run from the repo root)" >&2
  exit 1
fi

if [ ! -f "$README" ]; then
  echo "error: $README not found (run from the repo root)" >&2
  exit 1
fi

# Extract every MIME type literal that appears in the signature table.
# Matches "type/subtype" inside double quotes for the six top-level
# media types we currently emit.
extract_mime_types() {
  grep -oE '"(application|audio|video|image|text|font)/[a-zA-Z0-9.+;=_ -]+"' \
    "$MAGIC" | sort -u | sed -e 's/^"//' -e 's/"$//'
}

# Print one bullet per MIME type for a given top-level family.
emit_family() {
  family=$1
  heading=$2
  matched=$(extract_mime_types | awk -v f="$family/" 'index($0, f) == 1')
  if [ -z "$matched" ]; then
    return
  fi
  printf '%s\n\n' "$heading"
  printf '%s\n' "$matched" | while IFS= read -r mime; do
    printf -- '- `%s`\n' "$mime"
  done
  printf '\n'
}

# Generate the section body. The order here defines the document
# layout; alphabetical inside each family.
generate_body() {
  cat <<'INTRO'
`detect/1` recognises the following MIME types from byte-level
signatures or structural sniffs near the start of the input. This
list is generated from `src/mimetype/internal/magic.gleam` by
`scripts/generate_supported_formats.sh` — do not edit it by hand;
re-run `just generate-readme` after adding or removing a signature.

INTRO
  emit_family application "### Application formats"
  emit_family audio       "### Audio formats"
  emit_family font        "### Font formats"
  emit_family image       "### Image formats"
  emit_family text        "### Text formats"
  emit_family video       "### Video formats"
}

# Splice the generated body between BEGIN_MARKER and END_MARKER inside
# README.md, leaving everything else untouched. Uses awk so we don't
# depend on GNU sed's in-place flag.
splice_into_readme() {
  body=$1
  awk -v begin="$BEGIN_MARKER" -v end="$END_MARKER" -v body="$body" '
    BEGIN { state = "before" }
    {
      if (state == "before") {
        print
        if ($0 == begin) {
          print body
          state = "inside"
        }
        next
      }
      if (state == "inside") {
        if ($0 == end) {
          print
          state = "after"
        }
        next
      }
      print
    }
    END {
      if (state == "before") {
        print "error: BEGIN_SUPPORTED_FORMATS marker not found" > "/dev/stderr"
        exit 1
      }
      if (state == "inside") {
        print "error: END_SUPPORTED_FORMATS marker not found" > "/dev/stderr"
        exit 1
      }
    }
  ' "$README"
}

body=$(generate_body)
new_readme=$(splice_into_readme "$body")

if [ "$mode" = "check" ]; then
  if [ "$new_readme" != "$(cat "$README")" ]; then
    echo "error: README.md is out of date." >&2
    echo "Re-run 'just generate-readme' and commit the result." >&2
    exit 1
  fi
  exit 0
fi

printf '%s\n' "$new_readme" > "$README"
