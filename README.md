# repo-standard

The repository standard shared by the owner's repositories: git hooks and privacy rules, CI,
release and secret-scan workflows, Dependabot, a pull request template and bats tests. This
repository holds the canonical files at their real paths and publishes immutable versions
`vX.Y.Z`. Repositories adopt a published version with `tools/sync` and never edit the copies.
`.github/standard/MANIFEST` lists them.

## Layout

- `.githooks/`: the hooks, `privacy-scan`, `lib.sh` and the rule packs in `rules/`.
- `.github/workflows/`: the four canonical workflows, which also run here: `ci`, `secret-scan`,
  `release` and `image`.
- `.github/standard/bin/`: `conf`, `standard-check`, `install-tools`, `run-stage`, `no-skips`,
  `pr-text`, `pr-title`, `changelog-entry`, `secret-scan`, the release tools `release-meta`,
  `release-prepare`, `release-build`, `release-draft`, `release-promote` and `release-verify`,
  and their `lib.bash`.
- `.github/standard/tests/`: the bats suites of the vendored code, their `lib.bash` and the
  `gh`, `docker` and `gitleaks` stubs. `.github/standard/actions.allow`: the actions the
  workflows may use.
- `blocks/`: the canonical body of each block that repositories carry inside files they own,
  such as `blocks/SECURITY.md/reporting@private.md`. A hidden name's leading dot is written as `_`
  there (`blocks/_github/dependabot.yml/`), since git refuses a folder named `.gitattributes`.
- `tools/manifest`: writes `.github/standard/MANIFEST`. `tools/consumer-suite`: builds a scratch
  consumer, of a public or a private shape, that holds only what the MANIFEST vendors plus files
  of its own, where CI runs the standard's suites again. `tests/` holds the tests of `tools/`.
- `tools/sync`: writes a published release into a repository's worktree, run from a clone of
  its tag. `--init` adopts a repository (CONTRIBUTING.md, Adopting a repository).
  `tools/status`: the read-only audit of the repositories, run regularly.
- `tools/release-seal`, `tools/release-seal.ps1` and `tools/release-seal-askpass`: the seal tool
  of the repositories with `SEAL=yes`, its dialog and its passphrase dialog, released as assets
  and installed outside every clone (CONTRIBUTING.md, Release contract).
- `templates/`: the starters of an adoption: the config, CHANGELOG.md, CONTRIBUTING.md,
  SECURITY.md, tests/helpers.bash and ci/ per stack.
- `ci/test` and `ci/test.ps1` (Windows) and `ci/system` (Linux): this repository's CI stages.
- CONTRIBUTING.md and SECURITY.md: how this repository is changed and released, and its trust
  model.

## Releases

The releases and their notes are on GitHub's Releases page and in `CHANGELOG.md`.

## Checks

- `bats .github/standard/tests/hooks.bats` and the other suites, one file at a time on Windows
  (Git Bash); `bats tests/` for `tools/`.
- `sh .githooks/privacy-scan --tracked` and `sh tools/manifest --check`.
- `sh tools/consumer-suite [--shape private] DIR`, then `bats DIR/.github/standard/tests/`: the
  standard's suites where only the vendored files exist, as in a consumer.
- On Windows, `ci/test.ps1` under Windows PowerShell 5.1 with the pinned modules: the Pester
  tests of the seal dialog (CONTRIBUTING.md, Checks).
- CI: `ci.yml` runs the job `standard`: every vendored suite on Linux, the lint, the privacy
  packs, the MANIFEST and the pull request checks. It also runs the stage `test` on Windows
  (`ci/test`: the suites of the code that runs on Windows; then the smoke test of the pinned
  PowerShell modules), the stage `system` on Linux (the suites, lint included, in a scratch
  consumer of each shape) and `hooks-windows`. It fails on any skipped test. `secret-scan.yml`
  scans each pull request's commits. `release.yml` builds a pull request that touches the release
  files twice and compares the builds.
