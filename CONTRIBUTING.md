# Contributing to mimetype

## Development setup

You need the following tools installed:

- [Gleam](https://gleam.run/) 1.15+
- Erlang/OTP 28+
- Node.js 22+ for JavaScript-target builds and tests
- [just](https://github.com/casey/just) as a task runner
- [mise](https://mise.jdx.dev/) for toolchain management (recommended; this repository ships with `.mise.toml`)
- `jq` for regenerating the extension database from `mime-db`

Clone the repository and install the managed toolchain:

```console
git clone https://github.com/nao1215/mimetype.git
cd mimetype
mise install
just deps
```

`just` recipes and helper scripts locate the mise-managed toolchain via
`scripts/lib/mise_bootstrap.sh`, so `mise activate` is not required in
the current shell.

## Running checks

Run the full CI-equivalent check locally with:

```console
just ci
```

This runs format check, type check, lint, Erlang-target build and test,
JavaScript-target build and test.

You can also run individual steps:

| Command | Effect |
| --- | --- |
| `just format` | Reformat `src/` and `test/` |
| `just format-check` | Fail on formatting drift |
| `just typecheck` | `gleam check` |
| `just lint` | Run `glinter` with warnings as errors |
| `just build-erlang` / `just build-javascript` | Per-target build |
| `just test-erlang` / `just test-javascript` | Per-target test |
| `just docs` | Build HexDocs HTML |
| `just clean` | Delete `build/` |

## Regenerating the extension database

`src/mimetype/internal/db.gleam` is generated from
`doc/reference/upstream/mime-db/db.json`.

Regenerate it with:

```console
just generate-db
```

When changing the generation logic or updating the upstream data:

1. Regenerate `src/mimetype/internal/db.gleam`
2. Keep the upstream MIT notice in the generated header intact
3. Keep `THIRD_PARTY_NOTICES.md` aligned with the packaged third-party data
4. Run `just ci`

## Project structure

`mimetype` intentionally splits the problem into two layers:

- `src/mimetype.gleam` exposes the public API
- `src/mimetype/internal/db.gleam` contains generated extension and reverse lookup tables
- `src/mimetype/internal/magic.gleam` contains pure-Gleam byte-signature detection

The extension database provides broad coverage. Magic-number detection
provides content-based correction for common binary formats when the
filename or declared content type is missing or wrong.

## Code style

- Run `gleam format src/ test/` before committing.
- The build uses `--warnings-as-errors`; fix all warnings.
- `glinter` runs in `warnings_as_errors` mode. Rule changes in
  `gleam.toml` require a justification.
- Public API (`pub fn`, `pub type`, public constants) requires doc comments.
- Keep the public API small and deterministic.
- Prefer pure Gleam over target-specific FFI.
- Keep cross-target behavior aligned unless target-specific behavior is
  explicitly documented.
- Prefer content-based detection only where signatures are stable and
  cheap to check; broad coverage belongs in the generated extension map.

## Testing expectations

- Extension lookup changes need deterministic tests for representative extensions.
- Magic-number changes need positive tests for the new signature and a
  fallback test when detection should remain unknown.
- Behavior that differs by target must be tested on the relevant target
  and justified in code comments or docs.
- New public behavior should be reflected in README examples or doc comments.

## Pull request expectations

- All CI checks must pass (`just ci`).
- Include tests for new behavior.
- Keep generated files in sync with their generator.
- Use [Conventional Commits](https://www.conventionalcommits.org/) for
  commit messages (`feat:`, `fix:`, `docs:`, `ci:`, `chore:`, …).
- One logical change per pull request.

## Public documentation style

User-facing docs (README, release notes, doc comments, HexDocs) follow
a terse reference-oriented style. Treat violations as review blockers.

- No marketing prose. Write as if documenting a standard library.
- No emoji in code examples, tables, or prose.
- Prefer concrete examples over long explanations.
- State constraints factually.
- Keep examples runnable as written.
- Document precedence rules clearly when metadata and content can disagree.

## License

Contributions to this project are considered to be released under the
project license (MIT).
