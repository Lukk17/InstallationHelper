#!/usr/bin/env pwsh
#Requires -Version 7

<#
.SYNOPSIS
    Installation Helper bootstrap wizard for Windows (WSL backend).
.DESCRIPTION
    Detects WSL, ensures Ansible inside the default distro, then runs the
    playbook with optional desktop-environment and software selection.
    Uses Microsoft.PowerShell.ConsoleGuiTools (Out-ConsoleGridView) for
    rich multi-select pickers with filter-as-you-type.
.PARAMETER Profile
    Name of a preset profile under setup/ansible/profiles/. When given,
    skips interactive selection and applies the profile directly.
.PARAMETER NonInteractive
    Use group_vars defaults; never prompt.
.PARAMETER NoColor
    Disable themed output (also honored via $env:NO_COLOR).
.PARAMETER SkipSystemUpgrade
    Do not run the full system upgrade inside WSL before the playbook.
.PARAMETER PasswordlessSudo
    Drop Ansible's -K, so it does not prompt for a sudo password. Only correct on a WSL
    distribution whose account has a NOPASSWD sudo rule, which in practice means a hosted
    runner. Omitted by default, and omitting it keeps the prompt exactly as it has always been.
.EXAMPLE
    .\setup.ps1
.EXAMPLE
    .\setup.ps1 -Profile linux_live -NonInteractive
.EXAMPLE
    .\setup.ps1 -NonInteractive -PasswordlessSudo
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string] $Profile,
    [switch] $NonInteractive,
    [switch] $NoColor,
    [switch] $SkipSystemUpgrade,

    # Drops Ansible's -K from the WSL call, for a WSL distribution whose account has a NOPASSWD
    # sudo rule, which in practice means a hosted runner. Absent by default, so every existing
    # invocation keeps prompting for the sudo password exactly as it always has. Explicit rather
    # than auto-detected on purpose: privilege behaviour should not change because of something
    # the script noticed about its environment.
    [switch] $PasswordlessSudo
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$AnsibleDir = Join-Path $ScriptDir 'ansible'
$AllVars    = Join-Path $AnsibleDir 'group_vars\all.yaml'
$LinuxVars  = Join-Path $AnsibleDir 'group_vars\linux.yaml'
$WindowsVars = Join-Path $AnsibleDir 'group_vars\windows.yaml'
$ProfilesDir = Join-Path $AnsibleDir 'profiles'

# Native Windows installation. Kept in its own file so it can be tested without driving the
# whole wizard, and because Ansible cannot do this job from here at all: it runs inside WSL
# against localhost, so its facts describe the WSL distribution rather than Windows.
. (Join-Path $ScriptDir 'windows\WindowsSoftware.ps1')
. (Join-Path $ScriptDir 'windows\WindowsNpmTools.ps1')
. (Join-Path $ScriptDir 'windows\WindowsCustomInstalls.ps1')

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
    'import_hibernate_task' = 'System: scheduled task to hibernate at 2 AM (Windows)'
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
    if (-not $script:UseColor) { Clear-Host; return }
    [Console]::BackgroundColor = [ConsoleColor]::Black
    [Console]::ForegroundColor = [ConsoleColor]::DarkGreen
    Clear-Host
}

