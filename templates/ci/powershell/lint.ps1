# ci/lint.ps1 starter for a PowerShell repository: PSScriptAnalyzer over the PowerShell files,
# with the pinned module that install-tools installs (PS_MODULES=psscriptanalyzer). run-stage runs
# it under Windows PowerShell 5.1 from the top of the repository. The version comes from the
# copied install-tools, so a new pin there needs no edit here.
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

Import-Module -Name PSScriptAnalyzer -RequiredVersion (Get-Pin -Name PSSCRIPTANALYZER)
$files = @(Get-ChildItem -Path . -Recurse -File -Include *.ps1, *.psm1, *.psd1 |
    Where-Object { $_.FullName -notmatch '[\\/]\.git[\\/]' })
$findings = @($files | ForEach-Object { Invoke-ScriptAnalyzer -Path $_.FullName -Severity Warning, Error })
$findings | Format-Table -AutoSize | Out-String | Write-Output
if ($findings.Count -gt 0) { exit 1 }
