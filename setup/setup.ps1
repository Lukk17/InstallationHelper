#!/usr/bin/env pwsh
#Requires -Version 7

<#
.SYNOPSIS
    Installation Helper bootstrap wizard for Windows.
.DESCRIPTION
    Configures Windows, and only Windows: the software catalogue, the npm-based CLI tools, the
    installs no package mapping can express, and the four system settings. It no longer runs the
    Ansible playbook. The playbook was invoked as `-i localhost, -c local` from inside WSL, so it
    configured the WSL distribution rather than Windows, which was never what this wizard was for.
    See docs/regression_ledger.md.

    What remains of the WSL side is Ansible itself, installed inside the distribution because it is
    wanted there. Nothing else in WSL is touched.

    Every run ends by asking the machine what it actually ended up with, per application: installed,
    missing, or not requested. There is no flag to turn it off, because a run that reports success
    without checking is how every regression in docs/regression_ledger.md reached a real machine.
    The full result goes to installation_verify.log in the user profile, named on screen when the
    wizard finishes, and a missing application makes this script exit non-zero.

    Uses Microsoft.PowerShell.ConsoleGuiTools (Out-ConsoleGridView) for the multi-select picker
    with filter-as-you-type.
.PARAMETER Profile
    Accepted so the documented invocation keeps working, and it skips the interactive selection the
    same way -NonInteractive does. The profile file itself is an Ansible override for the Linux
    side and no longer applies, which the run says out loud rather than pretending otherwise.
.PARAMETER NonInteractive
    Use group_vars defaults; never prompt.
.PARAMETER NoColor
    Disable themed output (also honored via $env:NO_COLOR).
.PARAMETER SkipSystemUpgrade
    Do not upgrade the already-installed winget and Chocolatey packages first.
.PARAMETER Software
    The starting point the checklist would have started from, for a run with no checklist.
    defaults is the group_vars values as they are, all turns every selectable toggle on, and none
    turns every selectable toggle off so -EnableKey can build a run up from nothing. Implies
    -NonInteractive.
.PARAMETER EnableKey
    Toggle keys to turn on, whatever group_vars says. Comma separated, or a PowerShell array, and
    the keys are the ones -ListSoftware prints. A key the wizard does not offer is refused rather
    than ignored, because a typo that installs nothing while the run reports success is this
    project's most repeated defect. Implies -NonInteractive.
.PARAMETER DisableKey
    Toggle keys to turn off. Applied after -EnableKey, so a key named in both ends up off: the
    option that removes software wins over the option that adds it. Implies -NonInteractive.
.PARAMETER ListSoftware
    Print every key -EnableKey and -DisableKey accept, with its default state and its checklist
    label, and exit. Changes nothing.
.PARAMETER PrintPlan
    Print what this run would install and apply, phase by phase, and exit. Changes nothing, reaches
    no network and probes no package manager. This is where the bash wizard prints its resolved
    ansible-playbook command: there is no playbook command here, because this wizard no longer runs
    the playbook, so the resolved set itself is the answer to what the run would do.

    There is deliberately no -DesktopEnvironment or -DesktopAction to match the bash wizard's
    --desktop-environment and --desktop-action. Those choose what the playbook does about KDE or
    GNOME, this wizard configures Windows and runs no playbook, and a switch that cannot change
    anything is worse than an absent one.

    Exit codes: 0 success, 1 at least one item failed, 2 bad usage, 3 every phase reported success
    and the verification found something the run asked for missing from the machine.
.EXAMPLE
    .\setup.ps1
.EXAMPLE
    .\setup.ps1 -NonInteractive
.EXAMPLE
    .\setup.ps1 -NonInteractive -WhatIf
.EXAMPLE
    .\setup.ps1 -ListSoftware
.EXAMPLE
    .\setup.ps1 -Software none -EnableKey install_k3d -PrintPlan
.EXAMPLE
    .\setup.ps1 -Software all -DisableKey install_gridcoin,enable_hyperv
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string] $Profile,
    [switch] $NonInteractive,
    [switch] $NoColor,
    [switch] $SkipSystemUpgrade,

    [ValidateSet('defaults', 'all', 'none')]
    [string] $Software,

    [string[]] $EnableKey,
    [string[]] $DisableKey,

    [switch] $ListSoftware,
    [switch] $PrintPlan,

    # Permit an elevated run. Only correct on a machine that is thrown away afterwards, which in
    # practice means a hosted CI runner, where every process is elevated and the guard cannot be
    # satisfied. Explicit rather than detected, so privilege behaviour never changes by accident.
    [switch] $AllowAdministrator
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$AnsibleDir = Join-Path $ScriptDir 'ansible'
$AllVars    = Join-Path $AnsibleDir 'group_vars\all.yaml'
$WindowsVars = Join-Path $AnsibleDir 'group_vars\windows.yaml'

# Native Windows installation and configuration. Kept in their own files so they can be tested
# without driving the whole wizard, and because Ansible cannot do this job from here at all: it
# runs inside WSL against localhost, so its facts describe the WSL distribution rather than
# Windows. WindowsSoftware.ps1 is first because the other three read the toggles through it.
. (Join-Path $ScriptDir 'windows\WindowsSoftware.ps1')
. (Join-Path $ScriptDir 'windows\WindowsNpmTools.ps1')
. (Join-Path $ScriptDir 'windows\WindowsCustomInstalls.ps1')
. (Join-Path $ScriptDir 'windows\WindowsSettings.ps1')
# Last, because it asks the machine about what the other four installed and reads their tables to
# know what to ask about.
. (Join-Path $ScriptDir 'windows\WindowsVerify.ps1')

# Hidden from the checklist. Only two reasons qualify: the value is not a boolean the
# checklist could render, or getting it wrong costs a working machine. Everything else
# belongs on the checklist, because a setting the user cannot reach is a setting they
# cannot work around when it breaks. Must stay identical to EXCLUDED_VARS in setup.sh,
# and e2e/tier1/wizard_parse.sh fails if the two ever disagree.
$ExcludedVars = @(
    # Not booleans, or derived from the environment.
    'non_root_user', 'non_root_home', 'default_wallpaper',
    # A logging switch rather than software.
    'allow_callback_failure',
    # The bootstrap every later role assumes has run.
    'install_system_core',
    # Needs a swap device sized for RAM plus a resume kernel parameter.
    'setup_hibernate',
    # These rewrite the bootloader. A mistake here means the machine does not boot.
    'setup_systemd_boot', 'setup_grub',
    'remove_distro_grub', 'remove_distro_systemd_boot'
)

# System settings share the checklist with software, so their labels have to say what
# they do. "Zsh" next to "Chrome" tells the user nothing about which one reconfigures
# their shell. Keys not listed here fall through to the default prefix strip.
$LabelOverrides = @{
    'setup_zsh'             = 'System: zsh shell, with Powerlevel10k and Nerd Fonts'
    'setup_tmpfs'           = 'System: mount /tmp in RAM as tmpfs'
    'set_custom_wallpaper'  = 'System: set the desktop wallpaper'
    'toggle_wayland_nvidia' = 'System: force Wayland on NVIDIA, can break the session'
    'setup_karabiner'       = 'System: Karabiner-Elements key remapping (macOS)'
    'setup_finder_defaults' = 'System: Finder default settings (macOS)'
    'setup_wsl'             = 'System: install WSL and Ubuntu (Windows)'
    'enable_hyperv'         = 'System: enable Hyper-V, WSL, .NET and Sandbox features, needs a reboot (Windows)'
}

if ($env:NO_COLOR -or $NoColor) {
    $script:UseColor = $false
} else {
    $script:UseColor = $true
}

# ---------------------------------------------------------------------------
# Output helpers
# ---------------------------------------------------------------------------

