//// Content-based MIME detection.
////
//// `signatures` is tried in order and the first match wins. Every
//// check reads only the bytes it is given; the caller passes at most
//// the first 3072 bytes of a file.

import gleam/bit_array
import gleam/bool
import gleam/list
import gleam/result
import gleam/string
import mimetype/internal/charset

type Signature {
  /// Every `#(offset, bytes)` pair is present.
  Bytes(String, List(#(Int, BitArray)))
  /// A ZIP archive whose first entry is a stored file named `mimetype`
  /// that holds the type itself, as EPUB and OpenDocument require.
  StoredMimetype(String)
  /// A ZIP archive with, for each prefix, an entry whose name starts
  /// with it.
  ZipEntries(String, List(String))
  /// An OLE compound file with a stream named one of the names. With no
  /// names, any OLE compound file.
  OleStream(String, List(String))
  /// An EBML header whose DocType is the given name (Matroska, WebM).
  EbmlDocType(String, String)
  /// An ISO base media file whose `ftyp` major brand starts with one of
  /// the prefixes.
  FtypBrand(String, List(String))
  /// Any other test on the bytes.
  Check(String, fn(BitArray) -> Bool)
}

const signatures = [
  Bytes("audio/wav", [#(0, <<"RIFF":utf8>>), #(8, <<"WAVE":utf8>>)]),
  Bytes("video/x-msvideo", [#(0, <<"RIFF":utf8>>), #(8, <<"AVI ":utf8>>)]),
  Bytes("image/webp", [#(0, <<"RIFF":utf8>>), #(8, <<"WEBP":utf8>>)]),
  Bytes("audio/x-aiff", [#(0, <<"FORM":utf8>>), #(8, <<"AIFF":utf8>>)]),
  Bytes("image/png", [#(0, <<0x89, "PNG":utf8, 0x0D, 0x0A, 0x1A, 0x0A>>)]),
  Bytes("image/jpeg", [#(0, <<0xFF, 0xD8, 0xFF>>)]),
  Bytes("image/gif", [#(0, <<"GIF87a":utf8>>)]),
  Bytes("image/gif", [#(0, <<"GIF89a":utf8>>)]),
  // BITMAPFILEHEADER: the two reserved words after the file size are 0.
  Bytes("image/bmp", [#(0, <<"BM":utf8>>), #(6, <<0, 0, 0, 0>>)]),
  Bytes("image/tiff", [#(0, <<"II":utf8, 0x2A, 0x00>>)]),
  Bytes("image/tiff", [#(0, <<"MM":utf8, 0x00, 0x2A>>)]),
  Bytes("image/vnd.microsoft.icon", [#(0, <<0x00, 0x00, 0x01, 0x00>>)]),
  Bytes("image/x-icon", [#(0, <<0x00, 0x00, 0x02, 0x00>>)]),
  Bytes("image/vnd.adobe.photoshop", [#(0, <<"8BPS":utf8>>)]),
  // JPEG 2000 and the JPEG XL container start with a 12-byte signature box.
  Bytes(
    "image/jp2",
    [
      #(0, signature_box_size),
      #(4, <<"jP  ":utf8>>),
      #(8, signature_box_content),
    ],
  ),
  Bytes(
    "image/jxl",
    [
      #(0, signature_box_size),
      #(4, <<"JXL ":utf8>>),
      #(8, signature_box_content),
    ],
  ),
  Bytes("image/jxl", [#(0, <<0xFF, 0x0A>>)]),
  Bytes("image/vnd.ms-dds", [#(0, <<"DDS ":utf8>>)]),
  Bytes("image/vnd.radiance", [#(0, <<"#?RADIANCE":utf8, 0x0A>>)]),
  Bytes("image/x-exr", [#(0, <<0x76, 0x2F, 0x31, 0x01>>)]),
  Bytes("image/x-qoi", [#(0, <<"qoif":utf8>>)]),
  Bytes("image/fits", [#(0, <<"SIMPLE  =":utf8>>)]),
  Bytes("application/pdf", [#(0, <<"%PDF-":utf8>>)]),
  Bytes("application/pdf", [#(0, <<0x0A, "%PDF-":utf8>>)]),
  Bytes("application/pdf", [#(0, <<0xEF, 0xBB, 0xBF, "%PDF-":utf8>>)]),
  Bytes("application/postscript", [#(0, <<"%!PS-Adobe-":utf8>>)]),
  StoredMimetype("application/epub+zip"),
  StoredMimetype("application/vnd.oasis.opendocument.text"),
  StoredMimetype("application/vnd.oasis.opendocument.spreadsheet"),
  StoredMimetype("application/vnd.oasis.opendocument.presentation"),
  ZipEntries(
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    ["[Content_Types].xml", "word/"],
  ),
  ZipEntries(
    "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
    ["[Content_Types].xml", "xl/"],
  ),
  ZipEntries(
    "application/vnd.openxmlformats-officedocument.presentationml.presentation",
    ["[Content_Types].xml", "ppt/"],
  ),
  ZipEntries("application/java-archive", ["META-INF/MANIFEST.MF"]),
  ZipEntries("application/vnd.android.package-archive", ["AndroidManifest.xml"]),
  Bytes("application/zip", [#(0, zip_local_header)]),
  Bytes("application/zip", [#(0, <<"PK":utf8, 0x05, 0x06>>)]),
  Bytes("application/zip", [#(0, <<"PK":utf8, 0x07, 0x08>>)]),
  Bytes("application/gzip", [#(0, <<0x1F, 0x8B>>)]),
  Bytes("application/x-bzip2", [#(0, <<"BZh":utf8>>)]),
  Bytes("application/x-xz", [#(0, <<0xFD, "7zXZ":utf8, 0x00>>)]),
  Bytes("application/x-lz4", [#(0, <<0x04, 0x22, 0x4D, 0x18>>)]),
  Bytes("application/x-lz4", [#(0, <<0x02, 0x21, 0x4C, 0x18>>)]),
  Bytes("application/x-lzip", [#(0, <<"LZIP":utf8>>)]),
  Bytes(
    "application/x-snappy-framed",
    [
      #(0, <<0xFF, 0x06, 0x00, 0x00, "sNaPpY":utf8>>),
    ],
  ),
  Bytes("application/x-compress", [#(0, <<0x1F, 0x9D>>)]),
  Bytes("application/x-archive", [#(0, <<"!<arch>":utf8, 0x0A>>)]),
  // LZH: `??-lh?-`, where `?` is any byte.
  Bytes(
    "application/x-lzh-compressed",
    [
      #(2, <<"-lh":utf8>>),
      #(6, <<"-":utf8>>),
    ],
  ),
  Bytes(
    "application/x-7z-compressed",
    [
      #(0, <<"7z":utf8, 0xBC, 0xAF, 0x27, 0x1C>>),
    ],
  ),
  Bytes("application/vnd.rar", [#(0, <<"Rar!":utf8, 0x1A, 0x07, 0x00>>)]),
  Bytes("application/vnd.rar", [#(0, <<"Rar!":utf8, 0x1A, 0x07, 0x01, 0x00>>)]),
  // MS-CAB CFHEADER: the reserved field after the signature is 0.
  Bytes(
    "application/vnd.ms-cab-compressed",
    [
      #(0, <<"MSCF":utf8>>),
      #(4, <<0, 0, 0, 0>>),
    ],
  ),
  OleStream("application/msword", ["WordDocument"]),
  OleStream("application/vnd.ms-excel", ["Workbook", "Book"]),
  OleStream("application/vnd.ms-powerpoint", ["PowerPoint Document"]),
  OleStream("application/x-ole-storage", []),
  Bytes("application/wasm", [#(0, <<0x00, "asm":utf8>>)]),
  Bytes("application/x-elf", [#(0, <<0x7F, "ELF":utf8>>)]),
  Bytes("application/vnd.sqlite3", [#(0, <<"SQLite format 3":utf8, 0x00>>)]),
  Bytes("application/vnd.apache.parquet", [#(0, <<"PAR1":utf8>>)]),
  Bytes("font/otf", [#(0, <<"OTTO":utf8>>)]),
  Bytes("font/collection", [#(0, <<"ttcf":utf8>>)]),
  Bytes("font/woff", [#(0, <<"wOFF":utf8>>)]),
  Bytes("font/woff2", [#(0, <<"wOF2":utf8>>)]),
  Bytes(
    "application/vnd.ms-fontobject",
    [
      #(8, <<"LP":utf8>>),
      #(34, <<0x00, 0x00, 0x01>>),
    ],
  ),
  Bytes("font/ttf", [#(0, <<0x00, 0x01, 0x00, 0x00>>)]),
  // ID3v2: "ID3" and the major version, 2 to 4.
  Bytes("audio/mpeg", [#(0, <<"ID3":utf8, 0x02>>)]),
  Bytes("audio/mpeg", [#(0, <<"ID3":utf8, 0x03>>)]),
  Bytes("audio/mpeg", [#(0, <<"ID3":utf8, 0x04>>)]),
  // MPEG-1 Layer III and MPEG-2 Layer III frame sync, with and without CRC.
  Bytes("audio/mpeg", [#(0, <<0xFF, 0xFB>>)]),
  Bytes("audio/mpeg", [#(0, <<0xFF, 0xFA>>)]),
  Bytes("audio/mpeg", [#(0, <<0xFF, 0xF3>>)]),
  Bytes("audio/mpeg", [#(0, <<0xFF, 0xF2>>)]),
  // ADTS: 12 sync bits, then the layer bits, which are always 00.
  Bytes("audio/aac", [#(0, <<0xFF, 0xF1>>)]),
  Bytes("audio/aac", [#(0, <<0xFF, 0xF0>>)]),
  Bytes("audio/aac", [#(0, <<0xFF, 0xF9>>)]),
  Bytes("audio/aac", [#(0, <<0xFF, 0xF8>>)]),
  Bytes("audio/aac", [#(0, <<"ADIF":utf8>>)]),
  Bytes("audio/flac", [#(0, <<"fLaC":utf8, 0x00, 0x00, 0x00, 0x22>>)]),
  Bytes("audio/midi", [#(0, <<"MThd":utf8>>)]),
  Bytes("audio/amr", [#(0, <<"#!AMR":utf8, 0x0A>>)]),
  Bytes("audio/amr-wb", [#(0, <<"#!AMR-WB":utf8, 0x0A>>)]),
  Bytes("audio/ac3", [#(0, <<0x0B, 0x77>>)]),
  Bytes("application/ogg", [#(0, <<"OggS":utf8>>)]),
  Bytes(
    "application/vnd.ms-asf",
    [
      #(0, <<
        0x30, 0x26, 0xB2, 0x75, 0x8E, 0x66, 0xCF, 0x11, 0xA6, 0xD9, 0x00, 0xAA,
        0x00, 0x62, 0xCE, 0x6C,
      >>),
    ],
  ),
  Bytes("video/x-flv", [#(0, <<"FLV":utf8, 0x01>>)]),
  EbmlDocType("video/matroska", "matroska"),
  EbmlDocType("video/webm", "webm"),
  Check("application/zstd", has_zstd_frame),
  Bytes("application/x-tar", [#(257, <<"ustar":utf8>>)]),
  // ISO/IEC 23008-12 brands, then the audio-only MP4 brands, then 3GPP2
  // before 3GPP because "3g2" also starts with "3g".
  FtypBrand("image/avif", ["avif", "avis"]),
  FtypBrand("image/heic", ["heic", "heix"]),
  FtypBrand("image/heic-sequence", ["hevc", "hevx"]),
  FtypBrand("image/heif", ["mif1"]),
  FtypBrand("image/heif-sequence", ["msf1"]),
  FtypBrand("audio/mp4", ["M4A ", "M4B ", "M4P ", "F4A ", "F4B ", "NDAS"]),
  FtypBrand("video/quicktime", ["qt  "]),
  FtypBrand("video/3gpp2", ["3g2"]),
  FtypBrand("video/3gpp", ["3g"]),
  // Every other brand (isom, mp41, mp42, M4V, f4v, dash, ...).
  FtypBrand("video/mp4", [""]),
  Check("application/rtf", looks_like_rtf),
  Check("application/json", looks_like_json),
  // SVG first: an SVG file often starts with a comment.
  Check("image/svg+xml", looks_like_svg),
  Check("text/html", looks_like_html),
  Check("application/xml", looks_like_xml),
  // RFC 1950: CMF 0x78 (deflate, 32K window) and one of the four FLG
  // bytes that make CMF * 256 + FLG a multiple of 31. `x^` also starts
  // ordinary text, so a binary data byte has to follow.
  Check("application/zlib", looks_like_zlib),
  Bytes("text/plain; charset=utf-32le", [#(0, <<0xFF, 0xFE, 0x00, 0x00>>)]),
  Bytes("text/plain; charset=utf-32be", [#(0, <<0x00, 0x00, 0xFE, 0xFF>>)]),
  Bytes("text/plain; charset=utf-16le", [#(0, <<0xFF, 0xFE>>)]),
  Bytes("text/plain; charset=utf-16be", [#(0, <<0xFE, 0xFF>>)]),
  Bytes("text/plain; charset=utf-8", [#(0, <<0xEF, 0xBB, 0xBF>>)]),
]

const signature_box_size = <<0x00, 0x00, 0x00, 0x0C>>

const signature_box_content = <<0x0D, 0x0A, 0x87, 0x0A>>

const zip_local_header = <<"PK":utf8, 0x03, 0x04>>

/// Returns the type of the first signature that matches, or `text/plain`
/// when none does and the bytes look like text.
pub fn detect(bytes: BitArray) -> Result(String, Nil) {
  use <- result.lazy_or(detect_signature(bytes))
  case looks_like_text(bytes) {
    True -> Ok("text/plain")
    False -> Error(Nil)
  }
}

/// Returns the type of the first signature that matches, without the
/// `text/plain` fallback.
pub fn detect_signature(bytes: BitArray) -> Result(String, Nil) {
  list.find_map(signatures, fn(signature) {
    case matches(bytes, signature) {
      True -> Ok(mime_type(signature))
      False -> Error(Nil)
    }
  })
}

fn mime_type(signature: Signature) -> String {
  case signature {
    Bytes(mime_type, _)
    | StoredMimetype(mime_type)
    | ZipEntries(mime_type, _)
    | OleStream(mime_type, _)
    | EbmlDocType(mime_type, _)
    | FtypBrand(mime_type, _)
    | Check(mime_type, _) -> mime_type
  }
}

fn matches(bytes: BitArray, signature: Signature) -> Bool {
  case signature {
    Bytes(_, segments) ->
      list.all(segments, fn(segment) {
        has_bytes_at(bytes, segment.0, segment.1)
      })
    StoredMimetype(mime_type) ->
      has_bytes_at(bytes, 0, zip_local_header)
      && has_bytes_at(bytes, 30, <<"mimetype":utf8, mime_type:utf8>>)
    ZipEntries(_, prefixes) -> {
      let names = zip_entry_names(bytes, 0, zip_entry_budget, [])
      list.all(prefixes, fn(prefix) {
        list.any(names, string.starts_with(_, prefix))
      })
    }
    OleStream(_, names) ->
      has_bytes_at(bytes, 0, ole_header)
      && {
        names == []
        || list.any(names, fn(name) {
          contains(bytes, utf16le(name), bit_array.byte_size(bytes))
        })
      }
    // The DocType element: ID 0x4282, a one-byte size, the name.
    EbmlDocType(_, doc_type) ->
      has_bytes_at(bytes, 0, ebml_header)
      && contains(
        bytes,
        <<0x42, 0x82, { 0x80 + string.byte_size(doc_type) }, doc_type:utf8>>,
        ebml_search_window,
      )
    FtypBrand(_, prefixes) ->
      bit_array.byte_size(bytes) >= 12
      && has_bytes_at(bytes, 4, <<"ftyp":utf8>>)
      && list.any(prefixes, fn(prefix) {
        has_bytes_at(bytes, 8, <<prefix:utf8>>)
      })
    Check(_, predicate) -> predicate(bytes)
  }
}

fn has_bytes_at(bytes: BitArray, offset: Int, prefix: BitArray) -> Bool {
  bit_array.slice(bytes, offset, bit_array.byte_size(prefix)) == Ok(prefix)
}

// Whether `literal` starts at one of the first `within` offsets.
fn contains(bytes: BitArray, literal: BitArray, within: Int) -> Bool {
  use <- bool.guard(when: within <= 0, return: False)
  use <- bool.guard(when: has_bytes_at(bytes, 0, literal), return: True)
  case bytes {
    <<_, rest:bytes>> -> contains(rest, literal, within - 1)
    _ -> False
  }
}

fn drop(bytes: BitArray, count: Int) -> BitArray {
  bit_array.slice(bytes, count, bit_array.byte_size(bytes) - count)
  |> result.unwrap(<<>>)
}

const ole_header = <<0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1>>

const ebml_header = <<0x1A, 0x45, 0xDF, 0xA3>>

const ebml_search_window = 256

// OLE stream names are stored in UTF-16LE.
fn utf16le(name: String) -> BitArray {
  string.to_utf_codepoints(name)
  |> list.map(fn(codepoint) {
    <<string.utf_codepoint_to_int(codepoint):16-little>>
  })
  |> bit_array.concat
}

fn has_zstd_frame(bytes: BitArray) -> Bool {
  case bytes {
    // Zstandard frame magic 0xFD2FB528, for format versions 0.2 to 0.8.
    <<first, 0xB5, 0x2F, 0xFD, _:bits>> -> first >= 0x22 && first <= 0x28
    // Skippable frame magic 0x184D2A50 to 0x184D2A5F.
    <<first, 0x2A, 0x4D, 0x18, _:bits>> -> first >= 0x50 && first <= 0x5F
    _ -> False
  }
}

// RTF documents start with `{\rtfN`, N being the version digit.
fn looks_like_rtf(bytes: BitArray) -> Bool {
  case bytes {
    <<"{\\rtf":utf8, version, _:bits>> -> version >= 0x30 && version <= 0x39
    _ -> False
  }
}

// ---------------------------------------------------------------------------
// ZIP
// ---------------------------------------------------------------------------

// Local file header: signature (4), version, flags, method, time, date
// and CRC (14), compressed size (4), uncompressed size (4), name length
// (2), extra field length (2), then the name. The next header follows
// the name, the extra field and the compressed data.
const zip_entry_budget = 20

fn zip_entry_names(
  bytes: BitArray,
  offset: Int,
  budget: Int,
  names: List(String),
) -> List(String) {
  use <- bool.guard(when: budget <= 0, return: names)
  case bit_array.slice(bytes, offset, 30) {
    Ok(<<
      0x50,
      0x4B,
      0x03,
      0x04,
      _:bytes-size(14),
      size:32-little,
      _:bytes-size(4),
      name_size:16-little,
      extra_size:16-little,
    >>)
      if name_size > 0
    ->
      case bit_array.slice(bytes, offset + 30, name_size) {
        Ok(name) ->
          zip_entry_names(
            bytes,
            offset + 30 + name_size + extra_size + size,
            budget - 1,
            [bit_array.to_string(name) |> result.unwrap(""), ..names],
          )
        Error(Nil) -> names
      }
    _ -> names
  }
}

// ---------------------------------------------------------------------------
// JSON
// ---------------------------------------------------------------------------

// Only an object or an array at the top level counts: a bare number or
// string would match ordinary text. After the value only whitespace may
// follow (RFC 8259: JSON-text = ws value ws). A value that the end of the
// input cuts short still counts, because the caller passes only the first
// 3072 bytes of a file.

type Json {
  Valid(rest: BitArray)
  Truncated
  Invalid
}

// Containers nested deeper than this are not treated as JSON, which
// keeps the recursion bounded on every target.
const json_max_depth = 256

fn looks_like_json(bytes: BitArray) -> Bool {
  let bytes = bytes |> charset.strip_utf8_bom |> json_skip_ws
  case bytes {
    <<"{":utf8, _:bits>> | <<"[":utf8, _:bits>> ->
      case json_value(bytes, 0) {
        Valid(rest) -> json_skip_ws(rest) == <<>>
        Truncated -> True
        Invalid -> False
      }
    _ -> False
  }
}

fn json_skip_ws(bytes: BitArray) -> BitArray {
  case bytes {
    <<0x20, rest:bits>>
    | <<0x09, rest:bits>>
    | <<0x0A, rest:bits>>
    | <<0x0D, rest:bits>> -> json_skip_ws(rest)
    _ -> bytes
  }
}

fn json_then(result: Json, next: fn(BitArray) -> Json) -> Json {
  case result {
    Valid(rest) -> next(rest)
    Truncated -> Truncated
    Invalid -> Invalid
  }
}

fn json_value(bytes: BitArray, depth: Int) -> Json {
  use <- bool.guard(when: depth >= json_max_depth, return: Invalid)
  let bytes = json_skip_ws(bytes)
  case bytes {
    <<>> -> Truncated
    <<"{":utf8, rest:bits>> ->
      json_container(rest, 0x7D, True, json_member(_, depth + 1))
    <<"[":utf8, rest:bits>> ->
      json_container(rest, 0x5D, True, json_value(_, depth + 1))
    <<"\"":utf8, rest:bits>> -> json_string(rest)
    <<"true":utf8, rest:bits>>
    | <<"false":utf8, rest:bits>>
    | <<"null":utf8, rest:bits>> -> Valid(rest)
    <<"t":utf8, rest:bits>> -> json_literal_prefix(rest, <<"rue":utf8>>)
    <<"f":utf8, rest:bits>> -> json_literal_prefix(rest, <<"alse":utf8>>)
    <<"n":utf8, rest:bits>> -> json_literal_prefix(rest, <<"ull":utf8>>)
    <<"-":utf8, rest:bits>> -> json_number(rest, True)
    <<digit, _:bits>> if digit >= 0x30 && digit <= 0x39 ->
      json_number(bytes, True)
    _ -> Invalid
  }
}

// `close` ends the container; `member` reads one element.
fn json_container(
  bytes: BitArray,
  close: Int,
  first: Bool,
  member: fn(BitArray) -> Json,
) -> Json {
  let bytes = json_skip_ws(bytes)
  case bytes {
    <<>> -> Truncated
    <<byte, rest:bits>> if first && byte == close -> Valid(rest)
    _ -> {
      use rest <- json_then(member(bytes))
      case json_skip_ws(rest) {
        <<>> -> Truncated
        <<",":utf8, rest:bits>> -> json_container(rest, close, False, member)
        <<byte, rest:bits>> if byte == close -> Valid(rest)
        _ -> Invalid
      }
    }
  }
}

fn json_member(bytes: BitArray, depth: Int) -> Json {
  case bytes {
    <<"\"":utf8, rest:bits>> -> {
      use rest <- json_then(json_string(rest))
      case json_skip_ws(rest) {
        <<>> -> Truncated
        <<":":utf8, rest:bits>> -> json_value(rest, depth)
        _ -> Invalid
      }
    }
    _ -> Invalid
  }
}

fn json_string(bytes: BitArray) -> Json {
  case bytes {
    <<>> | <<"\\":utf8>> -> Truncated
    <<"\"":utf8, rest:bits>> -> Valid(rest)
    <<"\\":utf8, _, rest:bits>> -> json_string(rest)
    <<_, rest:bits>> -> json_string(rest)
    _ -> Invalid
  }
}

// Reads the rest of a number loosely: digits, `.`, `e`, `E`, `+`, `-`.
fn json_number(bytes: BitArray, first: Bool) -> Json {
  case bytes {
    <<>> -> Truncated
    <<byte, rest:bits>>
      if { byte >= 0x30 && byte <= 0x39 }
      || byte == 0x2E
      || byte == 0x65
      || byte == 0x45
      || byte == 0x2B
      || byte == 0x2D
    -> json_number(rest, False)
    _ if first -> Invalid
    _ -> Valid(bytes)
  }
}

// The input ends partway through `literal`. A complete literal was
// matched before this is called.
fn json_literal_prefix(bytes: BitArray, literal: BitArray) -> Json {
  let prefix = bit_array.slice(literal, 0, bit_array.byte_size(bytes))
  use <- bool.guard(when: prefix != Ok(bytes), return: Invalid)
  Truncated
}

// ---------------------------------------------------------------------------
// HTML, XML and SVG
// ---------------------------------------------------------------------------

// The HTML patterns of WHATWG MIME Sniffing, compared without regard to
// ASCII case. Each has to be followed by a tag-terminating byte.
const html_patterns = [
  <<"<!doctype html":utf8>>,
  <<"<html":utf8>>,
  <<"<head":utf8>>,
  <<"<script":utf8>>,
  <<"<iframe":utf8>>,
  <<"<h1":utf8>>,
  <<"<div":utf8>>,
  <<"<font":utf8>>,
  <<"<table":utf8>>,
  <<"<a":utf8>>,
  <<"<style":utf8>>,
  <<"<title":utf8>>,
  <<"<b":utf8>>,
  <<"<body":utf8>>,
  <<"<br":utf8>>,
  <<"<p":utf8>>,
]

// WHATWG MIME Sniffing also lists `<!--`. Markdown and other text files
// often start with a comment, so here a comment counts only when an HTML
// pattern follows it.
fn looks_like_html(bytes: BitArray) -> Bool {
  let bytes = trim_text_prefix(bytes)
  use <- bool.lazy_guard(
    when: has_bytes_at(bytes, 0, <<"<!--":utf8>>),
    return: fn() { looks_like_html(skip_past(drop(bytes, 4), <<"-->":utf8>>)) },
  )
  list.any(html_patterns, fn(pattern) {
    case drop_ascii_case_insensitive(bytes, pattern) {
      Ok(rest) -> is_tag_terminator(rest)
      Error(Nil) -> False
    }
  })
}

// WHATWG MIME Sniffing: the bytes `<?xml`.
fn looks_like_xml(bytes: BitArray) -> Bool {
  has_bytes_at(trim_text_prefix(bytes), 0, <<"<?xml":utf8>>)
}

// An `<svg` root element after any XML declaration, comments and
// DOCTYPE. XML names are case-sensitive, so `<SVG>` is not SVG.
fn looks_like_svg(bytes: BitArray) -> Bool {
  case bytes |> trim_text_prefix |> skip_prolog {
    <<"<svg":utf8, rest:bits>> ->
      case rest {
        <<"/":utf8, _:bits>> -> True
        _ -> is_tag_terminator(rest)
      }
    _ -> False
  }
}

fn skip_prolog(bytes: BitArray) -> BitArray {
  let bytes = charset.skip_whitespace(bytes)
  case bytes {
    <<"<?xml":utf8, rest:bits>> ->
      rest |> skip_past(<<"?>":utf8>>) |> skip_prolog
    <<"<!--":utf8, rest:bits>> ->
      rest |> skip_past(<<"-->":utf8>>) |> skip_prolog
    <<"<!DOCTYPE":utf8, rest:bits>> ->
      rest |> skip_past(<<">":utf8>>) |> skip_prolog
    _ -> bytes
  }
}

// Drops everything up to and including `literal`, or everything when it
// does not occur.
fn skip_past(bytes: BitArray, literal: BitArray) -> BitArray {
  case has_bytes_at(bytes, 0, literal), bytes {
    True, _ -> drop(bytes, bit_array.byte_size(literal))
    False, <<_, rest:bytes>> -> skip_past(rest, literal)
    False, _ -> <<>>
  }
}

fn looks_like_zlib(bytes: BitArray) -> Bool {
  case bytes {
    <<0x78, flags, _:bits>> ->
      { flags == 0x01 || flags == 0x5E || flags == 0x9C || flags == 0xDA }
      && charset.has_binary_data_byte(bytes)
    _ -> False
  }
}

fn trim_text_prefix(bytes: BitArray) -> BitArray {
  bytes |> charset.strip_utf8_bom |> charset.skip_whitespace
}

// Whitespace or `>`. WHATWG names only space and `>`; the other HTML
// whitespace bytes are accepted too, since `<html\n` is common.
fn is_tag_terminator(bytes: BitArray) -> Bool {
  case bytes {
    <<byte, _:bits>> ->
      byte == 0x20
      || byte == 0x09
      || byte == 0x0A
      || byte == 0x0C
      || byte == 0x0D
      || byte == 0x3E
    _ -> False
  }
}

// Drops `prefix`, a lowercase pattern, from the start of `bytes`,
// comparing ASCII letters without regard to case.
fn drop_ascii_case_insensitive(
  bytes: BitArray,
  prefix: BitArray,
) -> Result(BitArray, Nil) {
  case prefix, bytes {
    <<>>, _ -> Ok(bytes)
    <<expected, prefix:bits>>, <<byte, bytes:bits>> ->
      case
        byte == expected
        || byte + 0x20 == expected
        && byte >= 0x41
        && byte <= 0x5A
      {
        True -> drop_ascii_case_insensitive(bytes, prefix)
        False -> Error(Nil)
      }
    _, _ -> Error(Nil)
  }
}

// ---------------------------------------------------------------------------
// Text
// ---------------------------------------------------------------------------

// WHATWG MIME Sniffing: a resource is binary when it holds a binary data
// byte. Every byte is checked.
fn looks_like_text(bytes: BitArray) -> Bool {
  !charset.has_binary_data_byte(bytes)
}
