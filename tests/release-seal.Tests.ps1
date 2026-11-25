# release-seal.Tests.ps1 of repo-standard: the dialog of the seal tool, tools/release-seal.ps1,
# under Windows PowerShell 5.1 with the pinned Pester and PSScriptAnalyzer, which ci/test.ps1
# imports before it runs this file on Windows. The forms are built and checked, never shown, and
# a stub script stands in for release-seal. Every value is synthetic.

BeforeAll {
    $SealScript = Join-Path -Path $PSScriptRoot -ChildPath '..\tools\release-seal.ps1'
    . $SealScript -Repo 'example-owner/example'
    Add-Type -AssemblyName System.Windows.Forms, System.Drawing

    # The lines of a release-seal check run in which every check passed.
    function Get-GoodLine {
        @(
            "check`tok`tpublished`tpublished 2026-11-14, immutable",
            "check`tok`tdrafted`tdrafted by github-actions[bot]",
            "check`tok`tcommit`t0123456789ab is on main",
            "check`tok`tversion`tVERSION reads 1.1.0",
            "check`tok`tconfigured`tSEAL=yes at the commit of v1.1.0",
            "check`tok`tverify`tthe verify run of v1.1.0 is green",
            "check`tok`tunsealed`tno seal/v1.1.0 yet",
            "fact`tcommit`t0123456789abcdef0123456789abcdef01234567",
            "fact`tpr`t#3 chore(release): 1.1.0",
            "fact`tbase`tv1.0.0",
            "fact`tsince`t0123456 chore(release): 1.1.0 (#3)",
            "fact`tsince`t89abcde feat: a feature (#2)"
        )
    }
}

Describe 'ConvertFrom-SealOutput' {
    It 'reads the checks, the facts and the commits since the base' {
        $result = ConvertFrom-SealOutput -Lines (Get-GoodLine)
        @($result.Checks).Count | Should -Be 7
        $result.Checks[0].Name | Should -Be 'published'
        $result.Checks[0].Result | Should -Be 'ok'
        $result.Commit | Should -Be '0123456789abcdef0123456789abcdef01234567'
        $result.Pr | Should -Be '#3 chore(release): 1.1.0'
        $result.Base | Should -Be 'v1.0.0'
        @($result.Since).Count | Should -Be 2
        $result.Sealed | Should -Be ''
    }

    It 'reads the sealed line and ignores the lines it does not know' {
        $result = ConvertFrom-SealOutput -Lines @("sealed`tseal/v1.1.0`t0123", 'noise', "fact`tother`tx")
        $result.Sealed | Should -Be 'seal/v1.1.0'
        @($result.Checks).Count | Should -Be 0
    }
}

Describe 'Test-SealReady' {
    It 'is true only when each of the seven checks is there and passed' {
        Test-SealReady -Result (ConvertFrom-SealOutput -Lines (Get-GoodLine)) | Should -BeTrue
        $failed = (Get-GoodLine) -replace "^check`tok`tverify`t.*", "check`tFAIL`tverify`tthe verify run of v1.1.0 ended with failure"
        Test-SealReady -Result (ConvertFrom-SealOutput -Lines $failed) | Should -BeFalse
        $missing = @(Get-GoodLine | Where-Object { $_ -notlike "check`tok`tunsealed*" })
        Test-SealReady -Result (ConvertFrom-SealOutput -Lines $missing) | Should -BeFalse
        # A repository without SEAL=yes: the check fails, or an older tool did not print it.
        $notSealed = (Get-GoodLine) -replace "^check`tok`tconfigured`t.*", "check`tFAIL`tconfigured`tthe config at v1.1.0 does not set SEAL=yes"
        Test-SealReady -Result (ConvertFrom-SealOutput -Lines $notSealed) | Should -BeFalse
        $noConfigured = @(Get-GoodLine | Where-Object { $_ -notlike "check`tok`tconfigured*" })
        Test-SealReady -Result (ConvertFrom-SealOutput -Lines $noConfigured) | Should -BeFalse
        Test-SealReady -Result (ConvertFrom-SealOutput -Lines @()) | Should -BeFalse
    }
}

Describe 'ConvertFrom-SealVersionList' {
    It 'keeps the vX.Y.Z lines with their seal state, in their order' {
        $list = @(ConvertFrom-SealVersionList -Lines @("v1.2.0`tunsealed", "nightly`tunsealed", "v1.1.0`tsealed"))
        $list.Count | Should -Be 2
        $list[0].Tag | Should -Be 'v1.2.0'
        $list[0].Sealed | Should -BeFalse
        $list[1].Tag | Should -Be 'v1.1.0'
        $list[1].Sealed | Should -BeTrue
    }
}

