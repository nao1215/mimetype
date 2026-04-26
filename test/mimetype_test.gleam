import gleam/list
import gleeunit
import gleeunit/should
import mimetype

pub fn main() -> Nil {
  gleeunit.main()
}

fn should_detect(bytes, mime_type) {
  mimetype.detect(bytes)
  |> should.equal(mime_type)
}

fn should_fall_back(bytes) {
  mimetype.detect(bytes)
  |> should.equal("application/octet-stream")
}

pub fn extension_to_mime_type_normalizes_input_test() {
  mimetype.extension_to_mime_type(".JSON")
  |> should.equal("application/json")
}

pub fn extension_to_mime_type_empty_string_falls_back_to_default_test() {
  mimetype.extension_to_mime_type("")
  |> should.equal("application/octet-stream")
}

pub fn extension_to_mime_type_single_dot_falls_back_to_default_test() {
  mimetype.extension_to_mime_type(".")
  |> should.equal("application/octet-stream")
}

pub fn extension_to_mime_type_trims_whitespace_test() {
  mimetype.extension_to_mime_type("  json  ")
  |> should.equal("application/json")
}

pub fn extension_to_mime_type_strips_multiple_leading_dots_test() {
  mimetype.extension_to_mime_type("..json")
  |> should.equal("application/json")
}

pub fn extension_to_mime_type_falls_back_for_unknown_test() {
  mimetype.extension_to_mime_type("totally-unknown-ext")
  |> should.equal("application/octet-stream")
}

pub fn extension_to_mime_type_strict_returns_ok_for_known_extension_test() {
  mimetype.extension_to_mime_type_strict(".JSON")
  |> should.equal(Ok("application/json"))
}

pub fn extension_to_mime_type_strict_returns_error_for_unknown_extension_test() {
  mimetype.extension_to_mime_type_strict("totally-unknown-ext")
  |> should.equal(Error(Nil))
}

pub fn mime_type_to_extensions_returns_all_known_extensions_test() {
  mimetype.mime_type_to_extensions("image/jpeg")
  |> should.equal(["jpg", "jpeg", "jpe"])
}

pub fn mime_type_to_extensions_strict_returns_ok_for_known_type_test() {
  mimetype.mime_type_to_extensions_strict("image/jpeg")
  |> should.equal(Ok(["jpg", "jpeg", "jpe"]))
}

pub fn mime_type_to_extensions_strict_returns_error_for_unknown_type_test() {
  mimetype.mime_type_to_extensions_strict("application/x-not-real")
  |> should.equal(Error(Nil))
}

pub fn mime_type_to_extensions_empty_string_returns_empty_list_test() {
  mimetype.mime_type_to_extensions("")
  |> should.equal([])
}

pub fn mime_type_to_extensions_unknown_type_returns_empty_list_test() {
  mimetype.mime_type_to_extensions("application/x-not-real")
  |> should.equal([])
}

pub fn mime_type_to_extensions_trims_whitespace_test() {
  mimetype.mime_type_to_extensions("  image/jpeg  ")
  |> should.equal(["jpg", "jpeg", "jpe"])
}

pub fn mime_type_to_extensions_normalizes_case_test() {
  mimetype.mime_type_to_extensions("IMAGE/JPEG")
  |> should.equal(["jpg", "jpeg", "jpe"])
}

pub fn mime_type_to_extensions_ignores_parameters_test() {
  mimetype.mime_type_to_extensions("text/html; charset=utf-8")
  |> should.equal(["html", "htm", "shtml"])
}

pub fn essence_strips_parameters_and_normalizes_case_test() {
  mimetype.essence(" TEXT/HTML ; charset=UTF-8 ")
  |> should.equal("text/html")
}

pub fn parameter_matches_case_insensitively_test() {
  mimetype.parameter("text/html; CHARSET=UTF-8; boundary=abc123", "charset")
  |> should.equal(Ok("UTF-8"))
}

pub fn parameter_returns_error_for_missing_key_test() {
  mimetype.parameter("text/html; charset=UTF-8", "boundary")
  |> should.equal(Error(Nil))
}

