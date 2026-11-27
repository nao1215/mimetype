//// Metamorphic and differential tests for content negotiation.
////
//// - Differential: `accept.negotiate` against a small reference
////   model of RFC 9110 §12.5.1 written here, where the most specific
////   matching media range decides an offer's q-value (so `text/html;q=0`
////   excludes text/html even with `*/*` present), and a range with a
////   parameter, wildcard or not, matches only offers that carry it.
//// - Metamorphic: the order of the client's entries never changes the
////   result, the result is always one of the offers, and dropping offers
////   other than the chosen one keeps it chosen.

import gleam/bool
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/result
import gleam/string
import metamon
import metamon/generator.{type Generator}
import mimetype
import mimetype/accept

/// `parameter` adds `x=1` to the range, after the weight.
type Entry {
  Entry(range: String, parameter: Bool, quality: Option(String))
}

const ranges = [
  "*/*", "text/*", "image/*", "application/*", "text/html", "text/plain",
  "application/json", "image/png",
]

const offer_pool = [
  "text/html", "text/plain", "application/json", "image/png", "image/webp",
  "application/xml", "text/html; x=1", "image/png; x=1",
]

fn entry_gen() -> Generator(Entry) {
  generator.tuple3(
    generator.element_of(ranges),
    generator.bool(),
    generator.element_of([None, Some("0"), Some("0.1"), Some("0.5"), Some("1")]),
  )
  |> generator.map(fn(t) { Entry(t.0, t.1, t.2) })
}

/// Client entries with distinct media ranges: the RFC does not say which
/// q-value wins when the same range is listed twice.
fn entries_gen() -> Generator(List(Entry)) {
  generator.list_of(entry_gen(), generator.range(from: 1, to: 6))
  |> generator.map(fn(es) {
    list.fold(es, [], fn(acc, e) {
      case list.any(acc, fn(x: Entry) { x.range == e.range }) {
        True -> acc
        False -> [e, ..acc]
      }
    })
    |> list.reverse
  })
}

fn offers_gen() -> Generator(List(String)) {
  generator.list_of(
    generator.element_of(offer_pool),
    generator.range(from: 1, to: 5),
  )
  |> generator.map(list.unique)
}

fn render(entries: List(Entry)) -> String {
  entries
  |> list.map(fn(e) {
    // RFC 9110 reads any `q` as the weight, so the parameter can follow it.
    let q_param = case e.quality {
      Some(raw) -> ";q=" <> raw
      None -> ""
    }
    let parameter = case e.parameter {
      True -> ";x=1"
      False -> ""
    }
    e.range <> q_param <> parameter
  })
  |> string.join(", ")
}

fn q_of(e: Entry) -> Float {
  case e.quality {
    None -> 1.0
    Some(raw) ->
      case float.parse(raw) {
        Ok(f) -> f
        Error(Nil) -> int.parse(raw) |> result_to_float
      }
  }
}

fn result_to_float(r: Result(Int, Nil)) -> Float {
  case r {
    Ok(i) -> int.to_float(i)
    Error(Nil) -> 1.0
  }
}

fn is_specific(range: String) -> Bool {
  range != "*/*" && !string.ends_with(range, "/*")
}

fn precedence(e: Entry) -> Int {
  case e.range, is_specific(e.range) {
    "*/*", _ -> 0
    _, False -> 1
    _, True -> 2
  }
}

fn matches(e: Entry, offer: String) -> Bool {
  let #(essence, offer_has_parameter) = case string.split_once(offer, "; ") {
    Ok(#(essence, _)) -> #(essence, True)
    Error(Nil) -> #(offer, False)
  }
  let range_matches = case e.range, is_specific(e.range) {
    "*/*", _ -> True
    range, False -> string.starts_with(essence, string.drop_end(range, 1))
    range, True -> range == essence
  }
  range_matches && { !e.parameter || offer_has_parameter }
}

// The kind of range first, then whether it has a parameter.
fn entry_key(e: Entry) -> #(Int, Int) {
  use <- bool.guard(when: !e.parameter, return: #(precedence(e), 0))
  #(precedence(e), 1)
}

fn more_specific(a: Entry, b: Entry) -> Entry {
  case compare_key(entry_key(b), entry_key(a)) {
    order.Gt -> b
    _ -> a
  }
}

