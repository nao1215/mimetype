//// Boundary cases found by mutation testing: each one fails when a
//// comparison, a range end or a boolean operator in `src/` is changed.

import gleam/bit_array
import gleam/list
import gleam/result
import gleam/string
import mimetype
import mimetype/accept

fn mt(s: String) -> mimetype.MimeType {
  let assert Ok(value) = mimetype.parse(s)
  value
}

fn ascii(count: Int) -> BitArray {
  bit_array.from_string(string.repeat("a", count))
}

fn charset(bytes: BitArray) -> Result(String, Nil) {
  mimetype.detect_charset(bytes)
}

// ---------------------------------------------------------------------------
// UTF-8 scan
// ---------------------------------------------------------------------------

pub fn utf8_two_byte_lead_range_test() {
  // U+0080 starts with C2 and U+07FF with DF, the ends of the range.
  assert charset(<<"a\u{0080}":utf8>>) == Ok("utf-8")
  assert charset(<<"a\u{07FF}":utf8>>) == Ok("utf-8")
  assert charset(<<"a":utf8, 0xC1, 0xBF>>) == Error(Nil)
  assert charset(<<"a":utf8, 0x80>>) == Error(Nil)
}

pub fn utf8_four_byte_sequence_bounds_test() {
  assert charset(<<"a\u{10000}":utf8>>) == Ok("utf-8")
  assert charset(<<"a\u{10FFFF}":utf8>>) == Ok("utf-8")
  assert charset(<<"a":utf8, 0xF5, 0x80, 0x80, 0x80>>) == Error(Nil)
  assert charset(<<"a":utf8, 0xF0, 0x9F, 0x41, 0x80>>) == Error(Nil)
  assert charset(<<"a":utf8, 0xF0, 0x9F, 0xC0, 0x80>>) == Error(Nil)
  assert charset(<<"a":utf8, 0xF0, 0x9F, 0x98, 0x41>>) == Error(Nil)
  assert charset(<<"a":utf8, 0xF0, 0x9F, 0x98, 0xC0>>) == Error(Nil)
}

// Input longer than 3072 bytes whose scanned part ends with `tail`.
fn cut(tail: BitArray) -> BitArray {
  let size = bit_array.byte_size(tail)
  <<ascii(3072 - size):bits, tail:bits, "zz":utf8>>
}

pub fn sequence_cut_by_the_limit_must_be_a_valid_start_test() {
  // One byte left: a lead byte from C2 to F4.
  assert charset(cut(<<0xC2>>)) == Ok("utf-8")
  assert charset(cut(<<0xF4>>)) == Ok("utf-8")
  assert charset(cut(<<0xC1>>)) == Error(Nil)
  assert charset(cut(<<0xF5>>)) == Error(Nil)
  // Two bytes: a three- or four-byte lead and an allowed second byte.
  assert charset(cut(<<0xE0, 0xA0>>)) == Ok("utf-8")
  assert charset(cut(<<0xF4, 0x8F>>)) == Ok("utf-8")
  assert charset(cut(<<0xE0, 0x80>>)) == Error(Nil)
  assert charset(cut(<<0xF4, 0x90>>)) == Error(Nil)
  assert charset(cut(<<0xDF, 0xBF>>)) == Ok("utf-8")
  assert charset(cut(<<0xF5, 0x80>>)) == Error(Nil)
  // Three bytes: a four-byte lead, an allowed second byte and a
  // continuation byte.
  assert charset(cut(<<0xF0, 0x90, 0x80>>)) == Ok("utf-8")
  assert charset(cut(<<0xF4, 0x8F, 0xBF>>)) == Ok("utf-8")
  assert charset(cut(<<0xF0, 0x90, 0x7F>>)) == Error(Nil)
  assert charset(cut(<<0xF0, 0x90, 0xC0>>)) == Error(Nil)
  assert charset(cut(<<0xF0, 0x80, 0x80>>)) == Error(Nil)
  assert charset(cut(<<0xF5, 0x80, 0x80>>)) == Error(Nil)
  assert charset(cut(<<0xEF, 0xBF, 0x41>>)) == Error(Nil)
}

pub fn invalid_byte_well_before_the_limit_test() {
  assert charset(<<ascii(3000):bits, 0xFF, ascii(100):bits>>) == Error(Nil)
}

