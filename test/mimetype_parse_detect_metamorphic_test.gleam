//// Metamorphic relations for parsing and detection.
////
//// - `to_string` then `parse` gives back the same `MimeType` for any
////   header that parses, including quoted values with `"`, `\`, `;` and
////   spaces, and serialising twice is a no-op.
//// - Detection with a byte limit only looks at that many bytes: cutting
////   the input at the limit never changes the answer, and neither does
////   anything appended after it.

import gleam/bit_array
import gleam/list
import gleam/option
import gleam/result
import gleam/string
import metamon
import metamon/generator.{type Generator}
import metamon/generator/range
import mimetype

fn param_value_gen() -> Generator(String) {
  generator.list_of(
    generator.element_of([
      "a", "Z", "0", "-", ".", " ", ";", ",", "\"", "\\", "=", "/", "\t",
      "\u{00E9}",
    ]),
    range.constant(0, 8),
  )
  |> generator.map(string.concat)
}

fn quote(value: String) -> String {
  "\""
  <> value
  |> string.replace("\\", "\\\\")
  |> string.replace("\"", "\\\"")
  <> "\""
}

fn header_gen() -> Generator(String) {
  generator.tuple2(
    generator.element_of([
      "text/plain", "TEXT/Html", "application/json", "image/svg+xml",
      "multipart/form-data",
    ]),
    generator.list_of(
      generator.tuple3(
        generator.element_of(["charset", "Boundary", "q", "x-a"]),
        param_value_gen(),
        generator.element_of(["; ", ";", " ; "]),
      ),
      range.constant(0, 3),
    ),
  )
  |> generator.map(fn(t) {
    let #(essence, params) = t
    list.fold(params, essence, fn(acc, p) {
      let #(key, value, sep) = p
      acc <> sep <> key <> "=" <> quote(value)
    })
  })
}

pub fn to_string_round_trips_through_parse_test() -> Nil {
  metamon.forall(header_gen(), fn(header) {
    let assert Ok(parsed) = mimetype.parse(header)
    let wire = mimetype.to_string(parsed)
    mimetype.parse(wire) == Ok(parsed)
    && mimetype.parse_strict(wire) == Ok(parsed)
    && mimetype.to_string(parsed) == wire
  })
}

pub fn generated_headers_always_parse_test() -> Nil {
  // Every generated header is a valid quoted-string form, so a parse
  // error here is a parser bug rather than bad input.
  metamon.forall(header_gen(), fn(header) {
    mimetype.parse(header) |> result.is_ok
  })
}

fn signature_gen() -> Generator(BitArray) {
  generator.element_of([
    <<0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A>>,
    <<0xFF, 0xD8, 0xFF, 0xE0>>,
    <<"%PDF-1.7":utf8>>,
    <<0x50, 0x4B, 0x03, 0x04>>,
    <<"GIF89a":utf8>>,
    <<"<!DOCTYPE html>":utf8>>,
    <<"<?xml version=\"1.0\"?><svg>":utf8>>,
    <<"{\"a\": 1}":utf8>>,
    <<0xEF, 0xBB, 0xBF, "hi":utf8>>,
    <<"plain text":utf8>>,
    <<>>,
  ])
}

pub fn detect_with_limit_only_reads_the_first_limit_bytes_test() -> Nil {
  metamon.forall(
    generator.tuple3(
      signature_gen(),
      generator.bit_array(range.constant(0, 40)),
      generator.tuple2(
        generator.int(range.constant(-2, 48)),
        generator.bit_array(range.constant(0, 16)),
      ),
    ),
    fn(input) {
      let #(signature, tail, #(limit, junk)) = input
      let bytes = bit_array.append(signature, tail)
      let size = bit_array.byte_size(bytes)
      let cut = case limit < 0, limit > size {
        True, _ -> <<>>
        _, True -> bytes
        _, _ -> {
          let assert Ok(head) = bit_array.slice(bytes, 0, limit)
          head
        }
      }
      // Only the detected type is compared: an empty input reports
      // EmptyInput where a non-empty one cut to nothing reports NoMatch.
      let detect = fn(b) {
        option.from_result(mimetype.detect_with_limit_strict(b, limit))
      }
      let expected = detect(bytes)
      // Bytes appended after the first `limit` are never read.
      let appended = case limit <= size {
        True -> detect(bit_array.append(cut, junk)) == expected
        False -> True
      }
      detect(cut) == expected && appended
    },
  )
}

pub fn detect_reader_matches_detect_with_limit_test() -> Nil {
  metamon.forall(
    generator.tuple3(
      signature_gen(),
      generator.bit_array(range.constant(0, 40)),
      generator.int(range.constant(0, 48)),
    ),
    fn(input) {
      let #(signature, tail, limit) = input
      let bytes = bit_array.append(signature, tail)
      // A reader that ignores the requested count and hands back
      // everything must not let detection look past `limit`.
      let read_all = fn(_requested) { Ok(bytes) }
      option.from_result(mimetype.detect_reader_strict(read_all, limit))
      == option.from_result(mimetype.detect_with_limit_strict(bytes, limit))
    },
  )
}
