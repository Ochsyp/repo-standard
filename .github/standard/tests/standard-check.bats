#!/usr/bin/env bats
# standard-check.bats of the repository standard: the same file in every repository; never edit
# it here. standard-check's rules against good and bad fixture repositories: the copies, blocks
# and modes the MANIFEST lists, the owned files' forms, removed paths, the pull request rules on
# copies and loosening, ROLE=source, --local, and the pre-commit hook's call of --staged.

# The sh -c scripts are single-quoted, and bats runs each test in a subshell, both on purpose.
# shellcheck disable=SC2016,SC2030,SC2031
load lib

setup() {
    isolate_home
}

# Run standard-check MODE in $REPO through bats `run`, stderr apart.
check() {
    run --separate-stderr sh -c 'cd "$1" && exec sh .github/standard/bin/standard-check "$2"' \
        sh "$REPO" "$1"
}

# Print a block: its begin marker, the body file BODY of this repository's blocks/, its end
# marker. NAME and STYLE (md or hash) pick the markers.
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

# Print the blob id of this repository's block body FILE.
body_id() {
    git hash-object --no-filters "$REPO_ROOT/blocks/$1"
}

# Write and stage $REPO's MANIFEST: every copy under .githooks/ and .github/standard/, LICENSE
# (profile mit), the release workflow when present (profile release), and three blocks.
write_manifest() {
    local mode oid path profile
    {
        printf '# Repository standard 1.0.0. Written by tools/manifest; never edit it.\n'
        printf 'standard 1.0.0\n'
        while read -r mode oid _ path; do
            case $path in
                .github/standard/MANIFEST) continue ;;
                LICENSE) profile=mit ;;
                .github/workflows/release.yml) profile=release ;;
                *) profile=all ;;
            esac
            printf 'file %s %s %s %s\n' "$profile" "$oid" "$mode" "$path"
        done < <(git -C "$REPO" ls-files -s -- .githooks .github/standard .github/workflows LICENSE)
        printf 'block all %s - .github/dependabot.yml#dependabot\n' \
            "$(body_id _github/dependabot.yml/dependabot.yml)"
        printf 'block public %s - SECURITY.md#reporting@public\n' "$(body_id SECURITY.md/reporting@public.md)"
        printf 'block private %s - SECURITY.md#reporting@private\n' "$(body_id SECURITY.md/reporting@private.md)"
    } > "$REPO/.github/standard/MANIFEST"
    git -C "$REPO" add .github/standard/MANIFEST
}

# Commit what is staged in $REPO with the hooks off.
commit_unchecked() {
    git -C "$REPO" -c core.hooksPath=no-hooks commit -q -m "$1"
}

# Build a public repository at $REPO that holds the standard, committed on main, and switch to
# feat/example. The copies are this repository's hooks and bin/.
make_consumer() {
    make_repo
    write_config VISIBILITY=public PRIVACY_RULES=base
    printf '1.0.0\n' > "$REPO/VERSION"
    printf 'Synthetic licence text.\n' > "$REPO/LICENSE"
    mkdir -p "$REPO/ci"
    printf '#!/bin/sh\nexit 0\n' > "$REPO/ci/test"
    { block dependabot hash _github/dependabot.yml/dependabot.yml
      printf '  - package-ecosystem: github-actions\n    directory: /\n'
      printf '    schedule:\n      interval: weekly\n    open-pull-requests-limit: 0\n'; } \
        > "$REPO/.github/dependabot.yml"
    { printf '# Security\n\n'; block reporting md SECURITY.md/reporting@public.md; } > "$REPO/SECURITY.md"
    git -C "$REPO" add -A
    stage_executables
    write_manifest
    commit_unchecked "chore: adopt the standard"
    git -C "$REPO" switch -q -c feat/example
}

@test "a repository that holds the standard passes --ci and --staged" {
    make_consumer
    check --ci
    [ "$status" -eq 0 ]
    [ "$output" = "standard-check: ok" ]
    check --staged
    [ "$status" -eq 0 ]
}

