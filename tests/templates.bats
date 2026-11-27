#!/usr/bin/env bats
# templates.bats of repo-standard: the starters in templates/ that an adoption copies and fills
# in. Each parses or passes its checker: the config through conf, CHANGELOG.md through
# release-meta. CONTRIBUTING.md and SECURITY.md hold the markers of every block of blocks/ in
# order, and their own sections. tests/helpers.bash sources the standard's lib.bash. Each ci/
# starter passes its shell's syntax check and is stored with the mode it needs. sync.bats builds a
# consumer from them with tools/sync --init.

# The sh -c scripts and the PowerShell commands are single-quoted, and bats runs each test in a
# subshell, both on purpose.
# shellcheck disable=SC2016,SC2030,SC2031
load helpers

setup() {
    isolate_home
    T=$REPO_ROOT/templates
}

# Print the block markers of the file $1 in their order, as "begin NAME" and "end NAME".
markers() {
    grep -o -E '(<!-- |# )standard:(begin|end) [a-z-]+' "$1" | sed -e 's/^<!-- //' -e 's/^# //' \
        -e 's/^standard://'
}

# Print the names of the blocks that blocks/ holds for the file $1, without variants, sorted. A
# seal variant is left out: one that replaces a block shares its markers, and a block that exists
# only as a seal variant gets its markers from tools/sync, only where SEAL=yes.
block_names() {
    local body
    for body in "$REPO_ROOT/blocks/$1"/*; do
        body=${body##*/}
        body=${body%.md}
        [[ $body != *@seal ]] || continue
        printf '%s\n' "${body%%@*}"
    done | LC_ALL=C sort -u
}

@test "the config template parses and shows every key of the standard" {
    local key
    run sh "$REPO_ROOT/.github/standard/bin/conf" --check "$T/standard.conf"
    [ "$status" -eq 0 ] || { printf '%s\n' "$output" >&2; return 1; }
    for key in NAME VISIBILITY ROLE LICENSE CI_RUNNER CI_STAGES CI_WEEKLY PYTHON PS_MODULES \
        IMAGE_PLATFORMS RELEASE_KIND RELEASE_RUNNER RELEASE_MANIFEST RELEASE_ASSETS VERSION_COPY \
        SEAL PRIVACY_RULES PRIVACY_ALLOW PRIVACY_HISTORY_ACCEPT MAX_BLOB_KB; do
        grep -q -E "^(# )?$key=" "$T/standard.conf" || { printf '%s is missing\n' "$key" >&2; return 1; }
    done
    [ "$(sh "$REPO_ROOT/.github/standard/bin/conf" --get PRIVACY_RULES "$T/standard.conf")" = base ]
    # An adopter pastes this command, so it names the tool by its real path.
    grep -q -F 'run sh .github/standard/bin/conf --check' "$T/standard.conf"
}

@test "the CHANGELOG template passes release-meta with VERSION 0.0.0, before the first release" {
    mkdir -p "$BATS_TEST_TMPDIR/r"
    cp "$T/CHANGELOG.md" "$BATS_TEST_TMPDIR/r/CHANGELOG.md"
    printf '0.0.0\n' > "$BATS_TEST_TMPDIR/r/VERSION"
    run --separate-stderr env -u GITHUB_REPOSITORY bash "$REPO_ROOT/.github/standard/bin/release-meta" \
        check --root "$BATS_TEST_TMPDIR/r" < /dev/null
    [ "$status" -eq 0 ] || { printf '%s\n' "$stderr" >&2; return 1; }
    [[ $output == *"state=unreleased"* ]]
    [ -z "$(awk 'length($0) > 100' "$T/CHANGELOG.md")" ]
}

@test "CONTRIBUTING.md and SECURITY.md hold every block's markers once, in pairs, and their own sections" {
    local file name section
    for file in CONTRIBUTING.md SECURITY.md; do
        run markers "$T/$file"
        while IFS= read -r name; do
            [[ $output == *"begin $name"$'\n'"end $name"* ]] ||
                { printf '%s: no marker pair for %s\n' "$file" "$name" >&2; return 1; }
            [ "$(grep -c -x -e "begin $name" -e "end $name" <<< "$output")" -eq 2 ]
        done < <(block_names "$file")
    done
    for section in '## Checks' '## Test data' '## Release contract'; do
        grep -q -x -F -e "$section" "$T/CONTRIBUTING.md"
    done
    for section in '## Trust model' '## Known exposure' '## Network' '## Data that stays private'; do
        grep -q -x -F -e "$section" "$T/SECURITY.md"
    done
}

@test "the SECURITY.md template holds no seal block's markers, and says where tools/sync adds them" {
    local name
    run markers "$T/SECURITY.md"
    for name in "$REPO_ROOT"/blocks/SECURITY.md/*@seal.md; do
        name=${name##*/}
        name=${name%.md}
        name=${name%@seal}
        [[ $output != *" $name"* ]] || { printf 'the template holds the markers of %s\n' "$name" >&2; return 1; }
        grep -q -F -e "$name" "$T/SECURITY.md"
    done
}

