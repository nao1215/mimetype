//// Charset detection for text, and byte helpers shared with `magic`.
////
//// The signals, in order: a Unicode byte order mark, the `encoding` of
//// an XML declaration, a `<meta>` charset in the first 1024 bytes, and
//// a UTF-8 scan of the first 3072 bytes.

import gleam/bit_array
import gleam/bool
import gleam/list
import gleam/result
import gleam/string

// The XML declaration and `<meta>` have to appear this early (WHATWG
// HTML, "prescan a byte stream").
const declaration_limit = 1024

// The same number of bytes as detection reads.
const scan_limit = 3072

pub fn detect(bytes: BitArray) -> Result(String, Nil) {
  use <- result.lazy_or(byte_order_mark(bytes))
  let head = ascii_text(bytes, declaration_limit)
  use <- result.lazy_or(xml_encoding(head))
  use <- result.lazy_or(meta_charset(head))
  scan_utf8(bytes)
}

// The UTF-32LE mark starts with the UTF-16LE one, so it is tried first.
fn byte_order_mark(bytes: BitArray) -> Result(String, Nil) {
  case bytes {
    <<0xFF, 0xFE, 0x00, 0x00, _:bits>> -> Ok("utf-32le")
    <<0x00, 0x00, 0xFE, 0xFF, _:bits>> -> Ok("utf-32be")
    <<0xEF, 0xBB, 0xBF, _:bits>> -> Ok("utf-8")
    <<0xFF, 0xFE, _:bits>> -> Ok("utf-16le")
    <<0xFE, 0xFF, _:bits>> -> Ok("utf-16be")
    _ -> Error(Nil)
  }
}