pub fn charset_returns_lowercased_value_test() {
  mimetype.charset("text/html; CHARSET=UTF-8")
  |> should.equal(Ok("utf-8"))
}

pub fn charset_returns_error_when_missing_test() {
  mimetype.charset("text/html")
  |> should.equal(Error(Nil))
}

pub fn family_predicates_use_essence_test() {
  mimetype.is_image("IMAGE/PNG; version=1")
  |> should.equal(True)

  mimetype.is_text("text/html; charset=utf-8")
  |> should.equal(True)

  mimetype.is_audio("audio/mpeg")
  |> should.equal(True)

  mimetype.is_video("video/mp4")
  |> should.equal(True)

  mimetype.is_image("application/json")
  |> should.equal(False)
}

pub fn extension_and_mime_mapping_roundtrip_test() {
  ["json", "png", "jpg", "pdf", "html", "css", "js", "svg", "zip", "mp3"]
  |> list.each(fn(extension) {
    let mime_type = mimetype.extension_to_mime_type(extension)

    mimetype.mime_type_to_extensions(mime_type)
    |> list.contains(extension)
    |> should.equal(True)
  })
}

pub fn filename_to_mime_type_empty_string_falls_back_to_default_test() {
  mimetype.filename_to_mime_type("")
  |> should.equal("application/octet-stream")
}

pub fn filename_to_mime_type_without_extension_falls_back_to_default_test() {
  mimetype.filename_to_mime_type("README")
  |> should.equal("application/octet-stream")
}

pub fn filename_to_mime_type_detects_pdf_test() {
  mimetype.filename_to_mime_type("document.pdf")
  |> should.equal("application/pdf")
}

pub fn filename_to_mime_type_strict_returns_ok_for_known_filename_test() {
  mimetype.filename_to_mime_type_strict("document.pdf")
  |> should.equal(Ok("application/pdf"))
}

pub fn filename_to_mime_type_strict_returns_error_without_extension_test() {
  mimetype.filename_to_mime_type_strict("README")
  |> should.equal(Error(Nil))
}

pub fn filename_to_mime_type_uses_last_extension_test() {
  mimetype.filename_to_mime_type("/tmp/archive.tar.gz")
  |> should.equal("application/gzip")
}

pub fn filename_to_mime_type_ignores_query_string_test() {
  mimetype.filename_to_mime_type("file.pdf?v=2")
  |> should.equal("application/pdf")
}

pub fn filename_to_mime_type_ignores_fragment_test() {
  mimetype.filename_to_mime_type("file.pdf#page=5")
  |> should.equal("application/pdf")
}

pub fn filename_to_mime_type_supports_windows_paths_test() {
  mimetype.filename_to_mime_type("C:\\Users\\file.json")
  |> should.equal("application/json")
}

pub fn filename_to_mime_type_trailing_slash_falls_back_to_default_test() {
  mimetype.filename_to_mime_type("/path/to/")
  |> should.equal("application/octet-stream")
}

pub fn filename_to_mime_type_ignores_hidden_file_without_extension_test() {
  mimetype.filename_to_mime_type(".gitignore")
  |> should.equal("application/octet-stream")
}

pub fn detect_png_test() {
  mimetype.detect(<<0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A>>)
  |> should.equal("image/png")
}

pub fn detect_jpeg_test() {
  mimetype.detect(<<0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10>>)
  |> should.equal("image/jpeg")
}

pub fn detect_gif_test() {
  mimetype.detect(<<"GIF89a":utf8>>)
  |> should.equal("image/gif")
}

pub fn detect_pdf_test() {
  mimetype.detect(<<"%PDF-1.7":utf8>>)
  |> should.equal("application/pdf")
}

pub fn detect_zip_test() {
  mimetype.detect(<<0x50, 0x4B, 0x03, 0x04, 20, 0, 0, 0>>)
  |> should.equal("application/zip")
}

pub fn detect_wav_test() {
  mimetype.detect(<<"RIFF":utf8, 0, 0, 0, 0, "WAVE":utf8>>)
  |> should.equal("audio/wav")
}

