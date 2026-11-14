#!/usr/bin/env bats
# release-seal.bats of repo-standard: tools/release-seal, the seal of D1 = B, against the gh stub
# with fixed replies, a bare local origin, and throwaway SSH keys with a passphrase that an
# askpass stub types. The tests source the tool with SEAL_LIB=1 for its jq filters, so each stub
# reply answers exactly the call the tool makes. Every value is synthetic.

# The sh -c scripts are single-quoted, and bats runs each test in a subshell, both on purpose.
# shellcheck disable=SC2016,SC2030,SC2031,SC2034
load helpers

OWNER=example-owner
NAME=example
SLUG=$OWNER/$NAME
PASS='correct horse seal'

# The origin, once per file: main with v1.0.0, a feature, v1.1.0 and v1.1.1 on the same commit
# (whose VERSION reads 1.1.0), and v1.2.0 on a branch beside main; and two keys.
setup_file() {
    local work=$BATS_FILE_TMPDIR/work origin=$BATS_FILE_TMPDIR/remote/$OWNER/$NAME.git
    export GIT_CONFIG_GLOBAL=$BATS_FILE_TMPDIR/gitconfig GIT_CONFIG_NOSYSTEM=1
    printf '[user]\n\tname = Seal Test\n\temail = seal-test@example.invalid\n' > "$GIT_CONFIG_GLOBAL"
    mkdir -p "${origin%/*}"
    git init -q --bare "$origin"
    git init -q -b main "$work"
    printf '1.0.0\n' > "$work/VERSION"
    git -C "$work" add VERSION
    git -C "$work" commit -q -m "chore(release): 1.0.0 (#1)"
    git -C "$work" tag v1.0.0
    printf 'Text.\n' > "$work/README.md"
    git -C "$work" add README.md
    git -C "$work" commit -q -m "feat: a feature (#2)"
    printf '1.1.0\n' > "$work/VERSION"
    git -C "$work" commit -q -a -m "chore(release): 1.1.0 (#3)"
    git -C "$work" tag v1.1.0
    git -C "$work" tag v1.1.1
    git -C "$work" switch -q -c side
    printf '1.2.0\n' > "$work/VERSION"
    git -C "$work" commit -q -a -m "chore: a release beside main"
    git -C "$work" tag v1.2.0
    git -C "$work" push -q "$origin" main side v1.0.0 v1.1.0 v1.1.1 v1.2.0
    ssh-keygen -q -t ed25519 -N "$PASS" -C seal-test -f "$BATS_FILE_TMPDIR/key"
    ssh-keygen -q -t ed25519 -N "$PASS" -C other-test -f "$BATS_FILE_TMPDIR/other"
    printf 'maintainer namespaces="git" %s\n' "$(cat "$BATS_FILE_TMPDIR/key.pub")" \
        > "$BATS_FILE_TMPDIR/allowed_signers"
}

setup() {
    isolate_home
    printf '[user]\n\tname = Seal Test\n\temail = seal-test@example.invalid\n' > "$GIT_CONFIG_GLOBAL"
    # shellcheck source=tools/release-seal
    SEAL_LIB=1 source "$REPO_ROOT/tools/release-seal"
    export STUB_LOG=$BATS_TEST_TMPDIR/stub.log STUB_GH=$BATS_TEST_TMPDIR/gh STUB_GH_READONLY=1
    mkdir -p "$STUB_GH"
    : > "$STUB_LOG"
    cp -R "$BATS_FILE_TMPDIR/remote" "$BATS_TEST_TMPDIR/remote"
    ORIGIN=$BATS_TEST_TMPDIR/remote/$SLUG.git
    SEAL_HOME=$BATS_TEST_TMPDIR/seal-home
    mkdir -p "$SEAL_HOME"
    write_seal_config "$BATS_FILE_TMPDIR/allowed_signers"
    printf '#!/bin/sh\n[ -z "${SEAL_TEST_CANCEL:-}" ] || exit 1\nprintf "%%s\\n" "$SEAL_TEST_PASS"\n' \
        > "$BATS_TEST_TMPDIR/askpass"
    chmod +x "$BATS_TEST_TMPDIR/askpass"
    export SSH_ASKPASS=$BATS_TEST_TMPDIR/askpass SEAL_TEST_PASS=$PASS
    unset SEAL_TEST_CANCEL
    release_ok 1.1.0
}