@test "a changed copy, a wrong mode and a missing copy fail" {
    make_consumer
    printf '# edited\n' >> "$REPO/.githooks/pre-push"
    git -C "$REPO" add .githooks/pre-push
    git -C "$REPO" update-index --chmod=-x .githooks/commit-msg
    git -C "$REPO" rm -q --cached .githooks/rules/vm
    check --staged
    [ "$status" -eq 1 ]
    [[ $stderr == *".githooks/pre-push: differs from the MANIFEST"* ]]
    [[ $stderr == *".githooks/commit-msg: mode 100644, the MANIFEST says 100755"* ]]
    [[ $stderr == *".githooks/rules/vm: missing (the MANIFEST lists it)"* ]]
}

@test "a file of the standard's folders that the MANIFEST does not list fails" {
    make_consumer
    mkdir -p "$REPO/.github/workflows"
    printf 'name: own\n' > "$REPO/.github/workflows/own.yml"
    printf '#!/bin/sh\n' > "$REPO/.githooks/post-checkout"
    git -C "$REPO" add .github/workflows/own.yml .githooks/post-checkout
    check --staged
    [ "$status" -eq 1 ]
    [[ $stderr == *".github/workflows/own.yml: not in the MANIFEST"* ]]
    [[ $stderr == *".githooks/post-checkout: not in the MANIFEST"* ]]
}

@test "a block that differs, is missing or appears twice fails, and its variant follows VISIBILITY" {
    make_consumer
    sed -i 's/Do not open/Never open/' "$REPO/SECURITY.md"
    git -C "$REPO" add SECURITY.md
    check --staged
    [[ $stderr == *"SECURITY.md#reporting@public: the block differs from the MANIFEST"* ]]
    printf '# Security\n' > "$REPO/SECURITY.md"
    git -C "$REPO" add SECURITY.md
    check --staged
    [[ $stderr == *"SECURITY.md#reporting@public: the block's markers are missing"* ]]
    { block reporting md SECURITY.md/reporting@public.md; block reporting md SECURITY.md/reporting@public.md; } \
        > "$REPO/SECURITY.md"
    git -C "$REPO" add SECURITY.md
    check --staged
    [[ $stderr == *"the block's markers appear more than once or out of order"* ]]
    # A private repository needs the private variant.
    block reporting md SECURITY.md/reporting@public.md > "$REPO/SECURITY.md"
    write_config VISIBILITY=private PRIVACY_RULES=base
    git -C "$REPO" add SECURITY.md .github/standard.conf
    check --staged
    [ "$status" -eq 1 ]
    [[ $stderr == *"SECURITY.md#reporting@private: the block differs from the MANIFEST"* ]]
    block reporting md SECURITY.md/reporting@private.md > "$REPO/SECURITY.md"
    git -C "$REPO" add SECURITY.md
    check --staged
    [ "$status" -eq 0 ]
}

@test "under RELEASE_KIND=legacy a release workflow needs only to exist" {
    make_consumer
    mkdir -p "$REPO/.github/workflows"
    printf 'name: release\n' > "$REPO/.github/workflows/release.yml"
    git -C "$REPO" add .github/workflows/release.yml
    write_manifest
    commit_unchecked "ci: add the release workflow"
    printf 'name: release\non: push\n' > "$REPO/.github/workflows/release.yml"
    git -C "$REPO" add .github/workflows/release.yml
    check --staged
    [ "$status" -eq 1 ]
    [[ $stderr == *".github/workflows/release.yml: differs from the MANIFEST"* ]]
    write_config VISIBILITY=public PRIVACY_RULES=base RELEASE_KIND=legacy
    git -C "$REPO" add .github/standard.conf
    check --staged
    [ "$status" -eq 0 ]
}

@test "LICENSE follows the LICENSE key" {
    make_consumer
    write_config VISIBILITY=public PRIVACY_RULES=base LICENSE=none
    git -C "$REPO" add .github/standard.conf
    check --staged
    [[ $stderr == *"LICENSE: exists, but the config says LICENSE=none"* ]]
    git -C "$REPO" rm -q --cached LICENSE
    check --staged
    [[ $stderr != *"LICENSE:"* ]]
}

