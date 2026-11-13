# ci/lint.ps1 starter for a PowerShell repository: PSScriptAnalyzer over the PowerShell files,
# with the pinned module that install-tools installs (PS_MODULES=psscriptanalyzer). run-stage runs
# it under Windows PowerShell 5.1 from the top of the repository.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module -Name PSScriptAnalyzer -RequiredVersion 1.25.0
$files = @(Get-ChildItem -Path . -Recurse -File -Include *.ps1, *.psm1, *.psd1 |
    Where-Object { $_.FullName -notmatch '[\\/]\.git[\\/]' })
$findings = @($files | ForEach-Object { Invoke-ScriptAnalyzer -Path $_.FullName -Severity Warning, Error })
$findings | Format-Table -AutoSize | Out-String | Write-Output
if ($findings.Count -gt 0) { exit 1 }