function Write-Banner {
    $w = [Math]::Max(60, [Console]::WindowWidth)
    $border = '=' * $w
    Write-Host $border -ForegroundColor Green
    Write-Host '  INSTALLATION HELPER SETUP'.PadRight($w) -ForegroundColor Green
    Write-Host '  Ansible Deployment Wizard'.PadRight($w) -ForegroundColor DarkGreen
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
    param([string[]] $OnlyKeys)

    $toggles = Get-WindowsSoftwareToggle `
        -AllVarsPath     (Join-Path $AnsibleDir 'group_vars\all.yaml') `
        -WindowsVarsPath (Join-Path $AnsibleDir 'group_vars\windows.yaml')

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
        Java, Node, Flutter, Gridcoin and Razer Cortex. Separate from the mapping pass because each
        needs more than one package, or no package exists at all. See
        setup/windows/WindowsCustomInstalls.ps1 for what each one does and why.
    #>
    param([string[]] $OnlyKeys)

    $toggles = Get-WindowsSoftwareToggle `
        -AllVarsPath     (Join-Path $AnsibleDir 'group_vars\all.yaml') `
        -WindowsVarsPath (Join-Path $AnsibleDir 'group_vars\windows.yaml')

    $r = Invoke-WindowsCustomInstall -Toggles $toggles -OnlyKeys $OnlyKeys `
        -VersionsPath (Join-Path $AnsibleDir 'group_vars\versions.yaml')

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

    Write-Status "Windows packages: $($Result.Installed.Count) installed, $($Result.Present.Count) already present, $($Result.Failed.Count) failed"

    foreach ($f in $Result.Failed) {
        Write-Host "  [!] $($f.Key) ($($f.Package)) via $($f.Manager): $($f.Detail)" -ForegroundColor Red
    }

    if ($Result.Unmapped.Count -gt 0) {
        Write-Hint "  $($Result.Unmapped.Count) enabled toggle(s) have no Windows package mapping and were not installed:"
        Write-Hint "    $($Result.Unmapped -join ', ')"
        Write-Hint '  Some of those are Linux-only by design. The rest are handled by Ansible roles that cannot run on Windows yet, see docs/regression_ledger.md.'
    }
}

# ---------------------------------------------------------------------------
# Guards
# ---------------------------------------------------------------------------

function Assert-NotAdmin {
    $principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Err 'Do not run as Administrator. Run as your regular user.'
    }
}

function Assert-Wsl {
    $null = wsl --status 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Err 'WSL is not installed. Run: wsl --install -d Ubuntu'
    }
    $distros = (wsl --list --quiet 2>$null) -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ }
    if (-not $distros) {
        Write-Err 'WSL is installed but no Linux distro is registered. Run: wsl --install -d Ubuntu'
    }
}

function Assert-AnsibleDir {
    if (-not (Test-Path $AnsibleDir)) {
        Write-Err "Ansible directory not found at $AnsibleDir"
    }
}

# ---------------------------------------------------------------------------
# WSL helpers
# ---------------------------------------------------------------------------

function ConvertTo-WslPath {
    param([string]$WinPath)
    $result = wsl wslpath -u ($WinPath.Replace('\', '/')) 2>&1
    if ($LASTEXITCODE -ne 0) { Write-Err "Cannot convert path to WSL format: $WinPath" }
    return $result.Trim()
}

function Install-AnsibleInWsl {
    $null = wsl bash -c 'command -v ansible-playbook' 2>&1
    if ($LASTEXITCODE -eq 0) { return }
    Write-Status 'Ansible not found in WSL — detecting distro...'
    $distroId = (wsl bash -c 'source /etc/os-release 2>/dev/null; echo "${ID_LIKE:-$ID}"').Trim()
    Write-Status "Distro family: $distroId"
    if ($distroId -match 'debian|ubuntu') {
        wsl bash -c 'sudo apt-get update -q && sudo apt-get install -y software-properties-common && sudo add-apt-repository --yes --update ppa:ansible/ansible && sudo apt-get install -y ansible'
    } elseif ($distroId -match 'fedora|rhel|centos') {
        wsl bash -c 'sudo dnf install -y ansible'
    } elseif ($distroId -match 'arch') {
        wsl bash -c 'sudo pacman -S --noconfirm ansible'
    } else {
        Write-Err "Cannot auto-install Ansible for distro '$distroId'. Install manually inside WSL."
    }
}

function Invoke-WindowsSystemUpgrade {
    if ($SkipSystemUpgrade) {
        Write-Status 'Skipping Windows system upgrade (-SkipSystemUpgrade).'
        return
    }
    Write-Status 'Upgrading Windows packages before Ansible (skip with -SkipSystemUpgrade)...'

    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Write-Status 'winget: upgrading all installed packages...'
        & winget upgrade --all --accept-package-agreements --accept-source-agreements --silent --disable-interactivity
        if ($LASTEXITCODE -ne 0) {
            Write-Hint "winget exited with code $LASTEXITCODE (some packages may have no upgrade); continuing."
        }
    } else {
        Write-Hint 'winget not found; skipping winget upgrade.'
    }

    if (Get-Command choco -ErrorAction SilentlyContinue) {
        Write-Status 'chocolatey: upgrading all installed packages...'
        & choco upgrade all -y --no-progress
        if ($LASTEXITCODE -ne 0) {
            Write-Hint "choco exited with code $LASTEXITCODE; continuing."
        }
    } else {
        Write-Hint 'chocolatey not found; skipping choco upgrade.'
    }

    Write-Hint 'Windows Update (OS patches) is not triggered automatically — handled by Windows itself or Settings > Windows Update.'
}

function Install-Collections {
    param([string]$WslAnsibleDir)
    $required = (wsl bash -c "grep -E '^\s*-\s*name:\s*' '$WslAnsibleDir/requirements.yaml' | awk '{print `$NF}'") -split "`n" | Where-Object { $_ }
    $installed = (wsl bash -c "ansible-galaxy collection list 2>/dev/null | awk '/^[a-z]/{print `$1}'") -split "`n" | Where-Object { $_ }
    $missing = @($required | Where-Object { $_ -notin $installed })
    if ($missing.Count -eq 0) {
        Write-Status 'Ansible collections already installed.'
        return
    }
    Write-Status 'Installing Ansible collections...'
    wsl bash -c "ansible-galaxy collection install -r '$WslAnsibleDir/requirements.yaml'"
    if ($LASTEXITCODE -ne 0) { Write-Err 'Failed to install Ansible collections.' }
}

