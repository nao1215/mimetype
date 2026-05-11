//// Internal parser primitives for RFC 9110 §12.5 `Accept`-family
//// headers. Kept private (in `mimetype/internal/`) — the facade
//// `mimetype/accept` re-exports the parts callers need.
////
//// Responsibilities:
////   - Quote-aware splitting on top-level commas.
////   - q-value parsing per RFC 9110 §12.5.5
////     (`qvalue = ( "0" [ "." 0*3DIGIT ] ) / ( "1" [ "." 0*3("0") ] )`).
////   - Splitting a parameter list at the first `q=` parameter so the
////     facade can separate media-range parameters from accept-ext.
////   - Token-list parsing for `Accept-Encoding`, `Accept-Charset`, and
////     `Accept-Language` (semicolon-separated `value[;q=...]`).

import gleam/bool
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

/// Split a header value on top-level `,` characters while keeping
/// commas that appear inside a quoted-string attached to the
/// surrounding entry. Backslash escapes inside a quoted-string are
/// honoured.
pub fn split_on_unquoted_commas(s: String) -> List(String) {
  do_split_commas(s, "", [], False, False)
  |> list.reverse
}

fn do_split_commas(
  remaining: String,
  current: String,
  acc: List(String),
  in_quote: Bool,
  escape: Bool,
) -> List(String) {
  case string.pop_grapheme(remaining) {
    Error(Nil) -> [current, ..acc]
    Ok(#(g, rest)) ->
      case escape, g, in_quote {
        True, _, _ -> do_split_commas(rest, current <> g, acc, in_quote, False)
        False, "\\", True ->
          do_split_commas(rest, current <> g, acc, in_quote, True)
        False, "\"", _ ->
          do_split_commas(rest, current <> g, acc, !in_quote, False)
        False, ",", False ->
          do_split_commas(rest, "", [current, ..acc], False, False)
        False, _, _ -> do_split_commas(rest, current <> g, acc, in_quote, False)
      }
  }
}

/// Walk a parameter segment list (already split on `;`) and return
/// `#(params_before_q, q_value, params_after_q)`. The `q` lookup is
/// case-insensitive on the name. Returns `Error(Nil)` if a `q=`
/// segment is present but the value is not a valid qvalue. Returns
/// `Ok(#(all, 1.0, []))` if no `q=` parameter is present.
pub fn split_at_q(
  segments: List(String),
) -> Result(#(List(String), Float, List(String)), Nil) {
  do_split_at_q(segments, [])
}

fn do_split_at_q(
  remaining: List(String),
  before: List(String),
) -> Result(#(List(String), Float, List(String)), Nil) {
  case remaining {
    [] -> Ok(#(list.reverse(before), 1.0, []))
    [seg, ..rest] ->
      case extract_q(seg) {
        Some(raw) ->
          case parse_q_value(raw) {
            Ok(q) -> Ok(#(list.reverse(before), q, rest))
            Error(Nil) -> Error(Nil)
          }
        None -> do_split_at_q(rest, [seg, ..before])
      }
  }
}

fn extract_q(segment: String) -> Option(String) {
  case string.split_once(segment, on: "=") {
    Error(Nil) -> None
    Ok(#(name, value)) -> {
      let normalized = name |> string.trim |> string.lowercase
      case normalized == "q" {
        True -> Some(string.trim(value))
        False -> None
      }
    }
  }
}

/// Parse an RFC 9110 §12.5.5 qvalue (`0`, `0.5`, `1`, `1.000` etc.).
///
/// Accepts the lenient short forms `0`, `0.`, `1`, `1.` and the
/// unquoted form (RFC 9110 disallows surrounding double quotes for
/// the `weight` rule). Returns `Error(Nil)` for empty input, values
/// outside `[0.0, 1.0]`, more than three fractional digits, or any
/// non-digit character.
pub fn parse_q_value(raw: String) -> Result(Float, Nil) {
  let trimmed = string.trim(raw)
  use <- bool.guard(when: trimmed == "", return: Error(Nil))
  case string.split_once(trimmed, on: ".") {
    Error(Nil) ->
      case trimmed {
        "0" -> Ok(0.0)
        "1" -> Ok(1.0)
        _ -> Error(Nil)
      }
    Ok(#(int_part, frac_part)) ->
      case int_part {
        "0" -> parse_fraction_with_int(0, frac_part)
        "1" -> parse_fraction_with_int(1, frac_part)
        _ -> Error(Nil)
      }
  }
}

fn parse_fraction_with_int(
  int_part: Int,
  frac_part: String,
) -> Result(Float, Nil) {
  // RFC 9110: up to 3 fractional digits.
  use <- bool.guard(when: string.length(frac_part) > 3, return: Error(Nil))
  case frac_part {
    "" -> Ok(int.to_float(int_part))
    _ ->
      case int.parse(frac_part) {
        Error(Nil) -> Error(Nil)
        Ok(frac_int) -> {
          // For "1", every fractional digit must be 0 to keep the
          // total <= 1.0.
          use <- bool.guard(
            when: int_part == 1 && frac_int != 0,
            return: Error(Nil),
          )
          let denom = case string.length(frac_part) {
            1 -> 10.0
            2 -> 100.0
            3 -> 1000.0
            // length 0 handled above
            _ -> 1.0
          }
          Ok(int.to_float(int_part) +. int.to_float(frac_int) /. denom)
        }
      }
  }
}

/// Parse the simple comma-separated `value[;q=...]` form used by
/// `Accept-Encoding`, `Accept-Charset`, and `Accept-Language`. Returns
/// `Error(Nil)` if any entry has a syntactically invalid q-value or a
/// missing value.
pub fn parse_token_list(header: String) -> Result(List(#(String, Float)), Nil) {
  let trimmed = string.trim(header)
  use <- bool.guard(when: trimmed == "", return: Ok([]))
  split_on_unquoted_commas(trimmed)
  |> list.filter_map(fn(entry) {
    case string.trim(entry) {
      "" -> Error(Nil)
      non_empty -> Ok(non_empty)
    }
  })
  |> list.try_map(parse_token_entry)
}

fn parse_token_entry(entry: String) -> Result(#(String, Float), Nil) {
  let segments = case string.contains(entry, ";") {
    True -> string.split(entry, on: ";")
    False -> [entry]
  }
  case segments {
    [] -> Error(Nil)
    [value_raw, ..params] -> {
      let value = value_raw |> string.trim |> string.lowercase
      use <- bool.guard(when: value == "", return: Error(Nil))
      case split_at_q(params) {
        Error(Nil) -> Error(Nil)
        Ok(#(_before, q, _after)) -> Ok(#(value, q))
      }
    }
  }
}
