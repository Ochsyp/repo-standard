#!/usr/bin/env bats
# manifest.bats of repo-standard: tools/manifest over a small source repository (profiles,
# modes, block ids, what stays out, --check and --rev), over this repository, and lint of the
# repository's own scripts in tools/ and ci/.

# The sh -c scripts are single-quoted, and bats runs each test in a subshell, both on purpose.
# shellcheck disable=SC2016,SC2030,SC2031
load helpers

setup() {
    isolate_home
}

# Run tools/manifest with ARGS in $REPO through bats `run`, stderr apart.
run_manifest() {
    run --separate-stderr sh -c 'cd "$1" && shift && exec sh tools/manifest "$@"' sh "$REPO" "$@"
}

# A source repository at $REPO, all staged: the hooks and bin/ as copies, three workflows, a
# LICENSE, VERSION, three block bodies and tools/manifest itself.
make_source() {
    make_repo
    printf '1.0.0-dev\n' > "$REPO/VERSION"
    printf 'Synthetic licence text.\n' > "$REPO/LICENSE"
    mkdir -p "$REPO/.github/workflows" "$REPO/blocks/SECURITY.md" "$REPO/blocks/CONTRIBUTING.md" \
        "$REPO/blocks/_gitattributes" "$REPO/tools"
    printf 'name: ci\n' > "$REPO/.github/workflows/ci.yml"
    printf 'name: release\n' > "$REPO/.github/workflows/release.yml"
    printf 'name: bootstrap\n' > "$REPO/.github/workflows/bootstrap.yml"
    printf 'Report to the maintainer.\n' > "$REPO/blocks/SECURITY.md/reporting@private.md"
    printf 'Release in the browser.\n' > "$REPO/blocks/CONTRIBUTING.md/releasing.md"
    printf '* text=auto eol=lf\n' > "$REPO/blocks/_gitattributes/gitattributes"
    cp "$REPO_ROOT/tools/manifest" "$REPO/tools/manifest"
    git -C "$REPO" add -A
    stage_executables
}

# Fail unless $output has a MANIFEST line TYPE PROFILE ID MODE PATH.
has_entry() {
    if ! awk -v t="$1" -v p="$2" -v i="$3" -v m="$4" -v e="$5" \
        '$1 == t && $2 == p && $3 == i && $4 == m && $5 == e { found = 1 } END { exit !found }' \
        <<< "$output"; then
        printf 'no entry %s %s %s %s %s in:\n%s\n' "$@" "$output" >&2
        return 1
    fi
}

@test "tools/manifest lists the copies with profiles and modes, and the blocks with theirs" {
    make_source
    run_manifest --print
    [ "$status" -eq 0 ]
    [[ $output == *$'\nstandard 1.0.0-dev\n'* ]]
    has_entry file all "$(git -C "$REPO" rev-parse :.githooks/pre-commit)" 100755 .githooks/pre-commit
    has_entry file all "$(git -C "$REPO" rev-parse :.githooks/lib.sh)" 100644 .githooks/lib.sh
    has_entry file all "$(git -C "$REPO" rev-parse :.github/workflows/ci.yml)" 100644 .github/workflows/ci.yml
    has_entry file release "$(git -C "$REPO" rev-parse :.github/workflows/release.yml)" 100644 \
        .github/workflows/release.yml
    has_entry file mit "$(git -C "$REPO" rev-parse :LICENSE)" 100644 LICENSE
    has_entry block private "$(git -C "$REPO" rev-parse ':blocks/SECURITY.md/reporting@private.md')" - \
        'SECURITY.md#reporting@private'
    has_entry block release "$(git -C "$REPO" rev-parse :blocks/CONTRIBUTING.md/releasing.md)" - \
        'CONTRIBUTING.md#releasing'
    has_entry block all "$(git -C "$REPO" rev-parse :blocks/_gitattributes/gitattributes)" - \
        '.gitattributes#gitattributes'
}

@test "tools/manifest leaves out the MANIFEST, bootstrap.yml and the repository's own files" {
    make_source
    run_manifest
    [ "$status" -eq 0 ]
    git -C "$REPO" add .github/standard/MANIFEST
    run_manifest --print
    [ "$status" -eq 0 ]
    # The paths of the entries; the header's own words do not count.
    run grep -E -x -e '\.github/standard/MANIFEST|\.github/workflows/bootstrap\.yml' \
        -e 'VERSION|tools/manifest|blocks/.*' <<< "$(awk '$1 == "file" || $1 == "block" { print $5 }' <<< "$output")"
    [ "$status" -eq 1 ]
}

@test "tools/manifest refuses a block of an unknown variant and a body outside a file folder" {
    local name
    # An unknown variant, built from fragments: the whole name would read as an e-mail address.
    name=$(printf 'reporting@%s.md' internal)
    make_source
    printf 'x\n' > "$REPO/blocks/SECURITY.md/$name"
    git -C "$REPO" add -A
    run_manifest --print
    [ "$status" -ne 0 ]
    [[ $stderr == *"$name: not blocks/<file>/<name>[@public|@private|@seal]"* ]]
    git -C "$REPO" rm -q --cached "blocks/SECURITY.md/$name"
    printf 'x\n' > "$REPO/blocks/stray.md"
    git -C "$REPO" add blocks/stray.md
    run_manifest --print
    [ "$status" -ne 0 ]
    [[ $stderr == *"blocks/stray.md: a block body sits in blocks/<file>/"* ]]
}

@test "--check fails on a stale MANIFEST and passes once it is rebuilt; --rev reads a commit" {
    make_source
    run_manifest
    git -C "$REPO" add .github/standard/MANIFEST
    run_manifest --check
    [ "$status" -eq 0 ]
    git -C "$REPO" -c core.hooksPath=no-hooks commit -q -m "chore: the source"
    printf '# edited\n' >> "$REPO/.githooks/rules/vm"
    git -C "$REPO" add .githooks/rules/vm
    run_manifest --check
    [ "$status" -eq 1 ]
    [[ $stderr == *"differs from the files; run tools/manifest"* ]]
    run_manifest --check --rev HEAD
    [ "$status" -eq 0 ]
}

@test "this repository's MANIFEST matches its files" {
    REPO=$REPO_ROOT
    run_manifest --check
    [ "$status" -eq 0 ]
}

# bats test_tags=lint
@test "ShellCheck reports nothing in tools/, ci/ and tests/" {
    need command shellcheck
    run_shellcheck tools/manifest ci/test tests/helpers.bash tests/manifest.bats
    [ "$status" -eq 0 ] || { printf '%s\n' "$output" >&2; return 1; }
}
