#!/usr/bin/env pwsh
#Requires -Version 7

$ErrorActionPreference = 'Stop'

$ScriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$AnsibleDir = Join-Path $ScriptDir 'ansible'
$AllVars    = Join-Path $AnsibleDir 'group_vars\all.yaml'
$LinuxVars  = Join-Path $AnsibleDir 'group_vars\linux.yaml'

$ExcludedVars = @(
    'non_root_user', 'non_root_home', 'allow_callback_failure',
    'default_wallpaper', 'set_custom_wallpaper'
)

# ---------------------------------------------------------------------------
# Theme
# ---------------------------------------------------------------------------

function Set-Theme {
    [Console]::BackgroundColor = [ConsoleColor]::Black
    [Console]::ForegroundColor = [ConsoleColor]::DarkGreen
    Clear-Host
}

function Write-Banner {
    $w = [Math]::Max(60, [Console]::WindowWidth)
    $border = '=' * $w
    Write-Host $border -ForegroundColor Green
    $t1 = '  INSTALLATION HELPER SETUP  '
    $t2 = '  Ansible Deployment Wizard  '
    Write-Host $t1.PadRight($w) -ForegroundColor Green
    Write-Host $t2.PadRight($w) -ForegroundColor DarkGreen
    Write-Host $border -ForegroundColor Green
    Write-Host
}

function Write-Section {
    param([string]$Title)
    Write-Host
    Write-Host "  >> $Title" -ForegroundColor Green
    Write-Host ("  " + ("-" * ($Title.Length + 4))) -ForegroundColor DarkGreen
    Write-Host
}

function Write-Hint {
    param([string]$Text)
    Write-Host "  $Text" -ForegroundColor DarkGreen
}

function Write-Status {
    param([string]$Text)
    Write-Host "  [*] $Text" -ForegroundColor Green
}

