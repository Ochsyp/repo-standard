## Releasing

GitHub Actions builds each release, and the maintainer publishes it in the browser, then seals
it: the maintainer's own hosts install a sealed release only. Anyone else downloads and installs
a release without a seal.

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
4. Then the maintainer seals the release. Double-click this repository's seal shortcut and check
   what the dialog shows: the version, its commit, the release pull request, the commits since
   the last seal and each check the tool ran. Click **Seal** and type the passphrase of the
   offline signing key. The tool pushes the annotated, SSH-signed tag `seal/vX.Y.Z` on the
   release's commit, from a mirror of its own; `pre-push` refuses `refs/tags/seal/*` from every
   clone.
5. To fix a draft, merge a pull request from `fix/release-X.Y.Z-<slug>`; its `CHANGELOG.md` line
   goes into `## [X.Y.Z]`. Then run the `release` workflow on `main` (Actions, release, Run
   workflow). Merge nothing else until the draft is published: CI says so on every pull request
   while a release waits.
6. Never delete a published release, and never move or delete a seal: a host stops on a seal
   that moved. A tag ruleset enforces it: target tags, `refs/tags/seal/*`, the rules deletion
   and update, no bypass. It leaves creating a seal open. The maintainer sets it once, when the
   repository starts to seal. To stop a release before its seal, leave it unsealed and tick
   **Set as a pre-release**, so repo-standard's `tools/status` stops asking for its seal; then
   ship X.Y.Z+1. To stop a sealed release, use the hold that the Release contract names, and ship
   X.Y.Z+1. For a container image, the pre-release tick also moves `latest` back.

Only the maintainer publishes a release. No one creates a release tag or a seal by hand, and no
script or automation publishes a release, or edits or deletes a published one.
