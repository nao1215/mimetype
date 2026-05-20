import gleam/list
import gleam/option.{None, Some}
import gleeunit
import gleeunit/should
import mimetype
import mimetype/accept

pub fn main() -> Nil {
  gleeunit.main()
}

fn mt(s: String) -> mimetype.MimeType {
  let assert Ok(value) = mimetype.parse(s)
  value
}

fn ranges(items: List(accept.AcceptItem)) -> List(accept.MediaRange) {
  list.map(items, fn(i) { i.range })
}

fn essences(items: List(accept.AcceptItem)) -> List(String) {
  list.map(items, fn(item) {
    case item.range {
      accept.Specific(m) -> mimetype.essence_of(m)
      accept.TypeWildcard(t) -> t <> "/*"
      accept.AnyType -> "*/*"
    }
  })
}

// ---------------------------------------------------------------------------
// 1. parse basics
// ---------------------------------------------------------------------------

pub fn parse_empty_string_test() {
  accept.parse("")
  |> should.equal(Ok([]))
}

pub fn parse_whitespace_only_test() {
  accept.parse("   ")
  |> should.equal(Ok([]))
}

pub fn parse_single_concrete_test() {
  let assert Ok(items) = accept.parse("text/html")
  items
  |> ranges
  |> should.equal([accept.Specific(mt("text/html"))])
}

pub fn parse_default_q_is_1_test() {
  let assert Ok(items) = accept.parse("text/html")
  case items {
    [head] -> head.q |> should.equal(1.0)
    _ -> should.fail()
  }
}

pub fn parse_star_star_test() {
  let assert Ok(items) = accept.parse("*/*")
  items
  |> ranges
  |> should.equal([accept.AnyType])
}

pub fn parse_type_wildcard_test() {
  let assert Ok(items) = accept.parse("image/*")
  items
  |> ranges
  |> should.equal([accept.TypeWildcard("image")])
}

pub fn parse_multiple_entries_test() {
  let assert Ok(items) = accept.parse("text/html, application/json, image/*")
  items
  |> essences
  |> should.equal(["text/html", "application/json", "image/*"])
}

pub fn parse_preserves_wire_order_test() {
  let assert Ok(items) = accept.parse("application/json, text/html")
  items
  |> essences
  |> should.equal(["application/json", "text/html"])
}

pub fn parse_q_value_extracted_test() {
  let assert Ok(items) = accept.parse("text/html;q=0.5")
  case items {
    [head] -> {
      head.q |> should.equal(0.5)
      head.range |> should.equal(accept.Specific(mt("text/html")))
    }
    _ -> should.fail()
  }
}

pub fn parse_media_params_kept_test() {
  let assert Ok(items) = accept.parse("text/html;level=1;q=0.4")
  case items {
    [head] -> {
      head.q |> should.equal(0.4)
      case head.range {
        accept.Specific(m) ->
          mimetype.parameter_of(m, "level") |> should.equal(Some("1"))
        _ -> should.fail()
      }
    }
    _ -> should.fail()
  }
}

// ---------------------------------------------------------------------------
// 2. parse q-value edge cases
// ---------------------------------------------------------------------------

pub fn q_value_short_zero_test() {
  let assert Ok(items) = accept.parse("text/html;q=0")
  case items {
    [head] -> head.q |> should.equal(0.0)
    _ -> should.fail()
  }
}

pub fn q_value_short_one_test() {
  let assert Ok(items) = accept.parse("text/html;q=1")
  case items {
    [head] -> head.q |> should.equal(1.0)
    _ -> should.fail()
  }
}

pub fn q_value_zero_dot_test() {
  let assert Ok(items) = accept.parse("text/html;q=0.")
  case items {
    [head] -> head.q |> should.equal(0.0)
    _ -> should.fail()
  }
}

pub fn q_value_one_point_zero_zero_zero_test() {
  let assert Ok(items) = accept.parse("text/html;q=1.000")
  case items {
    [head] -> head.q |> should.equal(1.0)
    _ -> should.fail()
  }
}

pub fn q_value_three_decimals_test() {
  let assert Ok(items) = accept.parse("text/html;q=0.125")
  case items {
    [head] -> head.q |> should.equal(0.125)
    _ -> should.fail()
  }
}

