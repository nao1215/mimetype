//// Differential tests for detection against independent implementations.
////
//// - `charset_of` falls back to a UTF-8 validity scan. For byte strings
////   without a BOM or a markup declaration it must say `us-ascii` exactly
////   when every byte is below 0x80, `utf-8` exactly when the standard
////   library accepts the bytes as UTF-8, and nothing otherwise. The inputs
////   mix boundary code points (U+0080, U+07FF, U+0800, U+FFFF, U+10000,
////   U+10FFFF, around the surrogates) with overlong forms, encoded
////   surrogates, stray continuation bytes and truncated sequences.
//// - Every array or object `gleam_json` writes is detected as
////   `application/json`.

import gleam/bit_array
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/string
import metamon
import metamon/generator.{type Generator}
import metamon/generator/range
import mimetype

fn utf8_piece_gen() -> Generator(BitArray) {
  generator.frequency([
    // Valid code points, ASCII without `<` so no markup is sniffed.
    #(
      4,
      generator.element_of([
        0x00, 0x09, 0x0A, 0x20, 0x41, 0x7A, 0x7F, 0x80, 0xE9, 0x7FF, 0x800,
        0x3042, 0xD7FF, 0xE000, 0xFFFD, 0xFFFF, 0x10000, 0x1F600, 0x10FFFF,
      ])
        |> generator.map(fn(code) {
          let assert Ok(cp) = string.utf_codepoint(code)
          bit_array.from_string(string.from_utf_codepoints([cp]))
        }),
    ),
    // Malformed sequences.
    #(
      1,
      generator.element_of([
        <<0x80>>,
        <<0xBF>>,
        <<0xC0, 0x80>>,
        <<0xC1, 0xBF>>,
        <<0xC2>>,
        <<0xE0, 0x80, 0x80>>,
        <<0xE0, 0x9F, 0xBF>>,
        <<0xED, 0xA0, 0x80>>,
        <<0xED, 0xBF, 0xBF>>,
        <<0xE3, 0x81>>,
        <<0xF0, 0x8F, 0xBF, 0xBF>>,
        <<0xF4, 0x90, 0x80, 0x80>>,
        <<0xF5, 0x80, 0x80, 0x80>>,
        <<0xFF>>,
        <<0xFE>>,
        <<0xF0, 0x9F, 0x98>>,
      ]),
    ),
  ])
}

fn text_gen() -> Generator(BitArray) {
  generator.list_of(utf8_piece_gen(), range.constant(1, 40))
  |> generator.map(fn(pieces) { bit_array.concat([<<"x":utf8>>, ..pieces]) })
}

fn all_ascii(bytes: BitArray) -> Bool {
  case bytes {
    <<>> -> True
    <<b, rest:bytes>> -> b < 0x80 && all_ascii(rest)
    _ -> False
  }
}

pub fn charset_of_utf8_scan_matches_the_standard_library_test() -> Nil {
  metamon.forall(text_gen(), fn(bytes) {
    let expected = case all_ascii(bytes), bit_array.to_string(bytes) {
      True, _ -> Ok("us-ascii")
      False, Ok(_) -> Ok("utf-8")
      False, Error(Nil) -> Error(Nil)
    }
    let actual = case mimetype.charset_of(bytes) {
      Ok(charset) -> Ok(charset)
      Error(_) -> Error(Nil)
    }
    actual == expected
  })
}

fn json_gen(depth: Int) -> Generator(json.Json) {
  let leaf =
    generator.one_of([
      generator.return(json.null()),
      generator.map(generator.bool(), json.bool),
      generator.map(generator.int(range.constant(-100_000, 100_000)), json.int),
      generator.map(generator.float(-1000.0, 1000.0), json.float),
      generator.map(
        generator.element_of(["", "a", "\"", "\\", "\n", "\u{00E9}", "{[,:]}"]),
        json.string,
      ),
    ])
  case depth {
    0 -> leaf
    _ ->
      generator.frequency([
        #(2, leaf),
        #(1, container_gen(depth - 1)),
      ])
  }
}

fn container_gen(depth: Int) -> Generator(json.Json) {
  generator.one_of([
    generator.list_of(json_gen(depth), range.constant(0, 4))
      |> generator.map(fn(items) { json.preprocessed_array(items) }),
    generator.list_of(
      generator.tuple2(
        generator.element_of(["a", "key", "\u{00E9}", "\""]),
        json_gen(depth),
      ),
      range.constant(0, 4),
    )
      |> generator.map(json.object),
  ])
}

pub fn documents_gleam_json_writes_are_detected_as_json_test() -> Nil {
  metamon.forall(
    generator.tuple2(
      container_gen(2),
      generator.element_of(["", " ", "\n", "\r\n\t "]),
    ),
    fn(input) {
      let #(document, padding) = input
      let text = padding <> json.to_string(document) <> padding
      // The oracle: gleam_json reads it back, so it is valid JSON.
      let assert Ok(_) = json.parse(text, decode.dynamic)
      mimetype.essence_of(mimetype.detect(bit_array.from_string(text)))
      == "application/json"
    },
  )
}

pub fn json_detection_ignores_a_leading_bom_test() -> Nil {
  metamon.forall(container_gen(1), fn(document) {
    let bytes = bit_array.from_string(json.to_string(document))
    list.all([bytes, <<0xEF, 0xBB, 0xBF, bytes:bits>>], fn(b) {
      mimetype.essence_of(mimetype.detect(b)) == "application/json"
    })
  })
}