@test "both guard-rails blocks name the one tag push that pre-push lets through" {
    local variant text
    for variant in private public; do
        text=$(tr -s ' \n' ' ' < "$REPO_ROOT/blocks/CONTRIBUTING.md/guard-rails@$variant.md")
        [[ $text == *'every tag push except a `v*` tag under `RELEASE_KIND=legacy`'* ]] ||
            { printf 'guard-rails@%s does not name the exception\n' "$variant" >&2; return 1; }
    done
}

@test "the checklist line on skipped tests is the same in the template and both tools that print it" {
    local first second file
    first=$(grep -F -e 'no test was skipped' "$REPO_ROOT/.github/pull_request_template.md")
    second=$(grep -A 1 -F -e 'no test was skipped' "$REPO_ROOT/.github/pull_request_template.md" | tail -n 1)
    [[ $second == *'any other test stage'* ]]
    for file in tools/sync .github/standard/bin/release-prepare; do
        grep -q -F -e "$first" "$REPO_ROOT/$file" && grep -q -F -e "$second" "$REPO_ROOT/$file" ||
            { printf '%s does not hold the checklist line\n' "$file" >&2; return 1; }
    done
}

@test "the tests/helpers.bash template sources the standard's lib.bash and parses" {
    grep -q -F '/../.github/standard/tests/lib.bash' "$T/tests/helpers.bash"
    bash -n "$T/tests/helpers.bash"
    [[ $(git -C "$REPO_ROOT" ls-files -s -- templates/tests/helpers.bash) == 100644* ]]
}

@test "each ci/ starter passes its shell's syntax check and is stored with the mode it needs" {
    local path first checked=0
    while IFS= read -r path; do
        first=
        IFS= read -r first < "$REPO_ROOT/$path" || true
        case $first in
            '#!/bin/sh'*) sh -n "$REPO_ROOT/$path" ;;
            '#!/bin/bash'*) bash -n "$REPO_ROOT/$path" ;;
            *)
                [[ $path == *.ps1 ]] || { printf '%s: no shell line\n' "$path" >&2; return 1; }
                [[ $(git -C "$REPO_ROOT" ls-files -s -- "$path") == 100644* ]]
                continue
                ;;
        esac
        [[ $(git -C "$REPO_ROOT" ls-files -s -- "$path") == 100755* ]] ||
            { printf '%s is not stored as 100755\n' "$path" >&2; return 1; }
        checked=$((checked + 1))
    done < <(git -C "$REPO_ROOT" ls-files -- templates/ci)
    (( checked >= 4 ))
}

@test "each PowerShell starter parses" {
    local ps path native count=0
    if command -v pwsh > /dev/null 2>&1; then
        ps=pwsh
    elif command -v powershell.exe > /dev/null 2>&1; then
        ps=powershell.exe
    else
        need command pwsh
    fi
    while IFS= read -r path; do
        native=$REPO_ROOT/$path
        if command -v cygpath > /dev/null 2>&1; then native=$(cygpath -w "$native"); fi
        run "$ps" -NoProfile -NonInteractive -Command "\$e = \$null; [void][System.Management.Automation.Language.Parser]::ParseFile('$native', [ref]\$null, [ref]\$e); if (\$e.Count) { \$e | ForEach-Object { \$_.Message }; exit 1 }"
        [ "$status" -eq 0 ] || { printf '%s: %s\n' "$path" "$output" >&2; return 1; }
        count=$((count + 1))
    done < <(git -C "$REPO_ROOT" ls-files -- 'templates/*.ps1')
    (( count >= 2 ))
}

# The GitHub settings an adoption applies with gh come as files. Each must give exactly the line
# tools/status wants, so a file and the audit cannot drift apart. tools/status reads GitHub's
# replies with gh's own jq, which only reads API replies, so this test pins the files instead.
@test "the ruleset templates give exactly the lines tools/status wants" {
    need command jq
    STATUS_LIB=1 source "$REPO_ROOT/tools/status"
    run jq -r "$JQ_RULESET" "$T/github/ruleset.json"
    [ "$status" -eq 0 ]
    [ "$output" == "$STANDARD_RULESET" ] ||
        { printf 'got:  %q\nwant: %q\n' "$output" "$STANDARD_RULESET" >&2; return 1; }
    run jq -r "$JQ_TAG_RULESET" "$T/github/seal-ruleset.json"
    [ "$status" -eq 0 ]
    [ "$output" == "$SEAL_RULESET" ] ||
        { printf 'got:  %q\nwant: %q\n' "$output" "$SEAL_RULESET" >&2; return 1; }
    [ "$(jq -r .target "$T/github/ruleset.json")" = branch ]
    [ "$(jq -r .target "$T/github/seal-ruleset.json")" = tag ]
}

@test "the allow-list template lists exactly actions.allow, and no GitHub-owned or verified one" {
    diff <(sed -e '/^#/d' -e '/^$/d' "$REPO_ROOT/.github/standard/actions.allow") \
        <(sed -n 's/^    "\([^"]*\)",\{0,1\}$/\1/p' "$T/github/selected-actions.json")
    grep -q -x '  "github_owned_allowed": false,' "$T/github/selected-actions.json"
    grep -q -x '  "verified_allowed": false,' "$T/github/selected-actions.json"
}
