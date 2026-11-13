#Requires -Version 7.2
<#
.SYNOPSIS
    Backs up every configuration file the Windows wizard changes, and records every file and registry
    value it changed.

.DESCRIPTION
    Owner decision 40. Before its first change in a run, a configuration file that already exists is
    copied to %LOCALAPPDATA%\installation-helper\backup\<run timestamp>\<its full path without the
    drive colon>, so C:\Users\me\file.ini goes to ...\backup\2026-11-13T17-40-37Z\C\Users\me\file.ini. A
    file the run creates needs no copy. The registry has no file to copy, so a changed value is
    recorded with the value it held before. setup.ps1 prints both lists at the end of the run, through
    Write-ConfigChangeSummary.

    Every write of a configuration file goes through Invoke-WindowsConfigFileWrite, and every write of
    a registry value through Invoke-WindowsRegistryChange, which Set-WindowsUserEnvironmentVariable
    uses for the user environment. The Pester suite fails a write in setup.ps1 or setup/windows/ that
    goes through neither, docs/regression_ledger.md 10.311.

    The user environment, HKCU\Environment, is read and written here as the registry holds it: a
    %VARIABLE% stays unexpanded and a value keeps its kind, so a PATH written as ExpandString is never
    flattened into fixed paths, docs/regression_ledger.md 10.323.

    Nothing here writes to the console: the caller renders, which keeps the functions testable.
#>

Set-StrictMode -Version Latest

# The record of the current run, started by Start-WindowsConfigChangeRecord.
$script:ConfigChangeRecord = $null

function Start-WindowsConfigChangeRecord {
    <#
    .SYNOPSIS
        Starts the record of what this run changes, and names its backup folder after the run's start time.
    .DESCRIPTION
        Creates no folder. The backup folder is made by the first copy, so a run that changes no
        existing file leaves nothing behind. The name is the start time in UTC, Gregorian whatever
        the culture, in the shape the Linux backup uses, 2026-11-13T17-40-37Z, because local time
        repeats an hour when the clocks go back, docs/regression_ledger.md 10.330 and 10.337.
    .NOTES
        Throws when a folder of that name exists already, because this run's copies would mix with
        another run's.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [string] $BackupRoot,
        [datetime] $Started = (Get-Date)
    )

    if (-not $BackupRoot) {
        if (-not $env:LOCALAPPDATA) {
            throw 'LOCALAPPDATA is not set, so there is no folder to back configuration files up to'
        }
        $BackupRoot = Join-Path $env:LOCALAPPDATA 'installation-helper\backup'
    }

    $stamp = $Started.ToUniversalTime().ToString("yyyy-MM-dd'T'HH-mm-ss'Z'", [System.Globalization.CultureInfo]::InvariantCulture)
    $backupFolder = Join-Path $BackupRoot $stamp
    if (Test-Path -LiteralPath $backupFolder) {
        throw "$backupFolder exists already, so this run's backup would mix with another run's. Start the run again in a second."
    }

    $script:ConfigChangeRecord = [PSCustomObject]@{
        BackupFolder = $backupFolder
        Files        = [System.Collections.Generic.List[object]]::new()
        Registry     = [System.Collections.Generic.List[object]]::new()
    }
    return $script:ConfigChangeRecord
}

function Get-WindowsConfigChangeRecord {
    <#
    .SYNOPSIS
        The record of the current run, started now when nothing has started one.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    if ($null -eq $script:ConfigChangeRecord) {
        $null = Start-WindowsConfigChangeRecord
    }
    return $script:ConfigChangeRecord
}

function Get-WindowsConfigBackupPath {
    <#
    .SYNOPSIS
        Where the copy of a file goes: its full path, without the drive colon, under the backup folder.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $BackupFolder,
        [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $Path
    )

    $relative = ($Path -replace '^([A-Za-z]):', '$1') -replace '^[\\/]+', ''
    return Join-Path $BackupFolder $relative
}

