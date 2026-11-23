//// Parses the HTTP `Accept`, `Accept-Encoding`, `Accept-Charset` and
//// `Accept-Language` headers and picks the offer a client prefers, as
//// described in RFC 9110 section 12.5.
////
//// ```gleam
//// import mimetype
//// import mimetype/accept
////
//// pub fn choose(header: String) -> Result(mimetype.MimeType, Nil) {
////   let assert Ok(html) = mimetype.parse("text/html")
////   let assert Ok(json) = mimetype.parse("application/json")
////   case accept.parse(header) {
////     Ok(items) -> accept.negotiate(items, [html, json])
////     Error(_) -> Error(Nil)
////   }
//// }
//// ```

import gleam/bool
import gleam/float
import gleam/int
import gleam/list
import gleam/order.{type Order}
import gleam/result
import gleam/string
import mimetype.{type MimeType}
import mimetype/internal/accept as accept_internal
import mimetype/internal/parse as parse_internal

/// The media range of one `Accept` entry.
pub type MediaRange {
  /// A full `type/subtype`. Only the essence is compared when matching;
  /// parameters on the range are ignored.
  Specific(MimeType)
  /// `type/*`. The type is lowercase.
  TypeWildcard(type_: String)
  /// `*/*`.
  AnyType
}

/// One entry of an `Accept` header.
pub type AcceptItem {
  AcceptItem(
    range: MediaRange,
    /// The `q` weight, from 0.0 to 1.0. It is 1.0 when the entry has
    /// none.
    quality: Float,
    /// The parameters after `q`, with lowercase names. A parameter
    /// without `=` has the value `""`.
    extensions: List(#(String, String)),
  )
}

/// One entry of an `Accept-Encoding`, `Accept-Charset` or
/// `Accept-Language` header.
pub type ValueItem {
  /// `value` is lowercase, and `quality` is the `q` weight (1.0 when
  /// absent).
  ValueItem(value: String, quality: Float)
}

/// The reason a header could not be parsed.
pub type AcceptError {
  /// The `q` value of an entry is not a number from 0 to 1 with at most
  /// three decimals. Holds the entry.
  InvalidQValue(raw: String)
  /// The media range is not `*/*`, `type/*` or a valid `type/subtype`.
  InvalidMediaRange(raw: String)
}

// ---------------------------------------------------------------------------
// Accept
// ---------------------------------------------------------------------------

/// Parses an `Accept` header into its entries, in header order.
///
/// Empty entries and the whitespace around entries and parameters are
/// ignored, and an empty header gives `Ok([])`.
///
/// ## Examples
///
/// ```gleam
/// accept.parse("text/html, */*;q=0.1")
/// // -> Ok([
/// //   AcceptItem(Specific(html), quality: 1.0, extensions: []),
/// //   AcceptItem(AnyType, quality: 0.1, extensions: []),
/// // ])
/// ```
///
/// ```gleam
/// accept.parse("text/html;q=2")
/// // -> Error(InvalidQValue("text/html;q=2"))
/// ```
///
pub fn parse(header: String) -> Result(List(AcceptItem), AcceptError) {
  parse_internal.split_unquoted(header, on: ",")
  |> list.map(string.trim)
  |> list.filter(fn(entry) { entry != "" })
  |> list.try_map(parse_entry)
}

fn parse_entry(entry: String) -> Result(AcceptItem, AcceptError) {
  let #(range, parameters) = case
    parse_internal.split_unquoted(entry, on: ";")
  {
    [range, ..parameters] -> #(string.trim(range), parameters)
    [] -> #(entry, [])
  }
  use #(media_parameters, quality, extensions) <- result.try(
    accept_internal.split_at_q(parameters)
    |> result.replace_error(InvalidQValue(raw: entry)),
  )
  use range <- result.try(
    parse_media_range(range, media_parameters)
    |> result.replace_error(InvalidMediaRange(raw: range)),
  )
  Ok(AcceptItem(range:, quality:, extensions: parse_extensions(extensions)))
}

