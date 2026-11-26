#!/usr/bin/env bats
# status.bats of repo-standard: tools/status, the read-only audit, against the gh stub
# with fixed replies and bare local repositories. The tests source the tool with STATUS_LIB=1 for
# its jq filters, so each stub reply answers exactly the call the tool makes. Every value is
# synthetic; a run must never show a path, HOME or a denylist term.

# The sh -c scripts are single-quoted, and bats runs each test in a subshell, both on purpose.
# shellcheck disable=SC2016,SC2030,SC2031,SC2034
load helpers

OWNER=example-owner
RS=$OWNER/repo-standard
TODAY=2026-11-13

setup() {
    isolate_home
    # shellcheck source=tools/status
    STATUS_LIB=1 source "$REPO_ROOT/tools/status"
    export STUB_LOG=$BATS_TEST_TMPDIR/stub.log STUB_GH=$BATS_TEST_TMPDIR/gh STUB_GH_READONLY=1
    mkdir -p "$STUB_GH"
    : > "$STUB_LOG"
    SRC=$BATS_TEST_TMPDIR/rs
    git init -q -b main "$SRC"
    git -C "$SRC" remote add origin "https://github.com/$RS.git"
    mkdir -p "$SRC/tools" "$SRC/config"
    cp "$REPO_ROOT/tools/status" "$SRC/tools/status"
    cp -R "$REPO_ROOT/.githooks" "$SRC/.githooks"
    mkdir -p "$SRC/.github/standard/bin" "$SRC/.github/workflows"
    cp "$REPO_ROOT/.github/standard/actions.allow" "$SRC/.github/standard/actions.allow"
    cp "$REPO_ROOT/.github/standard/bin/"* "$SRC/.github/standard/bin/"
    cp "$REPO_ROOT/.github/workflows/"*.yml "$SRC/.github/workflows/"
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

# A MANIFEST of the standard X.Y.Z ($1) with one copy, the blob $2.
manifest_of() {
    printf '# Repository standard %s.\nstandard %s\nfile    all      %s  100755  .githooks/pre-commit\n' "$1" "$1" "$2"
}

# The stub's view of the repository $1, adopted at 1.0.0 (unless ADOPTED=no) with every setting
# as the standard wants it; VIS=public makes it public. The release asset of 1.0.0 equals its
# MANIFEST.
repo_ok() {
    local r=$OWNER/$1 m blob vis=${VIS:-private} private=true
    [[ $vis == private ]] || private=false
    blob=$(git -C "$SRC" hash-object -w --stdin <<< 'a hook')
    m=$BATS_TEST_TMPDIR/manifest-$1
    manifest_of 1.0.0 "$blob" > "$m"
    mkdir -p "$STUB_GH/assets-v1.0.0"
    cp "$m" "$STUB_GH/assets-v1.0.0/MANIFEST"
    printf 'v1.0.0\n' | gh_reply api "repos/$RS/releases/latest" --jq "$JQ_TAG"
    if [[ ${ADOPTED:-yes} == yes ]]; then
        git hash-object --no-filters "$m" | gh_reply api "repos/$r/contents/.github/standard/MANIFEST?ref=main" --jq "$JQ_SHA"
        gh_reply api -H "$RAW" "repos/$r/contents/.github/standard/MANIFEST?ref=main" < "$m"
        printf 'NAME=%s\nVISIBILITY=%s\nRELEASE_KIND=tar\n' "$1" "$vis" |
            gh_reply api -H "$RAW" "repos/$r/contents/.github/standard.conf?ref=main"
        printf 'success\n' | gh_reply api "repos/$r/actions/workflows/ci.yml/runs?branch=main&per_page=1" --jq "$JQ_RUN"
        printf 'success\n' | gh_reply api "repos/$r/actions/workflows/secret-scan.yml/runs?branch=main&per_page=1" --jq "$JQ_RUN"
        printf 'success\n' | gh_reply api "repos/$r/actions/workflows/release.yml/runs?event=release&per_page=1" --jq "$JQ_RUN"
        printf '2026-11-01T10:00:00Z\n' | gh_reply api --paginate "repos/$r/commits?sha=main&path=.github/standard/MANIFEST&per_page=100" --jq "$JQ_DATES"
        : | gh_reply api --paginate "repos/$r/commits?sha=main&since=2026-11-01T10:00:00Z&per_page=100" --jq "$JQ_DIRECT"
    else
        RC=1 gh_reply api "repos/$r/contents/.github/standard/MANIFEST?ref=main" --jq "$JQ_SHA" < /dev/null
        RC=1 gh_reply api -H "$RAW" "repos/$r/contents/.github/standard.conf?ref=main" < /dev/null
    fi
    printf '%s\ttrue\tfalse\tfalse\tPR_TITLE\tCOMMIT_MESSAGES\ttrue\tfalse\tenabled\tenabled\n' "$private" |
        gh_reply api "repos/$r" --jq "$JQ_REPO"
    printf 'true\n' | gh_reply api "repos/$r/immutable-releases" --jq "$JQ_ENABLED"
    printf 'read\tfalse\n' | gh_reply api "repos/$r/actions/permissions/workflow" --jq "$JQ_TOKEN"
    : | gh_reply api "repos/$r/vulnerability-alerts"
    printf 'true\n' | gh_reply api "repos/$r/automated-security-fixes" --jq "$JQ_ENABLED"
    printf 'true\tselected\ttrue\n' | gh_reply api "repos/$r/actions/permissions" --jq "$JQ_ACTIONS"
    printf 'false\tfalse\n' | gh_reply api "repos/$r/actions/permissions/selected-actions" --jq "$JQ_OWNED"
    sed -e '/^#/d' -e '/^$/d' "$SRC/.github/standard/actions.allow" |
        gh_reply api "repos/$r/actions/permissions/selected-actions" --jq "$JQ_PATTERNS"
    printf '7\n' | gh_reply api "repos/$r/rulesets" --jq "$JQ_RULESETS"
    printf 'active\t0\tdeletion,non_fast_forward,pull_request,required_status_checks\tall-passed:15368,scan:15368\tfalse\t0\n' |
        gh_reply api "repos/$r/rulesets/7" --jq "$JQ_RULESET"
    : | gh_reply api --paginate "repos/$r/pulls?state=open&per_page=100" --jq "$JQ_DEPENDABOT"
    : | gh_reply api --paginate "repos/$r/releases?per_page=100" --jq "$JQ_DRAFTS"
}

# Run tools/status of $SRC with ARGS, the stubs first on PATH, through bats `run`.
run_status() {
    run --separate-stderr env PATH="$REPO_ROOT/.github/standard/tests/stub-bin:$PATH" \
        bash "$SRC/tools/status" --today "$TODAY" "$@"
}

# Fail unless the output has the line "$1 $2 $3 ..." and its reason holds $4.
has_line() {
    grep -q -E "^$1 $2 $3( |$)" <<< "$output" || { printf 'no line "%s %s %s" in:\n%s\n' "$1" "$2" "$3" "$output" >&2; return 1; }
    [[ -z ${4:-} ]] || grep -E "^$1 $2 $3( |$)" <<< "$output" | grep -q -F -e "$4" ||
        { printf 'the line "%s %s %s" lacks "%s":\n%s\n' "$1" "$2" "$3" "$4" "$output" >&2; return 1; }
}

@test "ghr lets gh read only: a method other than GET and every field option are refused" {
    run ghr api -X POST "repos/$RS/releases"
    [ "$status" -eq 97 ]
    run ghr api --method=PATCH "repos/$RS"
    [ "$status" -eq 97 ]
    for opt in -f -F --field --raw-field --input; do
        run ghr api "repos/$RS/issues" "$opt" title=x
        [ "$status" -eq 97 ] || { printf '%s passed\n' "$opt" >&2; return 1; }
    done
    run ghr release create v1.0.0
    [ "$status" -eq 97 ]
    run ghr pr merge 1
    [ "$status" -eq 97 ]
}

@test "an adopted repository with every setting right is ok in every per-repository check" {
    repo_ok example
    run_status --checks standard,settings,health,history example
    [ "$status" -eq 0 ] || { printf '%s\n%s\n' "$output" "$stderr" >&2; return 1; }
    has_line example standard ok "1.0.0"
    has_line example settings ok
    has_line example health ok
    has_line example history ok
    [ "$(grep -c -v -E '^gh (api|release download) ' "$STUB_LOG")" -eq 0 ]
}

@test "standard: a MANIFEST unlike its asset is a FAIL; a lag and legacy warn; before adoption it warns" {
    repo_ok example
    printf 'other\n' > "$STUB_GH/assets-v1.0.0/MANIFEST"
    run_status --checks standard example
    [ "$status" -eq 1 ]
    has_line example standard FAIL "the MANIFEST differs from the v1.0.0 asset"
    repo_ok example
    printf 'v1.1.0\n' | gh_reply api "repos/$RS/releases/latest" --jq "$JQ_TAG"
    printf 'NAME=example\nVISIBILITY=private\nRELEASE_KIND=legacy\n' |
        gh_reply api -H "$RAW" "repos/$OWNER/example/contents/.github/standard.conf?ref=main"
    run_status --checks standard example
    [ "$status" -eq 0 ]
    has_line example standard warn "1.0.0, the newest release is 1.1.0"
    has_line example standard warn "RELEASE_KIND=legacy"
    ADOPTED=no repo_ok other
    run_status --checks standard,history other
    [ "$status" -eq 0 ]
    has_line other standard warn "not adopted yet"
    repo_ok source
    manifest_of 1.1.0-dev 0123456789012345678901234567890123456789 |
        gh_reply api -H "$RAW" "repos/$OWNER/source/contents/.github/standard/MANIFEST?ref=main"
    printf 'NAME=repo-standard\nVISIBILITY=private\nROLE=source\nRELEASE_KIND=tar\n' |
        gh_reply api -H "$RAW" "repos/$OWNER/source/contents/.github/standard.conf?ref=main"
    run_status --checks standard source
    [ "$status" -eq 0 ]
    has_line source standard ok "the source of the standard, at 1.1.0-dev"
}

@test "settings: each wrong setting is a FAIL; extra allow-list entries warn before adoption and fail after" {
    repo_ok example
    printf 'true\ttrue\ttrue\tfalse\tPR_TITLE\tPR_BODY\ttrue\ttrue\tenabled\tenabled\n' |
        gh_reply api "repos/$OWNER/example" --jq "$JQ_REPO"
    printf 'false\n' | gh_reply api "repos/$OWNER/example/immutable-releases" --jq "$JQ_ENABLED"
    printf 'write\ttrue\n' | gh_reply api "repos/$OWNER/example/actions/permissions/workflow" --jq "$JQ_TOKEN"
    RC=1 gh_reply api "repos/$OWNER/example/vulnerability-alerts" < /dev/null
    printf 'true\tselected\tfalse\n' | gh_reply api "repos/$OWNER/example/actions/permissions" --jq "$JQ_ACTIONS"
    { sed -e '/^#/d' -e '/^$/d' "$SRC/.github/standard/actions.allow"; printf 'example-owner/extra-action@*\n'; } |
        gh_reply api "repos/$OWNER/example/actions/permissions/selected-actions" --jq "$JQ_PATTERNS"
    run_status --checks settings example
    [ "$status" -eq 1 ]
    has_line example settings FAIL "merge commits are allowed"
    has_line example settings FAIL "squash messages are not COMMIT_MESSAGES"
    has_line example settings FAIL "auto-merge is allowed"
    has_line example settings FAIL "immutable releases are off"
    has_line example settings FAIL "the workflow token may write"
    has_line example settings FAIL "Actions may approve pull requests"
    has_line example settings FAIL "Dependabot alerts are off"
    has_line example settings FAIL "SHA pinning is off"
    has_line example settings FAIL "beyond actions.allow: example-owner/extra-action@*"
    ADOPTED=no repo_ok other
    { sed -e '/^#/d' -e '/^$/d' "$SRC/.github/standard/actions.allow"; printf 'example-owner/extra-action@*\ngithub/codeql-action/*@*\n'; } |
        gh_reply api "repos/$OWNER/other/actions/permissions/selected-actions" --jq "$JQ_PATTERNS"
    run_status --checks settings other
    [ "$status" -eq 0 ]
    has_line other settings warn "until the adoption: example-owner/extra-action@*"
    [[ $output != *codeql* ]]
}

@test "settings of a public repository: the standard ruleset exactly, secret scanning and push protection" {
    VIS=public repo_ok example
    run_status --checks settings example
    [ "$status" -eq 0 ] || { printf '%s\n' "$output" >&2; return 1; }
    has_line example settings ok
    printf 'active\t1\tdeletion,non_fast_forward,pull_request,required_status_checks\tall-passed:15368\ttrue\t1\n' |
        gh_reply api "repos/$OWNER/example/rulesets/7" --jq "$JQ_RULESET"
    printf 'false\ttrue\tfalse\tfalse\tPR_TITLE\tCOMMIT_MESSAGES\ttrue\tfalse\tdisabled\tenabled\n' |
        gh_reply api "repos/$OWNER/example" --jq "$JQ_REPO"
    run_status --checks settings example
    [ "$status" -eq 1 ]
    has_line example settings FAIL "the ruleset differs from the standard one"
    has_line example settings FAIL "secret scanning is off"
    printf 'NAME=example\nVISIBILITY=private\nRELEASE_KIND=tar\n' |
        gh_reply api -H "$RAW" "repos/$OWNER/example/contents/.github/standard.conf?ref=main"
    run_status --checks settings example
    has_line example settings FAIL "VISIBILITY=private, but GitHub shows it public"
}

# The other tests reply with a finished line; this one runs JQ_RULESET itself, on a ruleset as
# GitHub's API returns it, so a jq default that swallows false shows.
@test "settings: the ruleset filter turns GitHub's standard ruleset into the standard line" {
    local ruleset
    need command jq
    ruleset='{"enforcement":"active","bypass_actors":[],"rules":[{"type":"deletion"},
        {"type":"non_fast_forward"},{"type":"pull_request","parameters":
        {"required_approving_review_count":0}},{"type":"required_status_checks","parameters":
        {"strict_required_status_checks_policy":false,"required_status_checks":
        [{"context":"scan","integration_id":15368},
        {"context":"all-passed","integration_id":15368}]}}]}'
    run jq -r "$JQ_RULESET" <<< "$ruleset"
    [ "$status" -eq 0 ]
    [ "$output" == "$STANDARD_RULESET" ] ||
        { printf 'got:  %q\nwant: %q\n' "$output" "$STANDARD_RULESET" >&2; return 1; }
    run jq -r "$JQ_RULESET" <<< "${ruleset/:false,/:true,}"
    [[ $output == *$'\ttrue\t0' ]]
}

