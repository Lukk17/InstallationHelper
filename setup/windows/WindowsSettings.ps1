#Requires -Version 7.2
<#
.SYNOPSIS
    The four Windows system settings, applied natively instead of through Ansible.

.DESCRIPTION
    windows_core used to carry a task file for each of these and none of them could ever run: the
    playbook is invoked from inside WSL against localhost, so ansible_os_family reports Debian and
    every Windows-gated task was skipped. Those files were deleted on 2026-08-20, so nothing under
    setup/ansible/ describes this behaviour any more and this file is the only description of it.
    docs/regression_ledger.md recorded exactly these four as the remainder after the software
    catalogue got a native path, and this file is that remainder.

      enable_hyperv          nine optional features, including Hyper-V, WSL, .NET and Sandbox
      setup_wsl              WSL itself plus the Ubuntu distribution
      set_custom_wallpaper   the desktop wallpaper named by default_wallpaper
      import_hibernate_task  a scheduled task that hibernates the machine at 2 AM

    Whether a setting is wanted is read out of group_vars through Get-WindowsGroupVarToggle in
    WindowsSoftware.ps1, so the toggles stay one source of truth and it is the same pair of files
    the playbook reads. Nothing here writes to the console: the caller renders, which keeps the
    functions testable.

    Four things deliberately differ from the dead Ansible, and each difference is a defect that
    would otherwise have shipped the moment the Windows path became reachable:

      1. wsl_setup.yaml ran `wsl --install -d Ubuntu`, which registers the distribution and then
         launches it, and a first launch stops at a prompt for a username and password. In a wizard
         nobody is watching that is an unbounded hang. `--no-launch` registers it and stops.
      2. wsl_setup.yaml imported the scheduled task from `{{ playbook_dir }}\..\tasks\Hibernate@2AM.xml`
         and there is no setup/tasks/ directory anywhere in this repository, which is why the toggle
         is off with that reason beside it. The task is built here instead of imported, so there is
         nothing to lose track of.
      3. wallpaper_windows.yaml wrote the registry value and then called
         `RUNDLL32 user32.dll,UpdatePerUserSystemParameters`, which is undocumented and resets other
         per-user parameters as a side effect. SPI_SETDESKWALLPAPER is the documented call for this
         one setting and it writes the value itself.
      4. windows_features.yaml never mentioned that eight of these nine features need a reboot before
         they do anything. A restart that is owed is carried out to the caller here and said out
         loud, because a feature reported as enabled and not yet active is the same lie as a package
         reported as installed and absent.

    Depends on Get-WindowsGroupVarToggle from WindowsSoftware.ps1, which setup.ps1 dot-sources
    first.
#>

Set-StrictMode -Version Latest

# The toggles this file is responsible for. Declared as data rather than left implicit in the
# dispatch below, for the same reason WindowsCustomInstalls.ps1 declares its own list: a checker can
# then ask what is covered here instead of inferring it from the code.
$script:SettingKeys = @('enable_hyperv', 'setup_wsl', 'set_custom_wallpaper', 'import_hibernate_task')

# The nine features windows_features.yaml loops over, in its order. VirtualMachinePlatform and
# Microsoft-Windows-Subsystem-Linux are what WSL 2 needs, so enable_hyperv is a prerequisite of
# setup_wsl on a machine that has neither.
$script:OptionalFeatureNames = @(
    'VirtualMachinePlatform'
    'Microsoft-Windows-Subsystem-Linux'
    'HypervisorPlatform'
    'NetFx3'
    'NetFx4-AdvSrvs'
    'NetFx4Extended-ASPNET45'
    'Containers-DisposableClientVM'
    'Microsoft-Hyper-V'
    'ServicesForNFS-ClientOnly'
)

# default_wallpaper is a filename rather than a boolean, which is why the toggle reader cannot see
# it and why both wizards keep it off the checklist.
$script:WallpaperLinePattern = '^default_wallpaper:\s*"?(?<name>[^"#\s]+)"?\s*(#.*)?$'

