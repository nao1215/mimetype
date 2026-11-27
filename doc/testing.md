# Testing

`just ci` runs everything below except the nightly job and mutation testing. Tests run on the Erlang and JavaScript targets, on the Gleam floor (1.14.0, OTP 27, Node 22) and on the latest Gleam 1.x. CI also checks that `doc/supported-formats.md` matches `magic.gleam` and that the generated MIME database matches a fresh run of `scripts/generate_mime_db.sh`.

## Examples and unit tests

`test/mimetype_test.gleam` checks parsing, extension lookup, every magic-number signature and the detection entry points with fixed inputs; `test/mimetype_accept_test.gleam` does the same for the `Accept` family of headers, including the examples of RFC 9110 section 12.5. `test/readme_test.gleam` runs the examples from the README and the doc comments. `test/mimetype_boundary_test.gleam` holds the boundary cases that mutation testing showed were missing. Tests use Gleam's `assert`.

## Generated properties

`test/mimetype_metamon_test.gleam` uses metamon: `parse` and `to_string` round-trip canonical essences, the predicates follow the essence, extension lookup ignores case and a leading dot, and a known signature is still detected with random bytes after it.

## Differential testing

`test/mimetype_accept_metamorphic_test.gleam` compares `accept.negotiate` with a reference model of RFC 9110 §12.5.1 written in the test, on random `Accept` headers (wildcards, q-values including 0, a media type parameter before or after `q`) and random offers with and without that parameter. In the model the most specific matching range sets an offer's q-value. This test found that an explicit `q=0` did not exclude a type when a broader range was also listed.

`test/mimetype_conformance_test.gleam` keeps the results of a comparison with other implementations. Every fixture in `test/mimetype_test.gleam`, its first 1, 2, 4 and 8 bytes, the fixture padded to 3072 and 3073 bytes, and about 150 generated files (archives written by Python's `zipfile`, `tarfile`, `gzip`, `bz2`, `lzma` and `sqlite3`, ISO base media brands, text in UTF-8, UTF-16, UTF-32, Latin-1 and Shift_JIS, text around the 1024- and 3072-byte limits) were run through `detect`, Go's `github.com/gabriel-vasile/mimetype` v1.4.16 and `file --mime-type` (libmagic 5.46), and the extension table was compared with Python 3.14's `mimetypes`. Each difference was settled against the format's specification or the IANA media type registry, and the cases where `mimetype` was wrong are pinned there.

`test/mimetype_detect_differential_test.gleam` compares the UTF-8 scan behind `detect_charset` with the standard library's UTF-8 decoding on random mixes of boundary code points (U+0080, U+07FF, U+0800, U+FFFF, U+10000, U+10FFFF, around the surrogates) and malformed sequences (overlong forms, encoded surrogates, stray continuation bytes, truncated sequences), and requires every array or object `gleam_json` writes, with or without padding or a BOM, to be detected as `application/json`. This test found that the scan accepted overlong forms, surrogates and code points above U+10FFFF.

## Metamorphic relations

- `test/mimetype_accept_metamorphic_test.gleam`: the order of the client's entries never changes the result of `negotiate` or `negotiate_value`; the result is always one of the offers, and stays chosen when the other offers are dropped.
- `test/mimetype_parse_detect_metamorphic_test.gleam`: `to_string` then `parse` (and `parse_strict`) gives back the same value for headers with quoted values containing `"`, `\`, `;`, spaces and non-ASCII; bytes appended after the first 3072 never change what `detect` returns.

## Nightly runs

`.github/workflows/nightly-property.yml` runs the whole suite ten times with `METAMON_RUNS_MULTIPLIER=10`, each pass with a new seed. A failure report prints its seed, so the case can be replayed with `seed: Some(n)` in `metamon.Config` and kept as a regression test.

## Mutation testing

`gleam run -m metamon/mutation` (metamon 0.16.0) mutates every module under `src/`: `==` and `!=` swapped, `<` and `<=`, `>` and `>=` moved across the boundary, `&&` and `||` swapped, `!` dropped, `True` and `False` swapped, and the arithmetic operators swapped, and runs `gleam test` on the Erlang target for each mutant. The MIME database tables live in the FFI files, so no module is excluded. `.github/workflows/mutation.yml` mutates the modules a pull request changes and fails on a survivor that `doc/mutation/baseline.json` does not list; the weekly run mutates every module. `just mutation` runs it locally and `just mutation-record` records the baseline. The score is (killed + timed out) / (killed + timed out + lived). The first run (2026-11-27) scored 98.2% with 5 survivors; a test for the escape in quoted values (`test/mimetype_boundary_test.gleam`) killed one of them, which raised the score to 98.5%. The other 4 are equivalent mutants and stay in the baseline: `is_a` in `internal/predicates` guards against an empty essence (2), which no `MimeType` has; the JSON sniffer passes `first: True` for a number that starts with a digit (1), and the digit is always read before the flag matters; and the ASCII case folding of the HTML patterns accepts `Z` (1), which no pattern contains in lower case.

<!-- mutation:start -->
| Module | Killed | Lived | Timed out | Score |
|---|---:|---:|---:|---:|
| `mimetype` | 7 | 0 | 0 | 100.0% |
| `mimetype/accept` | 21 | 0 | 0 | 100.0% |
| `mimetype/internal/accept` | 10 | 0 | 0 | 100.0% |
| `mimetype/internal/charset` | 69 | 0 | 0 | 100.0% |
| `mimetype/internal/hierarchy` | 1 | 0 | 0 | 100.0% |
| `mimetype/internal/magic` | 99 | 2 | 0 | 98.0% |
| `mimetype/internal/parse` | 43 | 0 | 0 | 100.0% |
| `mimetype/internal/predicates` | 20 | 2 | 0 | 90.9% |
| all | 270 | 4 | 0 | 98.5% |
<!-- mutation:end -->