@test "VERSION and VERSION_COPY need their form" {
    local bad
    make_consumer
    for bad in '01.0.0' '1.0' '1.0.0-rc1' $'1.0.0\r' $'\357\273\2771.0.0'; do
        printf '%s\n' "$bad" > "$REPO/VERSION"
        git -C "$REPO" add VERSION
        check --staged
        [[ $stderr == *"VERSION: not one line X.Y.Z or X.Y.Z-dev"* ]] ||
            { printf 'not refused: %q\n' "$bad" >&2; return 1; }
    done
    printf '1.1.0-dev\n' > "$REPO/VERSION"
    printf 'version=1.0.0\n' > "$REPO/version.txt"
    write_config VISIBILITY=public PRIVACY_RULES=base 'VERSION_COPY=version.txt|version=X.Y.Z'
    git -C "$REPO" add VERSION version.txt .github/standard.conf
    check --staged
    [[ $stderr == *"version.txt: does not hold the VERSION_COPY line for 1.1.0-dev"* ]]
    printf 'version=1.1.0-dev\n' > "$REPO/version.txt"
    git -C "$REPO" add version.txt
    check --staged
    [ "$status" -eq 0 ]
}

@test "dependabot.yml needs the github-actions entry for / at limit 0" {
    make_consumer
    sed -i 's/open-pull-requests-limit: 0/open-pull-requests-limit: 5/' "$REPO/.github/dependabot.yml"
    git -C "$REPO" add .github/dependabot.yml
    check --staged
    [[ $stderr == *"the github-actions entry needs open-pull-requests-limit: 0"* ]]
    sed -i 's/package-ecosystem: github-actions/package-ecosystem: npm/' "$REPO/.github/dependabot.yml"
    git -C "$REPO" add .github/dependabot.yml
    check --staged
    [[ $stderr == *"no github-actions entry for /"* ]]
}

@test "a stage needs its ci/ script, and tests/helpers.bash must source lib.bash" {
    make_consumer
    write_config VISIBILITY=public PRIVACY_RULES=base 'CI_STAGES=lint test'
    mkdir -p "$REPO/tests"
    printf '# shellcheck shell=bash\n' > "$REPO/tests/helpers.bash"
    git -C "$REPO" add .github/standard.conf tests/helpers.bash
    check --staged
    [[ $stderr == *"ci/lint: missing (CI_STAGES lists lint)"* ]]
    [[ $stderr == *"tests/helpers.bash: does not source .github/standard/tests/lib.bash"* ]]
    printf '#!/bin/sh\nexit 0\n' > "$REPO/ci/lint.ps1"
    printf 'source "${BASH_SOURCE[0]%%/*}/../.github/standard/tests/lib.bash"\n' > "$REPO/tests/helpers.bash"
    git -C "$REPO" add ci/lint.ps1 tests/helpers.bash
    check --staged
    [ "$status" -eq 0 ]
}

@test "gitleaks' inline allow marker and a removed path fail" {
    make_consumer
    printf 'key = 1 # %s:%s\n' gitleaks allow > "$REPO/notes.txt"
    printf '[extend]\n' > "$REPO/.gitleaks.toml"
    git -C "$REPO" add notes.txt .gitleaks.toml
    check --staged
    [ "$status" -eq 1 ]
    [[ $stderr == *"notes.txt: holds gitleaks' inline allow marker"* ]]
    [[ $stderr == *".gitleaks.toml: removed by the standard; delete it"* ]]
}

@test "--ci compares VISIBILITY with GitHub" {
    make_consumer
    PRIVATE=true check --ci
    [ "$status" -eq 1 ]
    [[ $stderr == *"VISIBILITY=public, but GitHub says private"* ]]
    PRIVATE=false check --ci
    [ "$status" -eq 0 ]
}

