# mimetype

[![CI](https://github.com/nao1215/mimetype/actions/workflows/ci.yml/badge.svg)](https://github.com/nao1215/mimetype/actions/workflows/ci.yml)
[![Gitleaks](https://github.com/nao1215/mimetype/actions/workflows/gitleaks.yml/badge.svg)](https://github.com/nao1215/mimetype/actions/workflows/gitleaks.yml)
[![Trivy](https://github.com/nao1215/mimetype/actions/workflows/trivy.yml/badge.svg)](https://github.com/nao1215/mimetype/actions/workflows/trivy.yml)
[![OSV-Scanner](https://github.com/nao1215/mimetype/actions/workflows/osv-scan.yml/badge.svg)](https://github.com/nao1215/mimetype/actions/workflows/osv-scan.yml)
[![Hex](https://img.shields.io/hexpm/v/mimetype)](https://hex.pm/packages/mimetype)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/mimetype/)
[![Hex Downloads](https://img.shields.io/hexpm/dt/mimetype)](https://hex.pm/packages/mimetype)
[![License](https://img.shields.io/github/license/nao1215/mimetype)](./LICENSE)
[![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/nao1215/mimetype/badge)](https://scorecard.dev/viewer/?uri=github.com/nao1215/mimetype)

MIME type lookup and magic-number detection for Gleam on Erlang and
JavaScript. Pure Gleam; the extension table is generated from
[`jshttp/mime-db`](https://github.com/jshttp/mime-db), which tracks the
IANA registry and common aliases. The full API is on
[HexDocs](https://hexdocs.pm/mimetype/).

## Install

```sh
gleam add mimetype
```

## Lookup by filename or extension

`filename_to_mime_type` ignores case and falls back to
`application/octet-stream`, so it can go straight into a response path:

```gleam
import mimetype

pub fn content_type_for(filename: String) -> String {
  mimetype.filename_to_mime_type(filename)
  |> mimetype.to_string
}

// content_type_for("report.PDF")    -> "application/pdf"
// content_type_for("avatar.jpg")    -> "image/jpeg"
// content_type_for("archive.tar.gz") -> "application/gzip"
// content_type_for("notes")         -> "application/octet-stream"
```

Every call returns an opaque `MimeType`. `mimetype.parse` builds one from
a wire string and `mimetype.to_string` serialises it; `essence_of`,
`parameter_of`, `charset_of_type`, `is_image`, `is_a` and the other
accessors inspect it. The `parameter_of` doc comment gives the rules for
duplicate names (first wins), case-insensitive lookup and whitespace in
values.

```gleam
import gleam/option.{Some}
import mimetype

pub fn main() {
  mimetype.extension_to_mime_type(".json")
  |> mimetype.to_string
  // -> "application/json"

  let assert Ok(jpeg) = mimetype.parse("image/jpeg")
  mimetype.mime_type_to_extensions(jpeg)
  // -> ["jpg", "jpeg", "jpe"]

  mimetype.detect_with_filename(<<0, 1, 2, 3>>, "report.csv")
  |> mimetype.essence_of
  // -> "text/csv"

  let assert Ok(html) = mimetype.parse("text/html; charset=utf-8")
  mimetype.charset_of_type(html)
  // -> Some("utf-8")
}
```

## Detect an upload from its bytes

Uploaded filenames are user input. `detect_strict` checks the leading
bytes instead, and its error separates `EmptyInput` (zero bytes) from
`NoMatch` (no signature matched) so you can pick the HTTP status.
`detect` returns `application/octet-stream` in both cases.

```gleam
import mimetype

pub type UploadError {
  EmptyUpload
  Unsupported(detected: String)
}

/// Allow only PNG, JPEG, and WebP uploads, judged by magic bytes.
pub fn validate_image_upload(
  bytes: BitArray,
) -> Result(mimetype.MimeType, UploadError) {
  case mimetype.detect_strict(bytes) {
    Ok(mime) ->
      case mimetype.is_image(mime) && image_is_allowed(mime) {
        True -> Ok(mime)
        False -> Error(Unsupported(detected: mimetype.to_string(mime)))
      }
    Error(mimetype.EmptyInput) -> Error(EmptyUpload)
    Error(_) -> Error(Unsupported(detected: "application/octet-stream"))
  }
}

fn image_is_allowed(mime: mimetype.MimeType) -> Bool {
  case mimetype.essence_of(mime) {
    "image/png" | "image/jpeg" | "image/webp" -> True
    _ -> False
  }
}
```

### Reading only a prefix

`detect_reader` and `detect_reader_strict` take a synchronous
`Reader(read_error) = fn(Int) -> Result(BitArray, read_error)` and a
byte budget. The reader is called once and should return up to that
many bytes from offset 0; a shorter result means the source ended. The
strict variant keeps a reader failure as `ReaderError(e)`, apart from
`EmptyInput` and `NoMatch`.

```gleam
import mimetype

pub fn main() {
  let png = <<0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A>>
  let reader = fn(_limit) { Ok(png) }

  mimetype.detect_reader(reader, 3072)
  |> mimetype.to_string
  // -> "image/png"
}
```

On BEAM, wrap a file read of the first `limit` bytes. Browser `Blob` and
`ReadableStream` reads are asynchronous and cannot satisfy `Reader`, so
await `blob.slice(0, 3072).arrayBuffer()` yourself and pass the bytes to
`detect` or `detect_strict`.

### What detection does not do

- ZIP containers are inspected shallowly, only for `epub`, OOXML (`docx`/`xlsx`/`pptx`), OpenDocument (`odt`/`ods`/`odp`), `jar` and `apk`. Nested containers are not opened.
- Text sniffing is limited to the UTF-8/16/32 BOMs, which give `text/plain; charset=<utf-X>`, and a printable-ASCII check (the bounded WHATWG-style heuristic from #20), which gives bare `text/plain`. No other encoding is detected.
- Apart from those four BOM-derived charsets, detection does not parse or report MIME parameters.

## Content negotiation

`mimetype/accept` parses RFC 9110 §12.5 `Accept`-family headers and
picks the best server offer.

```gleam
import mimetype
import mimetype/accept

pub fn main() {
  let assert Ok(items) = accept.parse("text/html, application/json;q=0.9")
  let assert Ok(html) = mimetype.parse("text/html")
  let assert Ok(json) = mimetype.parse("application/json")
  accept.negotiate(client_accepts: items, server_offers: [json, html])
  // -> Some(html)
}
```

`Accept-Encoding`, `Accept-Charset` and `Accept-Language` work the same
way:

```gleam
import mimetype/accept

pub fn main() {
  let assert Ok(items) =
    accept.parse_encoding("gzip, br;q=1.0, *;q=0.1")
  accept.negotiate_value(client_accepts: items, server_offers: ["br", "gzip"])
  // -> Some("br")
}
```

`q=0` excludes a range. A bare `*/*` returns the server's first offer.
`Specific(MimeType)` matches on the essence only; RFC §12.5.1
parameter-level matching is out of scope.

## Supported magic-number formats

<!-- BEGIN_SUPPORTED_FORMATS -->
`detect/1` recognises the following MIME types from byte-level
signatures or structural sniffs near the start of the input. This
list is generated from `src/mimetype/internal/magic.gleam` by
`scripts/generate_supported_formats.sh`. Do not edit it by hand;
re-run `just generate-readme` after adding or removing a signature.

### Application formats

- `application/epub+zip`
- `application/gzip`
- `application/java-archive`
- `application/json`
- `application/msword`
- `application/ogg`
- `application/pdf`
- `application/rtf`
- `application/vnd.android.package-archive`
- `application/vnd.apache.parquet`
- `application/vnd.ms-asf`
- `application/vnd.ms-cab-compressed`
- `application/vnd.ms-excel`
- `application/vnd.ms-fontobject`
- `application/vnd.ms-powerpoint`
- `application/vnd.oasis.opendocument.presentation`
- `application/vnd.oasis.opendocument.spreadsheet`
- `application/vnd.oasis.opendocument.text`
- `application/vnd.openxmlformats-officedocument.presentationml.presentation`
- `application/vnd.openxmlformats-officedocument.spreadsheetml.sheet`
- `application/vnd.openxmlformats-officedocument.wordprocessingml.document`
- `application/vnd.sqlite3`
- `application/wasm`
- `application/x-7z-compressed`
- `application/x-archive`
- `application/x-bzip2`
- `application/x-compress`
- `application/x-deflate`
- `application/x-elf`
- `application/x-lz4`
- `application/x-lzh-compressed`
- `application/x-lzip`
- `application/x-ole-storage`
- `application/x-rar-compressed`
- `application/x-snappy-framed`
- `application/x-tar`
- `application/x-xz`
- `application/zip`
- `application/zstd`

### Audio formats

- `audio/aac`
- `audio/ac3`
- `audio/aiff`
- `audio/amr`
- `audio/amr-wb`
- `audio/flac`
- `audio/midi`
- `audio/mp4`
- `audio/mpeg`
- `audio/wav`

### Font formats

- `font/collection`
- `font/otf`
- `font/ttf`
- `font/woff`
- `font/woff2`

### Image formats

- `image/avif`
- `image/bmp`
- `image/fits`
- `image/gif`
- `image/heic`
- `image/jp2`
- `image/jpeg`
- `image/jxl`
- `image/png`
- `image/svg+xml`
- `image/tiff`
- `image/vnd.adobe.photoshop`
- `image/vnd.ms-dds`
- `image/vnd.radiance`
- `image/webp`
- `image/x-exr`
- `image/x-icon`
- `image/x-qoi`

### Text formats

- `text/html`
- `text/plain`
- `text/plain; charset=utf-16be`
- `text/plain; charset=utf-16le`
- `text/plain; charset=utf-32be`
- `text/plain; charset=utf-32le`
- `text/plain; charset=utf-8`
- `text/xml`

### Video formats

- `video/mp4`
- `video/quicktime`
- `video/webm`
- `video/x-flv`
- `video/x-matroska`
- `video/x-msvideo`
<!-- END_SUPPORTED_FORMATS -->

The detector only checks fixed signatures near the start of the input,
plus ZIP local headers for the containers listed above.

## Development

```sh
mise install
just ci
```

The generated MIME-DB lookup tables live in
`src/mimetype/internal/mimetype_db_ffi.erl` and
`src/mimetype/internal/db_ffi.mjs`, with a thin Gleam wrapper at
`src/mimetype/internal/db.gleam`. All three files are derived from
`doc/reference/upstream/mime-db/db.json`. Refresh them with:

```sh
just generate-db
```

CI runs the generator against the pinned upstream commit and fails if
the output differs from the committed files.

### Benchmarks

`test/mimetype_bench.gleam` times the lookup and detection paths:

```sh
just bench-erlang
just bench-javascript
just bench            # both, in sequence
```

Each run prints a Markdown table of `ns/op`. Save a baseline from
`main` (`just bench-erlang > before.md`), rerun on your branch and diff
the tables. CI does not run the benchmarks.

## Testing

| Technique | Bug class caught here |
|---|---|
| Examples and unit tests | [Wrong signatures, lookups and parse errors](doc/testing.md#examples-and-unit-tests) |
| Generated properties | [Round trips and predicates that break on unusual input](doc/testing.md#generated-properties) |
| Differential testing | [Content negotiation that departs from RFC 9110; UTF-8 and JSON detection that disagree with the standard library and gleam_json](doc/testing.md#differential-testing) |
| Metamorphic relations | [Order-dependent negotiation, lossy serialisation, detection reading past its limit](doc/testing.md#metamorphic-relations) |
| Nightly runs | [Rare inputs the normal run count misses](doc/testing.md#nightly-runs) |
| Mutation testing | [Assertions that miss a changed operator or branch](doc/testing.md#mutation-testing) |

## Verifying releases

Each GitHub Release attaches the Hex package tarball (`mimetype-<version>.tar`),
`checksums.txt`, a cosign signature bundle (`checksums.txt.sigstore.json`) and
build provenance (`mimetype-<version>.intoto.jsonl`). Download the assets, then:

```sh
gh attestation verify mimetype-<version>.tar --repo nao1215/mimetype

cosign verify-blob \
  --bundle checksums.txt.sigstore.json \
  --certificate-identity-regexp '^https://github\.com/nao1215/mimetype/\.github/workflows/release\.yml@refs/tags/v' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  checksums.txt
sha256sum --check checksums.txt
```

## Licensing

The data tables under `src/mimetype/internal/` are generated from
`jshttp/mime-db`. The generated FFI source files
(`mimetype_db_ffi.erl` and `db_ffi.mjs`) carry the MIT notice inline;
the same packaged notice is also included in `THIRD_PARTY_NOTICES.md`.
