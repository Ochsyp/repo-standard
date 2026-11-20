#!/usr/bin/env bats
# source-check.bats of repo-standard: what holds only here, where tools/manifest and blocks/
# exist: standard-check with ROLE=source, every rule pack over this repository's whole tree, and
# the order in which the standard block tells a repository to go public.
# The vendored suites run in every repository of the standard and must not need these paths.

# The sh -c scripts are single-quoted, and bats runs each test in a subshell, both on purpose.
# shellcheck disable=SC2016,SC2030,SC2031
load helpers

setup() {
    isolate_home
}

# Run standard-check MODE in $REPO through bats `run`, stderr apart.
check() {
    run --separate-stderr sh -c 'cd "$1" && exec sh .github/standard/bin/standard-check "$2"' \
        sh "$REPO" "$1"
}

# Print block NAME in STYLE (md or hash) with the body BODY of this repository's blocks/.
block() {
    local name=$1 style=$2 body=$3
    if [[ $style == md ]]; then
        printf '<!-- standard:begin %s -->\n' "$name"
        cat "$REPO_ROOT/blocks/$body"
        printf '<!-- standard:end %s -->\n' "$name"
    else
        printf '# standard:begin %s\n' "$name"
        cat "$REPO_ROOT/blocks/$body"
        printf '# standard:end %s\n' "$name"
    fi
}

# Commit what is staged in $REPO with the hooks off.
commit_unchecked() {
    git -C "$REPO" -c core.hooksPath=no-hooks commit -q -m "$1"
}

