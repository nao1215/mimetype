# Changelog

## Unreleased

- Detect `application/json` from leading bytes via a bounded JSON-prefix
  validator. Top-level objects (`{...}`) and arrays (`[...]`) are recognized
  after optional UTF-8 BOM and whitespace, including truncated inputs.
  Bare top-level scalars (numbers, strings, `true`/`false`/`null`) are
  intentionally not sniffed to avoid false positives on plain text. (#19)
- Detect `text/html` from leading bytes by case-insensitive matching on a
  WHATWG-aligned tag list (`<!doctype html`, `<html`, `<head`, `<body`,
  `<script`, `<iframe`, `<table`, `<style`, `<title`, `<br`, `<p`, `<h1`,
  `<div`, `<font`, `<img`, `<a`) followed by a tag-terminating byte
  (whitespace, `>`, or end of input). (#17)
- Detect `text/xml` from leading bytes by recognizing the lowercase
  `<?xml` declaration followed by a tag-terminating byte. Both detectors
  strip an optional UTF-8 BOM and HTML whitespace before matching. (#17)
- Detect `image/svg+xml` from the XML root element. The detector skips an
  optional UTF-8 BOM, whitespace, an `<?xml ... ?>` prolog, an
  `<!DOCTYPE ...>` declaration, and any number of `<!-- ... -->` comments
  before checking for a case-sensitive `<svg` element followed by a tag
  terminator (whitespace, `>`, `/`, or end of input). Takes priority over
  the generic `text/xml` signature so that SVG payloads with an XML
  prolog are reported as `image/svg+xml`. (#18)
- Detect six font formats from leading-byte signatures: TrueType (`font/ttf`),
  OpenType (`font/otf`), TrueType Collection (`font/collection`), WOFF
  (`font/woff`), WOFF2 (`font/woff2`), and Embedded OpenType
  (`application/vnd.ms-fontobject`). MIME types follow RFC 8081. (#22)
- Detect nine additional image formats from leading-byte signatures:
  Photoshop (`image/vnd.adobe.photoshop`), JPEG 2000 (`image/jp2`),
  JPEG XL raw codestream and ISO BMFF container (both `image/jxl`),
  DirectDraw Surface (`image/vnd.ms-dds`), Radiance HDR
  (`image/vnd.radiance`), OpenEXR (`image/x-exr`), QOI (`image/x-qoi`),
  and FITS (`image/fits`). Targa (TGA) is intentionally excluded
  because its only reliable magic is at end-of-file. (#23)
- Detect eight additional compression / archive formats: LZ4 frame and
  legacy (`application/x-lz4`), lzip (`application/x-lzip`), Snappy
  framed (`application/x-snappy-framed`), `.Z` compress
  (`application/x-compress`), ar archive (`application/x-archive`),
  LZH/LHA (`application/x-lzh-compressed`), and zlib raw streams
  (`application/x-deflate`). The zlib detector is intentionally placed
  last so it only fires when no other signature matched, since its
  2-byte magic is heuristic and false-positive prone. Brotli is
  intentionally excluded because the format has no fixed magic. (#24)
- Detect additional audio/video formats: ASF / WMV / WMA
  (`application/vnd.ms-asf`), Flash Video (`video/x-flv`), AAC ADTS and
  AAC ADIF (both `audio/aac`), AMR (`audio/amr`), AMR-WB
  (`audio/amr-wb`), and AC3 (`audio/ac3`). Differentiate Matroska
  (`video/x-matroska`) from WebM (`video/webm`) by inspecting the EBML
  DocType element within the first 256 bytes — a regression from the
  previous behavior where any EBML magic was reported as WebM. (#25)
- Detect plain text as a final fallback. Inputs prefixed with a
  Unicode BOM are reported with the explicit charset
  (`text/plain; charset=utf-8`, `…charset=utf-16le`,
  `…charset=utf-16be`, `…charset=utf-32le`, `…charset=utf-32be`).
  Inputs without a BOM that are entirely printable ASCII or HTML
  whitespace within the first 1 KB are reported as `text/plain`.
  Inputs containing C0 control bytes (other than tab/LF/FF/CR), 0x7F,
  or any byte ≥ 0x80 are treated as binary and continue to fall back
  to `application/octet-stream`. The check is registered as the final
  signature so binary formats and other text formats are detected
  first. **Behavior change**: inputs that previously fell through to
  `application/octet-stream` but consist entirely of printable ASCII
  (e.g. a config file, a CSV-without-extension, or a near-miss HTML
  fragment) are now reported as `text/plain`. (#20)

## [0.1.0] - 2026-04-26

- Added the initial cross-target Gleam project scaffold (`just`, `mise`, CI, release workflow).
- Added MIME type lookup derived from `mime-db`.
- Added common magic-number detection for binary file formats.

Until `1.0.0`, breaking changes may still occur in minor `0.x`
releases.