# A repository that seals (SEAL=yes) needs a tag ruleset that refuses to delete or move any seal,
# for every login, and no tag ruleset may refuse to create one: the seal tool pushes a new tag.
@test "settings of a sealed repository: a tag ruleset protects seals and none blocks a new one" {
    local r="repos/$OWNER/example"
    VIS=public repo_ok example
    printf 'NAME=example\nVISIBILITY=public\nRELEASE_KIND=tar\nSEAL=yes\n' |
        gh_reply api -H "$RAW" "$r/contents/.github/standard.conf?ref=main"
    : | gh_reply api "$r/rulesets" --jq "$JQ_TAG_RULESETS"
    run_status --checks settings example
    [ "$status" -eq 1 ]
    has_line example settings FAIL "no tag ruleset blocks deleting and moving the seal tags"

    printf '9\n' | gh_reply api "$r/rulesets" --jq "$JQ_TAG_RULESETS"
    printf 'active\t0\tdeletion,update\trefs/tags/seal/*\t\n' |
        gh_reply api "$r/rulesets/9" --jq "$JQ_TAG_RULESET"
    run_status --checks settings example
    [ "$status" -eq 0 ] || { printf '%s\n' "$output" >&2; return 1; }
    has_line example settings ok

    local bad
    for bad in $'active\t1\tdeletion,update\trefs/tags/seal/*\t' \
        $'evaluate\t0\tdeletion,update\trefs/tags/seal/*\t' \
        $'active\t0\tdeletion\trefs/tags/seal/*\t' $'active\t0\tdeletion,update\trefs/tags/*\t'; do
        printf '%s\n' "$bad" | gh_reply api "$r/rulesets/9" --jq "$JQ_TAG_RULESET"
        run_status --checks settings example
        [ "$status" -eq 1 ] || { printf 'passed: %q\n' "$bad" >&2; return 1; }
        has_line example settings FAIL "no tag ruleset blocks deleting and moving the seal tags"
    done

    printf 'active\t0\tcreation,deletion,update\trefs/tags/seal/*\t\n' |
        gh_reply api "$r/rulesets/9" --jq "$JQ_TAG_RULESET"
    run_status --checks settings example
    [ "$status" -eq 1 ]
    has_line example settings FAIL "a tag ruleset blocks creating a seal"

    printf '9\n10\n' | gh_reply api "$r/rulesets" --jq "$JQ_TAG_RULESETS"
    printf 'active\t0\tdeletion,update\trefs/tags/seal/*\t\n' |
        gh_reply api "$r/rulesets/9" --jq "$JQ_TAG_RULESET"
    printf 'active\t0\tcreation\t~ALL\t\n' | gh_reply api "$r/rulesets/10" --jq "$JQ_TAG_RULESET"
    run_status --checks settings example
    [ "$status" -eq 1 ]
    has_line example settings FAIL "a tag ruleset blocks creating a seal"
    [[ $output != *"no tag ruleset blocks deleting"* ]]
    printf 'active\t0\tcreation\trefs/tags/seal/v*\t\n' |
        gh_reply api "$r/rulesets/10" --jq "$JQ_TAG_RULESET"
    run_status --checks settings example
    has_line example settings FAIL "a tag ruleset blocks creating a seal"
    # A creation rule that leaves the seals out, or one that only evaluates, blocks nothing.
    for bad in $'active\t0\tcreation\trefs/tags/*\trefs/tags/seal/*' \
        $'evaluate\t0\tcreation\t~ALL\t'; do
        printf '%s\n' "$bad" | gh_reply api "$r/rulesets/10" --jq "$JQ_TAG_RULESET"
        run_status --checks settings example
        [ "$status" -eq 0 ] || { printf 'failed: %q\n%s\n' "$bad" "$output" >&2; return 1; }
    done

    RC=1 gh_reply api "$r/rulesets" --jq "$JQ_TAG_RULESETS" < /dev/null
    run_status --checks settings example
    [ "$status" -eq 1 ]
    has_line example settings FAIL "cannot read the tag rulesets"
}

