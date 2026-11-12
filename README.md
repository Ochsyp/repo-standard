# repo-standard

The repository standard shared by the owner's repositories: git hooks and privacy rules, CI,
release and secret-scan workflows, Dependabot, a pull request template and bats tests. This
repository holds the canonical files at their real paths and publishes immutable versions
`vX.Y.Z`. Each repository of the standard vendors a published version with `tools/sync` and never
edits the copies; `.github/standard/MANIFEST` lists them.

## Layout

- `.githooks/`: the hooks, `privacy-scan`, `lib.sh` and the rule packs in `rules/`.
- `.github/standard/bin/`: `conf`, `standard-check`, `install-tools`, `no-skips` and, later, the
  release tools.
- `.github/standard/tests/`: the bats suites of the vendored code and their `lib.bash`.
- `blocks/`: the canonical body of each block that repositories carry inside files they own,
  such as `blocks/SECURITY.md/reporting@private.md`; a hidden name's leading dot is written as `_`
  there (`blocks/_github/dependabot.yml/`), since git refuses a folder named `.gitattributes`.
- `tools/manifest`: writes `.github/standard/MANIFEST`. `tools/consumer-suite`: builds a scratch
  consumer that holds only what the MANIFEST vendors, where CI runs the standard's suites again.
  `tests/` holds the tests of `tools/`.

## Status

Phase 1 (hooks and checks) is under review. Phase 2 brings the workflows, the release tools,
`tools/sync` and `tools/status`, and releases version 1.0.0.

## Checks

- `bats .github/standard/tests/hooks.bats` and the other suites, one file at a time on Windows
  (Git Bash); `bats tests/` for `tools/`.
- `sh .githooks/privacy-scan --tracked` and `sh tools/manifest --check`.
- `sh tools/consumer-suite DIR`, then `bats DIR/.github/standard/tests/`: the standard's suites
  where only the vendored files exist, as in a consumer.
- CI (the temporary `bootstrap` workflow) runs every suite on Linux and in Git Bash on Windows,
  then the standard's suites again in a scratch consumer, and fails on any skipped test.
