#!/usr/bin/env bats
# source-check.bats of repo-standard: what holds only here, where tools/manifest and blocks/
# exist: standard-check with ROLE=source, the blocks of this repository's own documents (the
# check, the hook and tools/manifest's rewrite), every rule pack over this repository's whole
# tree, and the order in which the standard block tells a repository to go public.
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

# A copy of this repository's index at $REPO, staged in a new repository with no commit.
copy_own_tree() {
    REPO="$BATS_TEST_TMPDIR/copy"
    git -C "$REPO_ROOT" checkout-index -a --prefix="$REPO/"
    git init -q -b main "$REPO"
    git -C "$REPO" config user.name "Test User"
    git -C "$REPO" config user.email test@example.invalid
    git -C "$REPO" config core.autocrlf false
    git -C "$REPO" add -A
}

@test "repo-standard's own documents pass the source's block check, and a drift in one fails" {
    copy_own_tree
    check --staged
    [ "$status" -eq 0 ]
    sed -i 's/^## Workflow$/## The workflow/' "$REPO/CONTRIBUTING.md"
    git -C "$REPO" add CONTRIBUTING.md
    check --staged
    [ "$status" -eq 1 ]
    [[ $stderr == *"CONTRIBUTING.md#workflow: the block differs from blocks/; run sh tools/manifest"* ]]
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
    copy_own_tree
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

# Write $REPO/CONTRIBUTING.md: own text around the workflow block and the guard-rails block in
# VARIANT, both from this repository's blocks/.
write_contributing() {
    { printf '# Contributing\n\nOwn text before.\n\n'
      block workflow md CONTRIBUTING.md/workflow.md
      printf '\nOwn text between.\n\n'
      block guard-rails md "CONTRIBUTING.md/guard-rails@$1.md"
      printf '\nOwn text after.\n'; } > "$REPO/CONTRIBUTING.md"
}

@test "ROLE=source: an own block must be the variant the config selects" {
    make_source_check_repo
    write_contributing public
    git -C "$REPO" add CONTRIBUTING.md
    check --staged
    [ "$status" -eq 1 ]
    [[ $stderr == *"CONTRIBUTING.md#guard-rails@private: the block differs from blocks/; run sh tools/manifest"* ]]
    [[ $stderr != *"CONTRIBUTING.md#workflow"* ]]
    write_contributing private
    git -C "$REPO" add CONTRIBUTING.md
    check --staged
    [ "$status" -eq 0 ]
    [ -z "$stderr" ]
}

@test "ROLE=source: absent markers pass; markers twice or out of order fail; a seal-only block needs SEAL=yes" {
    make_source_check_repo
    # Neither guard-rails nor standard nor releasing has markers here: the source keeps own text.
    { printf '# Contributing\n\n'; block workflow md CONTRIBUTING.md/workflow.md; } > "$REPO/CONTRIBUTING.md"
    git -C "$REPO" add CONTRIBUTING.md
    check --staged
    [ "$status" -eq 0 ]
    block workflow md CONTRIBUTING.md/workflow.md >> "$REPO/CONTRIBUTING.md"
    git -C "$REPO" add CONTRIBUTING.md
    check --staged
    [ "$status" -eq 1 ]
    [[ $stderr == *"CONTRIBUTING.md#workflow: the block's markers appear more than once or out of order"* ]]
    printf '# Contributing\n\n<!-- standard:end workflow -->\n<!-- standard:begin workflow -->\n' \
        > "$REPO/CONTRIBUTING.md"
    git -C "$REPO" add CONTRIBUTING.md
    check --staged
    [ "$status" -eq 1 ]
    [[ $stderr == *"CONTRIBUTING.md#workflow: the block's markers appear more than once or out of order"* ]]
    git -C "$REPO" rm -q --cached CONTRIBUTING.md
    { printf '# Security\n\n'; block sealed-releases md SECURITY.md/sealed-releases@seal.md; } \
        > "$REPO/SECURITY.md"
    git -C "$REPO" add SECURITY.md
    check --staged
    [ "$status" -eq 1 ]
    [[ $stderr == *"SECURITY.md#sealed-releases@seal: the block is here, but the config does not set SEAL=yes"* ]]
}

@test "ROLE=source: pre-commit checks a commit that stages an own block's file, blocks/ or the config" {
    make_source_check_repo
    git -C "$REPO" checkout -q -b feat/own-blocks
    write_contributing public
    git -C "$REPO" add CONTRIBUTING.md
    run --separate-stderr git -C "$REPO" commit -q -m "docs: a drifted block"
    [ "$status" -ne 0 ]
    [[ $stderr == *"CONTRIBUTING.md#guard-rails@private: the block differs from blocks/"* ]]
    # Committed with the hooks off, the drift is in HEAD. A commit of tools/ alone runs no check.
    commit_unchecked "docs: a drifted block"
    printf '# a comment\n' >> "$REPO/tools/manifest"
    git -C "$REPO" add tools/manifest
    run --separate-stderr git -C "$REPO" commit -q -m "chore: touch a tool"
    [ "$status" -eq 0 ]
    # Staging the config, or a body in blocks/, runs it.
    printf '# a comment\n' >> "$REPO/.github/standard.conf"
    git -C "$REPO" add .github/standard.conf
    run --separate-stderr git -C "$REPO" commit -q -m "chore: comment the config"
    [ "$status" -ne 0 ]
    [[ $stderr == *"CONTRIBUTING.md#guard-rails@private: the block differs from blocks/"* ]]
    git -C "$REPO" reset -q
    printf 'One more line.\n' >> "$REPO/blocks/CONTRIBUTING.md/standard.md"
    git -C "$REPO" add blocks
    run --separate-stderr git -C "$REPO" commit -q -m "docs: extend a block"
    [ "$status" -ne 0 ]
    [[ $stderr == *"CONTRIBUTING.md#guard-rails@private: the block differs from blocks/"* ]]
}

@test "tools/manifest rewrites the own blocks from blocks/ by the config, keeps the text around them and stages nothing" {
    local before
    make_source_check_repo
    write_contributing private
    git -C "$REPO" add CONTRIBUTING.md
    commit_unchecked "docs: contributing"
    before=$(cat "$REPO/CONTRIBUTING.md")
    printf 'One more line.\n' >> "$REPO/blocks/CONTRIBUTING.md/workflow.md"
    git -C "$REPO" add blocks
    run --separate-stderr sh -c 'cd "$1" && exec sh tools/manifest' sh "$REPO"
    [ "$status" -eq 0 ]
    [[ $stderr == *"CONTRIBUTING.md#workflow: rewritten from blocks/"* ]]
    [[ $stderr != *"guard-rails"* ]]
    [ -z "$(git -C "$REPO" diff --cached --name-only -- CONTRIBUTING.md)" ]
    # Only the line added to the body differs, at the end of the workflow block.
    [ "$(sed '/^One more line\.$/d' "$REPO/CONTRIBUTING.md")" = "$before" ]
    [ "$(grep -c '^One more line\.$' "$REPO/CONTRIBUTING.md")" -eq 1 ]
    [ "$(grep -A1 '^One more line\.$' "$REPO/CONTRIBUTING.md")" = "$(printf 'One more line.\n<!-- standard:end workflow -->')" ]
    git -C "$REPO" add CONTRIBUTING.md .github/standard/MANIFEST
    check --staged
    [ "$status" -eq 0 ]
    # A new VISIBILITY selects the other variant; the check and the rewrite follow the config.
    sed -i 's/^VISIBILITY=private$/VISIBILITY=public/' "$REPO/.github/standard.conf"
    git -C "$REPO" add .github/standard.conf
    check --staged
    [ "$status" -eq 1 ]
    [[ $stderr == *"CONTRIBUTING.md#guard-rails@public: the block differs from blocks/"* ]]
    (cd "$REPO" && sh tools/manifest 2> /dev/null)
    git -C "$REPO" add CONTRIBUTING.md
    check --staged
    [ "$status" -eq 0 ]
    # A document whose blocks are right is not touched, even without a newline at its end.
    printf 'No newline at the end.' >> "$REPO/CONTRIBUTING.md"
    cp "$REPO/CONTRIBUTING.md" "$BATS_TEST_TMPDIR/before"
    run --separate-stderr sh -c 'cd "$1" && exec sh tools/manifest' sh "$REPO"
    [ "$status" -eq 0 ]
    [[ $stderr != *"rewritten"* ]]
    cmp "$REPO/CONTRIBUTING.md" "$BATS_TEST_TMPDIR/before"
    # While a body in blocks/ has changes that are not staged, nothing is rewritten, not even
    # from the staged body.
    printf 'Not staged yet.\n' >> "$REPO/blocks/CONTRIBUTING.md/workflow.md"
    run --separate-stderr sh -c 'cd "$1" && exec sh tools/manifest' sh "$REPO"
    [ "$status" -eq 0 ]
    [[ $stderr == *"blocks/ has changes that are not staged; stage them and run tools/manifest again"* ]]
    cmp "$REPO/CONTRIBUTING.md" "$BATS_TEST_TMPDIR/before"
    git -C "$REPO" checkout -q -- blocks
    printf '\n' >> "$REPO/CONTRIBUTING.md"
    # Broken markers are left as they are, with a message; the check refuses them.
    printf '<!-- standard:begin workflow -->\n' >> "$REPO/CONTRIBUTING.md"
    cp "$REPO/CONTRIBUTING.md" "$BATS_TEST_TMPDIR/broken"
    run --separate-stderr sh -c 'cd "$1" && exec sh tools/manifest' sh "$REPO"
    [ "$status" -eq 0 ]
    [[ $stderr == *"CONTRIBUTING.md#workflow: the markers appear more than once or out of order; not rewritten"* ]]
    cmp "$REPO/CONTRIBUTING.md" "$BATS_TEST_TMPDIR/broken"
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
