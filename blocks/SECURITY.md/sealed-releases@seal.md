## Sealed releases

Hosts install a release of this repository only when the maintainer has sealed it. A seal is an
annotated tag `seal/vX.Y.Z` with the message `<repository> vX.Y.Z`, signed with the
maintainer's offline SSH key, on the commit of the published release `vX.Y.Z`. The maintainer
seals after the publish, with a seal tool that first checks the release: published, immutable,
neither a draft nor a pre-release, drafted by GitHub Actions, its commit on `main`, and its
`verify` run green.

A host checks the seal with `git verify-tag` against its own root-owned list of allowed signers,
and checks its message, that the seal and `vX.Y.Z` name the same commit, that this commit is on
`main`, that no tag it has seen has moved, and that the version is newer. It needs no GitHub
token for this and calls no API. A stolen GitHub token or session can publish a release but
cannot seal it, so no host installs that release. A seal never moves and is never deleted; a
release that must not be installed stays unsealed, or is held on the hosts as the Release
contract in `CONTRIBUTING.md` says.
