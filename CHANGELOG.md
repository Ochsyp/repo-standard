# Changelog

All notable changes to this project are listed here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html). There are no releases yet.

## [Unreleased]

### Added

- The git hooks of the standard: `pre-commit`, `pre-merge-commit`, `commit-msg` and `pre-push`
  with full-ref branch guards, the tag rules, a staged-blob size guard and the copy guard, and
  `privacy-scan` (`--staged`, `--tracked`, `--message`, `--range`, `--history`) with one
  NUL-stripped stream and one grep per rule (phase 1)
- The denylist loader in `.githooks/lib.sh`: every `privacy.denylist` list (`--type=path`), the
  per-user and per-clone lists, `privacy.requireDenylist` (`--type=bool`), duplicate lists kept
  once, and lists named only as `~/...` or "list N of M" (phase 1)
- The rule packs `base`, `disk` (with the `/dev/disk/by-id/` rule) and `vm`, and the
  `PRIVACY_ALLOW` and `PRIVACY_HISTORY_ACCEPT` limits (phase 1)
- `conf`, `standard-check`, `install-tools`, `no-skips`, `tools/manifest`, the canonical block
  bodies in `blocks/`, and the bats suites `hooks.bats`, `privacy-scan.bats`, `conf.bats`,
  `standard-check.bats`, `lint.bats` and `tests/manifest.bats` with their `lib.bash` (phase 1)
- A temporary `bootstrap` workflow that runs the suites on Linux and in Git Bash on Windows
  (phase 1)

[Unreleased]: https://github.com/Ochsyp/repo-standard/commits/main
