# repo-standard

The repository standard shared by the owner's repositories: git hooks and privacy rules, CI,
release and secret-scan workflows, Dependabot, a pull request template and bats tests. This
repository holds the canonical files at their real paths and publishes immutable versions
`vX.Y.Z`. Each repository of the standard vendors a published version with `tools/sync` and never
edits the copies; `.github/standard/MANIFEST` lists them.

## Layout

- `.githooks/`: the hooks, `privacy-scan`, `lib.sh` and the rule packs in `rules/`.
- `.github/workflows/`: the four canonical workflows, live here too: `ci`, `secret-scan`,
  `release` and `image`.
- `.github/standard/bin/`: `conf`, `standard-check`, `install-tools`, `run-stage`, `no-skips`,
  `pr-text`, `pr-title`, `changelog-entry`, `secret-scan`, the release tools `release-meta`,
  `release-prepare`, `release-build`, `release-draft`, `release-promote` and `release-verify`,
  and their `lib.bash`.
- `.github/standard/tests/`: the bats suites of the vendored code, their `lib.bash` and the
  `gh`, `docker` and `gitleaks` stubs. `.github/standard/actions.allow`: the actions the
  workflows may use.
- `blocks/`: the canonical body of each block that repositories carry inside files they own,
  such as `blocks/SECURITY.md/reporting@private.md`; a hidden name's leading dot is written as `_`
  there (`blocks/_github/dependabot.yml/`), since git refuses a folder named `.gitattributes`.
- `config/private-names`: the private repositories that no copy or block may name; never
  vendored.
- `tools/manifest`: writes `.github/standard/MANIFEST`. `tools/consumer-suite`: builds a scratch
  consumer, of a public or a private shape, that holds only what the MANIFEST vendors plus files
  of its own, where CI runs the standard's suites again. `tests/` holds the tests of `tools/`.
- `ci/test` and `ci/test.ps1` (Windows) and `ci/system` (Linux): this repository's CI stages.

## Status

Phase 1 (hooks and checks) is merged. Phase 2 comes in three pull requests: the workflows, the
vendored tools and the secret scan; then `tools/sync`, `tools/status` and the templates; then
the release of version 1.0.0.

## Checks

- `bats .github/standard/tests/hooks.bats` and the other suites, one file at a time on Windows
  (Git Bash); `bats tests/` for `tools/`.
- `sh .githooks/privacy-scan --tracked` and `sh tools/manifest --check`.
- `sh tools/consumer-suite [--shape private] DIR`, then `bats DIR/.github/standard/tests/`: the
  standard's suites where only the vendored files exist, as in a consumer.
- CI: `ci.yml` runs the job `standard` (every vendored suite on Linux, the lint, the privacy
  packs, the MANIFEST and the pull request checks), the stage `test` on Windows (`ci/test`, then
  the smoke test of the pinned PowerShell modules), the stage `system` on Linux (the suites,
  lint included, in a scratch consumer of each shape) and `hooks-windows`, and fails on any
  skipped test. `secret-scan.yml` scans each pull request's commits, and `release.yml` builds a
  pull request that touches the release files twice and compares the builds.
