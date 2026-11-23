//// Parsing helpers for the RFC 9110 §12.5 `Accept`-family headers.

import gleam/bool
import gleam/int
import gleam/list
import gleam/result
import gleam/string

/// Separates the weight from the `;`-separated segments that follow a
/// media range or a value. Every parameter named `q` (in any case) is a
/// weight, wherever it appears (RFC 9110 §12.5.1), and the first one
/// decides. Returns the other segments and the weight, 1.0 when there
/// is none, or `Error(Nil)` when the deciding value is not a qvalue.
pub fn split_weight(
  segments: List(String),
) -> Result(#(List(String), Float), Nil) {
  let #(weights, parameters) = list.partition(segments, is_weight)
  case weights {
    [] -> Ok(#(parameters, 1.0))
    [weight, ..] ->
      weight
      |> string.split_once("=")
      |> result.try(fn(pair) { parse_qvalue(string.trim(pair.1)) })
      |> result.map(fn(quality) { #(parameters, quality) })
  }
}

fn is_weight(segment: String) -> Bool {
  case string.split_once(segment, "=") {
    Ok(#(name, _)) -> string.lowercase(string.trim(name)) == "q"
    Error(Nil) -> False
  }
}

/// RFC 9110 §12.4.2:
/// `qvalue = ( "0" [ "." 0*3DIGIT ] ) / ( "1" [ "." 0*3("0") ] )`.
fn parse_qvalue(raw: String) -> Result(Float, Nil) {
  let #(whole, fraction) = case string.split_once(raw, ".") {
    Ok(pair) -> pair
    Error(Nil) -> #(raw, "")
  }
  let digits = string.to_graphemes(fraction)
  use <- bool.guard(
    when: list.length(digits) > 3 || !list.all(digits, is_digit),
    return: Error(Nil),
  )
  let thousandths =
    string.pad_end(fraction, 3, "0") |> int.parse |> result.unwrap(0)
  case whole {
    "0" -> Ok(int.to_float(thousandths) /. 1000.0)
    "1" if thousandths == 0 -> Ok(1.0)
    _ -> Error(Nil)
  }
}

fn is_digit(grapheme: String) -> Bool {
  case grapheme {
    "0" | "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9" -> True
    _ -> False
  }
}

/// Parses one `value[;q=...]` entry of `Accept-Encoding`,
/// `Accept-Charset` or `Accept-Language`, lowercasing the value. Returns
/// `Error(Nil)` when the weight is not a qvalue or the value is empty.
pub fn parse_value(entry: String) -> Result(#(String, Float), Nil) {
  let #(value, parameters) = case string.split(entry, on: ";") {
    [value, ..parameters] -> #(value, parameters)
    [] -> #(entry, [])
  }
  let value = value |> string.trim |> string.lowercase
  use #(_, quality) <- result.try(split_weight(parameters))
  use <- bool.guard(when: value == "", return: Error(Nil))
  Ok(#(value, quality))
}