@test "--ci on a pull request: a copy changes only on a chore/standard-* branch of this repository" {
    local base
    make_consumer
    base=$(git -C "$REPO" rev-parse main)
    printf '# edited\n' >> "$REPO/.githooks/pre-push"
    git -C "$REPO" add .githooks/pre-push
    write_manifest
    commit_unchecked "chore: change a copy"
    export EVENT=pull_request BASE=$base REPO_NAME=owner/example
    REPO_SLUG=owner/example
    HEAD_REF=feat/example HEAD_REPO=$REPO_SLUG REPO=$REPO_SLUG run --separate-stderr sh -c \
        'cd "$1" && exec sh .github/standard/bin/standard-check --ci' sh "$BATS_TEST_TMPDIR/repo"
    [ "$status" -eq 1 ]
    [[ $stderr == *"a copy of the standard changes outside a chore/standard-* branch"* ]]
    HEAD_REF=chore/standard-1.0.1 HEAD_REPO=someone/example REPO=$REPO_SLUG run --separate-stderr \
        sh -c 'cd "$1" && exec sh .github/standard/bin/standard-check --ci' sh "$BATS_TEST_TMPDIR/repo"
    [ "$status" -eq 1 ]
    [[ $stderr == *"changes on a branch of another repository"* ]]
    HEAD_REF=chore/standard-1.0.1 HEAD_REPO=$REPO_SLUG REPO=$REPO_SLUG run --separate-stderr \
        sh -c 'cd "$1" && exec sh .github/standard/bin/standard-check --ci' sh "$BATS_TEST_TMPDIR/repo"
    [ "$status" -eq 0 ]
}

@test "--ci on a pull request: loosening needs a chore/privacy-* pull request of its own" {
    local base dir=$BATS_TEST_TMPDIR/repo
    make_consumer
    base=$(git -C "$REPO" rev-parse main)
    write_config VISIBILITY=public PRIVACY_RULES=
    git -C "$REPO" add .github/standard.conf
    commit_unchecked "chore: drop the base pack"
    export EVENT=pull_request BASE=$base
    HEAD_REF=feat/example HEAD_REPO=o/r REPO=o/r run --separate-stderr sh -c \
        'cd "$1" && exec sh .github/standard/bin/standard-check --ci' sh "$dir"
    [ "$status" -eq 1 ]
    [[ $stderr == *"loosens a check (a dropped rule pack"* ]]
    HEAD_REF=chore/privacy-drop HEAD_REPO=o/r REPO=o/r run --separate-stderr sh -c \
        'cd "$1" && exec sh .github/standard/bin/standard-check --ci' sh "$dir"
    [ "$status" -eq 0 ]
    printf 'notes\n' > "$dir/notes.txt"
    git -C "$dir" add notes.txt
    git -C "$dir" -c core.hooksPath=no-hooks commit -q -m "docs: add notes"
    HEAD_REF=chore/privacy-drop HEAD_REPO=o/r REPO=o/r run --separate-stderr sh -c \
        'cd "$1" && exec sh .github/standard/bin/standard-check --ci' sh "$dir"
    [ "$status" -eq 1 ]
    [[ $stderr == *"may change only .github/standard.conf, .gitleaksignore and CHANGELOG.md"* ]]
}

@test "pre-commit refuses a staged copy that differs from the MANIFEST" {
    make_consumer
    printf '# edited\n' >> "$REPO/.githooks/rules/vm"
    git -C "$REPO" add .githooks/rules/vm
    try_commit "chore: edit a copy"
    [ "$status" -ne 0 ]
    [[ $output == *".githooks/rules/vm: differs from the MANIFEST"* ]]
}

@test "--local reports the hooks and the denylist counts, and fails when the hooks are off" {
    make_consumer
    write_denylist
    check --local
    [ "$status" -eq 0 ]
    [[ $output == *"standard-check: hooks: on"* ]]
    [[ $output == *"denylists: 1 source(s), 1 term(s), 0 missing, 0 with NUL bytes"* ]]
    refute_term_shown
    git -C "$REPO" config --unset core.hooksPath
    check --local
    [ "$status" -eq 1 ]
    [[ $stderr == *"the hooks are off here"* ]]
}

@test "--local warns about a remote of another owner, as in a fork clone" {
    make_consumer
    write_denylist
    git -C "$REPO" remote add origin https://github.com/someone/example.git
    git -C "$REPO" remote add upstream https://github.com/owner/example.git
    check --local
    [[ $stderr == *"warning: remote upstream is example of another owner than origin"* ]]
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
