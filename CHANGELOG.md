# Changelog

## Unreleased

- Detect `application/json` from leading bytes via a bounded JSON-prefix
  validator. Top-level objects (`{...}`) and arrays (`[...]`) are recognized
  after optional UTF-8 BOM and whitespace, including truncated inputs.
  Bare top-level scalars (numbers, strings, `true`/`false`/`null`) are
  intentionally not sniffed to avoid false positives on plain text. (#19)

## [0.1.0] - 2026-04-26

- Added the initial cross-target Gleam project scaffold (`just`, `mise`, CI, release workflow).
- Added MIME type lookup derived from `mime-db`.
- Added common magic-number detection for binary file formats.

Until `1.0.0`, breaking changes may still occur in minor `0.x`
releases.