# Two Win32 calls with no cmdlet equivalent. Guarded so dot-sourcing this file twice in one session
# does not fail on a duplicate type, which is what a Pester run that imports it per Describe does.
if (-not ('InstallationHelper.NativeSetting' -as [type])) {
    Add-Type -Namespace 'InstallationHelper' -Name 'NativeSetting' -MemberDefinition @'
[DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
public static extern bool SystemParametersInfoW(uint uiAction, uint uiParam, string pvParam, uint fWinIni);

[DllImport("powrprof.dll")]
public static extern bool IsPwrHibernateAllowed();
'@
}

function Get-WindowsSettingKey {
    <#
    .SYNOPSIS
        The toggles handled by this file, so a coverage check and the applier read one list.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param()
    return $script:SettingKeys
}

function Get-WindowsOptionalFeatureName {
    <#
    .SYNOPSIS
        The optional features enable_hyperv turns on, so the list has one home.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param()
    return $script:OptionalFeatureNames
}

function New-SettingResult {
    <#
    .SYNOPSIS
        One result row, in the shape the wizard's summary reads.
    .DESCRIPTION
        Key, Package, Status and Detail are the same four fields the software and custom-install
        phases return, so setup.ps1 renders all of them the same way. RebootRequired is always
        present rather than added only when true, because Set-StrictMode Latest makes reading an
        absent property an error and the caller aggregates over every row.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $Key,
        [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $Package,
        [Parameter(Mandatory)] [ValidateSet('installed', 'present', 'skipped', 'failed')] [string] $Status,
        [string] $Detail = '',
        [switch] $RebootRequired
    )

    return [PSCustomObject]@{
        Key            = $Key
        Package        = $Package
        Status         = $Status
        Detail         = $Detail
        RebootRequired = [bool]$RebootRequired
    }
}

function Enable-WindowsFeatureSet {
    <#
    .SYNOPSIS
        Enables the optional features and reports, per feature, whether a reboot is still owed.
    .DESCRIPTION
        DISM against the running image needs administrator rights even to read a feature's state,
        and setup.ps1 deliberately refuses to run elevated, so all nine are batched into one
        elevated child process. That is one consent prompt for the batch rather than one per
        feature, which is the same trade Install-ChocolateyPackageBatch makes.

        The child writes one line per feature into a file rather than to stdout, because
        Start-Process -Verb RunAs goes through ShellExecute and ShellExecute cannot redirect a
        stream. Reading that file back is what makes a per-feature answer possible at all, and a
        per-feature answer is the point: one status stamped onto nine items cannot say which of them
        the machine actually has.

        NetFx3 is the one likely to fail on a normal machine, because Windows does not carry its
        payload and needs installation media or Windows Update to fetch it. That is reported as a
        failure with the message DISM gave, not smoothed over.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string[]] $FeatureName,
        [ValidateRange(1, 120)] [int] $TimeoutMinutes = 30
    )

    $results = [System.Collections.Generic.List[object]]::new()

    if (-not $PSCmdlet.ShouldProcess(($FeatureName -join ', '), 'enable Windows optional feature')) {
        foreach ($name in $FeatureName) {
            $results.Add((New-SettingResult -Key 'enable_hyperv' -Package $name -Status 'skipped' `
                -Detail 'WhatIf, would enable it through an elevated DISM child and report whether a reboot is owed'))
        }
        return $results
    }

    $stage = Join-Path ([System.IO.Path]::GetTempPath()) ('installation-helper-features-' + [guid]::NewGuid().ToString('N'))
    $null = New-Item -ItemType Directory -Path $stage -Force
    $resultFile = Join-Path $stage 'features.txt'

    $featureLiterals = ($FeatureName | ForEach-Object { "'$_'" }) -join ', '
    $inner = @"
`$ErrorActionPreference = 'Stop'
`$lines = [System.Collections.Generic.List[string]]::new()
foreach (`$name in @($featureLiterals)) {
    try {
        `$feature = Get-WindowsOptionalFeature -Online -FeatureName `$name -ErrorAction Stop
        if (`$feature.State -eq 'Enabled') {
            `$lines.Add("present|`$name|already enabled")
            continue
        }
        `$applied = Enable-WindowsOptionalFeature -Online -FeatureName `$name -All -NoRestart -ErrorAction Stop
        if (`$applied.RestartNeeded) { `$lines.Add("reboot|`$name|enabled") }
        else { `$lines.Add("installed|`$name|enabled") }
    } catch {
        `$message = `$_.Exception.Message -replace '[
|]', ' '
        # DISM says "Feature name <x> is unknown" for a feature this Windows edition does not
        # offer. On a Server SKU that is the truth about the edition rather than a fault, and three
        # of the names in this list are client-only. On a client SKU it means the list has drifted
        # from what Windows offers and it stays a failure so somebody looks at it.
        if (`$message -match 'is unknown' -and '$installationType' -ne 'Client') {
            `$lines.Add("skipped|`$name|not offered on this Windows edition ($installationType), so there is nothing to enable")
        } else {
            `$lines.Add("failed|`$name|" + `$message)
        }
    }
}
Set-Content -LiteralPath '$resultFile' -Value `$lines -Encoding utf8
"@

    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($inner))

    # Already-administrator is the normal case in CI, and there -Verb RunAs fails outright because
    # it needs an interactive desktop to prompt on. Same check, same reason, as the Chocolatey batch.
    $identity   = [Security.Principal.WindowsIdentity]::GetCurrent()
    $isElevated = ([Security.Principal.WindowsPrincipal]$identity).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)

    try {
        try {
            $startArgs = @{
                FilePath     = 'pwsh.exe'
                ArgumentList = @('-NoProfile', '-NonInteractive', '-EncodedCommand', $encoded)
                PassThru     = $true
                ErrorAction  = 'Stop'
            }
            if ($isElevated) {
                Write-Verbose 'Already elevated, running DISM in this process'
                $startArgs['NoNewWindow'] = $true
            } else {
                $startArgs['Verb'] = 'RunAs'
            }
            $proc = Start-Process @startArgs

            # A timeout rather than -Wait, for the reason the Chocolatey batch documents: -Wait offers
            # no bound at all, and an unanswered consent dialog would otherwise hold the wizard forever.
            if (-not $proc.WaitForExit($TimeoutMinutes * 60 * 1000)) {
                try { $proc.Kill($true) } catch { Write-Verbose "could not kill $($proc.Id): $($_.Exception.Message)" }
                foreach ($name in $FeatureName) {
                    $results.Add((New-SettingResult -Key 'enable_hyperv' -Package $name -Status 'failed' `
                        -Detail "the elevated feature child was still running after $TimeoutMinutes minutes and was killed, so this feature's state is unknown. Run 'Enable-WindowsOptionalFeature -Online -FeatureName $name -All' from an elevated shell to see it."))
                }
                return $results
            }
        } catch {
            # A refused consent prompt lands here, and is a user decision rather than a fault.
            foreach ($name in $FeatureName) {
                $results.Add((New-SettingResult -Key 'enable_hyperv' -Package $name -Status 'failed' `
                    -Detail "could not run the elevated feature child: $($_.Exception.Message)"))
            }
            return $results
        }

        if (-not (Test-Path -LiteralPath $resultFile)) {
            foreach ($name in $FeatureName) {
                $results.Add((New-SettingResult -Key 'enable_hyperv' -Package $name -Status 'failed' `
                    -Detail 'the elevated child exited without writing a result, so no feature can be reported as enabled'))
            }
            return $results
        }

        $reported = @{}
        foreach ($line in (Get-Content -LiteralPath $resultFile)) {
            if ($line -notmatch '^(?<state>present|installed|reboot|failed)\|(?<name>[^|]+)\|(?<detail>.*)$') { continue }
            $reported[$Matches['name']] = [PSCustomObject]@{ State = $Matches['state']; Detail = $Matches['detail'] }
        }

        foreach ($name in $FeatureName) {
            if (-not $reported.ContainsKey($name)) {
                $results.Add((New-SettingResult -Key 'enable_hyperv' -Package $name -Status 'failed' `
                    -Detail 'the elevated child reported nothing for this feature, so its state is unknown'))
                continue
            }
            $entry = $reported[$name]
            switch ($entry.State) {
                'present'   { $results.Add((New-SettingResult -Key 'enable_hyperv' -Package $name -Status 'present' -Detail $entry.Detail)) }
                'installed' { $results.Add((New-SettingResult -Key 'enable_hyperv' -Package $name -Status 'installed' -Detail $entry.Detail)) }
                'reboot'    { $results.Add((New-SettingResult -Key 'enable_hyperv' -Package $name -Status 'installed' -RebootRequired `
                                  -Detail 'enabled, and it does nothing until the machine is rebooted')) }
                'failed'    { $results.Add((New-SettingResult -Key 'enable_hyperv' -Package $name -Status 'failed' -Detail $entry.Detail)) }
                'skipped'   { $results.Add((New-SettingResult -Key 'enable_hyperv' -Package $name -Status 'skipped' -Detail $entry.Detail)) }
                # A state this switch does not know is a failure rather than nothing. Without this
                # default an unhandled state produced no result at all, which reads to the caller as a
                # feature nobody asked about, and the skipped branch above is exactly the state that
                # would have hit it.
                default     { $results.Add((New-SettingResult -Key 'enable_hyperv' -Package $name -Status 'failed' `
                                  -Detail "the elevated child reported a state this wizard does not understand, '$($entry.State)', so this feature is in an unknown state")) }
            }
        }
        return $results
    } finally {
        Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Get-WslDistributionName {
    <#
    .SYNOPSIS
        The WSL distributions registered on this machine, or an empty list when WSL is absent.
    .DESCRIPTION
        WSL_UTF8 is set for the call because wsl.exe writes UTF-16 by default, and read as anything
        else that arrives as "U b u n t u". The variable is restored afterwards so nothing else in
        the run sees a changed environment.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param()

    if (-not (Get-Command wsl -CommandType Application -ErrorAction SilentlyContinue)) { return @() }

    $previousUtf8   = $env:WSL_UTF8
    $previousNative = $PSNativeCommandUseErrorActionPreference
    try {
        # WSL exits non-zero when nothing is registered, which is an answer rather than a fault.
        $PSNativeCommandUseErrorActionPreference = $false
        $env:WSL_UTF8 = '1'
        $listed = & wsl --list --quiet 2>&1
    } finally {
        $env:WSL_UTF8 = $previousUtf8
        $PSNativeCommandUseErrorActionPreference = $previousNative
    }

    return @($listed | ForEach-Object { "$_".Trim() } | Where-Object { $_ })
}

function Install-WslDistribution {
    <#
    .SYNOPSIS
        Registers the WSL distribution, without launching it.
    .DESCRIPTION
        --no-launch is the whole reason this is not a straight port of wsl_setup.yaml. Without it
        the distribution's first run stops at a prompt for a username and password, and this runs
        inside a wizard nobody is watching.

        `wsl --update` is not called. It updates the WSL kernel package, needs elevation of its
        own, and has nothing to do with registering a distribution, which is what the toggle asks
        for.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [ValidateNotNullOrEmpty()] [string] $Distribution = 'Ubuntu',
        [ValidateRange(1, 120)] [int] $TimeoutMinutes = 20
    )

    $results = [System.Collections.Generic.List[object]]::new()

    if (-not (Get-Command wsl -CommandType Application -ErrorAction SilentlyContinue)) {
        $results.Add((New-SettingResult -Key 'setup_wsl' -Package $Distribution -Status 'failed' `
            -Detail 'wsl.exe is not on this machine, so no distribution can be registered. Enable the VirtualMachinePlatform and Microsoft-Windows-Subsystem-Linux features first, which enable_hyperv does, then reboot and rerun.'))
        return $results
    }

    if ((Get-WslDistributionName) -contains $Distribution) {
        $results.Add((New-SettingResult -Key 'setup_wsl' -Package $Distribution -Status 'present' -Detail 'already registered'))
        return $results
    }

    if (-not $PSCmdlet.ShouldProcess($Distribution, 'wsl --install -d')) {
        $results.Add((New-SettingResult -Key 'setup_wsl' -Package $Distribution -Status 'skipped' `
            -Detail "WhatIf, would run wsl --install -d $Distribution --no-launch and report whether a reboot is owed"))
        return $results
    }

    $stdout = New-TemporaryFile
    $stderr = New-TemporaryFile
    try {
        $proc = Start-Process -FilePath 'wsl.exe' -ArgumentList @('--install', '-d', $Distribution, '--no-launch') `
            -NoNewWindow -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
        if (-not $proc.WaitForExit($TimeoutMinutes * 60 * 1000)) {
            try { $proc.Kill($true) } catch { Write-Verbose "could not kill $($proc.Id): $($_.Exception.Message)" }
            $results.Add((New-SettingResult -Key 'setup_wsl' -Package $Distribution -Status 'failed' `
                -Detail "wsl --install was still running after $TimeoutMinutes minutes and was killed, so the distribution is NOT registered. Run 'wsl --install -d $Distribution --no-launch' by hand to see what it was waiting for."))
            return $results
        }

        # wsl.exe writes UTF-16 to a redirected handle as well, so the nulls are stripped rather
        # than the text being decoded twice.
        $tail = @(Get-Content -LiteralPath $stderr -ErrorAction SilentlyContinue
                  Get-Content -LiteralPath $stdout -ErrorAction SilentlyContinue) |
                ForEach-Object { ("$_" -replace "`0", '').Trim() } |
                Where-Object { $_ } | Select-Object -Last 2

        if ($proc.ExitCode -ne 0) {
            $results.Add((New-SettingResult -Key 'setup_wsl' -Package $Distribution -Status 'failed' `
                -Detail "wsl --install exited $($proc.ExitCode). $($tail -join ' ') Registering a distribution on a machine that has never had WSL also needs the optional features and a reboot, and it may need an elevated shell."))
            return $results
        }

        # Registered rather than usable: WSL asks for a reboot whenever it had to turn its own
        # platform features on, and the distribution's first launch is what creates the user
        # account. Saying "installed" without that is the lie this file exists to stop telling.
        $results.Add((New-SettingResult -Key 'setup_wsl' -Package $Distribution -Status 'installed' -RebootRequired `
            -Detail "registered without launching it. Reboot, then run 'wsl -d $Distribution' once to create the Linux user account."))
        return $results
    } finally {
        Remove-Item -LiteralPath $stdout, $stderr -Force -ErrorAction SilentlyContinue
    }
}

function Get-DefaultWallpaperName {
    <#
    .SYNOPSIS
        The wallpaper filename group_vars/all.yaml names in default_wallpaper.
    .DESCRIPTION
        Throws rather than returning nothing when the key is absent, because a wallpaper phase that
        quietly sets no wallpaper is indistinguishable from one that worked.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $AllVarsPath
    )

    if (-not (Test-Path -LiteralPath $AllVarsPath)) {
        throw "Toggle file not found: $AllVarsPath"
    }
    foreach ($line in (Get-Content -LiteralPath $AllVarsPath)) {
        if ($line -match $script:WallpaperLinePattern) { return $Matches['name'] }
    }
    throw "group_vars/all.yaml names no default_wallpaper, so there is no wallpaper to set"
}

function Set-WindowsWallpaper {
    <#
    .SYNOPSIS
        Copies the wallpaper next to the other public pictures and makes it the desktop background.
    .DESCRIPTION
        The copy is what wallpaper_windows.yaml did and it is worth keeping: pointing the registry
        at a file inside a checkout means the desktop breaks the day the checkout moves.

        SPI_SETDESKWALLPAPER with SPIF_UPDATEINIFILE and SPIF_SENDWININICHANGE is the documented
        way to apply it, and it writes the per-user value itself. The registry write is kept as well
        so the setting survives even when the live repaint is refused, and a refused repaint is
        reported rather than assumed harmless.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $SourcePath,
        [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $DestinationDirectory
    )

    $name = Split-Path -Leaf $SourcePath

    if (-not (Test-Path -LiteralPath $SourcePath -PathType Leaf)) {
        return New-SettingResult -Key 'set_custom_wallpaper' -Package $name -Status 'failed' `
            -Detail "no such file: $SourcePath. default_wallpaper must name a file that exists in setup/wallpapers/."
    }

    $destination = Join-Path $DestinationDirectory $name

    if (-not $PSCmdlet.ShouldProcess($destination, 'set desktop wallpaper')) {
        return New-SettingResult -Key 'set_custom_wallpaper' -Package $name -Status 'skipped' `
            -Detail "WhatIf, would copy $SourcePath to $destination and make it the desktop background"
    }

    try {
        $null = New-Item -ItemType Directory -Path $DestinationDirectory -Force
        Copy-Item -LiteralPath $SourcePath -Destination $destination -Force
        Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name 'Wallpaper' -Value $destination
    } catch {
        return New-SettingResult -Key 'set_custom_wallpaper' -Package $name -Status 'failed' `
            -Detail "could not put the wallpaper in place: $($_.Exception.Message)"
    }

    $SPI_SETDESKWALLPAPER = 0x0014
    $SPIF_UPDATEINIFILE   = 0x01
    $SPIF_SENDWININICHANGE = 0x02
    $applied = [InstallationHelper.NativeSetting]::SystemParametersInfoW(
        $SPI_SETDESKWALLPAPER, 0, $destination, ($SPIF_UPDATEINIFILE -bor $SPIF_SENDWININICHANGE))

    if (-not $applied) {
        $code = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        return New-SettingResult -Key 'set_custom_wallpaper' -Package $name -Status 'failed' `
            -Detail "the file is in place and the registry value points at it, so it applies at the next sign-in, but SystemParametersInfo refused to repaint the desktop now (Win32 error $code)"
    }

    return New-SettingResult -Key 'set_custom_wallpaper' -Package $name -Status 'installed' -Detail $destination
}

function Register-HibernateTask {
    <#
    .SYNOPSIS
        Registers a daily scheduled task that hibernates the machine, and says whether it can work.
    .DESCRIPTION
        wsl_setup.yaml imported this from an XML file that does not exist in this repository, which
        is why import_hibernate_task is off with that reason written beside it. It is built here
        from its four parts instead, so there is no missing artefact to lose track of.

        It registers under the account running the wizard, with no elevation, which is the only
        thing setup.ps1 can do without demanding an elevated wizard. The consequence is stated in
        the result: the task runs when that user is logged on.

        Whether hibernation is available at all is asked separately, through
        IsPwrHibernateAllowed, and reported as its own failure when it is not. A task that fires
        every night and does nothing is the failure mode ledger rule 5 is about, and parsing
        `powercfg /availablesleepstates` would have made that answer depend on the display language.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [ValidateNotNullOrEmpty()] [string] $TaskName = 'Hibernate@2AM',
        [ValidateNotNullOrEmpty()] [string] $At = '02:00'
    )

    $results = [System.Collections.Generic.List[object]]::new()

    $existing = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($existing) {
        $results.Add((New-SettingResult -Key 'import_hibernate_task' -Package $TaskName -Status 'present' `
            -Detail "already registered under $($existing.TaskPath)"))
    } elseif (-not $PSCmdlet.ShouldProcess($TaskName, 'register scheduled task')) {
        $results.Add((New-SettingResult -Key 'import_hibernate_task' -Package $TaskName -Status 'skipped' `
            -Detail "WhatIf, would register a daily $At task running 'shutdown.exe /h' as $env:USERNAME"))
    } else {
        try {
            $action  = New-ScheduledTaskAction -Execute 'shutdown.exe' -Argument '/h'
            $trigger = New-ScheduledTaskTrigger -Daily -At $At
            $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
            $null = Register-ScheduledTask -TaskName $TaskName -TaskPath '\' -Action $action -Trigger $trigger `
                -Settings $settings -Description 'Hibernate this machine, from InstallationHelper.' -Force -ErrorAction Stop
            $results.Add((New-SettingResult -Key 'import_hibernate_task' -Package $TaskName -Status 'installed' `
                -Detail "runs 'shutdown.exe /h' daily at $At as $env:USERNAME, so it fires while that account is logged on"))
        } catch {
            $results.Add((New-SettingResult -Key 'import_hibernate_task' -Package $TaskName -Status 'failed' `
                -Detail "could not register it: $($_.Exception.Message)"))
            return $results
        }
    }

    if (-not [InstallationHelper.NativeSetting]::IsPwrHibernateAllowed()) {
        $results.Add((New-SettingResult -Key 'import_hibernate_task' -Package 'hibernation support' -Status 'failed' `
            -Detail "the task exists but hibernation is not allowed on this machine, so it would do nothing every night. Turn it on with an elevated 'powercfg /hibernate on', or drop import_hibernate_task."))
    }

    return $results
}

function Invoke-WindowsSystemSetting {
    <#
    .SYNOPSIS
        Applies every enabled Windows system setting and returns a summary.
    .DESCRIPTION
        Takes the already-resolved toggle map from Get-WindowsGroupVarToggle, so whether a setting
        is wanted has one source of truth. Never throws for one setting: the others still run and
        the summary names every failure, which is the same contract the software and custom-install
        phases hold.

        The features go first because WSL needs two of them, and a machine that has just had them
        enabled will report the WSL step as needing the same reboot rather than pretending
        otherwise.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [hashtable] $Toggles,
        [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $SetupDir,
        [string[]] $OnlyKeys
    )

    $results = [System.Collections.Generic.List[object]]::new()

    $wanted = {
        param([string] $key)
        if (-not ($Toggles.ContainsKey($key) -and $Toggles[$key])) { return $false }
        if ($OnlyKeys -and $key -notin $OnlyKeys) { return $false }
        return $true
    }

    if (& $wanted 'enable_hyperv') {
        $results.AddRange([object[]]@(Enable-WindowsFeatureSet -FeatureName (Get-WindowsOptionalFeatureName)))
    }

    if (& $wanted 'setup_wsl') {
        $results.AddRange([object[]]@(Install-WslDistribution))
    }

    if (& $wanted 'set_custom_wallpaper') {
        # The filename is read here rather than inside Set-WindowsWallpaper, so a missing or
        # malformed default_wallpaper is one reported failure instead of an exception out of the
        # whole phase.
        try {
            $name = Get-DefaultWallpaperName -AllVarsPath (Join-Path $SetupDir 'ansible\group_vars\all.yaml')
            if ($name -match '[\\/:]|\.\.') {
                throw "default_wallpaper is '$name', which is a path rather than a filename. It is joined onto setup/wallpapers/ and then written into the registry, so only a bare filename is accepted."
            }
            $results.Add((Set-WindowsWallpaper `
                -SourcePath (Join-Path $SetupDir (Join-Path 'wallpapers' $name)) `
                -DestinationDirectory (Join-Path $env:PUBLIC (Join-Path 'Pictures' 'Backgrounds'))))
        } catch {
            $results.Add((New-SettingResult -Key 'set_custom_wallpaper' -Package 'default_wallpaper' -Status 'failed' `
                -Detail $_.Exception.Message))
        }
    }

    if (& $wanted 'import_hibernate_task') {
        $results.AddRange([object[]]@(Register-HibernateTask))
    }

    return [PSCustomObject]@{
        Results        = $results
        Installed      = @($results | Where-Object { $_.Status -eq 'installed' })
        Present        = @($results | Where-Object { $_.Status -eq 'present' })
        Skipped        = @($results | Where-Object { $_.Status -eq 'skipped' })
        Failed         = @($results | Where-Object { $_.Status -eq 'failed' })
        RebootRequired = @($results | Where-Object { $_.RebootRequired }).Count -gt 0
    }
}
