# Changelog

## Unreleased

## [0.9.0] - 2026-04-29

### Fixed

- **`parse`** now strips the surrounding `"` delimiters from quoted-string
  parameter values per RFC 7230 §3.2.6, and decodes backslash escapes
  inside (`\X` → `X`). `parameter_of(parse("text/html; charset=\"utf-8\""), "charset")`
  now returns `Some("utf-8")` instead of `Some("\"utf-8\"")`. The same
  fix unwraps quoted boundaries (`boundary="foo\"bar"` decodes to `foo"bar`)
  and stabilises round-tripping through `to_string` + `parse`. Token-form
  values pass through unchanged. Malformed inputs (lone `"`, unmatched
  leading `"`, trailing lone `\`) are passed through unchanged so the
  parser stays tolerant of off-spec wire input. (#69)

## [0.8.0] - 2026-04-29

### Added

- Detect OpenDocument ZIP containers via their required leading
  `mimetype` entry: `application/vnd.oasis.opendocument.text`
  (`.odt`), `application/vnd.oasis.opendocument.spreadsheet`
  (`.ods`), and `application/vnd.oasis.opendocument.presentation`
  (`.odp`). This brings content-based detection into line with the
  existing extension database and ZIP subtype hierarchy.
- **`pub opaque type MimeType`**: a normalised, validated MIME type
  value carrying both the essence (`type/subtype`) and the parsed
  parameter list. All detection / lookup helpers now return
  `MimeType` (or `Result(MimeType, _)`); predicates and accessors
  operate on `MimeType` rather than ad-hoc strings. Construction:
    - `parse(String) -> Result(MimeType, ParseError)` — wire-format
      parser. Returns `Error(EmptyMimeType)` for empty input and
      `Error(InvalidMimeType(original))` for malformed essences.
    - `to_string(MimeType) -> String` — serialise back to the
      wire format (round-trippable through `parse`).
  Accessors:
    - `essence_of(MimeType) -> String`
    - `parameter_of(MimeType, String) -> Option(String)`
    - `charset_of_type(MimeType) -> Option(String)`
- **`ParseError`** type, with `EmptyMimeType` and
  `InvalidMimeType(String)` variants, returned by `parse/1`.

### Changed

- **API-wide `String` → `MimeType` (BREAKING)**: every detection
  and lookup function now returns `MimeType` (or
  `Result(MimeType, DetectionError(_))`) instead of a bare
  `String`. Predicates and ancestor helpers take `MimeType`.
  Affected functions:
    - `detect`, `detect_strict`
    - `detect_with_limit`, `detect_with_limit_strict`
    - `detect_signature_only`, `detect_signature_only_with_limit`
    - `detect_with_extension`, `detect_with_extension_strict`
    - `detect_with_filename`, `detect_with_filename_strict`
    - `detect_reader`, `detect_reader_strict`
    - `extension_to_mime_type`, `extension_to_mime_type_strict`
    - `filename_to_mime_type`, `filename_to_mime_type_strict`
    - `mime_type_to_extensions`, `mime_type_to_extensions_strict`
      (argument changes from `String` to `MimeType`; return list
      stays `List(String)`)
    - `is_image`, `is_text`, `is_audio`, `is_video`
    - `is_a` (both arguments), `is_zip_based`, `is_xml_based`
    - `ancestors` (argument and list element type both `MimeType`)
  `default_mime_type` is now a `MimeType` constant rather than a
  `String`. Migration:
    - Reading: pipe results through `to_string` (for the wire
      form) or `essence_of` (for `type/subtype`). Predicates
      compose directly on the new value, no extraction needed.
    - Constructing arguments: replace bare strings with
      `parse(s)` (and `result.unwrap` / `let assert` if you
      know the input is well-formed). For
      `mime_type_to_extensions`, that's the most common
      migration site.
  `charset_of(BitArray)` continues to return
  `Result(String, DetectionError(Nil))` — its result is a charset
  name, not a MIME type. Closes #62. (#62)
- **Strict family (BREAKING)**: the ten strict-family functions
  (`detect_strict`, `detect_with_limit_strict`,
  `detect_signature_only`, `detect_signature_only_with_limit`,
  `detect_with_extension_strict`, `detect_with_filename_strict`,
  `extension_to_mime_type_strict`, `filename_to_mime_type_strict`,
  `charset_of`) now return `Result(_, DetectionError(Nil))` instead
  of `Result(_, Nil)`, matching the shape `detect_reader_strict`
  already used in 0.7.0. `DetectionError` gains two new variants
  alongside the existing `NoMatch` and `ReaderError(_)`:
    - `EmptyInput` — the input was a zero-byte `BitArray`, an empty
      extension string, or a path with no usable extension.
    - `UnknownExtension(String)` — the supplied filename / extension
      is not in the MIME database; the normalised lookup key is
      carried so callers can render it without re-parsing.
  Migration: callers that pattern-matched `Error(Nil)` switch to
  matching the relevant variant (often `Error(NoMatch)` for
  detection failures, `Error(EmptyInput)` for empty inputs, and
  `Error(UnknownExtension(_))` for the extension-lookup failures of
  `extension_to_mime_type_strict` / `filename_to_mime_type_strict`).
  Closes the rest of #61. (#61)
- **`charset_of` (BREAKING, behaviour change)**: now returns
  `Error(EmptyInput)` for the zero-byte `BitArray`. Previously the
  internal pure-ASCII fallback caused `charset_of(<<>>)` to return
  `Ok("us-ascii")`, which was surprising — "no bytes" is not
  evidence of an encoding. Non-empty inputs whose encoding cannot
  be determined now return `Error(NoMatch)` (renamed from
  `Error(Nil)`).

### Removed

- **`essence(String) -> String` (BREAKING)** — replaced by
  `essence_of(MimeType) -> String`. Migration: parse the string
  first via `parse/1`, then call `essence_of` on the result.
- **`parameter(String, String) -> Result(String, _)` (BREAKING)** —
  replaced by `parameter_of(MimeType, String) -> Option(String)`.
  The error shape collapses from `DetectionError` to `Option`
  because `parse/1` now front-loads the validation.
- **`charset(String) -> Result(String, _)` (BREAKING)** — replaced
  by `charset_of_type(MimeType) -> Option(String)`. Same migration
  as `parameter`.

### Documentation

- README now describes the actual shallow ZIP-container inspection
  behavior. The previous wording incorrectly implied that ZIP-based
  Office-family formats were not distinguished at all.
- README's `detect_strict(<<>>)` example shows the new
  `Error(EmptyInput)` shape.
- README usage block rewritten to show the `MimeType` workflow:
  `to_string` for serialisation, `parse` for construction,
  `essence_of` / `is_image` / `charset_of_type` for inspection.

## [0.7.0] - 2026-04-28

### Changed

- **Reader (BREAKING)**: `Reader = fn(Int) -> Result(BitArray, String)`
  is now `Reader(read_error) = fn(Int) -> Result(BitArray, read_error)`.
  Generic `read_error` lets JS-side readers (FileReader,
  ReadableStream) and BEAM-side readers (file handles, HTTP clients)
  preserve their richer error shapes through `detect_reader_strict`
  instead of being collapsed to a stringly-typed placeholder.
- **detect_reader_strict (BREAKING)**: returns
  `Result(String, DetectionError(read_error))` instead of
  `Result(String, Nil)`. The new `DetectionError(e)` type has two
  variants: `NoMatch` (the reader produced bytes but no signature
  matched) and `ReaderError(e)` (the reader itself failed before
  any bytes could be inspected, carrying the reader's own error
  through unchanged). Callers can now distinguish a
  format-recognition failure from an upstream read failure — useful
  for HTTP upload pipelines that want to render "couldn't read the
  file" differently from "we don't recognise this format".
  Migration: the lenient `detect_reader/2` shape is unchanged
  (still returns `String`); call sites that previously matched
  `Error(Nil)` against `detect_reader_strict` switch to matching
  `Error(NoMatch)` or `Error(ReaderError(_))`. (#61, partial)

### Notes

- This is a partial fix toward #61: only the `Reader`-bearing path
  carries the new structured error. The other `*_strict` functions
  in the strict family (`extension_to_mime_type_strict`,
  `filename_to_mime_type_strict`, `detect_strict`,
  `detect_with_limit_strict`, `detect_signature_only`,
  `detect_with_extension_strict`, `detect_with_filename_strict`,
  `parameter`, `charset`, `charset_of`) still return
  `Result(_, Nil)`. Migrating those to a unified
  `DetectionError(_)` shape is its own follow-up because each one
  has a different "no useful answer" reason
  (`UnknownExtension(_)`, `EmptyInput`, …) that needs a separate
  modelling pass.

## [0.6.0] - 2026-04-28

### Fixed

- `detect_with_filename/2` and `detect_with_extension/2` now consult
  the filename / extension hint when the byte signature side only
  matched the printable-ASCII fallback. Previously the
  printable-ASCII heuristic was treated as a "match", so a `.csv`
  filename paired with CSV content returned `text/plain` and the
  filename hint was silently ignored — defeating the canonical use
  case ("I have an upload, here's a `.csv` filename hint, give me
  a sensible Content-Type"). Genuine binary or structural signatures
  (PNG, JPEG, ZIP, JSON / HTML / XML / SVG, BOM-tagged text, ...)
  still take priority over the filename hint. The printable-ASCII
  heuristic remains the last-resort fallback when neither the byte
  signature nor the filename's extension is recognisable. (#58)

### Added

- `detect_signature_only/1` and `detect_signature_only_with_limit/2`
  expose the "genuine signature only" detection path: real magic
  numbers and structural sniffs return `Ok(mime_type)`, plain-ASCII
  payloads return `Error(Nil)`. This is the building block behind
  the `detect_with_filename` / `detect_with_extension` fix above and
  is useful for callers that want to compose their own fallback
  shape against a stronger out-of-band hint. (#58)

## [0.5.0] - 2026-04-28

### Documentation

- `detect/1` and `detect_strict/1` docstrings now spell out the
  fallback contract: `detect/1` returns `"application/octet-stream"`
  (the value of `default_mime_type`) for any input with no recognisable
  magic bytes, including the empty `BitArray`, while `detect_strict/1`
  returns `Error(Nil)` for the same case so callers can tell "no
  signature found" from "signature found". The README's `detect`
  example block also shows the empty-input + `detect_strict/1` pair so
  the choice between the two surfaces near the first usage line. (#54)
- README correctly describes what the library does and does not sniff.
  The previous wording claimed `mimetype` "does not detect text encodings
  or sniff `text/plain` heuristically" and "does not currently expose
  dedicated charset or MIME-parameter parsing helpers" — both contradicted
  the printable-ASCII heuristic added in #20 and the four UTF-BOM
  signatures (which surface `text/plain; charset=utf-*`). The relevant
  bullets now describe the actual behaviour: bare `text/plain` for
  printable-ASCII payloads, `text/plain; charset=<utf-X>` for the four
  BOM signatures, and no other MIME-parameter parsing or text-encoding
  detection. (#53)

## [0.4.0] - 2026-04-27

### Changed

- Cache the Erlang FFI MIME-DB lookup tables via `persistent_term`. The
  previous implementation rebuilt the full ~900-entry `extension_to_mime_table`
  and `mime_type_to_extensions_table` maps on every call to
  `extension_to_mime_type/1` or `mime_type_to_extensions/1`, allocating fresh
  maps per invocation and adding GC pressure on hot paths (e.g.
  Content-Type detection per HTTP request). The tables are now built lazily on
  first access and reused for the lifetime of the VM. The JavaScript target
  was already module-level cached and is unchanged. (#48)

### Fixed

- Recognize MP4 files using ISO BMFF brands beyond the previously enumerated
  set (`isom`, `iso2`, `mp41`, `mp42`, `avc1`). Any input with `ftyp` at offset
  4 and a full 4-byte brand at offset 8 is now classified as `video/mp4`,
  unless a more specific signature matches first (`avif`/`avis` → `image/avif`,
  `heic`/`heix`/`hevc` → `image/heic`, `` M4A  ``/`` M4B  ``/`` M4P  `` →
  `audio/mp4`, `` qt   `` → `video/quicktime`). Brands such as `` M4V  ``,
  `` f4v  ``, `MSNV`, `NDAS`, `dash`, and `mp71` are no longer reported as
  `application/octet-stream`.
  (#49)

## [0.3.0] - 2026-04-27

### Added

- Add `Reader` type and `detect_reader`/`detect_reader_strict` functions for
  streaming MIME detection without loading entire files into memory. The reader
  callback is called once with the byte limit and the result is fed through
  the existing magic pipeline. (#27)
- Detect pre-2007 Microsoft Office binary formats via OLE Compound File Binary
  (CFB) header and UTF-16LE stream name scanning: `.doc` → `application/msword`,
  `.xls` → `application/vnd.ms-excel`, `.ppt` → `application/vnd.ms-powerpoint`.
  Unrecognized CFB files fall back to `application/x-ole-storage`. (#21)
- Detect ZIP-based container formats by inspecting local file header entry
  filenames: EPUB (`application/epub+zip`), DOCX/XLSX/PPTX (Office Open XML),
  JAR (`application/java-archive`), and APK
  (`application/vnd.android.package-archive`). Generic ZIP archives continue
  to return `application/zip`. (#16)

## [0.2.0] - 2026-04-26

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
- Add `charset_of(bytes) -> Result(String, Nil)` for character encoding
  detection of text payloads. Composes four signals in priority order:
  Unicode BOM, XML prolog `encoding="..."`, HTML
  `<meta charset="...">` (or `<meta http-equiv> content="; charset=..."`),
  and a UTF-8 validity scan. Returns `utf-8`, `us-ascii`, `utf-16le`,
  `utf-16be`, `utf-32le`, `utf-32be`, or whatever charset the in-document
  declaration specifies (e.g. `shift_jis`, `iso-8859-1`). Returns
  `Error(Nil)` for non-UTF-8 high-byte content with no declaration. (#29)
- Add a static MIME-type subtype tree and matching public predicates:
  `is_a(mime, parent)` (reflexive + transitive), `is_zip_based`,
  `is_xml_based`, and `ancestors`. Initial parent map covers OOXML
  (`docx`/`xlsx`/`pptx`), OpenDocument (`odt`/`ods`/`odp`), `epub`,
  `jar`, `apk` → `application/zip`; legacy MS Office (`doc`/`xls`/`ppt`)
  → `application/x-ole-storage`; and `image/svg+xml` → `text/xml`.
  Tree mirrors the design of Go's `gabriel-vasile/mimetype` (single
  parent per child). (#26)
- Add `detect_with_limit` and `detect_with_limit_strict` plus the
  `default_detection_limit = 3072` constant. Callers can now bound
  the number of leading bytes the detector inspects, matching the
  knob Go's `gabriel-vasile/mimetype` exposes via `SetLimit`. The
  existing `detect`/`detect_strict` continue to work and are now
  defined as `detect_with_limit(_, default_detection_limit)`. (#28)
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
