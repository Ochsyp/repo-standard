#!/usr/bin/env bats
# bats file_tags=lint
# lint.bats of the repository standard: the same file in every repository; never edit it here.
# Syntax checks (sh -n, dash -n where present, bash -n), ShellCheck, the modes git stores, LF
# line ends, and image pins, for the hooks, the standard's tools and tests, and the shell scripts
# in ci/. CI runs it on Linux in every repository; on Windows the other suites run without it.

load lib

setup() {
    isolate_home
}

# Print the shell files to lint, relative to REPO_ROOT, as "sh PATH" or "bash PATH": the hooks
# and lib.sh, the standard's bin/ and tests/, and every script in ci/ with a shell shebang.
shell_files() {
    local path first
    while IFS= read -r path; do
        case $path in
            .githooks/rules/*) continue ;;
            .githooks/lib.sh) printf 'sh %s\n' "$path"; continue ;;
            *.bash | *.bats) printf 'bash %s\n' "$path"; continue ;;
        esac
        first=
        IFS= read -r first < "$REPO_ROOT/$path" || true
        case $first in
            '#!/bin/sh'*) printf 'sh %s\n' "$path" ;;
            '#!/bin/bash'* | '#!/usr/bin/env bash'*) printf 'bash %s\n' "$path" ;;
        esac
    done < <(git -C "$REPO_ROOT" ls-files -- .githooks .github/standard/bin .github/standard/tests ci)
}

@test "the hooks, lib.sh and the sh scripts pass sh -n, and dash -n where dash exists" {
    local shell path checked=0
    while read -r shell path; do
        [[ $shell == sh ]] || continue
        sh -n "$REPO_ROOT/$path"
        if command -v dash > /dev/null 2>&1; then
            dash -n "$REPO_ROOT/$path"
        fi
        checked=$((checked + 1))
    done < <(shell_files)
    (( checked >= 8 ))
}

@test "the bash scripts and helpers pass bash -n" {
    local shell path
    while read -r shell path; do
        [[ $shell == bash && $path != *.bats ]] || continue
        bash -n "$REPO_ROOT/$path"
    done < <(shell_files)
}

@test "ShellCheck reports nothing in the hooks, the standard's tools and tests, and ci/" {
    local -a paths=()
    local shell path
    need command shellcheck
    while read -r shell path; do
        paths+=("$path")
    done < <(shell_files)
    run_shellcheck "${paths[@]}"
    [ "$status" -eq 0 ] || { shellcheck_code_counts >&2; printf '%s\n' "$output" >&2; return 1; }
}

@test "git stores files with a shebang and .bats files as 100755, the others as 100644" {
    local mode path want first
    while read -r mode _ _ path; do
        first=
        IFS= read -r first < "$REPO_ROOT/$path" || true
        if [[ $first == '#!'* || $path == *.bats ]]; then want=100755; else want=100644; fi
        if [[ $mode != "$want" ]]; then
            printf '%s is stored with mode %s, not %s\n' "$path" "$mode" "$want" >&2
            return 1
        fi
    done < <(git -C "$REPO_ROOT" ls-files -s -- .githooks .github/standard ci)
}

@test "every hook and every tool of bin/ is a shell script that the lint checks" {
    local path
    local listed
    listed=$(shell_files)
    while IFS= read -r path; do
        [[ $path == .githooks/rules/* ]] && continue
        if [[ $listed != *" $path"* ]]; then
            printf '%s is not linted: give it a #!/bin/sh or #!/bin/bash line\n' "$path" >&2
            return 1
        fi
    done < <(git -C "$REPO_ROOT" ls-files -- .githooks .github/standard/bin)
}

@test "the standard's files and ci/ hold no CR byte" {
    local -a files=()
    local path
    while IFS= read -r path; do
        files+=("$REPO_ROOT/$path")
    done < <(git -C "$REPO_ROOT" ls-files -- .githooks .github/standard ci)
    (( ${#files[@]} > 0 ))
    # -U keeps a grep that reads files in text mode from dropping each CR before it matches.
    run grep -U -l $'\r' -- "${files[@]}"
    [ "$status" -eq 1 ]
}

@test "every image reference in ci/ and .github/ carries @sha256:" {
    local path line
    while IFS= read -r path; do
        while IFS= read -r line; do
            if [[ $line != *@sha256:* ]]; then
                printf '%s: an image without @sha256: %s\n' "$path" "$line" >&2
                return 1
            fi
        done < <(grep -E -o '(^[[:space:]]*FROM[[:space:]]+[^[:space:]]+|image:[[:space:]]+[^[:space:]]+|docker://[^[:space:]]+)' \
            "$REPO_ROOT/$path" | grep -v -E '\$\{\{|^[[:space:]]*FROM[[:space:]]+scratch$' || true)
    done < <(git -C "$REPO_ROOT" ls-files -- ci .github ':!.github/standard/tests')
}
