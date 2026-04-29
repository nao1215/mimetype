import gleam/bit_array
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

fn stored_mimetype_zip_archive(mime_type: BitArray) -> BitArray {
  let mime_type_size = bit_array.byte_size(mime_type)

  bit_array.concat([
    // Local file header signature
    <<0x50, 0x4B, 0x03, 0x04>>,
    // Version needed (2), flags (2), compression=stored (2)
    <<0x14, 0x00, 0x00, 0x00, 0x00, 0x00>>,
    // Last mod time (2), last mod date (2)
    <<0x00, 0x00, 0x00, 0x00>>,
    // CRC-32 (4)
    <<0x00, 0x00, 0x00, 0x00>>,
    // Compressed size = mime_type_size (4, little-endian)
    <<mime_type_size, 0x00, 0x00, 0x00>>,
    // Uncompressed size = mime_type_size (4, little-endian)
    <<mime_type_size, 0x00, 0x00, 0x00>>,
    // Filename length = 8 (2, little-endian)
    <<0x08, 0x00>>,
    // Extra field length = 0 (2)
    <<0x00, 0x00>>,
    // Filename: "mimetype"
    <<"mimetype":utf8>>,
    mime_type,
  ])
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
  |> should.equal(Error(mimetype.UnknownExtension("totally-unknown-ext")))
}

pub fn extension_to_mime_type_strict_returns_empty_input_for_blank_test() {
  mimetype.extension_to_mime_type_strict("")
  |> should.equal(Error(mimetype.EmptyInput))
}

