//// Benchmark harness for the hot lookup and detection paths.
////
//// This is *not* a strict performance gate. The harness exists so
//// contributors can spot material regressions when they grow the
//// signature corpus or refactor a detector. Run with:
////
////   just bench-erlang
////   just bench-javascript
////
//// The output is a Markdown table; pipe it to a file and diff against
//// a baseline run from `main` to evaluate a change.

import gleam/bit_array
import gleam/int
import gleam/io
import gleam/list
import mimetype

@target(erlang)
@external(erlang, "bench_ffi", "monotonic_ns")
fn now_ns() -> Int

@target(javascript)
@external(javascript, "./bench_ffi.mjs", "monotonic_ns")
fn now_ns() -> Int

@target(erlang)
const target_name = "erlang"

@target(javascript)
const target_name = "javascript"

pub fn main() -> Nil {
  io.println("# mimetype benchmarks")
  io.println("")
  io.println("target: " <> target_name)
  io.println("")
  io.println("| name | iterations | total_ms | ns/op |")
  io.println("| ---- | ---------- | -------- | ----- |")

  let cases = build_cases()

  // Warm the BEAM JIT / V8 with a single pass before the timed runs so
  // the first measurement is not penalised. We discard the result.
  list.each(cases, fn(c) {
    let BenchCase(_, iterations, action) = c
    loop_n(iterations / 10 + 1, action)
  })

  list.each(cases, fn(c) {
    let BenchCase(name, iterations, action) = c
    run(name, iterations, action)
  })
}

type BenchCase {
  BenchCase(name: String, iterations: Int, action: fn() -> Nil)
}

fn build_cases() -> List(BenchCase) {
  let png = <<0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A>>
  let pdf = <<"%PDF-1.7":utf8, 0x0A>>
  let zip = <<0x50, 0x4B, 0x03, 0x04, 20, 0, 0, 0>>
  let json = <<"{\"x\":1,\"y\":[1,2,3]}":utf8>>
  let html = <<"<html><body>hi</body></html>":utf8>>
  let text = <<"plain text payload\n":utf8>>
  let docx = build_docx()
  let jar = build_jar()
  let assert Ok(jpeg) = mimetype.parse("image/jpeg")

  [
    BenchCase("extension_to_mime_type(\"json\")", 100_000, fn() {
      let _ = mimetype.extension_to_mime_type("json")
      Nil
    }),
    BenchCase("mime_type_to_extensions(image/jpeg)", 100_000, fn() {
      let _ = mimetype.mime_type_to_extensions(jpeg)
      Nil
    }),
    BenchCase("filename_to_mime_type(\"photo.JPG\")", 100_000, fn() {
      let _ = mimetype.filename_to_mime_type("photo.JPG")
      Nil
    }),
    BenchCase("detect(png signature)", 100_000, fn() {
      let _ = mimetype.detect(png)
      Nil
    }),
    BenchCase("detect(pdf signature)", 100_000, fn() {
      let _ = mimetype.detect(pdf)
      Nil
    }),
    BenchCase("detect(zip signature)", 100_000, fn() {
      let _ = mimetype.detect(zip)
      Nil
    }),
    BenchCase("detect(docx structural)", 20_000, fn() {
      let _ = mimetype.detect(docx)
      Nil
    }),
    BenchCase("detect(jar structural)", 20_000, fn() {
      let _ = mimetype.detect(jar)
      Nil
    }),
    BenchCase("detect(json sniff)", 50_000, fn() {
      let _ = mimetype.detect(json)
      Nil
    }),
    BenchCase("detect(html sniff)", 50_000, fn() {
      let _ = mimetype.detect(html)
      Nil
    }),
    BenchCase("detect(printable ASCII fallback)", 50_000, fn() {
      let _ = mimetype.detect(text)
      Nil
    }),
  ]
}

fn run(name: String, iterations: Int, action: fn() -> Nil) -> Nil {
  let start = now_ns()
  loop_n(iterations, action)
  let elapsed = now_ns() - start
  let total_ms = elapsed / 1_000_000
  let per_op_ns = elapsed / iterations
  io.println(
    "| "
    <> name
    <> " | "
    <> int.to_string(iterations)
    <> " | "
    <> int.to_string(total_ms)
    <> " | "
    <> int.to_string(per_op_ns)
    <> " |",
  )
}

fn loop_n(n: Int, action: fn() -> Nil) -> Nil {
  case n {
    0 -> Nil
    _ -> {
      action()
      loop_n(n - 1, action)
    }
  }
}

// --- Fixture builders -------------------------------------------------

// DOCX = ZIP with [Content_Types].xml + word/ entry.
fn build_docx() -> BitArray {
  bit_array.concat([
    <<0x50, 0x4B, 0x03, 0x04>>,
    <<0x14, 0x00, 0x00, 0x00, 0x00, 0x00>>,
    <<0x00, 0x00, 0x00, 0x00>>,
    <<0x00, 0x00, 0x00, 0x00>>,
    <<0x00, 0x00, 0x00, 0x00>>,
    <<0x00, 0x00, 0x00, 0x00>>,
    <<0x13, 0x00>>,
    <<0x00, 0x00>>,
    <<"[Content_Types].xml":utf8>>,
    <<0x50, 0x4B, 0x03, 0x04>>,
    <<0x14, 0x00, 0x00, 0x00, 0x00, 0x00>>,
    <<0x00, 0x00, 0x00, 0x00>>,
    <<0x00, 0x00, 0x00, 0x00>>,
    <<0x00, 0x00, 0x00, 0x00>>,
    <<0x00, 0x00, 0x00, 0x00>>,
    <<0x11, 0x00>>,
    <<0x00, 0x00>>,
    <<"word/document.xml":utf8>>,
  ])
}

// JAR = ZIP with META-INF/MANIFEST.MF as a leading entry.
fn build_jar() -> BitArray {
  bit_array.concat([
    <<0x50, 0x4B, 0x03, 0x04>>,
    <<0x14, 0x00, 0x00, 0x00, 0x00, 0x00>>,
    <<0x00, 0x00, 0x00, 0x00>>,
    <<0x00, 0x00, 0x00, 0x00>>,
    <<0x00, 0x00, 0x00, 0x00>>,
    <<0x00, 0x00, 0x00, 0x00>>,
    <<0x14, 0x00>>,
    <<0x00, 0x00>>,
    <<"META-INF/MANIFEST.MF":utf8>>,
  ])
}
