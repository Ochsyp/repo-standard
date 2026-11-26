# Changelog

All notable changes to this project are listed here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).
Each version is the GitHub release `vX.Y.Z`.

## [Unreleased]

## [1.3.0] - 2026-11-26

### Added

- `.github/standard/README.md` has a Rules section: the config, `standard-check`'s rules 1 to
  10, the `ci/` interface, the workflow rules, the changelog and the secret scan. Comments and
  messages that pointed to numbered sections of a document outside the repository now point there,
  or name what they mean

### Changed

- The README points to GitHub's Releases page and `CHANGELOG.md` instead of keeping a Status
  section of its own, so a release needs no README pull request afterwards
- Neutral wording in the release steps, the seal tool's install, the release tools' comments and
  `tools/status`'s ruleset message, which now says "the ruleset differs from the standard one"
- The releasing blocks say that the `release` workflow builds twice and compares only for a zip,
  tar or stack release
- `tools/sync --init` refuses a target whose `.github/standard.conf` is not committed, or differs
  from the committed one, since the hooks and `privacy-scan` read the config from HEAD. Commit
  the config on its own before the adoption's sync
- The config template's starter value is `VISIBILITY=public`
- The seal shortcut "Seal NAME release" sits in the seal tool's own install folder, outside every
  clone, not on the desktop
- repo-standard's Windows test stage runs only the suites of the code that runs on Windows:
  `conf.bats`, the `run-stage` and `install-tools` tests and the seal tool's suites. Every suite
  still runs on Linux. `ci/test.ps1` reads the pinned Pester and PSScriptAnalyzer versions from
  `install-tools`
- The SECURITY.md, guard-rails and releasing blocks, `secret-scan` and the README no longer
  promise a daily check: the maintainer checks regularly with repo-standard's `tools/status`

### Removed

- `config/private-names` and its checks: `standard-check`'s rule 9 part in repo-standard,
  `tools/sync`'s four refusals and `tools/status`'s `names` check. The denylists and the hooks
  remain the guard for names that must never be written. `tools/sync` now runs from a release
  clone without the file

## [1.2.0] - 2026-11-25

### Added

- `privacy-scan --history` names, under each finding in a file, the commits behind it: one line
  per version of the file that holds the hit, with the full SHAs of the commits whose
  `PRIVACY_HISTORY_ACCEPT` record would accept that version. Those that HEAD holds come first,
  and the others are marked as outside HEAD, since the secret scan refuses a record whose commit
  is not in the base. A version that only a merge or a ref brings in gets a line that says no
  commit can, and a denylist finding gets none. A record for any one of them accepts that
  version, once the value is checked as synthetic. Other scans, exit codes and the finding lines
  are unchanged
- The seal tool's seventh check, `configured`: `.github/standard.conf` at the release's commit
  must set `SEAL=yes`, exactly once. A release of a repository without the seal, one made before
  its repository set `SEAL=yes`, or one whose config is missing or unreadable fails the check, so
  `seal` refuses it and the dialog leaves **Seal** off. A later `SEAL=yes` on main does not make an
  older release sealable. `versions` still lists every release

### Changed

- The README's status names 1.1.0 as published, with the seal
- In repo-standard (`ROLE=source`), `standard-check` also checks the blocks in its own documents:
  markers that are there must hold the body in `blocks/` that the config selects, once and in
  order, and a document may leave a block out. The pre-commit hook runs the check when a commit
  stages `blocks/`, such a document or the config, and `sh tools/manifest` rewrites those blocks
  from `blocks/`. Its notice on a stale MANIFEST says to run `sh tools/manifest`. Consumers are
  unchanged
- The `base` pack's host-name rule exempts a label that goes on with a hyphen and a letter only
  after `.local`, as in a folder name `x.local-tools`. After `.lan`, `.internal`, `.home.arpa`
  and `.ts.net` such a name is a host name again, reported with the same value as in 1.0.1, so a
  host name followed by a hyphen and a word, such as `<host>.lan-backup`, no longer passes.
  Tracked text that holds one fails the scan at the sync. Rename a real host name; only a name
  that is no host may be exempted, with a `PRIVACY_ALLOW` line in a `chore/privacy-*` pull
  request, since the line names its value