@test "settings: the tag ruleset filter turns GitHub's seal-tag ruleset into the standard line" {
    need command jq
    run jq -r "$JQ_TAG_RULESET" <<< '{"target":"tag","enforcement":"active","bypass_actors":[],
        "conditions":{"ref_name":{"include":["refs/tags/seal/*"],"exclude":[]}},
        "rules":[{"type":"update"},{"type":"deletion"}]}'
    [ "$status" -eq 0 ]
    [ "$output" == "$SEAL_RULESET" ] ||
        { printf 'got:  %q\nwant: %q\n' "$output" "$SEAL_RULESET" >&2; return 1; }
}

@test "health: a red ci on main, an old Dependabot pull request and a waiting draft" {
    repo_ok example
    printf 'failure\n' | gh_reply api "repos/$OWNER/example/actions/workflows/ci.yml/runs?branch=main&per_page=1" --jq "$JQ_RUN"
    printf '12\t2026-10-20\n13\t2026-11-10\n' |
        gh_reply api --paginate "repos/$OWNER/example/pulls?state=open&per_page=100" --jq "$JQ_DEPENDABOT"
    printf 'v1.1.0\n' | gh_reply api --paginate "repos/$OWNER/example/releases?per_page=100" --jq "$JQ_DRAFTS"
    run_status --checks health example
    [ "$status" -eq 1 ]
    has_line example health FAIL "ci on main ended with failure"
    has_line example health FAIL "Dependabot #12 is open 24 days"
    has_line example health FAIL "draft v1.1.0 waits for Publish"
    [[ $output != *"#13"* ]]
}

