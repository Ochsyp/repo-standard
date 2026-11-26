# ci/test.ps1 of repo-standard, after ci/test on Windows: a smoke test of the PowerShell modules
# that install-tools installs from their pinned packages (PS_MODULES). The pinned Pester must pass
# one test, and the pinned PSScriptAnalyzer must find the one rule a smoke script breaks. So both
# are known to load and to work under Windows PowerShell 5.1. Then Pester runs
# tests/release-seal.Tests.ps1, the tests of the seal dialog, which must all pass, none skipped.
# The pinned versions come from install-tools, so a new pin there needs no edit here.
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

$pester = Get-Pin -Name PESTER
$analyzer = Get-Pin -Name PSSCRIPTANALYZER
Import-Module -Name Pester -RequiredVersion $pester
Import-Module -Name PSScriptAnalyzer -RequiredVersion $analyzer
$dir = Join-Path -Path $env:TEMP -ChildPath ('repo-standard-modules-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $dir | Out-Null
try {
    $test = Join-Path -Path $dir -ChildPath 'Smoke.Tests.ps1'
    Set-Content -Path $test -Encoding ASCII -Value "Describe 'smoke' { It 'adds' { 1 + 1 | Should -Be 2 } }"
    $result = Invoke-Pester -Path $test -PassThru -Output None
    if ($result.PassedCount -ne 1 -or $result.FailedCount -ne 0) {
        throw ("Pester {0} did not pass its one smoke test" -f $pester)
    }
    $script = Join-Path -Path $dir -ChildPath 'Smoke.ps1'
    Set-Content -Path $script -Encoding ASCII -Value 'Invoke-Expression -Command "Get-Date"'
    $rules = @(Invoke-ScriptAnalyzer -Path $script | ForEach-Object { $_.RuleName })
    if ($rules -notcontains 'PSAvoidUsingInvokeExpression') {
        $text = 'PSScriptAnalyzer {0} did not find PSAvoidUsingInvokeExpression in its smoke script'
        throw ($text -f $analyzer)
    }
    Write-Output ('ci/test.ps1: Pester {0} and PSScriptAnalyzer {1} load and work' -f $pester,
        $analyzer)
} finally {
    Remove-Item -LiteralPath $dir -Recurse -Force
}

$suite = Join-Path -Path $PSScriptRoot -ChildPath '..\tests\release-seal.Tests.ps1'
$result = Invoke-Pester -Path $suite -PassThru -Output Detailed
if ($result.FailedCount -ne 0 -or $result.PassedCount -eq 0 -or $result.SkippedCount -ne 0 -or
    $result.NotRunCount -ne 0 -or $result.InconclusiveCount -ne 0) {
    throw ('tests/release-seal.Tests.ps1: {0} passed, {1} failed, {2} skipped, {3} not run' -f
        $result.PassedCount, $result.FailedCount, $result.SkippedCount, $result.NotRunCount)
}
Write-Output ('ci/test.ps1: tests/release-seal.Tests.ps1 passed {0} tests' -f $result.PassedCount)
