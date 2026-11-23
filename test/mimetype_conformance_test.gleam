//// Detection, extension and charset results checked against the format
//// specifications and the IANA media type registry. Each case came from
//// comparing `mimetype` with Go's `gabriel-vasile/mimetype`, libmagic
//// (`file --mime-type`) and Python's `mimetypes`.

import gleam/bit_array
import gleam/list
import gleam/result
import gleam/string
import mimetype

fn mt(s: String) -> mimetype.MimeType {
  let assert Ok(value) = mimetype.parse(s)
  value
}

fn detected(bytes: BitArray) -> Result(String, Nil) {
  mimetype.detect(bytes) |> result.map(mimetype.to_string)
}

fn by_extension(extension: String) -> Result(String, Nil) {
  mimetype.extension_to_mime_type(extension) |> result.map(mimetype.to_string)
}

fn ascii(count: Int) -> BitArray {
  bit_array.from_string(string.repeat("a", count))
}

fn ftyp(brand: String) -> BitArray {
  <<0x00, 0x00, 0x00, 0x18, "ftyp":utf8, brand:utf8, 0, 0, 0, 0>>
}

// ---------------------------------------------------------------------------
// Text
// ---------------------------------------------------------------------------

// WHATWG MIME Sniffing: only the binary data bytes (0x00-0x08, 0x0B,
// 0x0E-0x1A, 0x1C-0x1F) make a resource binary. Bytes at or above 0x80
// do not.
pub fn utf8_text_is_text_plain_test() {
  assert detected(<<"こんにちは\n":utf8>>) == Ok("text/plain")
  assert detected(<<"café crème\n":utf8>>) == Ok("text/plain")
}

pub fn latin1_text_is_text_plain_test() {
  assert detected(<<"caf":utf8, 0xE9, "\n":utf8>>) == Ok("text/plain")
}

pub fn escape_and_delete_bytes_are_text_test() {
  assert detected(<<"a":utf8, 0x1B, "[0m":utf8, 0x7F>>) == Ok("text/plain")
}

pub fn binary_data_bytes_are_not_text_test() {
  list.each([0x00, 0x08, 0x0B, 0x0E, 0x1A, 0x1C, 0x1F], fn(byte) {
    assert detected(<<"ab":utf8, byte, "cd":utf8>>) == Error(Nil)
  })
}

// Detection reads 3072 bytes, so a binary byte anywhere in them counts.
pub fn binary_byte_after_the_first_kilobyte_is_seen_test() {
  assert detected(<<ascii(1500):bits, 0x00>>) == Error(Nil)
  assert detected(<<ascii(3071):bits, 0x00>>) == Error(Nil)
}

pub fn binary_byte_after_3072_bytes_is_ignored_test() {
  assert detected(<<ascii(3072):bits, 0x00>>) == Ok("text/plain")
}

// ---------------------------------------------------------------------------
// JSON
// ---------------------------------------------------------------------------

// RFC 8259: JSON-text = ws value ws. Text after a complete value is not
// JSON.
pub fn json_value_followed_by_text_is_not_json_test() {
  assert detected(<<"[1] first item\n[2] second item\n":utf8>>)
    == Ok("text/plain")
  assert detected(<<"{\"a\": 1} trailing":utf8>>) == Ok("text/plain")
}

pub fn json_value_followed_by_whitespace_is_json_test() {
  assert detected(<<"{\"a\": 1}\n\n":utf8>>) == Ok("application/json")
  assert detected(<<"[1, 2]  \r\n":utf8>>) == Ok("application/json")
}

pub fn json_cut_at_the_detection_limit_is_json_test() {
  let body = bit_array.from_string(string.repeat("1,", 1600))
  assert detected(<<"[":utf8, body:bits>>) == Ok("application/json")
}

// ---------------------------------------------------------------------------
// HTML
// ---------------------------------------------------------------------------

// WHATWG MIME Sniffing lists `<!--` and `<B` among the HTML patterns.
pub fn html_comment_and_b_tag_are_html_test() {
  assert detected(<<"<!-- page --><html><body></body></html>":utf8>>)
    == Ok("text/html")
  assert detected(<<"<b>bold</b>":utf8>>) == Ok("text/html")
}

// Each WHATWG HTML pattern ends with a tag-terminating byte, so the
// input has to contain one.
pub fn html_tag_without_a_terminating_byte_is_not_html_test() {
  assert detected(<<"<a":utf8>>) == Ok("text/plain")
  assert detected(<<"<p":utf8>>) == Ok("text/plain")
  assert detected(<<"<!doctype html":utf8>>) == Ok("text/plain")
}

// ---------------------------------------------------------------------------
// ISO base media file format brands
// ---------------------------------------------------------------------------