@test "history: a commit on main that GitHub did not make and sign is a FAIL, by short SHA only" {
    repo_ok example
    printf '0123456\tsomeone\ttrue\n1111111\tweb-flow\ttrue\n2222222\tweb-flow\tfalse\n' | gh_reply api --paginate \
        "repos/$OWNER/example/commits?sha=main&since=2026-11-01T10:00:00Z&per_page=100" --jq "$JQ_DIRECT"
    printf '0\n' | gh_reply api "repos/$OWNER/example/commits/0123456/pulls" --jq "$JQ_MERGED"
    printf '0\n' | gh_reply api "repos/$OWNER/example/commits/2222222/pulls" --jq "$JQ_MERGED"
    run_status --checks history example
    [ "$status" -eq 1 ]
    has_line example history FAIL "a direct push to main: 0123456 2222222"
    [[ $output != *1111111* ]]
}

# A merge commit brings its branch's own commits onto main, committed by their author. Each such
# commit costs one GET, and only a pull request merged into main accepts it. A squash merge is
# GitHub's own commit and costs none: the stub has no reply for it, so a GET would show.
@test "history: only a pull request merged into main accepts a commit that GitHub did not make" {
    local c="repos/$OWNER/example/commits" since=2026-11-01T10:00:00Z
    repo_ok example
    printf '%s\n' $'aaaaaaa1\tweb-flow\ttrue' $'bbbbbbb2\tsomeone\ttrue' \
        $'ccccccc3\tweb-flow\ttrue' $'ddddddd4\tsomeone\tfalse' $'eeeeeee5\tsomeone\ttrue' \
        $'fffffff6\tsomeone\ttrue' |
        gh_reply api --paginate "$c?sha=main&since=$since&per_page=100" --jq "$JQ_DIRECT"
    printf '1\n' | gh_reply api "$c/bbbbbbb2/pulls" --jq "$JQ_MERGED"
    printf '0\n' | gh_reply api "$c/ddddddd4/pulls" --jq "$JQ_MERGED"
    printf '0\n' | gh_reply api "$c/eeeeeee5/pulls" --jq "$JQ_MERGED"
    RC=1 gh_reply api "$c/fffffff6/pulls" --jq "$JQ_MERGED" < /dev/null
    run_status --checks history example
    [ "$status" -eq 1 ]
    has_line example history FAIL "a direct push to main: ddddddd eeeeeee"
    has_line example history FAIL "cannot tell whether these came through a pull request: fffffff"
    [[ $output != *aaaaaaa* && $output != *bbbbbbb* && $output != *ccccccc* ]]

    printf '%s\n' $'aaaaaaa1\tweb-flow\ttrue' $'bbbbbbb2\tsomeone\ttrue' \
        $'ccccccc3\tweb-flow\ttrue' |
        gh_reply api --paginate "$c?sha=main&since=$since&per_page=100" --jq "$JQ_DIRECT"
    run_status --checks history example
    [ "$status" -eq 0 ] || { printf '%s\n' "$output" >&2; return 1; }
    has_line example history ok
}

