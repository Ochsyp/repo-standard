## Automated checks

- **Secret scan.** GitHub offers no secret scanning for this private repository, so the
  `secret-scan` workflow is its only server-side secret scanner. It runs gitleaks (MIT, pinned by
  version and SHA-256, always with its default rules) and this repository's rule packs. It scans
  the commits of each pull request and each push to `main`, and the whole history every Monday
  and when run by hand. Positive controls run first, so a scanner that finds nothing fails.
  Findings are redacted.
- **Hooks.** The hooks in `.githooks/` check every commit and push on the maintainer's machine:
  content, path names, messages, ref names and identities, against the rule packs and a denylist
  that never leaves that machine. The maintainer also checks regularly, with repo-standard's
  `tools/status`, what reached GitHub, pull request texts and release notes included.
- **CI and releases.** The `ci` workflow checks the standard's copies, the privacy rules over the
  tree, the version, the changelog and the pull request, and runs the tests. The `release`
  workflow builds and drafts each release, and verifies it once it is published.
- **Dependencies.** Dependabot watches the ecosystems in `.github/dependabot.yml`, with security
  updates on.

If a secret is ever committed, rotate it first, then remove it from the history.
