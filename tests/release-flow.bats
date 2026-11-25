#!/usr/bin/env bats
# release-flow.bats of repo-standard: the release tools in the checkouts that release.yml gives
# their jobs. The draft, promote and verify jobs check out only some directories, in cone mode,
# so a tool that needs a file outside them fails only after a publish. Each test makes that sparse
# checkout of a synthetic released repository with git itself, from the directories release.yml
# lists for the job. It runs the job's tool there with the gh and docker stubs. Every value is
# synthetic.

# The sh -c scripts are single-quoted, and bats runs each test in a subshell, both on purpose.
# shellcheck disable=SC2016,SC2030,SC2031
load helpers

SLUG=example-owner/example

setup() {
    isolate_home
    export STUB_LOG=$BATS_TEST_TMPDIR/stub.log STUB_GH=$BATS_TEST_TMPDIR/gh STUB_GH_READONLY=1
    export STUB_DOCKER_TAGS=$BATS_TEST_TMPDIR/docker-tags GITHUB_REPOSITORY=$SLUG
    mkdir -p "$STUB_GH"
    : > "$STUB_LOG"
    : > "$STUB_DOCKER_TAGS"
    CO=$BATS_TEST_TMPDIR/checkout
}

# The directories that the job $1 of this repository's release.yml checks out, one per line.
sparse_dirs() {
    awk -v job="  $1:" '
        $0 == job { injob = 1; next }
        injob && /^  [a-z-]+:$/ { exit }
        injob && /sparse-checkout: \|$/ { list = 1; next }
        list && /^            [^ ]/ { sub(/^ +/, ""); print; next }
        list { list = 0 }' "$REPO_ROOT/.github/workflows/release.yml"
}

# The name of the gh stub's reply file for the call ARGS, as stub-bin/gh builds it.
gh_key() {
    local key
    key=$(printf '%s ' "$@" | sed 's/[^A-Za-z0-9.-]\{1,\}/_/g')
    if (( ${#key} > 120 )); then key=$(printf '%s' "$key" | sha256sum | cut -c 1-64); fi
    printf '%s\n' "$key"
}

# Make the gh call ARGS print stdin.
gh_reply() {
    cat > "$STUB_GH/$(gh_key "$@")"
}

# A released repository at $REPO of the kind $1 with the base pack, and at $CO its clone with only
# the directories of the job $2 checked out, in cone mode, as actions/checkout makes it.
sparse_clone() {
    local -a dirs
    make_repo
    write_config "RELEASE_KIND=$1" PRIVACY_RULES=base
    git -C "$REPO" add -A
    stage_executables
    git -C "$REPO" -c core.hooksPath=no-hooks commit -q -m "chore: the standard's files"
    mapfile -t dirs < <(sparse_dirs "$2")
    (( ${#dirs[@]} > 0 )) || { printf 'release.yml lists no sparse checkout for %s\n' "$2" >&2; return 1; }
    git clone -q --no-checkout "$REPO" "$CO"
    git -C "$CO" sparse-checkout set --cone "${dirs[@]}"
    git -C "$CO" checkout -q main
}

# Run the tool $1 of the sparse checkout with the other arguments there, the stubs first on PATH.
tool_in_checkout() {
    local name=$1
    shift
    run --separate-stderr env PATH="$REPO_ROOT/.github/standard/tests/stub-bin:$PATH" \
        sh -c 'cd "$1" && shift && exec bash ".github/standard/bin/$0" "$@"' "$name" "$CO" "$@"
}

@test "release-verify runs in the checkout of the verify job, which reads the config through conf" {
    local commit pkg=$BATS_TEST_TMPDIR/pkg
    sparse_clone tar verify
    [ -f "$CO/.github/standard.conf" ]
    commit=$(git -C "$CO" rev-parse HEAD)
    mkdir -p "$pkg/example-1.0.0" "$STUB_GH/assets-v1.0.0"
    printf '{\n  "schema": 1,\n  "name": "example",\n  "version": "1.0.0",\n  "tag": "v1.0.0",\n  "commit": "%s"\n}\n' \
        "$commit" > "$pkg/example-1.0.0/example-release.json"
    tar -czf "$STUB_GH/assets-v1.0.0/example-1.0.0.tar.gz" -C "$pkg" example-1.0.0
    (cd "$STUB_GH/assets-v1.0.0" && sha256sum example-1.0.0.tar.gz > SHA256SUMS)
    printf 'false\ttrue\tgithub-actions[bot]\n' |
        gh_reply api "repos/$SLUG/releases/tags/v1.0.0" --jq '[.draft, .immutable, .author.login] | @tsv'
    printf '%s\n' "$commit" | gh_reply api "repos/$SLUG/commits/v1.0.0" --jq .sha
    tool_in_checkout release-verify --tag v1.0.0
    [ "$status" -eq 0 ] || { printf '%s\n' "$stderr" >&2; return 1; }
    [[ $stderr == *"v1.0.0 is verified"* ]]
}

@test "release-draft runs in the checkout of the draft job" {
    local commit dir
    sparse_clone tar draft
    commit=$(git -C "$CO" rev-parse HEAD)
    dir=$CO/release-build
    mkdir -p "$dir/assets"
    printf 'archive\n' > "$dir/assets/example-1.0.0.tar.gz"
    (cd "$dir/assets" && sha256sum example-1.0.0.tar.gz > SHA256SUMS)
    printf '### Added\n\n- A first feature.\n' > "$dir/notes.md"
    printf '%s\n' "$commit" | gh_reply api "repos/$SLUG/git/ref/heads/main" --jq .object.sha
    : | gh_reply api "repos/$SLUG/git/matching-refs/tags/v1.0.0" --jq '.[].ref'
    : | gh_reply api --paginate "repos/$SLUG/releases?per_page=100" --jq '.[] | [.id, .draft, .tag_name] | @tsv'
    unset STUB_GH_READONLY
    VERSION=1.0.0 COMMIT=$commit tool_in_checkout release-draft --dir release-build
    [ "$status" -eq 0 ] || { printf '%s\n' "$stderr" >&2; return 1; }
    grep -q -F -e "--draft --target $commit" "$STUB_LOG"
}

@test "release-promote runs in the checkout of the promote job" {
    local digest
    sparse_clone image promote
    digest=sha256:$(printf '6%.0s' {1..64})
    mkdir -p "$CO/release-build/assets"
    printf '{\n  "schema": 1,\n  "digest": "%s",\n  "version": "0.0.0"\n}\n' "$digest" > "$CO/release-build/assets/image.json"
    GITHUB_ACTOR=example-owner GH_TOKEN=synthetic-token-value \
        tool_in_checkout release-promote --rehearse --dir release-build/assets
    [ "$status" -eq 0 ] || { printf '%s\n' "$stderr" >&2; return 1; }
    [ "$(cat "$STUB_DOCKER_TAGS")" = "ghcr.io/$SLUG:rehearsal $digest" ]
}