// ---------------------------------------------------------------------------
// Declarations in the first 1024 bytes
// ---------------------------------------------------------------------------

// A `<meta>` whose closing quote is at byte `end` (counting from 0).
fn meta_ending_at(end: Int) -> BitArray {
  let tag = <<"<meta charset=\"koi8-r\"":utf8>>
  let padding = end + 1 - bit_array.byte_size(tag)
  <<ascii(padding):bits, tag:bits, ">":utf8>>
}

pub fn meta_charset_must_end_within_1024_bytes_test() {
  assert charset(meta_ending_at(1023)) == Ok("koi8-r")
  assert charset(meta_ending_at(1024)) == Ok("us-ascii")
}

pub fn bytes_above_0x7f_do_not_hide_a_declaration_test() {
  assert charset(<<"<html>":utf8, 0x80, "<meta charset=\"koi8-r\">":utf8>>)
    == Ok("koi8-r")
  assert charset(<<"<?xml version=\"1.0\" encoding=\"koi8-r\"?>":utf8, 0xFF>>)
    == Ok("koi8-r")
}

pub fn meta_must_be_followed_by_a_space_or_slash_test() {
  assert charset(<<"<metadata charset=\"koi8-r\">":utf8>>) == Ok("us-ascii")
  assert charset(<<"<meta/charset=\"koi8-r\">":utf8>>) == Ok("koi8-r")
  assert charset(<<"<meta\tcharset=koi8-r>":utf8>>) == Ok("koi8-r")
}

// ---------------------------------------------------------------------------
// Accept
// ---------------------------------------------------------------------------

// A parameter without `=` is not a weight; the lenient MIME parser drops
// it from the range.
pub fn parameter_without_a_value_is_not_a_weight_test() {
  assert accept.parse("text/html;level")
    == Ok([accept.AcceptItem(accept.Specific(mt("text/html")), 1.0)])
  assert accept.parse_values("gzip;level")
    == Ok([accept.ValueItem("gzip", 1.0)])
}

pub fn first_weight_decides_test() {
  assert accept.parse("text/html;q=0.5;q=0.9")
    |> result.map(list.map(_, fn(item) { item.quality }))
    == Ok([0.5])
}

// ---------------------------------------------------------------------------
// Tokens and predicates
// ---------------------------------------------------------------------------

// A value made of token characters is written without quotes. The ends
// of the letter and digit ranges are token characters.
pub fn token_character_range_ends_test() {
  list.each(["AZ", "az", "09", "!#$%&'*+-.^_`|~"], fn(value) {
    assert mimetype.to_string(mt("text/plain; a=" <> value))
      == "text/plain; a=" <> value
  })
  list.each(["@", "[", "`a{", "/", ":"], fn(value) {
    assert mimetype.to_string(mt("text/plain; a=\"" <> value <> "\""))
      == "text/plain; a=\"" <> value <> "\""
  })
}

pub fn is_text_for_sql_and_ecmascript_test() {
  assert mimetype.is_text(mt("application/sql"))
  assert mimetype.is_text(mt("application/x-sql"))
  assert mimetype.is_text(mt("application/ecmascript"))
  assert mimetype.is_text(mt("application/javascript"))
}

// ---------------------------------------------------------------------------
// Signatures
// ---------------------------------------------------------------------------

fn detected(bytes: BitArray) -> Result(String, Nil) {
  mimetype.detect(bytes) |> result.map(mimetype.to_string)
}

// The Matroska DocType element has to start in the first 256 bytes.
pub fn ebml_doc_type_search_window_test() {
  let doc_type = <<0x42, 0x82, 0x88, "matroska":utf8>>
  let at = fn(offset) {
    <<0x1A, 0x45, 0xDF, 0xA3, 0:size({ offset - 4 } * 8), doc_type:bits>>
  }
  assert detected(at(255)) == Ok("video/matroska")
  assert detected(at(256)) == Error(Nil)
  assert detected(at(300)) == Error(Nil)
}

