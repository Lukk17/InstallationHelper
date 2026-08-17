#Requires -Version 7.2
<#
.SYNOPSIS
    Installs the Windows software catalogue natively, without Ansible.

.DESCRIPTION
    Ansible cannot run as a control node on Windows, so both wizards invoked the playbook
    from inside WSL as `-i localhost, -c local`. The target was therefore the WSL
    distribution and ansible_os_family reported Debian, which meant every task gated on
    Windows never ran, vars/Windows.yaml was never loaded, and all 83 Windows mappings were
    dead. What a Windows user actually got was the Debian software set installed into their
    WSL instance. See docs/regression_ledger.md.

    This file replaces that path for software installation. It reads the same YAML the
    playbook reads, so the toggles and the package mappings stay a single source of truth
    and only the executor differs. e2e/tier1/windows_mapping.sh fails if this parser and
    the YAML ever disagree.

    Dot-source it, then call Invoke-WindowsSoftwareInstall. Nothing here writes to the
    console: the caller renders, which keeps the functions testable.
#>

Set-StrictMode -Version Latest

# Reading a boolean toggle out of a group_vars file. Anchored on a bare true or false so a
# line carrying a trailing comment cannot be half-parsed, which is exactly the defect the
# bash wizard shipped for months.
$script:ToggleLinePattern = '^(?<key>[a-z0-9_]+):\s*(?<value>true|false)\s*(#.*)?$'

# Reading one mapping entry out of vars/Windows.yaml. All 83 entries are single-line and
# uniform, verified by checking that no line matching the key pattern fails this one.
$script:MappingLinePattern = '^\s{2}(?<key>[a-z0-9_]+):\s*\{\s*manager:\s*"(?<manager>[a-z_]+)"\s*,\s*package:\s*"(?<package>[^"]*)"\s*(,\s*source:\s*"(?<source>[a-z]+)"\s*)?\}'

function Get-WindowsSoftwareToggle {
    <#
    .SYNOPSIS
        Returns every install_ toggle that applies to Windows, as a key to boolean map.
    .DESCRIPTION
        group_vars/windows.yaml is layered over group_vars/all.yaml, which is the same
        precedence the playbook and both wizards use. The key is returned without its
        install_ prefix so it lines up with the mapping keys.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $AllVarsPath,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $WindowsVarsPath
    )

    $toggles = @{}
    # all.yaml first so windows.yaml can override it.
    foreach ($path in @($AllVarsPath, $WindowsVarsPath)) {
        if (-not (Test-Path -LiteralPath $path)) {
            throw "Toggle file not found: $path"
        }
        foreach ($line in (Get-Content -LiteralPath $path)) {
            if ($line -match $script:ToggleLinePattern) {
                $key = $Matches['key']
                if (-not $key.StartsWith('install_')) { continue }
                $toggles[$key.Substring('install_'.Length)] = ($Matches['value'] -eq 'true')
            }
        }
    }
    Write-Verbose "Read $($toggles.Count) install toggles"
    return $toggles
}

function Get-WindowsSoftwareMapping {
    <#
    .SYNOPSIS
        Returns the Windows package mappings as a key to descriptor map.
    .DESCRIPTION
        Throws when a line looks like a mapping entry but does not parse, rather than
        skipping it. A silently dropped mapping is a package the user asked for and did not
        get, which is the failure mode this whole file exists to end.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $WindowsMappingPath
    )

    if (-not (Test-Path -LiteralPath $WindowsMappingPath)) {
        throw "Mapping file not found: $WindowsMappingPath"
    }

    $mappings = @{}
    $lineNumber = 0
    foreach ($line in (Get-Content -LiteralPath $WindowsMappingPath)) {
        $lineNumber++
        # Skip comments and anything that is not an indented key.
        if ($line -match '^\s*#') { continue }
        if ($line -notmatch '^\s{2}[a-z0-9_]+:') { continue }

        if ($line -notmatch $script:MappingLinePattern) {
            throw "vars/Windows.yaml line ${lineNumber} looks like a mapping but does not parse, so it would be silently skipped: $line"
        }
        $mappings[$Matches['key']] = [PSCustomObject]@{
            Manager = $Matches['manager']
            Package = $Matches['package']
            Source  = if ($Matches['source']) { $Matches['source'] } else { 'winget' }
        }
    }
    Write-Verbose "Read $($mappings.Count) Windows package mappings"
    return $mappings
}