pub fn detect_webp_test() {
  mimetype.detect(<<"RIFF":utf8, 0, 0, 0, 0, "WEBP":utf8>>)
  |> should.equal("image/webp")
}

pub fn detect_avi_test() {
  should_detect(<<"RIFF":utf8, 0, 0, 0, 0, "AVI ":utf8>>, "video/x-msvideo")
}

pub fn detect_aiff_test() {
  should_detect(<<"FORM":utf8, 0, 0, 0, 0, "AIFF":utf8>>, "audio/aiff")
}

pub fn detect_bmp_test() {
  should_detect(<<"BM":utf8, 0, 0>>, "image/bmp")
}

pub fn detect_tiff_variants_test() {
  should_detect(<<0x49, 0x49, 0x2A, 0x00>>, "image/tiff")
  should_detect(<<0x4D, 0x4D, 0x00, 0x2A>>, "image/tiff")
}

pub fn detect_ico_test() {
  should_detect(<<0x00, 0x00, 0x01, 0x00>>, "image/x-icon")
}

pub fn detect_sqlite_test() {
  mimetype.detect(<<"SQLite format 3":utf8, 0>>)
  |> should.equal("application/vnd.sqlite3")
}

pub fn detect_strict_returns_ok_for_known_signature_test() {
  mimetype.detect_strict(<<0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A>>)
  |> should.equal(Ok("image/png"))
}

pub fn detect_strict_returns_error_for_unknown_signature_test() {
  mimetype.detect_strict(<<>>)
  |> should.equal(Error(Nil))
}

pub fn detect_archive_and_compression_formats_test() {
  should_detect(<<0x50, 0x4B, 0x05, 0x06>>, "application/zip")
  should_detect(<<0x50, 0x4B, 0x07, 0x08>>, "application/zip")
  should_detect(<<0x1F, 0x8B>>, "application/gzip")
  should_detect(<<"BZh":utf8, 0x39>>, "application/x-bzip2")
  should_detect(<<0xFD, 0x37, 0x7A, 0x58, 0x5A, 0x00>>, "application/x-xz")
  should_detect(
    <<0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C>>,
    "application/x-7z-compressed",
  )
  should_detect(
    <<0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x00>>,
    "application/x-rar-compressed",
  )
  should_detect(
    <<0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x01, 0x00>>,
    "application/x-rar-compressed",
  )
  should_detect(<<"MSCF":utf8>>, "application/vnd.ms-cab-compressed")
  should_detect(<<0x22, 0xB5, 0x2F, 0xFD>>, "application/zstd")
  should_detect(<<0x50, 0x2A, 0x4D, 0x18>>, "application/zstd")
}

pub fn detect_runtime_and_container_formats_test() {
  should_detect(<<0x00, 0x61, 0x73, 0x6D>>, "application/wasm")
  should_detect(<<0x7F, 0x45, 0x4C, 0x46>>, "application/x-elf")
  should_detect(<<"PAR1":utf8>>, "application/vnd.apache.parquet")
  should_detect(<<"OggS":utf8>>, "application/ogg")
  should_detect(<<0x1A, 0x45, 0xDF, 0xA3>>, "video/webm")
}

pub fn detect_audio_formats_test() {
  should_detect(<<"ID3":utf8>>, "audio/mpeg")
  should_detect(<<0xFF, 0xFB, 0x90>>, "audio/mpeg")
  should_detect(<<"fLaC":utf8, 0x00, 0x00, 0x00, 0x22>>, "audio/flac")
  should_detect(<<"MThd":utf8>>, "audio/midi")
}

pub fn detect_empty_bytes_falls_back_to_default_test() {
  mimetype.detect(<<>>)
  |> should.equal("application/octet-stream")
}

pub fn detect_single_png_byte_falls_back_to_default_test() {
  mimetype.detect(<<0x89>>)
  |> should.equal("application/octet-stream")
}

pub fn detect_single_gif_byte_falls_back_to_default_test() {
  mimetype.detect(<<"G":utf8>>)
  |> should.equal("application/octet-stream")
}

