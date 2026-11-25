# ci/test.ps1 of repo-standard, after ci/test on Windows: a smoke test of the PowerShell modules
# that install-tools installs from their pinned packages (PS_MODULES). The pinned Pester must pass
# one test, and the pinned PSScriptAnalyzer must find the one rule a smoke script breaks. So both
# are known to load and to work under Windows PowerShell 5.1. Then Pester runs
# tests/release-seal.Tests.ps1, the tests of the seal dialog, which must all pass, none skipped.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module -Name Pester -RequiredVersion 6.2.0
Import-Module -Name PSScriptAnalyzer -RequiredVersion 1.25.0
$dir = Join-Path -Path $env:TEMP -ChildPath ('repo-standard-modules-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $dir | Out-Null
try {
    $test = Join-Path -Path $dir -ChildPath 'Smoke.Tests.ps1'
    Set-Content -Path $test -Encoding ASCII -Value "Describe 'smoke' { It 'adds' { 1 + 1 | Should -Be 2 } }"
    $result = Invoke-Pester -Path $test -PassThru -Output None
    if ($result.PassedCount -ne 1 -or $result.FailedCount -ne 0) {
        throw "Pester 6.2.0 did not pass its one smoke test"
    }
    $script = Join-Path -Path $dir -ChildPath 'Smoke.ps1'
    Set-Content -Path $script -Encoding ASCII -Value 'Invoke-Expression -Command "Get-Date"'
    $rules = @(Invoke-ScriptAnalyzer -Path $script | ForEach-Object { $_.RuleName })
    if ($rules -notcontains 'PSAvoidUsingInvokeExpression') {
        throw "PSScriptAnalyzer 1.25.0 did not find PSAvoidUsingInvokeExpression in its smoke script"
    }
    Write-Output 'ci/test.ps1: Pester 6.2.0 and PSScriptAnalyzer 1.25.0 load and work'
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