function Set-Theme {
    <#
    .SYNOPSIS
        Themes the console, and gives up quietly when there is no console to theme.
    .DESCRIPTION
        Clear-Host and the [Console] colour properties both go through the real console handle, and
        both throw "The handle is invalid" when stdout is a pipe or a file. That killed the whole
        wizard on its first line of work whenever it was run unattended, which is precisely the run
        where the exit code and the summary are the only things anyone reads. Cosmetics must never
        be able to end a run.
    #>
    try {
        if ($script:UseColor) {
            [Console]::BackgroundColor = [ConsoleColor]::Black
            [Console]::ForegroundColor = [ConsoleColor]::DarkGreen
        }
        Clear-Host
    } catch {
        Write-Verbose "no console to theme: $($_.Exception.Message)"
    }
}

function Write-Banner {
    # [Console]::WindowWidth throws "The handle is invalid" when stdout is a pipe or a file, for the
    # same reason Set-Theme has to tolerate it. 80 is the fallback because that is the width the
    # banner was drawn for.
    $w = 80
    try { $w = [Math]::Max(60, [Console]::WindowWidth) } catch { Write-Verbose 'no console, using a fixed banner width' }
    $border = '=' * $w
    Write-Host $border -ForegroundColor Green
    Write-Host '  INSTALLATION HELPER SETUP'.PadRight($w) -ForegroundColor Green
    Write-Host '  Windows Configuration Wizard'.PadRight($w) -ForegroundColor DarkGreen
    Write-Host $border -ForegroundColor Green
    Write-Host
}

function Write-Section { param([string]$Title)
    Write-Host
    Write-Host "  >> $Title" -ForegroundColor Green
    Write-Host ('  ' + ('-' * ($Title.Length + 4))) -ForegroundColor DarkGreen
    Write-Host
}

function Write-Hint   { param([string]$Text) Write-Host "  $Text" -ForegroundColor DarkGreen }
function Write-Status { param([string]$Text) Write-Host "  [*] $Text" -ForegroundColor Green }
function Write-Err    { param([string]$Text) Write-Host "  [!] $Text" -ForegroundColor Red; throw $Text }

function Invoke-AndShowNpmTools {
    <#
    .SYNOPSIS
        Installs the npm-based CLI tools and renders the outcome.
    .DESCRIPTION
        Separate from the winget and Chocolatey pass because these come from npm, not from a package
        mapping. The ai_tools Ansible role has a Windows task file for each and none of them can run,
        see docs/regression_ledger.md.
    #>
    param(
        [string[]] $OnlyKeys,
        [hashtable] $ToggleOverride
    )

    $toggles = Get-WindowsSoftwareToggle `
        -AllVarsPath     (Join-Path $AnsibleDir 'group_vars\all.yaml') `
        -WindowsVarsPath (Join-Path $AnsibleDir 'group_vars\windows.yaml') `
        -ToggleOverride  $ToggleOverride

    $r = Invoke-WindowsNpmToolInstall -Toggles $toggles -OnlyKeys $OnlyKeys

    if ($r.NpmMissing) {
        Write-Hint '  npm is not on PATH, so the CLI tools below were NOT installed:'
        Write-Hint "    $(($r.Wanted | ForEach-Object { $_.Display }) -join ', ')"
        Write-Hint '  Install Node.js first, then rerun. Saying so rather than skipping quietly, because'
        Write-Hint '  a silent skip would leave you believing these are present.'
        return $r
    }

    if ($r.Results.Count -eq 0) {
        Write-Status 'CLI tools: none enabled'
        return $r
    }

    Write-Status "CLI tools: $($r.Installed.Count) installed, $($r.Present.Count) already present, $($r.Failed.Count) failed"
    foreach ($f in $r.Failed) {
        Write-Host "  [!] $($f.Display) ($($f.Package)): $($f.Detail)" -ForegroundColor Red
    }
    return $r
}

function Invoke-AndShowCustomInstalls {
    <#
    .SYNOPSIS
        Runs the installs a package mapping cannot express and renders the outcome.
    .DESCRIPTION
        Java, Node, Flutter and Gridcoin. Separate from the mapping pass because each
        needs more than one package, or no package exists at all. See
        setup/windows/WindowsCustomInstalls.ps1 for what each one does and why.
    #>
    param(
        [string[]] $OnlyKeys,
        [hashtable] $ToggleOverride
    )

    $toggles = Get-WindowsSoftwareToggle `
        -AllVarsPath     (Join-Path $AnsibleDir 'group_vars\all.yaml') `
        -WindowsVarsPath (Join-Path $AnsibleDir 'group_vars\windows.yaml') `
        -ToggleOverride  $ToggleOverride

    $r = Invoke-WindowsCustomInstall -Toggles $toggles -OnlyKeys $OnlyKeys

    if ($r.Results.Count -eq 0) {
        Write-Status 'SDKs and standalone installers: none enabled'
        return $r
    }

    Write-Status "SDKs and standalone installers: $($r.Installed.Count) done, $($r.Present.Count) already present, $($r.Failed.Count) failed"
    foreach ($f in $r.Failed) {
        Write-Host "  [!] $($f.Key) ($($f.Package)): $($f.Detail)" -ForegroundColor Red
    }
    return $r
}

function Show-WindowsSoftwareResult {
    <#
    .SYNOPSIS
        Renders the result of the native Windows install.
    .DESCRIPTION
        Names every failure and every toggle that had nowhere to go. A count on its own would
        let a package quietly not install, which is the class of bug this replaces.
    #>
    param([Parameter(Mandatory)] $Result)

    Write-Status "Windows packages: $($Result.Installed.Count) installed, $($Result.Present.Count) already present, $($Result.Skipped.Count) not attempted, $($Result.Failed.Count) failed"

    foreach ($f in $Result.Failed) {
        Write-Host "  [!] $($f.Key) ($($f.Package)) via $($f.Manager): $($f.Detail)" -ForegroundColor Red
    }

    if ($Result.Unmapped.Count -gt 0) {
        Write-Hint "  $($Result.Unmapped.Count) enabled toggle(s) have no Windows package mapping and were not installed:"
        Write-Hint "    $($Result.Unmapped -join ', ')"
        Write-Hint '  Some of those are Linux-only by design. The rest are handled by Ansible roles that cannot run on Windows yet, see docs/regression_ledger.md.'
    }
}

function Invoke-AndShowDevEnvironment {
    <#
    .SYNOPSIS
        Writes the development environment variables and renders the outcome.
    .DESCRIPTION
        The Windows half of what roles/env_variables does on Linux and macOS. env_windows.yaml held
        these and could never run, because the playbook is invoked from inside WSL and reports
        os_family Debian, so on Windows they were never written at all. Not gated on a toggle, for
        the same reason the Unix role is not: the paths are where this project keeps tool state, and
        a machine configured by either side should agree about them.
    #>
    param()

    $r = Set-WindowsDevEnvironment
    $installed = @($r | Where-Object { $_.Status -eq 'installed' })
    $present   = @($r | Where-Object { $_.Status -eq 'present' })
    $failed    = @($r | Where-Object { $_.Status -eq 'failed' })

    Write-Status "Environment variables: $($installed.Count) written, $($present.Count) already correct, $($failed.Count) failed"
    foreach ($f in $failed) {
        Write-Host "  [!] $($f.Package): $($f.Detail)" -ForegroundColor Red
    }
    if ($installed.Count -gt 0) {
        Write-Hint '  A shell already open will not see these. Open a new one, and log out and back in for anything started by Explorer.'
    }

    return [PSCustomObject]@{
        Results = $r
        Installed = $installed
        Present   = $present
        Skipped   = @($r | Where-Object { $_.Status -eq 'skipped' })
        Failed    = $failed
    }
}

