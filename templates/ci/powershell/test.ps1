# ci/test.ps1 starter for a PowerShell repository: the Pester tests in tests/, with the pinned
# Pester that install-tools installs (PS_MODULES=pester). A failed, skipped or missing test fails
# the run, as CI requires.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module -Name Pester -RequiredVersion 6.2.0
$result = Invoke-Pester -Path tests -PassThru -Output Detailed
if ($result.FailedCount -gt 0 -or $result.SkippedCount -gt 0 -or $result.PassedCount -eq 0) { exit 1 }
