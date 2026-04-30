# mimetype

MIME type lookup and magic-number detection for Gleam on Erlang and JavaScript targets.

## Features

- Extension-to-MIME and MIME-to-extensions lookup derived from `mime-db`
- Magic-number detection for common binary formats across archive, document, image, audio, and video families
- Pure Gleam implementation that builds on both targets

## Install

```sh
gleam add mimetype
```

## When to use this

Use `mimetype` when you need a small, cross-target MIME utility in
Gleam:

- Serving files or attachments: resolve `Content-Type` from a filename or extension
- Validating uploads: prefer magic-number detection over user-supplied extensions
- Bridging APIs: map between file extensions and MIME types in both directions

The extension database is generated from `jshttp/mime-db`, which tracks
the IANA media type registry and common ecosystem aliases. Refreshing
the generated table keeps lookups aligned with that upstream source.

This library intentionally stays focused:

- It does perform shallow ZIP-container inspection for a small fixed allowlist: `epub`, OOXML (`docx`/`xlsx`/`pptx`), OpenDocument (`odt`/`ods`/`odp`), `jar`, and `apk`. It does not recurse arbitrarily into nested containers or inspect embedded subformats beyond those targeted signatures.
- It does sniff `text/plain` from printable-ASCII-only payloads (the bounded WHATWG-style binary-vs-text heuristic added in #20) and recognises the UTF-8/16/32 BOM signatures, returning `text/plain; charset=<utf-X>` for the BOM cases. This is the **only** text-related sniffing — it does not detect text encodings beyond the BOM marker, and the printable-ASCII fallback emits a bare `text/plain` with no charset parameter.
- Beyond the four BOM-derived `text/plain; charset=utf-*` signatures it does not parse, validate, or surface MIME-parameter values from the wire.

## Usage

Detection / lookup helpers return an opaque `MimeType` value. Use
`mimetype.to_string` to serialise one for an HTTP `Content-Type`
header; use `mimetype.parse` to construct one from a wire-format
string. Inspect with `essence_of`, `parameter_of`, `charset_of_type`,
`is_image`, `is_a`, and the rest of the predicate / accessor family.

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

  mimetype.filename_to_mime_type("photo.JPG")
  |> mimetype.to_string
  // -> "image/jpeg"

  mimetype.detect(<<0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A>>)
  |> mimetype.is_image
  // -> True

  mimetype.detect(<<>>)
  |> mimetype.to_string
  // -> "application/octet-stream"  (silent fallback for unknown / empty input)

  mimetype.detect_strict(<<>>)
  // -> Error(EmptyInput)  (loud variant — empty input vs. NoMatch)

  mimetype.detect_with_filename(<<0, 1, 2, 3>>, "report.csv")
  |> mimetype.essence_of
  // -> "text/csv"

  let assert Ok(html) = mimetype.parse("text/html; charset=utf-8")
  mimetype.charset_of_type(html)
  // -> Some("utf-8")
}
```

## Reader-based detection

`detect_reader` and `detect_reader_strict` let callers detect a MIME
type **without buffering the whole input**. They take a synchronous
reader plus a byte budget, and the reader is invoked **at most once**
to fetch up to that many bytes from the start of the source.

### Reader contract

```gleam
pub type Reader(read_error) = fn(Int) -> Result(BitArray, read_error)
```

- The `Int` argument is the maximum number of bytes the detector wants.
- Returning fewer bytes than requested is fine — it is interpreted as
  "the source ended early". Detection runs against whatever was
  returned.
- The returned `BitArray` should always be the prefix starting at
  offset 0 of the source. The detector inspects it from byte 0.
- The error parameter `read_error` is opaque to the library; in the
  strict variant it is preserved as `ReaderError(read_error)` so
  callers can distinguish IO failures from "no signature matched".

The reader is called **once per detection call**. There is no
streaming or back-and-forth — return enough bytes for the largest
signature you care about (the detector inspects up to a few KB by
default), or pass a custom `limit` argument tuned for your workload.

### In-memory adapter

The simplest case: when the bytes are already in hand, wrap them in a
function that ignores its argument.

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

### BEAM file prefix reader

On the Erlang target, wrap a file-IO library so that one call returns
up to `limit` bytes from the start of the file. Any IO library that
can open a file and read a fixed-size prefix works — the snippet below
sketches the shape using a `read_prefix(path, limit)` helper that
returns `Result(BitArray, your_error)`:

```gleam
import mimetype