function Write-Err {
    param([string]$Text)
    Write-Host "  [!] $Text" -ForegroundColor Red
    exit 1
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
        Write-Err 'WSL is not installed or not running. Run: wsl --install'
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

function Ensure-AnsibleInWsl {
    $null = wsl bash -c 'command -v ansible-playbook' 2>&1
    if ($LASTEXITCODE -ne 0) {
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
}

function Install-Collections {
    param([string]$WslAnsibleDir)
    Write-Status 'Installing Ansible collections...'
    wsl bash -c "ansible-galaxy collection install -r '$WslAnsibleDir/requirements.yaml'"
    if ($LASTEXITCODE -ne 0) { Write-Err 'Failed to install Ansible collections.' }
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

# ---------------------------------------------------------------------------
# TUI components
# ---------------------------------------------------------------------------

function Show-Radiolist {
    param(
        [string]   $Title,
        [string]   $Prompt,
        [string[]] $Options,
        [string[]] $Labels,
        [int]      $DefaultIndex = 0
    )

    $current = $DefaultIndex
    $w       = [Math]::Max(60, [Console]::WindowWidth)

    Set-Theme
    Write-Banner
    Write-Section $Title
    Write-Hint $Prompt
    Write-Hint '  arrow keys navigate  |  Enter select  |  Esc cancel'
    Write-Host

    $startRow = [Console]::CursorTop

    while ($true) {
        [Console]::SetCursorPosition(0, $startRow)

        for ($i = 0; $i -lt $Options.Length; $i++) {
            $marker = if ($i -eq $current) { ' (*) ' } else { ' ( ) ' }
            $line   = "$marker$($Labels[$i])"
            $pad    = ' ' * [Math]::Max(0, $w - $line.Length - 1)
            if ($i -eq $current) {
                Write-Host "$line$pad" -ForegroundColor Black -BackgroundColor Green
            } else {
                Write-Host "$line$pad" -ForegroundColor DarkGreen -BackgroundColor Black
            }
        }

        $key = [Console]::ReadKey($true)
        switch ($key.Key) {
            'UpArrow'   { if ($current -gt 0) { $current-- } }
            'DownArrow' { if ($current -lt $Options.Length - 1) { $current++ } }
            'Enter'     { Write-Host; return $Options[$current] }
            'Escape'    { Write-Host; return $null }
        }
    }
}

function Show-YesNo {
    param(
        [string] $Title,
        [string] $Prompt,
        [bool]   $DefaultYes = $true
    )

    $current = if ($DefaultYes) { 0 } else { 1 }
    $w       = [Math]::Max(60, [Console]::WindowWidth)

    Set-Theme
    Write-Banner
    Write-Section $Title
    Write-Hint $Prompt
    Write-Hint '  arrow keys navigate  |  Enter select  |  Y / N keys'
    Write-Host

    $startRow = [Console]::CursorTop

    while ($true) {
        [Console]::SetCursorPosition(0, $startRow)

        $yesStyle = if ($current -eq 0) { @{ Fg = 'Black'; Bg = 'Green'     } } else { @{ Fg = 'DarkGreen'; Bg = 'Black' } }
        $noStyle  = if ($current -eq 1) { @{ Fg = 'Black'; Bg = 'Green'     } } else { @{ Fg = 'DarkGreen'; Bg = 'Black' } }

        Write-Host -NoNewline '  '
        Write-Host -NoNewline '  YES  ' -ForegroundColor $yesStyle.Fg -BackgroundColor $yesStyle.Bg
        Write-Host -NoNewline '    '
        Write-Host -NoNewline '   NO  ' -ForegroundColor $noStyle.Fg  -BackgroundColor $noStyle.Bg
        Write-Host (' ' * [Math]::Max(0, $w - 24))

        $key  = [Console]::ReadKey($true)
        $char = $key.KeyChar.ToString().ToLower()
        switch ($key.Key) {
            'LeftArrow'  { $current = 0 }
            'RightArrow' { $current = 1 }
            'UpArrow'    { $current = 0 }
            'DownArrow'  { $current = 1 }
            'Enter'      { Write-Host; return ($current -eq 0) }
            'Escape'     { Write-Host; return $DefaultYes }
        }
        if ($char -eq 'y') { Write-Host; return $true  }
        if ($char -eq 'n') { Write-Host; return $false }
    }
}

function Show-Checklist {
    param(
        [string]           $Title,
        [string]           $Prompt,
        [PSCustomObject[]] $Items
    )

    if ($Items.Length -eq 0) { return @() }

    [bool[]] $states = $Items | ForEach-Object { $_.Enabled }
    $current         = 0
    $w               = [Math]::Max(60, [Console]::WindowWidth)
    $pageSize        = [Math]::Max(5, [Console]::WindowHeight - 12)
    $scrollOffset    = 0
    $total           = $Items.Length

    Set-Theme
    Write-Banner
    Write-Section $Title
    Write-Hint $Prompt
    Write-Hint '  arrow keys navigate  |  Space toggle  |  Enter confirm  |  Esc cancel'
    Write-Host

    $startRow = [Console]::CursorTop

    while ($true) {
        if ($current -lt $scrollOffset) { $scrollOffset = $current }
        if ($current -ge $scrollOffset + $pageSize) { $scrollOffset = $current - $pageSize + 1 }

        $enabledCount = ($states | Where-Object { $_ }).Count

        [Console]::SetCursorPosition(0, $startRow)

        # Scroll up indicator
        $upArrow = if ($scrollOffset -gt 0) { "  ^ $scrollOffset more above ^" } else { '' }
        Write-Host $upArrow.PadRight($w) -ForegroundColor DarkGreen -BackgroundColor Black

        # Visible items
        $visibleEnd = [Math]::Min($scrollOffset + $pageSize, $total)
        for ($i = $scrollOffset; $i -lt $visibleEnd; $i++) {
            $isSelected = ($i -eq $current)
            $isChecked  = $states[$i]

            $checkbox   = if ($isChecked) { '[X]' } else { '[ ]' }
            $line       = "  $checkbox  $($Items[$i].Key)"
            $pad        = ' ' * [Math]::Max(0, $w - $line.Length - 1)

            if ($isSelected -and $isChecked) {
                Write-Host "$line$pad" -ForegroundColor Black -BackgroundColor Green
            } elseif ($isSelected) {
                Write-Host "$line$pad" -ForegroundColor Black -BackgroundColor DarkGreen
            } elseif ($isChecked) {
                Write-Host "$line$pad" -ForegroundColor Green -BackgroundColor Black
            } else {
                Write-Host "$line$pad" -ForegroundColor DarkGreen -BackgroundColor Black
            }
        }

        # Blank padding to keep layout stable
        for ($i = $visibleEnd - $scrollOffset; $i -lt $pageSize; $i++) {
            Write-Host (' ' * ($w - 1)) -BackgroundColor Black
        }

        # Scroll down indicator
        $remaining = $total - $scrollOffset - $pageSize
        $downArrow = if ($remaining -gt 0) { "  v $remaining more below v" } else { '' }
        Write-Host $downArrow.PadRight($w) -ForegroundColor DarkGreen -BackgroundColor Black

        # Status bar
        $statusLine = "  Selected: $enabledCount / $total   Item: $($current + 1)"
        Write-Host $statusLine.PadRight($w) -ForegroundColor Green -BackgroundColor Black

        $key = [Console]::ReadKey($true)
        switch ($key.Key) {
            'UpArrow'   { if ($current -gt 0) { $current-- } }
            'DownArrow' { if ($current -lt $total - 1) { $current++ } }
            'PageUp'    { $current = [Math]::Max(0, $current - $pageSize) }
            'PageDown'  { $current = [Math]::Min($total - 1, $current + $pageSize) }
            'Home'      { $current = 0 }
            'End'       { $current = $total - 1 }
            'Spacebar'  { $states[$current] = -not $states[$current] }
            'Enter' {
                Write-Host
                return 0..($total - 1) | Where-Object { $states[$_] } | ForEach-Object { $Items[$_].Key }
            }
            'Escape' { Write-Host; return $null }
        }
    }
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

function Main {
    Assert-NotAdmin
    Assert-Wsl
    Assert-AnsibleDir

    Set-Theme
    Write-Banner
    Write-Section 'Bootstrapping'

    $wslAnsibleDir = ConvertTo-WslPath $AnsibleDir
    Ensure-AnsibleInWsl
    Install-Collections -WslAnsibleDir $wslAnsibleDir
    Write-Status 'Ready.'

    $extraVars = [System.Collections.Generic.List[string]]::new()

    # --- Desktop environment ---
    $deChoice = Show-Radiolist `
        -Title        'Desktop Environment' `
        -Prompt       'Select desktop environment to install (runs inside WSL):' `
        -Options      @('none', 'kde', 'gnome') `
        -Labels       @('No desktop environment', 'KDE Plasma (Wayland)', 'GNOME') `
        -DefaultIndex 0

    if ($null -eq $deChoice) {
        Set-Theme; Write-Banner; Write-Hint '  Cancelled.'; exit 0
    }

    $configureDe = $false
    if ($deChoice -ne 'none') {
        $configureDe = Show-YesNo `
            -Title      'Configure Desktop' `
            -Prompt     "Also configure $($deChoice.ToUpper()) after installation?" `
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

    # --- Optional task review ---
    $reviewTasks = Show-YesNo `
        -Title      'Task Review' `
        -Prompt     'Review and customise software toggles before running?' `
        -DefaultYes $false

    if ($reviewTasks) {
        $seenKeys   = [System.Collections.Generic.HashSet[string]]::new()
        $allToggles = [System.Collections.Generic.List[PSCustomObject]]::new()

        foreach ($item in (Read-Toggles $AllVars))   { if ($seenKeys.Add($item.Key)) { $allToggles.Add($item) } }
        foreach ($item in (Read-Toggles $LinuxVars)) { if ($seenKeys.Add($item.Key)) { $allToggles.Add($item) } }

        $deOverrideKeys = $extraVars | ForEach-Object { ($_ -split '=')[0] }
        $checklistItems = @($allToggles | Where-Object { $_.Key -notin $deOverrideKeys })

        $selectedKeys = Show-Checklist `
            -Title  'Software Selection' `
            -Prompt 'Toggle what to install, then press Enter to confirm.' `
            -Items  $checklistItems

        if ($null -eq $selectedKeys) {
            Set-Theme; Write-Banner; Write-Hint '  Cancelled.'; exit 0
        }

        foreach ($item in $checklistItems) {
            $extraVars.Add("$($item.Key)=$(($item.Key -in $selectedKeys).ToString().ToLower())")
        }
    }

    # --- Confirm and run ---
    $extraVarsStr = $extraVars -join ' '
    $ansibleCmd   = "ansible-playbook $wslAnsibleDir/site.yaml -i localhost, -c local -K"
    if ($extraVarsStr) { $ansibleCmd += " --extra-vars `"$extraVarsStr`"" }

    $confirmed = Show-YesNo `
        -Title      'Confirm' `
        -Prompt     "Ready to run Ansible playbook via WSL. Proceed?" `
        -DefaultYes $true

    if (-not $confirmed) {
        Set-Theme; Write-Banner; Write-Hint '  Cancelled.'; exit 0
    }

    Set-Theme
    Write-Banner
    Write-Section 'Running Playbook'
    Write-Status "Command: $ansibleCmd"
    Write-Host
    wsl bash -c $ansibleCmd
}

Main
