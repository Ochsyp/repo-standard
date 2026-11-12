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

[Unreleased]: https://github.com/Ochsyp/repo-standard/commits/main