function Resolve-WindowsSoftwarePlan {
    <#
    .SYNOPSIS
        Works out what will be installed, and what was asked for with nowhere to go.
    .DESCRIPTION
        The Unmapped list is the important half. A toggle set true with no Windows mapping
        means the user asked for software, the run reports success, and the software is
        absent. Returning it explicitly lets the caller say so out loud.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [hashtable] $Toggles,
        [Parameter(Mandatory)] [hashtable] $Mappings,
        [string[]] $OnlyKeys
    )

    $planned = [System.Collections.Generic.List[object]]::new()
    $unmapped = [System.Collections.Generic.List[string]]::new()

    foreach ($key in ($Toggles.Keys | Sort-Object)) {
        if (-not $Toggles[$key]) { continue }
        # The wizard's checklist narrows the set when the user customises it.
        if ($OnlyKeys -and $key -notin $OnlyKeys) { continue }

        if ($Mappings.ContainsKey($key)) {
            $m = $Mappings[$key]
            $planned.Add([PSCustomObject]@{
                Key     = $key
                Manager = $m.Manager
                Package = $m.Package
                Source  = $m.Source
            })
        } else {
            $unmapped.Add($key)
        }
    }

    return [PSCustomObject]@{
        Planned  = $planned
        Unmapped = $unmapped
    }
}

function Get-WingetPath {
    <#
    .SYNOPSIS
        Resolves a usable winget executable.
    .DESCRIPTION
        In an interactive session the App Execution Alias is on PATH and plain winget works,
        which is the normal case here because this runs as the logged-in user. The
        WindowsApps lookup is the fallback for a session where the alias is absent.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $onPath = Get-Command -Name winget -CommandType Application -ErrorAction SilentlyContinue
    if ($onPath) { return $onPath.Source }

    $candidate = Get-ChildItem -Path "$env:ProgramFiles\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($candidate) { return $candidate.FullName }

    throw 'winget was not found. Install App Installer from the Microsoft Store, then rerun.'
}

function Test-WingetPackageInstalled {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)] [string] $WingetPath,
        [Parameter(Mandatory)] [string] $PackageId
    )

    # Native non-zero exits must not throw here: "not installed" is an answer, not a fault.
    $previous = $PSNativeCommandUseErrorActionPreference
    try {
        $PSNativeCommandUseErrorActionPreference = $false
        & $WingetPath list --exact --id $PackageId --accept-source-agreements *> $null
        return ($LASTEXITCODE -eq 0)
    } finally {
        $PSNativeCommandUseErrorActionPreference = $previous
    }
}

function Install-WingetPackage {
    <#
    .SYNOPSIS
        Installs one winget package, skipping it when already present.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [string] $WingetPath,
        [Parameter(Mandatory)] [string] $PackageId,
        [string] $Source = 'winget'
    )

    if (Test-WingetPackageInstalled -WingetPath $WingetPath -PackageId $PackageId) {
        Write-Verbose "$PackageId already installed"
        return [PSCustomObject]@{ Package = $PackageId; Status = 'present'; Detail = '' }
    }

    if (-not $PSCmdlet.ShouldProcess($PackageId, 'winget install')) {
        return [PSCustomObject]@{ Package = $PackageId; Status = 'skipped'; Detail = 'WhatIf' }
    }

    $previous = $PSNativeCommandUseErrorActionPreference
    try {
        $PSNativeCommandUseErrorActionPreference = $false
        $output = & $WingetPath install --exact --id $PackageId --source $Source --silent `
            --accept-source-agreements --accept-package-agreements --disable-interactivity 2>&1 | Out-String
        $code = $LASTEXITCODE
    } finally {
        $PSNativeCommandUseErrorActionPreference = $previous
    }

    # winget reports an already-installed package as a failure code with a specific
    # message, so treat that text as success rather than reporting a false failure.
    if ($code -eq 0 -or $output -match 'already installed') {
        return [PSCustomObject]@{ Package = $PackageId; Status = 'installed'; Detail = '' }
    }
    return [PSCustomObject]@{
        Package = $PackageId
        Status  = 'failed'
        Detail  = "exit $code. $(($output -split "`n" | Where-Object { $_.Trim() } | Select-Object -Last 2) -join ' ')"
    }
}

function Install-ChocolateyPackageBatch {
    <#
    .SYNOPSIS
        Installs the Chocolatey packages in one elevated child process.
    .DESCRIPTION
        Chocolatey writes under C:\ProgramData and needs administrator rights, while winget
        installs per user and does not. setup.ps1 deliberately refuses to run elevated, so
        rather than demanding the whole wizard be elevated, the Chocolatey packages are
        batched into a single elevated child process. That is one consent prompt for the
        whole batch instead of one per package.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string[]] $PackageId
    )

    if (-not $PSCmdlet.ShouldProcess(($PackageId -join ', '), 'elevated choco install')) {
        return [PSCustomObject]@{ Status = 'skipped'; Detail = 'WhatIf' }
    }

    # Bootstraps Chocolatey when absent, then installs the batch. Runs in the child so the
    # bootstrap also gets the elevation it needs.
    $inner = @"
