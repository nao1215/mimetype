//// RFC 7230 §3.2.6 / RFC 6838 parsing and serialisation primitives.
////
//// All functions in this module operate on plain strings and
//// `(name, value)` tuples — none of them know about the public
//// `MimeType` opaque value. The facade (`mimetype`) wraps the
//// `(essence, parameters)` pair returned here into a `MimeType`.
////
//// Exposes:
////   - `parse_string` — wire-format parser, returns the essence and
////     the parsed parameter list.
////   - `serialise` — the symmetric inverse of `parse_string`. Quotes
////     parameter values that aren't a valid RFC 7230 token.
////   - `is_token` — public RFC 7230 §3.2.6 token predicate, used by
////     `internal/parameters` and the future quoted-key path.

import gleam/bool
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

/// Parse-side failure modes. Internal — the facade translates these
/// into its public `ParseError` constructors before returning to the
/// caller.
pub type ParseFailure {
  /// Input was empty or whitespace-only.
  Empty
  /// Input did not match the `type/subtype` essence shape; carries
  /// the original string for the caller's `InvalidMimeType` payload.
  InvalidEssence(original: String)
  /// A parameter value contained an ASCII control byte that is valid
  /// in neither `token` nor `quoted-string` per RFC 7231 §3.1.1.1.
  /// `byte` is the offending codepoint (0..31 except 9; or 127);
  /// `parameter` is the parameter name whose value was rejected so
  /// the caller can render an actionable error.
  InvalidParameterValue(parameter: String, byte: Int)
}

