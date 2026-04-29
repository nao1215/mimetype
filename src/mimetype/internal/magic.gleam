//// Internal content-based MIME detection.
////
//// The signatures below are intentionally limited to byte checks that
//// can be evaluated portably on both the Erlang and JavaScript
//// targets. Ordering is significant: the first matching signature wins.

import gleam/bit_array
import gleam/bool
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

type Signature {
  Bytes(String, List(#(Int, BitArray)))
  Check(String, fn(BitArray) -> Bool)
}

const signatures = [
  Bytes("audio/wav", [#(0, <<"RIFF":utf8>>), #(8, <<"WAVE":utf8>>)]),
  Bytes("video/x-msvideo", [#(0, <<"RIFF":utf8>>), #(8, <<"AVI ":utf8>>)]),
  Bytes("image/webp", [#(0, <<"RIFF":utf8>>), #(8, <<"WEBP":utf8>>)]),
  Bytes("audio/aiff", [#(0, <<"FORM":utf8>>), #(8, <<"AIFF":utf8>>)]),
  Bytes("image/png", [#(0, <<0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A>>)]),
  Bytes("image/jpeg", [#(0, <<0xFF, 0xD8, 0xFF>>)]),
  Bytes("image/gif", [#(0, <<"GIF87a":utf8>>)]),
  Bytes("image/gif", [#(0, <<"GIF89a":utf8>>)]),
  Bytes("image/bmp", [#(0, <<"BM":utf8>>)]),
  Bytes("image/tiff", [#(0, <<0x49, 0x49, 0x2A, 0x00>>)]),
  Bytes("image/tiff", [#(0, <<0x4D, 0x4D, 0x00, 0x2A>>)]),
  Bytes("image/x-icon", [#(0, <<0x00, 0x00, 0x01, 0x00>>)]),
  Bytes("image/x-icon", [#(0, <<0x00, 0x00, 0x02, 0x00>>)]),
  Bytes("image/vnd.adobe.photoshop", [#(0, <<0x38, 0x42, 0x50, 0x53>>)]),
  Bytes(
    "image/jp2",
    [
      #(
        0,
        <<
          0x00,
          0x00,
          0x00,
          0x0C,
          0x6A,
          0x50,
          0x20,
          0x20,
          0x0D,
          0x0A,
          0x87,
          0x0A,
        >>,
      ),
    ],
  ),
  Bytes(
    "image/jxl",
    [
      #(
        0,
        <<
          0x00,
          0x00,
          0x00,
          0x0C,
          0x4A,
          0x58,
          0x4C,
          0x20,
          0x0D,
          0x0A,
          0x87,
          0x0A,
        >>,
      ),
    ],
  ),
  Bytes("image/jxl", [#(0, <<0xFF, 0x0A>>)]),
  Bytes("image/vnd.ms-dds", [#(0, <<"DDS ":utf8>>)]),
  Bytes("image/vnd.radiance", [#(0, <<"#?RADIANCE":utf8, 0x0A>>)]),
  Bytes("image/x-exr", [#(0, <<0x76, 0x2F, 0x31, 0x01>>)]),
  Bytes("image/x-qoi", [#(0, <<"qoif":utf8>>)]),
  Bytes("image/fits", [#(0, <<"SIMPLE  =":utf8>>)]),
  Bytes("application/pdf", [#(0, <<0x25, 0x50, 0x44, 0x46, 0x2D>>)]),
  Bytes("application/pdf", [#(0, <<0x0A, 0x25, 0x50, 0x44, 0x46, 0x2D>>)]),
  Bytes(
    "application/pdf",
    [#(0, <<0xEF, 0xBB, 0xBF, 0x25, 0x50, 0x44, 0x46, 0x2D>>)],
  ),
  Check("application/epub+zip", looks_like_epub),
  Check("application/vnd.oasis.opendocument.text", looks_like_odt),
  Check("application/vnd.oasis.opendocument.spreadsheet", looks_like_ods),
  Check("application/vnd.oasis.opendocument.presentation", looks_like_odp),
  Check(
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    looks_like_docx,
  ),
  Check(
    "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
    looks_like_xlsx,
  ),
  Check(
    "application/vnd.openxmlformats-officedocument.presentationml.presentation",
    looks_like_pptx,
  ),
  Check("application/java-archive", looks_like_jar),
  Check("application/vnd.android.package-archive", looks_like_apk),
  Bytes("application/zip", [#(0, <<0x50, 0x4B, 0x03, 0x04>>)]),
  Bytes("application/zip", [#(0, <<0x50, 0x4B, 0x05, 0x06>>)]),
  Bytes("application/zip", [#(0, <<0x50, 0x4B, 0x07, 0x08>>)]),
  Bytes("application/gzip", [#(0, <<0x1F, 0x8B>>)]),
  Bytes("application/x-bzip2", [#(0, <<0x42, 0x5A, 0x68>>)]),
  Bytes("application/x-xz", [#(0, <<0xFD, 0x37, 0x7A, 0x58, 0x5A, 0x00>>)]),
  Bytes("application/x-lz4", [#(0, <<0x04, 0x22, 0x4D, 0x18>>)]),
  Bytes("application/x-lz4", [#(0, <<0x02, 0x21, 0x4C, 0x18>>)]),
  Bytes("application/x-lzip", [#(0, <<"LZIP":utf8>>)]),
  Bytes(
    "application/x-snappy-framed",
    [#(0, <<0xFF, 0x06, 0x00, 0x00, 0x73, 0x4E, 0x61, 0x50, 0x70, 0x59>>)],
  ),
  Bytes("application/x-compress", [#(0, <<0x1F, 0x9D>>)]),
  Bytes("application/x-archive", [#(0, <<"!<arch>":utf8, 0x0A>>)]),
  Check("application/x-lzh-compressed", has_lzh_magic),
  Bytes(
    "application/x-7z-compressed",
    [#(0, <<0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C>>)],
  ),
  Bytes(
    "application/x-rar-compressed",
    [#(0, <<0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x00>>)],
  ),
  Bytes(
    "application/x-rar-compressed",
    [#(0, <<0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x01, 0x00>>)],
  ),
  Bytes("application/vnd.ms-cab-compressed", [#(0, <<0x4D, 0x53, 0x43, 0x46>>)]),
  Check("application/msword", looks_like_ole_word),
  Check("application/vnd.ms-excel", looks_like_ole_excel),
  Check("application/vnd.ms-powerpoint", looks_like_ole_powerpoint),
  Check("application/x-ole-storage", looks_like_ole_cfb),
  Bytes("application/wasm", [#(0, <<0x00, 0x61, 0x73, 0x6D>>)]),
  Bytes("application/x-elf", [#(0, <<0x7F, 0x45, 0x4C, 0x46>>)]),
  Bytes(
    "application/vnd.sqlite3",
    [
      #(
        0,
        <<
          0x53,
          0x51,
          0x4C,
          0x69,
          0x74,
          0x65,
          0x20,
          0x66,
          0x6F,
          0x72,
          0x6D,
          0x61,
          0x74,
          0x20,
          0x33,
          0x00,
        >>,
      ),
    ],
  ),
  Bytes("application/vnd.apache.parquet", [#(0, <<0x50, 0x41, 0x52, 0x31>>)]),
  Bytes("font/otf", [#(0, <<"OTTO":utf8>>)]),
  Bytes("font/collection", [#(0, <<"ttcf":utf8>>)]),
  Bytes("font/woff", [#(0, <<"wOFF":utf8>>)]),
  Bytes("font/woff2", [#(0, <<"wOF2":utf8>>)]),
  Bytes(
    "application/vnd.ms-fontobject",
    [#(8, <<"LP":utf8>>), #(34, <<0x00, 0x00, 0x01>>)],
  ),
  Bytes("font/ttf", [#(0, <<0x00, 0x01, 0x00, 0x00>>)]),
  Bytes("audio/mpeg", [#(0, <<"ID3":utf8>>)]),
  Check("audio/mpeg", has_mp3_frame_sync),
  Check("audio/aac", has_aac_adts_sync),
  Bytes("audio/aac", [#(0, <<"ADIF":utf8>>)]),
  Bytes(
    "audio/flac",
    [#(0, <<0x66, 0x4C, 0x61, 0x43, 0x00, 0x00, 0x00, 0x22>>)],
  ),
  Bytes("audio/midi", [#(0, <<0x4D, 0x54, 0x68, 0x64>>)]),
  Bytes("audio/amr", [#(0, <<"#!AMR":utf8, 0x0A>>)]),
  Bytes("audio/amr-wb", [#(0, <<"#!AMR-WB":utf8, 0x0A>>)]),
  Bytes("audio/ac3", [#(0, <<0x0B, 0x77>>)]),
  Bytes("application/ogg", [#(0, <<0x4F, 0x67, 0x67, 0x53>>)]),
  Bytes(
    "application/vnd.ms-asf",
    [
      #(
        0,
        <<
          0x30, 0x26, 0xB2, 0x75, 0x8E, 0x66, 0xCF, 0x11, 0xA6, 0xD9, 0x00, 0xAA,
          0x00, 0x62, 0xCE, 0x6C,
        >>,
      ),
    ],
  ),
  Bytes("video/x-flv", [#(0, <<"FLV":utf8, 0x01>>)]),
  Check("video/x-matroska", looks_like_matroska),
  Check("video/webm", looks_like_webm),
  Check("application/zstd", has_zstd_frame),
  Bytes("application/x-tar", [#(257, <<"ustar":utf8>>)]),
  Bytes("image/avif", [#(4, <<"ftyp":utf8>>), #(8, <<"avif":utf8>>)]),
  Bytes("image/avif", [#(4, <<"ftyp":utf8>>), #(8, <<"avis":utf8>>)]),
  Bytes("image/heic", [#(4, <<"ftyp":utf8>>), #(8, <<"heic":utf8>>)]),
  Bytes("image/heic", [#(4, <<"ftyp":utf8>>), #(8, <<"heix":utf8>>)]),
  Bytes("image/heic", [#(4, <<"ftyp":utf8>>), #(8, <<"hevc":utf8>>)]),
  Bytes("audio/mp4", [#(4, <<"ftyp":utf8>>), #(8, <<"M4A ":utf8>>)]),
  Bytes("audio/mp4", [#(4, <<"ftyp":utf8>>), #(8, <<"M4B ":utf8>>)]),
  Bytes("audio/mp4", [#(4, <<"ftyp":utf8>>), #(8, <<"M4P ":utf8>>)]),
  Bytes("video/quicktime", [#(4, <<"ftyp":utf8>>), #(8, <<"qt  ":utf8>>)]),
  Check("video/mp4", looks_like_iso_bmff_video),
  Check("application/json", looks_like_json),
  Check("text/html", looks_like_html),
  Check("image/svg+xml", looks_like_svg),
  Check("text/xml", looks_like_xml),
  Check("application/x-deflate", has_zlib_magic),
  Bytes("text/plain; charset=utf-32le", [#(0, <<0xFF, 0xFE, 0x00, 0x00>>)]),
  Bytes("text/plain; charset=utf-32be", [#(0, <<0x00, 0x00, 0xFE, 0xFF>>)]),
  Bytes("text/plain; charset=utf-16le", [#(0, <<0xFF, 0xFE>>)]),
  Bytes("text/plain; charset=utf-16be", [#(0, <<0xFE, 0xFF>>)]),
  Bytes("text/plain; charset=utf-8", [#(0, <<0xEF, 0xBB, 0xBF>>)]),
  Check("text/plain", looks_like_plain_text),
]

/// Try to recognize a MIME type from a leading byte signature.
///
/// Returns `Some(mime_type)` when a known signature matches and `None`
/// otherwise.
pub fn detect(bytes: BitArray) -> Option(String) {
  case signatures |> list.find_map(detect_match(bytes, _)) {
    Ok(mime_type) -> Some(mime_type)
    Error(Nil) -> None
  }
}

/// Like `detect` but excludes the printable-ASCII heuristic.
///
/// Returns `Some(mime_type)` only for genuine signature matches: byte
/// magic numbers (PNG, JPEG, ZIP, ...) and structural sniffs that
/// inspect bytes (JSON, HTML, XML, SVG). Returns `None` for plain-ASCII
/// payloads where `detect` would have returned `Some("text/plain")`.
pub fn detect_signature(bytes: BitArray) -> Option(String) {
  let result =
    signatures
    |> list.filter(fn(signature) { !is_printable_ascii_fallback(signature) })
    |> list.find_map(detect_match(bytes, _))
  case result {
    Ok(mime_type) -> Some(mime_type)
    Error(Nil) -> None
  }
}

// The printable-ASCII fallback is the only `Check("text/plain", _)`
// entry in `signatures`: every other `text/plain` entry uses `Bytes`
// to match a specific BOM. Filtering on this shape keeps
// `detect_signature` from accepting plain-ASCII text as a "real"
// signature match while still returning the BOM-tagged variants.
fn is_printable_ascii_fallback(signature: Signature) -> Bool {
  case signature {
    Check("text/plain", _) -> True
    _ -> False
  }
}

fn detect_match(bytes: BitArray, signature: Signature) -> Result(String, Nil) {
  let mime_type = signature_mime_type(signature)

  use <- bool.guard(
    when: matches_signature(bytes, signature),
    return: Ok(mime_type),
  )

  Error(Nil)
}

fn signature_mime_type(signature: Signature) -> String {
  case signature {
    Bytes(mime_type, _) -> mime_type
    Check(mime_type, _) -> mime_type
  }
}

fn matches_signature(bytes: BitArray, signature: Signature) -> Bool {
  case signature {
    Bytes(_, segments) ->
      list.all(segments, fn(segment) {
        let #(offset, pattern) = segment
        has_bytes_at(bytes, offset, pattern)
      })
    Check(_, predicate) -> predicate(bytes)
  }
}

fn has_mp3_frame_sync(bytes: BitArray) -> Bool {
  case bytes {
    <<0xFF, second:size(8), _:bits>>
      if second == 0xFB || second == 0xFA || second == 0xF3 || second == 0xF2
    -> True
    _ -> False
  }
}

fn has_zstd_frame(bytes: BitArray) -> Bool {
  case bytes {
    <<first:size(8), 0xB5, 0x2F, 0xFD, _:bits>>
      if first >= 0x22 && first <= 0x28
    -> True
    <<first:size(8), 0x2A, 0x4D, 0x18, _:bits>>
      if first >= 0x50 && first <= 0x5F
    -> True
    _ -> False
  }
}

// ISO Base Media File Format catch-all for `video/mp4`.
//
// Reached only after the specific ftyp brand signatures (avif/avis, heic/heix/
// hevc, M4A/M4B/M4P, qt) have been tried and missed. Any remaining file with
// `ftyp` at offset 4 and a full 4-byte brand at offset 8 is treated as
// `video/mp4` rather than rejected, so brands like `M4V `, `f4v `, `MSNV`,
// `NDAS`, `dash`, `mp71`, etc. are no longer reported as
// `application/octet-stream`.
fn looks_like_iso_bmff_video(bytes: BitArray) -> Bool {
  has_bytes_at(bytes, 4, <<"ftyp":utf8>>) && bit_array.byte_size(bytes) >= 12
}

fn has_bytes_at(bytes: BitArray, offset: Int, prefix: BitArray) -> Bool {
  let prefix_size = bit_array.byte_size(prefix)
  case offset < 0 || bit_array.byte_size(bytes) < offset + prefix_size {
    True -> False
    False ->
      bit_array.slice(bytes, offset, prefix_size) |> result.unwrap(<<>>)
      == prefix
  }
}

// JSON sniffing: recognize `application/json` from leading bytes.
//
// Detection scope (top level): only `{...}` and `[...]` are sniffed. Bare
// scalars (numbers, strings, `true`/`false`/`null`) at the top level are
// rejected because they false-positive on plain text. Inside containers,
// numbers and the literals are accepted as element values.
//
// Truncated input (e.g. `{"a": 1`) is accepted as JSON: structural validity
// of the prefix is sufficient for sniffing. Junk after `{` (e.g.
// `{ this is not json }`) is rejected because the object body requires `"`
// or `}` after whitespace.
//
// Walking is bounded by `json_sniff_budget` so that arbitrarily large inputs
// short-circuit once enough valid prefix has been observed.

const json_sniff_budget = 4096

type JsonResult {
  Valid(BitArray, Int)
  Truncated
  Invalid
}

fn looks_like_json(bytes: BitArray) -> Bool {
  let stripped = json_strip_bom(bytes)
  let #(after_ws, budget) = json_skip_ws(stripped, json_sniff_budget)
  case after_ws {
    <<0x7B, rest:bits>> ->
      json_finalize(json_validate_object(rest, budget - 1, True))
    <<0x5B, rest:bits>> ->
      json_finalize(json_validate_array(rest, budget - 1, True))
    _ -> False
  }
}

fn json_finalize(result: JsonResult) -> Bool {
  case result {
    Valid(_, _) -> True
    Truncated -> True
    Invalid -> False
  }
}

fn json_strip_bom(bytes: BitArray) -> BitArray {
  case bytes {
    <<0xEF, 0xBB, 0xBF, rest:bits>> -> rest
    _ -> bytes
  }
}

fn json_skip_ws(bytes: BitArray, budget: Int) -> #(BitArray, Int) {
  use <- bool.guard(when: budget <= 0, return: #(bytes, budget))
  case bytes {
    <<0x20, rest:bits>> -> json_skip_ws(rest, budget - 1)
    <<0x09, rest:bits>> -> json_skip_ws(rest, budget - 1)
    <<0x0A, rest:bits>> -> json_skip_ws(rest, budget - 1)
    <<0x0D, rest:bits>> -> json_skip_ws(rest, budget - 1)
    _ -> #(bytes, budget)
  }
}

fn json_then(
  result: JsonResult,
  next: fn(BitArray, Int) -> JsonResult,
) -> JsonResult {
  case result {
    Valid(rest, budget) -> next(rest, budget)
    Truncated -> Truncated
    Invalid -> Invalid
  }
}

fn json_validate_value(bytes: BitArray, budget: Int) -> JsonResult {
  use <- bool.lazy_guard(when: budget <= 0, return: fn() { Truncated })
  let #(b, budget) = json_skip_ws(bytes, budget)
  case b {
    <<>> -> Truncated
    <<0x7B, rest:bits>> -> json_validate_object(rest, budget - 1, True)
    <<0x5B, rest:bits>> -> json_validate_array(rest, budget - 1, True)
    <<0x22, rest:bits>> -> json_skip_string(rest, budget - 1)
    <<0x74, rest:bits>> -> json_match_literal(rest, <<"rue":utf8>>, budget - 1)
    <<0x66, rest:bits>> -> json_match_literal(rest, <<"alse":utf8>>, budget - 1)
    <<0x6E, rest:bits>> -> json_match_literal(rest, <<"ull":utf8>>, budget - 1)
    <<0x2D, _:bits>> -> json_skip_number(b, budget)
    <<x, _:bits>> if x >= 0x30 && x <= 0x39 -> json_skip_number(b, budget)
    _ -> Invalid
  }
}

fn json_validate_object(
  bytes: BitArray,
  budget: Int,
  expecting_first: Bool,
) -> JsonResult {
  let #(b, budget) = json_skip_ws(bytes, budget)
  case b {
    <<>> -> Truncated
    <<0x7D, rest:bits>> -> {
      use <- bool.guard(when: !expecting_first, return: Invalid)
      Valid(rest, budget - 1)
    }
    <<0x22, rest:bits>> -> json_validate_object_member(rest, budget - 1)
    _ -> Invalid
  }
}

fn json_validate_object_member(bytes: BitArray, budget: Int) -> JsonResult {
  use after_key, budget <- json_then(json_skip_string(bytes, budget))
  let #(b, budget) = json_skip_ws(after_key, budget)
  case b {
    <<>> -> Truncated
    <<0x3A, after_colon:bits>> -> {
      use after_value, budget <- json_then(json_validate_value(
        after_colon,
        budget - 1,
      ))
      let #(b, budget) = json_skip_ws(after_value, budget)
      case b {
        <<>> -> Truncated
        <<0x2C, rest:bits>> -> json_validate_object(rest, budget - 1, False)
        <<0x7D, rest:bits>> -> Valid(rest, budget - 1)
        _ -> Invalid
      }
    }
    _ -> Invalid
  }
}

fn json_validate_array(
  bytes: BitArray,
  budget: Int,
  expecting_first: Bool,
) -> JsonResult {
  let #(b, budget) = json_skip_ws(bytes, budget)
  case b {
    <<>> -> Truncated
    <<0x5D, rest:bits>> -> {
      use <- bool.guard(when: !expecting_first, return: Invalid)
      Valid(rest, budget - 1)
    }
    _ -> {
      use after_value, budget <- json_then(json_validate_value(b, budget))
      let #(b, budget) = json_skip_ws(after_value, budget)
      case b {
        <<>> -> Truncated
        <<0x2C, rest:bits>> -> json_validate_array(rest, budget - 1, False)
        <<0x5D, rest:bits>> -> Valid(rest, budget - 1)
        _ -> Invalid
      }
    }
  }
}

fn json_skip_string(bytes: BitArray, budget: Int) -> JsonResult {
  use <- bool.lazy_guard(when: budget <= 0, return: fn() { Truncated })
  case bytes {
    <<>> -> Truncated
    <<0x22, rest:bits>> -> Valid(rest, budget - 1)
    <<0x5C, _esc, rest:bits>> -> json_skip_string(rest, budget - 2)
    <<0x5C>> -> Truncated
    <<_b, rest:bits>> -> json_skip_string(rest, budget - 1)
    _ -> Invalid
  }
}

fn json_skip_number(bytes: BitArray, budget: Int) -> JsonResult {
  use <- bool.lazy_guard(when: budget <= 0, return: fn() { Truncated })
  case bytes {
    <<>> -> Truncated
    <<0x2D, rest:bits>> -> json_skip_number_digits(rest, budget - 1)
    <<b, _:bits>> if b >= 0x30 && b <= 0x39 ->
      json_skip_number_digits(bytes, budget)
    _ -> Invalid
  }
}

fn json_skip_number_digits(bytes: BitArray, budget: Int) -> JsonResult {
  use <- bool.lazy_guard(when: budget <= 0, return: fn() { Truncated })
  case bytes {
    <<>> -> Truncated
    <<b, rest:bits>> if b >= 0x30 && b <= 0x39 ->
      json_skip_number_digits(rest, budget - 1)
    <<0x2E, rest:bits>> -> json_skip_number_digits(rest, budget - 1)
    <<0x65, rest:bits>> -> json_skip_number_digits(rest, budget - 1)
    <<0x45, rest:bits>> -> json_skip_number_digits(rest, budget - 1)
    <<0x2B, rest:bits>> -> json_skip_number_digits(rest, budget - 1)
    <<0x2D, rest:bits>> -> json_skip_number_digits(rest, budget - 1)
    _ -> Valid(bytes, budget)
  }
}

fn json_match_literal(bytes: BitArray, lit: BitArray, budget: Int) -> JsonResult {
  case bytes, lit {
    _, <<>> -> Valid(bytes, budget)
    <<>>, _ -> Truncated
    <<b, b_rest:bits>>, <<l, l_rest:bits>> -> {
      use <- bool.guard(when: b != l, return: Invalid)
      json_match_literal(b_rest, l_rest, budget - 1)
    }
    _, _ -> Invalid
  }
}

// HTML / XML sniffing per the WHATWG MIME Sniffing standard.
//
// `looks_like_html` recognizes inputs whose first non-whitespace token is
// `<!doctype html` or one of a small set of common HTML tags, matched
// case-insensitively and required to be followed by a tag-terminating byte
// (whitespace, `>`, or end of input). The terminator requirement avoids
// over-matching: `<address>` does not match the `<a` signature because
// `d` is not a terminator.
//
// `looks_like_xml` recognizes inputs starting with the lowercase XML
// declaration `<?xml` followed by a tag-terminating byte. The XML
// declaration is case-sensitive per the XML 1.0 spec; uppercase variants
// are not treated as XML.
//
// Both detectors strip an optional UTF-8 BOM and any leading HTML
// whitespace before matching. UTF-16 / UTF-32 BOMs are deferred to the
// dedicated text-plain detector (#20).

const html_tag_signatures = [
  <<"<html":utf8>>,
  <<"<head":utf8>>,
  <<"<body":utf8>>,
  <<"<script":utf8>>,
  <<"<iframe":utf8>>,
  <<"<table":utf8>>,
  <<"<style":utf8>>,
  <<"<title":utf8>>,
  <<"<br":utf8>>,
  <<"<p":utf8>>,
  <<"<h1":utf8>>,
  <<"<div":utf8>>,
  <<"<font":utf8>>,
  <<"<img":utf8>>,
  <<"<a":utf8>>,
]

fn looks_like_html(bytes: BitArray) -> Bool {
  let trimmed = trim_text_prefix(bytes)
  use <- bool.lazy_guard(when: matches_html_doctype(trimmed), return: fn() {
    True
  })
  list.any(html_tag_signatures, fn(tag) { matches_html_tag(trimmed, tag) })
}

fn looks_like_xml(bytes: BitArray) -> Bool {
  trim_text_prefix(bytes)
  |> match_byte_prefix(<<"<?xml":utf8>>)
  |> result.map(is_text_terminator)
  |> result.unwrap(False)
}

fn matches_html_doctype(bytes: BitArray) -> Bool {
  match_ci_prefix(bytes, <<"<!doctype html":utf8>>)
  |> result.map(is_text_terminator)
  |> result.unwrap(False)
}

fn matches_html_tag(bytes: BitArray, tag: BitArray) -> Bool {
  match_ci_prefix(bytes, tag)
  |> result.map(is_text_terminator)
  |> result.unwrap(False)
}

fn trim_text_prefix(bytes: BitArray) -> BitArray {
  bytes
  |> strip_utf8_bom
  |> skip_html_ws
}

fn strip_utf8_bom(bytes: BitArray) -> BitArray {
  case bytes {
    <<0xEF, 0xBB, 0xBF, rest:bits>> -> rest
    _ -> bytes
  }
}

fn skip_html_ws(bytes: BitArray) -> BitArray {
  case bytes {
    <<0x20, rest:bits>> -> skip_html_ws(rest)
    <<0x09, rest:bits>> -> skip_html_ws(rest)
    <<0x0A, rest:bits>> -> skip_html_ws(rest)
    <<0x0C, rest:bits>> -> skip_html_ws(rest)
    <<0x0D, rest:bits>> -> skip_html_ws(rest)
    _ -> bytes
  }
}

fn is_text_terminator(bytes: BitArray) -> Bool {
  case bytes {
    <<>> -> True
    <<0x20, _:bits>> -> True
    <<0x09, _:bits>> -> True
    <<0x0A, _:bits>> -> True
    <<0x0C, _:bits>> -> True
    <<0x0D, _:bits>> -> True
    <<0x3E, _:bits>> -> True
    _ -> False
  }
}

fn match_ci_prefix(bytes: BitArray, prefix: BitArray) -> Result(BitArray, Nil) {
  case prefix, bytes {
    <<>>, _ -> Ok(bytes)
    _, <<>> -> Error(Nil)
    <<p, p_rest:bits>>, <<b, b_rest:bits>> -> {
      use <- bool.lazy_guard(
        when: ascii_to_lower(b) != ascii_to_lower(p),
        return: fn() { Error(Nil) },
      )
      match_ci_prefix(b_rest, p_rest)
    }
    _, _ -> Error(Nil)
  }
}

fn match_byte_prefix(bytes: BitArray, prefix: BitArray) -> Result(BitArray, Nil) {
  case prefix, bytes {
    <<>>, _ -> Ok(bytes)
    _, <<>> -> Error(Nil)
    <<p, p_rest:bits>>, <<b, b_rest:bits>> -> {
      use <- bool.lazy_guard(when: b != p, return: fn() { Error(Nil) })
      match_byte_prefix(b_rest, p_rest)
    }
    _, _ -> Error(Nil)
  }
}

fn ascii_to_lower(byte: Int) -> Int {
  use <- bool.guard(when: byte < 0x41 || byte > 0x5A, return: byte)
  byte + 32
}

// SVG sniffing: distinguish SVG from generic XML by looking for an `<svg`
// root element. The XML declaration, DOCTYPE, comments, and whitespace
// between them are skipped before the root-element check so that real-world
// SVG files (which often start with a UTF-8 BOM, an `<?xml ?>` prolog, and
// a `<!DOCTYPE svg ...>` declaration) are recognized.
//
// The `<svg` match is case-sensitive: XML element names are case-sensitive
// per the XML 1.0 spec, so `<SVG>` is not SVG. The match also requires a
// terminator that includes `/` so that self-closing `<svg/>` works.
//
// Walking is bounded by `svg_sniff_budget` to cap work on pathological
// inputs (huge comments, huge DOCTYPE, etc.).

const svg_sniff_budget = 4096

fn looks_like_svg(bytes: BitArray) -> Bool {
  let bytes = trim_text_prefix(bytes)
  let bytes = skip_xml_prolog(bytes, svg_sniff_budget)
  let bytes = skip_xml_misc(bytes, svg_sniff_budget)
  match_byte_prefix(bytes, <<"<svg":utf8>>)
  |> result.map(is_xml_element_terminator)
  |> result.unwrap(False)
}

fn is_xml_element_terminator(bytes: BitArray) -> Bool {
  case bytes {
    <<>> -> True
    <<0x20, _:bits>> -> True
    <<0x09, _:bits>> -> True
    <<0x0A, _:bits>> -> True
    <<0x0C, _:bits>> -> True
    <<0x0D, _:bits>> -> True
    <<0x3E, _:bits>> -> True
    <<0x2F, _:bits>> -> True
    _ -> False
  }
}

fn skip_xml_prolog(bytes: BitArray, budget: Int) -> BitArray {
  match_byte_prefix(bytes, <<"<?xml":utf8>>)
  |> result.map(skip_until_literal(_, <<"?>":utf8>>, budget))
  |> result.unwrap(bytes)
}

fn skip_xml_misc(bytes: BitArray, budget: Int) -> BitArray {
  use <- bool.guard(when: budget <= 0, return: bytes)
  let trimmed = skip_html_ws(bytes)
  use <- bool.lazy_guard(
    when: starts_with_literal(trimmed, <<"<!--":utf8>>),
    return: fn() {
      skip_until_literal(trimmed, <<"-->":utf8>>, budget)
      |> skip_xml_misc(budget - 1)
    },
  )
  use <- bool.lazy_guard(
    when: starts_with_literal(trimmed, <<"<!DOCTYPE":utf8>>),
    return: fn() {
      skip_until_literal(trimmed, <<">":utf8>>, budget)
      |> skip_xml_misc(budget - 1)
    },
  )
  trimmed
}

fn skip_until_literal(
  bytes: BitArray,
  literal: BitArray,
  budget: Int,
) -> BitArray {
  use <- bool.guard(when: budget <= 0, return: bytes)
  case starts_with_literal(bytes, literal) {
    True ->
      match_byte_prefix(bytes, literal)
      |> result.unwrap(bytes)
    False ->
      case bytes {
        <<>> -> bytes
        <<_, rest:bits>> -> skip_until_literal(rest, literal, budget - 1)
        _ -> bytes
      }
  }
}

fn starts_with_literal(bytes: BitArray, literal: BitArray) -> Bool {
  match_byte_prefix(bytes, literal) |> result.is_ok
}

fn has_lzh_magic(bytes: BitArray) -> Bool {
  // LZH/LHA: `??-lh?-` where bytes 0-1 are size, 2-4 are `-lh`, 5 is the
  // method digit, and 6 is the trailing `-`. We match the fixed parts and
  // accept any byte at position 5.
  has_bytes_at(bytes, 2, <<"-lh":utf8>>) && has_bytes_at(bytes, 6, <<"-":utf8>>)
}

// OLE Compound File Binary (CFB) detection.
//
// The CFB header is 8 bytes: D0 CF 11 E0 A1 B1 1A E1.
// To distinguish Word/Excel/PowerPoint we scan for UTF-16LE encoded
// stream names in the leading bytes (typically within the first 2 KB).

const ole_cfb_header = <<0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1>>

// "WordDocument" in UTF-16LE
const ole_word_marker = <<
  0x57, 0x00, 0x6F, 0x00, 0x72, 0x00, 0x64, 0x00, 0x44, 0x00, 0x6F, 0x00, 0x63,
  0x00, 0x75, 0x00, 0x6D, 0x00, 0x65, 0x00, 0x6E, 0x00, 0x74, 0x00,
>>

// "Workbook" in UTF-16LE
const ole_workbook_marker = <<
  0x57, 0x00, 0x6F, 0x00, 0x72, 0x00, 0x6B, 0x00, 0x62, 0x00, 0x6F, 0x00, 0x6F,
  0x00, 0x6B, 0x00,
>>

// "Book" in UTF-16LE (older Excel format)
const ole_book_marker = <<0x42, 0x00, 0x6F, 0x00, 0x6F, 0x00, 0x6B, 0x00>>

// "PowerPoint Document" in UTF-16LE
const ole_powerpoint_marker = <<
  0x50, 0x00, 0x6F, 0x00, 0x77, 0x00, 0x65, 0x00, 0x72, 0x00, 0x50, 0x00, 0x6F,
  0x00, 0x69, 0x00, 0x6E, 0x00, 0x74, 0x00, 0x20, 0x00, 0x44, 0x00, 0x6F, 0x00,
  0x63, 0x00, 0x75, 0x00, 0x6D, 0x00, 0x65, 0x00, 0x6E, 0x00, 0x74, 0x00,
>>

fn has_ole_header(bytes: BitArray) -> Bool {
  has_bytes_at(bytes, 0, ole_cfb_header)
}

fn ole_contains_marker(bytes: BitArray, marker: BitArray) -> Bool {
  ole_scan_for_marker(bytes, marker, 0)
}

fn ole_scan_for_marker(bytes: BitArray, marker: BitArray, offset: Int) -> Bool {
  let marker_size = bit_array.byte_size(marker)
  let bytes_size = bit_array.byte_size(bytes)
  case offset + marker_size > bytes_size {
    True -> False
    False ->
      case has_bytes_at(bytes, offset, marker) {
        True -> True
        False -> ole_scan_for_marker(bytes, marker, offset + 1)
      }
  }
}

fn looks_like_ole_word(bytes: BitArray) -> Bool {
  has_ole_header(bytes) && ole_contains_marker(bytes, ole_word_marker)
}

fn looks_like_ole_excel(bytes: BitArray) -> Bool {
  has_ole_header(bytes)
  && {
    ole_contains_marker(bytes, ole_workbook_marker)
    || ole_contains_marker(bytes, ole_book_marker)
  }
}

fn looks_like_ole_powerpoint(bytes: BitArray) -> Bool {
  has_ole_header(bytes) && ole_contains_marker(bytes, ole_powerpoint_marker)
}

fn looks_like_ole_cfb(bytes: BitArray) -> Bool {
  has_ole_header(bytes)
}

// ZIP-based format detection.
//
// ZIP local file header layout:
//   Offset 0:  signature  PK\x03\x04  (4 bytes)
//   Offset 26: filename length         (2 bytes, little-endian)
//   Offset 28: extra field length      (2 bytes, little-endian)
//   Offset 30: filename                (variable)
//
// After filename + extra + compressed data comes the next local file header.
// We walk a few entries to collect filenames and decide the format.

const zip_local_header = <<0x50, 0x4B, 0x03, 0x04>>

fn has_zip_header(bytes: BitArray) -> Bool {
  has_bytes_at(bytes, 0, zip_local_header)
}

/// Extract filenames from ZIP local file headers (up to budget entries).
fn zip_collect_filenames(
  bytes: BitArray,
  offset: Int,
  budget: Int,
  acc: List(String),
) -> List(String) {
  use <- bool.guard(
    when: budget <= 0 || offset + 30 > bit_array.byte_size(bytes),
    return: acc,
  )
  use <- bool.guard(
    when: !has_bytes_at(bytes, offset, zip_local_header),
    return: acc,
  )
  case zip_read_entry_info(bytes, offset) {
    Error(Nil) -> acc
    Ok(#(filename, next_offset)) ->
      zip_collect_filenames(bytes, next_offset, budget - 1, [filename, ..acc])
  }
}

fn zip_read_entry_info(
  bytes: BitArray,
  offset: Int,
) -> Result(#(String, Int), Nil) {
  let size = bit_array.byte_size(bytes)
  use <- bool.guard(when: offset + 30 > size, return: Error(Nil))
  use comp_size_bits <- result.try(bit_array.slice(bytes, offset + 18, 4))
  use fname_len_bits <- result.try(bit_array.slice(bytes, offset + 26, 2))
  use extra_len_bits <- result.try(bit_array.slice(bytes, offset + 28, 2))
  let compressed_size = le_u32(comp_size_bits)
  let fname_len = le_u16(fname_len_bits)
  let extra_len = le_u16(extra_len_bits)
  use <- bool.guard(
    when: fname_len <= 0 || offset + 30 + fname_len > size,
    return: Error(Nil),
  )
  use fname_bytes <- result.try(bit_array.slice(bytes, offset + 30, fname_len))
  let filename = bit_array.to_string(fname_bytes) |> result.unwrap("")
  let next = offset + 30 + fname_len + extra_len + compressed_size
  Ok(#(filename, next))
}

fn le_u16(bytes: BitArray) -> Int {
  case bytes {
    <<lo, hi>> -> hi * 256 + lo
    _ -> 0
  }
}

fn le_u32(bytes: BitArray) -> Int {
  case bytes {
    <<b0, b1, b2, b3>> -> b3 * 16_777_216 + b2 * 65_536 + b1 * 256 + b0
    _ -> 0
  }
}

fn zip_filenames_contain(filenames: List(String), prefix: String) -> Bool {
  list.any(filenames, fn(name) { string.starts_with(name, prefix) })
}

const zip_stored_mimetype_entry_name = <<"mimetype":utf8>>

fn looks_like_zip_with_stored_mimetype(
  bytes: BitArray,
  expected_mime_type: BitArray,
) -> Bool {
  use <- bool.guard(when: !has_zip_header(bytes), return: False)
  let filename_offset = 30
  let content_offset =
    filename_offset + bit_array.byte_size(zip_stored_mimetype_entry_name)
  has_bytes_at(bytes, filename_offset, zip_stored_mimetype_entry_name)
  && has_bytes_at(bytes, content_offset, expected_mime_type)
}

fn looks_like_epub(bytes: BitArray) -> Bool {
  // EPUB requires "mimetype" as the first entry, stored uncompressed at
  // offset 30, with content "application/epub+zip".
  looks_like_zip_with_stored_mimetype(bytes, <<"application/epub+zip":utf8>>)
}

fn looks_like_odt(bytes: BitArray) -> Bool {
  looks_like_zip_with_stored_mimetype(bytes, <<
    "application/vnd.oasis.opendocument.text":utf8,
  >>)
}

fn looks_like_ods(bytes: BitArray) -> Bool {
  looks_like_zip_with_stored_mimetype(bytes, <<
    "application/vnd.oasis.opendocument.spreadsheet":utf8,
  >>)
}

fn looks_like_odp(bytes: BitArray) -> Bool {
  looks_like_zip_with_stored_mimetype(bytes, <<
    "application/vnd.oasis.opendocument.presentation":utf8,
  >>)
}

fn looks_like_jar(bytes: BitArray) -> Bool {
  use <- bool.guard(when: !has_zip_header(bytes), return: False)
  let filenames = zip_collect_filenames(bytes, 0, 20, [])
  zip_filenames_contain(filenames, "META-INF/MANIFEST.MF")
}

fn looks_like_apk(bytes: BitArray) -> Bool {
  use <- bool.guard(when: !has_zip_header(bytes), return: False)
  let filenames = zip_collect_filenames(bytes, 0, 20, [])
  zip_filenames_contain(filenames, "AndroidManifest.xml")
}

fn looks_like_docx(bytes: BitArray) -> Bool {
  use <- bool.guard(when: !has_zip_header(bytes), return: False)
  let filenames = zip_collect_filenames(bytes, 0, 20, [])
  zip_filenames_contain(filenames, "[Content_Types].xml")
  && zip_filenames_contain(filenames, "word/")
}

fn looks_like_xlsx(bytes: BitArray) -> Bool {
  use <- bool.guard(when: !has_zip_header(bytes), return: False)
  let filenames = zip_collect_filenames(bytes, 0, 20, [])
  zip_filenames_contain(filenames, "[Content_Types].xml")
  && zip_filenames_contain(filenames, "xl/")
}

fn looks_like_pptx(bytes: BitArray) -> Bool {
  use <- bool.guard(when: !has_zip_header(bytes), return: False)
  let filenames = zip_collect_filenames(bytes, 0, 20, [])
  zip_filenames_contain(filenames, "[Content_Types].xml")
  && zip_filenames_contain(filenames, "ppt/")
}

fn has_zlib_magic(bytes: BitArray) -> Bool {
  // RFC 1950 zlib stream: first byte 0x78 (CMF for deflate, 32K window),
  // second byte one of the four valid (FLEVEL, FDICT) combinations whose
  // CMF*256 + FLG is a multiple of 31. The check is heuristic — short
  // binary inputs that happen to start with these bytes will false-positive.
  // Placed at the end of `signatures` so this only fires when nothing else
  // matched.
  case bytes {
    <<0x78, second:size(8), _:bits>>
      if second == 0x01 || second == 0x5E || second == 0x9C || second == 0xDA
    -> True
    _ -> False
  }
}

fn has_aac_adts_sync(bytes: BitArray) -> Bool {
  // ADTS sync = 12 bits all 1, then ID (1 bit), Layer (2 bits, must be 00),
  // protection_absent (1 bit). Valid second-byte values (high nibble 0xF
  // plus low nibble where bits 5-4 = 00): 0xF0, 0xF1, 0xF8, 0xF9.
  case bytes {
    <<0xFF, second:size(8), _:bits>>
      if second == 0xF0 || second == 0xF1 || second == 0xF8 || second == 0xF9
    -> True
    _ -> False
  }
}

const matroska_doctype = <<0x42, 0x82, 0x88, "matroska":utf8>>

const webm_doctype = <<0x42, 0x82, 0x84, "webm":utf8>>

const ebml_search_budget = 256

fn looks_like_matroska(bytes: BitArray) -> Bool {
  case bytes {
    <<0x1A, 0x45, 0xDF, 0xA3, _:bits>> ->
      contains_literal(bytes, matroska_doctype, ebml_search_budget)
    _ -> False
  }
}

fn looks_like_webm(bytes: BitArray) -> Bool {
  case bytes {
    <<0x1A, 0x45, 0xDF, 0xA3, _:bits>> ->
      contains_literal(bytes, webm_doctype, ebml_search_budget)
    _ -> False
  }
}

fn contains_literal(bytes: BitArray, literal: BitArray, budget: Int) -> Bool {
  use <- bool.guard(when: budget <= 0, return: False)
  use <- bool.lazy_guard(
    when: starts_with_literal(bytes, literal),
    return: fn() { True },
  )
  case bytes {
    <<>> -> False
    <<_, rest:bits>> -> contains_literal(rest, literal, budget - 1)
    _ -> False
  }
}

// Plain-text fallback: when no other signature matched, classify the input
// as `text/plain` if the leading bytes are entirely printable ASCII or HTML
// whitespace. Per WHATWG MIME Sniffing's binary-vs-text rule, the presence
// of any C0 control byte (other than tab/LF/FF/CR), 0x7F, or any high byte
// (0x80–0xFF) marks the input as binary. The check is bounded by
// `text_sniff_budget` so that long text files terminate quickly.

const text_sniff_budget = 1024

fn looks_like_plain_text(bytes: BitArray) -> Bool {
  use <- bool.guard(when: bytes == <<>>, return: False)
  is_all_text_bytes(bytes, text_sniff_budget)
}

fn is_all_text_bytes(bytes: BitArray, budget: Int) -> Bool {
  use <- bool.guard(when: budget <= 0, return: True)
  case bytes {
    <<>> -> True
    <<b, rest:bits>> -> {
      use <- bool.guard(when: !is_text_byte(b), return: False)
      is_all_text_bytes(rest, budget - 1)
    }
    _ -> False
  }
}

fn is_text_byte(byte: Int) -> Bool {
  byte == 0x09
  || byte == 0x0A
  || byte == 0x0C
  || byte == 0x0D
  || { byte >= 0x20 && byte <= 0x7E }
}
