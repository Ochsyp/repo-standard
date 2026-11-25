# Security

repo-standard is public, and one maintainer runs it. Its files run in every repository of the
standard: the hooks on the maintainer's machine, the tools and workflows in GitHub Actions.

<!-- standard:begin reporting -->
## Reporting a vulnerability

Report a vulnerability through GitHub's private vulnerability reporting: the **Security** tab,
then **Report a vulnerability**. Do not open a public issue.
<!-- standard:end reporting -->

## Trust model

The standard trusts GitHub, the actions of `.github/standard/actions.allow` pinned by commit, and
the tools that `install-tools` checks by version and SHA-256. A repository takes a release of the
standard only when it is published and immutable and its MANIFEST equals the release's asset.

## Known exposure

A change here reaches every repository at its next sync. The owner's review of each pull request
here, of the release pull request and of each sync pull request is the gate; no session publishes
a release.

The seal tool is code from this repository that runs with the offline release key. A stolen
token that pushed to `main` here and published a release could offer a changed tool, so the
managing session installs a new version only from a verified asset and only after the owner's
OK, and `tools/status` reports direct pushes. The tool itself reads GitHub with `gh`, GET only;
asks the key's passphrase only in its own dialog, with no ssh agent; fetches into mirrors of its
own, where no hook runs and no file of a repository is run; verifies each new seal for
`maintainer` against the hosts' allowed signers before the push; and pushes that one tag, never
with force, so it cannot move a seal.

## Network

The hooks make no connection. CI downloads the pinned tools and actions. `tools/sync` and
`tools/status` read GitHub with `gh`, GET only. The seal tool reads the same way, fetches the
repository it seals and pushes one tag to it.

## Data that stays private

The denylists stay on the maintainer's machine; the hooks and the tools print counts and kinds,
never a term or a matched value. `config/private-names` is never vendored, and no copy names a
private repository.

<!-- standard:begin automated-checks -->
## Automated checks

- **Secret scan.** The `secret-scan` workflow runs gitleaks (MIT, pinned by version and SHA-256,
  always with its default rules) and this repository's rule packs. It scans the commits of each
  pull request and each push to `main`, and the whole history every Monday and when run by hand.
  Positive controls run first, so a scanner that finds nothing fails. Findings are redacted.
  GitHub's secret scanning and push protection are on as well. GitHub turns the Monday run off
  after 60 days without activity in this repository.
- **Hooks.** The hooks in `.githooks/` check every commit and push on the maintainer's machine:
  content, path names, messages, ref names and identities, against the rule packs and a denylist
  that never leaves that machine. The maintainer also checks every day what reached GitHub, pull
  request texts and release notes included.
- **CI and releases.** The `ci` workflow checks the standard's copies, the privacy rules over the
  tree, the version, the changelog and the pull request, and runs the tests. The `release`
  workflow builds, attests and drafts each release, and verifies it once it is published.
- **Dependencies.** Dependabot watches the ecosystems in `.github/dependabot.yml`, with security
  updates on.

If a secret is ever committed, rotate it first, then remove it from the history.
<!-- standard:end automated-checks -->
