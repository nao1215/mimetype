//// Magic-byte detection primitives.
////
//// Every function returns the detected essence as `Option(String)` /
//// `Result(String, DetectionError(_))`. The facade (`mimetype`) wraps
//// the essence into a `MimeType` and applies its lenient-vs-strict
//// fallback.

import gleam/bit_array
import gleam/bool
import gleam/option.{None, Some}
import gleam/result
import mimetype/internal/charset as charset_internal
import mimetype/internal/magic

/// Detect-side failure modes. The facade translates these into its
/// public `DetectionError` constructors before returning to the
/// caller.
pub type DetectFailure(read_error) {
  Empty
  NoSignatureMatch
  ReadFailed(read_error)
}

/// Detect the character encoding of a `BitArray`. Returns the
/// internal failure shape; the facade converts it to the public
/// `DetectionError`.
pub fn charset_of(bytes: BitArray) -> Result(String, DetectFailure(Nil)) {
  use <- bool.guard(when: bit_array.byte_size(bytes) == 0, return: Error(Empty))
  case charset_internal.detect(bytes) {
    Ok(charset) -> Ok(charset)
    Error(Nil) -> Error(NoSignatureMatch)
  }
}

/// Detect a MIME essence from at most `limit` bytes, including the
/// printable-ASCII `text/plain` heuristic.
pub fn detect_essence_with_limit(
  bytes: BitArray,
  limit: Int,
) -> Result(String, DetectFailure(Nil)) {
  use <- bool.guard(when: bit_array.byte_size(bytes) == 0, return: Error(Empty))
  case magic.detect(truncate_to_limit(bytes, limit)) {
    Some(s) -> Ok(s)
    None -> Error(NoSignatureMatch)
  }
}

/// Detect a MIME essence from a genuine binary or structural
/// signature — excludes the printable-ASCII heuristic.
pub fn detect_signature_only_with_limit(
  bytes: BitArray,
  limit: Int,
) -> Result(String, DetectFailure(Nil)) {
  use <- bool.guard(when: bit_array.byte_size(bytes) == 0, return: Error(Empty))
  case magic.detect_signature(truncate_to_limit(bytes, limit)) {
    Some(s) -> Ok(s)
    None -> Error(NoSignatureMatch)
  }
}

/// Pull at most `limit` bytes through `read` and detect the essence
/// from the resulting bytes. Reader errors flow through as
/// `ReadFailed(_)`.
pub fn detect_essence_via_reader(
  read: fn(Int) -> Result(BitArray, read_error),
  limit: Int,
) -> Result(String, DetectFailure(read_error)) {
  let safe_limit = case limit < 1 {
    True -> 0
    False -> limit
  }
  case read(safe_limit) {
    Ok(bytes) ->
      case detect_essence_with_limit(bytes, safe_limit) {
        Ok(s) -> Ok(s)
        Error(Empty) -> Error(Empty)
        Error(NoSignatureMatch) -> Error(NoSignatureMatch)
        // Unreachable: detect_essence_with_limit never produces
        // ReadFailed. Falling back to NoSignatureMatch keeps the
        // type exhaustive without leaking the unreachable branch.
        Error(ReadFailed(_)) -> Error(NoSignatureMatch)
      }
    Error(read_error) -> Error(ReadFailed(read_error))
  }
}

/// Slice the first `limit` bytes off `bytes`. Negative limits become 0;
/// limits larger than the input are clamped down to the input length.
pub fn truncate_to_limit(bytes: BitArray, limit: Int) -> BitArray {
  let size = bit_array.byte_size(bytes)
  let safe_limit = case limit < 0, limit > size {
    True, _ -> 0
    False, True -> size
    False, False -> limit
  }
  bit_array.slice(bytes, 0, safe_limit) |> result.unwrap(<<>>)
}
