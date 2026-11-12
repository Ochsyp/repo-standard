#!/usr/bin/env bats
# privacy-scan.bats of the repository standard: the same file in every repository; never edit it
# here. The rule packs base, disk and vm against a catalogue of leaks and of synthetic values,
# PRIVACY_ALLOW and PRIVACY_HISTORY_ACCEPT, every mode of privacy-scan, and its failures. The
# leaks are built from fragments at run time, so this file holds no value a rule matches.

# The sh -c scripts are single-quoted, ~ stays literal in git config values, and bats runs each
# test in a subshell, all on purpose.
# shellcheck disable=SC1003,SC2016,SC2030,SC2031,SC2088
load lib

setup() {
    isolate_home
}

# Run privacy-scan with ARGS in DIR (default $REPO) through bats `run`, stderr apart.
scan_in() {
    local dir=$1
    shift
    run --separate-stderr sh -c 'cd "$1" && shift && exec sh .githooks/privacy-scan "$@"' \
        sh "$dir" "$@"
}
scan() {
    scan_in "$REPO" "$@"
}

# Print one leak of each kind per line; the comment names the kind of each line.
leaks() {
    printf 'addr %s.%s.%s.%s\n' 192 168 7 9                   # 1 ipv4-private
    printf 'addr %s.%s.%s.%s\n' 10 1 2 3                      # 2 ipv4-private
    printf 'addr %s.%s.%s.%s\n' 172 20 0 5                    # 3 ipv4-private
    printf 'addr %s.%s.%s.%s\n' 100 100 4 2                   # 4 ipv4-private
    printf 'addr %s::%s\n' fe80 1                             # 5 ipv6-private
    printf 'addr %s:%s::%s\n' fd12 3456 1                     # 6 ipv6-private
    printf 'host printer.%s\n' lan                            # 7 host-name
    printf 'host nas.home.%s\n' arpa                          # 8 host-name
    printf 'host pi.%s\n' local                               # 9 host-name
    printf 'host db.%s\n' internal                            # 10 host-name
    printf 'host laptop.tail1234.ts.%s\n' net                 # 11 host-name
    printf 'mac %s:%s:%s:%s:%s:%s\n' 3c 22 fb 12 34 56        # 12 mac-address
    printf 'mac %s-%s-%s-%s-%s-%s\n' B8 27 EB 12 34 56        # 13 mac-address
    printf 'path /%s/someone/file\n' home                     # 14 home-path
    printf 'win C:%sUsers%ssomeone\n' '\' '\'                 # 15 home-path
    printf 'win C:/%s/someone\n' Users                         # 16 home-path
    printf 'msys /c/%s/someone\n' Users                       # 17 home-path
    printf 'mac /%s/someone\n' Users                          # 18 home-path
    printf 'mail someone@%s\n' example.de                     # 19 e-mail
    printf 'uuid %s-%s-%s-%s-%s\n' d00dfeed cafe 4abc 8def 0123456789ab   # 20 uuid
    printf 'luks %s%s%s%s%s\n' d00dfeed cafe 4abc 8def 0123456789ab       # 21 uuid-dashless
    printf 'serial %s%s\n' D00DFEED CAFEF00D                  # 22 ntfs-serial
    printf 'fat %s="%s-%s"\n' UUID 1A2B 3C4D                  # 23 fat-serial
    printf 'search --fs-uuid --set=root %s-%s\n' 1a2b 3c4d    # 24 fat-serial
    printf 'lvm %s-%s-%s-%s-%s-%s-%s\n' Ab12Cd 3456 7890 abcd EfGh 1234 Zz99Yy   # 25 lvm-uuid
    printf 'disk %sUUID="%s-01"\n' PART d00dfeed              # 26 partuuid
    printf 'id /dev/disk/%s/%s\n' by-id usb-Vendor_Model_123456-0:0      # 27 disk-by-id
    printf 'vm %s %s %s %s %s %s %s %s-%s %s %s %s %s %s %s %s\n' \
        56 4d 12 34 56 78 9a bc de f0 12 34 56 78 9a bc       # 28 vmware-uuid
    printf 'nic %s="%s"\n' MACAddress 080027AB12CD            # 29 vbox-mac
    printf 'label %s\n' "${DENY_TERM^^}"                      # 30 denylist
}