function Invoke-AndShowWindowsSettings {
    <#
    .SYNOPSIS
        Applies the four Windows system settings and renders the outcome.
    .DESCRIPTION
        The optional features, the WSL distribution, the wallpaper and the hibernate task. Each one
        had a windows_core task file that can never run, and until now nothing else applied them, so
        four toggles the user could switch on did nothing at all. See
        setup/windows/WindowsSettings.ps1 for what each one does and how it differs from the dead
        Ansible.
    #>
    param(
        [string[]] $OnlyKeys,
        [hashtable] $ToggleOverride
    )

    $toggles = Get-WindowsGroupVarToggle -AllVarsPath $AllVars -WindowsVarsPath $WindowsVars -ToggleOverride $ToggleOverride
    $r = Invoke-WindowsSystemSetting -Toggles $toggles -SetupDir $ScriptDir -OnlyKeys $OnlyKeys

    if ($r.Results.Count -eq 0) {
        Write-Status 'Windows system settings: none enabled'
        return $r
    }

    Write-Status "Windows system settings: $($r.Installed.Count) applied, $($r.Present.Count) already set, $($r.Skipped.Count) not attempted, $($r.Failed.Count) failed"
    foreach ($s in $r.Skipped) {
        Write-Hint "  $($s.Key) ($($s.Package)): $($s.Detail)"
    }
    foreach ($f in $r.Failed) {
        Write-Host "  [!] $($f.Key) ($($f.Package)): $($f.Detail)" -ForegroundColor Red
    }
    if ($r.RebootRequired) {
        Write-Hint '  Some of those need a reboot before they do anything. They are reported as applied and not as active, because a feature that is enabled and not yet running is not a finished job.'
    }
    return $r
}

function Invoke-AndShowWslAnsible {
    <#
    .SYNOPSIS
        Installs Ansible inside WSL and renders the outcome.
    .DESCRIPTION
        The only thing this wizard still does to WSL. The playbook used to be run from here against
        localhost inside the distribution, which configured Linux rather than Windows, and that is
        gone. Ansible itself stays, because it is wanted in there.

        A problem here is reported rather than thrown. This runs after the Windows work, and losing
        an entire finished Windows run to an apt failure inside WSL would throw away everything that
        did succeed.
    #>
    param()

    $r = Install-AnsibleInWsl

    Write-Status "Ansible inside WSL: $($r.Installed.Count) installed, $($r.Present.Count) already present, $($r.Skipped.Count) not attempted, $($r.Failed.Count) failed"
    foreach ($s in $r.Skipped) {
        Write-Hint "  $($s.Key) ($($s.Package)): $($s.Detail)"
    }
    foreach ($f in $r.Failed) {
        Write-Host "  [!] $($f.Key) ($($f.Package)): $($f.Detail)" -ForegroundColor Red
    }
    return $r
}

function Invoke-AndShowVerification {
    <#
    .SYNOPSIS
        Asks the machine what actually landed, prints the verdicts, and returns the result.
    .DESCRIPTION
        The last thing a run does, on every path that installs anything, which is what setup.sh does
        with finish_run on Linux and macOS. Everything above this point reports what the installers
        believed they did. This reports what is on the disk, which is a different claim and the only
        one worth exiting on.

        It installs nothing and changes nothing, so there is no option to skip it. A run that says
        success without asking the machine is the shape of every regression in
        docs/regression_ledger.md.

        The whole report goes to the log and to the screen. The Ansible side prints only the report
        lines it lifts out of the play's own output, because Ansible surrounds them with a task list
        nobody can read a verdict out of. Here the report is all there is.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [string[]] $OnlyKeys,
        [hashtable] $ToggleOverride
    )

    Write-Section 'Verifying what actually landed'
    Write-Hint '  This asks winget, Chocolatey, npm and the disk itself. It installs and changes nothing.'
    Write-Hint '  It asks winget once per package, so it takes a couple of minutes on a full selection.'

    $result = Invoke-WindowsVerification -AnsibleDir $AnsibleDir -OnlyKeys $OnlyKeys -ToggleOverride $ToggleOverride

    Write-Host
    foreach ($line in $result.Report) { Write-Host "  $line" }
    Write-Host

    if (-not $result.LogWritten) {
        Write-Hint "  The report above could not be written to $($result.LogPath), so this screen is the only copy."
    } elseif ($result.Failed.Count -eq 0) {
        Write-Status "Verification passed. Full result: $($result.LogPath)"
    } else {
        Write-Host "  [!] Verification FAILED: $($result.Failed.Count) item(s) requested and not present. Full result: $($result.LogPath)" -ForegroundColor Red
    }
    return $result
}

function Get-PhaseFailure {
    <#
    .SYNOPSIS
        One phase's failures, normalised to Key, Package and Detail.
    .DESCRIPTION
        The phases return slightly different shapes: the npm tools carry a Display name rather than
        a Key, and when npm is absent they carry no results at all, only the list of tools that were
        wanted. That last case is a total loss reported as a single flag, which is exactly how the
        old count read it as one failure however many tools the user had asked for.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param([Parameter(Mandatory)] [AllowNull()] $Result)

    if ($null -eq $Result) { return @() }

    $properties = $Result.PSObject.Properties.Name

    if (($properties -contains 'NpmMissing') -and $Result.NpmMissing) {
        return @($Result.Wanted | ForEach-Object {
            [PSCustomObject]@{
                Key     = $_.Key
                Package = $_.Package
                Detail  = 'npm is not on PATH, so this was never installed. Install Node.js first, then rerun.'
            }
        })
    }

    return @($Result.Failed | ForEach-Object {
        [PSCustomObject]@{
            Key     = if ($_.PSObject.Properties.Name -contains 'Key') { $_.Key } else { $_.Display }
            Package = $_.Package
            Detail  = $_.Detail
        }
    })
}

function Write-RunSummary {
    <#
    .SYNOPSIS
        Prints every failure from every phase, by key and package, and returns how many there were.
    .DESCRIPTION
        The last thing the run prints, unconditionally. Each phase already names its own failures as
        it goes, but a long run scrolls them off the screen, and the one line that used to reconcile
        them sat inside a condition that skipped it whenever the playbook had failed too. So a
        Windows package failure could be printed early, buried under the playbook's output, and
        never mentioned again.

        Both entry paths call this, because the non-interactive branch and the interactive one each
        had their own copy of the reconciliation and only one of them ever got fixed.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param([Parameter(Mandatory)] [System.Collections.Specialized.OrderedDictionary] $Phase)

    Write-Section 'Summary'

    $total = 0
    foreach ($label in $Phase.Keys) {
        $failures = @(Get-PhaseFailure -Result $Phase[$label])
        if ($failures.Count -eq 0) {
            Write-Status "${label}: nothing failed"
            continue
        }
        $total += $failures.Count
        Write-Host "  [!] ${label}: $($failures.Count) failed" -ForegroundColor Red
        foreach ($f in $failures) {
            Write-Host "      $($f.Key) ($($f.Package)): $($f.Detail)" -ForegroundColor Red
        }
    }

    foreach ($label in $Phase.Keys) {
        $result = $Phase[$label]
        if ($null -eq $result) { continue }
        if (($result.PSObject.Properties.Name -contains 'RebootRequired') -and $result.RebootRequired) {
            Write-Hint "  ${label} changed something that needs a reboot before it takes effect. Reboot, then rerun this wizard to confirm."
        }
    }

    if ($total -eq 0) {
        Write-Status 'Nothing failed.'
    } else {
        Write-Host "  [!] $total item(s) failed in total. Exiting non-zero so this is not read as a clean run." -ForegroundColor Red
    }
    return $total
}