pub fn q_value_uppercase_name_test() {
  let assert Ok(items) = accept.parse("text/html;Q=0.5")
  case items {
    [head] -> head.q |> should.equal(0.5)
    _ -> should.fail()
  }
}

pub fn q_value_invalid_two_test() {
  case accept.parse("text/html;q=2") {
    Error(accept.InvalidQValue(_)) -> Nil
    other -> should.fail() |> fn(_) { other |> should.equal(Ok([])) }
  }
}

pub fn q_value_invalid_negative_test() {
  case accept.parse("text/html;q=-0.5") {
    Error(accept.InvalidQValue(_)) -> Nil
    other -> should.fail() |> fn(_) { other |> should.equal(Ok([])) }
  }
}

pub fn q_value_invalid_four_decimals_test() {
  case accept.parse("text/html;q=0.1234") {
    Error(accept.InvalidQValue(_)) -> Nil
    other -> should.fail() |> fn(_) { other |> should.equal(Ok([])) }
  }
}

pub fn q_value_invalid_one_with_nonzero_test() {
  case accept.parse("text/html;q=1.5") {
    Error(accept.InvalidQValue(_)) -> Nil
    other -> should.fail() |> fn(_) { other |> should.equal(Ok([])) }
  }
}

// ---------------------------------------------------------------------------
// 3. parse quoted parameter values
// ---------------------------------------------------------------------------

pub fn parse_quoted_value_with_comma_test() {
  let assert Ok(items) = accept.parse("text/plain;description=\"a, b\";q=0.5")
  case items {
    [head] -> {
      head.q |> should.equal(0.5)
      case head.range {
        accept.Specific(m) ->
          mimetype.parameter_of(m, "description")
          |> should.equal(Some("a, b"))
        _ -> should.fail()
      }
    }
    _ -> should.fail()
  }
}

pub fn parse_quoted_value_with_semicolon_test() {
  let assert Ok(items) = accept.parse("text/plain;tag=\"x;y\"")
  case items {
    [head] ->
      case head.range {
        accept.Specific(m) ->
          mimetype.parameter_of(m, "tag") |> should.equal(Some("x;y"))
        _ -> should.fail()
      }
    _ -> should.fail()
  }
}

pub fn parse_two_entries_quoted_value_test() {
  let assert Ok(items) = accept.parse("text/plain;t=\"a,b\", application/json")
  items
  |> essences
  |> should.equal(["text/plain", "application/json"])
}

// ---------------------------------------------------------------------------
// 4. parse whitespace tolerance
// ---------------------------------------------------------------------------

pub fn whitespace_around_entries_test() {
  let assert Ok(items) = accept.parse("  text/html  ,  application/json  ")
  items
  |> essences
  |> should.equal(["text/html", "application/json"])
}

pub fn empty_entries_skipped_test() {
  let assert Ok(items) = accept.parse("text/html, , application/json")
  items
  |> essences
  |> should.equal(["text/html", "application/json"])
}

pub fn whitespace_around_q_test() {
  let assert Ok(items) = accept.parse("text/html ;  q  =  0.5")
  case items {
    [head] -> head.q |> should.equal(0.5)
    _ -> should.fail()
  }
}

// ---------------------------------------------------------------------------
// 5. parse malformed
// ---------------------------------------------------------------------------

pub fn malformed_no_slash_test() {
  case accept.parse("garbage") {
    Error(accept.InvalidMediaRange(_)) -> Nil
    other -> other |> should.equal(Ok([]))
  }
}

pub fn malformed_subtype_wildcard_with_type_wildcard_test() {
  case accept.parse("*/text") {
    Error(accept.InvalidMediaRange(_)) -> Nil
    other -> other |> should.equal(Ok([]))
  }
}

pub fn malformed_empty_essence_test() {
  case accept.parse("/") {
    Error(accept.InvalidMediaRange(_)) -> Nil
    other -> other |> should.equal(Ok([]))
  }
}

pub fn malformed_only_comma_test() {
  let assert Ok(items) = accept.parse(",,,")
  items |> should.equal([])
}

// ---------------------------------------------------------------------------
// 6. prefer sorting
// ---------------------------------------------------------------------------

pub fn prefer_q_descending_test() {
  let assert Ok(items) = accept.parse("text/html;q=0.5, application/json;q=0.9")
  accept.prefer(items)
  |> essences
  |> should.equal(["application/json", "text/html"])
}

