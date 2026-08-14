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
.EXAMPLE
    .\setup.ps1
.EXAMPLE
    .\setup.ps1 -Profile linux_live -NonInteractive
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string] $Profile,
    [switch] $NonInteractive,
    [switch] $NoColor,
    [switch] $SkipSystemUpgrade
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$AnsibleDir = Join-Path $ScriptDir 'ansible'
$AllVars    = Join-Path $AnsibleDir 'group_vars\all.yaml'
$LinuxVars  = Join-Path $AnsibleDir 'group_vars\linux.yaml'
$ProfilesDir = Join-Path $AnsibleDir 'profiles'

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
    param(
        [string]   $WslAnsibleDir,
        [string[]] $ExtraVars,
        [string]   $ProfileName
    )
    $argList = @(
        'ansible-playbook',
        "$WslAnsibleDir/site.yaml",
        '-i', 'localhost,',
        '-c', 'local',
        '-K'
    )
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
    wsl bash -c $cmd
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

    # Non-interactive path — skip the wizard.
    if ($NonInteractive -or $Profile) {
        $rc = Invoke-AnsiblePlaybook -WslAnsibleDir $wslAnsibleDir -ExtraVars @() -ProfileName $Profile
        exit $rc
    }

    Install-ConsoleGuiTools
    Write-Status 'Ready.'

    $extraVars = [System.Collections.Generic.List[string]]::new()

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
            $seenKeys   = [System.Collections.Generic.HashSet[string]]::new()
            $allToggles = [System.Collections.Generic.List[PSCustomObject]]::new()
            foreach ($item in (Read-Toggles $AllVars))   { if ($seenKeys.Add($item.Key)) { $allToggles.Add($item) } }
            foreach ($item in (Read-Toggles $LinuxVars)) { if ($seenKeys.Add($item.Key)) { $allToggles.Add($item) } }

            $deOverrideKeys = $extraVars | ForEach-Object { ($_ -split '=')[0] }
            $checklistItems = @($allToggles | Where-Object { $_.Key -notin $deOverrideKeys })

            $selectedKeys = Show-SoftwarePicker -Items $checklistItems
            if ($null -eq $selectedKeys) {
                Write-Hint '  Cancelled.'; exit 0
            }

            foreach ($item in $checklistItems) {
                $extraVars.Add("$($item.Key)=$(($item.Key -in $selectedKeys).ToString().ToLower())")
            }
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
    $confirmed = Show-YesNo `
        -Title  'Confirm' `
        -Prompt 'Ready to run the Ansible playbook via WSL. Proceed?' `
        -DefaultYes $true

    if (-not $confirmed) {
        Write-Hint '  Cancelled.'; exit 0
    }

    Set-Theme
    Write-Banner
    Write-Section 'Running playbook'
    $rc = Invoke-AnsiblePlaybook -WslAnsibleDir $wslAnsibleDir -ExtraVars $extraVars.ToArray() -ProfileName $Profile
    exit $rc
}

Invoke-Main