@test "history: the merged-pull-request filter counts only pull requests merged into main" {
    need command jq
    run jq -r "$JQ_MERGED" <<< '[{"merged_at":"2026-11-02T10:00:00Z","base":{"ref":"main"}},
        {"merged_at":null,"base":{"ref":"main"}}]'
    [ "$output" == 1 ]
    run jq -r "$JQ_MERGED" <<< '[{"merged_at":null,"base":{"ref":"main"}},
        {"merged_at":"2026-11-02T10:00:00Z","base":{"ref":"feat/example"}}]'
    [ "$output" == 0 ]
    run jq -r "$JQ_MERGED" <<< '[]'
    [ "$output" == 0 ]
}

@test "a run needs no config/private-names and has no names check" {
    repo_ok example
    [ ! -e "$SRC/config/private-names" ]
    run_status example
    [[ $output$stderr != *private-names* ]]
    [[ $output != *"example names "* ]]
}

@test "clones: hooks, requireDenylist, the includeIf lines and the denylist counts, never a path" {
    local clone=$BATS_TEST_TMPDIR/clones/example
    git init -q -b main "$clone"
    cp -R "$REPO_ROOT/.githooks" "$clone/.githooks"
    git -C "$clone" config core.hooksPath .githooks
    git -C "$clone" config privacy.requireDenylist true
    git -C "$clone" remote add origin "https://github.com/$OWNER/example.git"
    printf '[includeIf "hasconfig:remote.*.url:https://github.com/%s/example.git"]\n\tpath = hooks.inc\n' \
        "$OWNER" >> "$GIT_CONFIG_GLOBAL"
    mkdir -p "$XDG_CONFIG_HOME/git-privacy"
    printf 'forbidden-term-example\n' > "$DENYLIST"
    git -C "$clone" config privacy.denylist "$DENYLIST"
    run_status --checks clones --clones "example=$clone"
    [ "$status" -eq 0 ] || { printf '%s\n%s\n' "$output" "$stderr" >&2; return 1; }
    has_line example clones ok "hooks on, requireDenylist on, 1 includeIf line(s), 1 denylist source(s), 1 term(s)"
    git -C "$clone" config --unset core.hooksPath
    git -C "$clone" config privacy.requireDenylist false
    run_status --checks clones --clones "example=$clone"
    [ "$status" -eq 1 ]
    has_line example clones FAIL "the hooks are off"
    has_line example clones FAIL "requireDenylist is not on"
    [[ $output$stderr != *"$BATS_TEST_TMPDIR"* && $output$stderr != *"$HOME"* ]]
    [[ $output$stderr != *forbidden-term-example* ]]
}

@test "sweep: mirrors of its own, each commit once, findings as <repo> <sha> <kind>, and pull request texts" {
    local bare=$BATS_TEST_TMPDIR/remotes/example.git work=$BATS_TEST_TMPDIR/work sweep=$BATS_TEST_TMPDIR/sweep sha
    git init -q --bare "$bare"
    git init -q -b main "$work"
    git -C "$work" config user.name "Test User"
    git -C "$work" config user.email test@example.invalid
    printf 'clean\n' > "$work/a.txt"
    git -C "$work" add a.txt
    git -C "$work" -c core.hooksPath=no-hooks commit -q -m "chore: clean"
    git -C "$work" -c core.hooksPath=no-hooks push -q "$bare" main
    mkdir -p "$XDG_CONFIG_HOME/git-privacy"
    printf 'forbidden-term-example\n' > "$DENYLIST"
    git config --global privacy.denylist "$DENYLIST"
    : | gh_reply api --paginate "repos/$OWNER/example/pulls?state=all&sort=updated&direction=desc&per_page=100" --jq "$JQ_PRS"
    : | gh_reply api --paginate "repos/$OWNER/example/releases?per_page=100" --jq "$JQ_RELEASES"
    run_status --checks sweep --sweep "$sweep" --git-base "$BATS_TEST_TMPDIR/remotes" --now 2026-11-13T08:00:00Z example
    [ "$status" -eq 0 ] || { printf '%s\n%s\n' "$output" "$stderr" >&2; return 1; }
    has_line example sweep ok "1 ref(s)"
    [ -d "$sweep/example.git" ]
    printf 'forbidden-term-example\n' > "$work/b.txt"
    git -C "$work" add b.txt
    git -C "$work" -c core.hooksPath=no-hooks commit -q -m "chore: a leak"
    git -C "$work" -c core.hooksPath=no-hooks push -q "$bare" main
    sha=$(git -C "$work" rev-parse --short=7 HEAD)
    printf '5\t2026-11-13T12:00:00Z\n' |
        gh_reply api --paginate "repos/$OWNER/example/pulls?state=all&sort=updated&direction=desc&per_page=100" --jq "$JQ_PRS"
    printf 'A title\nforbidden-term-example\n' | gh_reply api "repos/$OWNER/example/pulls/5" --jq "$JQ_PR_TEXT"
    run_status --checks sweep --sweep "$sweep" --git-base "$BATS_TEST_TMPDIR/remotes" --now 2026-11-14T08:00:00Z example
    [ "$status" -eq 1 ]
    grep -q -x -F "example $sha denylist" <<< "$output"
    grep -q -x -F "example #5 denylist" <<< "$output"
    has_line example sweep FAIL "2 finding(s)"
    [[ $output$stderr != *forbidden-term-example* && $output$stderr != *"$BATS_TEST_TMPDIR"* ]]
    run_status --checks sweep --sweep "$sweep" --git-base "$BATS_TEST_TMPDIR/remotes" --now 2026-11-15T08:00:00Z example
    [[ $output != *"example $sha"* ]]
}