pub fn prefer_specificity_breaks_tie_test() {
  let assert Ok(items) = accept.parse("*/*, text/*, text/html")
  accept.prefer(items)
  |> essences
  |> should.equal(["text/html", "text/*", "*/*"])
}

pub fn prefer_is_stable_test() {
  let assert Ok(items) = accept.parse("text/html, application/json")
  accept.prefer(items)
  |> essences
  |> should.equal(["text/html", "application/json"])
}

pub fn prefer_ext_count_breaks_tie_test() {
  let assert Ok(items) = accept.parse("text/html;q=0.5, text/plain;q=0.5;a=1")
  accept.prefer(items)
  |> essences
  |> should.equal(["text/plain", "text/html"])
}

// ---------------------------------------------------------------------------
// 7. negotiate
// ---------------------------------------------------------------------------

pub fn negotiate_empty_offers_test() {
  let assert Ok(items) = accept.parse("text/html")
  accept.negotiate(client_accepts: items, server_offers: [])
  |> should.equal(None)
}

pub fn negotiate_empty_client_returns_first_test() {
  accept.negotiate(client_accepts: [], server_offers: [
    mt("text/html"),
    mt("application/json"),
  ])
  |> should.equal(Some(mt("text/html")))
}

pub fn negotiate_star_star_returns_server_first_test() {
  let assert Ok(items) = accept.parse("*/*")
  accept.negotiate(client_accepts: items, server_offers: [
    mt("application/json"),
    mt("text/html"),
  ])
  |> should.equal(Some(mt("application/json")))
}

pub fn negotiate_exact_match_test() {
  let assert Ok(items) = accept.parse("text/html, application/json;q=0.5")
  accept.negotiate(client_accepts: items, server_offers: [
    mt("application/json"),
    mt("text/html"),
  ])
  |> should.equal(Some(mt("text/html")))
}

pub fn negotiate_type_wildcard_match_test() {
  let assert Ok(items) = accept.parse("image/*")
  accept.negotiate(client_accepts: items, server_offers: [
    mt("application/json"),
    mt("image/png"),
  ])
  |> should.equal(Some(mt("image/png")))
}

pub fn negotiate_q_zero_excludes_test() {
  let assert Ok(items) = accept.parse("text/html;q=0, application/json")
  accept.negotiate(client_accepts: items, server_offers: [
    mt("text/html"),
    mt("application/json"),
  ])
  |> should.equal(Some(mt("application/json")))
}

pub fn negotiate_no_match_test() {
  let assert Ok(items) = accept.parse("image/png")
  accept.negotiate(client_accepts: items, server_offers: [
    mt("text/html"),
    mt("application/json"),
  ])
  |> should.equal(None)
}

pub fn negotiate_specificity_wins_test() {
  let assert Ok(items) = accept.parse("*/*;q=0.5, text/html;q=0.5")
  accept.negotiate(client_accepts: items, server_offers: [
    mt("application/json"),
    mt("text/html"),
  ])
  |> should.equal(Some(mt("text/html")))
}

// ---------------------------------------------------------------------------
// 8. encoding / charset / language
// ---------------------------------------------------------------------------

pub fn parse_encoding_basic_test() {
  let assert Ok(items) = accept.parse_encoding("gzip, br;q=1.0, *;q=0.1")
  list.length(items) |> should.equal(3)
}

pub fn parse_encoding_lowercases_test() {
  let assert Ok(items) = accept.parse_encoding("GZIP")
  case items {
    [head] -> head.value |> should.equal("gzip")
    _ -> should.fail()
  }
}

pub fn negotiate_encoding_picks_highest_q_test() {
  let assert Ok(items) = accept.parse_encoding("gzip;q=0.5, br;q=1.0")
  accept.negotiate_value(client_accepts: items, server_offers: ["gzip", "br"])
  |> should.equal(Some("br"))
}

pub fn negotiate_encoding_wildcard_test() {
  let assert Ok(items) = accept.parse_encoding("gzip, *;q=0.1")
  accept.negotiate_value(client_accepts: items, server_offers: ["br", "gzip"])
  |> should.equal(Some("gzip"))
}

pub fn negotiate_charset_q_zero_excludes_test() {
  let assert Ok(items) = accept.parse_charset("utf-8;q=0, iso-8859-1")
  accept.negotiate_value(client_accepts: items, server_offers: [
    "utf-8",
    "iso-8859-1",
  ])
  |> should.equal(Some("iso-8859-1"))
}