pub fn detect_file(path: String) -> Result(mimetype.MimeType, mimetype.DetectionError(your_error)) {
  let reader = fn(limit) { read_prefix(path, limit) }
  mimetype.detect_reader_strict(reader, 3072)
}
```

If `read_prefix` returns `Ok(<<>>)` for an empty file, the strict
variant surfaces `Error(EmptyInput)`. If `read_prefix` itself returns
`Error(some_io_error)`, the strict variant surfaces
`Error(ReaderError(some_io_error))` so the caller can distinguish IO
failure from a genuine no-match.

### JavaScript browser adapter

In the browser, `File` / `Blob` / `ReadableStream` reads are
asynchronous, so they cannot satisfy the synchronous `Reader`
contract directly. The intended pattern is:

1. Read the prefix asynchronously (`await blob.slice(0, limit).arrayBuffer()`
   or the equivalent on a `ReadableStream`).
2. Pass the resulting bytes to `detect` / `detect_strict`, **not** to
   `detect_reader`.

In Gleam pseudo-code, with an FFI helper `read_blob_prefix` that
awaits the slice and returns a `BitArray`:

```gleam
import mimetype

pub fn detect_blob(blob: Blob) -> mimetype.MimeType {
  // `read_blob_prefix` is your FFI: await blob.slice(0, 3072).arrayBuffer()
  let bytes = read_blob_prefix(blob, 3072)
  mimetype.detect(bytes)
}
```

The reader-based API is most useful when the source is itself
synchronous (BEAM file IO, in-memory buffers, deterministic stream
adapters). For Promise-based sources, awaiting the prefix once and
calling `detect` is the recommended shape.

### Strict variants and error handling

The strict variants return `Result(MimeType, DetectionError(read_error))`,
where `DetectionError` distinguishes:

- `EmptyInput` — the reader returned a zero-byte payload, so no
  detection was possible.
- `NoMatch` — the reader returned bytes, but no signature and no
  printable-ASCII fallback applied.
- `ReaderError(e)` — the reader itself failed; `e` is preserved
  unchanged.
- `UnknownExtension(_)` — only emitted by extension/filename helpers,
  not the reader API.

```gleam
import gleam/io
import mimetype

pub fn classify(reader) {
  case mimetype.detect_reader_strict(reader, 3072) {
    Ok(mime) -> io.println(mimetype.to_string(mime))
    Error(mimetype.EmptyInput) -> io.println("empty source")
    Error(mimetype.NoMatch) -> io.println("unrecognised content")
    Error(mimetype.ReaderError(reason)) -> io.debug(reason)
    Error(mimetype.UnknownExtension(_)) -> Nil
  }
}
```

## Supported magic-number formats

<!-- BEGIN_SUPPORTED_FORMATS -->
`detect/1` recognises the following MIME types from byte-level
signatures or structural sniffs near the start of the input. This
list is generated from `src/mimetype/internal/magic.gleam` by
`scripts/generate_supported_formats.sh` — do not edit it by hand;
re-run `just generate-readme` after adding or removing a signature.

### Application formats

- `application/epub+zip`
- `application/gzip`
- `application/java-archive`
- `application/json`
- `application/msword`
- `application/ogg`
- `application/pdf`
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

The detector is intentionally shallow: it looks only at fixed
signatures near the start of the byte stream, plus a small amount of
targeted ZIP local-header inspection for the container formats listed
above. It does not recurse arbitrarily into nested containers.

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

CI runs the same generator against the pinned upstream commit and fails
the build if the regenerated output drifts from the committed copies.

### Benchmarks

The hot lookup and detection paths have a small reproducible bench
harness under `test/mimetype_bench.gleam`. Run it on either target:

```sh
just bench-erlang
just bench-javascript
just bench            # both, in sequence
```

Each run prints a Markdown table of `ns/op` figures. Capture a
baseline from `main` before a refactor
(`just bench-erlang > before.md`), then re-run on the working branch
and diff the two tables to check for material regressions. The
harness is intentionally not wired into PR-time CI gates — it is for
local A/B comparison and ad-hoc investigation, not for blocking
merges on micro-fluctuations.

## Licensing

The data tables under `src/mimetype/internal/` are generated from
`jshttp/mime-db`. The generated FFI source files
(`mimetype_db_ffi.erl` and `db_ffi.mjs`) carry the MIT notice inline;
the same packaged notice is also included in `THIRD_PARTY_NOTICES.md`.