function Invoke-WindowsConfigFileWrite {
    <#
    .SYNOPSIS
        Copies a configuration file to the run's backup folder before its first change in the run, runs
        the write, and records the file as changed or created.
    .DESCRIPTION
        The one way the wizard writes a configuration file. The path is made full once, so two
        spellings of one file are one file, docs/regression_ledger.md 10.331. A file the run already
        changed is not copied again, so the copy always holds what the file held before the run.

        Write is called with two arguments, the full path and Argument, and takes everything it needs
        from them, because it runs in this function's scope, where a variable of the caller's could
        be one of this function's instead, docs/regression_ledger.md 10.332. Returns whatever Write
        returns.
    .NOTES
        Throws, before the write runs, when the copy cannot be made, so no existing file is changed
        without its copy. An exception from the write itself is passed on, and a file it created
        before it threw is still recorded.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $Path,
        [Parameter(Mandatory)] [scriptblock] $Write,
        [object] $Argument
    )

    $fullPath = [System.IO.Path]::GetFullPath($ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path))
    $changeRecord = Get-WindowsConfigChangeRecord
    $firstChange = @($changeRecord.Files | Where-Object { $_.Path -eq $fullPath }).Count -eq 0
    $copyPath = ''
    if ($firstChange -and (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
        $copyPath = Get-WindowsConfigBackupPath -BackupFolder $changeRecord.BackupFolder -Path $fullPath
        $null = New-Item -ItemType Directory -Path (Split-Path -Parent $copyPath) -Force -ErrorAction Stop
        Copy-Item -LiteralPath $fullPath -Destination $copyPath -Force -ErrorAction Stop
    }

    try {
        & $Write $fullPath $Argument
    } finally {
        if ($firstChange -and ($copyPath -or (Test-Path -LiteralPath $fullPath))) {
            $changeRecord.Files.Add([PSCustomObject]@{
                Path   = $fullPath
                Action = $(if ($copyPath) { 'changed' } else { 'created' })
                Backup = $copyPath
            })
        }
    }
}

function ConvertTo-RecordedRegistryValue {
    <#
    .SYNOPSIS
        A value as the record keeps it: $null for a value that is not set, its text otherwise, so an
        empty value stays apart from a missing one, docs/regression_ledger.md 10.333.
    #>
    [CmdletBinding()]
    param([AllowNull()] [object] $Value)

    if ($null -eq $Value) {
        return $null
    }
    return [string] $Value
}

function Invoke-WindowsRegistryChange {
    <#
    .SYNOPSIS
        Runs a write of one registry value and records the value before and after, when the write changed it.
    .DESCRIPTION
        The one way the wizard writes a registry value. Read answers the value as it stands, or $null
        when it is not set, and is asked before and after the write. A value changed twice in a run
        keeps one entry, with the value from before the first change. Read and Write are each called
        with Argument and take everything they need from it, for the reason Invoke-WindowsConfigFileWrite
        gives. Returns whatever Write returns.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $Location,
        [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $Name,
        [Parameter(Mandatory)] [scriptblock] $Read,
        [Parameter(Mandatory)] [scriptblock] $Write,
        [object] $Argument
    )

    $changeRecord = Get-WindowsConfigChangeRecord
    $valueBefore = ConvertTo-RecordedRegistryValue -Value (& $Read $Argument)
    & $Write $Argument
    $valueAfter = ConvertTo-RecordedRegistryValue -Value (& $Read $Argument)
    if (($null -eq $valueBefore) -eq ($null -eq $valueAfter) -and "$valueAfter" -ceq "$valueBefore") { return }

    $earlier = @($changeRecord.Registry | Where-Object { $_.Location -eq $Location -and $_.Name -eq $Name })
    if ($earlier.Count -gt 0) {
        $earlier[0].After = $valueAfter
        return
    }
    $changeRecord.Registry.Add([PSCustomObject]@{ Location = $Location; Name = $Name; Before = $valueBefore; After = $valueAfter })
}

