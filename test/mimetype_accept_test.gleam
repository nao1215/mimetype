import gleam/list
import gleeunit
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
      accept.Specific(m) -> mimetype.essence(m)
      accept.TypeWildcard(t) -> t <> "/*"
      accept.AnyType -> "*/*"
    }
  })
}

// ---------------------------------------------------------------------------
// 1. parse basics
// ---------------------------------------------------------------------------

pub fn parse_empty_string_test() {
  assert accept.parse("") == Ok([])
}

pub fn parse_whitespace_only_test() {
  assert accept.parse("   ") == Ok([])
}

pub fn parse_single_concrete_test() {
  let assert Ok(items) = accept.parse("text/html")
  assert items
    |> ranges
    == [accept.Specific(mt("text/html"))]
}

pub fn parse_default_q_is_1_test() {
  let assert Ok(items) = accept.parse("text/html")
  let assert [head] = items
  assert head.quality == 1.0
}

pub fn parse_star_star_test() {
  let assert Ok(items) = accept.parse("*/*")
  assert items
    |> ranges
    == [accept.AnyType]
}

pub fn parse_type_wildcard_test() {
  let assert Ok(items) = accept.parse("image/*")
  assert items
    |> ranges
    == [accept.TypeWildcard("image")]
}

pub fn parse_multiple_entries_test() {
  let assert Ok(items) = accept.parse("text/html, application/json, image/*")
  assert items
    |> essences
    == ["text/html", "application/json", "image/*"]
}

pub fn parse_preserves_wire_order_test() {
  let assert Ok(items) = accept.parse("application/json, text/html")
  assert items
    |> essences
    == ["application/json", "text/html"]
}

pub fn parse_q_value_extracted_test() {
  let assert Ok(items) = accept.parse("text/html;q=0.5")
  let assert [head] = items
  assert head.quality == 0.5
  assert head.range == accept.Specific(mt("text/html"))
}

pub fn parse_media_params_kept_test() {
  let assert Ok(items) = accept.parse("text/html;level=1;q=0.4")
  let assert [accept.AcceptItem(range: accept.Specific(m), quality:, ..)] =
    items
  assert quality == 0.4
  assert mimetype.parameter(m, "level") == Ok("1")
}

// ---------------------------------------------------------------------------
// 2. parse q-value edge cases
// ---------------------------------------------------------------------------

pub fn q_value_short_zero_test() {
  let assert Ok(items) = accept.parse("text/html;q=0")
  let assert [head] = items
  assert head.quality == 0.0
}

pub fn q_value_short_one_test() {
  let assert Ok(items) = accept.parse("text/html;q=1")
  let assert [head] = items
  assert head.quality == 1.0
}

pub fn q_value_zero_dot_test() {
  let assert Ok(items) = accept.parse("text/html;q=0.")
  let assert [head] = items
  assert head.quality == 0.0
}

pub fn q_value_one_point_zero_zero_zero_test() {
  let assert Ok(items) = accept.parse("text/html;q=1.000")
  let assert [head] = items
  assert head.quality == 1.0
}

pub fn q_value_three_decimals_test() {
  let assert Ok(items) = accept.parse("text/html;q=0.125")
  let assert [head] = items
  assert head.quality == 0.125
}

pub fn q_value_uppercase_name_test() {
  let assert Ok(items) = accept.parse("text/html;Q=0.5")
  let assert [head] = items
  assert head.quality == 0.5
}

pub fn q_value_invalid_two_test() {
  let assert Error(accept.InvalidQValue(_)) = accept.parse("text/html;q=2")
}

pub fn q_value_invalid_negative_test() {
  let assert Error(accept.InvalidQValue(_)) = accept.parse("text/html;q=-0.5")
}

pub fn q_value_invalid_four_decimals_test() {
  let assert Error(accept.InvalidQValue(_)) = accept.parse("text/html;q=0.1234")
}

pub fn q_value_invalid_one_with_nonzero_test() {
  let assert Error(accept.InvalidQValue(_)) = accept.parse("text/html;q=1.5")
}

// ---------------------------------------------------------------------------
// 3. parse quoted parameter values
// ---------------------------------------------------------------------------

pub fn parse_quoted_value_with_comma_test() {
  let assert Ok(items) = accept.parse("text/plain;description=\"a, b\";q=0.5")
  let assert [accept.AcceptItem(range: accept.Specific(m), quality:, ..)] =
    items
  assert quality == 0.5
  assert mimetype.parameter(m, "description") == Ok("a, b")
}