// ISO/IEC 23008-12 and the IANA registrations of image/heic,
// image/heic-sequence, image/heif and image/heif-sequence.
pub fn heif_brands_test() {
  assert detected(ftyp("heic")) == Ok("image/heic")
  assert detected(ftyp("heix")) == Ok("image/heic")
  assert detected(ftyp("hevc")) == Ok("image/heic-sequence")
  assert detected(ftyp("hevx")) == Ok("image/heic-sequence")
  assert detected(ftyp("mif1")) == Ok("image/heif")
  assert detected(ftyp("msf1")) == Ok("image/heif-sequence")
}

// RFC 3839 (video/3gpp) and RFC 4393 (video/3gpp2).
pub fn three_gpp_brands_test() {
  assert detected(ftyp("3gp4")) == Ok("video/3gpp")
  assert detected(ftyp("3gp6")) == Ok("video/3gpp")
  assert detected(ftyp("3g2a")) == Ok("video/3gpp2")
}

pub fn audio_only_mp4_brands_test() {
  assert detected(ftyp("NDAS")) == Ok("audio/mp4")
  assert detected(ftyp("F4A ")) == Ok("audio/mp4")
  assert detected(ftyp("F4B ")) == Ok("audio/mp4")
}

// ---------------------------------------------------------------------------
// Registered names
// ---------------------------------------------------------------------------

// Each of these formats has a type in the IANA registry, and the
// extension table already uses it.
pub fn detection_uses_registered_types_test() {
  assert detected(<<0x78, 0x9C, 0x00, 0x00>>) == Ok("application/zlib")
  assert detected(<<0x00, 0x00, 0x01, 0x00, 0x01, 0x00>>)
    == Ok("image/vnd.microsoft.icon")
  assert detected(<<"Rar!":utf8, 0x1A, 0x07, 0x00>>)
    == Ok("application/vnd.rar")
  assert detected(<<"Rar!":utf8, 0x1A, 0x07, 0x01, 0x00>>)
    == Ok("application/vnd.rar")
  assert detected(<<"<?xml version=\"1.0\"?><a/>":utf8>>)
    == Ok("application/xml")
  assert detected(<<0x1A, 0x45, 0xDF, 0xA3, 0x42, 0x82, 0x88, "matroska":utf8>>)
    == Ok("video/matroska")
}

// Cursor files share the icon layout but are not icons.
pub fn cursor_keeps_x_icon_test() {
  assert detected(<<0x00, 0x00, 0x02, 0x00, 0x01, 0x00>>) == Ok("image/x-icon")
}

// No registered type exists for AIFF; the extension table and libmagic
// use audio/x-aiff.
pub fn aiff_matches_the_extension_table_test() {
  assert detected(<<"FORM":utf8, 0, 0, 0, 0, "AIFF":utf8>>)
    == Ok("audio/x-aiff")
}

// RFC 2045 / 2046 register application/postscript, and WHATWG MIME
// Sniffing lists `%!PS-Adobe-`.
pub fn postscript_test() {
  assert detected(<<"%!PS-Adobe-3.0\n":utf8>>) == Ok("application/postscript")
}

// ---------------------------------------------------------------------------
// Short signatures that also start ordinary text
// ---------------------------------------------------------------------------

// BITMAPFILEHEADER: bfReserved1 and bfReserved2 (bytes 6 to 9) must be 0.
pub fn bmp_requires_zero_reserved_bytes_test() {
  assert detected(<<"BMW is a car maker\n":utf8>>) == Ok("text/plain")
  assert detected(<<"BM":utf8, 0x3E, 0, 0, 0, 0, 0, 0, 0, 0x36, 0, 0, 0>>)
    == Ok("image/bmp")
}

// MS-CAB CFHEADER: reserved1 (bytes 4 to 7) must be 0.
pub fn cab_requires_zero_reserved_bytes_test() {
  assert detected(<<"MSCF is a cabinet\n":utf8>>) == Ok("text/plain")
  assert detected(<<"MSCF":utf8, 0, 0, 0, 0, 0x2C, 0, 0, 0>>)
    == Ok("application/vnd.ms-cab-compressed")
}

// ID3v2: "ID3" is followed by the major version 2, 3 or 4.
pub fn id3_requires_a_version_byte_test() {
  assert detected(<<"ID3 tags\n":utf8>>) == Ok("text/plain")
  assert detected(<<"ID3":utf8, 0x03, 0x00, 0x00, 0, 0, 0, 0>>)
    == Ok("audio/mpeg")
  assert detected(<<"ID3":utf8, 0x04, 0x00, 0x00, 0, 0, 0, 0>>)
    == Ok("audio/mpeg")
}

// ---------------------------------------------------------------------------
// Extensions
// ---------------------------------------------------------------------------