Describe 'ConvertTo-BashArgument' {
    It 'leaves a plain argument and quotes blanks, quotes and an empty one' {
        ConvertTo-BashArgument -Value 'check' | Should -Be 'check'
        ConvertTo-BashArgument -Value 'C:/Program Files/x' | Should -Be '"C:/Program Files/x"'
        ConvertTo-BashArgument -Value 'a"b' | Should -Be '"a\"b"'
        ConvertTo-BashArgument -Value '' | Should -Be '""'
        ConvertTo-BashArgument -Value 'C:\a dir\' | Should -Be '"C:\a dir\\"'
    }
}

Describe 'Get-SealForm and Show-SealResult' {
    BeforeEach {
        $versions = @(
            [pscustomobject]@{ Tag = 'v1.1.0'; Sealed = $false },
            [pscustomobject]@{ Tag = 'v1.0.0'; Sealed = $true }
        )
        $form = Get-SealForm -Name 'example-owner/example' -Versions $versions
    }

    AfterEach {
        $form.Dispose()
    }

    It 'lists the versions with their seal state, and starts with Seal off and never the default button' {
        $form.Text | Should -Be 'Seal example-owner/example release'
        (@($form.Tag.Version.Items) -join '|') | Should -Be 'v1.1.0 (not sealed)|v1.0.0 (sealed)'
        $form.Tag.Seal.Enabled | Should -BeFalse
        $form.AcceptButton | Should -BeNullOrEmpty
        [object]::ReferenceEquals($form.CancelButton, $form.Tag.Cancel) | Should -BeTrue
        $form.Visible | Should -BeFalse
    }

    It 'shows the facts and each check, and enables Seal only when every check passed' {
        Show-SealResult -Form $form -Result (ConvertFrom-SealOutput -Lines (Get-GoodLine))
        $form.Tag.Commit.Text | Should -Be '0123456789abcdef0123456789abcdef01234567'
        $form.Tag.Pr.Text | Should -Be '#3 chore(release): 1.1.0'
        $form.Tag.Base.Text | Should -Be 'Commits since v1.0.0, newest first'
        @($form.Tag.Since.Lines).Count | Should -Be 2
        $form.Tag.Checks.Items.Count | Should -Be 7
        $form.Tag.Seal.Enabled | Should -BeTrue
        $failed = (Get-GoodLine) -replace "^check`tok`tcommit`t.*", "check`tFAIL`tcommit`tthe commit of v1.1.0 is not on main"
        Show-SealResult -Form $form -Result (ConvertFrom-SealOutput -Lines $failed)
        $form.Tag.Seal.Enabled | Should -BeFalse
        $form.Tag.Checks.Items[2].SubItems[1].Text | Should -Be 'FAIL'
        $form.Tag.Checks.Items[2].ForeColor | Should -Be ([System.Drawing.Color]::Firebrick)
    }
}

Describe 'Get-PassphraseForm' {
    It 'masks what is typed, stays on top, and has OK and Cancel' {
        $form = Get-PassphraseForm
        try {
            $form.Tag.Box.UseSystemPasswordChar | Should -BeTrue
            $form.TopMost | Should -BeTrue
            [object]::ReferenceEquals($form.AcceptButton, $form.Tag.Ok) | Should -BeTrue
            [object]::ReferenceEquals($form.CancelButton, $form.Tag.Cancel) | Should -BeTrue
            $form.Tag.Ok.DialogResult | Should -Be ([System.Windows.Forms.DialogResult]::OK)
        } finally {
            $form.Dispose()
        }
    }
}

