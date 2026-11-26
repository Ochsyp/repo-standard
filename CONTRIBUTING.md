# Contributing

repo-standard holds the standard that the owner's repositories share, and one maintainer runs it.
Its own changes follow the rules of every repository of the standard.

<!-- standard:begin workflow -->
## Workflow

Every change reaches `main` through a pull request that the maintainer reviews and merges. This
holds for the maintainer too.

1. Branch from an up-to-date `main`: `phase/<n>-<slug>` for a phase of the plan, or `fix/`,
   `feat/`, `docs/` or `chore/` plus a short slug.
2. Write commit messages and the pull request title as Conventional Commits (`feat:`, `fix:`,
   `docs:`, `chore:`, `ci:`, `test:`, `refactor:`).
3. Add a line under `## [Unreleased]` in `CHANGELOG.md`. Three kinds of pull request add none
   there: a release pull request (`chore/release-X.Y.Z`), which moves the lines into the new
   version; the fix of a draft release (`fix/release-X.Y.Z-<slug>`), whose line goes into that
   version's section; and a Dependabot pull request, whose updates the next release pull request
   sums up.
4. Run the checks in Checks below, and fix what they find.
5. Push the branch and open a pull request against `main`. Before every `gh pr create` and
   `gh pr edit`, run `.github/standard/bin/pr-text` on the title and the body: it refuses
   denylist terms and rule pack hits, and never prints them.
6. Start the next phase only after the pull request is merged.

One pull request holds one phase or one change.

Repository work happens only on a machine with the maintainer's git configuration, never in a
hosted environment such as a codespace or a cloud workspace. That configuration turns the hooks
on and loads the denylists for every clone of this repository's GitHub URL. A clone made from a
local path gets no hooks, so run `git config core.hooksPath .githooks` in it right after cloning.

An outside contributor's pull request is reviewed in the browser and through CI. Hooks run from
the checked-out tree with the maintainer's credentials, even during a fetch, so:
- never check out a fork's pull request branch in a clone with the hooks on;
- clone a fork only with `git clone <fork URL>` or `gh repo clone <fork> <folder> --no-upstream`,
  into a scratch folder, and never add a remote for this repository there.
<!-- standard:end workflow -->

<!-- standard:begin guard-rails -->
## Guard rails

GitHub's ruleset on `main` blocks direct pushes, force pushes and its deletion, and the merge
of a pull request whose `all-passed` or `scan` check failed.

The hooks in `.githooks/` guard every commit and push:
- `pre-commit` refuses a commit while `main` or `master` is checked out. It also refuses a changed
  copy of the standard, a staged file above `MAX_BLOB_KB`, and staged content, path names, author
  or committer that hold a denylist term or a rule pack hit. `pre-merge-commit` does the same for
  a merge.
- `commit-msg` refuses such a term or hit in the message.
- `pre-push` refuses a push to `main` or `master`, and a branch or tag name with a term or hit. It
  refuses every tag push except a `v*` tag under `RELEASE_KIND=legacy`; otherwise release tags
  come from publishing a release. It also refuses a term or hit in what the pushed commits bring
  in, which covers rebase, cherry-pick and `am` too.

The denylists hold names that must never be committed and never leave the maintainer's machine.
The rule packs in `.githooks/rules/` hold the patterns: private addresses, local host names, MAC
addresses, home paths and e-mail addresses, and disk and VM identifiers where the config enables
them. A refusal names the file, the line and the kind of finding, never the value.

The maintainer's git configuration turns the hooks on for every clone of this repository's GitHub
URL. Anywhere else, such as a clone made from a local path, turn them on once after cloning:
`git config core.hooksPath .githooks`. Never use `--no-verify`.
<!-- standard:end guard-rails -->

## Checks

- `bats .github/standard/tests/FILE.bats` for a suite of the standard, one file at a time in Git
  Bash on Windows, and `bats tests/` for the tests of `tools/`.
- `sh .githooks/privacy-scan --tracked`, `sh tools/manifest --check` and
  `sh .github/standard/bin/standard-check --local`.
- `sh tools/consumer-suite [--shape private] DIR`, then the standard's suites in DIR: they must
  pass where only the vendored files exist.
- On Windows, the tests of the seal dialog: `.github/standard/bin/install-tools pester
  psscriptanalyzer`, the folder `modules` beside the printed one first on `PSModulePath`, then
  `powershell.exe -NoProfile -File ci/test.ps1`.
- CI runs `standard` (every suite of the standard on Linux), `test` (Windows: `ci/test`, then
  `ci/test.ps1`: the smoke test of the pinned PowerShell modules and the Pester tests of the seal
  dialog), `system` (Linux: the scratch consumers, lint included) and `hooks-windows`. It fails
  on any skipped test. Locally a test may skip only for a missing tool, such as actionlint.

