//// RFC 9110 §12.5 content negotiation: parser and selector for the
//// `Accept`, `Accept-Encoding`, `Accept-Charset`, and `Accept-Language`
//// header families.
////
//// The module exposes:
////   - `parse/1` — turn a raw `Accept` header into a list of
////     `AcceptItem` values, preserving the client's q-values and any
////     accept-ext parameters (RFC 9110 §12.5.1).
////   - `prefer/1` — stable-sort parsed items by `(q desc, specificity
////     desc, accept-ext count desc)` so callers can iterate in the
////     order the client most prefers.
////   - `negotiate/2` — given a parsed client header and a list of
////     server offers, return the best `MimeType` to serve, or `None`
////     when no offer is acceptable. Implements the §12.5.1
////     proactive-negotiation algorithm with the documented essence-only
////     matching restriction.
////   - `parse_encoding/1`, `parse_charset/1`, `parse_language/1` and
////     their companion `prefer_values/1` / `negotiate_value/2`.

import gleam/bool
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order.{type Order, Eq}
import gleam/string
import mimetype.{type MimeType}
import mimetype/internal/accept as accept_internal
import mimetype/internal/parse as parse_internal

/// A single media-range entry as it appears on the wire.
///
/// - `Specific(mt)` matches a concrete `type/subtype`. Parameter-level
///   "more-specific" matching per RFC 9110 §12.5.1 is out of scope:
///   matching looks at the essence only and ignores attached
///   media-range parameters (other than `q` and accept-ext, which are
///   carried on `AcceptItem`).
/// - `TypeWildcard(type_)` matches any subtype within a top-level type
///   (e.g. `image/*`). The carried `type_` is already lowercased.
/// - `AnyType` matches any media range (`*/*`).
pub type MediaRange {
  Specific(MimeType)
  TypeWildcard(type_: String)
  AnyType
}