pub fn detect_tar_boundary_does_not_false_positive_before_offset_test() {
  mimetype.detect(<<0:size({ 256 * 8 })>>)
  |> should.equal("application/octet-stream")
}

pub fn detect_tar_via_offset_signature_test() {
  let bytes = <<0:size({ 257 * 8 }), 0x75, 0x73, 0x74, 0x61, 0x72, 0:size(64)>>

  mimetype.detect(bytes)
  |> should.equal("application/x-tar")
}

pub fn detect_incomplete_mp4_brand_falls_back_to_default_test() {
  mimetype.detect(<<0:size(32), "ftyp":utf8>>)
  |> should.equal("application/octet-stream")
}

pub fn detect_mp4_family_formats_test() {
  should_detect(<<0:size(32), "ftyp":utf8, "avif":utf8>>, "image/avif")
  should_detect(<<0:size(32), "ftyp":utf8, "heic":utf8>>, "image/heic")
  should_detect(<<0:size(32), "ftyp":utf8, "M4A ":utf8>>, "audio/mp4")
  should_detect(<<0:size(32), "ftyp":utf8, "qt  ":utf8>>, "video/quicktime")
  should_detect(<<0:size(32), "ftyp":utf8, "isom":utf8>>, "video/mp4")
}

pub fn detect_near_miss_signatures_fall_back_to_default_test() {
  should_fall_back(<<"GIF87b":utf8>>)
  should_fall_back(<<0x50, 0x4B, 0x00, 0x00>>)
  should_fall_back(<<0xFF, 0xD8, 0x00>>)
}

pub fn detect_with_extension_prefers_magic_over_conflicting_extension_test() {
  mimetype.detect_with_extension(
    <<0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A>>,
    "txt",
  )
  |> should.equal("image/png")
}

pub fn detect_with_extension_falls_back_when_magic_is_unknown_test() {
  mimetype.detect_with_extension(<<1, 2, 3, 4>>, "csv")
  |> should.equal("text/csv")
}

pub fn detect_with_extension_falls_back_to_default_for_unknown_extension_test() {
  mimetype.detect_with_extension(<<1, 2, 3, 4>>, "totally-unknown-ext")
  |> should.equal("application/octet-stream")
}

pub fn detect_with_extension_strict_prefers_magic_over_extension_test() {
  mimetype.detect_with_extension_strict(
    <<0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A>>,
    "txt",
  )
  |> should.equal(Ok("image/png"))
}

pub fn detect_with_extension_strict_falls_back_to_extension_test() {
  mimetype.detect_with_extension_strict(<<1, 2, 3, 4>>, "csv")
  |> should.equal(Ok("text/csv"))
}

pub fn detect_with_extension_strict_returns_error_when_both_are_unknown_test() {
  mimetype.detect_with_extension_strict(<<1, 2, 3, 4>>, "totally-unknown-ext")
  |> should.equal(Error(Nil))
}

pub fn detect_with_extension_normalizes_leading_dot_and_case_test() {
  mimetype.detect_with_extension(<<1, 2, 3, 4>>, ".JSON")
  |> should.equal("application/json")
}

pub fn detect_with_extension_uses_extension_for_empty_bytes_test() {
  mimetype.detect_with_extension(<<>>, "pdf")
  |> should.equal("application/pdf")
}

pub fn detect_with_filename_falls_back_when_magic_is_unknown_test() {
  mimetype.detect_with_filename(<<1, 2, 3, 4>>, "report.csv")
  |> should.equal("text/csv")
}

pub fn detect_with_filename_strict_falls_back_to_filename_test() {
  mimetype.detect_with_filename_strict(<<1, 2, 3, 4>>, "report.csv")
  |> should.equal(Ok("text/csv"))
}

pub fn detect_with_filename_strict_returns_error_when_both_are_unknown_test() {
  mimetype.detect_with_filename_strict(<<1, 2, 3, 4>>, "README")
  |> should.equal(Error(Nil))
}

