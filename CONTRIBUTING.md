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

The MIME-DB lookup tables live in three generated files, all derived
from `doc/reference/upstream/mime-db/db.json`:

- `src/mimetype/internal/db.gleam` — thin Gleam wrapper exposing the
  lookup functions via `@external`
- `src/mimetype/internal/mimetype_db_ffi.erl` — Erlang map-based table
- `src/mimetype/internal/db_ffi.mjs` — JavaScript `Map`-based table

Regenerate all three with:

```console
just generate-db
```

The script also build-checks the regenerated files inside a temporary
project on both Erlang and JavaScript targets before installing them.
CI re-runs the same script against the upstream commit pinned in the
`db.gleam` header and fails on any drift.

When changing the generation logic or updating the upstream data:

1. Run `just generate-db` and commit all three regenerated files
2. Keep the upstream MIT notice in the FFI files' headers intact
3. Keep `THIRD_PARTY_NOTICES.md` aligned with the packaged third-party data
4. Run `just ci`

### Automated upstream drift detection

The `Refresh mime-db` workflow (`.github/workflows/refresh-mime-db.yml`)
runs every Monday at 03:30 UTC and on demand via *Actions → Refresh mime-db
→ Run workflow*. It clones the latest `jshttp/mime-db`, regenerates the
embedded data tables in a fresh checkout, and — only when the regenerated
output differs from `main` — files (or updates) an issue tagged
`automation:mime-db-refresh` summarising:

- the upstream `package.json` version,
- the upstream commit SHA, and
- a `git diff --stat` of the regenerated files.

The workflow does not push or open a PR. To consume a drift notification:

1. Pick up the open `automation:mime-db-refresh` issue.
2. Locally run the regeneration steps documented above.
3. Open a normal PR with the regenerated files and link the issue.
4. Close the issue when the PR merges.

If you want to trigger a check off-cycle (e.g., to confirm the package
is at parity right after release), use the `workflow_dispatch` button.

## Project structure

`mimetype` intentionally splits the problem into two layers:

- `src/mimetype.gleam` exposes the public API
- `src/mimetype/internal/db.gleam` is the Gleam wrapper for the
  generated extension and reverse lookup tables; the data itself lives
  in the per-target FFI files `mimetype_db_ffi.erl` and `db_ffi.mjs`
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

## Release process

Releases are cut from `main` and driven entirely by tag pushes. The
`.github/workflows/release.yml` workflow runs the full check matrix,
publishes to Hex, and creates a GitHub Release whose body is extracted
from `CHANGELOG.md`.

Steps for a new release `vX.Y.Z`:

1. Confirm `main` is green on CI and the working tree is clean.
2. Promote any items under `## Unreleased` in `CHANGELOG.md` into a
   new `## [X.Y.Z] - YYYY-MM-DD` section directly below `## Unreleased`.
3. Bump `version = "X.Y.Z"` in `gleam.toml`.
4. Open a PR with the changelog and version bump, get it green and merged.
5. After merge, fast-forward `main` and tag the merge commit:
   ```console
   git checkout main
   git pull --ff-only origin main
   git tag vX.Y.Z
   git push origin vX.Y.Z
   ```
6. The release workflow handles `gleam publish` and the GitHub Release.
   Verify both completed at https://hex.pm/packages/mimetype and
   https://github.com/nao1215/mimetype/releases.

## License

Contributions to this project are considered to be released under the
project license (MIT).