pub fn extension_uses_registered_types_test() {
  // RFC 9639, RFC 9559, RFC 9512.
  assert by_extension("flac") == Ok("audio/flac")
  assert by_extension("mkv") == Ok("video/matroska")
  assert by_extension("yaml") == Ok("application/yaml")
  assert by_extension("yml") == Ok("application/yaml")
  assert by_extension("deb") == Ok("application/vnd.debian.binary-package")
  assert by_extension("udeb") == Ok("application/vnd.debian.binary-package")
  assert by_extension("asf") == Ok("application/vnd.ms-asf")
}

// No registered type exists for WAV. Detection reports audio/wav, so the
// extension table does too.
pub fn wav_extension_matches_detection_test() {
  assert by_extension("wav") == Ok("audio/wav")
}

// Every type that detection can report has an extension, and that
// extension looks the type up again. The exceptions have no usual
// extension, or share it with a narrower registered type.
pub fn detected_types_have_extensions_test() {
  let no_extension = [
    "application/x-elf", "application/x-ole-storage", "application/zlib",
  ]
  let shared_extension = [
    // .exr is registered as image/aces, an OpenEXR subset.
    "image/x-exr",
    // .ico is image/vnd.microsoft.icon.
    "image/x-icon",
  ]
  detectable_types()
  |> list.filter(fn(essence) { !list.contains(no_extension, essence) })
  |> list.each(fn(essence) {
    let assert [first, ..] = mimetype.mime_type_to_extensions(mt(essence))
      as essence
    assert list.contains(shared_extension, essence)
      || by_extension(first) == Ok(essence)
      as essence
  })
  list.each(no_extension, fn(essence) {
    assert mimetype.mime_type_to_extensions(mt(essence)) == [] as essence
  })
}

fn detectable_types() -> List(String) {
  [
    "application/epub+zip", "application/gzip", "application/java-archive",
    "application/json", "application/msword", "application/ogg",
    "application/pdf", "application/postscript", "application/rtf",
    "application/vnd.android.package-archive", "application/vnd.apache.parquet",
    "application/vnd.ms-asf", "application/vnd.ms-cab-compressed",
    "application/vnd.ms-excel", "application/vnd.ms-fontobject",
    "application/vnd.ms-powerpoint",
    "application/vnd.oasis.opendocument.presentation",
    "application/vnd.oasis.opendocument.spreadsheet",
    "application/vnd.oasis.opendocument.text",
    "application/vnd.openxmlformats-officedocument.presentationml.presentation",
    "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    "application/vnd.rar", "application/vnd.sqlite3", "application/wasm",
    "application/x-7z-compressed", "application/x-archive",
    "application/x-bzip2", "application/x-compress", "application/x-elf",
    "application/x-lz4", "application/x-lzh-compressed", "application/x-lzip",
    "application/x-ole-storage", "application/x-snappy-framed",
    "application/x-tar", "application/x-xz", "application/xml",
    "application/zip", "application/zlib", "application/zstd", "audio/aac",
    "audio/ac3", "audio/amr", "audio/amr-wb", "audio/flac", "audio/midi",
    "audio/mp4", "audio/mpeg", "audio/wav", "audio/x-aiff", "font/collection",
    "font/otf", "font/ttf", "font/woff", "font/woff2", "image/avif", "image/bmp",
    "image/fits", "image/gif", "image/heic", "image/heic-sequence", "image/heif",
    "image/heif-sequence", "image/jp2", "image/jpeg", "image/jxl", "image/png",
    "image/svg+xml", "image/tiff", "image/vnd.adobe.photoshop",
    "image/vnd.microsoft.icon", "image/vnd.ms-dds", "image/vnd.radiance",
    "image/webp", "image/x-exr", "image/x-icon", "image/x-qoi", "text/html",
    "text/plain", "video/3gpp", "video/3gpp2", "video/matroska", "video/mp4",
    "video/quicktime", "video/webm", "video/x-flv", "video/x-msvideo",
  ]
}

// ---------------------------------------------------------------------------
// XML hierarchy
// ---------------------------------------------------------------------------

// RFC 7303 defines text/xml as an alias of application/xml, and every
// `+xml` type as XML.
pub fn text_xml_is_application_xml_test() {
  let xml = mt("application/xml")
  assert mimetype.is_a(mt("text/xml"), xml)
  assert mimetype.is_a(mt("image/svg+xml"), xml)
  assert mimetype.is_a(mt("application/atom+xml"), xml)
  assert mimetype.ancestors(mt("image/svg+xml")) == [xml]
  assert mimetype.ancestors(mt("text/xml")) == [xml]
}

// ---------------------------------------------------------------------------
// Charset
// ---------------------------------------------------------------------------

