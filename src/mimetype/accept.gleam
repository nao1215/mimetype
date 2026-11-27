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
  /// A full `type/subtype`, with any media type parameters. An offer
  /// matches when it has the same essence and every one of these
  /// parameters.
  Specific(MimeType)
  /// `type/*`. The type is lowercase. An offer matches when it has this
  /// type and every one of the parameters.
  TypeWildcard(type_: String, parameters: List(#(String, String)))
  /// `*/*`. Every offer that has all of the parameters matches.
  AnyType(parameters: List(#(String, String)))
}

/// One entry of an `Accept` header.
pub type AcceptItem {
  AcceptItem(
    range: MediaRange,
    /// The `q` weight, from 0.0 to 1.0. It is 1.0 when the entry has
    /// none.
    quality: Float,
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
  /// three decimals, or a value entry is empty. Holds the entry.
  InvalidQValue(raw: String)
  /// The media range is not `*/*`, `type/*` or a valid `type/subtype`,
  /// or one of its parameters is invalid. Holds the entry.
  InvalidMediaRange(raw: String)
}

// ---------------------------------------------------------------------------
// Accept
// ---------------------------------------------------------------------------

/// Parses an `Accept` header into its entries, in header order.
///
/// Empty entries and the whitespace around entries and parameters are
/// ignored, and an empty header gives `Ok([])`. A parameter named `q`
/// is the weight wherever it appears; every other parameter belongs to
/// the media range, wildcards included (RFC 9110 section 12.5.1).
/// Parameter names are lowercase and quoted values are unquoted.
///
/// ## Examples
///
/// ```gleam
/// accept.parse("text/html, */*;q=0.1")
/// // -> Ok([
/// //   AcceptItem(Specific(html), quality: 1.0),
/// //   AcceptItem(AnyType([]), quality: 0.1),
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
  let #(range, segments) = case parse_internal.split_unquoted(entry, on: ";") {
    [range, ..segments] -> #(string.trim(range), segments)
    [] -> #(entry, [])
  }
  use #(parameters, quality) <- result.try(
    accept_internal.split_weight(segments)
    |> result.replace_error(InvalidQValue(raw: entry)),
  )
  use range <- result.try(
    parse_media_range(range, parameters)
    |> result.replace_error(InvalidMediaRange(raw: entry)),
  )
  Ok(AcceptItem(range:, quality:))
}

fn parse_media_range(
  range: String,
  parameters: List(String),
) -> Result(MediaRange, Nil) {
  let joined =
    [range, ..list.map(parameters, string.trim)]
    |> string.join("; ")
  // `*` is a token character, so wildcard ranges parse like any media
  // type and share its parameter rules.
  use #(essence, parameters) <- result.try(
    parse_internal.parse_string(joined) |> result.replace_error(Nil),
  )
  case string.split_once(essence, on: "/") {
    Ok(#("*", "*")) -> Ok(AnyType(parameters:))
    Ok(#("*", _)) -> Error(Nil)
    Ok(#(type_, "*")) -> Ok(TypeWildcard(type_:, parameters:))
    _ ->
      mimetype.parse(joined)
      |> result.map(Specific)
      |> result.replace_error(Nil)
  }
}

/// Sorts entries from most to least preferred: by `quality`, then by
/// precedence (RFC 9110 section 12.5.1): `type/subtype`, then `type/*`,
/// then `*/*`, and within each of these more parameters before fewer.
/// Entries that tie keep their order.
///
pub fn prefer(items: List(AcceptItem)) -> List(AcceptItem) {
  list.sort(items, fn(a, b) { compare_scores(score(b), score(a)) })
}

// `precedence` ranks the kind of range, `parameters` breaks ties
// between ranges of the same kind.
type Score {
  Score(quality: Float, precedence: Int, parameters: Int)
}

fn score(item: AcceptItem) -> Score {
  let #(precedence, parameters) = case item.range {
    AnyType(parameters:) -> #(0, list.length(parameters))
    TypeWildcard(parameters:, ..) -> #(1, list.length(parameters))
    Specific(range) -> #(2, list.length(parameters(range)))
  }
  Score(quality: item.quality, precedence:, parameters:)
}

fn compare_scores(a: Score, b: Score) -> Order {
  use <- order.lazy_break_tie(float.compare(a.quality, b.quality))
  compare_precedence(a, b)
}

fn compare_precedence(a: Score, b: Score) -> Order {
  use <- order.lazy_break_tie(int.compare(a.precedence, b.precedence))
  int.compare(a.parameters, b.parameters)
}

/// Picks the server offer the client prefers.
///
/// Each offer takes the quality of the matching entry with the highest
/// precedence (see `prefer`), so `text/html;q=0` rules out `text/html`
/// even when `*/*` is present, and `text/html;level=1;q=0` rules out
/// only offers with `level=1`. An entry with parameters matches only
/// offers that carry the same parameters; `charset` values are compared
/// without regard to case. The offer with the highest quality wins,
/// then the one matched by the entry with higher precedence, and on a
/// tie the earlier offer. When the header is empty, the first offer
/// wins.
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
/// let assert Ok(html) = mimetype.parse("text/html")
/// let assert Ok(json) = mimetype.parse("application/json")
/// accept.negotiate(items, [json, html])
/// // -> Error(Nil)
/// ```
///
pub fn negotiate(
  client_accepts: List(AcceptItem),
  server_offers: List(MimeType),
) -> Result(MimeType, Nil) {
  use <- bool.lazy_guard(when: client_accepts == [], return: fn() {
    list.first(server_offers)
  })
  server_offers
  |> list.index_map(fn(offer, index) {
    let offer_parameters = parameters(offer)
    client_accepts
    |> list.filter(fn(item) {
      range_matches(item.range, offer, offer_parameters)
    })
    |> list.map(score)
    |> decide
    |> result.try(acceptable)
    |> result.map(fn(score) { #(index, offer, score) })
  })
  |> pick
}

// Of the matching entries, the one with the highest precedence decides
// (RFC 9110 section 12.5.1). Among equally precise entries the highest
// quality is used.
fn decide(scores: List(Score)) -> Result(Score, Nil) {
  list.reduce(scores, fn(a, b) {
    let order = {
      use <- order.lazy_break_tie(compare_precedence(a, b))
      float.compare(a.quality, b.quality)
    }
    case order {
      order.Lt -> b
      order.Eq | order.Gt -> a
    }
  })
}

// A quality of 0 means "not acceptable" (RFC 9110 section 12.4.2).
fn acceptable(score: Score) -> Result(Score, Nil) {
  use <- bool.guard(when: score.quality <=. 0.0, return: Error(Nil))
  Ok(score)
}

// The acceptable offer with the best score, the earliest on a tie.
fn pick(scored: List(Result(#(Int, offer, Score), Nil))) -> Result(offer, Nil) {
  scored
  |> result.values
  |> list.sort(fn(a, b) {
    use <- order.lazy_break_tie(compare_scores(b.2, a.2))
    int.compare(a.0, b.0)
  })
  |> list.first
  |> result.map(fn(match) { match.1 })
}

fn range_matches(
  range: MediaRange,
  offer: MimeType,
  offer_parameters: List(#(String, String)),
) -> Bool {
  case range {
    AnyType(parameters:) -> has_all(offer_parameters, parameters)
    TypeWildcard(type_:, parameters:) ->
      string.starts_with(mimetype.essence(offer), type_ <> "/")
      && has_all(offer_parameters, parameters)
    Specific(range) ->
      mimetype.essence(range) == mimetype.essence(offer)
      && has_all(offer_parameters, parameters(range))
  }
}

fn has_all(
  offer_parameters: List(#(String, String)),
  range_parameters: List(#(String, String)),
) -> Bool {
  list.all(range_parameters, fn(parameter) {
    list.any(offer_parameters, same_parameter(parameter, _))
  })
}

// Parameter names are lowercase already. RFC 9110 section 8.3.2 makes
// charset names case-insensitive; other values are compared as given.
fn same_parameter(a: #(String, String), b: #(String, String)) -> Bool {
  a.0 == b.0
  && case a.0 {
    "charset" -> string.lowercase(a.1) == string.lowercase(b.1)
    _ -> a.1 == b.1
  }
}

// `MimeType` is opaque, so read the parameters back from its header
// form, which always parses.
fn parameters(mime: MimeType) -> List(#(String, String)) {
  parse_internal.parse_string(mimetype.to_string(mime))
  |> result.map(fn(parsed) { parsed.1 })
  |> result.unwrap([])
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
/// accept.parse_values("gzip, br;q=x")
/// // -> Error(InvalidQValue("br;q=x"))
/// ```
///
pub fn parse_values(header: String) -> Result(List(ValueItem), AcceptError) {
  parse_internal.split_unquoted(header, on: ",")
  |> list.map(string.trim)
  |> list.filter(fn(entry) { entry != "" })
  |> list.try_map(fn(entry) {
    accept_internal.parse_value(entry)
    |> result.map(fn(pair) { ValueItem(value: pair.0, quality: pair.1) })
    |> result.replace_error(InvalidQValue(raw: entry))
  })
}

/// Picks the server offer the client prefers from a header parsed with
/// `parse_values`.
///
/// Offers are compared without regard to case. An entry matches an
/// offer equal to it. An entry of 2 to 8 letters, a primary language
/// subtag, also matches an offer that starts with it and `-`, so `en`
/// matches `en-US` (RFC 4647 basic filtering) while `iso-2022-jp` does
/// not match `iso-2022-jp-2`. The longest matching entry sets the
/// quality. `*` gives its quality to every offer no entry matches,
/// and a quality of 0 rules an offer out.
///
/// `identity`, the absence of a content coding, is acceptable unless the
/// header rules it out with `identity;q=0` or `*;q=0`, and is then the
/// least preferred offer (RFC 9110 section 12.5.3). An empty header
/// asks for no content coding, so `identity` wins when it is offered,
/// and otherwise the first offer does.
///
/// On a tie the earlier offer wins. The chosen offer is returned as it
/// was given. Returns `Error(Nil)` when no offer is acceptable.
///
/// ## Examples
///
/// ```gleam
/// let assert Ok(items) = accept.parse_values("gzip, br;q=1.0, *;q=0.1")
/// accept.negotiate_value(items, ["br", "gzip"])
/// // -> Ok("br")
/// ```
///
/// ```gleam
/// let assert Ok(items) = accept.parse_values("da, en;q=0.7")
/// accept.negotiate_value(items, ["fr", "en-GB"])
/// // -> Ok("en-GB")
/// ```
///
pub fn negotiate_value(
  client_accepts: List(ValueItem),
  server_offers: List(String),
) -> Result(String, Nil) {
  use <- bool.lazy_guard(when: client_accepts == [], return: fn() {
    server_offers
    |> list.find(fn(offer) { string.lowercase(offer) == "identity" })
    |> result.lazy_or(fn() { list.first(server_offers) })
  })
  server_offers
  |> list.index_map(fn(offer, index) {
    value_score(client_accepts, string.lowercase(offer))
    |> result.try(acceptable)
    // The entry decided the quality; ties go to the earlier offer.
    |> result.map(fn(score) {
      #(index, offer, Score(..score, precedence: 0, parameters: 0))
    })
  })
  |> pick
}

// The longest entry equal to the offer, or a primary language subtag
// that the offer starts with followed by `-`, decides. Without one, `*` does, and without that `identity` is
// still acceptable as the least preferred choice.
fn value_score(items: List(ValueItem), offer: String) -> Result(Score, Nil) {
  let matching =
    list.filter_map(items, fn(item) {
      case
        item.value == offer
        || is_primary_language_subtag(item.value)
        && string.starts_with(offer, item.value <> "-")
      {
        True ->
          Ok(Score(
            quality: item.quality,
            precedence: string.length(item.value),
            parameters: 0,
          ))
        False -> Error(Nil)
      }
    })
  use <- result.lazy_or(decide(matching))
  case list.find(items, fn(item) { item.value == "*" }), offer {
    Ok(wildcard), _ ->
      Ok(Score(quality: wildcard.quality, precedence: 0, parameters: 0))
    Error(Nil), "identity" ->
      Ok(Score(quality: 0.001, precedence: 0, parameters: 0))
    Error(Nil), _ -> Error(Nil)
  }
}

// RFC 5646: 2 to 8 ASCII letters. Charset and coding names that share a
// prefix, such as iso-2022-jp and iso-2022-jp-2, are not language ranges.
fn is_primary_language_subtag(value: String) -> Bool {
  let size = string.length(value)
  size >= 2
  && size <= 8
  && list.all(string.to_graphemes(value), fn(letter) {
    string.contains("abcdefghijklmnopqrstuvwxyz", letter)
  })
}