fn parse_media_range(
  range: String,
  parameters: List(String),
) -> Result(MediaRange, Nil) {
  case string.split_once(string.lowercase(range), on: "/") {
    Ok(#("*", "*")) -> Ok(AnyType)
    Ok(#("*", _)) -> Error(Nil)
    Ok(#(type_, "*")) ->
      case parse_internal.is_token(type_) {
        True -> Ok(TypeWildcard(type_:))
        False -> Error(Nil)
      }
    Ok(_) ->
      [range, ..list.map(parameters, string.trim)]
      |> string.join("; ")
      |> mimetype.parse
      |> result.map(Specific)
      |> result.replace_error(Nil)
    Error(Nil) -> Error(Nil)
  }
}

fn parse_extensions(segments: List(String)) -> List(#(String, String)) {
  segments
  |> list.map(string.trim)
  |> list.filter(fn(segment) { segment != "" })
  |> list.map(fn(segment) {
    case string.split_once(segment, on: "=") {
      // RFC 9110 requires `name=value`, but some clients send a bare
      // name. Keep it with an empty value.
      Error(Nil) -> #(string.lowercase(segment), "")
      Ok(#(name, value)) -> #(
        name |> string.trim |> string.lowercase,
        value |> string.trim |> strip_quotes,
      )
    }
  })
}

fn strip_quotes(value: String) -> String {
  let quoted =
    string.length(value) >= 2
    && string.starts_with(value, "\"")
    && string.ends_with(value, "\"")
  case quoted {
    True -> value |> string.drop_start(1) |> string.drop_end(1)
    False -> value
  }
}

/// Sorts entries from most to least preferred: by `quality`, then
/// `type/subtype` before `type/*` before `*/*`, then by the number of
/// extensions. Entries that tie keep their order.
///
pub fn prefer(items: List(AcceptItem)) -> List(AcceptItem) {
  list.sort(items, fn(a, b) { compare_scores(score(b), score(a)) })
}

type Score {
  Score(quality: Float, specificity: Int, extensions: Int)
}

fn score(item: AcceptItem) -> Score {
  let specificity = case item.range {
    Specific(_) -> 3
    TypeWildcard(_) -> 2
    AnyType -> 1
  }
  Score(
    quality: item.quality,
    specificity:,
    extensions: list.length(item.extensions),
  )
}

fn compare_scores(a: Score, b: Score) -> Order {
  use <- order.lazy_break_tie(float.compare(a.quality, b.quality))
  use <- order.lazy_break_tie(int.compare(a.specificity, b.specificity))
  int.compare(a.extensions, b.extensions)
}

/// Picks the server offer the client prefers.
///
/// Each offer takes the quality of the most specific entry that matches
/// it, so `text/html;q=0` rules out `text/html` even when `*/*` is
/// present. The offer with the highest quality wins, then the one
/// matched by the more specific entry, and on a tie the earlier offer.
/// When the header is empty or only has `*/*`, the first offer wins.
/// Only the essence of each offer is compared.
///
/// Returns `Error(Nil)` when no offer is acceptable.
///
/// ## Examples
///
/// ```gleam
/// let assert Ok(items) = accept.parse("text/html, application/json;q=0.9")
/// let assert Ok(html) = mimetype.parse("text/html")
/// let assert Ok(json) = mimetype.parse("application/json")
/// accept.negotiate(items, [json, html])
/// // -> Ok(html)
/// ```
///
/// ```gleam
/// let assert Ok(items) = accept.parse("image/*")
/// accept.negotiate(items, [json, html])
/// // -> Error(Nil)
/// ```
///
pub fn negotiate(
  client_accepts: List(AcceptItem),
  server_offers: List(MimeType),
) -> Result(MimeType, Nil) {
  let only_any =
    list.all(client_accepts, fn(item) {
      item.range == AnyType && item.quality >. 0.0
    })
  use <- bool.lazy_guard(when: only_any, return: fn() {
    list.first(server_offers)
  })
  server_offers
  |> list.index_map(fn(offer, index) {
    best_match(offer, client_accepts)
    |> result.map(fn(score) { #(index, offer, score) })
  })
  |> result.values
  |> list.sort(fn(a, b) {
    use <- order.lazy_break_tie(compare_scores(b.2, a.2))
    int.compare(a.0, b.0)
  })
  |> list.first
  |> result.map(fn(match) { match.1 })
}

// Of the entries matching `offer`, the most specific one decides its
// quality (RFC 9110 section 12.5.1). Among equally specific entries the
// highest quality is used. A quality of 0 rules the offer out.
fn best_match(offer: MimeType, client: List(AcceptItem)) -> Result(Score, Nil) {
  let essence = mimetype.essence(offer)
  client
  |> list.filter(fn(item) { range_matches(item.range, essence) })
  |> list.map(score)
  |> list.reduce(fn(a, b) {
    let by_specificity = {
      use <- order.lazy_break_tie(int.compare(a.specificity, b.specificity))
      use <- order.lazy_break_tie(int.compare(a.extensions, b.extensions))
      float.compare(a.quality, b.quality)
    }
    case by_specificity {
      order.Lt -> b
      order.Eq | order.Gt -> a
    }
  })
  |> result.try(fn(score) {
    case score.quality >. 0.0 {
      True -> Ok(score)
      False -> Error(Nil)
    }
  })
}

fn range_matches(range: MediaRange, essence: String) -> Bool {
  case range {
    AnyType -> True
    TypeWildcard(type_:) -> string.starts_with(essence, type_ <> "/")
    Specific(mime) -> mimetype.essence(mime) == essence
  }
}

// ---------------------------------------------------------------------------
// Accept-Encoding, Accept-Charset and Accept-Language
// ---------------------------------------------------------------------------

/// Parses an `Accept-Encoding`, `Accept-Charset` or `Accept-Language`
/// header into its entries, in header order.
///
/// ## Examples
///
/// ```gleam
/// accept.parse_values("gzip, br;q=0.5")
/// // -> Ok([ValueItem("gzip", quality: 1.0), ValueItem("br", quality: 0.5)])
/// ```
///
/// ```gleam
/// accept.parse_values("gzip;q=x")
/// // -> Error(InvalidQValue("gzip;q=x"))
/// ```
///
pub fn parse_values(header: String) -> Result(List(ValueItem), AcceptError) {
  case accept_internal.parse_token_list(header) {
    Ok(pairs) ->
      Ok(
        list.map(pairs, fn(pair) { ValueItem(value: pair.0, quality: pair.1) }),
      )
    Error(Nil) -> Error(InvalidQValue(raw: header))
  }
}

/// Picks the server offer the client prefers from a header parsed with
/// `parse_values`.
///
/// Offers are compared without regard to case. `*` gives its quality to
/// every offer the header does not name, and a quality of 0 rules an
/// offer out. On a tie the earlier offer wins, and with an empty header
/// the first offer wins. The chosen offer is returned as it was given.
/// Returns `Error(Nil)` when no offer is acceptable.
///
/// ## Examples
///
/// ```gleam
/// let assert Ok(items) = accept.parse_values("gzip, br;q=1.0, *;q=0.1")
/// accept.negotiate_value(items, ["br", "gzip"])
/// // -> Ok("br")
/// ```
///
pub fn negotiate_value(
  client_accepts: List(ValueItem),
  server_offers: List(String),
) -> Result(String, Nil) {
  use <- bool.lazy_guard(when: client_accepts == [], return: fn() {
    list.first(server_offers)
  })
  let wildcard = quality_of(client_accepts, "*")
  server_offers
  |> list.index_map(fn(offer, index) {
    quality_of(client_accepts, string.lowercase(offer))
    |> result.or(wildcard)
    |> result.try(fn(quality) {
      case quality >. 0.0 {
        True -> Ok(#(index, offer, quality))
        False -> Error(Nil)
      }
    })
  })
  |> result.values
  |> list.sort(fn(a, b) {
    use <- order.lazy_break_tie(float.compare(b.2, a.2))
    int.compare(a.0, b.0)
  })
  |> list.first
  |> result.map(fn(match) { match.1 })
}

fn quality_of(items: List(ValueItem), value: String) -> Result(Float, Nil) {
  list.find_map(items, fn(item) {
    case item.value == value {
      True -> Ok(item.quality)
      False -> Error(Nil)
    }
  })
}
