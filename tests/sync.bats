#!/usr/bin/env bats
# sync.bats of repo-standard: tools/sync, run as in an adoption from a clone of a published tag,
# against a synthetic repo-standard at v1.0.0 (this repository's index, committed and tagged
# once per file) and the gh stub, which answers for the release and its MANIFEST asset. The
# targets are scratch repositories of each profile. Every value is synthetic.

# The sh -c scripts are single-quoted, and bats runs each test in a subshell, both on purpose.
# shellcheck disable=SC2016,SC2030,SC2031
load helpers

SLUG=example-owner/repo-standard
ZERO=0000000000000000000000000000000000000000

setup_file() {
    local src=$BATS_FILE_TMPDIR/source mode path
    export GIT_CONFIG_GLOBAL=$BATS_FILE_TMPDIR/gitconfig GIT_CONFIG_NOSYSTEM=1
    : > "$GIT_CONFIG_GLOBAL"
    mkdir -p "$src"
    git -C "$REPO_ROOT" checkout-index -a --prefix="$src/"
    git init -q -b main "$src"
    git -C "$src" config user.name "Test User"
    git -C "$src" config user.email test@example.invalid
    git -C "$src" config core.autocrlf false
    git -C "$src" config commit.gpgsign false
    printf '1.0.0\n' > "$src/VERSION"
    git -C "$src" add -A
    while read -r mode _ _ path; do
        [[ $mode != 100755 ]] || git -C "$src" update-index --chmod=+x -- "$path"
    done < <(git -C "$REPO_ROOT" ls-files -s)
    (cd "$src" && sh tools/manifest)
    git -C "$src" add .github/standard/MANIFEST
    git -C "$src" -c core.hooksPath=no-hooks commit -q -m "chore: release 1.0.0"
    git -C "$src" tag v1.0.0
    git -C "$src" remote add origin "https://github.com/$SLUG.git"
}

setup() {
    isolate_home
    SRC=$BATS_TEST_TMPDIR/source
    cp -R "$BATS_FILE_TMPDIR/source" "$SRC"
    export STUB_LOG=$BATS_TEST_TMPDIR/stub.log STUB_GH=$BATS_TEST_TMPDIR/gh
    mkdir -p "$STUB_GH/assets-v1.0.0"
    : > "$STUB_LOG"
    release_says false true
    cp "$SRC/.github/standard/MANIFEST" "$STUB_GH/assets-v1.0.0/MANIFEST"
    unset GITHUB_REPOSITORY STUB_GH_READONLY
}

# Make the gh stub say the release v1.0.0 has draft $1 and immutable $2.
release_says() {
    local key
    key=$(printf '%s ' api "repos/$SLUG/releases/tags/v1.0.0" --jq '[.draft, .immutable] | @tsv' |
        sed 's/[^A-Za-z0-9.-]\{1,\}/_/g')
    printf '%s\t%s\n' "$1" "$2" > "$STUB_GH/$key"
}