# ---------------------------------------------------------------------------
# Guards
# ---------------------------------------------------------------------------

function Assert-NotAdmin {
    <#
    .SYNOPSIS
        Refuse to run elevated, unless the caller says it means to.
    .DESCRIPTION
        Running this wizard elevated puts root-owned files in a normal user's profile and installs
        per-user software for the wrong account, which is why the refusal exists and why it is the
        first thing Invoke-Main does.

        -AllowAdministrator is the documented way past it, and it is a parameter rather than an
        environment sniff for the same reason -PasswordlessSudo is: privilege behaviour should change
        because someone asked, not because the script noticed something about its surroundings.

        The case that needs it is a hosted continuous integration runner. GitHub's own documentation
        states that "Windows virtual machines are configured to run as administrators with User
        Account Control (UAC) disabled", so every process on such a runner reads as elevated and this
        guard would refuse on its first line, every time, with no way to comply. There is no user
        profile to pollute there, because the machine is destroyed after the job.
    #>
    $principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        return
    }

    if ($AllowAdministrator) {
        Write-Hint 'Running elevated because -AllowAdministrator was passed. On a real machine this leaves root-owned files in your profile.'
        return
    }

    Write-Err 'Do not run as Administrator. Run as your regular user, or pass -AllowAdministrator if this is a throwaway machine such as a CI runner.'
}

function Assert-AnsibleDir {
    if (-not (Test-Path $AnsibleDir)) {
        Write-Err "Ansible directory not found at $AnsibleDir"
    }
}

# ---------------------------------------------------------------------------
# WSL — Ansible only
# ---------------------------------------------------------------------------

function Install-AnsibleInWsl {
    <#
    .SYNOPSIS
        Ensures WSL exists and Ansible is installed inside it, and returns a result summary.
    .DESCRIPTION
        Returns an object in the same shape as the Windows phases rather than throwing, so the run
        summary can name what went wrong here alongside everything else. It used to throw through
        Write-Err, which was correct while the whole point of the wizard was the playbook and is
        wrong now: WSL is no longer on the critical path for anything this wizard does to Windows.

        The apt branch adds the Ansible PPA because Ubuntu's own archive lags, which is the only apt
        work left in here. The system upgrade that used to run first was there to prepare the
        playbook, and the playbook is gone.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param()

    $results = [System.Collections.Generic.List[object]]::new()
    $add = {
        param([string] $Status, [string] $Detail)
        $results.Add([PSCustomObject]@{ Key = 'ansible'; Package = 'ansible'; Status = $Status; Detail = $Detail })
    }

    if (-not (Get-Command wsl -CommandType Application -ErrorAction SilentlyContinue)) {
        & $add 'failed' 'wsl.exe is not on this machine, so Ansible cannot be installed inside it. Run: wsl --install -d Ubuntu'
        return New-WslResult -Results $results
    }

    $previousNative = $PSNativeCommandUseErrorActionPreference
    try {
        # Every one of these exits non-zero for reasons that are answers rather than faults: no
        # distribution registered, ansible-playbook absent, a package manager that failed.
        $PSNativeCommandUseErrorActionPreference = $false

        $distros = @(Get-WslDistributionName)
        if ($distros.Count -eq 0) {
            & $add 'failed' 'WSL is installed but no Linux distribution is registered, so there is nothing to install Ansible into. Run: wsl --install -d Ubuntu'
            return New-WslResult -Results $results
        }

        # Every registered distribution is tried, in order, until one answers, and each is asked as
        # root rather than as its default user.
        #
        # Both halves of that are measured rather than preferred. A runner has two distributions,
        # the image's own Ubuntu and the Ubuntu-26.04 the workflow registers, and taking the first
        # one picked the freshly registered one, which answered an empty string at exit code 0:
        # registered with --no-launch, never initialised, no user but root, and nothing in
        # /etc/os-release that a shell could read. The distribution that would have worked was
        # second in the list. Asking one and giving up is how a machine with a working WSL still
        # gets told it has none.
        $distro     = $null
        $distroId   = $null
        $probeFails = [System.Collections.Generic.List[string]]::new()

        # /etc/os-release is read with cat and parsed on this side, and that is the whole point.
        # `wsl -d X -- bash -c '<script>'` returns an empty string at exit code 0 from PowerShell,
        # measured on 2026-08-22 against a working Ubuntu on a real machine: the argument reaches
        # wsl.exe mangled by PowerShell's native argument passing, bash runs something harmless and
        # prints nothing, and the caller cannot tell that from a distribution with no os-release.
        # That, and not the freshly registered distribution, is why the wizard reported
        # "cannot auto-install Ansible for distro family ''". cat with no shell in the way returns
        # all 399 bytes of the file, and the same call shape is used for the install below.
        foreach ($candidate in $distros) {
            $osRelease = wsl --distribution $candidate --user root -- cat /etc/os-release 2>&1
            $probeRc   = $LASTEXITCODE
            $fields    = @{}
            foreach ($line in @($osRelease)) {
                if ("$line" -match '^\s*([A-Z_]+)=(.*)$') {
                    $fields[$Matches[1]] = $Matches[2].Trim().Trim('"').Trim("'")
                }
            }
            $answer = if ($fields['ID_LIKE']) { $fields['ID_LIKE'] } elseif ($fields['ID']) { $fields['ID'] } else { '' }
            if ($probeRc -eq 0 -and $answer) {
                $distro   = $candidate
                $distroId = $answer
                break
            }
            $probeFails.Add("$candidate exited $probeRc and gave no ID or ID_LIKE")
        }

        if (-not $distro) {
            & $add 'failed' ("no registered WSL distribution could say what it is, so Ansible cannot " +
                "be installed into one. Asked each of them for /etc/os-release: " +
                ($probeFails -join '; ') + ". A distribution installed with --no-launch has never " +
                "completed its first run, so launch it once by hand and try again.")
            return New-WslResult -Results $results
        }

        $null = wsl --distribution $distro --user root -- which ansible-playbook 2>&1
        if ($LASTEXITCODE -eq 0) {
            & $add 'present' "ansible-playbook is already on PATH inside '$distro'"
            return New-WslResult -Results $results
        }

        # A list of argument lists rather than one shell string, and no sudo anywhere.
        #
        # No shell, because a command handed to `bash -c` through wsl.exe does not survive
        # PowerShell's argument passing, which is what the probe above documents. Each step is its
        # own wsl call with its arguments as an array, which needs no quoting at all and gives an
        # exit code per step, so a failure names the step that failed instead of the whole chain.
        #
        # No sudo, because these run as root already. Asking for it would fail on a distribution
        # that does not ship it, which Arch does not, and on a fresh registration where no user
        # exists to be in its sudoers.
        # Each step carries whether it may fail. Every one of these reaches the network, and on
        # 2026-08-25 the Windows defaults cell of sweep 32839893770 lost the whole phase to one of
        # them: `add-apt-repository --yes --update ppa:ansible/ansible` exited 1 after printing
        # "Adding repository." The PPA was not the problem, measured the same day, it publishes for
        # this suite and https://ppa.launchpadcontent.net/ansible/ansible/ubuntu/dists/resolute/Release
        # answers 200. What failed was the apt update that `--update` performs, and there was no retry
        # anywhere in this sequence.
        #
        # Optional means a failure is reported and the sequence continues. Only the PPA is optional,
        # and only because the distribution's own ansible is inside the version range setup.sh
        # accepts, so losing the PPA costs a newer ansible-core rather than costing Ansible. Every
        # other step is required, because without it nothing is installed at all.
        $steps = switch -Regex ($distroId) {
            'debian|ubuntu'      { ,@(
                                     @{ Args = @('apt-get', 'update', '-q'); Optional = $false },
                                     @{ Args = @('apt-get', 'install', '-y', 'software-properties-common'); Optional = $false },
                                     @{ Args = @('add-apt-repository', '--yes', '--update', 'ppa:ansible/ansible'); Optional = $true },
                                     @{ Args = @('apt-get', 'install', '-y', 'ansible'); Optional = $false }
                                   ) }
            'fedora|rhel|centos' { ,@( @{ Args = @('dnf', 'install', '-y', 'ansible'); Optional = $false } ) }
            'arch'               { ,@( @{ Args = @('pacman', '-S', '--noconfirm', 'ansible'); Optional = $false } ) }
            default              { $null }
        }
        if (-not $steps) {
            & $add 'failed' ("no package manager is known for the distribution family '$distroId' " +
                "reported by '$distro'. Install Ansible by hand inside WSL.")
            return New-WslResult -Results $results
        }

        $rendered = ($steps | ForEach-Object { $_.Args -join ' ' }) -join ' && '
        if (-not $PSCmdlet.ShouldProcess("$distroId inside WSL", 'install ansible')) {
            & $add 'skipped' "WhatIf, would run in '$distro': $rendered"
            return New-WslResult -Results $results
        }

        Write-Status "Installing Ansible inside WSL ($distro, family $distroId)..."
        $skippedSteps = [System.Collections.Generic.List[string]]::new()
        foreach ($step in $steps) {
            $label = $step.Args -join ' '
            $lastCode = 0
            # Three attempts with a pause between them, because these are network operations and a
            # single dropped connection must not cost the phase. The pause is short: apt keeps what it
            # already fetched, so a retry costs only what was lost.
            for ($attempt = 1; $attempt -le 3; $attempt++) {
                if ($attempt -gt 1) {
                    Write-Hint "  retrying '$label' inside '$distro', attempt $attempt of 3"
                    Start-Sleep -Seconds 15
                }
                wsl --distribution $distro --user root -- @($step.Args) | Out-Host
                $lastCode = $LASTEXITCODE
                if ($lastCode -eq 0) { break }
            }
            if ($lastCode -ne 0) {
                if ($step.Optional) {
                    $skippedSteps.Add($label)
                    Write-Hint ("  '$label' exited $lastCode after three attempts and is not required, " +
                        "so the sequence continues with the distribution's own package instead")
                    continue
                }
                & $add 'failed' ("'$label' exited $lastCode inside '$distro' after three attempts, so " +
                    "Ansible is not installed in there. The whole sequence is: $rendered")
                return New-WslResult -Results $results
            }
        }

        # Asked rather than assumed. This phase used to report installed on the strength of the last
        # step exiting zero, which is the shape this repository has been burnt by repeatedly: a
        # command that succeeds and leaves nothing behind. `which` is the same question the early-exit
        # probe above asks, so a present run and an installed run are decided the same way.
        $null = wsl --distribution $distro --user root -- which ansible-playbook 2>&1
        if ($LASTEXITCODE -ne 0) {
            & $add 'failed' ("every install step exited zero inside '$distro' and ansible-playbook is " +
                "still not on PATH there, so nothing usable was installed. The sequence was: $rendered")
            return New-WslResult -Results $results
        }

        $note = if ($skippedSteps.Count -gt 0) {
            "installed inside WSL, without $($skippedSteps -join ', '), which failed and is not required"
        } else {
            'installed inside WSL'
        }
        & $add 'installed' $note
        return New-WslResult -Results $results
    } finally {
        $PSNativeCommandUseErrorActionPreference = $previousNative
    }
}

