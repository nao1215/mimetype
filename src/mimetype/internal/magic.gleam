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
  Bytes("application/pdf", [#(0, <<0x25, 0x50, 0x44, 0x46, 0x2D>>)]),
  Bytes("application/pdf", [#(0, <<0x0A, 0x25, 0x50, 0x44, 0x46, 0x2D>>)]),
  Bytes(
    "application/pdf",
    [#(0, <<0xEF, 0xBB, 0xBF, 0x25, 0x50, 0x44, 0x46, 0x2D>>)],
  ),
  Bytes("application/zip", [#(0, <<0x50, 0x4B, 0x03, 0x04>>)]),
  Bytes("application/zip", [#(0, <<0x50, 0x4B, 0x05, 0x06>>)]),
  Bytes("application/zip", [#(0, <<0x50, 0x4B, 0x07, 0x08>>)]),
  Bytes("application/gzip", [#(0, <<0x1F, 0x8B>>)]),
  Bytes("application/x-bzip2", [#(0, <<0x42, 0x5A, 0x68>>)]),
  Bytes("application/x-xz", [#(0, <<0xFD, 0x37, 0x7A, 0x58, 0x5A, 0x00>>)]),
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
  Bytes("audio/mpeg", [#(0, <<"ID3":utf8>>)]),
  Check("audio/mpeg", has_mp3_frame_sync),
  Bytes(
    "audio/flac",
    [#(0, <<0x66, 0x4C, 0x61, 0x43, 0x00, 0x00, 0x00, 0x22>>)],
  ),
  Bytes("audio/midi", [#(0, <<0x4D, 0x54, 0x68, 0x64>>)]),
  Bytes("application/ogg", [#(0, <<0x4F, 0x67, 0x67, 0x53>>)]),
  Bytes("video/webm", [#(0, <<0x1A, 0x45, 0xDF, 0xA3>>)]),
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
  Bytes("video/mp4", [#(4, <<"ftyp":utf8>>), #(8, <<"isom":utf8>>)]),
  Bytes("video/mp4", [#(4, <<"ftyp":utf8>>), #(8, <<"iso2":utf8>>)]),
  Bytes("video/mp4", [#(4, <<"ftyp":utf8>>), #(8, <<"mp41":utf8>>)]),
  Bytes("video/mp4", [#(4, <<"ftyp":utf8>>), #(8, <<"mp42":utf8>>)]),
  Bytes("video/mp4", [#(4, <<"ftyp":utf8>>), #(8, <<"avc1":utf8>>)]),
  Check("application/json", looks_like_json),
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