/// Parse a wire-format MIME string into its essence + parameter list.
///
/// Rejects parameter values containing ASCII control bytes (0x00-0x1F
/// except HTAB `0x09`, plus DEL `0x7F`): these are valid in neither
/// `token` nor `quoted-string` per RFC 7231 §3.1.1.1, and emitting
/// them on the wire produces a `Content-Type` header that downstream
/// HTTP libraries refuse. Returns `InvalidParameterValue(parameter,
/// byte)` naming the offending parameter and the rejected codepoint.
pub fn parse_string(
  input: String,
) -> Result(#(String, List(#(String, String))), ParseFailure) {
  let trimmed = string.trim(input)
  use <- bool.guard(when: trimmed == "", return: Error(Empty))
  case split_on_unquoted_semicolons(trimmed) {
    [] -> Error(Empty)
    [head, ..rest] -> {
      let essence_value = head |> string.trim |> string.lowercase
      use <- bool.guard(
        when: !valid_essence(essence_value),
        return: Error(InvalidEssence(input)),
      )
      case parse_parameters(rest) {
        Ok(parameters) -> Ok(#(essence_value, parameters))
        Error(e) -> Error(e)
      }
    }
  }
}

/// Serialise an `(essence, parameters)` pair back to wire format.
///
/// Whitespace is normalised (`type/subtype; key=value`, single space
/// after each `;`). Parameter values that are not a valid `token` per
/// RFC 7230 §3.2.6 — including the empty string and any value
/// containing whitespace, `;`, `,`, `"`, etc. — are wrapped in a
/// quoted-string with inner `"` and `\` backslash-escaped.
pub fn serialise(essence: String, parameters: List(#(String, String))) -> String {
  case parameters {
    [] -> essence
    _ -> {
      let serialised_parameters =
        parameters
        |> list.map(fn(p) {
          let #(k, v) = p
          k <> "=" <> quote_value(v)
        })
        |> string.join("; ")
      essence <> "; " <> serialised_parameters
    }
  }
}

/// Check whether `s` is a non-empty `token` per RFC 7230 §3.2.6:
/// `1*tchar`, where `tchar` is a printable ASCII character that is
/// neither whitespace, a control character, nor an HTTP separator
/// (`(` `)` `<` `>` `@` `,` `;` `:` `\` `"` `/` `[` `]` `?` `=` `{` `}`).
pub fn is_token(s: String) -> Bool {
  use <- bool.guard(when: s == "", return: False)
  string.to_utf_codepoints(s)
  |> list.all(fn(cp) { is_tchar(string.utf_codepoint_to_int(cp)) })
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

/// Split on top-level `;` while keeping `;` characters that appear
/// inside an RFC 7230 §3.2.6 quoted-string (`"..."`) attached to the
/// surrounding value. Backslash escapes (`\"`, `\\`, `\;` etc.) within
/// a quoted-string are honoured so the next character does not toggle
/// the quote state.
fn split_on_unquoted_semicolons(s: String) -> List(String) {
  do_split_semis(s, "", [], False, False)
  |> list.reverse
}

fn do_split_semis(
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
        True, _, _ -> do_split_semis(rest, current <> g, acc, in_quote, False)
        False, "\\", True ->
          do_split_semis(rest, current <> g, acc, in_quote, True)
        False, "\"", _ ->
          do_split_semis(rest, current <> g, acc, !in_quote, False)
        False, ";", False ->
          do_split_semis(rest, "", [current, ..acc], False, False)
        False, _, _ -> do_split_semis(rest, current <> g, acc, in_quote, False)
      }
  }
}

fn valid_essence(essence: String) -> Bool {
  case string.split_once(essence, on: "/") {
    Ok(#(t, sub)) -> is_token(t) && is_token(sub)
    Error(Nil) -> False
  }
}

fn is_tchar(cp: Int) -> Bool {
  case cp {
    // ALPHA
    cp if cp >= 65 && cp <= 90 -> True
    cp if cp >= 97 && cp <= 122 -> True
    // DIGIT
    cp if cp >= 48 && cp <= 57 -> True
    // ! # $ % & ' * + - .
    33 | 35 | 36 | 37 | 38 | 39 | 42 | 43 | 45 | 46 -> True
    // ^ _ ` | ~
    94 | 95 | 96 | 124 | 126 -> True
    _ -> False
  }
}

fn parse_parameters(
  segments: List(String),
) -> Result(List(#(String, String)), ParseFailure) {
  segments
  |> list.try_fold([], parse_parameter_segment)
  |> result.map(list.reverse)
}

// Same lenience as the previous `list.filter_map` shape for
// non-`name=value` and empty-name segments — a stray `;` mid-string
// should not abort the parse. Forbidden control bytes inside a value
// abort, naming the offending parameter.
fn parse_parameter_segment(
  acc: List(#(String, String)),
  seg: String,
) -> Result(List(#(String, String)), ParseFailure) {
  case string.split_once(seg, on: "=") {
    Error(Nil) -> Ok(acc)
    Ok(#(name, value)) -> {
      let normalized_name = name |> string.trim |> string.lowercase
      let normalized_value = value |> string.trim |> unquote_value
      use <- bool.guard(when: normalized_name == "", return: Ok(acc))
      case forbidden_control_byte(normalized_value) {
        Some(byte) ->
          Error(InvalidParameterValue(parameter: normalized_name, byte: byte))
        None -> Ok([#(normalized_name, normalized_value), ..acc])
      }
    }
  }
}

/// Return `Some(byte)` for the first ASCII control byte in `s` that is
/// invalid in a parameter value, or `None` if every byte is allowed.
/// Allowed: HTAB (0x09) and every byte at or above 0x20 except DEL
/// (0x7F). Rejected: 0x00-0x08, 0x0A-0x1F, 0x7F.
fn forbidden_control_byte(s: String) -> Option(Int) {
  string.to_utf_codepoints(s)
  |> list.fold(None, fn(found, cp) {
    case found {
      Some(_) -> found
      None -> {
        let codepoint = string.utf_codepoint_to_int(cp)
        case is_forbidden_control(codepoint) {
          True -> Some(codepoint)
          False -> None
        }
      }
    }
  })
}

fn is_forbidden_control(codepoint: Int) -> Bool {
  case codepoint {
    9 -> False
    127 -> True
    cp if cp < 32 -> True
    _ -> False
  }
}

/// Wrap a parameter value for serialisation per RFC 7230 §3.2.6.
fn quote_value(value: String) -> String {
  use <- bool.guard(when: is_token(value), return: value)
  "\"" <> escape_quoted(value, "") <> "\""
}

fn escape_quoted(remaining: String, acc: String) -> String {
  case string.pop_grapheme(remaining) {
    Error(Nil) -> acc
    Ok(#("\"", rest)) -> escape_quoted(rest, acc <> "\\\"")
    Ok(#("\\", rest)) -> escape_quoted(rest, acc <> "\\\\")
    Ok(#(other, rest)) -> escape_quoted(rest, acc <> other)
  }
}

/// Unwrap a parameter value from RFC 7230 §3.2.6 quoted-string form.
fn unquote_value(value: String) -> String {
  use <- bool.guard(
    when: !{ string.starts_with(value, "\"") && string.ends_with(value, "\"") },
    return: value,
  )
  // Reject the lone `"` case (length 1: starts AND ends match the
  // same character, so the slice is empty but we'd otherwise
  // discard the original character).
  use <- bool.guard(when: string.length(value) < 2, return: value)
  let inner = value |> string.drop_start(1) |> string.drop_end(1)
  unescape_quoted(inner, "")
}

fn unescape_quoted(remaining: String, acc: String) -> String {
  case string.pop_grapheme(remaining) {
    Error(Nil) -> acc
    Ok(#("\\", rest)) ->
      case string.pop_grapheme(rest) {
        Ok(#(escaped, after)) -> unescape_quoted(after, acc <> escaped)
        // Trailing lone backslash: keep it as-is.
        Error(Nil) -> acc <> "\\"
      }
    Ok(#(other, rest)) -> unescape_quoted(rest, acc <> other)
  }
}