pub fn detect_with_filename_prefers_magic_over_extension_test() {
  mimetype.detect_with_filename(
    <<0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A>>,
    "not-really.txt",
  )
  |> should.equal("image/png")
}

pub fn detect_json_empty_object_test() {
  should_detect(<<"{}":utf8>>, "application/json")
}

pub fn detect_json_empty_array_test() {
  should_detect(<<"[]":utf8>>, "application/json")
}

pub fn detect_json_object_with_nested_array_test() {
  should_detect(<<"{\"a\": 1, \"b\": [true, null]}":utf8>>, "application/json")
}

pub fn detect_json_array_of_numbers_test() {
  should_detect(<<"[1, 2, 3]":utf8>>, "application/json")
}

pub fn detect_json_array_of_strings_test() {
  should_detect(<<"[\"a\", \"b\", \"c\"]":utf8>>, "application/json")
}

pub fn detect_json_with_leading_whitespace_test() {
  should_detect(<<"   \n  {\"a\":1}":utf8>>, "application/json")
}

pub fn detect_json_with_utf8_bom_test() {
  should_detect(<<0xEF, 0xBB, 0xBF, "{\"a\":1}":utf8>>, "application/json")
}

pub fn detect_json_truncated_object_test() {
  should_detect(<<"{\"a\": 1":utf8>>, "application/json")
}

pub fn detect_json_truncated_array_test() {
  should_detect(<<"[1, 2,":utf8>>, "application/json")
}

pub fn detect_json_string_with_escaped_quote_test() {
  should_detect(<<"{\"k\":\"a\\\"b\"}":utf8>>, "application/json")
}

pub fn detect_json_string_with_escaped_backslash_test() {
  should_detect(<<"{\"k\":\"a\\\\b\"}":utf8>>, "application/json")
}

pub fn detect_json_negative_number_test() {
  should_detect(<<"[-1, -2.5, -1e10]":utf8>>, "application/json")
}

pub fn detect_json_nested_object_test() {
  should_detect(<<"{\"a\":{\"b\":{\"c\":1}}}":utf8>>, "application/json")
}

pub fn detect_json_rejects_unquoted_words_test() {
  should_fall_back(<<"{ this is not json }":utf8>>)
}

pub fn detect_json_rejects_plain_text_test() {
  should_fall_back(<<"Hello world":utf8>>)
}

pub fn detect_json_html_input_matches_html_test() {
  should_detect(<<"<html>":utf8>>, "text/html")
}

pub fn detect_json_rejects_bare_number_test() {
  should_fall_back(<<"42":utf8>>)
}

pub fn detect_json_rejects_bare_string_test() {
  should_fall_back(<<"\"foo\"":utf8>>)
}

pub fn detect_json_rejects_bare_true_test() {
  should_fall_back(<<"true":utf8>>)
}

pub fn detect_json_rejects_bom_only_test() {
  should_fall_back(<<0xEF, 0xBB, 0xBF>>)
}

pub fn detect_json_rejects_open_brace_with_garbage_test() {
  should_fall_back(<<"{abc":utf8>>)
}

pub fn detect_json_rejects_object_with_unquoted_key_test() {
  should_fall_back(<<"{key: 1}":utf8>>)
}

pub fn detect_json_rejects_object_missing_colon_test() {
  should_fall_back(<<"{\"key\" 1}":utf8>>)
}

pub fn detect_json_rejects_trailing_comma_in_object_test() {
  should_fall_back(<<"{\"a\":1,}":utf8>>)
}

pub fn detect_json_rejects_trailing_comma_in_array_test() {
  should_fall_back(<<"[1,2,]":utf8>>)
}

pub fn detect_json_strict_returns_ok_test() {
  mimetype.detect_strict(<<"{\"x\":1}":utf8>>)
  |> should.equal(Ok("application/json"))
}

pub fn detect_json_array_of_objects_test() {
  should_detect(<<"[{\"a\":1},{\"b\":2}]":utf8>>, "application/json")
}

pub fn detect_json_object_with_multibyte_utf8_value_test() {
  should_detect(<<"{\"name\":\"日本語\"}":utf8>>, "application/json")
}