fn xml_encoding(head: String) -> Result(String, Nil) {
  case string.trim_start(head) {
    "<?xml" <> declaration -> {
      let declaration = case string.split_once(declaration, "?>") {
        Ok(#(declaration, _)) -> declaration
        Error(Nil) -> declaration
      }
      attribute_value(declaration, "encoding")
    }
    _ -> Error(Nil)
  }
}

// The first `<meta>` tag with a non-empty charset, either as its own
// attribute or inside `content` (`http-equiv="Content-Type"`).
fn meta_charset(head: String) -> Result(String, Nil) {
  case string.split(string.lowercase(head), "<meta") {
    [_, ..tags] -> list.find_map(tags, tag_charset)
    [] -> Error(Nil)
  }
}

// `tag` follows `<meta`; whitespace or `/` has to come next, so that
// `<metadata>` is not a meta tag.
fn tag_charset(tag: String) -> Result(String, Nil) {
  case tag {
    " " <> _ | "\t" <> _ | "\n" <> _ | "\r" <> _ | "\f" <> _ | "/" <> _ ->
      case string.split_once(tag, ">") {
        Ok(#(attributes, _)) -> attribute_value(attributes, "charset")
        Error(Nil) -> attribute_value(tag, "charset")
      }
    _ -> Error(Nil)
  }
}

// The lowercased, non-empty value after `name` and `=`, quoted or not.
fn attribute_value(text: String, name: String) -> Result(String, Nil) {
  use #(_, after) <- result.try(string.split_once(text, name))
  use after <- result.try(case string.trim_start(after) {
    "=" <> after -> Ok(string.trim_start(after))
    _ -> Error(Nil)
  })
  use value <- result.try(case after {
    "\"" <> rest -> quoted(rest, "\"")
    "'" <> rest -> quoted(rest, "'")
    _ ->
      Ok(
        take_until(after, [" ", "\t", "\n", "\r", ">", "/", ";", ",", "\"", "'"]),
      )
  })
  case string.trim(value) {
    "" -> Error(Nil)
    value -> Ok(string.lowercase(value))
  }
}

// A quoted value without its closing quote was cut off.
fn quoted(text: String, quote: String) -> Result(String, Nil) {
  string.split_once(text, quote) |> result.map(fn(pair) { pair.0 })
}

fn take_until(text: String, ends: List(String)) -> String {
  list.fold(ends, text, fn(text, end) {
    case string.split_once(text, end) {
      Ok(#(before, _)) -> before
      Error(Nil) -> text
    }
  })
}

// The first `limit` bytes as a string, with every byte above 0x7F
// replaced by DEL. The declarations are ASCII, and a document that
// declares its charset is usually not UTF-8.
fn ascii_text(bytes: BitArray, limit: Int) -> String {
  ascii_bytes(bytes, limit, [])
  |> list.reverse
  |> bit_array.concat
  |> bit_array.to_string
  |> result.unwrap("")
}

fn ascii_bytes(
  bytes: BitArray,
  limit: Int,
  acc: List(BitArray),
) -> List(BitArray) {
  use <- bool.guard(when: limit <= 0, return: acc)
  case bytes {
    <<byte, rest:bytes>> if byte < 0x80 ->
      ascii_bytes(rest, limit - 1, [<<byte>>, ..acc])
    <<_, rest:bytes>> -> ascii_bytes(rest, limit - 1, [<<0x7F>>, ..acc])
    _ -> acc
  }
}

// `us-ascii` when every byte is below 0x80, `utf-8` for valid UTF-8.
// Binary data bytes rule the input out. A character that the scan limit
// cuts in two counts as valid.
fn scan_utf8(bytes: BitArray) -> Result(String, Nil) {
  let cut = bit_array.byte_size(bytes) > scan_limit
  let head = bit_array.slice(bytes, 0, scan_limit) |> result.unwrap(bytes)
  case has_binary_data_byte(head), utf8_verdict(head, cut, False) {
    False, Ok(True) -> Ok("utf-8")
    False, Ok(False) -> Ok("us-ascii")
    _, _ -> Error(Nil)
  }
}

// `Ok(saw_multibyte)` for valid UTF-8.
fn utf8_verdict(
  bytes: BitArray,
  cut: Bool,
  multibyte: Bool,
) -> Result(Bool, Nil) {
  case bytes {
    <<>> -> Ok(multibyte)
    <<b, rest:bytes>> if b < 0x80 -> utf8_verdict(rest, cut, multibyte)
    <<b1, b2, rest:bytes>>
      if b1 >= 0xC2 && b1 <= 0xDF && b2 >= 0x80 && b2 <= 0xBF
    -> utf8_verdict(rest, cut, True)
    <<b1, b2, b3, rest:bytes>>
      if b1 >= 0xE0 && b1 <= 0xEF && b3 >= 0x80 && b3 <= 0xBF
    ->
      case second_byte_ok(b1, b2) {
        True -> utf8_verdict(rest, cut, True)
        False -> Error(Nil)
      }
    <<b1, b2, b3, b4, rest:bytes>>
      if b1 >= 0xF0
      && b1 <= 0xF4
      && b3 >= 0x80
      && b3 <= 0xBF
      && b4 >= 0x80
      && b4 <= 0xBF
    ->
      case second_byte_ok(b1, b2) {
        True -> utf8_verdict(rest, cut, True)
        False -> Error(Nil)
      }
    _ ->
      case cut && is_incomplete_sequence(bytes) {
        True -> Ok(True)
        False -> Error(Nil)
      }
  }
}

// The start of a valid sequence that the input ends inside.
fn is_incomplete_sequence(bytes: BitArray) -> Bool {
  case bytes {
    <<b1>> -> b1 >= 0xC2 && b1 <= 0xF4
    <<b1, b2>> -> b1 >= 0xE0 && b1 <= 0xF4 && second_byte_ok(b1, b2)
    <<b1, b2, b3>> ->
      b1 >= 0xF0
      && b1 <= 0xF4
      && second_byte_ok(b1, b2)
      && b3 >= 0x80
      && b3 <= 0xBF
    _ -> False
  }
}

/// The allowed range of the second byte of a 3- or 4-byte sequence
/// (Unicode Table 3-7, RFC 3629 section 4). The narrower ranges after
/// E0, ED, F0 and F4 reject overlong forms, UTF-16 surrogates
/// (U+D800-U+DFFF) and code points above U+10FFFF.
fn second_byte_ok(lead: Int, second: Int) -> Bool {
  let #(lo, hi) = case lead {
    0xE0 -> #(0xA0, 0xBF)
    0xED -> #(0x80, 0x9F)
    0xF0 -> #(0x90, 0xBF)
    0xF4 -> #(0x80, 0x8F)
    _ -> #(0x80, 0xBF)
  }
  second >= lo && second <= hi
}

/// Whether `bytes` holds a binary data byte as WHATWG MIME Sniffing
/// defines it: 0x00 to 0x08, 0x0B, 0x0E to 0x1A, or 0x1C to 0x1F.
pub fn has_binary_data_byte(bytes: BitArray) -> Bool {
  case bytes {
    <<byte, _:bytes>>
      if byte <= 0x08
      || byte == 0x0B
      || byte >= 0x0E
      && byte <= 0x1A
      || byte >= 0x1C
      && byte <= 0x1F
    -> True
    <<_, rest:bytes>> -> has_binary_data_byte(rest)
    _ -> False
  }
}

/// Drops a leading UTF-8 byte order mark.
pub fn strip_utf8_bom(bytes: BitArray) -> BitArray {
  case bytes {
    <<0xEF, 0xBB, 0xBF, rest:bits>> -> rest
    _ -> bytes
  }
}

/// Drops leading HTML whitespace (space, tab, LF, FF, CR).
pub fn skip_whitespace(bytes: BitArray) -> BitArray {
  case bytes {
    <<0x20, rest:bits>>
    | <<0x09, rest:bits>>
    | <<0x0A, rest:bits>>
    | <<0x0C, rest:bits>>
    | <<0x0D, rest:bits>> -> skip_whitespace(rest)
    _ -> bytes
  }
}