## Test data

Every value in a test is synthetic: `example.invalid`, `example-owner`, `192.0.2.x`,
`forbidden-term-example` and blob ids made at run time. Values that look private are built from
fragments at run time, so no file holds one whole. The config enables the `base` pack, with no
exemption and no accepted finding.

## Changing the standard

1. A change is a pull request here, from a branch off `main`, with a CHANGELOG line, the tests
   that prove it, and the MANIFEST rebuilt with `sh tools/manifest`. It also rewrites the blocks
   in this repository's own documents from `blocks/`; stage what it names.
2. No copy, no block and no template names a repository of `config/private-names`, and no copy
   names the owner; CI checks both.
3. Changes collect on `main` until a release pull request (`chore/release-X.Y.Z`, written with
   `.github/standard/bin/release-prepare`) raises `VERSION`. PATCH: fixes, pins and new pack
   rules. MINOR: new optional keys or features. MAJOR: a repository must change a file of its
   own.
4. After the owner publishes a release, each repository syncs when its owner next works on it:
   `tools/sync`, run from a clone of the published tag, writes it into a worktree on
   `chore/standard-X.Y.Z`.

<!-- standard:begin releasing -->
## Releasing

GitHub Actions builds each release, and the maintainer publishes it in the browser.

1. The maintainer opens the release pull request `chore/release-X.Y.Z`, written with
   `.github/standard/bin/release-prepare`: `VERSION`, the `VERSION_COPY` files, and the
   `CHANGELOG.md` section with its links. Its body names the dependency updates since the last
   release. CI checks the version, the date and the links. For a zip, tar or stack release, the
   `release` workflow builds it twice and compares the builds.
2. The maintainer reviews and squash-merges it. The push to `main` that changes `VERSION` runs
   the `release` workflow: the checks of `ci` on that commit, the build, an attestation in the
   public repositories, and a draft release `vX.Y.Z` of that commit.
3. The maintainer checks the draft (notes, assets, target commit, image digest) and clicks
   **Publish release**. GitHub creates the tag and the immutable release. The `verify` job then
   checks the published release, and the maintainer looks for it to pass.
4. To fix a draft, merge a pull request from `fix/release-X.Y.Z-<slug>`; its `CHANGELOG.md` line
   goes into `## [X.Y.Z]`. Then run the `release` workflow on `main` (Actions, release, Run
   workflow). Merge nothing else until the draft is published: CI says so on every pull request
   while a release waits.
5. Never delete a published release. Tick **Set as a pre-release** on a bad one instead, so that
   clients and updaters ignore it, and ship X.Y.Z+1. For a container image, the tick also moves
   `latest` back.

Only the maintainer publishes a release. No one creates a release tag by hand, and no script or
automation publishes, edits or deletes a release.
<!-- standard:end releasing -->

## Release contract

A release `vX.Y.Z` holds:
- `repo-standard-X.Y.Z.tar.gz`, the tree at the tag with the manifest
  `repo-standard-release.json` added;
- the `MANIFEST` asset, byte for byte the `.github/standard/MANIFEST` of the tag;
- the seal tool's `release-seal`, `release-seal-askpass` and `release-seal.ps1`, each byte for
  byte its file in `tools/` of the archive;
- `SHA256SUMS`.

`tools/sync` and `tools/status` trust a release only when it is published and immutable, and
compare each MANIFEST with its asset.

The seal tool runs on the maintainer's Windows PC, outside every clone. It needs Git for Windows
(bash, git, ssh-keygen) and a logged-in `gh`. The maintainer installs or updates it only from a
published, immutable release:

1. `gh release download vX.Y.Z -R OWNER/repo-standard --pattern 'release-seal*' --dir FOLDER`,
   into a folder of its own outside every git work tree.
2. `gh release verify-asset vX.Y.Z FOLDER/FILE -R OWNER/repo-standard` for each of the three
   files; any failure stops the install.
3. `FOLDER/config` with the lines `SIGNING_KEY=` the offline key's private file and
   `ALLOWED_SIGNERS=` the allowed signers file that the hosts trust, principal `maintainer`.
4. For each repository with `SEAL=yes`, a desktop shortcut "Seal NAME release" with the target
   `powershell.exe -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File
   "FOLDER\release-seal.ps1" -Repo OWNER/NAME`.

The tool fetches into `FOLDER/mirrors/`, where no hook runs, asks the passphrase only in its own
dialog, verifies each new seal for `maintainer` before the push, and pushes `seal/vX.Y.Z` alone,
never with force.