pub fn detect_json_rejects_whitespace_only_test() {
  should_fall_back(<<" \n\t\r ":utf8>>)
}

pub fn detect_json_truncated_after_whitespace_test() {
  should_detect(<<"{\"a\":   ":utf8>>, "application/json")
}

pub fn detect_html_doctype_test() {
  should_detect(
    <<"<!DOCTYPE html><html><body></body></html>":utf8>>,
    "text/html",
  )
}

pub fn detect_html_doctype_lowercase_test() {
  should_detect(<<"<!doctype html>":utf8>>, "text/html")
}

pub fn detect_html_uppercase_tag_test() {
  should_detect(<<"<HTML>":utf8>>, "text/html")
}

pub fn detect_html_with_leading_whitespace_test() {
  should_detect(<<"   \n\t<html>":utf8>>, "text/html")
}

pub fn detect_html_with_utf8_bom_test() {
  should_detect(<<0xEF, 0xBB, 0xBF, "<html>":utf8>>, "text/html")
}

pub fn detect_html_head_test() {
  should_detect(<<"<head>":utf8>>, "text/html")
}

pub fn detect_html_body_test() {
  should_detect(<<"<body>":utf8>>, "text/html")
}

pub fn detect_html_script_test() {
  should_detect(<<"<script>":utf8>>, "text/html")
}

pub fn detect_html_div_test() {
  should_detect(<<"<div class=\"x\">":utf8>>, "text/html")
}

pub fn detect_html_short_tag_a_test() {
  should_detect(<<"<a href=\"/\">":utf8>>, "text/html")
}

pub fn detect_html_short_tag_p_test() {
  should_detect(<<"<p>hello":utf8>>, "text/html")
}

pub fn detect_html_truncated_tag_test() {
  should_detect(<<"<html":utf8>>, "text/html")
}

pub fn detect_html_rejects_unknown_tag_test() {
  should_fall_back(<<"<not-a-known-tag>":utf8>>)
}

pub fn detect_html_rejects_space_after_lt_test() {
  should_fall_back(<<"< html>":utf8>>)
}

pub fn detect_html_rejects_address_via_short_a_signature_test() {
  should_fall_back(<<"<address>":utf8>>)
}

pub fn detect_html_rejects_pre_via_short_p_signature_test() {
  should_fall_back(<<"<pre>":utf8>>)
}

pub fn detect_html_rejects_plain_text_test() {
  should_fall_back(<<"Hello world":utf8>>)
}

pub fn detect_xml_declaration_test() {
  should_detect(<<"<?xml version=\"1.0\"?><root/>":utf8>>, "text/xml")
}

pub fn detect_xml_with_encoding_test() {
  should_detect(
    <<"<?xml version=\"1.0\" encoding=\"UTF-8\"?>":utf8>>,
    "text/xml",
  )
}

pub fn detect_xml_with_leading_whitespace_test() {
  should_detect(<<"  \n<?xml ?>":utf8>>, "text/xml")
}

pub fn detect_xml_with_utf8_bom_test() {
  should_detect(
    <<0xEF, 0xBB, 0xBF, "<?xml version=\"1.0\"?>":utf8>>,
    "text/xml",
  )
}

pub fn detect_xml_truncated_test() {
  should_detect(<<"<?xml ":utf8>>, "text/xml")
}

pub fn detect_xml_rejects_uppercase_declaration_test() {
  should_fall_back(<<"<?XML version=\"1.0\"?>":utf8>>)
}

pub fn detect_xml_rejects_processing_instruction_other_than_xml_test() {
  should_fall_back(<<"<?php ?>":utf8>>)
}

pub fn detect_xml_strict_returns_ok_test() {
  mimetype.detect_strict(<<"<?xml version=\"1.0\"?>":utf8>>)
  |> should.equal(Ok("text/xml"))
}

pub fn detect_html_strict_returns_ok_test() {
  mimetype.detect_strict(<<"<!DOCTYPE html>":utf8>>)
  |> should.equal(Ok("text/html"))
}