function Invoke-AnsiblePlaybook {
    <#
    .SYNOPSIS
        Runs the playbook inside WSL and returns its exit code.
    .DESCRIPTION
        AskBecomePass is an explicit parameter rather than a read of the script-level switch, so the
        function's behaviour is a function of its arguments alone and can be exercised without
        setting up script scope. Its default is $true, which is the historical behaviour: Ansible
        prompts for the sudo password.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $WslAnsibleDir,
        [string[]] $ExtraVars,
        [string]   $ProfileName,
        [bool]     $AskBecomePass = $true
    )
    $argList = @(
        'ansible-playbook',
        "$WslAnsibleDir/site.yaml",
        '-i', 'localhost,',
        '-c', 'local'
    )
    if ($AskBecomePass) { $argList += '-K' }
    if ($ProfileName) {
        $argList += @('-e', "@$WslAnsibleDir/profiles/$ProfileName.yaml")
    }
    if ($ExtraVars -and $ExtraVars.Count -gt 0) {
        $joined = ($ExtraVars -join ' ')
        $argList += @('--extra-vars', "`"$joined`"")
    }
    $cmd = ($argList -join ' ')
    Write-Status "Running: $cmd"
    Write-Host

    # Out-Host, not a bare call. A native command's output inside a function goes to the output
    # stream, so without this the function returned every line the playbook printed and then the
    # integer. The caller's $rc was therefore an array, `$rc -eq 0` became an array filter rather
    # than a comparison, and `exit $rc` could not convert. The exit code of the whole wizard was
    # unusable on Windows, which matters most for an unattended run where the exit code is the only
    # thing anyone reads. Out-Host also restores live streaming, which the accidental capture had
    # been suppressing.
    wsl bash -c $cmd | Out-Host
    return $LASTEXITCODE
}

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
    param([string]$FilePath)
    if (-not (Test-Path $FilePath)) { return @() }
    return Get-Content $FilePath |
        Where-Object { $_ -match '^[a-z_]+: (true|false)' } |
        Where-Object { ($_ -split ':')[0] -notin $ExcludedVars } |
        ForEach-Object {
            if ($_ -match '^([a-z_]+): (true|false)') {
                [PSCustomObject]@{ Key = $Matches[1]; Enabled = ($Matches[2] -eq 'true') }
            }
        }
}

function Get-ProfilePaths {
    if (-not (Test-Path $ProfilesDir)) { return @() }
    Get-ChildItem -Path $ProfilesDir -Filter '*.yaml' | ForEach-Object {
        $base = [IO.Path]::GetFileNameWithoutExtension($_.Name)
        $desc = 'No description'
        foreach ($line in (Get-Content $_.FullName -TotalCount 5)) {
            if ($line -match '^---$') { continue }
            if ($line -match '^#\s*(.+)$') { $desc = $Matches[1]; break }
            break
        }
        [PSCustomObject]@{
            File = $base
            Name = ((($base -split '_') | ForEach-Object { (Get-Culture).TextInfo.ToTitleCase($_) }) -join ' ')
            Description = $desc
        }
    }
}

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
        @{ N = 'Name';    E = { if ($LabelOverrides.ContainsKey($_.Key)) { $LabelOverrides[$_.Key] } else { ($_.Key -replace '^install_','' -replace '^setup_','' -replace '^configure_','' -replace '_',' ') } } }, `
        @{ N = 'Default'; E = { if ($_.Enabled) { 'ON' } else { 'off' } } }

    $selected = $rows |
        Out-ConsoleGridView `
            -Title 'Software — type to filter, Space to mark, Enter to confirm, Esc to cancel' `
            -OutputMode Multiple

    if ($null -eq $selected) { return $null }
    return @($selected.Key)
}

function Show-ProfilePicker {
    Import-Module Microsoft.PowerShell.ConsoleGuiTools -ErrorAction Stop

    $profiles = @()
    $profiles += [PSCustomObject]@{
        File = ''
        Name = 'Default'
        Description = 'All software from group_vars defaults'
    }
    $profiles += @(Get-ProfilePaths)

    $picked = $profiles |
        Select-Object Name, Description, File |
        Out-ConsoleGridView -Title 'Pick a profile' -OutputMode Single

    if ($null -eq $picked) { return $null }
    return $picked.File
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

function Invoke-Main {
    Assert-NotAdmin
    Assert-Wsl
    Assert-AnsibleDir

    Set-Theme
    Write-Banner
    Write-Section 'Bootstrapping'

    Invoke-WindowsSystemUpgrade
    $wslAnsibleDir = ConvertTo-WslPath $AnsibleDir
    Install-AnsibleInWsl
    # Pre-create Ansible tmp + fact-cache dirs inside WSL (ansible.cfg points there).
    wsl bash -c 'mkdir -p "$HOME/.ansible/tmp" "$HOME/.ansible/facts-cache"' | Out-Null
    Install-Collections -WslAnsibleDir $wslAnsibleDir

    # Non-interactive path — skip the wizard. Still installs the Windows software, because
    # skipping the prompts is not the same as wanting half a run.
    if ($NonInteractive -or $Profile) {
        Write-Section 'Installing Windows software'
        $windowsResult = Invoke-WindowsSoftwareInstall -AnsibleDir $AnsibleDir
        Show-WindowsSoftwareResult -Result $windowsResult
        $npmResult = Invoke-AndShowNpmTools
        $customResult = Invoke-AndShowCustomInstalls

        Write-Section 'Configuring the Linux environment inside WSL'
        $rc = Invoke-AnsiblePlaybook -WslAnsibleDir $wslAnsibleDir -ExtraVars @() -ProfileName $Profile -AskBecomePass (-not $PasswordlessSudo)
        $winFailed = $windowsResult.Failed.Count + $npmResult.Failed.Count + [int]$npmResult.NpmMissing + $customResult.Failed.Count
        if ($winFailed -gt 0 -and $rc -eq 0) { exit 1 }
        exit $rc
    }

    Install-ConsoleGuiTools
    Write-Status 'Ready.'

    $extraVars = [System.Collections.Generic.List[string]]::new()

    # Null means "everything the group_vars files enable". Only the customise path narrows it,
    # and the profile path deliberately does not, because the profiles are Linux overrides and
    # have nothing to say about which Windows packages you want.
    $selectedSoftwareKeys = $null

    # Step 1: Desktop environment
    $deChoice = Show-Choice `
        -Title  'Step 1/3 — Desktop Environment' `
        -Prompt 'Pick a desktop environment to install (runs inside WSL):' `
        -Options @('none', 'kde', 'gnome') `
        -HelpMessages @('No desktop environment', 'KDE Plasma (Wayland)', 'GNOME')

    $configureDe = $false
    if ($deChoice -ne 'none') {
        $configureDe = Show-YesNo `
            -Title 'Step 1/3 — Configure DE' `
            -Prompt "Also apply $($deChoice.ToUpper()) configuration after install?" `
            -DefaultYes $true
    }

    switch ($deChoice) {
        'kde' {
            $extraVars.Add('install_kde_plasma=true')
            $extraVars.Add("configure_kde_plasma=$($configureDe.ToString().ToLower())")
            $extraVars.Add('install_gnome=false')
            $extraVars.Add('configure_gnome=false')
        }
        'gnome' {
            $extraVars.Add('install_gnome=true')
            $extraVars.Add("configure_gnome=$($configureDe.ToString().ToLower())")
            $extraVars.Add('install_kde_plasma=false')
            $extraVars.Add('configure_kde_plasma=false')
        }
        'none' {
            $extraVars.Add('install_kde_plasma=false')
            $extraVars.Add('configure_kde_plasma=false')
            $extraVars.Add('install_gnome=false')
            $extraVars.Add('configure_gnome=false')
        }
    }

    # Step 2: Software selection mode
    $reviewMode = Show-Choice `
        -Title  'Step 2/3 — Software Selection' `
        -Prompt 'How would you like to choose software?' `
        -Options @('defaults', 'customise', 'profile') `
        -HelpMessages @('Use group_vars settings as-is',
                        'Open the multi-select grid to toggle individual apps',
                        'Load a preset profile')

    $profileFile = $null
    switch ($reviewMode) {
        'defaults' { }
        'customise' {
            # windows.yaml has to be in here. A run from this wizard now does two things,
            # installing Windows software natively and configuring the Linux side inside WSL,
            # so the checklist has to offer both sets. Without it the Windows-only toggles
            # never appeared, which meant a user who chose customise silently lost every
            # Windows-only application: not being on the list is indistinguishable from being
            # unticked. Windows keys are harmless in the Ansible extra vars, since the WSL run
            # has no mapping for them and skips them.
            $seenKeys   = [System.Collections.Generic.HashSet[string]]::new()
            $allToggles = [System.Collections.Generic.List[PSCustomObject]]::new()
            foreach ($item in (Read-Toggles $AllVars))     { if ($seenKeys.Add($item.Key)) { $allToggles.Add($item) } }
            foreach ($item in (Read-Toggles $WindowsVars)) { if ($seenKeys.Add($item.Key)) { $allToggles.Add($item) } }
            foreach ($item in (Read-Toggles $LinuxVars))   { if ($seenKeys.Add($item.Key)) { $allToggles.Add($item) } }

            $deOverrideKeys = $extraVars | ForEach-Object { ($_ -split '=')[0] }
            $checklistItems = @($allToggles | Where-Object { $_.Key -notin $deOverrideKeys })

            $selectedKeys = Show-SoftwarePicker -Items $checklistItems
            if ($null -eq $selectedKeys) {
                Write-Hint '  Cancelled.'; exit 0
            }

            foreach ($item in $checklistItems) {
                $extraVars.Add("$($item.Key)=$(($item.Key -in $selectedKeys).ToString().ToLower())")
            }

            # The native Windows installer keys off the bare name, without the install_ prefix
            # the checklist carries.
            $selectedSoftwareKeys = @($selectedKeys | ForEach-Object {
                if ($_ -like 'install_*') { $_.Substring('install_'.Length) } else { $_ }
            })
        }
        'profile' {
            $profileFile = Show-ProfilePicker
            if ($null -eq $profileFile) {
                Write-Hint '  Cancelled.'; exit 0
            }
            if (-not [string]::IsNullOrWhiteSpace($profileFile)) {
                $Profile = $profileFile
            }
        }
    }

    # Step 3: Confirm
    Write-Section 'Step 3/3 — Confirm and Run'
    Write-Hint '  Windows software is installed natively with winget and Chocolatey.'
    Write-Hint '  The Ansible playbook then configures the Linux environment inside WSL.'
    $confirmed = Show-YesNo `
        -Title  'Confirm' `
        -Prompt 'Install Windows software, then run the playbook inside WSL. Proceed?' `
        -DefaultYes $true

    if (-not $confirmed) {
        Write-Hint '  Cancelled.'; exit 0
    }

    Set-Theme
    Write-Banner

    # Windows software first, natively. Ansible cannot manage the Windows side from here:
    # it runs inside WSL against localhost, so its facts describe the WSL distribution and
    # every task gated on Windows is skipped. That is why this step exists and why it does
    # not go through the playbook. See docs/regression_ledger.md.
    Write-Section 'Installing Windows software'
    $windowsResult = Invoke-WindowsSoftwareInstall -AnsibleDir $AnsibleDir -OnlyKeys $selectedSoftwareKeys
    Show-WindowsSoftwareResult -Result $windowsResult
    $npmResult = Invoke-AndShowNpmTools -OnlyKeys $selectedSoftwareKeys
    $customResult = Invoke-AndShowCustomInstalls -OnlyKeys $selectedSoftwareKeys

    # Then the WSL side, which is what the playbook has always actually configured.
    Write-Section 'Configuring the Linux environment inside WSL'
    $rc = Invoke-AnsiblePlaybook -WslAnsibleDir $wslAnsibleDir -ExtraVars $extraVars.ToArray() -ProfileName $Profile -AskBecomePass (-not $PasswordlessSudo)

    # A Windows package failure must not be hidden behind a green playbook exit.
    # npm tools count toward this too, and a missing npm counts as a failure rather than a skip,
    # because the tools the user asked for are not installed either way. So do the SDKs and the
    # standalone installers, for the same reason.
    $winFailed = $windowsResult.Failed.Count + $npmResult.Failed.Count + [int]$npmResult.NpmMissing + $customResult.Failed.Count
    if ($winFailed -gt 0 -and $rc -eq 0) {
        Write-Hint "  The playbook succeeded but $winFailed Windows item(s) failed. Exiting non-zero so this is not read as a clean run."
        exit 1
    }
    exit $rc
}

Invoke-Main
