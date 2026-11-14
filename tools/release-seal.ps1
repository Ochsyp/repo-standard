<#
.SYNOPSIS
The dialog of the seal tool (D1 = B): shows a published release of a SEAL=yes repository with
the checks of release-seal, and seals it on a click on Seal.

.DESCRIPTION
release-seal.ps1 of repo-standard, released as an asset beside release-seal and
release-seal-askpass and installed with them outside every clone. A desktop shortcut starts it
under Windows PowerShell 5.1 with a hidden window:
    powershell.exe -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass
        -File <folder>\release-seal.ps1 -Repo OWNER/NAME
It runs release-seal in Git for Windows' bash with no console window: versions for the version
picker, check for the facts and checks of the version picked, and seal after a click on Seal,
which is enabled only when every check passed and is never the default button. With -Askpass it
is the passphrase dialog that release-seal-askpass starts for ssh-keygen: it prints the
passphrase on stdout and nothing else, or exits 1 on Cancel. It never shows, logs or keeps the
passphrase. Exit 0 sealed; 1 not sealed; 2 the dialog cannot run.
#>
[CmdletBinding(DefaultParameterSetName = 'Seal')]
param(
    [Parameter(ParameterSetName = 'Seal', Mandatory = $true)]
    [ValidatePattern('^[A-Za-z0-9-]+/[A-Za-z0-9._-]+$')]
    [string] $Repo,

    [Parameter(ParameterSetName = 'Seal')]
    [string] $Bash,

    [Parameter(ParameterSetName = 'Askpass', Mandatory = $true)]
    [switch] $Askpass
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-SealBash {
    <# The bash.exe of Git for Windows: the path given, else bin\bash.exe of the Git folder that
       holds a git.exe on PATH (in cmd, bin or mingw64\bin), else of its install path. #>
    param([string] $Path)
    if ($Path) {
        if (Test-Path -LiteralPath $Path -PathType Leaf) { return $Path }
        throw 'There is no bash at the path that -Bash names.'
    }
    $folders = New-Object -TypeName System.Collections.Generic.List[string]
    foreach ($git in @(Get-Command -Name git.exe -CommandType Application -All -ErrorAction SilentlyContinue)) {
        $dir = Split-Path -Parent -Path $git.Source
        for ($up = 0; $up -lt 3 -and $dir; $up++) {
            $folders.Add($dir)
            $dir = Split-Path -Parent -Path $dir
        }
    }
    $install = Get-ItemProperty -Path 'HKLM:\SOFTWARE\GitForWindows' -Name InstallPath -ErrorAction SilentlyContinue
    if ($null -ne $install) { $folders.Add($install.InstallPath) }
    foreach ($folder in $folders) {
        $candidate = Join-Path -Path $folder -ChildPath 'bin\bash.exe'
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
    }
    throw 'Git for Windows was not found: the seal tool runs release-seal in its bash.'
}

function ConvertTo-BashArgument {
    <# One argument for a command line that the Windows C runtime splits, quoted where needed. #>
    param([Parameter(Mandatory = $true)] [AllowEmptyString()] [string] $Value)
    if ($Value -ne '' -and $Value -notmatch '[\s"]') { return $Value }
    $escaped = $Value -replace '(\\*)"', '$1$1\"' -replace '(\\+)$', '$1$1'
    return '"' + $escaped + '"'
}

function Invoke-SealCore {
    <# Runs release-seal (or -Script) in bash with the arguments given, with no window, and
       returns its exit code, its output lines and its error lines. #>
    param(
        [Parameter(Mandatory = $true)] [string] $BashPath,
        [Parameter(Mandatory = $true)] [string[]] $Arguments,
        [string] $Script = (Join-Path -Path $PSScriptRoot -ChildPath 'release-seal')
    )
    $all = @(($Script -replace '\\', '/')) + $Arguments
    $info = New-Object -TypeName System.Diagnostics.ProcessStartInfo
    $info.FileName = $BashPath
    $info.Arguments = (@($all | ForEach-Object { ConvertTo-BashArgument -Value $_ })) -join ' '
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $process = [System.Diagnostics.Process]::Start($info)
    $errors = $process.StandardError.ReadToEndAsync()
    $output = $process.StandardOutput.ReadToEnd()
    $process.WaitForExit()
    return [pscustomobject]@{
        ExitCode = $process.ExitCode
        Lines    = @($output -split "`r?`n" | Where-Object { $_ -ne '' })
        Errors   = @($errors.Result -split "`r?`n" | Where-Object { $_ -ne '' })
    }
}

function ConvertFrom-SealOutput {
    <# The check, fact and sealed lines of release-seal check or seal, as one object. #>
    param([AllowEmptyCollection()] [string[]] $Lines = @())
    $checks = New-Object -TypeName System.Collections.Generic.List[object]
    $since = New-Object -TypeName System.Collections.Generic.List[string]
    $facts = @{ commit = ''; pr = ''; base = '' }
    $sealed = ''
    foreach ($line in $Lines) {
        $field = $line -split "`t"
        if ($field[0] -eq 'check' -and $field.Count -ge 4) {
            $checks.Add([pscustomobject]@{ Name = $field[2]; Result = $field[1]; Reason = $field[3] })
        } elseif ($field[0] -eq 'fact' -and $field.Count -ge 3) {
            if ($field[1] -eq 'since') { $since.Add($field[2]) }
            elseif ($facts.ContainsKey($field[1])) { $facts[$field[1]] = $field[2] }
        } elseif ($field[0] -eq 'sealed' -and $field.Count -ge 3) {
            $sealed = $field[1]
        }
    }
    return [pscustomobject]@{
        Checks = $checks.ToArray()
        Commit = $facts.commit
        Pr     = $facts.pr
        Base   = $facts.base
        Since  = $since.ToArray()
        Sealed = $sealed
    }
}

function Test-SealReady {
    <# True when each check of release-seal is there, once, and passed. #>
    param([Parameter(Mandatory = $true)] $Result)
    foreach ($name in @('published', 'drafted', 'commit', 'version', 'verify', 'unsealed')) {
        $found = @($Result.Checks | Where-Object { $_.Name -eq $name })
        if ($found.Count -ne 1 -or $found[0].Result -ne 'ok') { return $false }
    }
    return $true
}

function ConvertFrom-SealVersionList {
    <# The lines of release-seal versions, as tags with their seal state. #>
    param([AllowEmptyCollection()] [string[]] $Lines = @())
    foreach ($line in $Lines) {
        $field = $line -split "`t"
        if ($field.Count -eq 2 -and $field[0] -match '^v\d+\.\d+\.\d+$') {
            [pscustomobject]@{ Tag = $field[0]; Sealed = ($field[1] -eq 'sealed') }
        }
    }
}

function Add-SealLabel {
    <# A label on the form at x, y with the width and text given. #>
    param($Form, [int] $X, [int] $Y, [int] $Width, [string] $Text)
    $label = New-Object -TypeName System.Windows.Forms.Label
    $label.Location = New-Object -TypeName System.Drawing.Point -ArgumentList $X, $Y
    $label.Size = New-Object -TypeName System.Drawing.Size -ArgumentList $Width, 20
    $label.Text = $Text
    $label.AutoEllipsis = $true
    $Form.Controls.Add($label)
    return $label
}

function Get-SealForm {
    <# The seal dialog of the repository and the versions given, not shown. #>
    param([Parameter(Mandatory = $true)] [string] $Name, [object[]] $Versions = @())
    Add-Type -AssemblyName System.Windows.Forms, System.Drawing
    $form = New-Object -TypeName System.Windows.Forms.Form
    $form.Text = "Seal $Name release"
    $form.StartPosition = 'CenterScreen'
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.ClientSize = New-Object -TypeName System.Drawing.Size -ArgumentList 640, 540
    $form.Font = New-Object -TypeName System.Drawing.Font -ArgumentList 'Segoe UI', 9
    $mono = New-Object -TypeName System.Drawing.Font -ArgumentList 'Consolas', 9

    [void] (Add-SealLabel -Form $form -X 12 -Y 15 -Width 140 -Text 'Repository')
    [void] (Add-SealLabel -Form $form -X 160 -Y 15 -Width 468 -Text $Name)
    [void] (Add-SealLabel -Form $form -X 12 -Y 45 -Width 140 -Text 'Version')
    $version = New-Object -TypeName System.Windows.Forms.ComboBox
    $version.DropDownStyle = 'DropDownList'
    $version.Location = New-Object -TypeName System.Drawing.Point -ArgumentList 160, 42
    $version.Size = New-Object -TypeName System.Drawing.Size -ArgumentList 200, 24
    foreach ($entry in $Versions) {
        $state = if ($entry.Sealed) { 'sealed' } else { 'not sealed' }
        [void] $version.Items.Add(('{0} ({1})' -f $entry.Tag, $state))
    }
    $form.Controls.Add($version)
    [void] (Add-SealLabel -Form $form -X 12 -Y 75 -Width 140 -Text 'Commit')
    $commit = Add-SealLabel -Form $form -X 160 -Y 75 -Width 468 -Text ''
    $commit.Font = $mono
    [void] (Add-SealLabel -Form $form -X 12 -Y 100 -Width 140 -Text 'Release pull request')
    $pr = Add-SealLabel -Form $form -X 160 -Y 100 -Width 468 -Text ''

    $checks = New-Object -TypeName System.Windows.Forms.ListView
    $checks.View = 'Details'
    $checks.FullRowSelect = $true
    $checks.HeaderStyle = 'Nonclickable'
    $checks.Location = New-Object -TypeName System.Drawing.Point -ArgumentList 12, 128
    $checks.Size = New-Object -TypeName System.Drawing.Size -ArgumentList 616, 160
    [void] $checks.Columns.Add('Check', 90)
    [void] $checks.Columns.Add('Result', 60)
    [void] $checks.Columns.Add('Reason', 440)
    $form.Controls.Add($checks)

    $base = Add-SealLabel -Form $form -X 12 -Y 298 -Width 616 -Text 'Commits since the last seal'
    $since = New-Object -TypeName System.Windows.Forms.TextBox
    $since.Multiline = $true
    $since.ReadOnly = $true
    $since.ScrollBars = 'Vertical'
    $since.WordWrap = $false
    $since.Font = $mono
    $since.Location = New-Object -TypeName System.Drawing.Point -ArgumentList 12, 320
    $since.Size = New-Object -TypeName System.Drawing.Size -ArgumentList 616, 160
    $form.Controls.Add($since)

    $status = Add-SealLabel -Form $form -X 12 -Y 505 -Width 410 -Text ''
    $seal = New-Object -TypeName System.Windows.Forms.Button
    $seal.Text = 'Seal'
    $seal.Enabled = $false
    $seal.Location = New-Object -TypeName System.Drawing.Point -ArgumentList 440, 500
    $seal.Size = New-Object -TypeName System.Drawing.Size -ArgumentList 88, 28
    $form.Controls.Add($seal)
    $cancel = New-Object -TypeName System.Windows.Forms.Button
    $cancel.Text = 'Cancel'
    $cancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $cancel.Location = New-Object -TypeName System.Drawing.Point -ArgumentList 540, 500
    $cancel.Size = New-Object -TypeName System.Drawing.Size -ArgumentList 88, 28
    $form.Controls.Add($cancel)
    $form.CancelButton = $cancel

    $form.Tag = @{
        Version = $version; Commit = $commit; Pr = $pr; Checks = $checks; Base = $base
        Since = $since; Status = $status; Seal = $seal; Cancel = $cancel
    }
    return $form
}

function Show-SealResult {
    <# Fills the seal dialog with one run of release-seal check; Seal is enabled only when ready. #>
    param([Parameter(Mandatory = $true)] $Form, [Parameter(Mandatory = $true)] $Result)
    $control = $Form.Tag
    $control.Commit.Text = $Result.Commit
    $control.Pr.Text = $Result.Pr
    $control.Base.Text = if ($Result.Base -and $Result.Base -ne 'none') {
        "Commits since $($Result.Base), newest first"
    } else {
        'Commits of this release, newest first (no earlier release)'
    }
    $control.Since.Lines = [string[]] $Result.Since
    $control.Checks.Items.Clear()
    foreach ($check in $Result.Checks) {
        $item = New-Object -TypeName System.Windows.Forms.ListViewItem -ArgumentList $check.Name
        [void] $item.SubItems.Add($check.Result)
        [void] $item.SubItems.Add($check.Reason)
        if ($check.Result -ne 'ok') { $item.ForeColor = [System.Drawing.Color]::Firebrick }
        [void] $control.Checks.Items.Add($item)
    }
    $control.Seal.Enabled = (Test-SealReady -Result $Result)
}

function Get-PassphraseForm {
    <# The passphrase dialog, not shown: a masked box, OK and Cancel. #>
    Add-Type -AssemblyName System.Windows.Forms, System.Drawing
    $form = New-Object -TypeName System.Windows.Forms.Form
    $form.Text = 'Seal key passphrase'
    $form.StartPosition = 'CenterScreen'
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.TopMost = $true
    $form.ClientSize = New-Object -TypeName System.Drawing.Size -ArgumentList 380, 120
    $form.Font = New-Object -TypeName System.Drawing.Font -ArgumentList 'Segoe UI', 9
    [void] (Add-SealLabel -Form $form -X 12 -Y 12 -Width 356 -Text 'Type the passphrase of the offline seal key.')
    $box = New-Object -TypeName System.Windows.Forms.TextBox
    $box.UseSystemPasswordChar = $true
    $box.Location = New-Object -TypeName System.Drawing.Point -ArgumentList 12, 40
    $box.Size = New-Object -TypeName System.Drawing.Size -ArgumentList 356, 24
    $form.Controls.Add($box)
    $ok = New-Object -TypeName System.Windows.Forms.Button
    $ok.Text = 'OK'
    $ok.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $ok.Location = New-Object -TypeName System.Drawing.Point -ArgumentList 186, 80
    $ok.Size = New-Object -TypeName System.Drawing.Size -ArgumentList 88, 28
    $form.Controls.Add($ok)
    $cancel = New-Object -TypeName System.Windows.Forms.Button
    $cancel.Text = 'Cancel'
    $cancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $cancel.Location = New-Object -TypeName System.Drawing.Point -ArgumentList 280, 80
    $cancel.Size = New-Object -TypeName System.Drawing.Size -ArgumentList 88, 28
    $form.Controls.Add($cancel)
    $form.AcceptButton = $ok
    $form.CancelButton = $cancel
    $form.Tag = @{ Box = $box; Ok = $ok; Cancel = $cancel }
    $form.add_Shown({ $this.Activate(); $this.Tag.Box.Focus() })
    return $form
}

function Invoke-Askpass {
    <# The passphrase dialog for ssh-keygen: the passphrase on stdout, or exit 1 on Cancel. #>
    $form = Get-PassphraseForm
    try {
        if ($form.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return 1 }
        [Console]::OutputEncoding = New-Object -TypeName System.Text.UTF8Encoding -ArgumentList $false
        [Console]::Out.Write($form.Tag.Box.Text + "`n")
        [Console]::Out.Flush()
        return 0
    } finally {
        $form.Tag.Box.Clear()
        $form.Dispose()
    }
}

function Show-SealError {
    <# A message box with the error given. #>
    param([Parameter(Mandatory = $true)] [string] $Text)
    Add-Type -AssemblyName System.Windows.Forms
    [void] [System.Windows.Forms.MessageBox]::Show($Text, 'Seal', 'OK', 'Error')
}

function Invoke-ReleaseCheck {
    <# Runs release-seal check for the version picked in the dialog and shows the result. It
       never throws: an error shows in the status line, with Seal off. #>
    param(
        [Parameter(Mandatory = $true)] $Form,
        [Parameter(Mandatory = $true)] [string] $Shell,
        [Parameter(Mandatory = $true)] [string] $Slug,
        [Parameter(Mandatory = $true)] [object[]] $Versions,
        [string] $Script = (Join-Path -Path $PSScriptRoot -ChildPath 'release-seal')
    )
    $control = $Form.Tag
    $control.Seal.Enabled = $false
    try {
        $tag = $Versions[$control.Version.SelectedIndex].Tag
        $control.Status.Text = "Checking $tag ..."
        $Form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
        [System.Windows.Forms.Application]::DoEvents()
        $result = Invoke-SealCore -BashPath $Shell -Script $Script `
            -Arguments @('check', '--repo', $Slug, '--version', $tag.Substring(1))
        Show-SealResult -Form $Form -Result (ConvertFrom-SealOutput -Lines $result.Lines)
        $control.Status.Text = if ($result.ExitCode -eq 0) {
            'Every check passed.'
        } elseif ($result.ExitCode -eq 1) {
            'A check failed: this release cannot be sealed.'
        } else {
            'The checks cannot run: ' + ($result.Errors | Select-Object -Last 1)
        }
    } catch {
        $control.Seal.Enabled = $false
        $control.Status.Text = 'The checks cannot run: ' + $_.Exception.Message
    } finally {
        $Form.Cursor = [System.Windows.Forms.Cursors]::Default
    }
}

function Invoke-ReleaseSeal {
    <# Runs release-seal seal for the version picked in the dialog: the name of the seal pushed,
       or an empty string. It never throws: an error shows in the status line. #>
    param(
        [Parameter(Mandatory = $true)] $Form,
        [Parameter(Mandatory = $true)] [string] $Shell,
        [Parameter(Mandatory = $true)] [string] $Slug,
        [Parameter(Mandatory = $true)] [object[]] $Versions,
        [string] $Script = (Join-Path -Path $PSScriptRoot -ChildPath 'release-seal')
    )
    $control = $Form.Tag
    $control.Seal.Enabled = $false
    $control.Cancel.Enabled = $false
    $control.Version.Enabled = $false
    try {
        $tag = $Versions[$control.Version.SelectedIndex].Tag
        $control.Status.Text = 'Sealing: type the passphrase in the next dialog.'
        $Form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
        [System.Windows.Forms.Application]::DoEvents()
        $result = Invoke-SealCore -BashPath $Shell -Script $Script `
            -Arguments @('seal', '--repo', $Slug, '--version', $tag.Substring(1))
        $parsed = ConvertFrom-SealOutput -Lines $result.Lines
        if ($result.ExitCode -eq 0 -and $parsed.Sealed) {
            $control.Status.Text = "$($parsed.Sealed) is sealed and pushed."
            return $parsed.Sealed
        }
        if (@($parsed.Checks).Count -gt 0) { Show-SealResult -Form $Form -Result $parsed }
        $control.Seal.Enabled = $false
        $control.Status.Text = 'Not sealed: ' + ($result.Errors | Select-Object -Last 1)
    } catch {
        $control.Seal.Enabled = $false
        $control.Status.Text = 'Not sealed: ' + $_.Exception.Message
    } finally {
        $Form.Cursor = [System.Windows.Forms.Cursors]::Default
        $control.Cancel.Enabled = $true
        $control.Version.Enabled = $true
    }
    return ''
}

function Invoke-SealDialog {
    <# The seal dialog of the repository given: 0 sealed, 1 not sealed, 2 cannot run. #>
    param([Parameter(Mandatory = $true)] [string] $Slug, [string] $BashPath)
    Add-Type -AssemblyName System.Windows.Forms, System.Drawing
    [System.Windows.Forms.Application]::EnableVisualStyles()
    try {
        $shell = Get-SealBash -Path $BashPath
    } catch {
        Show-SealError -Text $_.Exception.Message
        return 2
    }
    $run = Invoke-SealCore -BashPath $shell -Arguments @('versions', '--repo', $Slug)
    if ($run.ExitCode -ne 0) {
        Show-SealError -Text ("release-seal cannot list the releases:`n" + ($run.Errors -join "`n"))
        return 2
    }
    $versions = @(ConvertFrom-SealVersionList -Lines $run.Lines)
    if ($versions.Count -eq 0) {
        Show-SealError -Text 'There is no published release to seal.'
        return 1
    }
    $form = Get-SealForm -Name $Slug -Versions $versions
    $control = $form.Tag
    $state = @{ Sealed = $false }
    $control.Version.add_SelectedIndexChanged({
        Invoke-ReleaseCheck -Form $form -Shell $shell -Slug $Slug -Versions $versions
    })
    $control.Seal.add_Click({
        $sealed = Invoke-ReleaseSeal -Form $form -Shell $shell -Slug $Slug -Versions $versions
        if ($sealed) {
            $state.Sealed = $true
            [void] [System.Windows.Forms.MessageBox]::Show("$sealed is sealed and pushed.", 'Seal', 'OK', 'Information')
            $form.Close()
        }
    })
    # The newest version without a seal comes first; else the newest.
    $state.First = 0
    for ($i = 0; $i -lt $versions.Count; $i++) {
        if (-not $versions[$i].Sealed) { $state.First = $i; break }
    }
    $form.add_Shown({ $control.Version.SelectedIndex = $state.First })
    try {
        [void] $form.ShowDialog()
    } finally {
        $form.Dispose()
    }
    if ($state.Sealed) { return 0 }
    return 1
}

if ($MyInvocation.InvocationName -ne '.') {
    if ($Askpass) { exit (Invoke-Askpass) }
    exit (Invoke-SealDialog -Slug $Repo -BashPath $Bash)
}