pub fn extension_to_mime_type_strict_returns_empty_input_for_dot_only_test() {
  mimetype.extension_to_mime_type_strict(".")
  |> should.equal(Error(mimetype.EmptyInput))
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

pub fn extension_to_mime_type_repeated_lookups_are_consistent_test() {
  // Regression for issue #48: the Erlang FFI now caches the lookup tables
  // via persistent_term. Repeated lookups (mixing the same key, different
  // keys, and unknown keys) must keep returning the same answers.
  list.repeat(Nil, 200)
  |> list.each(fn(_) {
    mimetype.extension_to_mime_type(".json")
    |> should.equal("application/json")
    mimetype.extension_to_mime_type(".png")
    |> should.equal("image/png")
    mimetype.extension_to_mime_type("totally-unknown-ext")
    |> should.equal("application/octet-stream")
  })
}

pub fn mime_type_to_extensions_repeated_lookups_are_consistent_test() {
  // Regression for issue #48: matching coverage on the reverse-lookup map.
  list.repeat(Nil, 200)
  |> list.each(fn(_) {
    mimetype.mime_type_to_extensions("image/jpeg")
    |> should.equal(["jpg", "jpeg", "jpe"])
    mimetype.mime_type_to_extensions("application/json")
    |> should.equal(["json", "map"])
    mimetype.mime_type_to_extensions("application/x-not-real")
    |> should.equal([])
  })
}

pub fn essence_strips_parameters_and_normalizes_case_test() {
  mimetype.essence(" TEXT/HTML ; charset=UTF-8 ")
  |> should.equal("text/html")
}

pub fn parameter_matches_case_insensitively_test() {
  mimetype.parameter("text/html; CHARSET=UTF-8; boundary=abc123", "charset")
  |> should.equal(Ok("UTF-8"))
}

pub fn parameter_returns_no_match_for_missing_key_test() {
  mimetype.parameter("text/html; charset=UTF-8", "boundary")
  |> should.equal(Error(mimetype.NoMatch))
}

pub fn parameter_returns_empty_input_for_blank_key_test() {
  mimetype.parameter("text/html; charset=UTF-8", "")
  |> should.equal(Error(mimetype.EmptyInput))
}

pub fn charset_returns_lowercased_value_test() {
  mimetype.charset("text/html; CHARSET=UTF-8")
  |> should.equal(Ok("utf-8"))
}

pub fn charset_returns_no_match_when_missing_test() {
  mimetype.charset("text/html")
  |> should.equal(Error(mimetype.NoMatch))
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

pub fn filename_to_mime_type_strict_returns_empty_input_without_extension_test() {
  mimetype.filename_to_mime_type_strict("README")
  |> should.equal(Error(mimetype.EmptyInput))
}

pub fn filename_to_mime_type_strict_returns_unknown_extension_test() {
  mimetype.filename_to_mime_type_strict("notes.totally-unknown-ext")
  |> should.equal(Error(mimetype.UnknownExtension("totally-unknown-ext")))
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

pub fn detect_strict_returns_empty_input_for_zero_bytes_test() {
  mimetype.detect_strict(<<>>)
  |> should.equal(Error(mimetype.EmptyInput))
}

pub fn detect_strict_returns_no_match_for_unknown_signature_test() {
  // Single 0xFF byte — not empty, but no signature matches and the
  // printable-ASCII fallback rejects it.
  mimetype.detect_strict(<<0xFF>>)
  |> should.equal(Error(mimetype.NoMatch))
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

pub fn detect_epub_test() {
  // EPUB: ZIP with "mimetype" as first entry containing "application/epub+zip"
  // Local file header: PK\x03\x04 + 22 bytes header + filename + data
  let epub = stored_mimetype_zip_archive(<<"application/epub+zip":utf8>>)
  should_detect(epub, "application/epub+zip")
}

pub fn detect_odt_test() {
  let odt =
    stored_mimetype_zip_archive(<<
      "application/vnd.oasis.opendocument.text":utf8,
    >>)
  should_detect(odt, "application/vnd.oasis.opendocument.text")
}

pub fn detect_ods_test() {
  let ods =
    stored_mimetype_zip_archive(<<
      "application/vnd.oasis.opendocument.spreadsheet":utf8,
    >>)
  should_detect(ods, "application/vnd.oasis.opendocument.spreadsheet")
}

pub fn detect_odp_test() {
  let odp =
    stored_mimetype_zip_archive(<<
      "application/vnd.oasis.opendocument.presentation":utf8,
    >>)
  should_detect(odp, "application/vnd.oasis.opendocument.presentation")
}

pub fn detect_docx_test() {
  // DOCX: ZIP with [Content_Types].xml and word/ entry
  let docx =
    bit_array.concat([
      // Entry 1: [Content_Types].xml (stored, 0 bytes data for test)
      <<0x50, 0x4B, 0x03, 0x04>>,
      <<0x14, 0x00, 0x00, 0x00, 0x00, 0x00>>,
      <<0x00, 0x00, 0x00, 0x00>>,
      <<0x00, 0x00, 0x00, 0x00>>,
      <<0x00, 0x00, 0x00, 0x00>>,
      <<0x00, 0x00, 0x00, 0x00>>,
      // Filename length = 19
      <<0x13, 0x00>>,
      <<0x00, 0x00>>,
      <<"[Content_Types].xml":utf8>>,
      // Entry 2: word/document.xml
      <<0x50, 0x4B, 0x03, 0x04>>,
      <<0x14, 0x00, 0x00, 0x00, 0x00, 0x00>>,
      <<0x00, 0x00, 0x00, 0x00>>,
      <<0x00, 0x00, 0x00, 0x00>>,
      <<0x00, 0x00, 0x00, 0x00>>,
      <<0x00, 0x00, 0x00, 0x00>>,
      // Filename length = 17
      <<0x11, 0x00>>,
      <<0x00, 0x00>>,
      <<"word/document.xml":utf8>>,
    ])
  should_detect(
    docx,
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
  )
}

pub fn detect_xlsx_test() {
  // XLSX: ZIP with [Content_Types].xml and xl/ entry
  let xlsx =
    bit_array.concat([
      // Entry 1: [Content_Types].xml
      <<0x50, 0x4B, 0x03, 0x04>>,
      <<0x14, 0x00, 0x00, 0x00, 0x00, 0x00>>,
      <<0x00, 0x00, 0x00, 0x00>>,
      <<0x00, 0x00, 0x00, 0x00>>,
      <<0x00, 0x00, 0x00, 0x00>>,
      <<0x00, 0x00, 0x00, 0x00>>,
      <<0x13, 0x00>>,
      <<0x00, 0x00>>,
      <<"[Content_Types].xml":utf8>>,
      // Entry 2: xl/workbook.xml
      <<0x50, 0x4B, 0x03, 0x04>>,
      <<0x14, 0x00, 0x00, 0x00, 0x00, 0x00>>,
      <<0x00, 0x00, 0x00, 0x00>>,
      <<0x00, 0x00, 0x00, 0x00>>,
      <<0x00, 0x00, 0x00, 0x00>>,
      <<0x00, 0x00, 0x00, 0x00>>,
      // Filename length = 15
      <<0x0F, 0x00>>,
      <<0x00, 0x00>>,
      <<"xl/workbook.xml":utf8>>,
    ])
  should_detect(
    xlsx,
    "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
  )
}

pub fn detect_pptx_test() {
  // PPTX: ZIP with [Content_Types].xml and ppt/ entry
  let pptx =
    bit_array.concat([
      // Entry 1: [Content_Types].xml
      <<0x50, 0x4B, 0x03, 0x04>>,
      <<0x14, 0x00, 0x00, 0x00, 0x00, 0x00>>,
      <<0x00, 0x00, 0x00, 0x00>>,
      <<0x00, 0x00, 0x00, 0x00>>,
      <<0x00, 0x00, 0x00, 0x00>>,
      <<0x00, 0x00, 0x00, 0x00>>,
      <<0x13, 0x00>>,
      <<0x00, 0x00>>,
      <<"[Content_Types].xml":utf8>>,
      // Entry 2: ppt/presentation.xml
      <<0x50, 0x4B, 0x03, 0x04>>,
      <<0x14, 0x00, 0x00, 0x00, 0x00, 0x00>>,
      <<0x00, 0x00, 0x00, 0x00>>,
      <<0x00, 0x00, 0x00, 0x00>>,
      <<0x00, 0x00, 0x00, 0x00>>,
      <<0x00, 0x00, 0x00, 0x00>>,
      // Filename length = 20
      <<0x14, 0x00>>,
      <<0x00, 0x00>>,
      <<"ppt/presentation.xml":utf8>>,
    ])
  should_detect(
    pptx,
    "application/vnd.openxmlformats-officedocument.presentationml.presentation",
  )
}

pub fn detect_jar_test() {
  // JAR: ZIP with META-INF/MANIFEST.MF
  let jar =
    bit_array.concat([
      <<0x50, 0x4B, 0x03, 0x04>>,
      <<0x14, 0x00, 0x00, 0x00, 0x00, 0x00>>,
      <<0x00, 0x00, 0x00, 0x00>>,
      <<0x00, 0x00, 0x00, 0x00>>,
      <<0x00, 0x00, 0x00, 0x00>>,
      <<0x00, 0x00, 0x00, 0x00>>,
      // Filename length = 20
      <<0x14, 0x00>>,
      <<0x00, 0x00>>,
      <<"META-INF/MANIFEST.MF":utf8>>,
    ])
  should_detect(jar, "application/java-archive")
}

pub fn detect_apk_test() {
  // APK: ZIP with AndroidManifest.xml
  let apk =
    bit_array.concat([
      <<0x50, 0x4B, 0x03, 0x04>>,
      <<0x14, 0x00, 0x00, 0x00, 0x00, 0x00>>,
      <<0x00, 0x00, 0x00, 0x00>>,
      <<0x00, 0x00, 0x00, 0x00>>,
      <<0x00, 0x00, 0x00, 0x00>>,
      <<0x00, 0x00, 0x00, 0x00>>,
      // Filename length = 19
      <<0x13, 0x00>>,
      <<0x00, 0x00>>,
      <<"AndroidManifest.xml":utf8>>,
    ])
  should_detect(apk, "application/vnd.android.package-archive")
}

pub fn detect_generic_zip_test() {
  // Plain ZIP with no recognized entries falls back to application/zip
  let zip =
    bit_array.concat([
      <<0x50, 0x4B, 0x03, 0x04>>,
      <<0x14, 0x00, 0x00, 0x00, 0x00, 0x00>>,
      <<0x00, 0x00, 0x00, 0x00>>,
      <<0x00, 0x00, 0x00, 0x00>>,
      <<0x00, 0x00, 0x00, 0x00>>,
      <<0x00, 0x00, 0x00, 0x00>>,
      // Filename length = 8
      <<0x08, 0x00>>,
      <<0x00, 0x00>>,
      <<"test.txt":utf8>>,
    ])
  should_detect(zip, "application/zip")
}

pub fn detect_zip_truncated_to_header_only_test() {
  // Only the 4-byte ZIP header — still recognized as ZIP
  should_detect(<<0x50, 0x4B, 0x03, 0x04>>, "application/zip")
}

pub fn detect_ole_word_test() {
  // CFB header + padding + "WordDocument" in UTF-16LE
  let header = <<0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1>>
  let padding = <<0:size({ 100 * 8 })>>
  let marker = <<
    0x57, 0x00, 0x6F, 0x00, 0x72, 0x00, 0x64, 0x00, 0x44, 0x00, 0x6F, 0x00, 0x63,
    0x00, 0x75, 0x00, 0x6D, 0x00, 0x65, 0x00, 0x6E, 0x00, 0x74, 0x00,
  >>
  let bytes = bit_array.concat([header, padding, marker])
  should_detect(bytes, "application/msword")
}

pub fn detect_ole_excel_workbook_test() {
  // CFB header + padding + "Workbook" in UTF-16LE
  let header = <<0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1>>
  let padding = <<0:size({ 100 * 8 })>>
  let marker = <<
    0x57, 0x00, 0x6F, 0x00, 0x72, 0x00, 0x6B, 0x00, 0x62, 0x00, 0x6F, 0x00, 0x6F,
    0x00, 0x6B, 0x00,
  >>
  let bytes = bit_array.concat([header, padding, marker])
  should_detect(bytes, "application/vnd.ms-excel")
}

pub fn detect_ole_excel_book_test() {
  // CFB header + padding + "Book" in UTF-16LE (older format)
  let header = <<0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1>>
  let padding = <<0:size({ 200 * 8 })>>
  let marker = <<0x42, 0x00, 0x6F, 0x00, 0x6F, 0x00, 0x6B, 0x00>>
  let bytes = bit_array.concat([header, padding, marker])
  should_detect(bytes, "application/vnd.ms-excel")
}

pub fn detect_ole_powerpoint_test() {
  // CFB header + padding + "PowerPoint Document" in UTF-16LE
  let header = <<0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1>>
  let padding = <<0:size({ 100 * 8 })>>
  let marker = <<
    0x50, 0x00, 0x6F, 0x00, 0x77, 0x00, 0x65, 0x00, 0x72, 0x00, 0x50, 0x00, 0x6F,
    0x00, 0x69, 0x00, 0x6E, 0x00, 0x74, 0x00, 0x20, 0x00, 0x44, 0x00, 0x6F, 0x00,
    0x63, 0x00, 0x75, 0x00, 0x6D, 0x00, 0x65, 0x00, 0x6E, 0x00, 0x74, 0x00,
  >>
  let bytes = bit_array.concat([header, padding, marker])
  should_detect(bytes, "application/vnd.ms-powerpoint")
}

pub fn detect_ole_cfb_generic_test() {
  // CFB header only, no recognized stream names
  let header = <<0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1>>
  let padding = <<0:size({ 500 * 8 })>>
  let bytes = bit_array.concat([header, padding])
  should_detect(bytes, "application/x-ole-storage")
}

pub fn detect_ole_truncated_header_falls_back_test() {
  // Less than 8 bytes — should not match CFB
  should_fall_back(<<0xD0, 0xCF, 0x11, 0xE0>>)
}

pub fn detect_ole_word_marker_in_non_cfb_no_match_test() {
  // "WordDocument" marker without CFB header should not match Word
  let non_cfb = <<0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00>>
  let marker = <<
    0x57, 0x00, 0x6F, 0x00, 0x72, 0x00, 0x64, 0x00, 0x44, 0x00, 0x6F, 0x00, 0x63,
    0x00, 0x75, 0x00, 0x6D, 0x00, 0x65, 0x00, 0x6E, 0x00, 0x74, 0x00,
  >>
  let bytes = bit_array.concat([non_cfb, marker])
  mimetype.detect(bytes)
  |> should.not_equal("application/msword")
}

pub fn detect_runtime_and_container_formats_test() {
  should_detect(<<0x00, 0x61, 0x73, 0x6D>>, "application/wasm")
  should_detect(<<0x7F, 0x45, 0x4C, 0x46>>, "application/x-elf")
  should_detect(<<"PAR1":utf8>>, "application/vnd.apache.parquet")
  should_detect(<<"OggS":utf8>>, "application/ogg")
  // WebM/Matroska detection now requires the EBML DocType element, not just
  // the EBML magic — see `detect_webm_test` and `detect_matroska_test`.
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

pub fn detect_single_gif_byte_classified_as_text_test() {
  // After #20, single ASCII byte falls through to the text/plain heuristic.
  mimetype.detect(<<"G":utf8>>)
  |> should.equal("text/plain")
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

pub fn detect_partial_mp4_brand_falls_back_to_default_test() {
  // 11 bytes: ftyp at 4-7 plus only 3 of the 4 brand bytes. The catch-all
  // requires `byte_size >= 12`, so this must not match video/mp4.
  should_fall_back(<<0:size(32), "ftyp":utf8, "abc":utf8>>)
}

pub fn detect_mp4_family_formats_test() {
  should_detect(<<0:size(32), "ftyp":utf8, "avif":utf8>>, "image/avif")
  should_detect(<<0:size(32), "ftyp":utf8, "heic":utf8>>, "image/heic")
  should_detect(<<0:size(32), "ftyp":utf8, "M4A ":utf8>>, "audio/mp4")
  should_detect(<<0:size(32), "ftyp":utf8, "qt  ":utf8>>, "video/quicktime")
  should_detect(<<0:size(32), "ftyp":utf8, "isom":utf8>>, "video/mp4")
}

pub fn detect_mp4_recognizes_extra_iso_bmff_brands_test() {
  // Brands not previously enumerated are now classified as video/mp4 via the
  // ftyp catch-all (issue #49). The brand bytes are arbitrary 4-byte tokens,
  // so brands beyond the well-known set should also resolve to video/mp4.
  should_detect(<<0:size(32), "ftyp":utf8, "M4V ":utf8>>, "video/mp4")
  should_detect(<<0:size(32), "ftyp":utf8, "f4v ":utf8>>, "video/mp4")
  should_detect(<<0:size(32), "ftyp":utf8, "MSNV":utf8>>, "video/mp4")
  should_detect(<<0:size(32), "ftyp":utf8, "NDAS":utf8>>, "video/mp4")
  should_detect(<<0:size(32), "ftyp":utf8, "dash":utf8>>, "video/mp4")
  should_detect(<<0:size(32), "ftyp":utf8, "mp71":utf8>>, "video/mp4")
  should_detect(<<0:size(32), "ftyp":utf8, "XYZQ":utf8>>, "video/mp4")
}

pub fn detect_mp4_specific_brands_take_precedence_over_catch_all_test() {
  // The image/heic, audio/mp4 and video/quicktime brand mappings still win
  // against the ftyp catch-all because the specific signatures are evaluated
  // first.
  should_detect(<<0:size(32), "ftyp":utf8, "heix":utf8>>, "image/heic")
  should_detect(<<0:size(32), "ftyp":utf8, "hevc":utf8>>, "image/heic")
  should_detect(<<0:size(32), "ftyp":utf8, "avis":utf8>>, "image/avif")
  should_detect(<<0:size(32), "ftyp":utf8, "M4B ":utf8>>, "audio/mp4")
  should_detect(<<0:size(32), "ftyp":utf8, "M4P ":utf8>>, "audio/mp4")
}

pub fn detect_near_miss_signatures_fall_back_to_default_test() {
  // ASCII near-miss falls through to text/plain after #20.
  should_detect(<<"GIF87b":utf8>>, "text/plain")
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

pub fn detect_with_extension_strict_returns_no_match_when_both_are_unknown_test() {
  mimetype.detect_with_extension_strict(<<1, 2, 3, 4>>, "totally-unknown-ext")
  |> should.equal(Error(mimetype.NoMatch))
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

pub fn detect_with_filename_strict_returns_no_match_when_both_are_unknown_test() {
  mimetype.detect_with_filename_strict(<<1, 2, 3, 4>>, "README")
  |> should.equal(Error(mimetype.NoMatch))
}

pub fn detect_with_filename_prefers_magic_over_extension_test() {
  mimetype.detect_with_filename(
    <<0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A>>,
    "not-really.txt",
  )
  |> should.equal("image/png")
}

// Regression: issue #58 — printable-ASCII content used to be treated
// as a "matched signature" by `detect_with_filename`, so the filename
// hint was ignored. `text/csv` for `.csv` is the canonical case.
pub fn detect_with_filename_prefers_filename_over_printable_ascii_csv_test() {
  let bytes = <<
    "type,severity,message,occurred_at\nlogin,info,hi,2026-04-28\n":utf8,
  >>
  mimetype.detect_with_filename(bytes, "fixtures.csv")
  |> should.equal("text/csv")
}

pub fn detect_with_filename_prefers_filename_over_printable_ascii_md_test() {
  mimetype.detect_with_filename(<<"# Title\n\nbody\n":utf8>>, "dump.md")
  |> should.equal("text/markdown")
}

pub fn detect_with_filename_falls_back_to_text_plain_when_filename_unknown_test() {
  // Plain ASCII + filename without a known extension: the
  // printable-ASCII heuristic is still the right last resort.
  mimetype.detect_with_filename(<<"plain text\n":utf8>>, "README")
  |> should.equal("text/plain")
}

pub fn detect_with_extension_prefers_extension_over_printable_ascii_csv_test() {
  mimetype.detect_with_extension(<<"a,b,c\n1,2,3\n":utf8>>, "csv")
  |> should.equal("text/csv")
}

pub fn detect_with_extension_strict_prefers_extension_over_printable_ascii_csv_test() {
  mimetype.detect_with_extension_strict(<<"a,b,c\n1,2,3\n":utf8>>, "csv")
  |> should.equal(Ok("text/csv"))
}

pub fn detect_with_extension_falls_back_to_text_plain_when_extension_unknown_test() {
  mimetype.detect_with_extension(<<"plain text\n":utf8>>, "totally-unknown-ext")
  |> should.equal("text/plain")
}

pub fn detect_signature_only_returns_ok_for_binary_signature_test() {
  mimetype.detect_signature_only(<<
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
  >>)
  |> should.equal(Ok("image/png"))
}

pub fn detect_signature_only_returns_ok_for_structural_sniff_test() {
  mimetype.detect_signature_only(<<"{\"x\":1}":utf8>>)
  |> should.equal(Ok("application/json"))
}

pub fn detect_signature_only_returns_ok_for_bom_tagged_text_test() {
  // BOM-tagged text is a real signature, not the printable-ASCII
  // heuristic, so it must still be returned.
  mimetype.detect_signature_only(<<0xEF, 0xBB, 0xBF, "hello":utf8>>)
  |> should.equal(Ok("text/plain; charset=utf-8"))
}

pub fn detect_signature_only_returns_no_match_for_printable_ascii_test() {
  // The whole point of this helper: plain printable ASCII is *not*
  // a signature match here.
  mimetype.detect_signature_only(<<"plain text\n":utf8>>)
  |> should.equal(Error(mimetype.NoMatch))
}

pub fn detect_signature_only_returns_empty_input_for_empty_test() {
  mimetype.detect_signature_only(<<>>)
  |> should.equal(Error(mimetype.EmptyInput))
}

pub fn detect_signature_only_returns_no_match_for_unknown_binary_test() {
  mimetype.detect_signature_only(<<1, 2, 3, 4>>)
  |> should.equal(Error(mimetype.NoMatch))
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
  // JSON detector correctly rejects; falls through to text/plain (ASCII).
  should_detect(<<"{ this is not json }":utf8>>, "text/plain")
}

pub fn detect_json_rejects_plain_text_test() {
  should_detect(<<"Hello world":utf8>>, "text/plain")
}

pub fn detect_json_html_input_matches_html_test() {
  should_detect(<<"<html>":utf8>>, "text/html")
}

pub fn detect_json_rejects_bare_number_test() {
  should_detect(<<"42":utf8>>, "text/plain")
}

pub fn detect_json_rejects_bare_string_test() {
  should_detect(<<"\"foo\"":utf8>>, "text/plain")
}

pub fn detect_json_rejects_bare_true_test() {
  should_detect(<<"true":utf8>>, "text/plain")
}

pub fn detect_json_rejects_bom_only_test() {
  // After #20, a lone UTF-8 BOM is classified as text/plain; charset=utf-8.
  should_detect(<<0xEF, 0xBB, 0xBF>>, "text/plain; charset=utf-8")
}

pub fn detect_json_rejects_open_brace_with_garbage_test() {
  should_detect(<<"{abc":utf8>>, "text/plain")
}

pub fn detect_json_rejects_object_with_unquoted_key_test() {
  should_detect(<<"{key: 1}":utf8>>, "text/plain")
}

pub fn detect_json_rejects_object_missing_colon_test() {
  should_detect(<<"{\"key\" 1}":utf8>>, "text/plain")
}

pub fn detect_json_rejects_trailing_comma_in_object_test() {
  should_detect(<<"{\"a\":1,}":utf8>>, "text/plain")
}

pub fn detect_json_rejects_trailing_comma_in_array_test() {
  should_detect(<<"[1,2,]":utf8>>, "text/plain")
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
  should_detect(<<" \n\t\r ":utf8>>, "text/plain")
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
  should_detect(<<"<not-a-known-tag>":utf8>>, "text/plain")
}

pub fn detect_html_rejects_space_after_lt_test() {
  should_detect(<<"< html>":utf8>>, "text/plain")
}

pub fn detect_html_rejects_address_via_short_a_signature_test() {
  should_detect(<<"<address>":utf8>>, "text/plain")
}

pub fn detect_html_rejects_pre_via_short_p_signature_test() {
  should_detect(<<"<pre>":utf8>>, "text/plain")
}

pub fn detect_html_rejects_plain_text_test() {
  should_detect(<<"Hello world":utf8>>, "text/plain")
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
  should_detect(<<"<?XML version=\"1.0\"?>":utf8>>, "text/plain")
}

pub fn detect_xml_rejects_processing_instruction_other_than_xml_test() {
  should_detect(<<"<?php ?>":utf8>>, "text/plain")
}

pub fn detect_xml_strict_returns_ok_test() {
  mimetype.detect_strict(<<"<?xml version=\"1.0\"?>":utf8>>)
  |> should.equal(Ok("text/xml"))
}

pub fn detect_html_strict_returns_ok_test() {
  mimetype.detect_strict(<<"<!DOCTYPE html>":utf8>>)
  |> should.equal(Ok("text/html"))
}

pub fn detect_svg_root_with_xmlns_test() {
  should_detect(
    <<
      "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"10\" height=\"10\"/>":utf8,
    >>,
    "image/svg+xml",
  )
}

pub fn detect_svg_self_closing_test() {
  should_detect(<<"<svg/>":utf8>>, "image/svg+xml")
}

pub fn detect_svg_after_xml_prolog_test() {
  should_detect(<<"<?xml version=\"1.0\"?><svg></svg>":utf8>>, "image/svg+xml")
}

pub fn detect_svg_after_xml_prolog_and_doctype_test() {
  should_detect(
    <<
      "<?xml version=\"1.0\"?>\n<!DOCTYPE svg PUBLIC \"-//W3C//DTD SVG 1.1//EN\" \"http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd\">\n<svg>":utf8,
    >>,
    "image/svg+xml",
  )
}

pub fn detect_svg_after_comment_test() {
  should_detect(
    <<"<?xml version=\"1.0\"?><!-- some comment --><svg/>":utf8>>,
    "image/svg+xml",
  )
}

pub fn detect_svg_with_utf8_bom_test() {
  should_detect(<<0xEF, 0xBB, 0xBF, "<svg/>":utf8>>, "image/svg+xml")
}

pub fn detect_svg_with_leading_whitespace_test() {
  should_detect(<<"   \n  <svg></svg>":utf8>>, "image/svg+xml")
}

pub fn detect_svg_truncated_root_test() {
  should_detect(<<"<svg":utf8>>, "image/svg+xml")
}

pub fn detect_svg_rejects_uppercase_root_test() {
  // <SVG> is not SVG (XML element names are case-sensitive). After #20 it
  // falls through to text/plain instead of octet-stream.
  should_detect(<<"<SVG>":utf8>>, "text/plain")
}

pub fn detect_svg_rejects_extended_name_test() {
  // <svg-fake> must not match: after <svg, the next byte (-) is not a
  // tag terminator. Falls through to text/plain.
  should_detect(<<"<svg-fake>":utf8>>, "text/plain")
}

pub fn detect_svg_xml_prolog_without_svg_falls_back_to_xml_test() {
  should_detect(<<"<?xml ?><html>":utf8>>, "text/xml")
}

pub fn detect_svg_strict_returns_ok_test() {
  mimetype.detect_strict(<<"<svg/>":utf8>>)
  |> should.equal(Ok("image/svg+xml"))
}

pub fn detect_ttf_test() {
  should_detect(<<0x00, 0x01, 0x00, 0x00>>, "font/ttf")
}

pub fn detect_otf_test() {
  should_detect(<<"OTTO":utf8>>, "font/otf")
}

pub fn detect_ttc_test() {
  should_detect(<<"ttcf":utf8>>, "font/collection")
}

pub fn detect_woff_test() {
  should_detect(<<"wOFF":utf8>>, "font/woff")
}

pub fn detect_woff2_test() {
  should_detect(<<"wOF2":utf8>>, "font/woff2")
}

pub fn detect_eot_test() {
  // EOT signature: "LP" at offset 8, "00 00 01" at offset 34.
  let bytes = <<
    0:size({ 8 * 8 }),
    "LP":utf8,
    0:size({ 24 * 8 }),
    0x00,
    0x00,
    0x01,
  >>
  should_detect(bytes, "application/vnd.ms-fontobject")
}

pub fn detect_eot_strict_returns_ok_test() {
  let bytes = <<
    0:size({ 8 * 8 }),
    "LP":utf8,
    0:size({ 24 * 8 }),
    0x00,
    0x00,
    0x01,
  >>
  mimetype.detect_strict(bytes)
  |> should.equal(Ok("application/vnd.ms-fontobject"))
}

pub fn detect_eot_rejects_missing_offset_34_magic_test() {
  // "LP" at offset 8 alone is not enough — must also have 00 00 01 at 34.
  let bytes = <<0:size({ 8 * 8 }), "LP":utf8, 0:size({ 27 * 8 })>>
  should_fall_back(bytes)
}

pub fn detect_font_strict_returns_ok_for_ttf_test() {
  mimetype.detect_strict(<<0x00, 0x01, 0x00, 0x00>>)
  |> should.equal(Ok("font/ttf"))
}

pub fn detect_psd_test() {
  should_detect(<<0x38, 0x42, 0x50, 0x53>>, "image/vnd.adobe.photoshop")
}

pub fn detect_jp2_test() {
  should_detect(
    <<0x00, 0x00, 0x00, 0x0C, 0x6A, 0x50, 0x20, 0x20, 0x0D, 0x0A, 0x87, 0x0A>>,
    "image/jp2",
  )
}

pub fn detect_jxl_container_test() {
  should_detect(
    <<0x00, 0x00, 0x00, 0x0C, 0x4A, 0x58, 0x4C, 0x20, 0x0D, 0x0A, 0x87, 0x0A>>,
    "image/jxl",
  )
}

pub fn detect_jxl_codestream_test() {
  should_detect(<<0xFF, 0x0A>>, "image/jxl")
}

pub fn detect_dds_test() {
  should_detect(<<"DDS ":utf8>>, "image/vnd.ms-dds")
}

pub fn detect_hdr_radiance_test() {
  should_detect(
    <<"#?RADIANCE":utf8, 0x0A, "GAMMA=1.0":utf8>>,
    "image/vnd.radiance",
  )
}

pub fn detect_exr_test() {
  should_detect(<<0x76, 0x2F, 0x31, 0x01>>, "image/x-exr")
}

pub fn detect_qoi_test() {
  should_detect(<<"qoif":utf8, 0, 0, 0, 0>>, "image/x-qoi")
}

pub fn detect_fits_test() {
  should_detect(<<"SIMPLE  = ":utf8, "T":utf8>>, "image/fits")
}

pub fn detect_image_strict_returns_ok_for_psd_test() {
  mimetype.detect_strict(<<0x38, 0x42, 0x50, 0x53>>)
  |> should.equal(Ok("image/vnd.adobe.photoshop"))
}

pub fn detect_lz4_frame_test() {
  should_detect(<<0x04, 0x22, 0x4D, 0x18>>, "application/x-lz4")
}

pub fn detect_lz4_legacy_test() {
  should_detect(<<0x02, 0x21, 0x4C, 0x18>>, "application/x-lz4")
}

pub fn detect_lzip_test() {
  should_detect(<<"LZIP":utf8>>, "application/x-lzip")
}

pub fn detect_snappy_framed_test() {
  should_detect(
    <<0xFF, 0x06, 0x00, 0x00, 0x73, 0x4E, 0x61, 0x50, 0x70, 0x59>>,
    "application/x-snappy-framed",
  )
}

pub fn detect_compress_test() {
  should_detect(<<0x1F, 0x9D>>, "application/x-compress")
}

pub fn detect_ar_archive_test() {
  should_detect(<<"!<arch>":utf8, 0x0A>>, "application/x-archive")
}

pub fn detect_lzh_method_5_test() {
  // 2 bytes size, `-lh5-`, method byte 5, trailing `-`.
  should_detect(<<0, 0, "-lh5-":utf8>>, "application/x-lzh-compressed")
}

pub fn detect_lzh_method_0_test() {
  should_detect(<<0, 0, "-lh0-":utf8>>, "application/x-lzh-compressed")
}

pub fn detect_zlib_default_compression_test() {
  // 0x78 0x9C is the most common zlib stream prefix (default compression).
  should_detect(<<0x78, 0x9C, 0x00, 0x00>>, "application/x-deflate")
}

pub fn detect_zlib_best_compression_test() {
  should_detect(<<0x78, 0xDA, 0x00, 0x00>>, "application/x-deflate")
}

pub fn detect_zlib_does_not_steal_png_test() {
  // PNG bytes start with 0x89 PNG... — must NOT be detected as zlib even
  // though PNG contains zlib internally. Verifies signature ordering.
  should_detect(<<0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A>>, "image/png")
}

pub fn detect_compression_strict_returns_ok_for_lzip_test() {
  mimetype.detect_strict(<<"LZIP":utf8>>)
  |> should.equal(Ok("application/x-lzip"))
}

pub fn detect_aac_adts_test() {
  // ADTS sync: 0xFF then 0xF0/F1/F8/F9.
  should_detect(<<0xFF, 0xF1, 0x00, 0x00>>, "audio/aac")
}

pub fn detect_aac_adif_test() {
  should_detect(<<"ADIF":utf8>>, "audio/aac")
}

pub fn detect_amr_test() {
  should_detect(<<"#!AMR":utf8, 0x0A, 0x00, 0x00>>, "audio/amr")
}

pub fn detect_amr_wb_test() {
  should_detect(<<"#!AMR-WB":utf8, 0x0A, 0x00, 0x00>>, "audio/amr-wb")
}

pub fn detect_ac3_test() {
  should_detect(<<0x0B, 0x77, 0x00, 0x00>>, "audio/ac3")
}

pub fn detect_asf_test() {
  should_detect(
    <<
      0x30, 0x26, 0xB2, 0x75, 0x8E, 0x66, 0xCF, 0x11, 0xA6, 0xD9, 0x00, 0xAA,
      0x00, 0x62, 0xCE, 0x6C,
    >>,
    "application/vnd.ms-asf",
  )
}

pub fn detect_flv_test() {
  should_detect(<<"FLV":utf8, 0x01, 0x05>>, "video/x-flv")
}

pub fn detect_matroska_test() {
  // EBML magic + DocType element (0x4282) + length 0x88 + "matroska".
  let bytes = <<
    0x1A, 0x45, 0xDF, 0xA3, 0x9F, 0x42, 0x86, 0x81, 0x01, 0x42, 0xF7, 0x81, 0x01,
    0x42, 0x82, 0x88, "matroska":utf8,
  >>
  should_detect(bytes, "video/x-matroska")
}

pub fn detect_webm_test() {
  // EBML magic + DocType element (0x4282) + length 0x84 + "webm".
  let bytes = <<
    0x1A, 0x45, 0xDF, 0xA3, 0x9F, 0x42, 0x86, 0x81, 0x01, 0x42, 0xF7, 0x81, 0x01,
    0x42, 0x82, 0x84, "webm":utf8,
  >>
  should_detect(bytes, "video/webm")
}

pub fn detect_ebml_without_doctype_falls_back_test() {
  // EBML magic alone (no matroska/webm DocType in budget) → falls back.
  should_fall_back(<<0x1A, 0x45, 0xDF, 0xA3, 0x9F, 0x42, 0x86, 0x81, 0x01>>)
}

pub fn detect_av_strict_returns_ok_for_amr_test() {
  mimetype.detect_strict(<<"#!AMR":utf8, 0x0A>>)
  |> should.equal(Ok("audio/amr"))
}

pub fn detect_text_plain_utf8_bom_test() {
  should_detect(
    <<0xEF, 0xBB, 0xBF, "Hello world":utf8>>,
    "text/plain; charset=utf-8",
  )
}

pub fn detect_text_plain_utf16le_bom_test() {
  should_detect(
    <<0xFF, 0xFE, "H":utf8, 0x00, "i":utf8, 0x00>>,
    "text/plain; charset=utf-16le",
  )
}

pub fn detect_text_plain_utf16be_bom_test() {
  should_detect(
    <<0xFE, 0xFF, 0x00, "H":utf8, 0x00, "i":utf8>>,
    "text/plain; charset=utf-16be",
  )
}

pub fn detect_text_plain_utf32le_bom_test() {
  should_detect(
    <<0xFF, 0xFE, 0x00, 0x00, "H":utf8, 0x00, 0x00, 0x00>>,
    "text/plain; charset=utf-32le",
  )
}

pub fn detect_text_plain_utf32be_bom_test() {
  should_detect(
    <<0x00, 0x00, 0xFE, 0xFF, 0x00, 0x00, 0x00, "H":utf8>>,
    "text/plain; charset=utf-32be",
  )
}

pub fn detect_text_plain_ascii_only_test() {
  should_detect(<<"Hello world\n":utf8>>, "text/plain")
}

pub fn detect_text_plain_config_style_test() {
  should_detect(<<"key=value\n# comment\n":utf8>>, "text/plain")
}

pub fn detect_text_plain_with_tabs_and_crlf_test() {
  should_detect(<<"a\tb\r\nc\td\r\n":utf8>>, "text/plain")
}

pub fn detect_text_plain_rejects_binary_with_nul_test() {
  should_fall_back(<<0x00, 0x01, 0x02, 0x03>>)
}

pub fn detect_text_plain_rejects_binary_with_high_byte_test() {
  // High byte (0x80+) without BOM = binary, not text/plain. JSON/HTML/etc.
  // would already not match, so this verifies the heuristic falls through.
  should_fall_back(<<"hello":utf8, 0xC3>>)
}

pub fn detect_text_plain_rejects_empty_test() {
  // Empty stays at default; the text/plain heuristic must not catch empty.
  mimetype.detect(<<>>)
  |> should.equal("application/octet-stream")
}

pub fn detect_text_plain_does_not_steal_png_test() {
  // PNG bytes start with 0x89 (binary) so the text heuristic must not fire.
  should_detect(<<0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A>>, "image/png")
}

pub fn detect_text_plain_does_not_steal_json_test() {
  // JSON content classified as application/json, not text/plain, even though
  // it's all printable ASCII. Verifies signature ordering (JSON before text).
  should_detect(<<"{\"x\":1}":utf8>>, "application/json")
}

pub fn detect_text_plain_strict_returns_ok_test() {
  mimetype.detect_strict(<<"plain text":utf8>>)
  |> should.equal(Ok("text/plain"))
}

pub fn detect_with_limit_png_within_limit_test() {
  // PNG signature is 8 bytes; a limit of exactly 8 must match.
  mimetype.detect_with_limit(
    <<0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A>>,
    8,
  )
  |> should.equal("image/png")
}

pub fn detect_with_limit_tar_below_offset_test() {
  // TAR `ustar` magic sits at offset 257; a limit of 256 must cut it off.
  let bytes = <<0:size({ 257 * 8 }), 0x75, 0x73, 0x74, 0x61, 0x72, 0:size(64)>>
  mimetype.detect_with_limit(bytes, 256)
  |> should.equal("application/octet-stream")
}

pub fn detect_with_limit_tar_above_offset_test() {
  let bytes = <<0:size({ 257 * 8 }), 0x75, 0x73, 0x74, 0x61, 0x72, 0:size(64)>>
  mimetype.detect_with_limit(bytes, 512)
  |> should.equal("application/x-tar")
}

pub fn detect_with_limit_zip_within_4_bytes_test() {
  // ZIP local file header `50 4B 03 04` fits in 4 bytes.
  mimetype.detect_with_limit(<<0x50, 0x4B, 0x03, 0x04, 20, 0, 0, 0>>, 4)
  |> should.equal("application/zip")
}

pub fn detect_with_limit_empty_bytes_test() {
  mimetype.detect_with_limit(<<>>, 1024)
  |> should.equal("application/octet-stream")
}

pub fn detect_with_limit_zero_test() {
  mimetype.detect_with_limit(
    <<0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A>>,
    0,
  )
  |> should.equal("application/octet-stream")
}

pub fn detect_with_limit_negative_treated_as_zero_test() {
  mimetype.detect_with_limit(
    <<0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A>>,
    -1,
  )
  |> should.equal("application/octet-stream")
}

pub fn detect_with_limit_default_matches_detect_test() {
  // detect/1 must agree with detect_with_limit using the default cap on
  // every existing fixture.
  let png = <<0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A>>
  let json = <<"{\"x\":1}":utf8>>
  let text = <<"hello":utf8>>
  mimetype.detect(png)
  |> should.equal(mimetype.detect_with_limit(
    png,
    mimetype.default_detection_limit,
  ))
  mimetype.detect(json)
  |> should.equal(mimetype.detect_with_limit(
    json,
    mimetype.default_detection_limit,
  ))
  mimetype.detect(text)
  |> should.equal(mimetype.detect_with_limit(
    text,
    mimetype.default_detection_limit,
  ))
}

pub fn detect_with_limit_strict_returns_ok_test() {
  mimetype.detect_with_limit_strict(
    <<0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A>>,
    8,
  )
  |> should.equal(Ok("image/png"))
}

pub fn detect_with_limit_strict_returns_no_match_when_below_offset_test() {
  let bytes = <<0:size({ 257 * 8 }), 0x75, 0x73, 0x74, 0x61, 0x72, 0:size(64)>>
  mimetype.detect_with_limit_strict(bytes, 100)
  |> should.equal(Error(mimetype.NoMatch))
}

pub fn detect_reader_returns_same_as_detect_test() {
  let png = <<0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A>>
  let reader = fn(_limit) { Ok(png) }
  mimetype.detect_reader(reader, 3072)
  |> should.equal("image/png")
}

pub fn detect_reader_truncated_prefix_falls_back_test() {
  // TAR signature at offset 257 — only 64 bytes provided
  let short_bytes = <<0:size({ 64 * 8 })>>
  let reader = fn(_limit) { Ok(short_bytes) }
  mimetype.detect_reader(reader, 3072)
  |> should.equal("application/octet-stream")
}

pub fn detect_reader_short_eof_still_detects_test() {
  // Reader returns fewer bytes than limit but contains a valid PNG signature
  let png = <<0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A>>
  let reader = fn(_limit) { Ok(png) }
  mimetype.detect_reader(reader, 8192)
  |> should.equal("image/png")
}

pub fn detect_reader_strict_error_preserves_reader_error_test() {
  let reader = fn(_limit) { Error("disk read failure") }
  mimetype.detect_reader_strict(reader, 3072)
  |> should.equal(Error(mimetype.ReaderError("disk read failure")))
}

pub fn detect_reader_error_returns_default_test() {
  let reader = fn(_limit) { Error("io error") }
  mimetype.detect_reader(reader, 3072)
  |> should.equal("application/octet-stream")
}

pub fn detect_reader_called_with_limit_test() {
  // Verify reader receives the limit value
  let reader = fn(requested) {
    case requested {
      100 -> Ok(<<0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A>>)
      _ -> Error("unexpected limit")
    }
  }
  mimetype.detect_reader(reader, 100)
  |> should.equal("image/png")
}

pub fn detect_reader_strict_ok_test() {
  let png = <<0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A>>
  let reader = fn(_limit) { Ok(png) }
  mimetype.detect_reader_strict(reader, 3072)
  |> should.equal(Ok("image/png"))
}

pub fn detect_reader_strict_no_match_returns_no_match_test() {
  let unknown = <<0x00, 0x01, 0x02, 0x03>>
  let reader: fn(Int) -> Result(BitArray, String) = fn(_limit) { Ok(unknown) }
  mimetype.detect_reader_strict(reader, 3072)
  |> should.equal(Error(mimetype.NoMatch))
}

pub fn is_a_reflexive_test() {
  mimetype.is_a("application/zip", "application/zip")
  |> should.equal(True)
}

pub fn is_a_docx_inherits_from_zip_test() {
  mimetype.is_a(
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    "application/zip",
  )
  |> should.equal(True)
}

pub fn is_a_svg_inherits_from_xml_test() {
  mimetype.is_a("image/svg+xml", "text/xml")
  |> should.equal(True)
}

pub fn is_a_unrelated_returns_false_test() {
  mimetype.is_a("image/png", "application/zip")
  |> should.equal(False)
}

pub fn is_a_normalizes_essence_test() {
  // Parameters and case differences are stripped before comparison.
  mimetype.is_a("APPLICATION/ZIP; charset=utf-8", "application/zip")
  |> should.equal(True)
}

pub fn is_a_empty_returns_false_test() {
  mimetype.is_a("", "application/zip")
  |> should.equal(False)
  mimetype.is_a("application/zip", "")
  |> should.equal(False)
}

pub fn is_zip_based_apk_test() {
  mimetype.is_zip_based("application/vnd.android.package-archive")
  |> should.equal(True)
}

pub fn is_zip_based_jar_test() {
  mimetype.is_zip_based("application/java-archive")
  |> should.equal(True)
}

pub fn is_zip_based_epub_test() {
  mimetype.is_zip_based("application/epub+zip")
  |> should.equal(True)
}

pub fn is_zip_based_zip_itself_test() {
  mimetype.is_zip_based("application/zip")
  |> should.equal(True)
}

pub fn is_zip_based_png_test() {
  mimetype.is_zip_based("image/png")
  |> should.equal(False)
}

pub fn is_xml_based_svg_test() {
  mimetype.is_xml_based("image/svg+xml")
  |> should.equal(True)
}

pub fn is_xml_based_text_xml_test() {
  mimetype.is_xml_based("text/xml")
  |> should.equal(True)
}

pub fn is_xml_based_application_xml_test() {
  mimetype.is_xml_based("application/xml")
  |> should.equal(True)
}

pub fn is_xml_based_html_test() {
  // HTML is sniffable but is not XML; it is not a child of text/xml.
  mimetype.is_xml_based("text/html")
  |> should.equal(False)
}

pub fn ancestors_epub_test() {
  mimetype.ancestors("application/epub+zip")
  |> should.equal(["application/zip"])
}

pub fn ancestors_root_returns_empty_test() {
  mimetype.ancestors("application/octet-stream")
  |> should.equal([])
}

pub fn ancestors_unknown_mime_returns_empty_test() {
  mimetype.ancestors("application/x-not-real")
  |> should.equal([])
}

pub fn ancestors_msword_inherits_from_ole_test() {
  mimetype.ancestors("application/msword")
  |> should.equal(["application/x-ole-storage"])
}

pub fn ancestors_empty_input_returns_empty_test() {
  mimetype.ancestors("")
  |> should.equal([])
}

pub fn charset_of_html_meta_charset_test() {
  mimetype.charset_of(<<
    "<html><head><meta charset=\"utf-8\"></head></html>":utf8,
  >>)
  |> should.equal(Ok("utf-8"))
}

pub fn charset_of_html_meta_charset_uppercase_test() {
  mimetype.charset_of(<<
    "<html><head><meta charset=\"Shift_JIS\"></head></html>":utf8,
  >>)
  |> should.equal(Ok("shift_jis"))
}

pub fn charset_of_html_http_equiv_content_charset_test() {
  mimetype.charset_of(<<
    "<html><head><meta http-equiv=\"Content-Type\" content=\"text/html; charset=Shift_JIS\"></head></html>":utf8,
  >>)
  |> should.equal(Ok("shift_jis"))
}

pub fn charset_of_xml_encoding_test() {
  mimetype.charset_of(<<
    "<?xml version=\"1.0\" encoding=\"UTF-8\"?><root/>":utf8,
  >>)
  |> should.equal(Ok("utf-8"))
}

pub fn charset_of_utf8_bom_wins_over_meta_test() {
  mimetype.charset_of(<<
    0xEF, 0xBB, 0xBF, "<html><meta charset=\"latin1\"></html>":utf8,
  >>)
  |> should.equal(Ok("utf-8"))
}

pub fn charset_of_pure_ascii_test() {
  mimetype.charset_of(<<"Hello world\n":utf8>>)
  |> should.equal(Ok("us-ascii"))
}

pub fn charset_of_valid_utf8_multibyte_test() {
  mimetype.charset_of(<<"こんにちは":utf8>>)
  |> should.equal(Ok("utf-8"))
}

pub fn charset_of_html_with_utf8_body_no_meta_test() {
  mimetype.charset_of(<<"<html><body>こんにちは</body></html>":utf8>>)
  |> should.equal(Ok("utf-8"))
}

pub fn charset_of_invalid_utf8_returns_no_match_test() {
  // 0xC0 0x20 — invalid UTF-8 (0xC0 is an over-long encoding lead byte that
  // cannot be followed by 0x20 in valid UTF-8).
  mimetype.charset_of(<<0x48, 0x69, 0xC0, 0x20>>)
  |> should.equal(Error(mimetype.NoMatch))
}

pub fn charset_of_empty_returns_empty_input_test() {
  mimetype.charset_of(<<>>)
  |> should.equal(Error(mimetype.EmptyInput))
}

pub fn charset_of_truncated_meta_does_not_false_positive_test() {
  // <meta charset="u — incomplete attribute, no closing quote. The
  // quoted-value reader can't find the closing quote, but all-ASCII
  // input still falls through to us-ascii via the UTF-8 fallback.
  mimetype.charset_of(<<"<meta charset=\"u":utf8>>)
  |> should.equal(Ok("us-ascii"))
}

pub fn charset_of_utf16_le_bom_test() {
  mimetype.charset_of(<<0xFF, 0xFE, 0x48, 0x00, 0x69, 0x00>>)
  |> should.equal(Ok("utf-16le"))
}

pub fn charset_of_utf16_be_bom_test() {
  mimetype.charset_of(<<0xFE, 0xFF, 0x00, 0x48, 0x00, 0x69>>)
  |> should.equal(Ok("utf-16be"))
}

pub fn charset_of_utf32_le_bom_test() {
  mimetype.charset_of(<<0xFF, 0xFE, 0x00, 0x00, 0x48, 0x00, 0x00, 0x00>>)
  |> should.equal(Ok("utf-32le"))
}

pub fn charset_of_utf32_be_bom_test() {
  mimetype.charset_of(<<0x00, 0x00, 0xFE, 0xFF, 0x00, 0x00, 0x00, 0x48>>)
  |> should.equal(Ok("utf-32be"))
}