function New-WslResult {
    <#
    .SYNOPSIS
        Wraps the WSL result rows in the same summary shape every other phase returns.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param([Parameter(Mandatory)] [AllowEmptyCollection()] [System.Collections.Generic.List[object]] $Results)

    return [PSCustomObject]@{
        Results   = $Results
        Installed = @($Results | Where-Object { $_.Status -eq 'installed' })
        Present   = @($Results | Where-Object { $_.Status -eq 'present' })
        Skipped   = @($Results | Where-Object { $_.Status -eq 'skipped' })
        Failed    = @($Results | Where-Object { $_.Status -eq 'failed' })
    }
}

function Invoke-WindowsSystemUpgrade {
    <#
    .SYNOPSIS
        Upgrades the packages already installed on Windows.
    .DESCRIPTION
        ShouldProcess is not decoration here. Both upgrades are native commands, which -WhatIf
        cannot intercept on its own, so without the guard a dry run of this wizard upgraded every
        winget and Chocolatey package on the machine before printing a single "would install" line.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param()

    if ($SkipSystemUpgrade) {
        Write-Status 'Skipping Windows system upgrade (-SkipSystemUpgrade).'
        return
    }
    Write-Status 'Upgrading the packages already installed on Windows (skip with -SkipSystemUpgrade)...'

    if (Get-Command winget -ErrorAction SilentlyContinue) {
        if ($PSCmdlet.ShouldProcess('every installed winget package', 'winget upgrade --all')) {
            Write-Status 'winget: upgrading all installed packages...'
            & winget upgrade --all --accept-package-agreements --accept-source-agreements --silent --disable-interactivity
            if ($LASTEXITCODE -ne 0) {
                Write-Hint "winget exited with code $LASTEXITCODE (some packages may have no upgrade); continuing."
            }
        }
    } else {
        Write-Hint 'winget not found; skipping winget upgrade.'
    }

    if (Get-Command choco -ErrorAction SilentlyContinue) {
        if ($PSCmdlet.ShouldProcess('every installed Chocolatey package', 'choco upgrade all')) {
            Write-Status 'chocolatey: upgrading all installed packages...'
            & choco upgrade all -y --no-progress
            if ($LASTEXITCODE -ne 0) {
                Write-Hint "choco exited with code $LASTEXITCODE; continuing."
            }
        }
    } else {
        Write-Hint 'chocolatey not found; skipping choco upgrade.'
    }

    Write-Hint 'Windows Update (OS patches) is not triggered automatically — handled by Windows itself or Settings > Windows Update.'
}

# The Ansible collections install went with the playbook run. requirements.yaml exists so the
# playbook can resolve its collections, and nothing this wizard still does needs them: a user who
# later runs the playbook inside WSL by hand installs them there with
# `ansible-galaxy collection install -r requirements.yaml`, which is what setup.sh does on Linux.

# ---------------------------------------------------------------------------
# ConsoleGuiTools bootstrap — required for the new picker UX
# ---------------------------------------------------------------------------

function Install-ConsoleGuiTools {
    if (Get-Module -ListAvailable -Name Microsoft.PowerShell.ConsoleGuiTools) {
        return
    }
    Write-Status 'Installing Microsoft.PowerShell.ConsoleGuiTools (one-time)...'
    try {
        Install-Module -Name Microsoft.PowerShell.ConsoleGuiTools -Scope CurrentUser -Force -AcceptLicense -ErrorAction Stop
    } catch {
        Write-Err "Could not install Microsoft.PowerShell.ConsoleGuiTools: $_"
    }
}

# ---------------------------------------------------------------------------
# Toggle reader
# ---------------------------------------------------------------------------

function Read-Toggles {
    <#
    .SYNOPSIS
        One group_vars file's boolean toggles, minus the ones the checklist deliberately hides.
    .DESCRIPTION
        The character class is [a-z0-9_], the same class WindowsSoftware.ps1 uses in
        $script:ToggleLinePattern, because a toggle name may carry a digit. It was [a-z_] here, which
        cannot match install_k3d: the toggle is enabled by default, and it was invisible to the
        checklist, so a user could neither see it nor untick it. Any name with a digit in it would
        have gone the same way. See docs/regression_ledger.md.
    #>
    param([string]$FilePath)
    if (-not (Test-Path $FilePath)) { return @() }
    return Get-Content $FilePath |
        Where-Object { $_ -match '^[a-z0-9_]+: (true|false)' } |
        Where-Object { ($_ -split ':')[0] -notin $ExcludedVars } |
        ForEach-Object {
            if ($_ -match '^([a-z0-9_]+): (true|false)') {
                [PSCustomObject]@{ Key = $Matches[1]; Enabled = ($Matches[2] -eq 'true') }
            }
        }
}