@test "sweep: an edited release note is scanned again, and a run that could not read saves no progress" {
    local bare=$BATS_TEST_TMPDIR/remotes/example.git work=$BATS_TEST_TMPDIR/work sweep=$BATS_TEST_TMPDIR/sweep sha
    local prs="repos/$OWNER/example/pulls?state=all&sort=updated&direction=desc&per_page=100"
    git init -q --bare "$bare"
    git init -q -b main "$work"
    git -C "$work" config user.name "Test User"
    git -C "$work" config user.email test@example.invalid
    printf 'clean\n' > "$work/a.txt"
    git -C "$work" add a.txt
    git -C "$work" -c core.hooksPath=no-hooks commit -q -m "chore: clean"
    git -C "$work" -c core.hooksPath=no-hooks push -q "$bare" main
    mkdir -p "$XDG_CONFIG_HOME/git-privacy"
    printf 'forbidden-term-example\n' > "$DENYLIST"
    git config --global privacy.denylist "$DENYLIST"
    : | gh_reply api --paginate "$prs" --jq "$JQ_PRS"
    printf '9\tv1.0.0\n' | gh_reply api --paginate "repos/$OWNER/example/releases?per_page=100" --jq "$JQ_RELEASES"
    printf 'v1.0.0\nThe notes.\n' | gh_reply api "repos/$OWNER/example/releases/9" --jq "$JQ_RELEASE_TEXT"
    run_status --checks sweep --sweep "$sweep" --git-base "$BATS_TEST_TMPDIR/remotes" --now 2026-11-13T08:00:00Z example
    [ "$status" -eq 0 ] || { printf '%s\n%s\n' "$output" "$stderr" >&2; return 1; }
    # The notes change after the publish; published_at does not.
    printf 'v1.0.0\nforbidden-term-example\n' | gh_reply api "repos/$OWNER/example/releases/9" --jq "$JQ_RELEASE_TEXT"
    run_status --checks sweep --sweep "$sweep" --git-base "$BATS_TEST_TMPDIR/remotes" --now 2026-11-14T08:00:00Z example
    [ "$status" -eq 1 ]
    grep -q -x -F "example v1.0.0 denylist" <<< "$output"
    # A leak, and a pull request text that cannot be read: nothing is saved, so the next run sees both.
    printf 'forbidden-term-example\n' > "$work/b.txt"
    git -C "$work" add b.txt
    git -C "$work" -c core.hooksPath=no-hooks commit -q -m "chore: a leak"
    git -C "$work" -c core.hooksPath=no-hooks push -q "$bare" main
    sha=$(git -C "$work" rev-parse --short=7 HEAD)
    printf '5\t2026-11-14T12:00:00Z\n' | gh_reply api --paginate "$prs" --jq "$JQ_PRS"
    RC=1 gh_reply api "repos/$OWNER/example/pulls/5" --jq "$JQ_PR_TEXT" < /dev/null
    run_status --checks sweep --sweep "$sweep" --git-base "$BATS_TEST_TMPDIR/remotes" --now 2026-11-15T08:00:00Z example
    [ "$status" -eq 1 ]
    grep -q -x -F "example $sha denylist" <<< "$output"
    has_line example sweep FAIL "cannot read #5"
    printf 'A title\nA body.\n' | gh_reply api "repos/$OWNER/example/pulls/5" --jq "$JQ_PR_TEXT"
    run_status --checks sweep --sweep "$sweep" --git-base "$BATS_TEST_TMPDIR/remotes" --now 2026-11-16T08:00:00Z example
    grep -q -x -F "example $sha denylist" <<< "$output"
    [[ $output != *"cannot read"* && $output != *"v1.0.0 denylist"* ]]
}

# Synthetic commits and tag objects of the seal tests.
C100=$(printf '1%.0s' {1..40})
C110=$(printf '2%.0s' {1..40})
T100=$(printf 'a%.0s' {1..40})
T110=$(printf 'b%.0s' {1..40})
T111=$(printf 'c%.0s' {1..40})

# The stub's view of the SEAL=yes repository example: v1.0.0, and v1.1.0 published at $1, both
# drafted by the release workflow, and v1.2.0, which the owner made by hand; the seal refs come
# as "ref TAB type TAB sha" lines on stdin.
seal_view() {
    local r=$OWNER/example
    printf 'NAME=example\nVISIBILITY=private\nRELEASE_KIND=tar\nSEAL=yes\n' |
        gh_reply api -H "$RAW" "repos/$r/contents/.github/standard.conf?ref=main"
    printf 'v1.2.0\t2026-11-14T11:00:00Z\texample-owner\nv1.1.0\t%s\tgithub-actions[bot]\nv1.0.0\t2026-11-01T10:00:00Z\tgithub-actions[bot]\n' "$1" |
        gh_reply api --paginate "repos/$r/releases?per_page=100" --jq "$JQ_SEALABLE"
    gh_reply api --paginate "repos/$r/git/matching-refs/tags/seal/v" --jq "$JQ_REFS"
    printf 'commit\t%s\n' "$C100" | gh_reply api "repos/$r/git/ref/tags/v1.0.0" --jq "$JQ_OBJECT"
    printf 'commit\t%s\n' "$C110" | gh_reply api "repos/$r/git/ref/tags/v1.1.0" --jq "$JQ_OBJECT"
    printf 'commit\t%s\texample v1.0.0\n' "$C100" | gh_reply api "repos/$r/git/tags/$T100" --jq "$JQ_SEAL"
    printf 'commit\t%s\texample v1.1.0\n' "$C110" | gh_reply api "repos/$r/git/tags/$T110" --jq "$JQ_SEAL"
}