`$ErrorActionPreference = 'Stop'
if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
    Set-ExecutionPolicy Bypass -Scope Process -Force
    [System.Net.ServicePointManager]::SecurityProtocol = 3072
    Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
}
choco install $($PackageId -join ' ') -y --no-progress --limit-output
exit `$LASTEXITCODE
"@

    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($inner))

    # Already-administrator is the normal case in a container and in CI, and there
    # -Verb RunAs fails outright because it needs an interactive desktop to prompt on. Asking
    # to elevate when already elevated is also just wasted work, so check first.
    $identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
    $isElevated = ([Security.Principal.WindowsPrincipal]$identity).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)

    # -PassThru with an explicit WaitForExit rather than -Wait, so this cannot block forever. It was
    # the last unbounded blocking call in the Windows path, and it is now on the critical path for
    # install_nodejs and install_flutter as well as the mapped Chocolatey packages. Two ways it hangs:
    # choco prompting inside the elevated child despite -y, or a consent dialog nobody answers.
    # -Wait offers no timeout at all, which is why it had to go.
    $timeoutMinutes = 30
    try {
        $startArgs = @{
            FilePath     = 'pwsh.exe'
            ArgumentList = @('-NoProfile', '-NonInteractive', '-EncodedCommand', $encoded)
            PassThru     = $true
            ErrorAction  = 'Stop'
        }
        if ($isElevated) {
            Write-Verbose 'Already elevated, running choco in this process'
            $startArgs['NoNewWindow'] = $true
        } else {
            $startArgs['Verb'] = 'RunAs'
        }
        $proc = Start-Process @startArgs

        if (-not $proc.WaitForExit($timeoutMinutes * 60 * 1000)) {
            # Kill($true) takes the tree, because choco spawns msiexec and installer children that
            # would otherwise survive the parent and keep holding their locks.
            try { $proc.Kill($true) } catch { Write-Verbose "could not kill $($proc.Id): $($_.Exception.Message)" }
            return [PSCustomObject]@{
                Status = 'failed'
                Detail = "the Chocolatey batch was still running after $timeoutMinutes minutes and was killed, so those packages are NOT installed. Most likely a prompt inside the elevated child, or an unanswered consent dialog. Run 'choco install $($PackageId -join ' ') -y' by hand to see it."
            }
        }
        if ($proc.ExitCode -eq 0) {
            return [PSCustomObject]@{ Status = 'installed'; Detail = "$($PackageId.Count) package(s)" }
        }
        return [PSCustomObject]@{ Status = 'failed'; Detail = "choco exited $($proc.ExitCode)" }
    } catch {
        # A refused consent prompt lands here, and is a user decision rather than a fault.
        return [PSCustomObject]@{ Status = 'failed'; Detail = "could not run choco: $($_.Exception.Message)" }
    }
}

function Invoke-WindowsSoftwareInstall {
    <#
    .SYNOPSIS
        Installs the enabled Windows software and returns a result summary.
    .DESCRIPTION
        Returns an object rather than printing, so the caller decides how to render it and
        so this is testable. Never throws for a single package failure: one bad package must
        not abandon the other 82, and the summary names every failure so nothing is hidden.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $AnsibleDir,
        [string[]] $OnlyKeys
    )

    $toggles  = Get-WindowsSoftwareToggle `
        -AllVarsPath     (Join-Path $AnsibleDir 'group_vars\all.yaml') `
        -WindowsVarsPath (Join-Path $AnsibleDir 'group_vars\windows.yaml')
    $mappings = Get-WindowsSoftwareMapping `
        -WindowsMappingPath (Join-Path $AnsibleDir 'vars\Windows.yaml')

    $plan = Resolve-WindowsSoftwarePlan -Toggles $toggles -Mappings $mappings -OnlyKeys $OnlyKeys

    $results = [System.Collections.Generic.List[object]]::new()

    $wingetItems = @($plan.Planned | Where-Object { $_.Manager -eq 'winget' })
    if ($wingetItems.Count -gt 0) {
        $winget = Get-WingetPath
        Write-Verbose "Using winget at $winget"
        foreach ($item in $wingetItems) {
            $r = Install-WingetPackage -WingetPath $winget -PackageId $item.Package -Source $item.Source
            $results.Add([PSCustomObject]@{
                Key = $item.Key; Manager = 'winget'; Package = $item.Package
                Status = $r.Status; Detail = $r.Detail
            })
        }
    }

    $chocoItems = @($plan.Planned | Where-Object { $_.Manager -eq 'choco' })
    if ($chocoItems.Count -gt 0) {
        $batch = Install-ChocolateyPackageBatch -PackageId ($chocoItems.Package)
        foreach ($item in $chocoItems) {
            $results.Add([PSCustomObject]@{
                Key = $item.Key; Manager = 'choco'; Package = $item.Package
                Status = $batch.Status; Detail = $batch.Detail
            })
        }
    }

    return [PSCustomObject]@{
        Planned   = $plan.Planned
        Unmapped  = $plan.Unmapped
        Results   = $results
        Installed = @($results | Where-Object { $_.Status -eq 'installed' })
        Present   = @($results | Where-Object { $_.Status -eq 'present' })
        Failed    = @($results | Where-Object { $_.Status -eq 'failed' })
    }
}