function Get-ToggleLabel {
    <#
    .SYNOPSIS
        The label the checklist shows for one toggle key.
    .DESCRIPTION
        Shared by the interactive picker and -ListSoftware, so the name a scripted caller reads is
        the name the person at the keyboard reads. A system setting whose label came out of the
        default prefix strip would render setup_zsh as "Zsh" next to "Chrome", which is why
        $LabelOverrides exists and why e2e/tier1/wizard_parse.sh fails when one is missing.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $Key)

    if ($LabelOverrides.ContainsKey($Key)) { return $LabelOverrides[$Key] }
    return ($Key -replace '^install_', '' -replace '^setup_', '' -replace '^configure_', '' -replace '_', ' ')
}

function Get-SelectableToggle {
    <#
    .SYNOPSIS
        Every toggle this wizard offers, in file order, as Key / Enabled / Label rows.
    .DESCRIPTION
        One list with four readers: the interactive checklist renders it, -ListSoftware prints it,
        -EnableKey and -DisableKey are validated against it, and -Software resolves against it. A
        second list would let a scripted run reach a key the checklist hides, or refuse one it offers.

        all.yaml and windows.yaml, and only those two. linux.yaml used to be read as well, because a
        run also configured the Linux side inside WSL and the checklist had to offer both sets. It no
        longer does, so a Linux-only toggle on this list could not change anything whichever way it
        was left, and a control that does nothing is worse than an absent one.

        Which keys are offered, and in what order, comes from Read-Toggles: it is per file, so it can
        keep the order of the files and drop the hidden ones. Whether a key is on comes from
        Get-WindowsGroupVarToggle, the same reader every phase uses, because windows.yaml is layered
        over all.yaml and only that reader applies the layering. Taking the state per file instead
        showed the first spelling of a key that appears in both: install_dbeaver and
        install_onlyoffice are true in all.yaml and false in windows.yaml, so the checklist said ON
        for two packages a Windows run does not install.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param()

    $effective = Get-WindowsGroupVarToggle -AllVarsPath $AllVars -WindowsVarsPath $WindowsVars

    $seenKeys = [System.Collections.Generic.HashSet[string]]::new()
    $items    = [System.Collections.Generic.List[PSCustomObject]]::new()
    foreach ($item in (@(Read-Toggles $AllVars) + @(Read-Toggles $WindowsVars))) {
        if (-not $seenKeys.Add($item.Key)) { continue }
        $items.Add([PSCustomObject]@{
            Key     = $item.Key
            Enabled = [bool] $effective[$item.Key]
            Label   = (Get-ToggleLabel -Key $item.Key)
        })
    }
    return $items.ToArray()
}

function Split-KeyList {
    <#
    .SYNOPSIS
        Splits -EnableKey and -DisableKey into bare keys.
    .DESCRIPTION
        Commas and whitespace both separate, because PowerShell hands an array over when the caller
        writes -EnableKey a,b and a single string when a pipeline interpolates one, and the bash
        wizard's --enable accepts both spellings too.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param([string[]] $Value)

    if (-not $Value) { return @() }
    return @($Value -split '[,\s]+' | Where-Object { $_ })
}

function Assert-KnownSelectionKey {
    <#
    .SYNOPSIS
        Refuses a key the checklist does not offer, naming it and pointing at -ListSoftware.
    .DESCRIPTION
        Called from Invoke-Main, on the main path, and that placement is the whole point. The bash
        wizard's first version of this check sat inside a process substitution where its exit ended
        the subshell and nothing else: the error printed, the run carried on, and the group_vars
        defaults were installed while the run claimed to honour options it had just rejected.

        Refused rather than ignored: a key this wizard cannot reach is either a typo or a setting
        deliberately kept off the checklist, and both deserve an error rather than a run that
        installs something else and reports success.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $ParameterName,
        [string[]] $Key,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [PSCustomObject[]] $Selectable
    )

    $known   = @($Selectable | ForEach-Object { $_.Key })
    $unknown = @(Split-KeyList -Value $Key | Where-Object { $_ -notin $known })
    if ($unknown.Count -eq 0) { return }

    Write-Host "  [!] $ParameterName names $($unknown.Count) key(s) this wizard does not offer: $($unknown -join ', ')" -ForegroundColor Red
    Write-Host '      Run .\setup.ps1 -ListSoftware for the keys it does offer.' -ForegroundColor Red
    exit 2
}

function Resolve-ToggleOverride {
    <#
    .SYNOPSIS
        Turns -Software, -EnableKey and -DisableKey into a key to boolean map, or null when none was passed.
    .DESCRIPTION
        Null means "nobody asked", which is not the same as an empty map, and the caller needs the
        difference: null leaves group_vars alone and keeps the interactive path available, while an
        empty map is -Software defaults, which asks for group_vars as they are and no prompts.

        A defaults baseline emits nothing rather than restating each toggle's current value, which is
        what the bash wizard has to do because it hands its selection to Ansible as extra variables.
        Here the phases read the files themselves, so an entry per toggle would be a second copy of a
        value nobody asked to change, and a second copy is a thing that can be wrong.

        -DisableKey is applied last so a key named in both ends up off. That order is the safe one.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [PSCustomObject[]] $Selectable,
        [string] $Baseline,
        [string[]] $EnableKey,
        [string[]] $DisableKey
    )

    $enable  = @(Split-KeyList -Value $EnableKey)
    $disable = @(Split-KeyList -Value $DisableKey)
    if (-not $Baseline -and $enable.Count -eq 0 -and $disable.Count -eq 0) { return $null }

    $override = @{}
    switch ($Baseline) {
        'all'  { foreach ($item in $Selectable) { $override[$item.Key] = $true } }
        'none' { foreach ($item in $Selectable) { $override[$item.Key] = $false } }
    }
    foreach ($key in $enable)  { $override[$key] = $true }
    foreach ($key in $disable) { $override[$key] = $false }
    return $override
}

function Show-SoftwareList {
    <#
    .SYNOPSIS
        Prints every key -EnableKey and -DisableKey accept, with its default state and its label.
    .DESCRIPTION
        Write-Output rather than Write-Host, because this is data a pipeline reads and parses rather
        than a status line for a person, and because it must survive being redirected to a file with
        no console attached.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [AllowEmptyCollection()] [PSCustomObject[]] $Selectable)

    foreach ($item in $Selectable) {
        Write-Output ('{0,-32} {1,-4} {2}' -f $item.Key, $(if ($item.Enabled) { 'ON' } else { 'OFF' }), $item.Label)
    }
}

# The profile picker went with the playbook run. Every file under setup/ansible/profiles/ is a set
# of Ansible variable overrides for the Linux side, applied with -e "@<file>", and there is nothing
# on the Windows side for them to override: the native installer deliberately ignored them even
# while the playbook still ran, because a Linux live-USB profile has no opinion about which Windows
# packages you want.

# ---------------------------------------------------------------------------
# Picker screens — Out-ConsoleGridView for multi-select, PromptForChoice for yes/no
# ---------------------------------------------------------------------------