@test "seal: the newest release of a SEAL=yes repository warns for 24 hours without its seal, then fails" {
    printf 'refs/tags/seal/v1.0.0\ttag\t%s\n' "$T100" | seal_view 2026-11-14T10:00:00Z
    run_status --checks seal --now 2026-11-14T20:00:00Z example
    [ "$status" -eq 0 ] || { printf '%s\n%s\n' "$output" "$stderr" >&2; return 1; }
    has_line example seal warn "v1.1.0 waits for its Seal click"
    run_status --checks seal --now 2026-11-15T10:00:00Z example
    [ "$status" -eq 1 ]
    has_line example seal FAIL "v1.1.0 has waited 24 hours for its seal"
    # The newer v1.2.0 came from the owner's hand, not the release workflow, so it needs no seal.
    [[ $output != *v1.2.0* ]]
    # A repository without SEAL=yes gets no seal line.
    printf 'NAME=example\nVISIBILITY=private\nRELEASE_KIND=tar\n' |
        gh_reply api -H "$RAW" "repos/$OWNER/example/contents/.github/standard.conf?ref=main"
    run_status --checks seal --now 2026-11-15T10:00:00Z example
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    [ "$(grep -c -v -E '^gh api ' "$STUB_LOG")" -eq 0 ]
}

@test "seal: a sealed release is ok; a seal off its commit, with another message or unannotated fails" {
    local r=$OWNER/example
    printf 'refs/tags/seal/v1.0.0\ttag\t%s\nrefs/tags/seal/v1.1.0\ttag\t%s\n' "$T100" "$T110" |
        seal_view 2026-11-14T10:00:00Z
    run_status --checks seal --now 2026-11-16T10:00:00Z example
    [ "$status" -eq 0 ] || { printf '%s\n%s\n' "$output" "$stderr" >&2; return 1; }
    has_line example seal ok "v1.1.0 is sealed"
    printf 'commit\t%s\texample v1.1.0\n' "$C100" | gh_reply api "repos/$r/git/tags/$T110" --jq "$JQ_SEAL"
    run_status --checks seal --now 2026-11-16T10:00:00Z example
    [ "$status" -eq 1 ]
    has_line example seal FAIL "seal/v1.1.0 is not on the commit of v1.1.0"
    printf 'commit\t%s\tanother v1.1.0\n' "$C110" | gh_reply api "repos/$r/git/tags/$T110" --jq "$JQ_SEAL"
    run_status --checks seal --now 2026-11-16T10:00:00Z example
    has_line example seal FAIL 'the message of seal/v1.1.0 is not "example v1.1.0"'
    printf 'refs/tags/seal/v1.0.0\ttag\t%s\nrefs/tags/seal/v1.1.0\tcommit\t%s\nrefs/tags/seal/v9.9.9\ttag\t%s\n' \
        "$T100" "$C110" "$T111" | gh_reply api --paginate "repos/$r/git/matching-refs/tags/seal/v" --jq "$JQ_REFS"
    printf 'commit\t%s\texample v9.9.9\n' "$C110" | gh_reply api "repos/$r/git/tags/$T111" --jq "$JQ_SEAL"
    RC=1 gh_reply api "repos/$r/git/ref/tags/v9.9.9" --jq "$JQ_OBJECT" < /dev/null
    run_status --checks seal --now 2026-11-16T10:00:00Z example
    [ "$status" -eq 1 ]
    has_line example seal FAIL "seal/v1.1.0 is not an annotated tag"
    has_line example seal FAIL "seal/v9.9.9 has no release tag v9.9.9"
}

@test "seal: with --sweep, a seal that moved or vanished since its first run fails until its line goes" {
    local r=$OWNER/example sweep=$BATS_TEST_TMPDIR/sweep
    printf 'refs/tags/seal/v1.0.0\ttag\t%s\nrefs/tags/seal/v1.1.0\ttag\t%s\n' "$T100" "$T110" |
        seal_view 2026-11-14T10:00:00Z
    run_status --checks seal --sweep "$sweep" --now 2026-11-16T10:00:00Z example
    [ "$status" -eq 0 ] || { printf '%s\n%s\n' "$output" "$stderr" >&2; return 1; }
    [ "$(wc -l < "$sweep/example.seals")" -eq 2 ]
    printf 'refs/tags/seal/v1.1.0\ttag\t%s\n' "$T111" |
        gh_reply api --paginate "repos/$r/git/matching-refs/tags/seal/v" --jq "$JQ_REFS"
    printf 'commit\t%s\texample v1.1.0\n' "$C110" | gh_reply api "repos/$r/git/tags/$T111" --jq "$JQ_SEAL"
    run_status --checks seal --sweep "$sweep" --now 2026-11-17T10:00:00Z example
    [ "$status" -eq 1 ]
    has_line example seal FAIL "seal/v1.1.0 moved"
    has_line example seal FAIL "seal/v1.0.0 vanished"
    run_status --checks seal --sweep "$sweep" --now 2026-11-18T10:00:00Z example
    has_line example seal FAIL "seal/v1.1.0 moved"
    sed -i '/seal\/v1\.1\.0/d; /seal\/v1\.0\.0/d' "$sweep/example.seals"
    run_status --checks seal --sweep "$sweep" --now 2026-11-19T10:00:00Z example
    [ "$status" -eq 0 ] || { printf '%s\n%s\n' "$output" "$stderr" >&2; return 1; }
    [[ $output$stderr != *"$BATS_TEST_TMPDIR"* ]]
}

