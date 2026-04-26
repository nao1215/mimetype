//// Charset detection for text payloads.
////
//// Resolves the character encoding of a `BitArray` by composing four
//// signals in priority order:
////
////   1. Unicode BOM (UTF-8, UTF-16 LE/BE, UTF-32 LE/BE)
////   2. XML prolog `<?xml ... encoding="..." ?>`
////   3. HTML `<meta charset="...">` (or `http-equiv` `content` charset)
////   4. UTF-8 validity heuristic — `utf-8` for valid multi-byte UTF-8,
////      `us-ascii` for input that is entirely 0x00–0x7F.
////
//// Returns `Error(Nil)` when none of the signals fire (typically
//// non-UTF-8 high-byte content like Latin-1 or Shift_JIS without an
//// in-document declaration).

import gleam/bit_array
import gleam/bool
import gleam/result
import gleam/string

const scan_budget = 1024

pub fn detect(bytes: BitArray) -> Result(String, Nil) {
  use <- guard_bom(bytes)
  use <- guard_xml(bytes)
  use <- guard_html(bytes)
  utf8_or_ascii(bytes)
}

fn guard_bom(
  bytes: BitArray,
  fallback: fn() -> Result(String, Nil),
) -> Result(String, Nil) {
  case bytes {
    <<0xFF, 0xFE, 0x00, 0x00, _:bits>> -> Ok("utf-32le")
    <<0x00, 0x00, 0xFE, 0xFF, _:bits>> -> Ok("utf-32be")
    <<0xEF, 0xBB, 0xBF, _:bits>> -> Ok("utf-8")
    <<0xFF, 0xFE, _:bits>> -> Ok("utf-16le")
    <<0xFE, 0xFF, _:bits>> -> Ok("utf-16be")
    _ -> fallback()
  }
}

fn guard_xml(
  bytes: BitArray,
  fallback: fn() -> Result(String, Nil),
) -> Result(String, Nil) {
  case xml_prolog_encoding(bytes) {
    Ok(charset) -> Ok(charset)
    Error(Nil) -> fallback()
  }
}

fn guard_html(
  bytes: BitArray,
  fallback: fn() -> Result(String, Nil),
) -> Result(String, Nil) {
  case html_meta_charset(bytes) {
    Ok(charset) -> Ok(charset)
    Error(Nil) -> fallback()
  }
}

fn xml_prolog_encoding(bytes: BitArray) -> Result(String, Nil) {
  use <- bool.guard(when: !starts_with_xml_prolog(bytes), return: Error(Nil))
  case to_string_bounded(bytes, scan_budget) {
    Ok(text) -> {
      use prolog <- result.try(slice_to_substring(text, "?>"))
      attribute_value(prolog, "encoding")
    }
    Error(Nil) -> Error(Nil)
  }
}

fn html_meta_charset(bytes: BitArray) -> Result(String, Nil) {
  case to_string_bounded(bytes, scan_budget) {
    Ok(text) -> meta_charset_in_text(text)
    Error(Nil) -> Error(Nil)
  }
}

fn meta_charset_in_text(text: String) -> Result(String, Nil) {
  let lower = string.lowercase(text)
  use <- bool.guard(when: !string.contains(lower, "<meta"), return: Error(Nil))
  case attribute_value(lower, "charset") {
    Ok(value) -> Ok(value)
    Error(Nil) ->
      attribute_value(lower, "content")
      |> result.try(fn(content) { attribute_value(content, "charset") })
  }
}

fn utf8_or_ascii(bytes: BitArray) -> Result(String, Nil) {
  case scan_utf8(bytes, False, 0) {
    UnknownEncoding -> Error(Nil)
    PureAscii -> Ok("us-ascii")
    ValidUtf8 -> Ok("utf-8")
  }
}

type Utf8Verdict {
  PureAscii
  ValidUtf8
  UnknownEncoding
}

fn scan_utf8(bytes: BitArray, saw_multibyte: Bool, walked: Int) -> Utf8Verdict {
  use <- bool.lazy_guard(when: walked >= scan_budget, return: fn() {
    case saw_multibyte {
      True -> ValidUtf8
      False -> PureAscii
    }
  })
  case bytes {
    <<>> ->
      case saw_multibyte {
        True -> ValidUtf8
        False -> PureAscii
      }
    <<b, rest:bits>> if b <= 0x7F -> scan_utf8(rest, saw_multibyte, walked + 1)
    <<0xC2, b2, rest:bits>> if b2 >= 0x80 && b2 <= 0xBF ->
      scan_utf8(rest, True, walked + 2)
    <<b1, b2, rest:bits>>
      if b1 >= 0xC3 && b1 <= 0xDF && b2 >= 0x80 && b2 <= 0xBF
    -> scan_utf8(rest, True, walked + 2)
    <<b1, b2, b3, rest:bits>>
      if b1 >= 0xE0
      && b1 <= 0xEF
      && b2 >= 0x80
      && b2 <= 0xBF
      && b3 >= 0x80
      && b3 <= 0xBF
    -> scan_utf8(rest, True, walked + 3)
    <<b1, b2, b3, b4, rest:bits>>
      if b1 >= 0xF0
      && b1 <= 0xF4
      && b2 >= 0x80
      && b2 <= 0xBF
      && b3 >= 0x80
      && b3 <= 0xBF
      && b4 >= 0x80
      && b4 <= 0xBF
    -> scan_utf8(rest, True, walked + 4)
    _ -> UnknownEncoding
  }
}