/// One parsed entry from an `Accept` header. `q` defaults to `1.0` if
/// the wire form omits it; `extensions` holds the accept-ext name/value
/// pairs that appeared *after* the `q=` parameter, with names
/// lowercased and values preserved.
pub type AcceptItem {
  AcceptItem(range: MediaRange, q: Float, extensions: List(#(String, String)))
}

/// One parsed entry from `Accept-Encoding`, `Accept-Charset`, or
/// `Accept-Language`. The `value` is lowercased.
pub type ValueItem {
  ValueItem(value: String, q: Float)
}

/// Why a header could not be parsed.
pub type AcceptError {
  /// An entry did not match the expected `media-range[;params]` shape.
  /// `at` is the zero-based entry index; `raw` is the raw entry text.
  Malformed(at: Int, raw: String)
  /// An entry's q-value was syntactically invalid.
  InvalidQValue(raw: String)
  /// A media-range field was not a wildcard, a `type/*` form, or a
  /// valid `type/subtype` per RFC 6838.
  InvalidMediaRange(raw: String)
}

// ---------------------------------------------------------------------------
// Accept header
// ---------------------------------------------------------------------------

/// Parse an `Accept` header into a list of `AcceptItem` values in the
/// order they appeared on the wire. Use `prefer/1` afterwards to sort
/// by preference.
///
/// Whitespace tolerance: empty entries (`"a, , b"`) and surrounding
/// whitespace on each entry / parameter are accepted per RFC 9110
/// §5.6.3.
pub fn parse(header: String) -> Result(List(AcceptItem), AcceptError) {
  let trimmed = string.trim(header)
  use <- bool.guard(when: trimmed == "", return: Ok([]))
  accept_internal.split_on_unquoted_commas(trimmed)
  |> list.index_map(fn(entry, i) { #(i, entry) })
  |> list.filter(fn(pair) {
    let #(_, raw) = pair
    string.trim(raw) != ""
  })
  |> list.try_map(fn(pair) {
    let #(i, raw) = pair
    parse_entry(i, raw)
  })
}

fn parse_entry(index: Int, raw: String) -> Result(AcceptItem, AcceptError) {
  let trimmed = string.trim(raw)
  let segments = parse_internal.split_on_unquoted_semicolons(trimmed)
  case segments {
    [] -> Error(Malformed(at: index, raw: raw))
    [range_raw, ..params] -> parse_entry_parts(index, raw, range_raw, params)
  }
}

fn parse_entry_parts(
  index: Int,
  raw: String,
  range_raw: String,
  params: List(String),
) -> Result(AcceptItem, AcceptError) {
  let range_trimmed = string.trim(range_raw)
  case accept_internal.split_at_q(params) {
    Error(Nil) -> Error(InvalidQValue(raw: raw))
    Ok(#(before_q, q, after_q)) ->
      case parse_media_range(range_trimmed, before_q) {
        Error(_) -> Error(InvalidMediaRange(raw: range_trimmed))
        Ok(range) -> finish_entry(index, raw, range, q, after_q)
      }
  }
}

fn finish_entry(
  index: Int,
  raw: String,
  range: MediaRange,
  q: Float,
  after_q: List(String),
) -> Result(AcceptItem, AcceptError) {
  case parse_extensions(after_q) {
    Error(Nil) -> Error(Malformed(at: index, raw: raw))
    Ok(extensions) -> Ok(AcceptItem(range: range, q: q, extensions: extensions))
  }
}

fn parse_media_range(
  range_raw: String,
  media_params: List(String),
) -> Result(MediaRange, Nil) {
  let lower = string.lowercase(range_raw)
  case lower, media_params {
    "*/*", [] -> Ok(AnyType)
    "*/*", _ -> Ok(AnyType)
    _, _ ->
      case string.split_once(lower, on: "/") {
        Error(Nil) -> Error(Nil)
        Ok(#(_t, "*")) ->
          case string.split_once(lower, on: "/") {
            Ok(#(t, _)) ->
              case t, is_valid_token(t) {
                "*", _ -> Error(Nil)
                _, True -> Ok(TypeWildcard(type_: t))
                _, False -> Error(Nil)
              }
            Error(Nil) -> Error(Nil)
          }
        Ok(#("*", _)) -> Error(Nil)
        Ok(_) -> {
          let wire = case media_params {
            [] -> range_raw
            _ ->
              range_raw
              <> "; "
              <> string.join(list.map(media_params, string.trim), "; ")
          }
          case mimetype.parse(wire) {
            Ok(mt) -> Ok(Specific(mt))
            Error(_) -> Error(Nil)
          }
        }
      }
  }
}

fn is_valid_token(s: String) -> Bool {
  parse_internal.is_token(s)
}

fn parse_extensions(
  segments: List(String),
) -> Result(List(#(String, String)), Nil) {
  segments
  |> list.try_fold([], fn(acc, seg) {
    let trimmed = string.trim(seg)
    case trimmed {
      "" -> Ok(acc)
      _ ->
        case string.split_once(trimmed, on: "=") {
          Error(Nil) -> {
            // accept-ext can be a bare token without a value
            // (RFC 9110 §12.5.1: `parameter = token "=" ( token / quoted-string )`,
            // but in practice some servers emit bare tokens).
            // We model the bare form as `name = ""`.
            let name = trimmed |> string.lowercase
            Ok([#(name, ""), ..acc])
          }
          Ok(#(name, value)) -> {
            let normalized_name = name |> string.trim |> string.lowercase
            let normalized_value = value |> string.trim |> strip_quotes
            Ok([#(normalized_name, normalized_value), ..acc])
          }
        }
    }
  })
  |> result_map_reverse
}

fn result_map_reverse(r: Result(List(a), e)) -> Result(List(a), e) {
  case r {
    Ok(xs) -> Ok(list.reverse(xs))
    Error(e) -> Error(e)
  }
}

fn strip_quotes(value: String) -> String {
  let is_quoted =
    string.starts_with(value, "\"") && string.ends_with(value, "\"")
  use <- bool.guard(when: !is_quoted, return: value)
  use <- bool.guard(when: string.length(value) < 2, return: value)
  value |> string.drop_start(1) |> string.drop_end(1)
}

/// Stable-sort parsed `AcceptItem`s by client preference:
///   1. q-value descending,
///   2. specificity descending (concrete > `type/*` > `*/*`),
///   3. accept-ext count descending (RFC 9110 §12.5.1 tie-breaker).
pub fn prefer(items: List(AcceptItem)) -> List(AcceptItem) {
  list.sort(items, compare_accept_items)
}

fn compare_accept_items(a: AcceptItem, b: AcceptItem) -> Order {
  // q desc
  let q_order = float.compare(b.q, a.q)
  use <- chain(q_order)
  // specificity desc
  let s_order = int.compare(specificity(b.range), specificity(a.range))
  use <- chain(s_order)
  // ext count desc
  int.compare(list.length(b.extensions), list.length(a.extensions))
}

fn chain(primary: Order, fallback: fn() -> Order) -> Order {
  case primary {
    Eq -> fallback()
    other -> other
  }
}

fn specificity(range: MediaRange) -> Int {
  case range {
    Specific(_) -> 3
    TypeWildcard(_) -> 2
    AnyType -> 1
  }
}

/// Pick the best server offer for a parsed `Accept` header. Returns
/// `None` when no offer is acceptable (e.g. every match has `q=0`, or
/// `server_offers` is empty).
///
/// Special case: if every client item is `AnyType` with `q>0`, the
/// server's first offer wins (server preference). Otherwise we score
/// each server offer by the best matching client item — `(q,
/// specificity, ext_count)` — and break ties by the order the offer
/// appears in `server_offers`.
///
/// Matching is essence-only: parameter-level "more-specific" matching
/// per RFC 9110 §12.5.1 is out of scope.
pub fn negotiate(
  client_accepts client: List(AcceptItem),
  server_offers offers: List(MimeType),
) -> Option(MimeType) {
  case offers {
    [] -> None
    _ ->
      case client {
        [] -> first(offers)
        _ ->
          case all_any_type(client) {
            True -> first(offers)
            False -> best_server_match(client, offers)
          }
      }
  }
}

fn first(offers: List(MimeType)) -> Option(MimeType) {
  case offers {
    [head, ..] -> Some(head)
    [] -> None
  }
}

fn all_any_type(items: List(AcceptItem)) -> Bool {
  list.all(items, fn(item) {
    case item.range, item.q >. 0.0 {
      AnyType, True -> True
      _, _ -> False
    }
  })
}

fn best_server_match(
  client: List(AcceptItem),
  offers: List(MimeType),
) -> Option(MimeType) {
  offers
  |> list.index_map(fn(offer, i) { #(i, offer, best_match_for(offer, client)) })
  |> list.filter_map(fn(triple) {
    let #(i, offer, m) = triple
    case m {
      Some(score) -> Ok(#(i, offer, score))
      None -> Error(Nil)
    }
  })
  |> list.sort(compare_offer_scores)
  |> list.first
  |> option.from_result
  |> option.map(fn(t) {
    let #(_, offer, _) = t
    offer
  })
}

type MatchScore {
  MatchScore(q: Float, specificity: Int, ext_count: Int)
}

fn compare_offer_scores(
  a: #(Int, MimeType, MatchScore),
  b: #(Int, MimeType, MatchScore),
) -> Order {
  let #(i_a, _, score_a) = a
  let #(i_b, _, score_b) = b
  let q_order = float.compare(score_b.q, score_a.q)
  use <- chain(q_order)
  let s_order = int.compare(score_b.specificity, score_a.specificity)
  use <- chain(s_order)
  let e_order = int.compare(score_b.ext_count, score_a.ext_count)
  use <- chain(e_order)
  // server preference: lower index wins
  int.compare(i_a, i_b)
}

fn best_match_for(
  offer: MimeType,
  client: List(AcceptItem),
) -> Option(MatchScore) {
  let offer_essence = mimetype.essence_of(offer)
  client
  |> list.filter_map(fn(item) {
    case range_matches(item.range, offer_essence) {
      True ->
        case item.q >. 0.0 {
          True ->
            Ok(MatchScore(
              q: item.q,
              specificity: specificity(item.range),
              ext_count: list.length(item.extensions),
            ))
          False -> Error(Nil)
        }
      False -> Error(Nil)
    }
  })
  |> max_score
}

fn max_score(scores: List(MatchScore)) -> Option(MatchScore) {
  case scores {
    [] -> None
    [head, ..rest] ->
      Some(
        list.fold(rest, head, fn(best, candidate) {
          case better_score(candidate, best) {
            True -> candidate
            False -> best
          }
        }),
      )
  }
}

fn better_score(a: MatchScore, b: MatchScore) -> Bool {
  case float.compare(a.q, b.q) {
    order.Gt -> True
    order.Lt -> False
    Eq ->
      case int.compare(a.specificity, b.specificity) {
        order.Gt -> True
        order.Lt -> False
        Eq ->
          case int.compare(a.ext_count, b.ext_count) {
            order.Gt -> True
            _ -> False
          }
      }
  }
}

fn range_matches(range: MediaRange, offer_essence: String) -> Bool {
  case range {
    AnyType -> True
    TypeWildcard(type_:) ->
      case string.split_once(offer_essence, on: "/") {
        Ok(#(t, _)) -> t == type_
        Error(Nil) -> False
      }
    Specific(mt) -> mimetype.essence_of(mt) == offer_essence
  }
}

// ---------------------------------------------------------------------------
// Encoding / Charset / Language
// ---------------------------------------------------------------------------

/// Parse an `Accept-Encoding` header.
pub fn parse_encoding(header: String) -> Result(List(ValueItem), AcceptError) {
  parse_value_header(header)
}

/// Parse an `Accept-Charset` header.
pub fn parse_charset(header: String) -> Result(List(ValueItem), AcceptError) {
  parse_value_header(header)
}

/// Parse an `Accept-Language` header.
pub fn parse_language(header: String) -> Result(List(ValueItem), AcceptError) {
  parse_value_header(header)
}

fn parse_value_header(header: String) -> Result(List(ValueItem), AcceptError) {
  case accept_internal.parse_token_list(header) {
    Error(Nil) -> Error(InvalidQValue(raw: header))
    Ok(pairs) ->
      Ok(
        list.map(pairs, fn(p) {
          let #(value, q) = p
          ValueItem(value: value, q: q)
        }),
      )
  }
}

/// Stable-sort `ValueItem`s by q-value descending.
pub fn prefer_values(items: List(ValueItem)) -> List(ValueItem) {
  list.sort(items, fn(a, b) { float.compare(b.q, a.q) })
}

/// Pick the best server offer for an `Accept-Encoding` /
/// `Accept-Charset` / `Accept-Language` header. The `*` wildcard
/// matches any value not already named explicitly; entries with `q=0`
/// are excluded.
pub fn negotiate_value(
  client_accepts client: List(ValueItem),
  server_offers offers: List(String),
) -> Option(String) {
  case offers {
    [] -> None
    _ ->
      case client {
        [] ->
          case offers {
            [head, ..] -> Some(head)
            [] -> None
          }
        _ -> best_value_match(client, offers)
      }
  }
}

fn best_value_match(
  client: List(ValueItem),
  offers: List(String),
) -> Option(String) {
  let normalised_offers =
    list.index_map(offers, fn(offer, i) { #(i, offer, string.lowercase(offer)) })
  let wildcard_q = find_q(client, "*")
  normalised_offers
  |> list.filter_map(fn(triple) {
    let #(i, original, lower) = triple
    let explicit_q = find_q(client, lower)
    let chosen = case explicit_q, wildcard_q {
      Some(q), _ -> Some(q)
      None, Some(q) -> Some(q)
      None, None -> None
    }
    case chosen {
      Some(q) ->
        case q >. 0.0 {
          True -> Ok(#(i, original, q))
          False -> Error(Nil)
        }
      None -> Error(Nil)
    }
  })
  |> list.sort(fn(a, b) {
    let #(i_a, _, q_a) = a
    let #(i_b, _, q_b) = b
    let q_order = float.compare(q_b, q_a)
    use <- chain(q_order)
    int.compare(i_a, i_b)
  })
  |> list.first
  |> option.from_result
  |> option.map(fn(t) {
    let #(_, original, _) = t
    original
  })
}

fn find_q(items: List(ValueItem), value: String) -> Option(Float) {
  list.find_map(items, fn(item) {
    case item.value == value {
      True -> Ok(item.q)
      False -> Error(Nil)
    }
  })
  |> option.from_result
}