pub fn parse_quoted_value_with_semicolon_test() {
  let assert Ok(items) = accept.parse("text/plain;tag=\"x;y\"")
  let assert [accept.AcceptItem(range: accept.Specific(m), ..)] = items
  assert mimetype.parameter(m, "tag") == Ok("x;y")
}

pub fn parse_two_entries_quoted_value_test() {
  let assert Ok(items) = accept.parse("text/plain;t=\"a,b\", application/json")
  assert items
    |> essences
    == ["text/plain", "application/json"]
}

// ---------------------------------------------------------------------------
// 4. parse whitespace tolerance
// ---------------------------------------------------------------------------

pub fn whitespace_around_entries_test() {
  let assert Ok(items) = accept.parse("  text/html  ,  application/json  ")
  assert items
    |> essences
    == ["text/html", "application/json"]
}

pub fn empty_entries_skipped_test() {
  let assert Ok(items) = accept.parse("text/html, , application/json")
  assert items
    |> essences
    == ["text/html", "application/json"]
}

pub fn whitespace_around_q_test() {
  let assert Ok(items) = accept.parse("text/html ;  q  =  0.5")
  let assert [head] = items
  assert head.quality == 0.5
}

// ---------------------------------------------------------------------------
// 5. parse malformed
// ---------------------------------------------------------------------------

pub fn malformed_no_slash_test() {
  let assert Error(accept.InvalidMediaRange(_)) = accept.parse("garbage")
}

pub fn malformed_subtype_wildcard_with_type_wildcard_test() {
  let assert Error(accept.InvalidMediaRange(_)) = accept.parse("*/text")
}

pub fn malformed_empty_essence_test() {
  let assert Error(accept.InvalidMediaRange(_)) = accept.parse("/")
}

pub fn malformed_only_comma_test() {
  let assert Ok(items) = accept.parse(",,,")
  assert items == []
}

// ---------------------------------------------------------------------------
// 6. prefer sorting
// ---------------------------------------------------------------------------

pub fn prefer_q_descending_test() {
  let assert Ok(items) = accept.parse("text/html;q=0.5, application/json;q=0.9")
  assert accept.prefer(items)
    |> essences
    == ["application/json", "text/html"]
}

pub fn prefer_specificity_breaks_tie_test() {
  let assert Ok(items) = accept.parse("*/*, text/*, text/html")
  assert accept.prefer(items)
    |> essences
    == ["text/html", "text/*", "*/*"]
}

pub fn prefer_is_stable_test() {
  let assert Ok(items) = accept.parse("text/html, application/json")
  assert accept.prefer(items)
    |> essences
    == ["text/html", "application/json"]
}

pub fn prefer_ext_count_breaks_tie_test() {
  let assert Ok(items) = accept.parse("text/html;q=0.5, text/plain;q=0.5;a=1")
  assert accept.prefer(items)
    |> essences
    == ["text/plain", "text/html"]
}

// ---------------------------------------------------------------------------
// 7. negotiate
// ---------------------------------------------------------------------------

pub fn negotiate_empty_offers_test() {
  let assert Ok(items) = accept.parse("text/html")
  assert accept.negotiate(items, []) == Error(Nil)
}

pub fn negotiate_empty_client_returns_first_test() {
  assert accept.negotiate([], [
      mt("text/html"),
      mt("application/json"),
    ])
    == Ok(mt("text/html"))
}

pub fn negotiate_star_star_returns_server_first_test() {
  let assert Ok(items) = accept.parse("*/*")
  assert accept.negotiate(items, [
      mt("application/json"),
      mt("text/html"),
    ])
    == Ok(mt("application/json"))
}

pub fn negotiate_exact_match_test() {
  let assert Ok(items) = accept.parse("text/html, application/json;q=0.5")
  assert accept.negotiate(items, [
      mt("application/json"),
      mt("text/html"),
    ])
    == Ok(mt("text/html"))
}

pub fn negotiate_type_wildcard_match_test() {
  let assert Ok(items) = accept.parse("image/*")
  assert accept.negotiate(items, [
      mt("application/json"),
      mt("image/png"),
    ])
    == Ok(mt("image/png"))
}

pub fn negotiate_q_zero_excludes_test() {
  let assert Ok(items) = accept.parse("text/html;q=0, application/json")
  assert accept.negotiate(items, [
      mt("text/html"),
      mt("application/json"),
    ])
    == Ok(mt("application/json"))
}

pub fn negotiate_no_match_test() {
  let assert Ok(items) = accept.parse("image/png")
  assert accept.negotiate(items, [
      mt("text/html"),
      mt("application/json"),
    ])
    == Error(Nil)
}