function Open-WindowsUserEnvironmentKey {
    <#
    .SYNOPSIS
        Opens HKCU\Environment, the user's environment variables, for the caller to dispose of.
    .DESCRIPTION
        The one place the key is opened, so the Pester suite can hand the reader and the writer a fake.
        Answers $null when the key does not exist and is not opened for writing.
    #>
    [CmdletBinding()]
    param([switch] $Writable)

    if ($Writable) {
        return [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey('Environment', $true)
    }
    return [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment')
}

function Get-WindowsUserEnvironmentValue {
    <#
    .SYNOPSIS
        One user environment variable as HKCU\Environment holds it, %VARIABLE% unexpanded, with its value kind.
    .DESCRIPTION
        Value and Kind are both $null when the variable is not set. Kind is the name of the
        RegistryValueKind, String or ExpandString for an environment variable.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param([Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $Name)

    $notSet = [PSCustomObject]@{ Value = $null; Kind = $null }
    $key = Open-WindowsUserEnvironmentKey
    if ($null -eq $key) {
        return $notSet
    }
    try {
        $value = $key.GetValue($Name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        if ($null -eq $value) {
            return $notSet
        }
        return [PSCustomObject]@{ Value = [string] $value; Kind = [string] $key.GetValueKind($Name) }
    } finally {
        $key.Dispose()
    }
}

function Send-WindowsEnvironmentChange {
    <#
    .SYNOPSIS
        Tells running programs that the user environment changed, the WM_SETTINGCHANGE broadcast Explorer listens for.
    .DESCRIPTION
        Without it a program started from Explorer after the run still gets the environment Explorer
        read at sign-in. A window that does not answer within five seconds is skipped. Returns whether
        the broadcast went out.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    if (-not ('InstallationHelper.EnvironmentBroadcast' -as [type])) {
        Add-Type -Namespace 'InstallationHelper' -Name 'EnvironmentBroadcast' -MemberDefinition @'
[DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint msg, UIntPtr wParam, string lParam, uint flags, uint timeout, out UIntPtr result);
'@
    }

    $HWND_BROADCAST   = [IntPtr] 0xffff
    $WM_SETTINGCHANGE = 0x001A
    $SMTO_ABORTIFHUNG = 0x0002
    $answer = [UIntPtr]::Zero
    $sent = [InstallationHelper.EnvironmentBroadcast]::SendMessageTimeout(
        $HWND_BROADCAST, $WM_SETTINGCHANGE, [UIntPtr]::Zero, 'Environment', $SMTO_ABORTIFHUNG, 5000, [ref] $answer)
    return $sent -ne [IntPtr]::Zero
}

function Set-WindowsUserEnvironmentVariable {
    <#
    .SYNOPSIS
        Sets one environment variable for the user, HKCU\Environment, records the change and tells running programs.
    .DESCRIPTION
        The value is written as given, %VARIABLE% included, as ExpandString when the variable already
        was one or the new value names a %VARIABLE%, and as String otherwise. The record holds the
        values as the registry held them, unexpanded, docs/regression_ledger.md 10.323.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $Name,
        [Parameter(Mandatory)] [AllowEmptyString()] [string] $Value
    )

    Invoke-WindowsRegistryChange -Location 'HKCU\Environment' -Name $Name -Argument ([PSCustomObject]@{ Name = $Name; Value = $Value }) `
        -Read { param($Change) (Get-WindowsUserEnvironmentValue -Name $Change.Name).Value } `
        -Write {
            param($Change)
            $kindBefore = (Get-WindowsUserEnvironmentValue -Name $Change.Name).Kind
            $kind = if ($kindBefore -eq 'ExpandString' -or $Change.Value -match '%[^%;]+%') { 'ExpandString' } else { 'String' }
            $key = Open-WindowsUserEnvironmentKey -Writable
            try {
                $key.SetValue($Change.Name, $Change.Value, [Microsoft.Win32.RegistryValueKind] $kind)
            } finally {
                $key.Dispose()
            }
            $null = Send-WindowsEnvironmentChange
        }
}

function Add-WindowsUserPathEntry {
    <#
    .SYNOPSIS
        Adds to the user PATH the directories it does not hold yet, keeping every %VARIABLE% in it.
    .DESCRIPTION
        A directory counts as present when it names the same place as an entry once both are expanded,
        so %USERPROFILE%\bin covers C:\Users\me\bin. The missing ones are appended to the text as the
        registry holds it, through Set-WindowsUserEnvironmentVariable, which keeps the value kind,
        docs/regression_ledger.md 10.323. Returns Missing, the directories that were not there, and
        Written, whether PATH was written, which it is not under -WhatIf or when nothing is missing.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([PSCustomObject])]
    param([Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string[]] $Directory)

    $comparable = { param($Entry) [Environment]::ExpandEnvironmentVariables($Entry).Trim().TrimEnd('\') }
    $held = "$((Get-WindowsUserEnvironmentValue -Name 'PATH').Value)"
    $present = [System.Collections.Generic.List[string]]::new()
    foreach ($entry in @($held -split ';' | Where-Object { $_.Trim() })) {
        $present.Add((& $comparable $entry))
    }

    $missing = [System.Collections.Generic.List[string]]::new()
    foreach ($candidate in $Directory) {
        $wanted = & $comparable $candidate
        if ($wanted -notin $present) {
            $missing.Add($candidate)
            $present.Add($wanted)
        }
    }

    $written = $false
    if ($missing.Count -gt 0 -and $PSCmdlet.ShouldProcess(($missing -join '; '), 'add to the user PATH')) {
        $kept = $held.TrimEnd(';')
        $text = if ($kept) { "$kept;$($missing -join ';')" } else { $missing -join ';' }
        Set-WindowsUserEnvironmentVariable -Name 'PATH' -Value $text
        $written = $true
    }
    return [PSCustomObject]@{ Missing = @($missing); Written = $written }
}