@test "repo-standard's own documents hold the block variants its VISIBILITY selects" {
    # No sync writes the source's own blocks, so this test holds them to the config instead.
    local vis file name body
    vis=$(sh "$REPO_ROOT/.github/standard/bin/conf" --get VISIBILITY "$REPO_ROOT/.github/standard.conf")
    for file in SECURITY.md:reporting SECURITY.md:automated-checks CONTRIBUTING.md:guard-rails; do
        name=${file#*:}
        file=${file%%:*}
        body=$(awk -v n="$name" '
            $0 == "<!-- standard:end " n " -->" { exit }
            on { print }
            $0 == "<!-- standard:begin " n " -->" { on = 1 }' "$REPO_ROOT/$file")
        [ "$body" = "$(cat "$REPO_ROOT/blocks/$file/$name@$vis.md")" ] ||
            { printf '%s#%s is not the %s variant\n' "$file" "$name" "$vis" >&2; return 1; }
    done
}

@test "the standard block gives the order for going public: pull request, switch, commit, merge" {
    # The pull request that sets VISIBILITY=public fails standard-check until GitHub says public.
    # Only these tokens are checked, in order, so the wording around them may change.
    local text
    text=$(tr '\n' ' ' < "$REPO_ROOT/blocks/CONTRIBUTING.md/standard.md")
    [[ $text == *'VISIBILITY=public'*'on GitHub'*'settings'*'new commit'*'merges'* ]] ||
        { echo "blocks/CONTRIBUTING.md/standard.md does not give that order" >&2; return 1; }
}

@test "repo-standard's whole tree passes every rule pack" {
    REPO="$BATS_TEST_TMPDIR/copy"
    git -C "$REPO_ROOT" checkout-index -a --prefix="$REPO/"
    git init -q -b main "$REPO"
    git -C "$REPO" config user.name "Test User"
    git -C "$REPO" config user.email test@example.invalid
    git -C "$REPO" config core.autocrlf false
    git -C "$REPO" add -A
    commit_config 'PRIVACY_RULES=base disk vm'
    run --separate-stderr sh -c 'cd "$1" && exec sh .githooks/privacy-scan --tracked' sh "$REPO"
    [ "$status" -eq 0 ]
}

@test "ROLE=source: a stale MANIFEST is a notice, and an error on a release pull request" {
    local base dir=$BATS_TEST_TMPDIR/repo
    make_repo
    write_config ROLE=source PRIVACY_RULES=base
    printf '1.0.0\n' > "$REPO/VERSION"
    printf 'Synthetic licence text.\n' > "$REPO/LICENSE"
    mkdir -p "$REPO/ci" "$REPO/tools"
    printf '#!/bin/sh\nexit 0\n' > "$REPO/ci/test"
    cp "$REPO_ROOT/tools/manifest" "$REPO/tools/manifest"
    cp -R "$REPO_ROOT/blocks" "$REPO/blocks"
    { block dependabot hash _github/dependabot.yml/dependabot.yml
      printf '  - package-ecosystem: github-actions\n    directory: /\n'; } > "$REPO/.github/dependabot.yml"
    git -C "$REPO" add -A
    stage_executables
    (cd "$REPO" && sh tools/manifest)
    git -C "$REPO" add .github/standard/MANIFEST
    commit_unchecked "chore: the source"
    base=$(git -C "$REPO" rev-parse HEAD)
    check --ci
    [ "$status" -eq 0 ]
    printf '# edited\n' >> "$REPO/.githooks/rules/vm"
    git -C "$REPO" add .githooks/rules/vm
    commit_unchecked "fix: edit a rule pack"
    check --ci
    [ "$status" -eq 0 ]
    [[ $stderr == *"notice: .github/standard/MANIFEST differs from the tree"* ]]
    printf '1.0.1\n' > "$REPO/VERSION"
    git -C "$REPO" add VERSION
    commit_unchecked "chore: release 1.0.1"
    EVENT=pull_request BASE=$base run --separate-stderr sh -c \
        'cd "$1" && exec sh .github/standard/bin/standard-check --ci' sh "$dir"
    [ "$status" -eq 1 ]
    [[ $stderr == *".github/standard/MANIFEST: differs from the tree; run tools/manifest"* ]]
    # A copy that names a private repository fails as well.
    printf 'example-private\n' > "$REPO/config-names"
    mkdir -p "$REPO/config"
    mv "$REPO/config-names" "$REPO/config/private-names"
    printf '# see example-private\n' >> "$REPO/.githooks/rules/disk"
    git -C "$REPO" add config/private-names .githooks/rules/disk
    (cd "$REPO" && sh tools/manifest)
    git -C "$REPO" add .github/standard/MANIFEST
    check --staged
    [ "$status" -eq 1 ]
    [[ $stderr == *".githooks/rules/disk: names a private repository"* ]]
}

# A source repository at $REPO, committed as repo-standard holds it: ROLE=source, the copies,
# blocks/, tools/manifest and a MANIFEST that matches them.
make_source_check_repo() {
    make_repo
    write_config ROLE=source PRIVACY_RULES=base
    printf '1.0.0\n' > "$REPO/VERSION"
    printf 'Synthetic licence text.\n' > "$REPO/LICENSE"
    mkdir -p "$REPO/ci" "$REPO/tools"
    printf '#!/bin/sh\nexit 0\n' > "$REPO/ci/test"
    cp "$REPO_ROOT/tools/manifest" "$REPO/tools/manifest"
    cp -R "$REPO_ROOT/blocks" "$REPO/blocks"
    { block dependabot hash _github/dependabot.yml/dependabot.yml
      printf '  - package-ecosystem: github-actions\n    directory: /\n'; } > "$REPO/.github/dependabot.yml"
    git -C "$REPO" add -A
    stage_executables
    (cd "$REPO" && sh tools/manifest)
    git -C "$REPO" add .github/standard/MANIFEST
    commit_unchecked "chore: the source"
}

@test "ROLE=source: a template that names a private repository fails, as a copy does" {
    make_source_check_repo
    mkdir -p "$REPO/config" "$REPO/templates"
    printf 'example-private\n' > "$REPO/config/private-names"
    printf '# Security\n\nAsk example-private.\n' > "$REPO/templates/SECURITY.md"
    git -C "$REPO" add config/private-names templates/SECURITY.md
    (cd "$REPO" && sh tools/manifest)
    git -C "$REPO" add .github/standard/MANIFEST
    check --staged
    [ "$status" -eq 1 ]
    [[ $stderr == *"templates/SECURITY.md: names a private repository"* ]]
}

@test "no copy and no block names the owner of this repository, LICENSE aside" {
    local owner type oid path
    owner=${GITHUB_REPOSITORY%%/*}
    if [[ -z $owner ]]; then
        owner=$(git -C "$REPO_ROOT" remote get-url origin 2> /dev/null |
            sed -n 's#.*github\.com[:/]\([^/]*\)/.*#\1#p')
    fi
    [[ -n $owner ]] || { echo "neither GITHUB_REPOSITORY nor a github.com origin names the owner" >&2; return 1; }
    # MIT names its copyright holder in LICENSE. Every other copy and block lands in each
    # repository of the standard and names no account; the name is read here and never printed.
    while read -r type _ oid _ path; do
        [[ $type == file || $type == block ]] || continue
        [[ $path != LICENSE ]] || continue
        if git -C "$REPO_ROOT" cat-file blob "$oid" | grep -q -i -F -e "$owner"; then
            printf '%s names the owner of this repository\n' "${path%%#*}" >&2
            return 1
        fi
    done < "$REPO_ROOT/.github/standard/MANIFEST"
}

@test "bats --count honours --filter-tags, so a count check over a filtered run holds" {
    local all filtered
    all=$(bats --count "$REPO_ROOT/.github/standard/tests/lint.bats")
    filtered=$(bats --count --filter-tags '!lint' "$REPO_ROOT/.github/standard/tests/lint.bats")
    (( all > 0 ))
    [ "$filtered" -eq 0 ]
}
