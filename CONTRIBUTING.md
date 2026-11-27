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
- CI runs `standard` (every suite of the standard on Linux), `test` (Windows: `ci/test`, the
  suites of the code that runs on Windows, then `ci/test.ps1`: the smoke test of the pinned
  PowerShell modules and the Pester tests of the seal dialog), `system` (Linux: the scratch
  consumers, lint included) and `hooks-windows`. It fails on any skipped test. Locally a test may
  skip only for a missing tool, such as actionlint.

## Test data

Every value in a test is synthetic: `example.invalid`, `example-owner`, `192.0.2.x`,
`forbidden-term-example` and blob ids made at run time. Values that look private are built from
fragments at run time, so no file holds one whole. The config enables the `base` pack, with no
exemption and no accepted finding.

## Adopting a repository

A repository adopts the standard once, in one pull request on a branch `chore/standard-X.Y.Z`,
from a clone of the published tag `vX.Y.Z`. `tools/sync --init` writes what it can and its notes
name the rest; these steps cover both. `OWNER`, `NAME`, `TAG-CLONE` and `PATH-TO` stand for the
repository's owner and name, the tag clone's folder and a folder of the maintainer's machine.

1. The maintainer's git setup (below) covers the repository's GitHub URL, so the hooks run in
   every clone of it.
2. On `chore/standard-X.Y.Z` from an up-to-date `main`, write `.github/standard.conf` from
   `templates/standard.conf`, check it with `sh TAG-CLONE/.github/standard/bin/conf --check
   .github/standard.conf`, and commit it alone: the hooks read it from `HEAD`, and `--init`
   refuses a config that is not committed.
3. Clone the tag into a short temporary folder,
   `git clone --depth 1 --branch vX.Y.Z https://github.com/OWNER/repo-standard.git TAG-CLONE`,
   and run `sh TAG-CLONE/tools/sync --init --to .` from the repository's top.
4. Read sync's notes: the lines that repeat a block, where an appended block goes, the
   `CHANGELOG.md` line, blobs above `MAX_BLOB_KB`, and what `standard-check`, `privacy-scan` and
   `release-meta` find in what sync staged. sync adds the dependabot `github-actions` entry at
   `open-pull-requests-limit: 0` itself; the repository's own entries go below it.
5. Write what only the repository knows:
   - `ci/<stage>` for each stage in `CI_STAGES`, from `templates/ci/<stack>/`;
   - `tests/helpers.bash` from `templates/tests/helpers.bash`, so the tests source the standard's
     `lib.bash` first;
   - a root `VERSION` (`X.Y.Z` or `X.Y.Z-dev`; `VERSION_COPY` keeps other copies equal), and
     `CHANGELOG.md` in the form of `templates/CHANGELOG.md` with sync's line under `### Changed`;
   - the sections of `CONTRIBUTING.md` and `SECURITY.md` around the blocks, in the order that
     `templates/` shows, and the README's text about the repository's CI.
6. Delete what the standard replaces:
   - files in `.githooks/`, `.github/standard/` and `.github/workflows/` that the MANIFEST does not
     list, an old `tests.yml` among them, and `.gitleaks.toml`;
   - the repository's own tests of an older privacy scan;
   - lines of `.gitattributes` and `.editorconfig` that repeat a block.
7. Test values go into the synthetic ranges of Test data in the repository's `CONTRIBUTING.md`
   (`192.0.2.x`, `example-`, `*.invalid`, `5ca1ab1e`), or are built from fragments at run time.
   A real value is replaced, never accepted.
8. Run until clean: `sh .github/standard/bin/standard-check --local`,
   `sh .githooks/privacy-scan --tracked`, `git tag -l 'v*' | bash .github/standard/bin/release-meta
   check`, and the repository's own tests. Then commit, push and open the pull request; CI must
   pass.