fn starts_with_xml_prolog(bytes: BitArray) -> Bool {
  let stripped = strip_utf8_bom(bytes)
  let trimmed = skip_ws(stripped)
  case trimmed {
    <<"<?xml":utf8, _:bits>> -> True
    _ -> False
  }
}

fn strip_utf8_bom(bytes: BitArray) -> BitArray {
  case bytes {
    <<0xEF, 0xBB, 0xBF, rest:bits>> -> rest
    _ -> bytes
  }
}

fn skip_ws(bytes: BitArray) -> BitArray {
  case bytes {
    <<0x20, rest:bits>> -> skip_ws(rest)
    <<0x09, rest:bits>> -> skip_ws(rest)
    <<0x0A, rest:bits>> -> skip_ws(rest)
    <<0x0C, rest:bits>> -> skip_ws(rest)
    <<0x0D, rest:bits>> -> skip_ws(rest)
    _ -> bytes
  }
}

fn to_string_bounded(bytes: BitArray, limit: Int) -> Result(String, Nil) {
  let size = bit_array.byte_size(bytes)
  let take = case limit > size {
    True -> size
    False -> limit
  }
  bit_array.slice(bytes, 0, take)
  |> result.try(bit_array.to_string)
}

fn slice_to_substring(text: String, terminator: String) -> Result(String, Nil) {
  case string.split_once(text, on: terminator) {
    Ok(#(prefix, _)) -> Ok(prefix)
    Error(Nil) -> Ok(text)
  }
}

/// Find `attribute=` in `text` (case-sensitive on the attribute name —
/// callers should lowercase the input first). Returns the value, with
/// surrounding quotes stripped and whitespace / trailing delimiters
/// trimmed. The value is lowercased to match charset registry
/// conventions.
fn attribute_value(text: String, attribute: String) -> Result(String, Nil) {
  use after_name <- result.try(after_attribute_name(text, attribute))
  let after_eq = consume_equals(after_name)
  use #(raw, _) <- result.try(read_value(after_eq))
  Ok(string.lowercase(string.trim(raw)))
}

fn after_attribute_name(text: String, attribute: String) -> Result(String, Nil) {
  case string.split_once(text, on: attribute) {
    Ok(#(_, after)) -> Ok(after)
    Error(Nil) -> Error(Nil)
  }
}

fn consume_equals(text: String) -> String {
  let stripped = string.trim_start(text)
  case string.starts_with(stripped, "=") {
    True -> string.trim_start(string.drop_start(stripped, 1))
    False -> stripped
  }
}

fn read_value(text: String) -> Result(#(String, String), Nil) {
  case string.starts_with(text, "\"") {
    True -> read_quoted(string.drop_start(text, 1), "\"")
    False ->
      case string.starts_with(text, "'") {
        True -> read_quoted(string.drop_start(text, 1), "'")
        False -> Ok(read_unquoted(text))
      }
  }
}

fn read_quoted(text: String, quote: String) -> Result(#(String, String), Nil) {
  case string.split_once(text, on: quote) {
    Ok(#(value, rest)) -> Ok(#(value, rest))
    Error(Nil) -> Error(Nil)
  }
}

fn read_unquoted(text: String) -> #(String, String) {
  let value = take_unquoted(text, "")
  let rest = string.drop_start(text, string.length(value))
  #(value, rest)
}

fn take_unquoted(text: String, acc: String) -> String {
  case string.pop_grapheme(text) {
    Error(Nil) -> acc
    Ok(#(g, rest)) ->
      case is_value_terminator(g) {
        True -> acc
        False -> take_unquoted(rest, acc <> g)
      }
  }
}

fn is_value_terminator(g: String) -> Bool {
  g == " "
  || g == "\t"
  || g == "\n"
  || g == "\r"
  || g == ">"
  || g == "/"
  || g == ";"
  || g == ","
  || g == "\""
  || g == "'"
}