// Zstandard frames for format versions 0.2 to 0.8 (first byte 0x22 to
// 0x28) and skippable frames (0x50 to 0x5F).
pub fn zstd_magic_ranges_test() {
  assert detected(<<0x22, 0xB5, 0x2F, 0xFD, 0>>) == Ok("application/zstd")
  assert detected(<<0x28, 0xB5, 0x2F, 0xFD, 0>>) == Ok("application/zstd")
  assert detected(<<0x50, 0x2A, 0x4D, 0x18, 0>>) == Ok("application/zstd")
  assert detected(<<0x5F, 0x2A, 0x4D, 0x18, 0>>) == Ok("application/zstd")
  list.each([0x21, 0x29], fn(first) {
    assert detected(<<first, 0xB5, 0x2F, 0xFD, 0>>) != Ok("application/zstd")
  })
  list.each([0x4F, 0x60], fn(first) {
    assert detected(<<first, 0x2A, 0x4D, 0x18, 0>>) != Ok("application/zstd")
  })
}

fn zip_entry(name: String, extra: BitArray, data: BitArray) -> BitArray {
  let name = bit_array.from_string(name)
  <<
    "PK":utf8,
    0x03,
    0x04,
    0:size(112),
    bit_array.byte_size(data):32-little,
    bit_array.byte_size(data):32-little,
    bit_array.byte_size(name):16-little,
    bit_array.byte_size(extra):16-little,
    name:bits,
    extra:bits,
    data:bits,
  >>
}

// The walk steps over each entry's name, extra field and data.
pub fn zip_walk_skips_extra_fields_and_data_test() {
  let first = zip_entry("a.class", <<1, 2, 3, 4>>, <<"hello":utf8>>)
  let manifest = zip_entry("META-INF/MANIFEST.MF", <<>>, <<>>)
  assert detected(<<first:bits, manifest:bits>>)
    == Ok("application/java-archive")
}

// Up to 20 entries are read.
pub fn zip_walk_reads_twenty_entries_test() {
  let filler = fn(count) {
    list.repeat(zip_entry("f", <<>>, <<>>), count) |> bit_array.concat
  }
  let manifest = zip_entry("META-INF/MANIFEST.MF", <<>>, <<>>)
  assert detected(<<filler(19):bits, manifest:bits>>)
    == Ok("application/java-archive")
  assert detected(<<filler(20):bits, manifest:bits>>) == Ok("application/zip")
}

// An entry with an empty name ends the walk.
pub fn zip_walk_stops_at_an_empty_name_test() {
  let empty = zip_entry("", <<>>, <<>>)
  let manifest = zip_entry("META-INF/MANIFEST.MF", <<>>, <<>>)
  assert detected(<<empty:bits, manifest:bits>>) == Ok("application/zip")
}

// Nesting deeper than 256 levels is accepted without reading further.
pub fn json_depth_limit_test() {
  let open = fn(count) { bit_array.from_string(string.repeat("[", count)) }
  assert detected(<<open(256):bits, "x":utf8>>) == Ok("application/json")
  assert detected(<<open(255):bits, "x":utf8>>) == Ok("text/plain")
}

// RFC 8259: a number starts with `-` or a digit, and may have an
// exponent with `e` or `E`.
pub fn json_number_grammar_test() {
  assert detected(<<"[0]":utf8>>) == Ok("application/json")
  assert detected(<<"[9]":utf8>>) == Ok("application/json")
  assert detected(<<"[1e5, 1E5, -2.5e-3]":utf8>>) == Ok("application/json")
  assert detected(<<"[.5]":utf8>>) == Ok("text/plain")
  assert detected(<<"[e]":utf8>>) == Ok("text/plain")
  assert detected(<<"[-]":utf8>>) == Ok("text/plain")
}

// A literal cut off by the end of the input still counts; a wrong one
// does not.
pub fn json_literal_prefix_test() {
  assert detected(<<"[tr":utf8>>) == Ok("application/json")
  assert detected(<<"[fals":utf8>>) == Ok("application/json")
  assert detected(<<"[n":utf8>>) == Ok("application/json")
  assert detected(<<"[tx":utf8>>) == Ok("text/plain")
  assert detected(<<"[nul]":utf8>>) == Ok("text/plain")
}

pub fn html_tag_terminators_and_case_test() {
  list.each(["\t", "\n", "\u{000C}", "\r", " ", ">"], fn(terminator) {
    assert detected(bit_array.from_string("<html" <> terminator))
      == Ok("text/html")
  })
  assert detected(<<"<A href=x>":utf8>>) == Ok("text/html")
  assert detected(<<"<HTML>":utf8>>) == Ok("text/html")
  assert detected(<<"<htmx>":utf8>>) == Ok("text/plain")
}
