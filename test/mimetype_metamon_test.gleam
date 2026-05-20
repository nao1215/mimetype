import gleam/list
import gleam/result
import gleam/string
import metamon
import metamon/generator
import metamon/generator/range
import metamon/relation
import mimetype

// ---------- parse / to_string round-trip ----------

pub fn parse_then_to_string_round_trip_for_canonical_essences_test() -> Nil {
  metamon.forall(
    generator.element_of([
      "text/plain", "text/html", "image/png", "image/jpeg", "image/svg+xml",
      "application/json", "application/xml", "application/zip",
      "application/pdf", "audio/mpeg", "video/mp4", "font/ttf",
    ]),
    fn(essence) {
      let case_insensitive =
        relation.equivalent_under(string.lowercase, "case_insensitive")
      let assert Ok(parsed) = mimetype.parse(essence)
      case_insensitive.holds(mimetype.to_string(parsed), essence)
    },
  )
}

pub fn essence_of_lowercases_essence_test() -> Nil {
  metamon.forall(
    generator.element_of(["TEXT/PLAIN", "Image/PNG", "APPLICATION/JSON"]),
    fn(essence) {
      let assert Ok(parsed) = mimetype.parse(essence)
      mimetype.essence_of(parsed) == string.lowercase(essence)
    },
  )
}

pub fn parse_rejects_empty_input_test() -> Nil {
  assert mimetype.parse("") == Error(mimetype.EmptyMimeType)
}

pub fn parse_rejects_whitespace_only_input_test() -> Nil {
  metamon.forall(
    generator.element_of([" ", "  ", "\t", "\n", " \t\n "]),
    fn(input) { mimetype.parse(input) == Error(mimetype.EmptyMimeType) },
  )
}

pub fn parse_rejects_inputs_without_slash_test() -> Nil {
  // string_alpha guarantees no slash, so the input cannot satisfy
  // `type/subtype`. The specific error variant depends on the input
  // (whitespace-only inputs from `string_alpha`'s edge list collapse
  // to `EmptyMimeType` after trimming; alpha-only inputs hit
  // `InvalidMimeType`) so we only assert "rejected".
  metamon.forall(generator.string_alpha(range.constant(1, 8)), fn(input) {
    result.is_error(mimetype.parse(input))
  })
}

// ---------- predicates ----------

pub fn is_image_holds_iff_essence_starts_with_image_slash_test() -> Nil {
  metamon.forall(
    generator.element_of([
      "image/png", "image/jpeg", "image/gif", "image/webp", "text/plain",
      "application/json", "video/mp4",
    ]),
    fn(essence) {
      let assert Ok(parsed) = mimetype.parse(essence)
      mimetype.is_image(parsed)
      == string.starts_with(mimetype.essence_of(parsed), "image/")
    },
  )
}

pub fn is_text_holds_for_text_family_and_json_xml_test() -> Nil {
  // Post-#129 contract: `is_text` is True for `text/*` AND for
  // text-encoded `application/*` payloads (JSON / JS / SQL families)
  // AND for any `*+json` / `*+xml` structured-syntax-suffix type.
  // Binary `application/*` and image / video types stay False.
  let text_essences = [
    "text/plain", "text/html", "text/csv", "application/json", "application/xml",
    "application/ld+json", "application/xhtml+xml", "image/svg+xml",
  ]
  let binary_essences = ["image/png", "video/mp4", "application/octet-stream"]
  metamon.forall(generator.element_of(text_essences), fn(essence) {
    let assert Ok(parsed) = mimetype.parse(essence)
    mimetype.is_text(parsed)
  })
  metamon.forall(generator.element_of(binary_essences), fn(essence) {
    let assert Ok(parsed) = mimetype.parse(essence)
    !mimetype.is_text(parsed)
  })
}