- Plain writing of the shared text: the block bodies and the comments of the copied hooks, tools
  and tests say the same in shorter sentences, one idea each. The going-public paragraph of the
  block `standard` adds that `tools/sync` writes the public block texts, that the maintainer also
  turns on the ruleset, and that CI on `main` and `tools/status` fail until the pull request
  merges. The block `guard-rails@public` says that the ruleset blocks direct pushes and the merge
  of a pull request whose `all-passed` or `scan` check failed, without the wait for an update.
  No command, check or exit code changes
- Plain writing of repo-standard's own text: README, CONTRIBUTING and SECURITY outside the blocks,
  and the comments in `tools/`, `ci/` and `tests/`. The block `SECURITY.md#sealed-releases@seal`
  also names the seal tool's check that the config at the release's commit sets `SEAL=yes`

## [1.1.0] - 2026-11-24

### Added

- The key `SEAL` (`yes` or `no`, default `no`; never with `RELEASE_KIND=legacy`) and the profile
  `seal`: under `SEAL=yes` the block `CONTRIBUTING.md#releasing@seal` replaces `releasing` with
  the Seal step, and `SECURITY.md#sealed-releases@seal` says what the hosts check. `standard-check`
  and `tools/sync` select them, and without `SEAL=yes` a block that exists only as a seal variant
  must be absent. A repository that sets `SEAL=yes` adds the markers of `sealed-releases` to its
  `SECURITY.md` first (phase 3)
- `tools/release-seal`, the seal tool: `check` shows a published release's checks and
  facts, and `seal` signs the annotated tag `seal/vX.Y.Z` with the offline SSH key through
  `SSH_ASKPASS` only, verifies it for `maintainer` and pushes that one tag, without force, from a
  mirror of its own where no hook runs; `gh` only reads (phase 3)
- `tools/release-seal.ps1`, its dialog in Windows PowerShell 5.1 with Windows Forms, which enables
  Seal only when every check passed, and `tools/release-seal-askpass`, which shows its masked
  passphrase dialog for ssh-keygen. The three files are assets of each release, and
  `ci/test.ps1` runs their Pester tests (phase 3)
- The check `seal` of `tools/status`: the newest release that the release workflow drafted in a
  `SEAL=yes` repository warns for 24 hours without its seal, then fails; a seal off its
  release's commit, with another message, unannotated, moved or vanished fails; with
  `--allowed-signers FILE`, each seal must verify for `maintainer` in the sweep's mirror
  (phase 3)
- `tools/sync --init` prints on stderr what an adoption must still fix by hand: lines that repeat
  a configuration block, a github-actions entry that is missing or lacks limit 0, a
  `dependabot.yaml` beside `dependabot.yml`, each Markdown block appended at the end, where an
  older section on the same topic may stand beside it, the CHANGELOG line and a missing Checks
  section. The notes never quote the repository's own text, and the pull request text stays the
  same
- `tools/sync --init` and `standard-check --local` give a notice for each tracked blob above the
  `MAX_BLOB_KB` of HEAD, which is the limit the hooks apply, by id and size, with the git command
  that finds its file, and for a blob they cannot read. The notice says to raise the limit first
  in a commit of its own, and in a `chore/privacy-*` pull request once the config is on `main`.
  The size guard and every exit code stay as they are

### Changed

- The shared block `CONTRIBUTING.md#standard` gives the order in which a repository goes public:
  a pull request with `VISIBILITY=public` and the public block texts, the switch on GitHub with
  the security settings those texts promise, a new commit that reruns its checks, then that merge
  before any other

### Fixed

- `privacy-scan` reports a hit in a blob that a tag or another ref names directly. Such a blob has
  no path, and the scan dropped its hits, also when the same blob was a committed file, so
  `pre-push` and the history scan let it through. The finding names the blob, and a
  `PRIVACY_ALLOW` path of `^$` does not exempt it
- The words the first adoption found wrong or missing. The guard-rails blocks name the `v*` tag
  that a legacy repository may push, and the public one says when the full ruleset starts.
  `release-meta` and `standard-check` name the right file in two messages. The `dependabot.yaml`
  note of `tools/sync --init` warns against a duplicate entry, and its Checks note no longer
  names a step number. The config template explains `PRIVACY_ALLOW` and `MAX_BLOB_KB`, and the
  PowerShell starter names the privileges it holds on a Windows runner. The pull request checklist
  still asks that no test was skipped, and says that `no-skips` reads bats output only
