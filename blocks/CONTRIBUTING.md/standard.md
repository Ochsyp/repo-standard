## The repository standard

Files listed in `.github/standard/MANIFEST` are copies of the repository standard. Never edit
them here: change repo-standard, release it, and sync with a `chore/standard-X.Y.Z` pull request.
CI fails when a copy differs or changes on another branch. Sync summaries and pull request texts
here name no other repository. An exemption, an accepted finding or a dropped check comes in a
`chore/privacy-*` pull request of its own.

A repository goes public in this order. A pull request sets `VISIBILITY=public` and brings the
public block texts. The maintainer switches the repository to public on GitHub and turns on the
security settings those texts promise. A new commit on that branch reruns its checks; a rerun
from the Actions page keeps the old private flag. Then that pull request merges before anything
else, since until then `main` says private while GitHub says public.
