# Supported formats

<!-- BEGIN_SUPPORTED_FORMATS -->
`mimetype.detect` recognises these MIME types from the first 3072 bytes
of a file. The list is generated from `src/mimetype/internal/magic.gleam`;
run `just generate-formats` after adding or removing a signature.

## Application formats

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

## Audio formats

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

## Font formats

- `font/collection`
- `font/otf`
- `font/ttf`
- `font/woff`
- `font/woff2`

## Image formats

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

## Text formats

- `text/html`
- `text/plain`
- `text/plain; charset=utf-16be`
- `text/plain; charset=utf-16le`
- `text/plain; charset=utf-32be`
- `text/plain; charset=utf-32le`
- `text/plain; charset=utf-8`
- `text/xml`

## Video formats

- `video/mp4`
- `video/quicktime`
- `video/webm`
- `video/x-flv`
- `video/x-matroska`
- `video/x-msvideo`
<!-- END_SUPPORTED_FORMATS -->
