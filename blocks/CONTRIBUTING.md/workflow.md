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
cloud session. That configuration turns the hooks on and loads the denylists for every clone of
this repository's GitHub URL. A clone made from a local path gets no hooks, so run
`git config core.hooksPath .githooks` in it right after cloning.

An outside contributor's pull request is reviewed in the browser and through CI. Hooks run from
the checked-out tree with the maintainer's credentials, even during a fetch, so:
- never check out a fork's pull request branch in a clone with the hooks on;
- clone a fork only with `git clone <fork URL>` or `gh repo clone <fork> <folder> --no-upstream`,
  into a scratch folder, and never add a remote for this repository there.
