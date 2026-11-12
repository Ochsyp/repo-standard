#!/usr/bin/env bats
# conf.bats of the repository standard: the same file in every repository; never edit it here.
# The parser of .github/standard.conf: keys, value forms, repeats, required keys, defaults, the
# modes, the limits on PRIVACY_ALLOW and PRIVACY_HISTORY_ACCEPT, and that no message shows a
# value from the file. Every value is synthetic.

# The sh -c scripts are single-quoted, ~ stays literal in git config values, and bats runs each
# test in a subshell, all on purpose.
# shellcheck disable=SC1003,SC2016,SC2030,SC2031,SC2088
load lib

setup() {
    isolate_home
    CONF="$REPO_ROOT/.github/standard/bin/conf"
    REPO="$BATS_TEST_TMPDIR"
    FILE="$REPO/.github/standard.conf"
    # A synthetic home and a home prefix, built from fragments so this file passes the packs.
    SYN_HOME=$(printf '/%s/%s' home example-user)
    HOME_PREFIX=$(printf '/%s/' home)
}

run_conf() {
    run --separate-stderr sh "$CONF" "$@"
}

@test "a minimal config parses, and --print fills in the defaults" {
    write_config
    run_conf --print "$FILE"
    [ "$status" -eq 0 ]
    [ "$output" = "NAME=example
VISIBILITY=private
ROLE=consumer
LICENSE=MIT
CI_RUNNER=ubuntu
CI_STAGES=test
CI_WEEKLY=no
PYTHON=
PS_MODULES=
IMAGE_PLATFORMS=
RELEASE_KIND=tar
RELEASE_RUNNER=ubuntu
RELEASE_MANIFEST=example-release.json
RELEASE_ASSETS=
PRIVACY_RULES=
MAX_BLOB_KB=1024" ]
}

@test "--defaults prints the defaults without a file" {
    run_conf --defaults
    [ "$status" -eq 0 ]
    [[ $output == *$'\n'"ROLE=consumer"$'\n'* ]]
    [[ $output == *$'\n'"MAX_BLOB_KB=1024" ]]
    [[ $output == "NAME="$'\n'* ]]
}

@test "--get prints a value, a default, or each line of a repeatable key" {
    write_config 'CI_STAGES=lint test' 'VERSION_COPY=a/b|V="X.Y.Z"' 'VERSION_COPY=c|X.Y.Z'
    run_conf --get CI_STAGES "$FILE"
    [ "$output" = "lint test" ]
    run_conf --get CI_WEEKLY "$FILE"
    [ "$output" = no ]
    run_conf --get VERSION_COPY "$FILE"
    [ "$output" = $'a/b|V="X.Y.Z"\nc|X.Y.Z' ]
    run_conf --get PRIVACY_ALLOW "$FILE"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "every key takes the values of the standard" {
    write_config NAME=example-2 VISIBILITY=public ROLE=source LICENSE=none CI_RUNNER=windows \
        'CI_STAGES=lint test system' CI_WEEKLY=yes PYTHON=3.13 'PS_MODULES=pester psscriptanalyzer' \
        'IMAGE_PLATFORMS=linux/amd64 linux/arm64' RELEASE_KIND=image RELEASE_RUNNER=windows \
        RELEASE_MANIFEST=example.json 'RELEASE_ASSETS=src/install.ps1 example.json' \
        'VERSION_COPY=share/example/VERSION|X.Y.Z' 'PRIVACY_RULES=base disk vm' \
        "PRIVACY_ALLOW=home-path ^tests/ ^$SYN_HOME$" \
        "PRIVACY_HISTORY_ACCEPT=$(printf '%040d' 0 | tr 0 a) e-mail" MAX_BLOB_KB=2048
    run_conf --check "$FILE"
    [ "$status" -eq 0 ]
    [ -z "$stderr" ]
}

@test "an unknown key, a line that is not KEY=value and a key set twice are refused by line" {
    write_config BOGUS=1 'not a setting' CI_WEEKLY=yes CI_WEEKLY=no '# a comment' ''
    run_conf --check "$FILE"
    [ "$status" -eq 1 ]
    [[ $stderr == *"conf: line 4: the key BOGUS is unknown"* ]]
    [[ $stderr == *"conf: line 5: not a KEY=value line"* ]]
    [[ $stderr == *"conf: line 7: CI_WEEKLY is set twice"* ]]
    [ "$(grep -c '^conf: ' <<< "$stderr")" -eq 3 ]
}

@test "NAME, VISIBILITY and RELEASE_KIND are required" {
    printf '# empty\n' > "$BATS_TEST_TMPDIR/empty.conf"
    run_conf --check "$BATS_TEST_TMPDIR/empty.conf"
    [ "$status" -eq 1 ]
    [[ $stderr == *"NAME is required"* ]]
    [[ $stderr == *"VISIBILITY is required"* ]]
    [[ $stderr == *"RELEASE_KIND is required"* ]]
}

@test "each key refuses a value outside its form" {
    local bad
    for bad in NAME=Example_Name VISIBILITY=internal ROLE=owner LICENSE=GPL CI_RUNNER=macos \
        'CI_STAGES=test test' 'CI_STAGES=test  lint' CI_STAGES=deploy CI_WEEKLY=maybe PYTHON=2.7 \
        PS_MODULES=pester-extra IMAGE_PLATFORMS=linux/386 RELEASE_KIND=deb 'RELEASE_KIND=zip tar' \
        RELEASE_RUNNER=mac RELEASE_MANIFEST=dir/file.json RELEASE_ASSETS=../outside \
        RELEASE_ASSETS=/abs 'VERSION_COPY=file' 'VERSION_COPY=../f|X.Y.Z' \
        'VERSION_COPY=f|X.Y.Z X.Y.Z' 'PRIVACY_RULES=base extra' MAX_BLOB_KB=0 MAX_BLOB_KB=12345678 \
        MAX_BLOB_KB=1k; do
        write_config "$bad"
        run_conf --check "$FILE"
        if [[ $status -ne 1 || $stderr != *"conf: line "*": ${bad%%=*}: expected"* ]]; then
            printf 'not refused as expected: %s\n%s\n' "$bad" "$stderr" >&2
            return 1
        fi
    done
}

@test "a CR line end, a trailing space and a tab are refused" {
    mkdir -p "${FILE%/*}"
    printf 'NAME=example\r\nVISIBILITY=private\nRELEASE_KIND=tar \nPYTHON=3.1\t3\n' > "$FILE"
    run_conf --check "$FILE"
    [ "$status" -eq 1 ]
    [[ $stderr == *"line 1: ends with a CR"* ]]
    [[ $stderr == *"line 3: RELEASE_KIND: the value ends with a space"* ]]
    [[ $stderr == *"line 4: PYTHON: the value ends with a space or holds a tab"* ]]
}

@test "PRIVACY_ALLOW needs a pack kind other than denylist and an anchored value ERE" {
    local bad
    for bad in 'denylist ^x/ ^value$' 'no-such-kind ^x/ ^value$' 'home-path ^x/' \
        "home-path ^x/ $SYN_HOME$" "home-path ^x/ ^$SYN_HOME" \
        "home-path ^x/ ^$SYN_HOME\\\$"; do
        write_config "PRIVACY_ALLOW=$bad"
        run_conf --check "$FILE"
        if [[ $status -ne 1 || $stderr != *"PRIVACY_ALLOW: expected"* ]]; then
            printf 'not refused: %s\n%s\n' "$bad" "$stderr" >&2
            return 1
        fi
    done
}

@test "PRIVACY_ALLOW refuses a value ERE that would also exempt a realistic value" {
    local bad
    for bad in "home-path ^tests/ ^$HOME_PREFIX.*$" 'home-path ^tests/ ^[a-z]:[\\/]+users[\\/]+.*$' \
        'ipv4-private ^ ^192\.168\..*$' 'e-mail ^ ^.*@gmail\.com$' \
        'uuid ^ ^[0-9a-f-]+$' 'disk-by-id ^ ^/dev/disk/by-id/.*$' \
        'mac-address ^ ^..:..:..:..:..:..$' 'host-name ^ ^.*\.lan$'; do
        write_config "PRIVACY_ALLOW=$bad"
        run_conf --check "$FILE"
        if [[ $status -ne 1 || $stderr != *"the value ERE matches a realistic"* ]]; then
            printf 'not refused: %s\n%s\n' "$bad" "$stderr" >&2
            return 1
        fi
    done
    write_config "PRIVACY_ALLOW=home-path ^tests/ ^$SYN_HOME$" \
        'PRIVACY_ALLOW=ipv4-private ^compose\.yaml$ ^172\.30\.0\.[0-9]+$'
    run_conf --check "$FILE"
    [ "$status" -eq 0 ]
}

@test "PRIVACY_ALLOW refuses an ERE that does not compile" {
    write_config "PRIVACY_ALLOW=home-path ^tests/( ^$SYN_HOME$"
    run_conf --check "$FILE"
    [ "$status" -eq 1 ]
    [[ $stderr == *"PRIVACY_ALLOW: an ERE does not compile"* ]]
}

@test "PRIVACY_HISTORY_ACCEPT needs a full commit SHA and a pack kind" {
    local sha bad
    sha=$(printf '%040d' 7)
    write_config "PRIVACY_HISTORY_ACCEPT=$sha e-mail" "PRIVACY_HISTORY_ACCEPT=$sha${sha:0:24} uuid"
    run_conf --check "$FILE"
    [ "$status" -eq 0 ]
    for bad in "${sha:0:12} e-mail" "$sha denylist" "$sha no-such-kind" "$sha" "$sha e-mail extra" \
        "${sha^^}x e-mail"; do
        write_config "PRIVACY_HISTORY_ACCEPT=$bad"
        run_conf --check "$FILE"
        if [[ $status -ne 1 ]]; then
            printf 'not refused: %s\n' "$bad" >&2
            return 1
        fi
    done
}

@test "no message shows a value from the file" {
    write_config NAME=Example_5ca1ab1e PYTHON=five-ca1ab1e "PRIVACY_ALLOW=home-path ^x/ ^$HOME_PREFIX.*5ca1ab1e.*$"
    run_conf --check "$FILE"
    [ "$status" -eq 1 ]
    [[ $stderr != *5ca1ab1e* && $stderr != *5CA1AB1E* ]]
}

@test "usage errors exit 64, and a missing file exits 2 without its path" {
    run_conf
    [ "$status" -eq 64 ]
    run_conf --bogus
    [ "$status" -eq 64 ]
    run_conf --get
    [ "$status" -eq 64 ]
    run_conf --get NO_SUCH_KEY "$FILE"
    [ "$status" -eq 64 ]
    run_conf --defaults extra
    [ "$status" -eq 64 ]
    run_conf --check "$BATS_TEST_TMPDIR/missing-5ca1ab1e.conf"
    [ "$status" -eq 2 ]
    [[ $stderr != *missing-5ca1ab1e* ]]
}

@test "conf reads the config from stdin with -" {
    write_config
    run --separate-stderr sh -c 'sh "$1" --get NAME - < "$2"' sh "$CONF" "$FILE"
    [ "$status" -eq 0 ]
    [ "$output" = example ]
}

@test "conf runs under dash" {
    need command dash
    write_config "PRIVACY_ALLOW=home-path ^tests/ ^$SYN_HOME$"
    run --separate-stderr dash "$CONF" --get PRIVACY_ALLOW "$FILE"
    [ "$status" -eq 0 ]
    [ "$output" = "home-path ^tests/ ^$SYN_HOME$" ]
}

@test "PRIVACY_ALLOW refuses a | outside parentheses and a path ERE without ^" {
    local bad
    for bad in "home-path ^x/ ^$SYN_HOME\$|b\$" "home-path ^x/|^y/ ^$SYN_HOME\$" \
        "home-path x/ ^$SYN_HOME\$"; do
        write_config "PRIVACY_ALLOW=$bad"
        run_conf --check "$FILE"
        if [[ $status -ne 1 || $stderr != *"PRIVACY_ALLOW: expected"* ]]; then
            printf 'not refused: %s\n%s\n' "$bad" "$stderr" >&2
            return 1
        fi
    done
    write_config "PRIVACY_ALLOW=home-path ^(x|y)/ ^$HOME_PREFIX(example-user|example-admin)\$" \
        'PRIVACY_ALLOW=ipv4-private ^compose\.yaml$ ^172\.30\.0\.[0-9|]+$'
    run_conf --check "$FILE"
    [ "$status" -eq 0 ]
}

@test "--allow-lines prints the PRIVACY_ALLOW lines of a config that parses, and nothing otherwise" {
    write_config "PRIVACY_ALLOW=home-path ^tests/ ^$SYN_HOME\$" PRIVACY_RULES=base
    run_conf --allow-lines "$FILE"
    [ "$status" -eq 0 ]
    [ "$output" = 4 ]
    write_config "PRIVACY_ALLOW=home-path ^tests/ $SYN_HOME\$"
    run_conf --allow-lines "$FILE"
    [ "$status" -eq 1 ]
    [ -z "$output" ]
}