- The rule pack `base` lets GitHub's support address of every Dependabot sign-off through, so a
  Dependabot pull request, its merge and the history scan no longer fail on it; any other
  address at github.com still hits. The host-name rule no longer reads a last label that goes on
  from `lan`, `local`, `internal`, `home.arpa` or `ts.net` with a hyphen and a letter, such as
  the folder name `x.local-tools-old`, as a host name; real names under those suffixes, also
  with a hyphen and a digit after them, hit as before
- repo-standard is public, so its config says `VISIBILITY=public`, which ends the red `ci` on
  `main`, and its own SECURITY.md and CONTRIBUTING.md carry the public variants of the
  reporting, automated-checks and guard-rails blocks. A test in `tests/source-check.bats` holds
  those blocks to the config, since no sync writes the source's own documents

## [1.0.1] - 2026-11-14

### Fixed

- The verify job of `release.yml` checks out `.githooks/` too: `release-verify` reads the config
  through `conf`, which needs the rule packs, so the check of a published release failed. The
  v1.0.0 release itself is sound. `tests/release-flow.bats` runs the tools of the draft, promote
  and verify jobs in the sparse checkouts that release.yml gives them
- `release-prepare` stages `VERSION` before it rebuilds the MANIFEST in repo-standard, so the
  MANIFEST of a release names its version
- The test job of `ci.yml` fetches the tags, so a suite that checks the repository's release
  state, as `release-meta.bats` does, sees a published release as published

## [1.0.0] - 2026-11-14

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
- `tools/consumer-suite`, which builds a scratch consumer of a public (MIT, tar) or a private
  (no licence, legacy) shape that holds only what the MANIFEST vendors plus a file of its own;
  CI runs the standard's suites in one of each, so a vendored test that needs a file only this
  repository holds, or scans a consumer's own files, fails in CI (phase 1)
- `conf --ci`, which prints what CI runs (runners, stages, image, Windows hook tests, full
  suite, the jobs `all-passed` requires, public, rehearsal) for `$GITHUB_OUTPUT`, and
  `conf --samples`, which prints the realistic values of a pack kind (phase 2)
- `run-stage`, which runs a repository's `ci/<stage>` and then `ci/<stage>.ps1` under Windows
  PowerShell 5.1 from the top of the repository, with the helpers of the standard's tools in
  `bin/lib.bash` (phase 2)
- `pr-text`, which refuses a pull request title that is not a Conventional Commit and runs
  title and body through the hooks' privacy scan, its denylists only through their loader, and
  `pr-title`, which checks the current title and body of a pull request in CI (phase 2)
- `release-meta`, the release checks with the version rules and the `-dev` rule, which checks
  `VERSION`, `CHANGELOG.md` and the tags and tells whether a release is unreleased, pending or
  released, and `changelog-entry`, which checks the lines a pull request adds to `CHANGELOG.md`,
  with the exceptions for a release, a draft fix and Dependabot (phase 2)
- `secret-scan`, which proves with positive controls that gitleaks and the rule packs still find
  something, checks that accepted findings name old commits only, refuses `.gitleaks.toml` and
  ignores inline allow markers, and scans a pull request's or a push's commits, or the whole
  history, reporting counts and rule names only (phase 2)
- The release tools: `release-prepare` writes a release pull request's `VERSION`, `VERSION_COPY`
  files, CHANGELOG section and links and prints its body; `release-build` builds the archive
  twice and compares the builds byte for byte, or writes the image kind's `image.json`;
  `release-draft` drafts a release from the tip of `main` only, never over a published release
  or a tag without one; `release-promote` gives an image's digest its version tag and `latest`;
  and `release-verify` checks a published release without changing anything (phase 2)
- The standard's workflows: `ci` (the `standard` job, the `lint`, `test` and `system` stages,
  `image`, `hooks-windows` and the `all-passed` gate), `secret-scan`, `release` (dry run, checks,
  build, attestation, draft, promote, verify) and `image`, with `actions.allow` and
  `workflows.bats`, which holds them to the pin, permission, token and contract rules (phase 2)
