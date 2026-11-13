# Changelog

All notable changes to this project are listed here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html). There are no releases yet.

## [Unreleased]

### Added

- The git hooks of the standard: `pre-commit`, `pre-merge-commit`, `commit-msg` (which drops only
  what git's cleanup rules drop: the cut line's tail and, in the strip mode, comment lines) and
  `pre-push`, with full-ref branch guards, the tag rules, a staged-blob size guard and the copy
  guard, and `privacy-scan` (`--staged`, `--tracked`, `--message`, `--range`, `--history`) with
  one NUL-stripped stream and one grep per rule (phase 1)
- The denylist loader in `.githooks/lib.sh`: every `privacy.denylist` list (`--type=path`), the
  per-user and per-clone lists, `privacy.requireDenylist` (`--type=bool`), duplicate lists kept
  once, a configured list without a term counted as missing, terms with a fullwidth at sign read
  as `@`, a relative `$PRIVACY_DENYLIST` read from where the command starts, and lists named only
  as `~/...` or "list N of M" (phase 1)
- The rule packs `base`, `disk` (with the `/dev/disk/by-id/` rule) and `vm`, the fullwidth at
  sign read as `@`, and the `PRIVACY_ALLOW` (one kind per line) and `PRIVACY_HISTORY_ACCEPT`
  limits (phase 1)
- `conf`, `standard-check`, `install-tools`, `no-skips`, `tools/manifest`, the canonical block
  bodies in `blocks/`, and the bats suites `hooks.bats`, `privacy-scan.bats`, `conf.bats`,
  `standard-check.bats`, `lint.bats`, `tests/manifest.bats` and `tests/source-check.bats` with
  their `lib.bash` (phase 1)
- A temporary `bootstrap` workflow that runs the suites on Linux and in Git Bash on Windows
  (phase 1)
- `tools/consumer-suite`, which builds a scratch consumer of a public (MIT, tar) or a private
  (no licence, legacy) shape that holds only what the MANIFEST vendors plus a file of its own;
  `bootstrap` runs the standard's suites in one of each, so a vendored test that needs a file
  only this repository holds, or scans a consumer's own files, fails in CI (phase 1)
- `conf --ci`, which prints what CI runs (runners, stages, image, Windows hook tests, full
  suite, the jobs `all-passed` requires, public, rehearsal) for `$GITHUB_OUTPUT`, and
  `conf --samples`, which prints the realistic values of a pack kind (phase 2)
- `run-stage`, which runs a repository's `ci/<stage>` and then `ci/<stage>.ps1` under Windows
  PowerShell 5.1 from the top of the repository, with the helpers of the standard's tools in
  `bin/lib.bash` (phase 2)
- `pr-text`, which refuses a pull request title that is not a Conventional Commit and runs
  title and body through the hooks' privacy scan, its denylists only through their loader, and
  `pr-title`, which checks the current title and body of a pull request in CI (phase 2)
- `release-meta`, ported from image-backup with the launcher's version rules and the `-dev` rule,
  which checks `VERSION`, `CHANGELOG.md` and the tags and tells whether a release is
  unreleased, pending or released, and `changelog-entry`, which checks the lines a pull request
  adds to `CHANGELOG.md`, with the exceptions for a release, a draft fix and Dependabot (phase 2)
- `secret-scan`, which proves with positive controls that gitleaks and the rule packs still find
  something, checks that accepted findings name old commits only, refuses `.gitleaks.toml`, and
  scans a pull request's or a push's commits, or the whole history, reporting counts and rule
  names only (phase 2)

### Changed

- `install-tools` prints the folder of its tools every time, so a script can use them in the
  same step, and on Windows installs Pester and PSScriptAnalyzer from their pinned PowerShell
  Gallery packages (phase 2)
- `standard-check` names a `VERSION_COPY` problem by its entry, never by its path, and notes in
  CI when GitHub did not say whether the repository is private (phase 2)

[Unreleased]: https://github.com/Ochsyp/repo-standard/commits/main