# Print synthetic and reserved values that every pack lets through.
synthetic() {
    printf 'addr %s.%s.%s.%s\n' 192 0 2 10
    printf 'addr %s:%s::%s\n' 2001 db8 1
    printf 'host example-nas.home.%s\n' arpa
    printf 'host example-pi.%s\n' local
    printf 'mac %s-%s-%s-%s-%s-%s\n' 00 00 5E 00 53 01
    printf 'mac %s:%s:%s:%s:%s:%s\n' 5c a1 ab 1e 00 01
    printf 'mail test@example.%s\n' invalid
    printf 'mail someone@example.%s\n' com
    printf 'mail %s@%s.%s\n' 12345+someone users.noreply.github com
    printf 'trailer <noreply@%s.%s>\n' example org
    printf 'remote git@github.%s:owner/repo.git\n' com
    printf 'uuid %s-%s-%s-%s-%s\n' 5ca1ab1e cafe 4abc 8def 0123456789ab
    printf 'luks %s%s\n' 5ca1ab1e 0123456789abcdef01234567
    printf 'serial %s%s\n' 5CA1AB1E 01234567
    printf 'fat %s="%s"\n' UUID 5CA1-AB1E
    printf 'lvm %s-%s-%s-%s-%s-%s-%s\n' 5ca1ab 3456 7890 abcd EfGh 1234 Zz99Yy
    printf 'disk %sUUID=%s-01\n' PART 5ca1ab1e
    printf 'id /dev/disk/%s/%s\n' by-id usb-Synthetic_Stick_5CA1AB1E00000001-0:0
    printf 'id /dev/disk/%s/%s\n' by-id ata-Synthetic-part1
    printf 'glob /dev/disk/%s/*\n' by-id
    printf 'vm %s %s %s %s %s %s %s %s-%s %s %s %s %s %s %s %s\n' \
        5c a1 ab 1e 00 00 00 01 de f0 12 34 56 78 9a bc
    printf 'nic %s="%s"\n' MACAddress 5CA1AB1E0001
}

@test "privacy-scan reports each kind of leak by file and line, never the value" {
    local blob hit name
    local -a want=()
    make_repo
    write_denylist
    git -C "$REPO" switch -q -c feat/example
    commit_config 'PRIVACY_RULES=base disk vm'
    leaks > "$REPO/leak.txt"
    printf 'one\r\ntwo\r\n' > "$REPO/crlf.txt"
    name=$(printf 'nas.%s.txt' lan)
    printf 'synthetic\n' > "$REPO/$name"
    git -C "$REPO" add leak.txt crlf.txt "$name"
    blob=$(printf '/%s/someone/x' home | git -C "$REPO" hash-object -w --stdin)
    git -C "$REPO" update-index --add --cacheinfo "120000,$blob,link"
    scan --staged
    [ "$status" -eq 1 ]
    want=(1 2 3 4)
    for hit in "${want[@]}"; do [[ $stderr == *"leak.txt:$hit: ipv4-private"* ]]; done
    for hit in 5 6; do [[ $stderr == *"leak.txt:$hit: ipv6-private"* ]]; done
    for hit in 7 8 9 10 11; do [[ $stderr == *"leak.txt:$hit: host-name"* ]]; done
    for hit in 12 13; do [[ $stderr == *"leak.txt:$hit: mac-address"* ]]; done
    for hit in 14 15 16 17 18; do [[ $stderr == *"leak.txt:$hit: home-path"* ]]; done
    for hit in "19: e-mail" "20: uuid" "21: uuid-dashless" "22: ntfs-serial" "23: fat-serial" \
        "24: fat-serial" "25: lvm-uuid" "26: partuuid" "27: disk-by-id" "28: vmware-uuid" \
        "29: vbox-mac" "30: denylist"; do
        [[ $stderr == *"leak.txt:$hit"* ]] || { printf 'missing: leak.txt:%s\n%s\n' "$hit" "$stderr" >&2; return 1; }
    done
    [[ $stderr == *"privacy-scan: crlf.txt: crlf"* ]]
    [[ $stderr == *"privacy-scan: link:1: home-path"* ]]
    [[ $stderr == *"privacy-scan: path name 4 of the scanned paths: host-name"* ]]
    # Exactly these 33 findings: nothing twice, nothing else.
    [ "$(grep -c '^privacy-scan: .*: [a-z0-9-]*$' <<< "$stderr")" -eq 33 ]
    [[ $stderr != *someone* && $stderr != *d00dfeed* && $stderr != *D00DFEED* && $stderr != *1A2B* ]]
    refute_term_shown
    assert_tmpdir_empty
}

