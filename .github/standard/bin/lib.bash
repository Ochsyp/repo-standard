# shellcheck shell=bash
# lib.bash of the repository standard's tools: the same file in every repository; never edit it
# here. The bash tools of .github/standard/bin source it; it runs nothing by itself.
#   say TEXT...           print "TOOL: TEXT" on stderr
#   error TEXT...         the same, as an error annotation (::error::) in Actions
#   die TEXT...           error TEXT, then exit 1
#   on_windows            true in Git Bash and the other Windows shells
#   win_path PATH         PATH as Windows writes it in Git Bash, unchanged elsewhere
#   has_hook NAME         true when ci/NAME or ci/NAME.ps1 exists
#   run_hook NAME ARGS... run ci/NAME, then ci/NAME.ps1, with ARGS (the ci/ interface)
# TOOL is the name of the script that sources this file. The tools run from the top of the
# repository, where ci/ lives.

std_tool=${0##*/}

say() {
    printf '%s: %s\n' "$std_tool" "$*" >&2
}

error() {
    if [[ ${GITHUB_ACTIONS:-} == true ]]; then
        printf '::error::%s: %s\n' "$std_tool" "$*" >&2
    else
        say "$@"
    fi
}

die() {
    error "$@"
    exit 1
}

on_windows() {
    case $(uname -s) in
        MINGW* | MSYS* | CYGWIN*) return 0 ;;
        *) return 1 ;;
    esac
}

win_path() {
    if command -v cygpath > /dev/null 2>&1; then
        cygpath -w "$1"
    else
        printf '%s\n' "$1"
    fi
}

has_hook() {
    [[ -f ci/$1 || -f ci/$1.ps1 ]]
}

# Run ci/NAME with ARGS when it exists, then ci/NAME.ps1 with ARGS under Windows PowerShell 5.1,
# as spec 2.6 sets it: -NoProfile -ExecutionPolicy Bypass, with TEMP and TMP set to RUNNER_TEMP.
# Return the first failing status, or 0; a .ps1 off Windows dies. POWERSHELL names the
# PowerShell to run (default powershell.exe).
run_hook() {
    local name=$1 temp
    shift
    if [[ -f ci/$name ]]; then
        "./ci/$name" "$@" || return
    fi
    if [[ -f ci/$name.ps1 ]]; then
        on_windows || die "ci/$name.ps1 needs Windows PowerShell 5.1, which runs on Windows only"
        temp=$(win_path "${RUNNER_TEMP:-${TMPDIR:-/tmp}}")
        TEMP=$temp TMP=$temp "${POWERSHELL:-powershell.exe}" -NoProfile -ExecutionPolicy Bypass \
            -File "$(win_path "ci/$name.ps1")" "$@" || return
    fi
}