9. After the merge, the maintainer applies the GitHub settings that `tools/status` checks, one
   `gh` line each:
   - `gh api --method PATCH repos/OWNER/NAME -F allow_squash_merge=true -F allow_merge_commit=false
     -F allow_rebase_merge=false -f squash_merge_commit_title=PR_TITLE -f
     squash_merge_commit_message=COMMIT_MESSAGES -F delete_branch_on_merge=true -F
     allow_auto_merge=false`
   - `gh api --method PUT repos/OWNER/NAME/actions/permissions/workflow -f
     default_workflow_permissions=read -F can_approve_pull_request_reviews=false`
   - `gh api --method PUT repos/OWNER/NAME/immutable-releases`
   - `gh api --method PUT repos/OWNER/NAME/vulnerability-alerts`
   - `gh api --method PUT repos/OWNER/NAME/automated-security-fixes`
   - `gh api --method PUT repos/OWNER/NAME/actions/permissions -F enabled=true -f
     allowed_actions=selected -F sha_pinning_required=true`
   - `gh api --method PUT repos/OWNER/NAME/actions/permissions/selected-actions --input
     TAG-CLONE/templates/github/selected-actions.json`
   - a public repository only: `gh api --method PATCH repos/OWNER/NAME -f
     'security_and_analysis[secret_scanning][status]=enabled' -f
     'security_and_analysis[secret_scanning_push_protection][status]=enabled'`
   - a public repository only: `gh api --method POST repos/OWNER/NAME/rulesets --input
     TAG-CLONE/templates/github/ruleset.json`
10. A repository that seals does so only once it is public, in this order: the repository is
    public; the tag ruleset, `gh api --method POST repos/OWNER/NAME/rulesets --input
    TAG-CLONE/templates/github/seal-ruleset.json`; then `SEAL=yes` in a `chore/standard-X.Y.Z`
    pull request. `conf` refuses `SEAL=yes` in a private repository.
11. `tools/status` reads the repository, with `--clones NAME=CLONE` for the maintainer's clone;
    every line should say `ok`. Delete the tag clone.

### The maintainer's git setup

The hooks and the denylists come from the maintainer's global git configuration, never from a
repository. One included file holds the settings:

```
[core]
    hooksPath = .githooks
[privacy]
    requireDenylist = true
    denylist = PATH-TO/denylist
```

The denylist is a file of fixed terms, one per line, that never leaves the machine. The global
configuration loads the included file for each repository of the standard, with one line for
each form of its GitHub URL:

```
[includeIf "hasconfig:remote.*.url:https://github.com/OWNER/NAME.git"]
    path = PATH-TO/standard.gitconfig
[includeIf "hasconfig:remote.*.url:https://github.com/OWNER/NAME"]
    path = PATH-TO/standard.gitconfig
[includeIf "hasconfig:remote.*.url:git@github.com:OWNER/NAME.git"]
    path = PATH-TO/standard.gitconfig
[includeIf "hasconfig:remote.*.url:git@github.com:OWNER/NAME"]
    path = PATH-TO/standard.gitconfig
```

`git config --global 'includeIf.hasconfig:remote.*.url:https://github.com/OWNER/NAME.git.path'
PATH-TO/standard.gitconfig` writes the first; the other three follow the same way.
`tools/status --clones` checks each clone: the hooks on, `privacy.requireDenylist` on, the
includeIf lines, and the number of denylist terms, never a term.

## Changing the standard

1. A change is a pull request here, from a branch off `main`, with a CHANGELOG line, the tests
   that prove it, and the MANIFEST rebuilt with `sh tools/manifest`. It also rewrites the blocks
   in this repository's own documents from `blocks/`; stage what it names.
2. No copy names the owner; CI checks it.
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

1. `.github/standard/bin/release-prepare` writes the release pull request `chore/release-X.Y.Z`:
   `VERSION`, the `VERSION_COPY` files, and the `CHANGELOG.md` section with its links. Its body
   names the dependency updates since the last release. CI checks the version, the date and the
   links. For a zip, tar or stack release, the `release` workflow builds it twice and compares
   the builds.
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
automation publishes a release, or edits or deletes a published one.
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
4. For each repository with `SEAL=yes`, a shortcut "Seal NAME release" in `FOLDER` itself, beside
   the three files and outside every clone, with the target
   `powershell.exe -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File
   "FOLDER\release-seal.ps1" -Repo OWNER/NAME`.

The tool fetches into `FOLDER/mirrors/`, where no hook runs, asks the passphrase only in its own
dialog, verifies each new seal for `maintainer` before the push, and pushes `seal/vX.Y.Z` alone,
never with force.