/// The most specific matching entry gives the offer its q-value and
/// specificity; q=0 makes the offer unacceptable.
fn score_offer(
  entries: List(Entry),
  offer: String,
  index: Int,
) -> Result(#(Float, #(Int, Int), Int, String), Nil) {
  let matching = list.filter(entries, fn(e) { matches(e, offer) })
  use best <- result.try(list.reduce(matching, more_specific))
  let quality = q_of(best)
  case quality >. 0.0 {
    True -> Ok(#(quality, entry_key(best), index, offer))
    False -> Error(Nil)
  }
}

fn compare_scores(
  a: #(Float, #(Int, Int), Int, String),
  b: #(Float, #(Int, Int), Int, String),
) -> order.Order {
  use <- order.lazy_break_tie(float.compare(b.0, a.0))
  use <- order.lazy_break_tie(compare_key(b.1, a.1))
  int.compare(a.2, b.2)
}

/// Reference model of RFC 9110 §12.5.1. Offers are ranked by the q and
/// precedence of their most specific match and then by server order.
fn reference(
  entries: List(Entry),
  offers: List(String),
) -> Result(String, Nil) {
  case entries {
    [] -> list.first(offers)
    _ ->
      offers
      |> list.index_map(fn(offer, i) { score_offer(entries, offer, i) })
      |> list.filter_map(fn(x) { x })
      |> list.sort(compare_scores)
      |> list.first
      |> result.map(fn(t) { t.3 })
  }
}

fn compare_key(a: #(Int, Int), b: #(Int, Int)) -> order.Order {
  case int.compare(a.0, b.0) {
    order.Eq -> int.compare(a.1, b.1)
    other -> other
  }
}

fn negotiate(
  entries: List(Entry),
  offers: List(String),
) -> Result(String, Nil) {
  let assert Ok(items) = accept.parse(render(entries))
  let offers =
    list.map(offers, fn(offer) {
      let assert Ok(mime) = mimetype.parse(offer)
      mime
    })
  accept.negotiate(items, offers) |> result.map(mimetype.to_string)
}

fn negotiate_encoding(
  header: String,
  offers: List(String),
) -> Result(String, Nil) {
  let assert Ok(items) = accept.parse_values(header)
  accept.negotiate_value(items, offers)
}

pub fn negotiate_matches_rfc_9110_reference_model_test() -> Nil {
  metamon.forall(generator.tuple2(entries_gen(), offers_gen()), fn(input) {
    let #(entries, offers) = input
    assert negotiate(entries, offers) == reference(entries, offers)
  })
}

pub fn negotiate_ignores_the_order_of_client_entries_test() -> Nil {
  metamon.forall(
    generator.tuple3(
      entries_gen(),
      offers_gen(),
      generator.list_of(
        generator.int(generator.range(from: 0, to: 99)),
        generator.range(from: 6, to: 6),
      ),
    ),
    fn(input) {
      let #(entries, offers, keys) = input
      let shuffled =
        list.zip(entries, keys)
        |> list.sort(fn(a, b) { int.compare(a.1, b.1) })
        |> list.map(fn(p) { p.0 })
      assert negotiate(shuffled, offers) == negotiate(entries, offers)
    },
  )
}

pub fn negotiate_returns_an_offer_and_keeps_it_when_others_are_dropped_test() -> Nil {
  metamon.forall(generator.tuple2(entries_gen(), offers_gen()), fn(input) {
    let #(entries, offers) = input
    case negotiate(entries, offers) {
      Error(Nil) -> Nil
      Ok(chosen) -> {
        assert list.contains(offers, chosen)
        assert negotiate(entries, [chosen]) == Ok(chosen)
      }
    }
  })
}

pub fn negotiate_encoding_ignores_the_order_of_client_entries_test() -> Nil {
  metamon.forall(
    generator.tuple3(
      generator.list_of(
        generator.tuple2(
          generator.element_of(["gzip", "br", "zstd", "identity", "*"]),
          generator.element_of(["", ";q=0", ";q=0.5", ";q=1"]),
        ),
        generator.range(from: 1, to: 5),
      ),
      generator.list_of(
        generator.element_of(["gzip", "br", "zstd", "identity", "deflate"]),
        generator.range(from: 1, to: 4),
      ),
      generator.list_of(
        generator.int(generator.range(from: 0, to: 99)),
        generator.range(from: 5, to: 5),
      ),
    ),
    fn(input) {
      let #(raw, offers, keys) = input
      let entries =
        list.fold(raw, [], fn(acc, e) {
          case list.any(acc, fn(x: #(String, String)) { x.0 == e.0 }) {
            True -> acc
            False -> [e, ..acc]
          }
        })
      let header = fn(es: List(#(String, String))) {
        es |> list.map(fn(e) { e.0 <> e.1 }) |> string.join(", ")
      }
      let shuffled =
        list.zip(entries, keys)
        |> list.sort(fn(a, b) { int.compare(a.1, b.1) })
        |> list.map(fn(p) { p.0 })
      let offers = list.unique(offers)
      assert negotiate_encoding(header(shuffled), offers)
        == negotiate_encoding(header(entries), offers)
    },
  )
}