pub fn negotiate_language_test() {
  let assert Ok(items) = accept.parse_language("en;q=0.9, ja")
  accept.negotiate_value(client_accepts: items, server_offers: ["en", "ja"])
  |> should.equal(Some("ja"))
}

// ---------------------------------------------------------------------------
// 9. real-world headers
// ---------------------------------------------------------------------------

pub fn firefox_default_accept_test() {
  let header =
    "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8"
  let assert Ok(items) = accept.parse(header)
  list.length(items) |> should.equal(6)
}

pub fn curl_default_accept_test() {
  let assert Ok(items) = accept.parse("*/*")
  accept.negotiate(client_accepts: items, server_offers: [
    mt("application/json"),
  ])
  |> should.equal(Some(mt("application/json")))
}

pub fn json_first_html_fallback_test() {
  let assert Ok(items) = accept.parse("application/json, text/html;q=0.5")
  accept.negotiate(client_accepts: items, server_offers: [
    mt("text/html"),
    mt("application/json"),
  ])
  |> should.equal(Some(mt("application/json")))
}

pub fn html_with_avif_and_webp_test() {
  let header =
    "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8"
  let assert Ok(items) = accept.parse(header)
  accept.negotiate(client_accepts: items, server_offers: [
    mt("application/json"),
    mt("text/html"),
  ])
  |> should.equal(Some(mt("text/html")))
}

// --- #125 negotiate_strings convenience wrappers ---------------------

pub fn negotiate_strings_picks_highest_q_test() {
  accept.negotiate_strings(header: "text/html;q=0.5, application/json", offers: [
    "application/json",
    "text/html",
  ])
  |> should.equal(Ok("application/json"))
}

pub fn negotiate_strings_returns_verbatim_offer_test() {
  // Returned string is the original input form (not the parsed and
  // re-rendered MimeType), so it can be compared directly against a
  // routing table.
  accept.negotiate_strings(header: "application/json", offers: [
    "APPLICATION/JSON",
  ])
  |> should.equal(Ok("APPLICATION/JSON"))
}

pub fn negotiate_strings_no_overlap_test() {
  accept.negotiate_strings(header: "image/png", offers: [
    "text/html",
    "application/json",
  ])
  |> should.equal(Error(accept.NoOverlap))
}

pub fn negotiate_strings_empty_offers_test() {
  accept.negotiate_strings(header: "*/*", offers: [])
  |> should.equal(Error(accept.NoOverlap))
}

pub fn negotiate_strings_invalid_header_test() {
  let result =
    accept.negotiate_strings(
      header: "this is/not a header at all;;;q=oops",
      offers: ["text/html"],
    )
  case result {
    Error(accept.InvalidHeader(_)) -> Nil
    _ -> should.fail()
  }
}

pub fn negotiate_strings_invalid_offer_test() {
  let result =
    accept.negotiate_strings(header: "*/*", offers: [
      "text/html",
      "not-a-mime-type",
    ])
  case result {
    Error(accept.InvalidOffer(raw: "not-a-mime-type")) -> Nil
    _ -> should.fail()
  }
}

pub fn negotiate_strings_wildcard_picks_first_offer_test() {
  accept.negotiate_strings(header: "*/*", offers: [
    "application/json",
    "text/html",
  ])
  |> should.equal(Ok("application/json"))
}

pub fn negotiate_encoding_strings_test() {
  accept.negotiate_encoding_strings(header: "gzip, br;q=0.9", offers: [
    "br",
    "gzip",
    "identity",
  ])
  |> should.equal(Ok("gzip"))
}

pub fn negotiate_encoding_strings_no_overlap_test() {
  accept.negotiate_encoding_strings(header: "br", offers: ["gzip"])
  |> should.equal(Error(accept.NoOverlap))
}

pub fn negotiate_charset_strings_test() {
  accept.negotiate_charset_strings(header: "utf-8", offers: [
    "utf-8",
    "iso-8859-1",
  ])
  |> should.equal(Ok("utf-8"))
}

pub fn negotiate_language_strings_test() {
  accept.negotiate_language_strings(header: "en-US, en;q=0.9, *;q=0.1", offers: [
    "en-US",
    "de",
  ])
  |> should.equal(Ok("en-US"))
}