# The seal home's config, with the allowed signers file $1.
write_seal_config() {
    printf 'SIGNING_KEY=%s\nALLOWED_SIGNERS=%s\nGIT_BASE=%s\n' "$BATS_FILE_TMPDIR/key" "$1" \
        "$BATS_TEST_TMPDIR/remote" > "$SEAL_HOME/config"
}

# The name of the gh stub's reply file for the call ARGS, as stub-bin/gh builds it.
gh_key() {
    local key
    key=$(printf '%s ' "$@" | sed 's/[^A-Za-z0-9.-]\{1,\}/_/g')
    if (( ${#key} > 120 )); then key=$(printf '%s' "$key" | sha256sum | cut -c 1-64); fi
    printf '%s\n' "$key"
}

# Make the gh call ARGS print stdin, and exit with RC when that is set.
gh_reply() {
    local key
    key=$(gh_key "$@")
    cat > "$STUB_GH/$key"
    if [[ -n ${RC:-} ]]; then printf '%s\n' "$RC" > "$STUB_GH/$key.rc"; else rm -f "$STUB_GH/$key.rc"; fi
}

# The commit of the tag $1 in the origin.
commit_of() {
    git -C "$ORIGIN" rev-parse "$1^{commit}"
}

# The stub's view of the release vX.Y.Z ($1): published, immutable, drafted by the bot, its
# verify run green, and its pull request.
release_ok() {
    local commit
    commit=$(commit_of "v$1")
    printf 'false\tfalse\ttrue\tgithub-actions[bot]\t2026-11-14T10:00:00Z\n' |
        gh_reply api "repos/$SLUG/releases/tags/v$1" --jq "$JQ_RELEASE"
    printf 'success\n' |
        gh_reply api "repos/$SLUG/actions/workflows/release.yml/runs?event=release&head_sha=$commit&per_page=1" --jq "$JQ_RUN"
    printf '#3 chore(release): %s\n' "$1" | gh_reply api "repos/$SLUG/commits/$commit/pulls" --jq "$JQ_PR"
}

# Run tools/release-seal with ARGS and the test home, the stubs first on PATH, through bats `run`.
run_seal() {
    run --separate-stderr env PATH="$REPO_ROOT/.github/standard/tests/stub-bin:$PATH" \
        bash "$REPO_ROOT/tools/release-seal" "$@" --home "$SEAL_HOME"
}

# Fail unless a line of the output starts with $1.
has() {
    P=$1 awk 'index($0, ENVIRON["P"]) == 1 { found = 1 } END { exit !found }' <<< "$output" ||
        { printf 'no line starting with "%s" in:\n%s\n%s\n' "$1" "$output" "$stderr" >&2; return 1; }
}

# Fail when the origin or the mirror holds the seal of v$1.
refute_sealed() {
    run git -C "$ORIGIN" rev-parse -q --verify "refs/tags/seal/v$1"
    [ "$status" -ne 0 ]
    run git -C "$SEAL_HOME/mirrors/$SLUG.git" rev-parse -q --verify "refs/tags/seal/v$1"
    [ "$status" -ne 0 ]
}

@test "ghr lets gh read only" {
    run ghr api -X POST "repos/$SLUG/git/refs"
    [ "$status" -eq 97 ]
    run ghr api "repos/$SLUG/git/refs" -f ref=refs/tags/x
    [ "$status" -eq 97 ]
    run ghr release create v1.0.0
    [ "$status" -eq 97 ]
}

@test "check passes a published, immutable, bot-drafted release on main and prints its facts" {
    local name
    run_seal check --repo "$SLUG" --version 1.1.0
    [ "$status" -eq 0 ] || { printf '%s\n%s\n' "$output" "$stderr" >&2; return 1; }
    for name in published drafted commit version verify unsealed; do
        has $'check\tok\t'"$name"$'\t'
    done
    has $'fact\tcommit\t'"$(commit_of v1.1.0)"
    has $'fact\tpr\t#3 chore(release): 1.1.0'
    has $'fact\tbase\tv1.0.0'
    [ "$(grep -c $'^fact\tsince\t' <<< "$output")" -eq 2 ]
    has $'fact\tsince\t'"$(git -C "$ORIGIN" rev-parse --short 'v1.1.0^{commit}') chore(release): 1.1.0 (#3)"
    run grep -v '^gh api ' "$STUB_LOG"
    [ "$status" -eq 1 ]
}

@test "check fails each check on its own, with its reason" {
    printf 'true\tfalse\ttrue\tgithub-actions[bot]\t\n' |
        gh_reply api "repos/$SLUG/releases/tags/v1.1.0" --jq "$JQ_RELEASE"
    run_seal check --repo "$SLUG" --version 1.1.0
    [ "$status" -eq 1 ]
    has $'check\tFAIL\tpublished\tv1.1.0 is a draft'
    printf 'false\ttrue\ttrue\tgithub-actions[bot]\t2026-11-14T10:00:00Z\n' |
        gh_reply api "repos/$SLUG/releases/tags/v1.1.0" --jq "$JQ_RELEASE"
    run_seal check --repo "$SLUG" --version 1.1.0
    has $'check\tFAIL\tpublished\tv1.1.0 is a pre-release'
    printf 'false\tfalse\tfalse\tgithub-actions[bot]\t2026-11-14T10:00:00Z\n' |
        gh_reply api "repos/$SLUG/releases/tags/v1.1.0" --jq "$JQ_RELEASE"
    run_seal check --repo "$SLUG" --version 1.1.0
    has $'check\tFAIL\tpublished\tv1.1.0 is not immutable'
    printf 'false\tfalse\ttrue\texample-user\t2026-11-14T10:00:00Z\n' |
        gh_reply api "repos/$SLUG/releases/tags/v1.1.0" --jq "$JQ_RELEASE"
    run_seal check --repo "$SLUG" --version 1.1.0
    has $'check\tok\tpublished\t'
    has $'check\tFAIL\tdrafted\tv1.1.0 was drafted by example-user'
    release_ok 1.1.0
    printf 'failure\n' |
        gh_reply api "repos/$SLUG/actions/workflows/release.yml/runs?event=release&head_sha=$(commit_of v1.1.0)&per_page=1" --jq "$JQ_RUN"
    run_seal check --repo "$SLUG" --version 1.1.0
    [ "$status" -eq 1 ]
    has $'check\tFAIL\tverify\tthe verify run of v1.1.0 ended with failure'
    # v1.1.1 sits on the commit whose VERSION reads 1.1.0.
    release_ok 1.1.1
    run_seal check --repo "$SLUG" --version 1.1.1
    [ "$status" -eq 1 ]
    has $'check\tok\tcommit\t'
    has $'check\tFAIL\tversion\tVERSION at the commit of v1.1.1 does not read 1.1.1'
    # v1.2.0 sits on a branch beside main.
    release_ok 1.2.0
    run_seal check --repo "$SLUG" --version 1.2.0
    [ "$status" -eq 1 ]
    has $'check\tFAIL\tcommit\tthe commit of v1.2.0 is not on main'
    # No release and no tag at all.
    RC=1 gh_reply api "repos/$SLUG/releases/tags/v9.9.9" --jq "$JQ_RELEASE" < /dev/null
    run_seal check --repo "$SLUG" --version 9.9.9
    [ "$status" -eq 1 ]
    has $'check\tFAIL\tpublished\tno release v9.9.9'
    has $'check\tFAIL\tcommit\tno tag v9.9.9'
}

@test "seal pushes seal/vX.Y.Z on the release's commit, which verify-tag accepts for maintainer" {
    local clone=$BATS_TEST_TMPDIR/clone.git
    run_seal seal --repo "$SLUG" --version 1.1.0
    [ "$status" -eq 0 ] || { printf '%s\n%s\n' "$output" "$stderr" >&2; return 1; }
    has $'sealed\tseal/v1.1.0\t'"$(git -C "$ORIGIN" rev-parse refs/tags/seal/v1.1.0)"
    git clone -q --bare "$ORIGIN" "$clone"
    [ "$(git -C "$clone" cat-file -t seal/v1.1.0)" = tag ]
    [ "$(git -C "$clone" rev-parse 'seal/v1.1.0^{commit}')" = "$(commit_of v1.1.0)" ]
    [ "$(git -C "$clone" for-each-ref --format='%(contents:subject)' refs/tags/seal/v1.1.0)" = "$NAME v1.1.0" ]
    [ "$(git -C "$clone" for-each-ref --format='%(taggername) %(taggeremail)' refs/tags/seal/v1.1.0)" = \
        'Seal Test <seal-test@example.invalid>' ]
    run git -C "$clone" -c gpg.ssh.allowedSignersFile="$BATS_FILE_TMPDIR/allowed_signers" verify-tag seal/v1.1.0
    [ "$status" -eq 0 ] || { printf '%s\n' "$output" >&2; return 1; }
    [[ $output == *'Good "git" signature for maintainer'* ]]
    run grep -v '^gh api ' "$STUB_LOG"
    [ "$status" -eq 1 ]
}

@test "seal refuses a release that has its seal, and never moves a seal" {
    local before
    run_seal seal --repo "$SLUG" --version 1.1.0
    [ "$status" -eq 0 ] || { printf '%s\n%s\n' "$output" "$stderr" >&2; return 1; }
    before=$(git -C "$ORIGIN" rev-parse refs/tags/seal/v1.1.0)
    run_seal seal --repo "$SLUG" --version 1.1.0
    [ "$status" -eq 1 ]
    has $'check\tFAIL\tunsealed\tseal/v1.1.0 exists'
    [ "$(git -C "$ORIGIN" rev-parse refs/tags/seal/v1.1.0)" = "$before" ]
    # A later release of the same commit counts its commits from that seal: none.
    release_ok 1.1.1
    run_seal check --repo "$SLUG" --version 1.1.1
    has $'fact\tbase\tseal/v1.1.0'
    [ "$(grep -c $'^fact\tsince\t' <<< "$output")" -eq 0 ]
}

@test "a wrong passphrase or a cancelled passphrase dialog seals and pushes nothing" {
    SEAL_TEST_PASS='not the passphrase' run_seal seal --repo "$SLUG" --version 1.1.0
    [ "$status" -eq 1 ]
    [[ $stderr == *"the seal could not be signed"* ]]
    refute_sealed 1.1.0
    SEAL_TEST_CANCEL=1 run_seal seal --repo "$SLUG" --version 1.1.0
    [ "$status" -eq 1 ]
    [[ $stderr == *"the seal could not be signed"* ]]
    [[ $stderr != *"$BATS_TEST_TMPDIR"* && $output != *"$BATS_TEST_TMPDIR"* ]]
    refute_sealed 1.1.0
}

@test "seal refuses a seal that the allowed signers do not accept for maintainer, before the push" {
    printf 'maintainer namespaces="git" %s\n' "$(cat "$BATS_FILE_TMPDIR/other.pub")" \
        > "$BATS_TEST_TMPDIR/allowed_signers"
    write_seal_config "$BATS_TEST_TMPDIR/allowed_signers"
    run_seal seal --repo "$SLUG" --version 1.1.0
    [ "$status" -eq 1 ]
    [[ $stderr == *"the new seal does not verify for maintainer against ALLOWED_SIGNERS"* ]]
    refute_sealed 1.1.0
}

@test "no hook runs in the mirror, and the tool runs only from a home outside every work tree" {
    local hook
    mkdir -p "$BATS_TEST_TMPDIR/hooks" "$BATS_TEST_TMPDIR/no-hooks"
    for hook in reference-transaction pre-push post-checkout; do
        printf '#!/bin/sh\ntouch "%s/hook-ran"\nexit 1\n' "$BATS_TEST_TMPDIR" > "$BATS_TEST_TMPDIR/hooks/$hook"
        chmod +x "$BATS_TEST_TMPDIR/hooks/$hook"
    done
    # The origin stands in for GitHub, which runs none of this machine's hooks.
    git -C "$ORIGIN" config core.hooksPath "$BATS_TEST_TMPDIR/no-hooks"
    git config --global core.hooksPath "$BATS_TEST_TMPDIR/hooks"
    run_seal seal --repo "$SLUG" --version 1.1.0
    [ "$status" -eq 0 ] || { printf '%s\n%s\n' "$output" "$stderr" >&2; return 1; }
    [ ! -e "$BATS_TEST_TMPDIR/hook-ran" ]
    git config --global --unset core.hooksPath
    git init -q "$BATS_TEST_TMPDIR/clone"
    mkdir -p "$BATS_TEST_TMPDIR/clone/seal"
    cp "$SEAL_HOME/config" "$BATS_TEST_TMPDIR/clone/seal/config"
    run --separate-stderr env PATH="$REPO_ROOT/.github/standard/tests/stub-bin:$PATH" \
        bash "$REPO_ROOT/tools/release-seal" check --repo "$SLUG" --version 1.1.0 --home "$BATS_TEST_TMPDIR/clone/seal"
    [ "$status" -eq 2 ]
    [[ $stderr == *"its home must be outside every git work tree"* ]]
}

@test "versions lists the published releases that are not pre-releases, newest first, with their seal" {
    : | gh_reply api --paginate "repos/$SLUG/releases?per_page=100" --jq "$JQ_TAGS"
    run_seal versions --repo "$SLUG"
    [ "$status" -eq 0 ] || { printf '%s\n' "$stderr" >&2; return 1; }
    [ -z "$output" ]
    printf 'v1.0.0\nv1.2.0\nnightly\nv1.1.0\nv1.1.1\n' |
        gh_reply api --paginate "repos/$SLUG/releases?per_page=100" --jq "$JQ_TAGS"
    run_seal seal --repo "$SLUG" --version 1.1.0
    [ "$status" -eq 0 ] || { printf '%s\n%s\n' "$output" "$stderr" >&2; return 1; }
    run_seal versions --repo "$SLUG"
    [ "$status" -eq 0 ] || { printf '%s\n' "$stderr" >&2; return 1; }
    [ "$output" = $'v1.2.0\tunsealed\nv1.1.1\tunsealed\nv1.1.0\tsealed\nv1.0.0\tunsealed' ]
}

@test "a tag that moved since the last fetch stops the tool" {
    run_seal check --repo "$SLUG" --version 1.1.0
    [ "$status" -eq 0 ] || { printf '%s\n%s\n' "$output" "$stderr" >&2; return 1; }
    git -C "$ORIGIN" tag -f v1.1.0 v1.0.0 > /dev/null
    run_seal check --repo "$SLUG" --version 1.1.0
    [ "$status" -eq 2 ]
    [[ $stderr == *"a tag moved since the last fetch"* ]]
}

@test "the config's files may be named from the home, and the allowed signers may have CRLF line ends" {
    cp "$BATS_FILE_TMPDIR/key" "$SEAL_HOME/key"
    printf 'maintainer namespaces="git" %s\r\n' "$(cat "$BATS_FILE_TMPDIR/key.pub")" > "$SEAL_HOME/signers"
    printf 'SIGNING_KEY=key\r\nALLOWED_SIGNERS=signers\r\nGIT_BASE=%s\r\n' "$BATS_TEST_TMPDIR/remote" \
        > "$SEAL_HOME/config"
    run_seal seal --repo "$SLUG" --version 1.1.0
    [ "$status" -eq 0 ] || { printf '%s\n%s\n' "$output" "$stderr" >&2; return 1; }
    has $'sealed\tseal/v1.1.0\t'
}

@test "the config needs SIGNING_KEY and ALLOWED_SIGNERS, and knows no other key" {
    printf 'SIGNING_KEY=%s\n' "$BATS_FILE_TMPDIR/key" > "$SEAL_HOME/config"
    run_seal check --repo "$SLUG" --version 1.1.0
    [ "$status" -eq 2 ]
    [[ $stderr == *"ALLOWED_SIGNERS is missing"* ]]
    printf 'SIGNING_KEY=%s\nALLOWED_SIGNERS=%s\nBOGUS=1\n' "$BATS_FILE_TMPDIR/key" \
        "$BATS_FILE_TMPDIR/allowed_signers" > "$SEAL_HOME/config"
    run_seal check --repo "$SLUG" --version 1.1.0
    [ "$status" -eq 2 ]
    [[ $stderr == *"the config line 3 is not a known KEY=value"* ]]
    [[ $stderr != *BOGUS* ]]
}

@test "the seal tool's three files are release assets of repo-standard, kept in its archive" {
    local file assets
    assets=" $(sh "$REPO_ROOT/.github/standard/bin/conf" --get RELEASE_ASSETS "$REPO_ROOT/.github/standard.conf") "
    for file in tools/release-seal tools/release-seal-askpass tools/release-seal.ps1; do
        [[ $assets == *" $file "* ]] || { printf '%s is no release asset\n' "$file" >&2; return 1; }
        git -C "$REPO_ROOT" ls-files --error-unmatch -- "$file" > /dev/null
        [ "$(git -C "$REPO_ROOT" check-attr export-ignore -- "$file" | awk '{ print $NF }')" != set ]
    done
}

@test "usage: a command, OWNER/NAME and, for check and seal, a version X.Y.Z" {
    run_seal
    [ "$status" -eq 64 ]
    run_seal check --repo not-a-slug --version 1.1.0
    [ "$status" -eq 64 ]
    run_seal check --repo "$OWNER/.." --version 1.1.0
    [ "$status" -eq 64 ]
    run_seal check --repo "$SLUG" --version 1.1
    [ "$status" -eq 64 ]
    run_seal seal --repo "$SLUG"
    [ "$status" -eq 64 ]
    run_seal versions --repo "$SLUG" --version 1.1.0
    [ "$status" -eq 64 ]
}