// The declaration matters most when the document is not UTF-8.
pub fn xml_declaration_in_a_shift_jis_document_test() {
  let body = <<0x93, 0xFA, 0x96, 0x7B>>
  let doc = <<
    "<?xml version=\"1.0\" encoding=\"Shift_JIS\"?><a>":utf8,
    body:bits,
    "</a>":utf8,
  >>
  assert mimetype.detect_charset(doc) == Ok("shift_jis")
}

pub fn html_meta_charset_in_a_latin1_document_test() {
  let doc = <<
    "<html><head><meta charset=\"ISO-8859-1\"></head><body>caf":utf8, 0xE9,
    "</body></html>":utf8,
  >>
  assert mimetype.detect_charset(doc) == Ok("iso-8859-1")
}

pub fn xml_declaration_after_a_cut_multibyte_character_test() {
  // The 1024th byte falls inside a three-byte character.
  let body = bit_array.from_string(string.repeat("日", 400))
  let doc = <<"<?xml version=\"1.0\" encoding=\"EUC-JP\"?><a>":utf8, body:bits>>
  assert mimetype.detect_charset(doc) == Ok("euc-jp")
}

pub fn empty_declared_charset_is_ignored_test() {
  assert mimetype.detect_charset(<<
      "<?xml version=\"1.0\" encoding=\"\"?><a/>":utf8,
    >>)
    == Ok("us-ascii")
  assert mimetype.detect_charset(<<"<html><meta charset=\"\"></html>":utf8>>)
    == Ok("us-ascii")
}

pub fn charset_outside_a_meta_tag_is_ignored_test() {
  let doc = <<"<meta name=\"x\"><p>charset=koi8-r</p>":utf8>>
  assert mimetype.detect_charset(doc) == Ok("us-ascii")
}

pub fn meta_http_equiv_content_charset_test() {
  let doc = <<
    "<meta http-equiv=\"Content-Type\" content=\"text/html; charset=EUC-KR\">":utf8,
  >>
  assert mimetype.detect_charset(doc) == Ok("euc-kr")
}

// The UTF-8 scan reads the same 3072 bytes as `detect`.
pub fn invalid_utf8_after_the_first_kilobyte_is_seen_test() {
  assert mimetype.detect_charset(<<ascii(1500):bits, 0xFF>>) == Error(Nil)
  assert mimetype.detect_charset(<<ascii(3071):bits, 0xFF>>) == Error(Nil)
}

pub fn invalid_utf8_after_3072_bytes_is_ignored_test() {
  assert mimetype.detect_charset(<<ascii(3072):bits, 0xFF>>) == Ok("us-ascii")
}

// A character that the 3072-byte limit cuts in two is not an error, but
// one that the input itself ends inside is.
pub fn multibyte_character_cut_by_the_limit_test() {
  assert mimetype.detect_charset(<<ascii(3071):bits, "あ":utf8>>) == Ok("utf-8")
  assert mimetype.detect_charset(<<ascii(3070):bits, "あ":utf8>>) == Ok("utf-8")
  assert mimetype.detect_charset(<<ascii(3071):bits, 0xE3>>) == Error(Nil)
  assert mimetype.detect_charset(<<ascii(3070):bits, 0xE3, 0x81>>) == Error(Nil)
}

// UTF-16 without a byte order mark is full of NUL bytes. It is not
// US-ASCII text.
pub fn utf16_without_bom_is_not_us_ascii_test() {
  assert mimetype.detect_charset(<<"h":utf8, 0, "i":utf8, 0>>) == Error(Nil)
  assert mimetype.detect_charset(<<0, "h":utf8, 0, "i":utf8>>) == Error(Nil)
}

// A UTF-32LE byte order mark starts with the UTF-16LE one, so the
// longer mark has to win.
pub fn utf32_and_utf16_byte_order_marks_test() {
  assert mimetype.detect_charset(<<0xFF, 0xFE, 0x00, 0x00, "h":utf8, 0, 0, 0>>)
    == Ok("utf-32le")
  assert mimetype.detect_charset(<<0xFF, 0xFE, "h":utf8, 0x00>>)
    == Ok("utf-16le")
  assert mimetype.detect_charset(<<0x00, 0x00, 0xFE, 0xFF>>) == Ok("utf-32be")
  assert mimetype.detect_charset(<<0xFE, 0xFF, 0x00, "h":utf8>>)
    == Ok("utf-16be")
  assert mimetype.detect_charset(<<0xEF, 0xBB, 0xBF>>) == Ok("utf-8")
}

// Nesting as deep as the detection limit allows must not exhaust the
// stack on either target.
pub fn deeply_nested_json_test() {
  let arrays = bit_array.from_string(string.repeat("[", 3072))
  assert detected(arrays) == Ok("application/json")
  let objects = bit_array.from_string(string.repeat("{\"a\":", 700))
  assert detected(objects) == Ok("application/json")
}