@test "seal: with --allowed-signers, each seal must verify for maintainer in the sweep's mirror" {
    local bare=$BATS_TEST_TMPDIR/remotes/example.git work=$BATS_TEST_TMPDIR/work sweep=$BATS_TEST_TMPDIR/sweep
    local r=$OWNER/example commit seal
    git init -q --bare "$bare"
    git init -q -b main "$work"
    git -C "$work" config user.name "Test User"
    git -C "$work" config user.email test@example.invalid
    printf '1.1.0\n' > "$work/VERSION"
    git -C "$work" add VERSION
    git -C "$work" -c core.hooksPath=no-hooks commit -q -m "chore(release): 1.1.0"
    git -C "$work" tag v1.1.0
    ssh-keygen -q -t ed25519 -N '' -C seal-test -f "$BATS_TEST_TMPDIR/key"
    ssh-keygen -q -t ed25519 -N '' -C other-test -f "$BATS_TEST_TMPDIR/other"
    git -C "$work" -c gpg.format=ssh -c user.signingKey="$BATS_TEST_TMPDIR/key" \
        tag -s -m "example v1.1.0" seal/v1.1.0 v1.1.0
    git -C "$work" -c core.hooksPath=no-hooks push -q "$bare" main v1.1.0 seal/v1.1.0
    commit=$(git -C "$work" rev-parse HEAD)
    seal=$(git -C "$work" rev-parse refs/tags/seal/v1.1.0)
    # The good file has CRLF line ends, as an editor on Windows may write it.
    printf 'maintainer namespaces="git" %s\r\n' "$(cat "$BATS_TEST_TMPDIR/key.pub")" > "$BATS_TEST_TMPDIR/signers"
    printf 'maintainer namespaces="git" %s\n' "$(cat "$BATS_TEST_TMPDIR/other.pub")" > "$BATS_TEST_TMPDIR/others"
    mkdir -p "$XDG_CONFIG_HOME/git-privacy"
    printf 'forbidden-term-example\n' > "$DENYLIST"
    git config --global privacy.denylist "$DENYLIST"
    : | gh_reply api --paginate "repos/$r/pulls?state=all&sort=updated&direction=desc&per_page=100" --jq "$JQ_PRS"
    : | gh_reply api --paginate "repos/$r/releases?per_page=100" --jq "$JQ_RELEASES"
    printf 'NAME=example\nVISIBILITY=private\nRELEASE_KIND=tar\nSEAL=yes\n' |
        gh_reply api -H "$RAW" "repos/$r/contents/.github/standard.conf?ref=main"
    printf 'v1.1.0\t2026-11-14T10:00:00Z\tgithub-actions[bot]\n' |
        gh_reply api --paginate "repos/$r/releases?per_page=100" --jq "$JQ_SEALABLE"
    printf 'refs/tags/seal/v1.1.0\ttag\t%s\n' "$seal" |
        gh_reply api --paginate "repos/$r/git/matching-refs/tags/seal/v" --jq "$JQ_REFS"
    printf 'commit\t%s\n' "$commit" | gh_reply api "repos/$r/git/ref/tags/v1.1.0" --jq "$JQ_OBJECT"
    printf 'commit\t%s\texample v1.1.0\n' "$commit" | gh_reply api "repos/$r/git/tags/$seal" --jq "$JQ_SEAL"
    # A relative path counts from where the run starts, not from the mirror.
    cd "$BATS_TEST_TMPDIR"
    run_status --checks sweep,seal --sweep "$sweep" --git-base "$BATS_TEST_TMPDIR/remotes" \
        --allowed-signers signers --now 2026-11-14T12:00:00Z example
    [ "$status" -eq 0 ] || { printf '%s\n%s\n' "$output" "$stderr" >&2; return 1; }
    has_line example seal ok "v1.1.0 is sealed"
    run_status --checks sweep,seal --sweep "$sweep" --git-base "$BATS_TEST_TMPDIR/remotes" \
        --allowed-signers "$BATS_TEST_TMPDIR/others" --now 2026-11-14T13:00:00Z example
    [ "$status" -eq 1 ]
    has_line example seal FAIL "seal/v1.1.0 does not verify for maintainer"
    [[ $output$stderr != *"$BATS_TEST_TMPDIR"* ]]
    run_status --checks seal --allowed-signers "$BATS_TEST_TMPDIR/signers" example
    [ "$status" -eq 64 ]
}

@test "pins: an advisory for a pinned action is a FAIL with its id; a newer release 14 days old warns" {
    local action version
    while read -r action version; do
        : | gh_reply api "advisories?ecosystem=actions&affects=$action@$version" --jq "$JQ_GHSA"
        printf 'v%s\t2026-01-01\n' "$version" | gh_reply api "repos/$action/releases/latest" --jq "$JQ_LATEST"
    done < <(pinned_actions "$SRC")
    while read -r _ repo version; do
        printf '%s\t2026-01-01\n' "$version" | gh_reply api "repos/$repo/releases/latest" --jq "$JQ_LATEST"
    done < <(pinned_tools "$SRC")
    run_status --checks pins
    [ "$status" -eq 0 ] || { printf '%s\n%s\n' "$output" "$stderr" >&2; return 1; }
    has_line repo-standard pins ok
    printf 'GHSA-aaaa-bbbb-cccc\n' | gh_reply api "advisories?ecosystem=actions&affects=actions/checkout@7.0.1" --jq "$JQ_GHSA"
    printf 'v7.2.0\t2026-10-01\n' | gh_reply api "repos/actions/setup-python/releases/latest" --jq "$JQ_LATEST"
    printf 'v8.0.0\t2026-11-10\n' | gh_reply api "repos/actions/attest/releases/latest" --jq "$JQ_LATEST"
    run_status --checks pins
    [ "$status" -eq 1 ]
    has_line repo-standard pins FAIL "actions/checkout 7.0.1: GHSA-aaaa-bbbb-cccc"
    has_line repo-standard pins FAIL "actions/setup-python v7.2.0 is out"
    [[ $output != *"actions/attest v8.0.0"* ]]
}

@test "tokens: 30 days before the expiry a warning, after it a FAIL, and no line without dates" {
    run_status --checks tokens
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    run_status --checks tokens --token sessions=2026-12-01
    [ "$status" -eq 0 ]
    has_line sessions tokens warn "expires in 18 days"
    run_status --checks tokens --token sessions=2026-11-01
    [ "$status" -eq 1 ]
    has_line sessions tokens FAIL "expired 12 days ago"
    run_status --checks tokens --token sessions=2027-06-01
    has_line sessions tokens ok
    run_status --token sessions=tomorrow
    [ "$status" -eq 64 ]
}
