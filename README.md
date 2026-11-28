# mimetype

[![CI](https://github.com/nao1215/mimetype/actions/workflows/ci.yml/badge.svg)](https://github.com/nao1215/mimetype/actions/workflows/ci.yml)
![Coverage](https://raw.githubusercontent.com/nao1215/octocovs-central-repo/main/badges/nao1215/mimetype/coverage.svg)
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
- Bytes without a signature are reported as `text/plain` unless they hold a binary data byte (a control byte other than tab, LF, FF, CR and ESC), as in WHATWG MIME Sniffing. This covers UTF-8 and Latin-1 text; `detect_charset` tells them apart.
- `detect_charset` reads a byte order mark, an XML declaration, an HTML `<meta charset>` or, failing those, checks for valid UTF-8. It does not guess other encodings such as Latin-1.
- `accept.negotiate` follows RFC 9110 section 12.5.1: a media range with parameters, such as `text/html;level=1`, matches only offers with those parameters and takes precedence over `text/html`. Parameters on `type/*` and `*/*` are ignored.
- `accept.negotiate_value` matches `en` to `en-US` (RFC 4647 basic filtering) and treats `identity` as acceptable unless the header rules it out (RFC 9110 section 12.5.3).

How the package is tested is described in [doc/testing.md](https://github.com/nao1215/mimetype/blob/main/doc/testing.md).

## Verifying releases

Each GitHub Release attaches the tarball published to Hex (`mimetype-<version>.tar`), `checksums.txt`, a cosign signature bundle (`checksums.txt.sigstore.json`) and build provenance (`mimetype-<version>.intoto.jsonl`). The release workflow downloads the tarball from Hex after `gleam publish` and checks it against the checksum Hex records before signing it, so the tarball you get from Hex is the one that is signed and attested.

```sh
curl -fsSLO https://repo.hex.pm/tarballs/mimetype-<version>.tar
gh attestation verify mimetype-<version>.tar --repo nao1215/mimetype
```

To check the signature as well, download `checksums.txt` and `checksums.txt.sigstore.json` from the Release into the same directory. The workflow runs on the release tag, or on `main` when the assets of a published tag are attached again.

```sh
cosign verify-blob \
  --bundle checksums.txt.sigstore.json \
  --certificate-identity-regexp '^https://github\.com/nao1215/mimetype/\.github/workflows/release\.yml@refs/(tags/v.+|heads/main)$' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  checksums.txt
sha256sum --check checksums.txt
```

## License

[MIT](https://github.com/nao1215/mimetype/blob/main/LICENSE). The extension table is derived from jshttp/mime-db, also MIT; see [THIRD_PARTY_NOTICES.md](https://github.com/nao1215/mimetype/blob/main/THIRD_PARTY_NOTICES.md).
