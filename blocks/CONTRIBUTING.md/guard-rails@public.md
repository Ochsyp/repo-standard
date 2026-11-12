## Guard rails

GitHub's ruleset on `main` blocks force pushes and its deletion. From this repository's
adoption of the standard on, it also blocks direct pushes, and the merge of a pull request whose
`all-passed` or `scan` check failed.

The hooks in `.githooks/` guard every commit and push:
- `pre-commit` refuses a commit while `main` or `master` is checked out, a changed copy of the
  standard, a staged file above `MAX_BLOB_KB`, and staged content, path names, author or
  committer that hold a denylist term or a rule pack hit. `pre-merge-commit` does the same for a
  merge.
- `commit-msg` refuses such a term or hit in the message.
- `pre-push` refuses a push to `main` or `master`, every tag push (release tags come from
  publishing a release), a branch or tag name with a term or hit, and what the pushed commits
  bring in, which covers rebase, cherry-pick and `am` too.

The denylists hold names that must never be committed and never leave the maintainer's machine.
The rule packs in `.githooks/rules/` hold the patterns: private addresses, local host names, MAC
addresses, home paths, e-mail addresses, and disk and VM identifiers where the config enables
them. A refusal names the file and line and the kind of finding, never the value.

The maintainer's git configuration turns the hooks on for every clone of this repository's GitHub
URL. In a clone made from a local path, or anywhere else, turn them on once after cloning:
`git config core.hooksPath .githooks`. Never use `--no-verify`.