pub fn is_a_is_reflexive_test() -> Nil {
  metamon.forall(
    generator.element_of([
      "text/plain", "image/png", "application/json", "application/xml",
      "video/mp4", "audio/mpeg",
    ]),
    fn(essence) {
      let assert Ok(parsed) = mimetype.parse(essence)
      mimetype.is_a(parsed, parsed)
    },
  )
}

// ---------- extension ↔ mime type ----------

pub fn extension_lookup_is_case_insensitive_test() -> Nil {
  metamon.forall(
    generator.element_of(["png", "jpg", "pdf", "json", "html", "txt", "zip"]),
    fn(extension) {
      let lower = mimetype.extension_to_mime_type(extension)
      let upper = mimetype.extension_to_mime_type(string.uppercase(extension))
      mimetype.essence_of(lower) == mimetype.essence_of(upper)
    },
  )
}

pub fn extension_lookup_strips_leading_dot_test() -> Nil {
  metamon.forall(
    generator.element_of(["png", "jpg", "pdf", "json", "html", "txt"]),
    fn(extension) {
      let plain = mimetype.extension_to_mime_type(extension)
      let dotted = mimetype.extension_to_mime_type("." <> extension)
      mimetype.essence_of(plain) == mimetype.essence_of(dotted)
    },
  )
}

pub fn extension_round_trips_via_strict_lookup_test() -> Nil {
  metamon.forall(
    generator.element_of(["png", "pdf", "json", "html", "zip"]),
    fn(extension) {
      let assert Ok(mt) = mimetype.extension_to_mime_type_strict(extension)
      let assert Ok(extensions) = mimetype.mime_type_to_extensions_strict(mt)
      list.contains(extensions, extension)
    },
  )
}

pub fn unknown_extension_returns_octet_stream_test() -> Nil {
  metamon.forall(
    generator.element_of([
      "definitely_not_a_real_extension_x", "asdfqwerzxcv", "noextxxx",
    ]),
    fn(extension) {
      let mt = mimetype.extension_to_mime_type(extension)
      mimetype.essence_of(mt) == "application/octet-stream"
    },
  )
}

// ---------- detect ----------

pub fn detect_empty_returns_octet_stream_test() -> Nil {
  let mt = mimetype.detect(<<>>)
  assert mimetype.essence_of(mt) == "application/octet-stream"
}

pub fn detect_strict_empty_is_empty_input_error_test() -> Nil {
  assert mimetype.detect_strict(<<>>) == Error(mimetype.EmptyInput)
}

pub fn detect_png_signature_yields_image_png_test() -> Nil {
  let bytes = <<0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A>>
  let mt = mimetype.detect(bytes)
  assert mimetype.essence_of(mt) == "image/png"
}

pub fn detect_jpeg_signature_yields_image_jpeg_test() -> Nil {
  let bytes = <<0xFF, 0xD8, 0xFF, 0xE0>>
  let mt = mimetype.detect(bytes)
  assert mimetype.essence_of(mt) == "image/jpeg"
}

pub fn detect_pdf_signature_yields_application_pdf_test() -> Nil {
  let bytes = <<"%PDF-1.4":utf8>>
  let mt = mimetype.detect(bytes)
  assert mimetype.essence_of(mt) == "application/pdf"
}

pub fn detect_zip_signature_yields_application_zip_test() -> Nil {
  let bytes = <<0x50, 0x4B, 0x03, 0x04>>
  let mt = mimetype.detect(bytes)
  assert mimetype.essence_of(mt) == "application/zip"
}

// ---------- detect with random preserved-prefix property ----------

pub fn detect_is_stable_under_appending_random_bytes_test() -> Nil {
  // Property: detection that succeeds on a known signature must
  // remain the same when arbitrary bytes follow it.
  metamon.forall(generator.bit_array(range.constant(0, 32)), fn(extra) {
    let png_signature = <<0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A>>
    let combined = <<png_signature:bits, extra:bits>>
    let original = mimetype.detect(png_signature)
    let appended = mimetype.detect(combined)
    mimetype.essence_of(original) == mimetype.essence_of(appended)
  })
}