Describe 'Invoke-SealCore' {
    It 'runs the script in bash with no window and returns its exit code, lines and error lines' {
        $dir = Join-Path -Path $env:TEMP -ChildPath ('release-seal-test-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $dir | Out-Null
        try {
            $stub = Join-Path -Path $dir -ChildPath 'stub seal'
            $body = @'
printf 'fact\tpr\t%s\n' "$*"
printf 'oops\n' >&2
exit 3
'@
            [System.IO.File]::WriteAllText($stub, ($body -replace "`r", '') + "`n")
            $run = Invoke-SealCore -BashPath (Get-SealBash) -Script $stub `
                -Arguments @('check', '--repo', 'example-owner/example', '--version', '1.1.0')
            $run.ExitCode | Should -Be 3
            ($run.Lines -join '|') | Should -Be "fact`tpr`tcheck --repo example-owner/example --version 1.1.0"
            ($run.Errors -join '|') | Should -Be 'oops'
        } finally {
            Remove-Item -LiteralPath $dir -Recurse -Force
        }
    }
}

Describe 'Invoke-ReleaseCheck and Invoke-ReleaseSeal' {
    BeforeAll {
        # A stub of release-seal that prints the files beside it: check.out for check, and for
        # seal seal.out, seal.err on stderr and the exit code in seal.rc.
        $stubDir = Join-Path -Path $env:TEMP -ChildPath ('release-seal-test-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $stubDir | Out-Null
        $stub = Join-Path -Path $stubDir -ChildPath 'release-seal'
        $body = @'
here=$(dirname "$0")
case $1 in
    check) cat "$here/check.out" ;;
    seal) cat "$here/seal.out"; cat "$here/seal.err" >&2; exit "$(cat "$here/seal.rc")" ;;
esac
'@
        [System.IO.File]::WriteAllText($stub, ($body -replace "`r", '') + "`n")
        [System.IO.File]::WriteAllText((Join-Path -Path $stubDir -ChildPath 'check.out'), ((Get-GoodLine) -join "`n") + "`n")
        $bash = Get-SealBash
        $versions = @([pscustomobject]@{ Tag = 'v1.1.0'; Sealed = $false })
        $slug = 'example-owner/example'

        # Make the stub's seal print OUT, ERR on stderr, and exit with RC.
        function Set-SealStub {
            param([string] $Out, [string] $Err, [int] $Rc)
            [System.IO.File]::WriteAllText((Join-Path -Path $stubDir -ChildPath 'seal.out'), $Out)
            [System.IO.File]::WriteAllText((Join-Path -Path $stubDir -ChildPath 'seal.err'), $Err)
            [System.IO.File]::WriteAllText((Join-Path -Path $stubDir -ChildPath 'seal.rc'), "$Rc`n")
        }
    }

    AfterAll {
        Remove-Item -LiteralPath $stubDir -Recurse -Force
    }

    BeforeEach {
        $form = Get-SealForm -Name $slug -Versions $versions
        $form.Tag.Version.SelectedIndex = 0
    }

    AfterEach {
        $form.Dispose()
    }

    It 'shows a check run in which every check passed, and enables Seal' {
        Invoke-ReleaseCheck -Form $form -Shell $bash -Slug $slug -Versions $versions -Script $stub
        $form.Tag.Status.Text | Should -Be 'Every check passed.'
        $form.Tag.Seal.Enabled | Should -BeTrue
        $form.Tag.Checks.Items.Count | Should -Be 7
    }

    It 'turns an error into its status line, with Seal off, and never throws' {
        # A bash that is not there makes the process start throw inside both functions.
        $missing = Join-Path -Path $stubDir -ChildPath 'no-such-bash.exe'
        Invoke-ReleaseCheck -Form $form -Shell $missing -Slug $slug -Versions $versions -Script $stub
        $form.Tag.Seal.Enabled | Should -BeFalse
        $form.Tag.Status.Text | Should -BeLike 'The checks cannot run: *'
        Invoke-ReleaseSeal -Form $form -Shell $missing -Slug $slug -Versions $versions -Script $stub |
            Should -Be ''
        $form.Tag.Status.Text | Should -BeLike 'Not sealed: *'
        $form.Tag.Seal.Enabled | Should -BeFalse
        $form.Tag.Cancel.Enabled | Should -BeTrue
    }

    It 'returns the seal it pushed, and on a refusal an empty name, with Cancel and the picker on again' {
        Set-SealStub -Out "sealed`tseal/v1.1.0`t0123456789abcdef0123456789abcdef01234567`n" -Err '' -Rc 0
        Invoke-ReleaseSeal -Form $form -Shell $bash -Slug $slug -Versions $versions -Script $stub |
            Should -Be 'seal/v1.1.0'
        $form.Tag.Status.Text | Should -Be 'seal/v1.1.0 is sealed and pushed.'
        Set-SealStub -Out '' -Err "release-seal: the seal could not be signed`n" -Rc 1
        Invoke-ReleaseSeal -Form $form -Shell $bash -Slug $slug -Versions $versions -Script $stub |
            Should -Be ''
        $form.Tag.Status.Text | Should -Be 'Not sealed: release-seal: the seal could not be signed'
        $form.Tag.Seal.Enabled | Should -BeFalse
        $form.Tag.Cancel.Enabled | Should -BeTrue
        $form.Tag.Version.Enabled | Should -BeTrue
    }
}

Describe 'PSScriptAnalyzer' {
    It 'reports no warning and no error in release-seal.ps1' {
        $findings = @(Invoke-ScriptAnalyzer -Path $SealScript -Severity Warning, Error)
        ($findings | ForEach-Object { '{0} line {1}: {2}' -f $_.RuleName, $_.Line, $_.Message }) -join "`n" |
            Should -BeNullOrEmpty
    }
}