pub fn negotiate_specificity_wins_test() {
  let assert Ok(items) = accept.parse("*/*;q=0.5, text/html;q=0.5")
  assert accept.negotiate(items, [
      mt("application/json"),
      mt("text/html"),
    ])
    == Ok(mt("text/html"))
}

// RFC 9110 §12.5.1: when several media ranges match an offer, the most
// specific one decides its q-value, so a broader range listed with a
// higher q does not override it.
pub fn negotiate_explicit_q_zero_overrides_wildcards_test() {
  let assert Ok(items) = accept.parse("*/*, text/html;q=0")
  assert accept.negotiate(items, [mt("text/html")]) == Error(Nil)

  let assert Ok(items) =
    accept.parse("*/*;q=0.5, application/json;q=0, application/*")
  assert accept.negotiate(items, [
      mt("text/html"),
      mt("application/json"),
      mt("application/xml"),
    ])
    == Ok(mt("application/xml"))
}

pub fn negotiate_most_specific_range_sets_the_q_value_test() {
  // text/plain gets 0.3 from text/*, not 0.5 from */*, so json wins.
  let assert Ok(items) =
    accept.parse("text/*;q=0.3, */*;q=0.5, application/json;q=0.4")
  assert accept.negotiate(items, [
      mt("text/plain"),
      mt("application/json"),
    ])
    == Ok(mt("application/json"))
}

// ---------------------------------------------------------------------------
// 8. encoding / charset / language
// ---------------------------------------------------------------------------

pub fn parse_encoding_basic_test() {
  let assert Ok(items) = accept.parse_values("gzip, br;q=1.0, *;q=0.1")
  assert list.length(items) == 3
}

pub fn parse_encoding_lowercases_test() {
  let assert Ok(items) = accept.parse_values("GZIP")
  let assert [head] = items
  assert head.value == "gzip"
}

pub fn negotiate_encoding_picks_highest_q_test() {
  let assert Ok(items) = accept.parse_values("gzip;q=0.5, br;q=1.0")
  assert accept.negotiate_value(items, ["gzip", "br"]) == Ok("br")
}

pub fn negotiate_encoding_wildcard_test() {
  let assert Ok(items) = accept.parse_values("gzip, *;q=0.1")
  assert accept.negotiate_value(items, ["br", "gzip"]) == Ok("gzip")
}

pub fn negotiate_charset_q_zero_excludes_test() {
  let assert Ok(items) = accept.parse_values("utf-8;q=0, iso-8859-1")
  assert accept.negotiate_value(items, [
      "utf-8",
      "iso-8859-1",
    ])
    == Ok("iso-8859-1")
}

pub fn negotiate_language_test() {
  let assert Ok(items) = accept.parse_values("en;q=0.9, ja")
  assert accept.negotiate_value(items, ["en", "ja"]) == Ok("ja")
}

// ---------------------------------------------------------------------------
// 9. real-world headers
// ---------------------------------------------------------------------------

pub fn firefox_default_accept_test() {
  let header =
    "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8"
  let assert Ok(items) = accept.parse(header)
  assert list.length(items) == 6
}

pub fn curl_default_accept_test() {
  let assert Ok(items) = accept.parse("*/*")
  assert accept.negotiate(items, [
      mt("application/json"),
    ])
    == Ok(mt("application/json"))
}

pub fn json_first_html_fallback_test() {
  let assert Ok(items) = accept.parse("application/json, text/html;q=0.5")
  assert accept.negotiate(items, [
      mt("text/html"),
      mt("application/json"),
    ])
    == Ok(mt("application/json"))
}

pub fn html_with_avif_and_webp_test() {
  let header =
    "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8"
  let assert Ok(items) = accept.parse(header)
  assert accept.negotiate(items, [
      mt("application/json"),
      mt("text/html"),
    ])
    == Ok(mt("text/html"))
}

// --- Accept-Encoding, Accept-Charset and Accept-Language -------------

fn negotiate_value(
  header: String,
  offers: List(String),
) -> Result(String, Nil) {
  let assert Ok(items) = accept.parse_values(header)
  accept.negotiate_value(items, offers)
}

pub fn negotiate_value_encoding_test() {
  assert negotiate_value("gzip, br;q=0.9", ["br", "gzip", "identity"])
    == Ok("gzip")
}

pub fn negotiate_value_no_overlap_test() {
  assert negotiate_value("br", ["gzip"]) == Error(Nil)
}

pub fn negotiate_value_returns_the_offer_as_given_test() {
  assert negotiate_value("en-US, en;q=0.9, *;q=0.1", ["en-US", "de"])
    == Ok("en-US")
}

pub fn negotiate_value_empty_offers_test() {
  assert negotiate_value("*", []) == Error(Nil)
}
