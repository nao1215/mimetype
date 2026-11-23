# mimetype

[![CI](https://github.com/nao1215/mimetype/actions/workflows/ci.yml/badge.svg)](https://github.com/nao1215/mimetype/actions/workflows/ci.yml)
[![Gitleaks](https://github.com/nao1215/mimetype/actions/workflows/gitleaks.yml/badge.svg)](https://github.com/nao1215/mimetype/actions/workflows/gitleaks.yml)
[![Trivy](https://github.com/nao1215/mimetype/actions/workflows/trivy.yml/badge.svg)](https://github.com/nao1215/mimetype/actions/workflows/trivy.yml)
[![OSV-Scanner](https://github.com/nao1215/mimetype/actions/workflows/osv-scan.yml/badge.svg)](https://github.com/nao1215/mimetype/actions/workflows/osv-scan.yml)
[![Hex](https://img.shields.io/hexpm/v/mimetype)](https://hex.pm/packages/mimetype)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/mimetype/)
[![Hex Downloads](https://img.shields.io/hexpm/dt/mimetype)](https://hex.pm/packages/mimetype)
[![License](https://img.shields.io/github/license/nao1215/mimetype)](https://github.com/nao1215/mimetype/blob/main/LICENSE)
[![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/nao1215/mimetype/badge)](https://scorecard.dev/viewer/?uri=github.com/nao1215/mimetype)

MIME types from file extensions and from file contents, for Gleam on Erlang and JavaScript.

The extension table is generated from [jshttp/mime-db](https://github.com/jshttp/mime-db), the data behind the `mime-types` npm package. Detection reads the first 3072 bytes of a file and recognises more than 80 formats by their magic numbers or structure, including JSON, HTML, SVG and the ZIP-based Office, OpenDocument and EPUB files. The `mimetype/accept` module picks a response type from an `Accept` header. The only dependency is `gleam_stdlib`.

```sh
gleam add mimetype@0
```

## Usage

The type for a file name, with `application/octet-stream` as the fallback:

```gleam
import gleam/result
import mimetype

pub fn content_type(filename: String) -> String {
  mimetype.filename_to_mime_type(filename)
  |> result.unwrap(mimetype.octet_stream)
  |> mimetype.to_string
}

// content_type("report.PDF") -> "application/pdf"
// content_type("notes") -> "application/octet-stream"
```

An uploaded file name comes from the user, so check the bytes instead:

```gleam
import gleam/list
import mimetype

pub fn is_allowed_image(bytes: BitArray) -> Bool {
  case mimetype.detect(bytes) {
    Ok(mime) ->
      list.contains(["image/png", "image/jpeg", "image/webp"], mimetype.essence(mime))
    Error(Nil) -> False
  }
}
```

`detect_with_filename` uses both. A signature in the bytes wins, and a text type from the name such as `text/csv` is kept when the bytes are text. A binary type from the name is not trusted for text bytes, so a text file named `photo.png` is `text/plain`.

```gleam
mimetype.detect_with_filename(<<"id,name\n1,gleam\n":utf8>>, "users.csv")
|> result.map(mimetype.to_string)
// -> Ok("text/csv")
```

Choosing a response type from an `Accept` header:

```gleam
import mimetype
import mimetype/accept

pub fn response_type(header: String) -> Result(mimetype.MimeType, Nil) {
  let assert Ok(html) = mimetype.parse("text/html")
  let assert Ok(json) = mimetype.parse("application/json")
  case accept.parse(header) {
    Ok(items) -> accept.negotiate(items, [html, json])
    Error(_) -> Error(Nil)
  }
}

// response_type("application/json, text/html;q=0.9") -> Ok(json)
// response_type("image/*") -> Error(Nil)
```

The API reference is on [HexDocs](https://hexdocs.pm/mimetype/), and the detected types are listed on the [Supported formats](https://hexdocs.pm/mimetype/supported-formats.html) page.

## Notes

- Inside a ZIP archive, detection reads only the entry names near the start of the file, which is enough for docx, xlsx, pptx, odt, ods, odp, epub, jar and apk. Archives inside archives are not opened.
- Printable ASCII without a signature is reported as `text/plain`. UTF-8 text without a byte order mark matches no signature, so `detect` returns `Error(Nil)` for it; use `detect_with_filename` or `detect_charset` for such files.
- `detect_charset` reads a byte order mark, an XML declaration, an HTML `<meta charset>` or, failing those, checks for valid UTF-8. It does not guess other encodings such as Latin-1.
- `accept.negotiate` compares `type/subtype` only. Parameters on media ranges are ignored.

How the package is tested is described in [doc/testing.md](https://github.com/nao1215/mimetype/blob/main/doc/testing.md).

## Verifying releases

Each GitHub Release attaches the Hex package tarball (`mimetype-<version>.tar`),
`checksums.txt`, a cosign signature bundle (`checksums.txt.sigstore.json`) and
build provenance (`mimetype-<version>.intoto.jsonl`). Download the assets, then:

```sh
gh attestation verify mimetype-<version>.tar --repo nao1215/mimetype

cosign verify-blob \
  --bundle checksums.txt.sigstore.json \
  --certificate-identity-regexp '^https://github\.com/nao1215/mimetype/\.github/workflows/release\.yml@refs/tags/v' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  checksums.txt
sha256sum --check checksums.txt
```

## License

[MIT](https://github.com/nao1215/mimetype/blob/main/LICENSE). The extension table is derived from jshttp/mime-db, also MIT; see [THIRD_PARTY_NOTICES.md](https://github.com/nao1215/mimetype/blob/main/THIRD_PARTY_NOTICES.md).
