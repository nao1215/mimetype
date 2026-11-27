//// The examples in README.md and in the doc comments, run as tests so
//// the documented results stay true on both targets.

import gleam/list
import gleam/result
import mimetype
import mimetype/accept

fn mime(value: String) -> mimetype.MimeType {
  let assert Ok(mime) = mimetype.parse(value)
  mime
}

fn content_type(filename: String) -> String {
  mimetype.filename_to_mime_type(filename)
  |> result.unwrap(mimetype.octet_stream)
  |> mimetype.to_string
}

fn is_allowed_image(bytes: BitArray) -> Bool {
  case mimetype.detect(bytes) {
    Ok(mime) ->
      list.contains(
        ["image/png", "image/jpeg", "image/webp"],
        mimetype.essence(mime),
      )
    Error(Nil) -> False
  }
}

fn response_type(header: String) -> Result(mimetype.MimeType, Nil) {
  let html = mime("text/html")
  let json = mime("application/json")
  case accept.parse(header) {
    Ok(items) -> accept.negotiate(items, [html, json])
    Error(_) -> Error(Nil)
  }
}

pub fn readme_content_type_test() {
  assert content_type("report.PDF") == "application/pdf"
  assert content_type("notes") == "application/octet-stream"
}

pub fn readme_is_allowed_image_test() {
  assert is_allowed_image(<<0x89, "PNG":utf8, 0x0D, 0x0A, 0x1A, 0x0A>>)
  assert !is_allowed_image(<<"GIF89a":utf8>>)
  assert !is_allowed_image(<<>>)
}

pub fn readme_detect_with_filename_test() {
  assert mimetype.detect_with_filename(
      <<"id,name\n1,gleam\n":utf8>>,
      "users.csv",
    )
    |> result.map(mimetype.to_string)
    == Ok("text/csv")
  assert mimetype.detect_with_filename(<<"hello":utf8>>, "photo.png")
    |> result.map(mimetype.to_string)
    == Ok("text/plain")
}

pub fn readme_response_type_test() {
  assert response_type("application/json, text/html;q=0.9")
    == Ok(mime("application/json"))
  assert response_type("image/*") == Error(Nil)
}

pub fn readme_text_without_a_signature_is_text_plain_test() {
  assert mimetype.detect(<<"こんにちは":utf8>>)
    |> result.map(mimetype.to_string)
    == Ok("text/plain")
  assert mimetype.detect_charset(<<"こんにちは":utf8>>) == Ok("utf-8")
}

pub fn doc_parse_test() {
  let assert Ok(html) = mimetype.parse("Text/HTML; Charset=UTF-8")
  assert mimetype.to_string(html) == "text/html; charset=UTF-8"
  assert mimetype.parse("html") == Error(mimetype.InvalidMimeType("html"))
  assert mimetype.parse_strict("text/plain;")
    == Error(mimetype.MalformedParameter(""))
}

pub fn doc_to_string_test() {
  assert mimetype.to_string(mime("text/plain;title=\"a b\""))
    == "text/plain; title=\"a b\""
}

pub fn doc_accessors_test() {
  assert mimetype.essence(mime("text/html; charset=utf-8")) == "text/html"
  let form = mime("multipart/form-data; boundary=xyz")
  assert mimetype.parameter(form, "Boundary") == Ok("xyz")
  assert mimetype.parameter(form, "charset") == Error(Nil)
  assert mimetype.charset(mime("text/html; charset=UTF-8")) == Ok("utf-8")
  assert mimetype.is_a(mime("application/epub+zip"), mime("application/zip"))
  assert mimetype.ancestors(mime(
      "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    ))
    |> list.map(mimetype.to_string)
    == ["application/zip"]
}

pub fn doc_lookup_test() {
  assert mimetype.extension_to_mime_type(".JSON")
    |> result.map(mimetype.to_string)
    == Ok("application/json")
  assert mimetype.extension_to_mime_type("nosuch") == Error(Nil)
  assert mimetype.filename_to_mime_type("photos/IMG_0001.JPG")
    |> result.map(mimetype.to_string)
    == Ok("image/jpeg")
  assert mimetype.filename_to_mime_type(".gitignore") == Error(Nil)
  assert mimetype.mime_type_to_extensions(mime("image/jpeg"))
    == ["jpg", "jpeg", "jpe"]
}

pub fn doc_detect_test() {
  assert mimetype.detect(<<0x89, "PNG":utf8, 0x0D, 0x0A, 0x1A, 0x0A>>)
    |> result.map(mimetype.to_string)
    == Ok("image/png")
  assert mimetype.detect(<<0xFF, 0x00, 0xFE>>) == Error(Nil)
  assert mimetype.detect_signature_only(<<"a,b\n1,2\n":utf8>>) == Error(Nil)
  assert mimetype.detect_with_extension(<<"a,b\n1,2\n":utf8>>, "csv")
    |> result.map(mimetype.to_string)
    == Ok("text/csv")
  assert mimetype.detect_with_extension(<<"hello":utf8>>, "png")
    |> result.map(mimetype.to_string)
    == Ok("text/plain")
  assert mimetype.detect_with_filename(<<"# Title\n":utf8>>, "notes.md")
    |> result.map(mimetype.to_string)
    == Ok("text/markdown")
  assert mimetype.detect_charset(<<0x48, 0x69, 0xC0, 0x20>>) == Error(Nil)
}

pub fn doc_accept_test() {
  let html = mime("text/html")
  let json = mime("application/json")
  assert accept.parse("text/html, */*;q=0.1")
    == Ok([
      accept.AcceptItem(accept.Specific(html), quality: 1.0),
      accept.AcceptItem(accept.AnyType([]), quality: 0.1),
    ])
  assert accept.parse("text/html;q=2")
    == Error(accept.InvalidQValue("text/html;q=2"))
  let assert Ok(items) = accept.parse("text/html, application/json;q=0.9")
  assert accept.negotiate(items, [json, html]) == Ok(html)
  let assert Ok(items) = accept.parse("image/*")
  assert accept.negotiate(items, [json, html]) == Error(Nil)
}

pub fn doc_accept_values_test() {
  assert accept.parse_values("gzip, br;q=0.5")
    == Ok([
      accept.ValueItem("gzip", quality: 1.0),
      accept.ValueItem("br", quality: 0.5),
    ])
  assert accept.parse_values("gzip;q=x")
    == Error(accept.InvalidQValue("gzip;q=x"))
  let assert Ok(items) = accept.parse_values("gzip, br;q=1.0, *;q=0.1")
  assert accept.negotiate_value(items, ["br", "gzip"]) == Ok("br")
}