# A new target repository at $TGT with the config lines given, and a README of its own,
# committed.
make_target() {
    TARGETS=$((${TARGETS:-0} + 1))
    TGT=$BATS_TEST_TMPDIR/target$TARGETS
    git init -q -b main "$TGT"
    git -C "$TGT" config user.name "Test User"
    git -C "$TGT" config user.email test@example.invalid
    git -C "$TGT" config core.autocrlf false
    git -C "$TGT" config commit.gpgsign false
    printf 'A repository of its own.\n' > "$TGT/README.md"
    if (( $# )); then
        mkdir -p "$TGT/.github"
        printf '%s\n' "$@" > "$TGT/.github/standard.conf"
    fi
    git -C "$TGT" add -A
    git -C "$TGT" -c core.hooksPath=no-hooks commit -q -m "chore: start"
}

# Run tools/sync of the source clone with ARGS, the stubs first on PATH, through bats `run`.
run_sync() {
    run --separate-stderr env PATH="$REPO_ROOT/.github/standard/tests/stub-bin:$PATH" \
        bash "$SRC/tools/sync" "$@"
}

# Fail unless every file entry of the selected profiles is in the target's index with the blob
# and the mode the MANIFEST names; $1 is the profile filter as an ERE.
copies_match() {
    local type profile oid mode path
    while read -r type profile oid mode path; do
        [[ $type == file && $profile =~ ^($1)$ ]] || continue
        [[ $(git -C "$TGT" ls-files -s -- "$path") == "$mode $oid 0"$'\t'"$path" ]] ||
            { printf '%s is not %s %s in the target\n' "$path" "$mode" "$oid" >&2; return 1; }
    done < "$SRC/.github/standard/MANIFEST"
}

# The lines strictly between the markers of block $2 in the file $1.
block_of() {
    awk -v name="$2" '
        $0 == "<!-- standard:end " name " -->" || $0 == "# standard:end " name { exit }
        on { print }
        $0 == "<!-- standard:begin " name " -->" || $0 == "# standard:begin " name { on = 1 }' "$1"
}

@test "sync --init refuses a target without .github/standard.conf, and sync without --init a target not adopted" {
    make_target
    run_sync --init --to "$TGT"
    [ "$status" -eq 1 ]
    [[ $stderr == *"has no .github/standard.conf; write it from templates/standard.conf first"* ]]
    make_target NAME=example VISIBILITY=private RELEASE_KIND=legacy
    run_sync --to "$TGT"
    [ "$status" -eq 1 ]
    [[ $stderr == *"has no .github/standard/MANIFEST; adopt it with --init"* ]]
    run_sync --to "$TGT" --init extra
    [ "$status" -eq 64 ]
}

@test "sync refuses a clone that is not the published, immutable tag, or a MANIFEST unlike the asset" {
    make_target NAME=example VISIBILITY=private RELEASE_KIND=legacy
    release_says true true
    run_sync --init --to "$TGT"
    [ "$status" -eq 1 ]
    [[ $stderr == *"v1.0.0 is not a published release"* ]]
    release_says false false
    run_sync --init --to "$TGT"
    [ "$status" -eq 1 ]
    [[ $stderr == *"v1.0.0 is not immutable"* ]]
    release_says false true
    printf 'other\n' > "$STUB_GH/assets-v1.0.0/MANIFEST"
    run_sync --init --to "$TGT"
    [ "$status" -eq 1 ]
    [[ $stderr == *"the MANIFEST differs from the release's MANIFEST asset"* ]]
    cp "$SRC/.github/standard/MANIFEST" "$STUB_GH/assets-v1.0.0/MANIFEST"
    git -C "$SRC" -c core.hooksPath=no-hooks commit -q --allow-empty -m "chore: after the tag"
    run_sync --init --to "$TGT"
    [ "$status" -eq 1 ]
    [[ $stderr == *"this clone is not at the tag v1.0.0"* ]]
    [ -z "$(git -C "$TGT" status --porcelain)" ]
    [ "$(grep -c -v -E '^gh (api|release download) ' "$STUB_LOG")" -eq 0 ]
}

@test "sync refuses when a copy or the CHANGELOG line names a private repository" {
    make_target NAME=example VISIBILITY=private RELEASE_KIND=legacy
    run_sync --init --to "$TGT" --summary "work for example-private"
    [ "$status" -eq 0 ] || { printf '%s\n' "$stderr" >&2; return 1; }
    make_target NAME=example VISIBILITY=private RELEASE_KIND=legacy
    printf 'example-private\n' >> "$SRC/config/private-names"
    git -C "$SRC" add config/private-names
    git -C "$SRC" -c core.hooksPath=no-hooks commit -q -m "chore: one more name"
    git -C "$SRC" tag -f v1.0.0 > /dev/null
    run_sync --init --to "$TGT" --summary "work for example-private"
    [ "$status" -eq 1 ]
    [[ $stderr == *"the CHANGELOG line names a private repository"* ]]
    [[ $stderr != *example-private* ]]
    printf '# see example-private\n' >> "$SRC/.githooks/rules/disk"
    git -C "$SRC" add .githooks/rules/disk
    (cd "$SRC" && sh tools/manifest)
    git -C "$SRC" add .github/standard/MANIFEST
    git -C "$SRC" -c core.hooksPath=no-hooks commit -q -m "chore: a copy that names one"
    git -C "$SRC" tag -f v1.0.0 > /dev/null
    cp "$SRC/.github/standard/MANIFEST" "$STUB_GH/assets-v1.0.0/MANIFEST"
    run_sync --init --to "$TGT"
    [ "$status" -eq 1 ]
    [[ $stderr == *".githooks/rules/disk names a private repository"* ]]
    [ -z "$(git -C "$TGT" status --porcelain)" ]
}

@test "sync --init refuses a template that names a private repository, before it writes anything" {
    make_target NAME=example VISIBILITY=private RELEASE_KIND=legacy
    printf 'example-private\n' >> "$SRC/config/private-names"
    printf 'Ask example-private.\n' >> "$SRC/templates/SECURITY.md"
    git -C "$SRC" add config/private-names templates/SECURITY.md
    git -C "$SRC" -c core.hooksPath=no-hooks commit -q -m "chore: a template that names one"
    git -C "$SRC" tag -f v1.0.0 > /dev/null
    run_sync --init --to "$TGT"
    [ "$status" -eq 1 ]
    [[ $stderr == *"templates/SECURITY.md names a private repository"* ]]
    [[ $stderr != *example-private* ]]
    [ -z "$(git -C "$TGT" status --porcelain)" ]
}

@test "sync --init writes the copies with their modes, the blocks, the MANIFEST and the PR body" {
    local asset
    make_target NAME=example VISIBILITY=public RELEASE_KIND=tar
    printf '# Security\n\nOur own words.\n' > "$TGT/SECURITY.md"
    git -C "$TGT" add SECURITY.md
    git -C "$TGT" -c core.hooksPath=no-hooks commit -q -m "docs: our own security file"
    run_sync --init --to "$TGT"
    [ "$status" -eq 0 ] || { printf '%s\n' "$stderr" >&2; return 1; }
    copies_match 'all|release|mit'
    [ ! -e "$TGT/.github/workflows/bootstrap.yml" ]
    [[ $(git -C "$TGT" ls-files -s -- .githooks/pre-commit) == 100755* ]]
    asset=$(git hash-object "$STUB_GH/assets-v1.0.0/MANIFEST")
    [ "$(git -C "$TGT" rev-parse :.github/standard/MANIFEST)" = "$asset" ]
    # CONTRIBUTING.md comes from the template; SECURITY.md keeps its own words and gets the blocks.
    [ "$(block_of "$TGT/CONTRIBUTING.md" workflow)" = "$(cat "$SRC/blocks/CONTRIBUTING.md/workflow.md")" ]
    grep -q -x -F '## Release contract' "$TGT/CONTRIBUTING.md"
    [ "$(head -n 3 "$TGT/SECURITY.md")" = $'# Security\n\nOur own words.' ]
    [ "$(block_of "$TGT/SECURITY.md" reporting)" = "$(cat "$SRC/blocks/SECURITY.md/reporting@public.md")" ]
    [ "$(block_of "$TGT/.gitattributes" gitattributes)" = "$(cat "$SRC/blocks/_gitattributes/gitattributes")" ]
    [ "$(head -n 1 "$TGT/.github/dependabot.yml")" = '# standard:begin dependabot' ]
    grep -q -x -F '    open-pull-requests-limit: 0' "$TGT/.github/dependabot.yml"
    [[ $output == *"## What and why"* && $output == *"$asset"* ]]
    [[ $output == *"- Repository standard 1.0.0: adopted, with the hooks, checks, workflows and blocks."* ]]
    [[ $output == *"- .githooks/pre-commit"* && $output == *"- SECURITY.md#reporting"* ]]
}

@test "sync keeps the text outside the markers, and a second run changes nothing" {
    make_target NAME=example VISIBILITY=private LICENSE=none RELEASE_KIND=legacy
    run_sync --init --to "$TGT"
    [ "$status" -eq 0 ] || { printf '%s\n' "$stderr" >&2; return 1; }
    {
        printf 'Before.\n'
        cat "$TGT/CONTRIBUTING.md"
        printf 'After.\n'
    } > "$BATS_TEST_TMPDIR/c" && mv "$BATS_TEST_TMPDIR/c" "$TGT/CONTRIBUTING.md"
    sed -i 's/^## Checks$/## Checks\n\nOur checks./' "$TGT/CONTRIBUTING.md"
    printf 'drifted text\n' >> "$TGT/.githooks/pre-commit"
    git -C "$TGT" add -A
    git -C "$TGT" -c core.hooksPath=no-hooks commit -q -m "chore: adopt"
    run_sync --to "$TGT"
    [ "$status" -eq 0 ] || { printf '%s\n' "$stderr" >&2; return 1; }
    [ "$(head -n 1 "$TGT/CONTRIBUTING.md")" = Before. ]
    [ "$(tail -n 1 "$TGT/CONTRIBUTING.md")" = After. ]
    grep -q -x -F 'Our checks.' "$TGT/CONTRIBUTING.md"
    copies_match 'all|private'
    [[ $output == *"- .githooks/pre-commit"* ]]
    git -C "$TGT" -c core.hooksPath=no-hooks commit -q -m "chore: sync again"
    run_sync --to "$TGT"
    [ "$status" -eq 0 ] || { printf '%s\n' "$stderr" >&2; return 1; }
    [ -z "$(git -C "$TGT" status --porcelain)" ]
    [[ $output == *$'Changed files:\n- none'* && $output == *$'Changed blocks:\n- none'* ]]
}

@test "sync refuses a block whose begin marker is there twice and its end marker not at all" {
    make_target NAME=example VISIBILITY=private LICENSE=none RELEASE_KIND=legacy
    run_sync --init --to "$TGT"
    [ "$status" -eq 0 ] || { printf '%s\n' "$stderr" >&2; return 1; }
    git -C "$TGT" add -A
    git -C "$TGT" -c core.hooksPath=no-hooks commit -q -m "chore: adopt"
    sed -i -e 's/^<!-- standard:end workflow -->$/<!-- standard:begin workflow -->/' "$TGT/CONTRIBUTING.md"
    printf 'Our own closing words.\n' >> "$TGT/CONTRIBUTING.md"
    cp "$TGT/CONTRIBUTING.md" "$BATS_TEST_TMPDIR/before"
    run_sync --to "$TGT"
    [ "$status" -eq 1 ]
    [[ $stderr == *"CONTRIBUTING.md: the block workflow needs one begin and one end marker"* ]]
    cmp "$BATS_TEST_TMPDIR/before" "$TGT/CONTRIBUTING.md"
}

@test "sync selects the profiles: private, LICENSE=none and legacy keep their own files" {
    make_target NAME=example VISIBILITY=private LICENSE=none RELEASE_KIND=legacy
    mkdir -p "$TGT/.github/workflows"
    printf 'name: release\non: workflow_dispatch\n' > "$TGT/.github/workflows/release.yml"
    git -C "$TGT" add -A
    git -C "$TGT" -c core.hooksPath=no-hooks commit -q -m "ci: our own release"
    run_sync --init --to "$TGT"
    [ "$status" -eq 0 ] || { printf '%s\n' "$stderr" >&2; return 1; }
    [ "$(cat "$TGT/.github/workflows/release.yml")" = $'name: release\non: workflow_dispatch' ]
    [ "$(git -C "$TGT" rev-parse :.github/workflows/image.yml)" = \
        "$(git -C "$SRC" rev-parse HEAD:.github/workflows/image.yml)" ]
    [ ! -e "$TGT/LICENSE" ]
    [ "$(block_of "$TGT/SECURITY.md" reporting)" = "$(cat "$SRC/blocks/SECURITY.md/reporting@private.md")" ]
    [ -z "$(block_of "$TGT/CONTRIBUTING.md" releasing)" ]
    copies_match 'all|private'
}

@test "sync under SEAL=yes writes the seal variants; a later SEAL=yes needs the seal block's markers first" {
    make_target NAME=example VISIBILITY=public RELEASE_KIND=tar SEAL=yes
    run_sync --init --to "$TGT"
    [ "$status" -eq 0 ] || { printf '%s\n' "$stderr" >&2; return 1; }
    [ "$(block_of "$TGT/CONTRIBUTING.md" releasing)" = "$(cat "$SRC/blocks/CONTRIBUTING.md/releasing@seal.md")" ]
    [ "$(block_of "$TGT/SECURITY.md" sealed-releases)" = \
        "$(cat "$SRC/blocks/SECURITY.md/sealed-releases@seal.md")" ]
    [[ $output == *"- SECURITY.md#sealed-releases"* ]]
    # Without SEAL, the plain releasing block and no seal block.
    make_target NAME=example VISIBILITY=public RELEASE_KIND=tar
    run_sync --init --to "$TGT"
    [ "$status" -eq 0 ] || { printf '%s\n' "$stderr" >&2; return 1; }
    [ "$(block_of "$TGT/CONTRIBUTING.md" releasing)" = "$(cat "$SRC/blocks/CONTRIBUTING.md/releasing.md")" ]
    run grep -c -F 'standard:begin sealed-releases' "$TGT/SECURITY.md"
    [ "$output" = 0 ]
    git -C "$TGT" add -A
    git -C "$TGT" -c core.hooksPath=no-hooks commit -q -m "chore: adopt"
    # Setting SEAL=yes later: sync refuses until SECURITY.md holds the markers.
    printf 'SEAL=yes\n' >> "$TGT/.github/standard.conf"
    run_sync --to "$TGT"
    [ "$status" -eq 1 ]
    [[ $stderr == *"SECURITY.md: the markers of the block sealed-releases are missing"* ]]
    printf '%s\n' '<!-- standard:begin sealed-releases -->' '<!-- standard:end sealed-releases -->' \
        >> "$TGT/SECURITY.md"
    run_sync --to "$TGT"
    [ "$status" -eq 0 ] || { printf '%s\n' "$stderr" >&2; return 1; }
    [ "$(block_of "$TGT/CONTRIBUTING.md" releasing)" = "$(cat "$SRC/blocks/CONTRIBUTING.md/releasing@seal.md")" ]
    [ "$(block_of "$TGT/SECURITY.md" sealed-releases)" = \
        "$(cat "$SRC/blocks/SECURITY.md/sealed-releases@seal.md")" ]
}

@test "sync deletes the files the release drops, and refuses a target that is repo-standard itself" {
    local line
    make_target NAME=example VISIBILITY=private LICENSE=none RELEASE_KIND=legacy
    run_sync --init --to "$TGT"
    [ "$status" -eq 0 ] || { printf '%s\n' "$stderr" >&2; return 1; }
    printf '#!/bin/sh\n' > "$TGT/.github/standard/bin/old-tool"
    line=$(printf 'file    all      %s  100755  .github/standard/bin/old-tool' \
        "$(git hash-object "$TGT/.github/standard/bin/old-tool")")
    printf '%s\n' "$line" >> "$TGT/.github/standard/MANIFEST"
    git -C "$TGT" add -A
    git -C "$TGT" -c core.hooksPath=no-hooks commit -q -m "chore: an older standard"
    run_sync --to "$TGT"
    [ "$status" -eq 0 ] || { printf '%s\n' "$stderr" >&2; return 1; }
    [ ! -e "$TGT/.github/standard/bin/old-tool" ]
    [ -z "$(git -C "$TGT" ls-files -- .github/standard/bin/old-tool)" ]
    [[ $output == *$'Removed files:\n- .github/standard/bin/old-tool'* ]]
    printf 'ROLE=source\n' >> "$TGT/.github/standard.conf"
    run_sync --to "$TGT"
    [ "$status" -eq 1 ]
    [[ $stderr == *"is repo-standard itself (ROLE=source)"* ]]
}

@test "a consumer built by sync --init from the templates passes standard-check --ci" {
    make_target
    mkdir -p "$TGT/.github" "$TGT/ci" "$TGT/tests"
    cp "$SRC/templates/standard.conf" "$TGT/.github/standard.conf"
    run_sync --init --to "$TGT"
    [ "$status" -eq 0 ] || { printf '%s\n' "$stderr" >&2; return 1; }
    sed 's#OWNER/REPO#example-owner/example#' "$SRC/templates/CHANGELOG.md" > "$TGT/CHANGELOG.md"
    printf '0.0.0\n' > "$TGT/VERSION"
    cp "$SRC/templates/tests/helpers.bash" "$TGT/tests/helpers.bash"
    cp "$SRC/templates/ci/bash/test" "$TGT/ci/test"
    git -C "$TGT" add -A
    git -C "$TGT" update-index --chmod=+x ci/test
    git -C "$TGT" -c core.hooksPath=no-hooks commit -q -m "chore: adopt the repository standard"
    run --separate-stderr sh -c 'cd "$1" && EVENT=push BASE="$2" PRIVATE=true exec sh .github/standard/bin/standard-check --ci' \
        sh "$TGT" "$ZERO"
    [ "$status" -eq 0 ] || { printf '%s\n%s\n' "$output" "$stderr" >&2; return 1; }
}

# Commit everything in the target with the hooks off.
commit_target() {
    git -C "$TGT" add -A
    git -C "$TGT" -c core.hooksPath=no-hooks commit -q -m "$1"
}

# The numbers of the lines of file $1 outside its standard blocks that equal one of the other
# arguments, as "line N" or "lines N, M".
own_lines() {
    local file=$1 found
    shift
    found=$(printf '%s\n' "$@" | awk '
        FNR == NR { want[$0] = 1; next }
        /standard:begin / { inside = 1; next }
        /standard:end / { inside = 0; next }
        !inside && ($0 in want) { out = out (out == "" ? "" : ", ") FNR; n++ }
        END { print (n > 1 ? "lines " : "line ") out }' - "$file")
    printf '%s' "$found"
}

# These tests share targets, because each sync run costs CI's Windows job about 20 seconds.
@test "sync --init names the lines that repeat a configuration block, and leaves them" {
    local at line='- Repository standard 1.0.0: adopted, with the hooks, checks, workflows and blocks.'
    make_target NAME=example VISIBILITY=public RELEASE_KIND=tar
    printf '%s\n' 'version: 2' 'registries:' '  example:' '    type: npm-registry' 'updates:' \
        '  - package-ecosystem: npm' '    directory: /' '    schedule:' '      interval: weekly' \
        > "$TGT/.github/dependabot.yml"
    printf '%s\n' 'root = true' '' '[*]' 'indent_size = 4' '' '[*.example]' 'indent_size = 4' \
        > "$TGT/.editorconfig"
    printf '%s\n' '* text=auto eol=lf' '*.example binary' > "$TGT/.gitattributes"
    sed 's#OWNER/REPO#example-owner/example#' "$SRC/templates/CHANGELOG.md" > "$TGT/CHANGELOG.md"
    commit_target "chore: our own configuration"
    run_sync --init --to "$TGT"
    [ "$status" -eq 0 ] || { printf '%s\n' "$stderr" >&2; return 1; }
    at=$(own_lines "$TGT/.github/dependabot.yml" 'version: 2' 'updates:')
    [[ $at == "lines "* ]]
    # Deleting only the repeats would nest the entries under registries, so the note moves them.
    [[ $stderr == *"sync: note: .github/dependabot.yml: $at repeat the block's version or updates. Delete the repeated version and updates. Then put your entries directly below the block's end marker, and any other top-level key such as registries after them."* ]]
    [[ $stderr == *"sync: note: .github/dependabot.yml: add a github-actions entry for / with open-pull-requests-limit: 0"* ]]
    # A setting under another section is no repeat; only root and the section header are.
    at=$(own_lines "$TGT/.editorconfig" 'root = true' '[*]')
    [[ $stderr == *"sync: note: .editorconfig: $at repeat the block's root or a section header."* ]]
    # In .gitattributes the last matching line wins, so the note never says to delete outright.
    at=$(own_lines "$TGT/.gitattributes" '* text=auto eol=lf')
    [[ $stderr == *"sync: note: .gitattributes: $at repeats the block. The last matching line wins, so check whether a line of yours relies on the repeat before you delete it."* ]]
    [[ $stderr != *".gitattributes: $at repeats the block. Delete"* ]]
    # Line numbers go stale with the first edit, so the first note says how to keep them right.
    [[ $(grep -m 1 'sync: note:' <<< "$stderr") == *"Line numbers hold for the files as sync left them. In each file, delete from the last line up, then move what the notes say to move."* ]]
    [[ $stderr == *"sync: note: CHANGELOG.md: add under ### Changed: $line"* ]]
    grep -q -x -F 'indent_size = 4' "$TGT/.editorconfig"
    [[ $output != *"note:"* ]]
}

@test "sync --init notes an actions entry without limit 0 and a dependabot.yaml beside the file" {
    make_target NAME=example VISIBILITY=public RELEASE_KIND=tar
    printf '%s\n' 'version: 2' 'updates:' '  - package-ecosystem: github-actions' '    directory: /' \
        '    schedule:' '      interval: weekly' > "$TGT/.github/dependabot.yml"
    printf '%s\n' 'version: 2' 'updates: []' > "$TGT/.github/dependabot.yaml"
    printf '%s\n' '# Contributing' '' '### Checks' '' 'Our checks.' > "$TGT/CONTRIBUTING.md"
    commit_target "chore: an entry without the limit, and a second file"
    run_sync --init --to "$TGT"
    [ "$status" -eq 0 ] || { printf '%s\n' "$stderr" >&2; return 1; }
    [[ $stderr == *"sync: note: .github/dependabot.yml: set open-pull-requests-limit: 0 on the github-actions entry for /"* ]]
    [[ $stderr == *"sync: note: .github/dependabot.yaml stands beside .github/dependabot.yml, the file the standard checks. Move your entries into it, leaving out any github-actions entry for / and any entry for a package-ecosystem, directory and target-branch it already covers, and put other top-level keys such as registries after them. Then delete the .yaml file."* ]]
    # A Checks heading of any level counts.
    [[ $stderr != *"add a ## Checks section"* ]]
}

@test "sync --init says an older section may stand beside an appended block, and names none" {
    local short line='- Repository standard 1.0.0: adopted, with the hooks, checks, workflows and blocks.'
    local says='was appended at the end. An older section on the same topic may stand beside it, so compare them by eye.'
    make_target
    mkdir -p "$TGT/.github"
    printf '%s\n' 'version: 2' 'updates:' '  - package-ecosystem: github-actions' '    directory: /' \
        '    schedule:' '      interval: weekly' '    open-pull-requests-limit: 0' \
        > "$TGT/.github/dependabot.yml"
    printf '%s\n' '# Contributing' '' '## Workflow' '' 'Our old steps.' > "$TGT/CONTRIBUTING.md"
    printf '%s\n' '# Security' '' '## Reporting' '' 'Our old address.' > "$TGT/SECURITY.md"
    printf '%s\n' '# Changelog' '' '## [Unreleased]' '' '### Changed' '' "$line" > "$TGT/CHANGELOG.md"
    head -c 1049600 /dev/zero | tr '\0' a > "$TGT/large-name.dat"
    commit_target "docs: our own documents"
    short=$(git -C "$TGT" rev-parse --short=12 HEAD:large-name.dat)
    # As in a real adoption, the config is written but not committed yet.
    printf '%s\n' NAME=example VISIBILITY=public RELEASE_KIND=tar SEAL=yes MAX_BLOB_KB=2048 \
        > "$TGT/.github/standard.conf"
    run_sync --init --to "$TGT"
    [ "$status" -eq 0 ] || { printf '%s\n' "$stderr" >&2; return 1; }
    [[ $stderr == *"sync: note: CONTRIBUTING.md: the block workflow $says templates/CONTRIBUTING.md shows where the block goes."* ]]
    [[ $stderr == *"sync: note: SECURITY.md: the block reporting $says templates/SECURITY.md shows where the block goes."* ]]
    [[ $stderr == *"sync: note: SECURITY.md: the block sealed-releases $says templates/SECURITY.md shows where the block goes."* ]]
    [[ $stderr != *"old section"* ]]
    [[ $stderr == *"sync: note: CONTRIBUTING.md: add a ## Checks section. The workflow block points to it."* ]]
    [[ $stderr != *"github-actions entry"* && $stderr != *"note: CHANGELOG.md"* ]]
    # Without a config in HEAD the hooks use 1024, whatever the new config says.
    [[ $stderr == *"sync: note: blob $short is 1025 KB, above MAX_BLOB_KB=1024."* ]]
    # The notes never repeat the repository's own words.
    [[ $stderr != *"Our old"* && $output != *"note:"* ]]
}

@test "sync --init into a fresh repository notes only the CHANGELOG line; a later sync notes nothing" {
    local line='- Repository standard 1.0.0: adopted, with the hooks, checks, workflows and blocks.'
    make_target NAME=example VISIBILITY=public RELEASE_KIND=tar
    run_sync --init --to "$TGT"
    [ "$status" -eq 0 ] || { printf '%s\n' "$stderr" >&2; return 1; }
    [[ $stderr == *"sync: note: CHANGELOG.md: write it from templates/CHANGELOG.md, then add under ### Changed: $line"* ]]
    [ "$(grep -c 'sync: note:' <<< "$stderr")" -eq 1 ]
    sed 's#OWNER/REPO#example-owner/example#' "$SRC/templates/CHANGELOG.md" > "$TGT/CHANGELOG.md"
    commit_target "chore: adopt"
    run_sync --to "$TGT"
    [ "$status" -eq 0 ] || { printf '%s\n' "$stderr" >&2; return 1; }
    [[ $stderr != *"note:"* ]]
}

@test "sync --init names tracked blobs by id against HEAD's limit, and says when one is unreadable" {
    local short at_limit ghost
    ghost=$(printf '%040d' 0 | tr 0 1)
    make_target NAME=example VISIBILITY=public RELEASE_KIND=tar MAX_BLOB_KB=1
    head -c 2048 /dev/zero | tr '\0' a > "$TGT/large-name.dat"
    head -c 1024 /dev/zero | tr '\0' a > "$TGT/at-limit.dat"
    commit_target "feat: a large file and one at the limit"
    short=$(git -C "$TGT" rev-parse --short=12 HEAD:large-name.dat)
    at_limit=$(git -C "$TGT" rev-parse --short=12 HEAD:at-limit.dat)
    # Raised in the work tree only: the hooks still read 1 from HEAD.
    sed -i 's/^MAX_BLOB_KB=1$/MAX_BLOB_KB=1024/' "$TGT/.github/standard.conf"
    git -C "$TGT" update-index --add --cacheinfo "100644,$ghost,ghost-name.dat"
    run_sync --init --to "$TGT"
    [ "$status" -eq 0 ] || { printf '%s\n' "$stderr" >&2; return 1; }
    [[ $stderr == *"sync: note: blob $short is 2 KB, above MAX_BLOB_KB=1."* ]]
    [[ $stderr == *"Find its file with: git ls-files -s | grep $short"* ]]
    [[ $stderr == *"in a commit of its own"* && $stderr == *"chore/privacy-*"* ]]
    [[ $stderr != *"blob $at_limit"* ]]
    [[ $stderr == *"sync: note: blob ${ghost:0:12} could not be read, so its size was not compared. Find its file with: git ls-files -s | grep ${ghost:0:12}"* ]]
    [[ $stderr != *large-name* && $stderr != *ghost-name* && $output != *"$short"* ]]
}
