## Releasing

GitHub Actions builds each release, and the maintainer publishes it in the browser.

1. The maintainer opens the release pull request `chore/release-X.Y.Z`, written with
   `.github/standard/bin/release-prepare`: `VERSION`, the `VERSION_COPY` files, and the
   `CHANGELOG.md` section with its links. Its body names the dependency updates since the last
   release. CI checks the version, the date and the links. The `release` workflow builds the
   release twice and compares the builds.
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