- repo-standard's own `LICENSE` (the MIT text of the standard's repositories),
  `.github/dependabot.yml` with the active `github-actions` entry, the pull request template,
  `.github/standard/README.md`, and `config/private-names`, the private repositories that no
  copy or block may name (phase 2)
- `ci/system`, the Linux stage: the tests of `tools/`, then the standard's suites, lint included,
  in both scratch consumers; and `ci/test.ps1`, a smoke test of the pinned Pester and
  PSScriptAnalyzer (phase 2)
- Tests that no copy and no block names the repository's owner, `LICENSE` aside, and that
  `bats --count` honours `--filter-tags` (phase 2)
- `templates/`, the starters of an adoption: a config that shows every key, `CHANGELOG.md`,
  `CONTRIBUTING.md` and `SECURITY.md` with the markers of their blocks, `tests/helpers.bash`, and
  `ci/` starters for shell, PowerShell, Python and the image kind, each checked by
  `tests/templates.bats` (phase 2)
- `tools/sync`, which writes a published release into a repository's worktree from a clone of
  its tag: it refuses a draft, a mutable release, a clone off the tag, a MANIFEST unlike the
  asset and any text that names a private repository; it writes `.githooks/` first, then the
  copies with their modes and the blocks between their markers, deletes what the release drops,
  and prints the pull request text; `--init` adopts a repository that has its config (phase 2)
- `tools/status`, the read-only daily audit: per repository the standard's version and asset,
  the settings, CI health, direct pushes and private names; with `--clones` the hooks and the
  denylist counts; with `--sweep` a denylist scan of every new commit, pull request text and
  release note in mirrors of its own; once per run the pins' advisories and newer releases, and
  token expiry. It prints one `<repo> <check> ok|warn|FAIL <reason>` line per check, never a
  path or a term, and its `gh` wrapper only reads (phase 2)
- repo-standard's own `CONTRIBUTING.md`, with the workflow, guard-rails and releasing blocks and
  its sections Checks, Test data, Changing the standard and Release contract, and `SECURITY.md`,
  with the reporting and automated-checks blocks and its trust model (phase 2)

### Changed

- `install-tools` prints the folder of its tools every time, so a script can use them in the
  same step, and on Windows installs Pester and PSScriptAnalyzer from their pinned PowerShell
  Gallery packages (phase 2)
- `standard-check` names a `VERSION_COPY` problem by its entry, never by its path, and notes in
  CI when GitHub did not say whether the repository is private (phase 2)
- `standard-check` also holds repo-standard's `templates/` to the private names, since
  `tools/sync --init` copies them into a repository (phase 2)
- `lint.bats` also finds an image without a digest in an `image=` option, and runs actionlint,
  which may report only the `ubuntu-26.04` runner label it does not know yet (phase 2)
- repo-standard's CI runs `test` on Windows: `ci/test` runs the tests of `tools/` and the
  standard's suites in Git Bash, the lint aside, and `ci/system` runs the scratch consumers on
  Linux; the config sets `CI_RUNNER=windows`, `CI_STAGES=test system` and `PS_MODULES` (phase 2)
- `tools/consumer-suite` builds from the tree with `tools/manifest --print`, and gives each
  consumer a `VERSION` and a `CHANGELOG.md`, and the private shape release workflows of its own
  that the general rules accept (phase 2)
- `tests/manifest.bats` lints every shell script that git tracks in `tools/`, `ci/` and
  `tests/`, and leaves the workflow lines out of the MANIFEST self-check, so a Dependabot pull
  request passes; `standard-check` still holds the release pull request to the whole MANIFEST
  (phase 2)

[Unreleased]: https://github.com/Ochsyp/repo-standard/compare/v1.3.0...HEAD
[1.3.0]: https://github.com/Ochsyp/repo-standard/compare/v1.2.0...v1.3.0
[1.2.0]: https://github.com/Ochsyp/repo-standard/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/Ochsyp/repo-standard/compare/v1.0.1...v1.1.0
[1.0.1]: https://github.com/Ochsyp/repo-standard/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/Ochsyp/repo-standard/releases/tag/v1.0.0
