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
  let assert [accept.AcceptItem(range: accept.Specific(m), quality:)] = items
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
  let assert [accept.AcceptItem(range: accept.Specific(m), quality:)] = items
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

// ---------------------------------------------------------------------------
// 10. RFC 9110 conformance
// ---------------------------------------------------------------------------

// §12.4.2: qvalue = ( "0" [ "." 0*3DIGIT ] ) / ( "1" [ "." 0*3("0") ] ).
// Signs are not digits.
pub fn q_value_fraction_must_be_digits_test() {
  assert accept.parse("text/html;q=0.-1")
    == Error(accept.InvalidQValue("text/html;q=0.-1"))
  assert accept.parse("text/html;q=0.+5")
    == Error(accept.InvalidQValue("text/html;q=0.+5"))
  assert accept.parse("text/html;q=1.-0")
    == Error(accept.InvalidQValue("text/html;q=1.-0"))
  assert accept.parse_values("gzip;q=0.-1")
    == Error(accept.InvalidQValue("gzip;q=0.-1"))
}

// §12.5.1: recipients SHOULD process any parameter named "q" as weight,
// regardless of order, and the accept-ext grammar was removed, so
// parameters after q still belong to the media range.
pub fn parameters_after_q_belong_to_the_range_test() {
  let assert Ok([accept.AcceptItem(range: accept.Specific(range), quality:)]) =
    accept.parse("text/plain;q=0.5;format=flowed")
  assert quality == 0.5
  assert mimetype.parameter(range, "format") == Ok("flowed")
}

// §12.5.1: "text/plain;format=flowed" is more specific than "text/plain",
// which is more specific than "text/*", then "*/*".
pub fn prefer_orders_by_rfc_precedence_test() {
  let assert Ok(items) =
    accept.parse("*/*, text/*, text/plain, text/plain;format=flowed")
  assert accept.prefer(items)
    |> list.map(fn(item) {
      case item.range {
        accept.Specific(m) -> mimetype.to_string(m)
        accept.TypeWildcard(t) -> t <> "/*"
        accept.AnyType -> "*/*"
      }
    })
    == ["text/plain; format=flowed", "text/plain", "text/*", "*/*"]
}

// §12.5.1 Table 5. The RFC lists 0.7 for text/html;level=3, which errata
// report 7138 corrects to 0.3: no text/html range is in the header, so
// text/* applies.
pub fn rfc_9110_table_5_test() {
  let assert Ok(items) =
    accept.parse(
      "text/*;q=0.3, text/plain;q=0.7, text/plain;format=flowed, text/plain;format=fixed;q=0.4, */*;q=0.5",
    )
  let pick = fn(a, b) { accept.negotiate(items, [mt(a), mt(b)]) }
  // flowed 1 > plain 0.7 > image/jpeg 0.5 > fixed 0.4 > html 0.3
  assert pick("text/plain;format=fixed", "text/plain;format=flowed")
    == Ok(mt("text/plain;format=flowed"))
  assert pick("text/plain;format=fixed", "text/plain") == Ok(mt("text/plain"))
  assert pick("text/plain;format=fixed", "image/jpeg") == Ok(mt("image/jpeg"))
  assert pick("text/html", "text/plain;format=fixed")
    == Ok(mt("text/plain;format=fixed"))
  assert pick("text/html;level=3", "text/plain;format=fixed")
    == Ok(mt("text/plain;format=fixed"))
  assert pick("text/html;level=3", "text/html") == Ok(mt("text/html;level=3"))
}

// A range with parameters applies only to offers that carry them.
// Charset values compare without regard to case (RFC 9110 §8.3.2).
pub fn range_parameters_must_match_the_offer_test() {
  let assert Ok(items) = accept.parse("text/html;charset=utf-8")
  assert accept.negotiate(items, [mt("text/html")]) == Error(Nil)
  assert accept.negotiate(items, [mt("text/html;charset=UTF-8")])
    == Ok(mt("text/html;charset=UTF-8"))
  assert accept.negotiate(items, [mt("text/html;charset=utf-8;level=1")])
    == Ok(mt("text/html;charset=utf-8;level=1"))
  let assert Ok(items) = accept.parse("text/plain;format=flowed")
  assert accept.negotiate(items, [mt("text/plain;format=Flowed")]) == Error(Nil)
}

// §12.5.1: the q value comes from the most specific matching range, so a
// parameterised range overrides a bare one for the offers it matches.
pub fn parameterised_range_overrides_the_bare_range_test() {
  let assert Ok(items) = accept.parse("text/html, text/html;level=1;q=0")
  assert accept.negotiate(items, [mt("text/html;level=1")]) == Error(Nil)
  assert accept.negotiate(items, [mt("text/html;level=1"), mt("text/html")])
    == Ok(mt("text/html"))
}

// §12.5.3 rule 2: a representation with no content coding is acceptable
// unless "identity;q=0" or "*;q=0" excludes it. It is the least preferred
// choice when the header does not name it.
pub fn identity_is_acceptable_unless_excluded_test() {
  assert negotiate_value("gzip", ["identity"]) == Ok("identity")
  assert negotiate_value("gzip", ["identity", "gzip"]) == Ok("gzip")
  assert negotiate_value("gzip;q=0.001", ["identity", "gzip"]) == Ok("identity")
  assert negotiate_value("gzip, identity;q=0", ["identity"]) == Error(Nil)
  assert negotiate_value("*;q=0", ["identity"]) == Error(Nil)
  assert negotiate_value("*;q=0, identity", ["identity"]) == Ok("identity")
  assert negotiate_value("br, *;q=0.5", ["identity", "br"]) == Ok("br")
}

// §12.5.3: an empty Accept-Encoding asks for no content coding.
pub fn empty_header_prefers_identity_test() {
  assert negotiate_value("", ["gzip", "identity"]) == Ok("identity")
  assert negotiate_value("", ["gzip", "br"]) == Ok("gzip")
}

// §12.5.4 with RFC 4647 §3.3.1 basic filtering: a range matches a tag
// that equals it or starts with it followed by "-". The longest
// matching range sets the quality, as RFC 2616 §14.4 described.
pub fn language_ranges_use_basic_filtering_test() {
  assert negotiate_value("en", ["de", "en-US"]) == Ok("en-US")
  assert negotiate_value("EN", ["en-us"]) == Ok("en-us")
  assert negotiate_value("en;q=0.5, en-gb", ["en-US", "en-GB"]) == Ok("en-GB")
  assert negotiate_value("en-gb", ["en"]) == Error(Nil)
  assert negotiate_value("en", ["eng"]) == Error(Nil)
  assert negotiate_value("en, en-us;q=0", ["en-US", "en"]) == Ok("en")
  assert negotiate_value("da, en-gb;q=0.8, en;q=0.7", ["en-AU", "en-GB"])
    == Ok("en-GB")
}

// `parse` and `parse_values` both report the entry that failed.
pub fn parse_values_reports_the_failing_entry_test() {
  assert accept.parse_values("gzip, br;q=x")
    == Error(accept.InvalidQValue("br;q=x"))
}