@test "the synthetic and reserved values pass every pack" {
    make_repo
    git -C "$REPO" switch -q -c feat/example
    commit_config 'PRIVACY_RULES=base disk vm'
    synthetic > "$REPO/fixture.txt"
    printf 'synthetic\n' > "$REPO/example-nas.lan.txt"
    git -C "$REPO" add fixture.txt example-nas.lan.txt
    scan --staged
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "privacy-scan refuses a bad option or argument count with exit 64" {
    make_repo
    scan --all
    [ "$status" -eq 64 ]
    [[ $stderr == usage:* ]]
    scan
    [ "$status" -eq 64 ]
    scan --staged extra
    [ "$status" -eq 64 ]
    scan --message
    [ "$status" -eq 64 ]
    scan --range
    [ "$status" -eq 64 ]
}

@test "privacy-scan --tracked finds nothing in this repository" {
    scan_in "$REPO_ROOT" --tracked
    [ "$status" -eq 0 ]
}

@test "the standard's own files pass every rule pack" {
    REPO="$BATS_TEST_TMPDIR/copy"
    git -C "$REPO_ROOT" checkout-index -a --prefix="$REPO/"
    git init -q -b main "$REPO"
    git -C "$REPO" config user.name "Test User"
    git -C "$REPO" config user.email test@example.invalid
    git -C "$REPO" config core.autocrlf false
    git -C "$REPO" add -A
    commit_config 'PRIVACY_RULES=base disk vm'
    scan --tracked
    [ "$status" -eq 0 ]
}

@test "a PRIVACY_ALLOW exemption covers its own kind and paths only" {
    local home
    home=$(printf '/%s/%s' home example-user)
    make_repo
    git -C "$REPO" switch -q -c feat/example
    commit_config PRIVACY_RULES=base "PRIVACY_ALLOW=home-path ^tests/ ^$home\$"
    stage tests/a.txt "home $home"
    stage docs/b.txt "home $home"
    stage tests/c.txt "$(printf 'home /%s/someone' home)"
    scan --staged
    [ "$status" -eq 1 ]
    [[ $stderr == *"docs/b.txt:1: home-path"* ]]
    [[ $stderr == *"tests/c.txt:1: home-path"* ]]
    [[ $stderr != *"tests/a.txt"* ]]
}

@test "--message checks a file or stdin and names message lines" {
    make_repo
    write_denylist
    commit_config PRIVACY_RULES=base
    printf 'feat: add notes\n\nseen at printer.%s\nby %s\n' lan "$DENY_TERM" > "$BATS_TEST_TMPDIR/msg"
    scan --message "$BATS_TEST_TMPDIR/msg"
    [ "$status" -eq 1 ]
    [[ $stderr == *"message line 3: host-name"* ]]
    [[ $stderr == *"message line 4: denylist"* ]]
    refute_term_shown
    run --separate-stderr sh -c 'cd "$1" && printf "fix: a clean title\n" | sh .githooks/privacy-scan --message -' \
        sh "$REPO"
    [ "$status" -eq 0 ]
}

@test "--range scans what the commits bring in, not what the remote already has" {
    make_repo
    git -C "$REPO" switch -q -c feat/example
    commit_config PRIVACY_RULES=base
    git -C "$REPO" switch -q main
    git -C "$REPO" merge -q --ff-only feat/example
    stage old.txt "$(printf 'old /%s/someone' home)"
    git -C "$REPO" -c core.hooksPath=no-hooks commit -q -m "docs: old notes"
    add_remote
    git -C "$REPO" switch -q feat/example
    git -C "$REPO" merge -q --ff-only main
    stage notes.txt 'synthetic notes'
    git -C "$REPO" -c core.hooksPath=no-hooks commit -q -m "docs: notes"
    scan --range HEAD --not --remotes=origin
    [ "$status" -eq 0 ]
    stage new.txt "$(printf 'new /%s/someone' home)"
    git -C "$REPO" -c core.hooksPath=no-hooks commit -q -m "docs: new notes"
    scan --range HEAD --not --remotes=origin
    [ "$status" -eq 1 ]
    [[ $stderr == *"new.txt:1: home-path"* ]]
    [[ $stderr != *"old.txt"* ]]
}

@test "--history honours PRIVACY_HISTORY_ACCEPT for that commit and kind only" {
    local sha
    make_repo
    git -C "$REPO" switch -q -c feat/example
    commit_config PRIVACY_RULES=base
    stage old.txt "$(printf 'mail someone@%s\nhome /%s/someone' example.de home)"
    git -C "$REPO" -c core.hooksPath=no-hooks commit -q -m "docs: old notes"
    sha=$(git -C "$REPO" rev-parse HEAD)
    scan --history
    [ "$status" -eq 1 ]
    [[ $stderr == *"old.txt:1: e-mail"* ]]
    commit_config PRIVACY_RULES=base "PRIVACY_HISTORY_ACCEPT=$sha e-mail"
    scan --history
    [ "$status" -eq 1 ]
    [[ $stderr == *"old.txt:2: home-path"* ]]
    [[ $stderr != *"e-mail"* ]]
}

@test "CRLF in the index is refused, except in -text paths" {
    make_repo
    git -C "$REPO" switch -q -c feat/example
    printf '*.bin -text\n' > "$REPO/.gitattributes"
    printf 'one\r\ntwo\r\n' > "$REPO/crlf.txt"
    printf 'one\r\ntwo\r\n' > "$REPO/data.bin"
    git -C "$REPO" add .gitattributes crlf.txt data.bin
    scan --staged
    [ "$status" -eq 1 ]
    [[ $stderr == *"crlf.txt: crlf"* ]]
    [[ $stderr != *"data.bin"* ]]
}

@test "a committed config that does not parse makes every pack run, with a note" {
    make_repo
    git -C "$REPO" switch -q -c feat/example
    commit_config BOGUS=1
    stage disk.txt "$(printf 'uuid %s-%s-%s-%s-%s' d00dfeed cafe 4abc 8def 0123456789ab)"
    scan --staged
    [ "$status" -eq 1 ]
    [[ $stderr == *"does not parse, so every rule pack runs"* ]]
    [[ $stderr == *"disk.txt:1: uuid"* ]]
}

@test "a rule pack line that does not parse stops the scan with exit 2" {
    make_repo
    printf 'broken|rule\n' >> "$REPO/.githooks/rules/base"
    git -C "$REPO" switch -q -c feat/example
    commit_config PRIVACY_RULES=base
    stage notes.txt 'synthetic notes'
    scan --staged
    [ "$status" -eq 2 ]
    [[ $stderr == *"not kind|ERE|exempt-ERE"* ]]
    [[ $stderr == *"a rule pack does not parse, so this is refused"* ]]
}

@test "a missing rule pack stops the scan with exit 2" {
    make_repo
    git -C "$REPO" switch -q -c feat/example
    commit_config PRIVACY_RULES=vm
    rm "$REPO/.githooks/rules/vm"
    stage notes.txt 'synthetic notes'
    scan --staged
    [ "$status" -eq 2 ]
    [[ $stderr == *"the rule pack vm is missing"* ]]
}