function Show-Choice {
    param(
        [string]   $Title,
        [string]   $Prompt,
        [string[]] $Options,
        [string[]] $HelpMessages = $null
    )
    Write-Section $Title
    $choices = @()
    for ($i = 0; $i -lt $Options.Length; $i++) {
        $label = $Options[$i]
        $help = if ($HelpMessages -and $i -lt $HelpMessages.Length) { $HelpMessages[$i] } else { $label }
        $choices += [System.Management.Automation.Host.ChoiceDescription]::new("&$label", $help)
    }
    $idx = $Host.UI.PromptForChoice('', $Prompt, $choices, 0)
    return $Options[$idx]
}

function Show-YesNo {
    param([string]$Title, [string]$Prompt, [bool]$DefaultYes = $true)
    Write-Section $Title
    $choices = @(
        [System.Management.Automation.Host.ChoiceDescription]::new('&Yes', 'Confirm')
        [System.Management.Automation.Host.ChoiceDescription]::new('&No',  'Decline')
    )
    $default = if ($DefaultYes) { 0 } else { 1 }
    return ($Host.UI.PromptForChoice('', $Prompt, $choices, $default) -eq 0)
}

function Show-SoftwarePicker {
    param([PSCustomObject[]] $Items)
    if ($Items.Length -eq 0) { return @() }

    Import-Module Microsoft.PowerShell.ConsoleGuiTools -ErrorAction Stop

    # Build display objects. Pre-select currently-enabled items by piping them
    # into Out-ConsoleGridView's input — selection state is preserved via the
    # `Enabled` column which the user sees and can toggle.
    $rows = $Items | Select-Object `
        @{ N = 'Key';     E = { $_.Key } }, `
        @{ N = 'Name';    E = { $_.Label } }, `
        @{ N = 'Default'; E = { if ($_.Enabled) { 'ON' } else { 'off' } } }

    $selected = $rows |
        Out-ConsoleGridView `
            -Title 'Software — type to filter, Space to mark, Enter to confirm, Esc to cancel' `
            -OutputMode Multiple

    if ($null -eq $selected) { return $null }
    return @($selected.Key)
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

function Get-SoftwareSelection {
    <#
    .SYNOPSIS
        Asks which software to install, and returns the chosen keys, or null for the defaults.
    .DESCRIPTION
        Null means "everything the group_vars files enable". Only the customise path narrows it.
        A cancelled picker exits the run from here rather than returning null, because null already
        means the defaults and the caller could not tell the two apart.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [AllowEmptyCollection()] [PSCustomObject[]] $Selectable)

    $mode = Show-Choice `
        -Title  'Step 1/2 — Software Selection' `
        -Prompt 'How would you like to choose software?' `
        -Options @('defaults', 'customise') `
        -HelpMessages @('Use group_vars settings as-is',
                        'Open the multi-select grid to toggle individual apps')

    if ($mode -eq 'defaults') { return $null }

    $selectedKeys = Show-SoftwarePicker -Items $Selectable
    if ($null -eq $selectedKeys) {
        Write-Hint '  Cancelled.'
        exit 0
    }

    # The native installers key off the bare name, without the install_ prefix the checklist
    # carries. The four system settings have no prefix and pass through unchanged, which is what
    # lets unticking one of them mean it is not applied.
    return @($selectedKeys | ForEach-Object {
        if ($_ -like 'install_*') { $_.Substring('install_'.Length) } else { $_ }
    })
}

function Invoke-WindowsRun {
    <#
    .SYNOPSIS
        Runs every phase and returns the phase results, keyed by the label the summary prints.
    .DESCRIPTION
        One function for both entry paths. The non-interactive branch and the interactive one used to
        carry their own copy of this, and of the reconciliation that followed it, which is how the
        interactive copy got a fix the other one did not.

        Ansible cannot manage any of this from here: it runs inside WSL against localhost, so its
        facts describe the WSL distribution and every task gated on Windows is skipped. That is why
        these phases exist and why none of them goes through the playbook. See
        docs/regression_ledger.md.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [string[]] $OnlyKeys,
        [hashtable] $ToggleOverride
    )

    Write-Section 'Installing Windows software'
    $windowsResult = Invoke-WindowsSoftwareInstall -AnsibleDir $AnsibleDir -OnlyKeys $OnlyKeys -ToggleOverride $ToggleOverride
    Show-WindowsSoftwareResult -Result $windowsResult
    $npmResult    = Invoke-AndShowNpmTools        -OnlyKeys $OnlyKeys -ToggleOverride $ToggleOverride
    $customResult = Invoke-AndShowCustomInstalls  -OnlyKeys $OnlyKeys -ToggleOverride $ToggleOverride

    # After the installs, because the Android variables point at what the Android SDK install just
    # wrote and JAVA_HOME is set by the Java install above.
    $envResult    = Invoke-AndShowDevEnvironment

    # After the software, because enabling an optional feature can ask for a reboot and there is no
    # reason to make the packages wait behind that.
    Write-Section 'Applying Windows system settings'
    $settingsResult = Invoke-AndShowWindowsSettings -OnlyKeys $OnlyKeys -ToggleOverride $ToggleOverride

    # Last, and the only thing left that touches WSL at all.
    Write-Section 'Installing Ansible inside WSL'
    $wslResult = Invoke-AndShowWslAnsible

    $phases = [ordered]@{}
    $phases['Windows packages']               = $windowsResult
    $phases['CLI tools']                      = $npmResult
    $phases['SDKs and standalone installers'] = $customResult
    $phases['Environment variables']          = $envResult
    $phases['Windows system settings']        = $settingsResult
    $phases['Ansible inside WSL']             = $wslResult
    return $phases
}

function Show-ResolvedPlan {
    <#
    .SYNOPSIS
        Prints what this run would install and apply, phase by phase, and does none of it.
    .DESCRIPTION
        The Windows answer to the bash wizard's --print-command. There is no playbook command to
        print, because this wizard no longer runs the playbook, so printing one would describe a run
        that does not happen. The resolved set is the honest answer instead: the same toggle map, the
        same package mappings and the same per-phase key lists the phases themselves read, so what
        this prints and what a real run does cannot come from two different places.

        Nothing here touches winget, Chocolatey, npm, DISM or the network, which is what makes it safe
        to run first and cheap enough for a pipeline to run on every change. It therefore says what
        would be attempted, not what is already installed: only the run itself can tell those apart.

        Write-Output rather than Write-Host, for the same reason as Show-SoftwareList.
    #>
    [CmdletBinding()]
    param([hashtable] $ToggleOverride)

    $softwareToggles = Get-WindowsSoftwareToggle -AllVarsPath $AllVars -WindowsVarsPath $WindowsVars -ToggleOverride $ToggleOverride
    $settingToggles  = Get-WindowsGroupVarToggle -AllVarsPath $AllVars -WindowsVarsPath $WindowsVars -ToggleOverride $ToggleOverride
    $mappings        = Get-WindowsSoftwareMapping -WindowsMappingPath (Join-Path $AnsibleDir 'vars\Windows.yaml')
    $plan            = Resolve-WindowsSoftwarePlan -Toggles $softwareToggles -Mappings $mappings

    # The three later phases own their own key lists and each exposes it, so this asks them instead
    # of restating what they handle. A restated list is how a toggle comes to be reported as planned
    # by one file and ignored by another.
    $npmPackages = Get-NpmToolPackage

    $wantedNpm     = @(@($npmPackages.Keys)             | Where-Object { $softwareToggles.ContainsKey($_) -and $softwareToggles[$_] })
    $wantedCustom  = @(@(Get-WindowsCustomInstallKey)   | Where-Object { $softwareToggles.ContainsKey($_) -and $softwareToggles[$_] })
    $wantedSetting = @(@(Get-WindowsSettingKey)         | Where-Object { $settingToggles.ContainsKey($_)  -and $settingToggles[$_] })

    $baseline = if ($Software) { $Software } else { 'defaults' }
    $enabled  = @(Split-KeyList -Value $EnableKey)
    $disabled = @(Split-KeyList -Value $DisableKey)

    Write-Output 'Resolved plan. Nothing was installed and nothing was changed.'
    Write-Output ''
    Write-Output "  Baseline: $baseline"
    Write-Output "  Turned on by -EnableKey:   $(if ($enabled.Count)  { $enabled  -join ', ' } else { '(none)' })"
    Write-Output "  Turned off by -DisableKey: $(if ($disabled.Count) { $disabled -join ', ' } else { '(none)' })"
    if ($Profile) {
        Write-Output "  -Profile '$Profile' selects nothing here: the profiles are Ansible variable overrides for the Linux side."
    }
    Write-Output ''

    Write-Output "  Windows packages, winget and Chocolatey ($($plan.Planned.Count)):"
    if ($plan.Planned.Count -eq 0) { Write-Output '    (none)' }
    foreach ($item in $plan.Planned) {
        Write-Output ('    {0,-28} {1,-7} {2}' -f $item.Key, $item.Manager, $item.Package)
    }
    Write-Output ''

    Write-Output "  Enabled with no Windows package mapping, so nothing would install them ($($plan.Unmapped.Count)):"
    if ($plan.Unmapped.Count -eq 0) { Write-Output '    (none)' }
    foreach ($key in $plan.Unmapped) { Write-Output "    $key" }
    Write-Output ''

    Write-Output "  CLI tools from npm ($($wantedNpm.Count)):"
    if ($wantedNpm.Count -eq 0) { Write-Output '    (none)' }
    foreach ($key in $wantedNpm) {
        Write-Output ('    {0,-28} {1}' -f $key, $npmPackages[$key].Package)
    }
    Write-Output ''

    Write-Output "  SDKs and standalone installers ($($wantedCustom.Count)):"
    if ($wantedCustom.Count -eq 0) { Write-Output '    (none)' }
    foreach ($key in $wantedCustom) { Write-Output "    $key" }
    Write-Output ''

    Write-Output "  Windows system settings ($($wantedSetting.Count)):"
    if ($wantedSetting.Count -eq 0) { Write-Output '    (none)' }
    foreach ($key in $wantedSetting) {
        if ($key -eq 'enable_hyperv') {
            Write-Output "    $key -> $((Get-WindowsOptionalFeatureName) -join ', ')"
            continue
        }
        Write-Output "    $key"
    }
    Write-Output ''

    # Neither of these is a toggle, so no selection option can change them. Printed because they are
    # things the run does, and a plan that leaves them out would understate it.
    if ($SkipSystemUpgrade) {
        Write-Output '  Upgrade of the already-installed packages: skipped (-SkipSystemUpgrade).'
    } else {
        Write-Output '  Upgrade of the already-installed packages: winget upgrade --all, then choco upgrade all.'
    }
    Write-Output '  Ansible inside WSL: installed if a distribution is registered and it is not there yet.'
}

function Invoke-Main {
    Assert-NotAdmin
    Assert-AnsibleDir

    # Everything the options decide is worked out here, before anything can change the machine, and
    # the refusal is called from here rather than from inside the resolver, on the main path, for the
    # reason Assert-KnownSelectionKey documents. -ListSoftware and -PrintPlan also answer from here,
    # before the system upgrade, so asking what a run would do never upgrades every winget and
    # Chocolatey package on the machine first.
    $selectable = Get-SelectableToggle

    # Before the refusal, and deliberately: this is the answer the refusal tells the user to ask for,
    # so a wrong key in the same command line must not be able to swallow it.
    if ($ListSoftware) {
        Show-SoftwareList -Selectable $selectable
        exit 0
    }

    Assert-KnownSelectionKey -ParameterName '-EnableKey'  -Key $EnableKey  -Selectable $selectable
    Assert-KnownSelectionKey -ParameterName '-DisableKey' -Key $DisableKey -Selectable $selectable

    # Null means no selection option was passed, which is what keeps the interactive path reachable
    # and group_vars untouched. Anything else is a scripted selection, and a scripted selection
    # cannot be asked to confirm itself at a prompt.
    $toggleOverride = Resolve-ToggleOverride -Selectable $selectable -Baseline $Software `
        -EnableKey $EnableKey -DisableKey $DisableKey

    if ($PrintPlan) {
        Show-ResolvedPlan -ToggleOverride $toggleOverride
        exit 0
    }

    Set-Theme
    Write-Banner
    Write-Section 'Bootstrapping'

    Invoke-WindowsSystemUpgrade

    $selectedSoftwareKeys = $null

    if ($NonInteractive -or $Profile -or $null -ne $toggleOverride) {
        # Skipping the prompts is not the same as wanting half a run, so everything still happens.
        if ($Profile) {
            Write-Hint "  -Profile '$Profile' selects nothing here. The profiles are Ansible variable overrides for the Linux side, this wizard configures Windows, and it is accepted only so the documented command still runs."
        }
    } else {
        Install-ConsoleGuiTools
        Write-Status 'Ready.'

        $selectedSoftwareKeys = Get-SoftwareSelection -Selectable $selectable

        Write-Section 'Step 2/2 — Confirm and Run'
        Write-Hint '  Windows software is installed natively with winget and Chocolatey.'
        Write-Hint '  Then the four Windows system settings, and Ansible inside WSL.'
        $confirmed = Show-YesNo `
            -Title  'Confirm' `
            -Prompt 'Configure Windows now. Proceed?' `
            -DefaultYes $true

        if (-not $confirmed) {
            Write-Hint '  Cancelled.'; exit 0
        }

        Set-Theme
        Write-Banner
    }

    $phases = Invoke-WindowsRun -OnlyKeys $selectedSoftwareKeys -ToggleOverride $toggleOverride

    # Always, and last. Every phase names its own failures as it goes, and a long run scrolls them
    # off the screen, so this is the one block that reconciles all of them in one place.
    $failed = Write-RunSummary -Phase $phases

    # Then the machine's own answer, which is a different question from the one above. The summary
    # says what the installers reported, this says what is actually here, and the gap between those
    # two is where every silent failure in docs/regression_ledger.md lived.
    #
    # Handed exactly the selection the run was given, from the same two variables the phases were
    # handed, so an application the user unticked is reported as not requested rather than demanded
    # and reported missing.
    #
    # Not run under -WhatIf, and that is not a way out of verifying. A dry run installed nothing, so
    # every application it named would come back missing and a plan that did what it promised would
    # exit non-zero. The reason is said out loud rather than skipped quietly.
    $verifyFailed = 0
    if ($WhatIfPreference) {
        Write-Section 'Verifying what actually landed'
        Write-Hint '  Skipped: -WhatIf installed nothing, so there is nothing this machine could be asked about yet.'
    } else {
        $verification = Invoke-AndShowVerification -OnlyKeys $selectedSoftwareKeys -ToggleOverride $toggleOverride
        $verifyFailed = $verification.Failed.Count
    }

    # The install's own status wins when it is non-zero, and a happy verification never erases it,
    # which is the same order finish_run uses on the Unix side. A verification failure on a run that
    # otherwise succeeded gets its own code, so a caller can tell "the install broke" from "the
    # install claimed success and the machine disagrees".
    if ($failed -gt 0) {
        if ($verifyFailed -gt 0) {
            Write-Host "  [!] The run reported $failed failure(s) and the verification found $verifyFailed item(s) missing." -ForegroundColor Red
        }
        exit 1
    }
    if ($verifyFailed -gt 0) {
        Write-Host "  [!] Every phase reported success and the machine disagrees about $verifyFailed item(s). Exiting 3." -ForegroundColor Red
        exit 3
    }
    exit 0
}

Invoke-Main
