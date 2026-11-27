# ci/test.ps1 starter for a PowerShell repository: the Pester tests in tests/, with the pinned
# Pester that install-tools installs (PS_MODULES=pester). A failed, skipped or missing test fails
# the run, as CI requires. The version comes from the copied install-tools, so a new pin there
# needs no edit here.
# Under run-stage on a Windows runner, whose account is an administrator, Git Bash turns on the
# backup and restore privileges for this script, so a Deny rule does not stop it listing a folder.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# The version that install-tools pins for NAME, from its line "readonly NAME_VERSION=X.Y.Z".
function Get-Pin {
    param([Parameter(Mandatory = $true)][string]$Name)
    $path = Join-Path -Path $PSScriptRoot -ChildPath '..\.github\standard\bin\install-tools'
    $pattern = '^readonly {0}_VERSION=([0-9]+\.[0-9]+\.[0-9]+)$' -f $Name
    $found = @(Select-String -LiteralPath $path -Pattern $pattern -CaseSensitive)
    if ($found.Count -ne 1) {
        throw ('install-tools does not pin {0}_VERSION in one line' -f $Name)
    }
    $found[0].Matches[0].Groups[1].Value
}

Import-Module -Name Pester -RequiredVersion (Get-Pin -Name PESTER)
$result = Invoke-Pester -Path tests -PassThru -Output Detailed
if ($result.FailedCount -gt 0 -or $result.SkippedCount -gt 0 -or $result.PassedCount -eq 0) { exit 1 }
