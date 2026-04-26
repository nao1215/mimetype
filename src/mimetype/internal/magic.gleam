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
