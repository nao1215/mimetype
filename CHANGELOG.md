# Changelog

## Unreleased

- Detect `application/json` from leading bytes via a bounded JSON-prefix
  validator. Top-level objects (`{...}`) and arrays (`[...]`) are recognized
  after optional UTF-8 BOM and whitespace, including truncated inputs.
  Bare top-level scalars (numbers, strings, `true`/`false`/`null`) are
  intentionally not sniffed to avoid false positives on plain text. (#19)
- Detect `text/html` from leading bytes by case-insensitive matching on a
  WHATWG-aligned tag list (`<!doctype html`, `<html`, `<head`, `<body`,
  `<script`, `<iframe`, `<table`, `<style`, `<title`, `<br`, `<p`, `<h1`,
  `<div`, `<font`, `<img`, `<a`) followed by a tag-terminating byte
  (whitespace, `>`, or end of input). (#17)
- Detect `text/xml` from leading bytes by recognizing the lowercase
  `<?xml` declaration followed by a tag-terminating byte. Both detectors
  strip an optional UTF-8 BOM and HTML whitespace before matching. (#17)

## [0.1.0] - 2026-04-26

- Added the initial cross-target Gleam project scaffold (`just`, `mise`, CI, release workflow).
- Added MIME type lookup derived from `mime-db`.
- Added common magic-number detection for binary file formats.

Until `1.0.0`, breaking changes may still occur in minor `0.x`
releases.
