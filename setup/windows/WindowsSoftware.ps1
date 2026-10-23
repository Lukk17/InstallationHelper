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

# This file's own path, captured while it is being dot-sourced, because the elevated winget child
# dot-sources it again to run the same Invoke-BoundedWinget rather than a second copy of it.
$script:WindowsSoftwarePath = $PSCommandPath

# The installer types winget refuses to install machine-wide unless winget itself runs elevated:
# winget-cli v1.29.380, src/AppInstallerCommonCore/Manifest/ManifestCommon.cpp,
# DoesInstallerTypeRequireAdminForMachineScopeInstall, which InstallFlow.cpp's
# EnsureRunningAsAdminForMachineScopeInstall applies when --scope machine was asked for. Every other
# type starts an installer that asks for elevation itself.
$script:WingetAdminInstallerTypes = @('font', 'portable', 'msstore', 'msix')

# The two of those whose machine-wide copy is a provisioned package, which winget can only see from
# an elevated process: its installed source reads them through PackageManager.FindProvisionedPackages,
# and that call answered "Access is denied" from an unelevated shell on this machine on 2026-10-11. A
# machine-wide portable or font is in the HKLM registry, which any user can read.
$script:WingetProvisionedInstallerTypes = @('msstore', 'msix')

# The retry rule every package manager follows, read by Invoke-PackageManagerRetry. The same numbers
# as retries and delay in setup/ansible/tasks/install_role_packages.yaml.
$script:PackageRetryCount = 3
$script:PackageRetryDelaySeconds = 20

# Reading a boolean toggle out of a group_vars file. Anchored on a bare true or false so a
# line carrying a trailing comment cannot be half-parsed, which is exactly the defect the
# bash wizard shipped for months.
$script:ToggleLinePattern = '^(?<key>[a-z0-9_]+):\s*(?<value>true|false)\s*(#.*)?$'

# Reading one mapping entry out of vars/Windows.yaml. All 83 entries are single-line and
# uniform, verified by checking that no line matching the key pattern fails this one.
# scope is optional and only winget reads it. It exists because a winget manifest can carry several
# installers for one package and the client picks by scope: Bruno ships a per-user nullsoft
# installer and a machine-scope MSI, and the per-user one dies with an access violation when the
# wizard runs elevated, which is how every Windows cell of 2026-08-22 lost it.
# installer_type follows scope, and only a machine pin carries it: the installer type winget selects
# for --scope machine, which decides whether winget itself has to run elevated, see
# Test-WingetElevationRequired.
$script:MappingLinePattern = '^\s{2}(?<key>[a-z0-9_]+):\s*\{\s*manager:\s*"(?<manager>[a-z_]+)"\s*,\s*package:\s*"(?<package>[^"]*)"\s*(,\s*source:\s*"(?<source>[a-z]+)"\s*)?(,\s*scope:\s*"(?<scope>[a-z]+)"\s*)?(,\s*installer_type:\s*"(?<installertype>[a-z]+)"\s*)?(,\s*client_only:\s*(?<clientonly>true|false)\s*)?(,\s*user_context:\s*(?<usercontext>true|false)\s*)?(,\s*requires_nvidia_gpu:\s*(?<nvidia>true|false)\s*)?(,\s*verify_path:\s*"(?<verifypath>[^"]*)"\s*)?\}'

function Get-WindowsGroupVarToggle {
    <#
    .SYNOPSIS
        Returns every boolean toggle that applies to Windows, as a key to boolean map.
    .DESCRIPTION
        group_vars/windows.yaml is layered over group_vars/all.yaml, which is the same
        precedence the playbook and both wizards use. Keys come back exactly as written, so
        one parse of one pair of files serves both the install_ toggles this file dispatches
        and the system-setting toggles WindowsSettings.ps1 applies. A second hand-written
        reader of the same format would drift from this one, which is the defect the bash and
        PowerShell wizards shipped for months.

        ToggleOverride is the wizard's non-interactive selection, and it is applied last, after both
        files, because it is the caller's explicit answer and the files are only defaults. It is
        applied here rather than at each callsite for the same single-source-of-truth reason: a
        selection honoured by the software phase and dropped by the settings phase would be a run
        that installs a different set from the one it was asked for, and says nothing about it.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $AllVarsPath,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $WindowsVarsPath,

        [hashtable] $ToggleOverride
    )

    $toggles = @{}
    # all.yaml first so windows.yaml can override it.
    foreach ($path in @($AllVarsPath, $WindowsVarsPath)) {
        if (-not (Test-Path -LiteralPath $path)) {
            throw "Toggle file not found: $path"
        }
        foreach ($line in (Get-Content -LiteralPath $path)) {
            if ($line -match $script:ToggleLinePattern) {
                $toggles[$Matches['key']] = ($Matches['value'] -eq 'true')
            }
        }
    }

    if ($null -ne $ToggleOverride) {
        foreach ($key in $ToggleOverride.Keys) {
            $toggles[$key] = [bool] $ToggleOverride[$key]
        }
        Write-Verbose "Applied $($ToggleOverride.Count) toggle override(s) from the wizard's selection"
    }

    Write-Verbose "Read $($toggles.Count) boolean toggles"
    return $toggles
}

function Get-WindowsSoftwareToggle {
    <#
    .SYNOPSIS
        Returns every install_ toggle that applies to Windows, as a key to boolean map.
    .DESCRIPTION
        A filter over Get-WindowsGroupVarToggle, so the file precedence, the line pattern and the
        wizard's selection override all live in one place. The key is returned without its install_
        prefix so it lines up with the mapping keys, which is also why the override has to be applied
        before the strip rather than here: its keys are the checklist's, and the checklist carries the
        prefix.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $AllVarsPath,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $WindowsVarsPath,

        [hashtable] $ToggleOverride
    )

    $all = Get-WindowsGroupVarToggle -AllVarsPath $AllVarsPath -WindowsVarsPath $WindowsVarsPath -ToggleOverride $ToggleOverride

    $toggles = @{}
    foreach ($key in $all.Keys) {
        if (-not $key.StartsWith('install_')) { continue }
        $toggles[$key.Substring('install_'.Length)] = $all[$key]
    }
    Write-Verbose "Read $($toggles.Count) install toggles"
    return $toggles
}

# The toggle that chooses which OpenCode version the installs take. A version choice rather than a system setting,
# so WindowsSettings.ps1 does not apply it, and e2e/tier1/windows_settings.sh reads this line to tell the two apart.
$script:OpenCodeVersionToggle = 'opencode_use_v1'

function Get-OpenCodeVersion {
    <#
    .SYNOPSIS
        v1 when opencode_use_v1 is on for this run, v2 otherwise.
    .DESCRIPTION
        One answer for the npm phase, the custom installs and the verification, the way
        setup/ansible/tasks/opencode_version.yaml is the one answer on Linux and macOS. Read through
        Get-WindowsGroupVarToggle, so the file layering and the scripted selection apply to it exactly as
        to every other toggle, and narrowed by OnlyKeys like every other key the checklist offers.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $AllVarsPath,
        [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $WindowsVarsPath,
        [hashtable] $ToggleOverride,
        [string[]] $OnlyKeys
    )

    $toggles = Get-WindowsGroupVarToggle -AllVarsPath $AllVarsPath -WindowsVarsPath $WindowsVarsPath -ToggleOverride $ToggleOverride
    $useV1 = $toggles.ContainsKey($script:OpenCodeVersionToggle) -and $toggles[$script:OpenCodeVersionToggle]
    if ($OnlyKeys -and $script:OpenCodeVersionToggle -notin $OnlyKeys) {
        $useV1 = $false
    }
    if ($useV1) {
        return 'v1'
    }
    return 'v2'
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
            Scope   = if ($Matches['scope'])  { $Matches['scope'] }  else { '' }
            InstallerType = if ($Matches['installertype']) { $Matches['installertype'] } else { '' }
            # Two facts about where a package can install, rather than about what it is. Both are
            # read here so the dispatch can report "skipped, and why" instead of a failure that is
            # true of the machine rather than of the run.
            ClientOnly  = ($Matches['clientonly'] -eq 'true')
            UserContext = ($Matches['usercontext'] -eq 'true')
            RequiresNvidiaGpu = ($Matches['nvidia'] -eq 'true')
            # A path that proves the package is installed when the package manager cannot say so.
            # Empty for almost everything, because asking the manager is the better question when
            # the manager can answer.
            VerifyPath = if ($Matches['verifypath']) { $Matches['verifypath'] } else { '' }
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
                # Read defensively, because these three are optional and a caller can hand over a
                # mapping object that predates them. The Pester suite does exactly that: it builds
                # mappings by hand, and under Set-StrictMode -Version Latest reading a property that
                # is not there is a terminating error, so the plan blew up on
                # "The property 'Scope' cannot be found on this object". Third time this session
                # that an untested read of something optional has broken a run.
                Scope       = if ($m.PSObject.Properties['Scope'])       { $m.Scope }       else { '' }
                InstallerType = if ($m.PSObject.Properties['InstallerType']) { $m.InstallerType } else { '' }
                ClientOnly  = if ($m.PSObject.Properties['ClientOnly'])  { $m.ClientOnly }  else { $false }
                UserContext = if ($m.PSObject.Properties['UserContext']) { $m.UserContext } else { $false }
                RequiresNvidiaGpu = if ($m.PSObject.Properties['RequiresNvidiaGpu']) { $m.RequiresNvidiaGpu } else { $false }
                VerifyPath  = if ($m.PSObject.Properties['VerifyPath'])  { $m.VerifyPath }  else { '' }
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

function Get-WingetPackagePresence {
    <#
    .SYNOPSIS
        Whether winget lists the package as installed, optionally in one scope only, and whether it
        could be asked at all.
    .DESCRIPTION
        Scope narrows the question with `winget list --scope`, measured with winget v1.29.380 on
        2026-10-11: Git.Git installed machine-wide answers 0 for machine and 0x8A150014, no package
        found, for user, and a per-user Visual Studio Code answers the other way round. Without a
        scope a per-user copy counts as installed, which is right for a package pinned to user and
        wrong for one pinned to machine.

        Elevated runs the probe in the elevated winget child, because winget reads provisioned msix
        packages, which is where a machine-scope msix lands, through FindProvisionedPackages, an API
        its own source says has historically not been accessible unelevated
        (PredefinedInstalledSourceFactory.cpp, v1.29.380), and which answered "Access is denied"
        unelevated when measured, see $script:WingetProvisionedInstallerTypes.

        Answered is false when the elevated child never ran winget, a refused consent prompt above
        all. That is not "not installed": an already provisioned Slack then fell through to the
        per-user check, which finds the copy registered for this user, and the wizard reported it as
        installed for this user only. Refused says which of the two it was, Reason says why in words.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $WingetPath,
        [Parameter(Mandatory)] [string] $PackageId,
        [ValidateSet('', 'machine', 'user')] [string] $Scope = '',
        [switch] $Elevated
    )

    # Bounded like the install below it, and for the same reason. This runs once per package before
    # anything is installed, it talks to a remote source, and an unbounded call here hangs the run
    # just as thoroughly as an unbounded install does. A probe whose winget runs out of time answers
    # false, which is the safe direction: the worst case is that winget is asked to install something
    # that is already there, and it says so and exits.
    $arguments = @('list', '--exact', '--id', $PackageId, '--accept-source-agreements')
    if ($Scope) { $arguments += @('--scope', $Scope) }
    $run = if ($Elevated) {
        Invoke-ElevatedWinget -WingetPath $WingetPath -TimeoutSeconds 180 -Arguments $arguments
    } else {
        Invoke-BoundedWinget -WingetPath $WingetPath -TimeoutSeconds 180 -Arguments $arguments
    }

    $notRun = if ($run.PSObject.Properties['ElevationFailure']) { [string]$run.ElevationFailure } else { '' }
    if ($notRun) {
        return [PSCustomObject]@{
            Answered  = $false
            Installed = $false
            Refused   = [bool]($run.PSObject.Properties['Refused'] -and $run.Refused)
            Reason    = $notRun
        }
    }
    if ($run.TimedOut) {
        Write-Verbose "winget list for $PackageId ran out of time, treating it as not installed"
    }
    return [PSCustomObject]@{
        Answered  = $true
        Installed = (-not $run.TimedOut -and $run.ExitCode -eq 0)
        Refused   = $false
        Reason    = ''
    }
}

function Test-WingetPackageInstalled {
    <#
    .SYNOPSIS
        Whether winget lists the package as installed, optionally in one scope only, asked from this
        process, which always gets an answer.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)] [string] $WingetPath,
        [Parameter(Mandatory)] [string] $PackageId,
        [ValidateSet('', 'machine', 'user')] [string] $Scope = ''
    )

    return (Get-WingetPackagePresence -WingetPath $WingetPath -PackageId $PackageId -Scope $Scope).Installed
}

function Test-WingetElevationRequired {
    <#
    .SYNOPSIS
        Whether this winget install has to run in an elevated child rather than in this process.
    .DESCRIPTION
        True only for a machine-scope install of a type in $script:WingetAdminInstallerTypes from a
        process that is not elevated. The wizard refuses to run elevated, so on a real machine that
        is Syncthing, which winget would otherwise stop with
        APPINSTALLER_CLI_ERROR_COMMAND_REQUIRES_ADMIN before downloading anything. Already elevated,
        which is the GitHub runner, winget runs in this process as it always has.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [ValidateSet('', 'machine', 'user')] [string] $Scope = '',
        [string] $InstallerType = ''
    )

    if ($Scope -ne 'machine') { return $false }
    if ($script:WingetAdminInstallerTypes -notcontains $InstallerType) { return $false }
    # Asked last, because it is the only question that reaches the operating system.
    return (-not (Test-IsAdministrator))
}

function ConvertTo-PowerShellLiteral {
    <#
    .SYNOPSIS
        A value as a single-quoted PowerShell string, for interpolating into a child's script text.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [AllowEmptyString()] [string] $Value)

    return "'" + ($Value -replace "'", "''") + "'"
}

function Test-ConsentRefusal {
    <#
    .SYNOPSIS
        Whether an exception from Start-Process -Verb RunAs is the user saying no to the consent prompt.
    .DESCRIPTION
        ShellExecuteEx reports a refused prompt as ERROR_CANCELLED, 1223, which Start-Process wraps
        in a Win32Exception. The message is matched as well, for a host that rethrows it without the
        inner exception.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory)] [System.Exception] $Exception)

    for ($e = $Exception; $e; $e = $e.InnerException) {
        if ($e -is [System.ComponentModel.Win32Exception] -and $e.NativeErrorCode -eq 1223) { return $true }
        if ($e.Message -match 'canceled by the user|cancelled by the user') { return $true }
    }
    return $false
}

function Invoke-ElevatedPowerShell {
    <#
    .SYNOPSIS
        Runs a script in an elevated pwsh child and reports how it ended.
    .DESCRIPTION
        The one route to administrator rights for the wizard, which refuses to run elevated itself:
        the Chocolatey batch, the optional features, the elevated winget calls and the Syncthing
        firewall rules all come through here, so each call is one consent prompt of its own. The
        script goes in as -EncodedCommand, through -Verb RunAs when this process is not elevated and
        in this console when it is, because RunAs needs an interactive desktop to prompt on and a
        runner has none. -Verb RunAs cannot redirect a stream, so the script writes its own answer
        into a file the caller names. Bounded by WaitForExit rather than -Wait, so an unanswered
        consent dialog cannot hold the wizard forever, and Kill($true) takes the tree, because choco
        and DISM start installer children that would otherwise outlive the deadline.

        Returns ExitCode, TimedOut, StartError and Refused. StartError is the message when the child
        never started, and Refused is true when that was a refused consent prompt.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $Script,
        [ValidateRange(30, 86400)] [int] $TimeoutSeconds = 900
    )

    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($Script))
    $startArgs = @{
        FilePath     = 'pwsh.exe'
        ArgumentList = @('-NoProfile', '-NonInteractive', '-EncodedCommand', $encoded)
        PassThru     = $true
        ErrorAction  = 'Stop'
    }
    if (Test-IsAdministrator) {
        $startArgs['NoNewWindow'] = $true
    } else {
        $startArgs['Verb'] = 'RunAs'
    }

    try {
        $proc = Start-Process @startArgs
    } catch {
        $refused = Test-ConsentRefusal -Exception $_.Exception
        $message = if ($refused) { "the administrator consent prompt was refused ($($_.Exception.Message))" } else { $_.Exception.Message }
        return [PSCustomObject]@{ ExitCode = -1; TimedOut = $false; StartError = $message; Refused = $refused }
    }

    if (-not $proc.WaitForExit($TimeoutSeconds * 1000)) {
        try { $proc.Kill($true) } catch { Write-Verbose "could not kill $($proc.Id): $($_.Exception.Message)" }
        return [PSCustomObject]@{ ExitCode = -1; TimedOut = $true; StartError = ''; Refused = $false }
    }
    return [PSCustomObject]@{ ExitCode = $proc.ExitCode; TimedOut = $false; StartError = ''; Refused = $false }
}

function Invoke-ElevatedWinget {
    <#
    .SYNOPSIS
        Invoke-BoundedWinget, run in an elevated child, with the same three answers.
    .DESCRIPTION
        The child dot-sources this file and calls Invoke-BoundedWinget itself, so the deadline, the
        kill and the reading of both streams are one implementation rather than two, and writes the
        result as JSON for this process to read back. The child's own deadline is the one asked for,
        and this process waits five minutes longer, which is the time a person gets to answer the
        consent prompt.

        ElevationFailure is empty when winget ran in the child, and otherwise says why it did not,
        with Refused true for a refused consent prompt. A caller must not read the exit code of a
        winget that never ran as an answer about the package.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $WingetPath,
        [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string[]] $Arguments,
        [ValidateRange(30, 7200)] [int] $TimeoutSeconds = 900
    )

    $resultFile = Join-Path ([System.IO.Path]::GetTempPath()) ('installation-helper-winget-' + [guid]::NewGuid().ToString('N') + '.json')
    $argumentLiterals = ($Arguments | ForEach-Object { ConvertTo-PowerShellLiteral -Value $_ }) -join ', '
    $resultLiteral = ConvertTo-PowerShellLiteral -Value $resultFile

    $inner = @"
`$ErrorActionPreference = 'Stop'
try {
    . $(ConvertTo-PowerShellLiteral -Value $script:WindowsSoftwarePath)
    `$run = Invoke-BoundedWinget -WingetPath $(ConvertTo-PowerShellLiteral -Value $WingetPath) -TimeoutSeconds $TimeoutSeconds -Arguments @($argumentLiterals)
} catch {
    `$run = [PSCustomObject]@{ Output = "the elevated winget child failed: `$(`$_.Exception.Message)"; ExitCode = -1; TimedOut = `$false }
}
`$run | ConvertTo-Json -Compress | Set-Content -LiteralPath $resultLiteral -Encoding utf8
"@

    $notRun = { param($output, $timedOut, $refused)
        [PSCustomObject]@{ Output = $output; ExitCode = -1; TimedOut = $timedOut; ElevationFailure = $output; Refused = $refused } }

    try {
        $child = Invoke-ElevatedPowerShell -Script $inner -TimeoutSeconds ($TimeoutSeconds + 300)
        $refused = [bool]($child.PSObject.Properties['Refused'] -and $child.Refused)
        if ($child.StartError) {
            return (& $notRun "could not start winget elevated, which a machine-wide install of this package needs: $($child.StartError)" $false $refused)
        }
        if ($child.TimedOut) {
            return (& $notRun 'the elevated winget child did not finish, most likely an unanswered consent prompt' $true $false)
        }
        if (-not (Test-Path -LiteralPath $resultFile)) {
            return (& $notRun "the elevated winget child exited $($child.ExitCode) without writing a result, so what winget did is unknown" $false $false)
        }
        $read = Get-Content -LiteralPath $resultFile -Raw | ConvertFrom-Json
        return [PSCustomObject]@{
            Output           = [string]$read.Output
            ExitCode         = [int]$read.ExitCode
            TimedOut         = [bool]$read.TimedOut
            ElevationFailure = ''
            Refused          = $false
        }
    } finally {
        Remove-Item -LiteralPath $resultFile -Force -ErrorAction SilentlyContinue
    }
}

function Wait-BoundedProcess {
    <#
    .SYNOPSIS
        Waits for a started process until a deadline, and answers true only once its redirected
        output is complete as well.
    .DESCRIPTION
        Every caller that starts a program with Start-Process -RedirectStandardOutput and reads the
        files afterwards waits through this, so the rule lives in one place. On Linux and macOS,
        Start-Process copies the output into the files through .NET's asynchronous readers, and
        WaitForExit with a deadline returns when the process ends, before they have finished, so
        about one read in 140 found an empty file. So a true answer from the deadline wait is
        followed by WaitForExit with no deadline, which waits for those readers. On Windows the
        process writes the files itself and the second wait returns at once. Entry 10.183 of
        docs/regression_ledger.md.

        False means the deadline passed and the process is still running, and the caller decides
        what to do with it.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)] [ValidateNotNull()] [object] $Process,
        [Parameter(Mandatory)] [ValidateRange(1, [int]::MaxValue)] [int] $TimeoutMilliseconds
    )

    if (-not $Process.WaitForExit($TimeoutMilliseconds)) {
        return $false
    }
    $Process.WaitForExit()
    return $true
}

function Invoke-BoundedWinget {
    <#
    .SYNOPSIS
        Runs winget with a deadline and returns its output, its exit code and whether it timed out.

    .DESCRIPTION
        Two Windows cells of the sweep of 2026-08-22 were cancelled at their 150 minute ceiling, both
        of them inside the software phase, having printed nothing since the phase header. Two and a
        half hours, no output, no attribution: the transcript could not even say which package was
        being installed when it stopped. A run that can hang for hours with nothing to show for it is
        not one anybody can debug.

        So every winget call is bounded. The process is started rather than invoked through the
        pipeline, because a native command in a pipeline cannot be given a deadline: killing it needs
        the process object. Both streams go to files under the temporary directory and are read back
        after, which is also what makes the output complete rather than interleaved.

        A package that runs out of time is a failure with the reason stated, not a hang and not a
        silent pass. TimedOut is returned separately from the exit code so the caller can say which
        of the two happened.

        The files are read only after Wait-BoundedProcess says the output is complete, entry 10.183
        of docs/regression_ledger.md.

    .PARAMETER TimeoutSeconds
        The deadline. 900 by default, which is fifteen minutes for a single package: generous next to
        the couple of minutes a large installer takes, and a fraction of the job ceiling.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $WingetPath,
        [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string[]] $Arguments,
        [ValidateRange(30, 7200)] [int] $TimeoutSeconds = 900
    )

    $stdout = [System.IO.Path]::GetTempFileName()
    $stderr = [System.IO.Path]::GetTempFileName()
    try {
        $process = Start-Process -FilePath $WingetPath -ArgumentList $Arguments -PassThru -NoNewWindow `
            -RedirectStandardOutput $stdout -RedirectStandardError $stderr
        if (-not (Wait-BoundedProcess -Process $process -TimeoutMilliseconds ($TimeoutSeconds * 1000))) {
            try { $process.Kill($true) } catch { Write-Verbose "could not kill winget: $($_.Exception.Message)" }
            $null = Wait-BoundedProcess -Process $process -TimeoutMilliseconds 30000
            return [PSCustomObject]@{
                Output   = (Get-Content -LiteralPath $stdout -Raw -ErrorAction SilentlyContinue)
                ExitCode = -1
                TimedOut = $true
            }
        }
        $text = @(
            (Get-Content -LiteralPath $stdout -Raw -ErrorAction SilentlyContinue)
            (Get-Content -LiteralPath $stderr -Raw -ErrorAction SilentlyContinue)
        ) -join "`n"
        return [PSCustomObject]@{ Output = $text; ExitCode = $process.ExitCode; TimedOut = $false }
    } finally {
        Remove-Item -LiteralPath $stdout, $stderr -Force -ErrorAction SilentlyContinue
    }
}

function Get-NvidiaGraphicsAdapter {
    <#
    .SYNOPSIS
        The names of the NVIDIA display adapters this machine has, or an empty array.

    .DESCRIPTION
        Asked of the machine rather than assumed, and the answer is reported in the skip detail so a
        log says what was measured rather than what was believed. Win32_VideoController lists every
        display adapter Windows has a driver entry for, including the Microsoft Basic Display Adapter
        a virtual machine gets, so matching on the vendor name is the question that matters.

        An empty array when the query fails, which is the same answer as "no NVIDIA adapter". That is
        the safe direction: it can only turn an install into a reported skip, never a failure into a
        silent pass, and the reason travels with it.
    #>
    [CmdletBinding()]
    param()

    try {
        return @(Get-CimInstance -ClassName Win32_VideoController -ErrorAction Stop |
                 Where-Object { $_.Name -match 'NVIDIA' } |
                 ForEach-Object { $_.Name })
    } catch {
        Write-Verbose "Win32_VideoController is unreadable: $($_.Exception.Message)"
        return @()
    }
}

function Get-WindowsInstallationType {
    <#
    .SYNOPSIS
        Client, Server, or Server Core, read from the registry.

    .DESCRIPTION
        The one place the edition question is asked. Get-WindowsMachineFact here and
        Enable-WindowsFeatureSet in WindowsSettings.ps1 both call it, so a client-only package and a
        client-only optional feature are decided from the same answer. setup.ps1 dot-sources this file
        before WindowsSettings.ps1, the Pester suite and the windows_settings check load them in the
        same order, and WindowsSettings.ps1 already depends on this file for its toggles. The
        windows_pester check fails on a second InstallationType read under setup/.

        Client when the value cannot be read, on purpose. Not knowing the edition must not turn a
        real failure into a skip, and only a non-Client answer is allowed to soften one.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    try {
        $key = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' `
            -Name 'InstallationType' -ErrorAction Stop
        if ($key.InstallationType) { return [string]$key.InstallationType }
    } catch {
        Write-Verbose "InstallationType is unreadable, assuming Client: $($_.Exception.Message)"
    }
    return 'Client'
}

function Test-IsAdministrator {
    <#
    .SYNOPSIS
        Whether this process runs with an administrator token.

    .DESCRIPTION
        The one place the elevation question is asked. setup.ps1, WindowsSettings.ps1 and this file
        all call it, so they cannot disagree, and the Pester suite can mock the answer, which the
        .NET call inside cannot be. The windows_pester check fails on a second IsInRole call.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    $principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-WindowsMachineFact {
    <#
    .SYNOPSIS
        The three facts about this machine that decide whether a package can run on it.

    .DESCRIPTION
        Asked once per run and handed to Test-WindowsPackageSkip, so every caller decides from the
        same answers. None of the three changes between packages.
    #>
    [CmdletBinding()]
    param()

    return [PSCustomObject]@{
        InstallationType = Get-WindowsInstallationType
        IsElevated       = Test-IsAdministrator
        NvidiaAdapters   = @(Get-NvidiaGraphicsAdapter)
    }
}

function Test-WindowsPackageSkip {
    <#
    .SYNOPSIS
        The reason this package cannot run on this machine, or an empty string when it can.

    .DESCRIPTION
        One function, three callers: the winget loop, the Chocolatey batch and the verification. It
        exists because they disagreed. client_only and user_context were honoured in the winget loop
        only, so a Chocolatey package carrying client_only was installed anyway while the
        verification, which read the same key, reported it as not applicable. Run 32778481303 shows
        exactly that: razer-synapse-4 installed and exited 0, and the verification called it not
        applicable in the same run.

        Read defensively for the reason the rest of this file does: the Pester suite hands these
        functions mappings built by hand without the optional keys, and under
        Set-StrictMode -Version Latest an absent property is a terminating error rather than $false.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Item,
        [Parameter(Mandatory)] $Fact
    )

    $clientOnly  = if ($Item.PSObject.Properties['ClientOnly'])  { $Item.ClientOnly }  else { $false }
    $userContext = if ($Item.PSObject.Properties['UserContext']) { $Item.UserContext } else { $false }
    $needsNvidia = if ($Item.PSObject.Properties['RequiresNvidiaGpu']) { $Item.RequiresNvidiaGpu } else { $false }

    if ($clientOnly -and $Fact.InstallationType -ne 'Client') {
        return "the vendor ships this for client editions of Windows only, and this is $($Fact.InstallationType), so its installer refuses before it starts"
    }
    if ($userContext -and $Fact.IsElevated) {
        return 'its installer refuses to run from an administrator context, and this wizard was started elevated. Run the wizard as your normal user and it installs.'
    }
    if ($needsNvidia -and @($Fact.NvidiaAdapters).Count -eq 0) {
        return 'this is NVIDIA graphics software and Win32_VideoController reports no NVIDIA display adapter on this machine, so there is nothing for it to drive'
    }
    return ''
}

function Get-CommandOutputTail {
    <#
    .SYNOPSIS
        The last two lines a program wrote that carry text, joined by spaces, for a one-line failure reason.
    .DESCRIPTION
        Splits on a carriage return and line feed as well as on a line feed alone, because on Windows
        Out-String and the files Start-Process redirects into end every line with both.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([AllowNull()] [AllowEmptyString()] [string] $Text)

    return (@($Text -split '\r?\n' | Where-Object { $_.Trim() } | Select-Object -Last 2) -join ' ')
}

function Invoke-PackageManagerRetry {
    <#
    .SYNOPSIS
        Runs one package install under the retry rule every package manager on Windows shares.
    .DESCRIPTION
        The first attempt runs against whatever package list the manager already holds. After a
        failure it waits, runs the manager's own refresh, then tries again, up to Retries more
        times. $script:PackageRetryCount and $script:PackageRetryDelaySeconds are the same three
        retries twenty seconds apart that setup/ansible/tasks/install_role_packages.yaml gives apt,
        dnf and pacman, which ansible-core runs as one first attempt and up to three more.

        Attempt is a script block returning Succeeded, Final and Failure. Final stops the retries,
        for a failure a second try cannot change, such as a deadline or a refused consent prompt.
        Refresh is an optional script block returning an empty string, or the reason it failed. A
        failed refresh is reported and the retry still runs.

        Returns Package, Succeeded, Attempts, MaxAttempts, Failures, RefreshFailures, Detail and
        Outcome, the last object Attempt returned. Detail names every failure that is not the last.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $Package,
        [Parameter(Mandatory)] [scriptblock] $Attempt,
        [scriptblock] $Refresh,
        [ValidateRange(0, 10)] [int] $Retries = $script:PackageRetryCount,
        [ValidateRange(0, 300)] [int] $DelaySeconds = $script:PackageRetryDelaySeconds
    )

    $retryMaxAttempts = $Retries + 1
    $retryFailures = [System.Collections.Generic.List[string]]::new()
    $retryRefreshFailures = [System.Collections.Generic.List[string]]::new()
    $retryAttemptNumber = 0

    while ($true) {
        $retryAttemptNumber++
        $retryOutcome = & $Attempt

        if ($retryOutcome.Succeeded) {
            break
        }

        $retryFailures.Add([string]$retryOutcome.Failure)
        if ($retryOutcome.Final -or $retryAttemptNumber -ge $retryMaxAttempts) {
            break
        }

        Write-Host ("      attempt {0} of {1} for {2} failed, retrying in {3}s{4}: {5}" -f
            $retryAttemptNumber, $retryMaxAttempts, $Package, $DelaySeconds,
            $(if ($Refresh) { ' after a refresh' } else { '' }), $retryOutcome.Failure)
        if ($DelaySeconds -gt 0) { Start-Sleep -Seconds $DelaySeconds }

        if ($Refresh) {
            $retryRefreshWhy = [string](& $Refresh)
            if ($retryRefreshWhy) {
                $retryRefreshFailures.Add($retryRefreshWhy)
                Write-Host "      the refresh before attempt $($retryAttemptNumber + 1) failed, retrying anyway: $retryRefreshWhy"
            }
        }
    }

    # Earlier failures grouped by what they said, so four identical failures read as one sentence.
    $earlierCount = if ($retryOutcome.Succeeded) { $retryFailures.Count } else { $retryFailures.Count - 1 }
    $saidBy = [ordered]@{}
    for ($i = 0; $i -lt $earlierCount; $i++) {
        if (-not $saidBy.Contains($retryFailures[$i])) { $saidBy[$retryFailures[$i]] = [System.Collections.Generic.List[int]]::new() }
        $saidBy[$retryFailures[$i]].Add($i + 1)
    }
    $earlierText = (@(foreach ($said in $saidBy.Keys) {
        $numbers = @($saidBy[$said])
        $which = if ($numbers.Count -eq 1) { "attempt $($numbers[0])" } else { "attempts $(($numbers | Select-Object -SkipLast 1) -join ', ') and $($numbers[-1])" }
        "$which said $said"
    }) -join '; ')
    $detail = if ($retryOutcome.Succeeded) {
        if ($earlierCount -gt 0) { "installed on attempt $retryAttemptNumber of $retryMaxAttempts, after $earlierText" } else { '' }
    } else {
        $last = [string]$retryOutcome.Failure
        if ($earlierCount -gt 0) { "$last (attempt $retryAttemptNumber of $retryMaxAttempts; $earlierText)" } else { $last }
    }
    if ($retryRefreshFailures.Count -gt 0) {
        $detail = ("$detail The refresh before a retry failed: " + (@($retryRefreshFailures | Select-Object -Unique) -join '; ')).Trim()
    }

    return [PSCustomObject]@{
        Package         = $Package
        Succeeded       = [bool]$retryOutcome.Succeeded
        Attempts        = $retryAttemptNumber
        MaxAttempts     = $retryMaxAttempts
        Failures        = $retryFailures.ToArray()
        RefreshFailures = $retryRefreshFailures.ToArray()
        Detail          = $detail
        Outcome         = $retryOutcome
    }
}

function Invoke-InstallStepWithRetry {
    <#
    .SYNOPSIS
        Runs one install step that returns a result row under Invoke-PackageManagerRetry.
    .DESCRIPTION
        Step returns the Key, Package, Status and Detail row the custom installs and the settings
        return. A failed row is retried unless it carries Final set to true, for a failure a second
        try cannot change, such as a deadline or a missing command. Any other status ends the
        retries. Returns the last row, its Detail replaced by the retry's account of every attempt
        when there was more than one. Refresh is passed through unchanged.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $Package,
        [Parameter(Mandatory)] [scriptblock] $Step,
        [scriptblock] $Refresh,
        [ValidateRange(0, 10)] [int] $Retries = $script:PackageRetryCount,
        [ValidateRange(0, 300)] [int] $RetryPauseSeconds = $script:PackageRetryDelaySeconds
    )

    $stepOnce = {
        $stepRow = & $Step
        $stepFailed = $stepRow.Status -eq 'failed'
        $stepFinal = $stepFailed -and [bool]($stepRow.PSObject.Properties['Final'] -and $stepRow.Final)
        [PSCustomObject]@{ Succeeded = -not $stepFailed; Final = $stepFinal; Failure = [string]$stepRow.Detail; Row = $stepRow }
    }

    $retry = Invoke-PackageManagerRetry -Package $Package -Attempt $stepOnce -Refresh $Refresh `
        -Retries $Retries -DelaySeconds $RetryPauseSeconds
    $row = $retry.Outcome.Row
    if ($retry.Attempts -gt 1) { $row.Detail = $retry.Detail }
    return $row
}

function Install-WingetPackage {
    <#
    .SYNOPSIS
        Installs one winget package, skipping it when already present.
    .DESCRIPTION
        Retried through Invoke-PackageManagerRetry, refreshing the package's own source with
        `winget source update --name <source>` before each retry, the update subcommand documented
        at https://learn.microsoft.com/en-us/windows/package-manager/winget/source. The refresh runs
        in this process even when the install runs elevated, so it costs no consent prompt. Whether
        an elevated install reads the source data an unelevated refresh wrote has not been measured.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [string] $WingetPath,
        [Parameter(Mandatory)] [string] $PackageId,
        [string] $Source = 'winget',
        # Passed through to winget when the mapping names one. Empty means winget chooses, which is
        # only allowed for a package whose manifest offers no choice of scope, enforced by
        # e2e/tier1/winget_scope_pins.sh.
        [ValidateSet('', 'machine', 'user')] [string] $Scope = '',
        # The mapping's installer_type, the type winget selects for --scope machine. Read only to
        # decide whether winget has to run elevated, see Test-WingetElevationRequired.
        [string] $InstallerType = '',
        [ValidateRange(30, 7200)] [int] $TimeoutSeconds = 900,
        # The directory to install into, passed to winget as --location. Empty means the installer's own default.
        [string] $Location = '',

        # Parameters so a test can run the retries with no pause, defaulting to the shared rule.
        [ValidateRange(0, 10)] [int] $Retries = $script:PackageRetryCount,
        [ValidateRange(0, 300)] [int] $RetryPauseSeconds = $script:PackageRetryDelaySeconds
    )

    $elevated = Test-WingetElevationRequired -Scope $Scope -InstallerType $InstallerType
    # One consent prompt fewer for a portable: only a provisioned package needs the elevated probe.
    $probeElevated = $elevated -and ($script:WingetProvisionedInstallerTypes -contains $InstallerType)

    if ($Scope -eq 'machine') {
        # Asked by scope, because an unscoped `winget list` reports a per-user copy as installed, and
        # then the machine-wide install this mapping asks for never runs on any machine that already
        # had the per-user one. That was every package moved from user to machine on 2026-10-11.
        $machine = Get-WingetPackagePresence -WingetPath $WingetPath -PackageId $PackageId -Scope 'machine' -Elevated:$probeElevated
        # An unanswered machine check is reported as exactly that. Falling through to the per-user
        # check would find the copy a provisioned msix registers for every user and call it per-user.
        if (-not $machine.Answered) {
            $detail = if ($machine.Refused) {
                "the machine-wide check was refused, so whether $PackageId is installed for all users is unknown. Run the wizard again and accept the administrator prompt to check it and install it."
            } else {
                "the machine-wide check could not run, so whether $PackageId is installed for all users is unknown: $($machine.Reason)"
            }
            return [PSCustomObject]@{ Package = $PackageId; Status = 'failed'; Detail = $detail }
        }
        if ($machine.Installed) {
            Write-Verbose "$PackageId already installed machine-wide"
            return [PSCustomObject]@{ Package = $PackageId; Status = 'present'; Detail = '' }
        }
        # A per-user copy is the user's, so it is reported rather than removed, and the machine-wide
        # install is not run beside it: two copies of one application, each with its own shortcuts
        # and its own updater, is worse than either one alone.
        if (Test-WingetPackageInstalled -WingetPath $WingetPath -PackageId $PackageId -Scope 'user') {
            return [PSCustomObject]@{
                Package = $PackageId
                Status  = 'skipped'
                Detail  = "installed for this user only, the machine-wide install was skipped. To install it machine-wide, remove the per-user copy with 'winget uninstall --exact --id $PackageId --scope user' and run the wizard again."
            }
        }
    } elseif (Test-WingetPackageInstalled -WingetPath $WingetPath -PackageId $PackageId) {
        Write-Verbose "$PackageId already installed"
        return [PSCustomObject]@{ Package = $PackageId; Status = 'present'; Detail = '' }
    }

    if (-not $PSCmdlet.ShouldProcess($PackageId, 'winget install')) {
        return [PSCustomObject]@{ Package = $PackageId; Status = 'skipped'; Detail = 'WhatIf' }
    }

    $arguments = @(
        'install', '--exact', '--id', $PackageId, '--source', $Source, '--silent',
        '--accept-source-agreements', '--accept-package-agreements', '--disable-interactivity')
    if ($Scope) { $arguments += @('--scope', $Scope) }
    if ($Location) { $arguments += @('--location', $Location) }
    # A timeout is never retried. The deadline exists to stop a hang, and spending it again on one
    # package is the opposite of what it is for. An elevated child that never ran winget is not
    # retried either: there is no flaky installer to give a second chance, and after a refused prompt
    # a retry would only put the same question to the same person again.
    $installOnce = {
        $run = if ($elevated) {
            Invoke-ElevatedWinget -WingetPath $WingetPath -TimeoutSeconds $TimeoutSeconds -Arguments $arguments
        } else {
            Invoke-BoundedWinget -WingetPath $WingetPath -TimeoutSeconds $TimeoutSeconds -Arguments $arguments
        }

        if ($run.TimedOut) {
            return [PSCustomObject]@{ Succeeded = $false; Final = $true
                Failure = "gave up after $TimeoutSeconds seconds and killed winget, so this package is not installed and the run was not left hanging on it" }
        }
        if ($run.PSObject.Properties['ElevationFailure'] -and $run.ElevationFailure) {
            return [PSCustomObject]@{ Succeeded = $false; Final = $true; Failure = $run.ElevationFailure }
        }

        $tail = Get-CommandOutputTail -Text $run.Output

        # winget exited 0 for Prime Video and Slack in a Windows all apps run and its own list found
        # neither afterwards, so exit 0 counts only when winget then lists the package in the same
        # scope, asked the same way as before the install. docs/regression_ledger.md 10.187.
        if ($run.ExitCode -eq 0) {
            $after = Get-WingetPackagePresence -WingetPath $WingetPath -PackageId $PackageId -Scope $Scope -Elevated:$probeElevated
            if ($after.Installed) {
                return [PSCustomObject]@{ Succeeded = $true; Final = $false; Failure = '' }
            }
            $listed = "winget list --exact --id $PackageId$(if ($Scope) { " --scope $Scope" })"
            if (-not $after.Answered) {
                return [PSCustomObject]@{ Succeeded = $false; Final = $true
                    Failure = "winget exited 0, and whether $PackageId is now installed is unknown, because $listed could not run: $($after.Reason) $tail".Trim() }
            }
            return [PSCustomObject]@{ Succeeded = $false; Final = $false
                Failure = "winget exited 0 and $listed finds nothing, so $PackageId is not installed. $tail".Trim() }
        }

        # winget reports an already-installed package as a failure code with a specific
        # message, so treat that text as success rather than reporting a false failure.
        if ($run.Output -match 'already installed') {
            return [PSCustomObject]@{ Succeeded = $true; Final = $false; Failure = '' }
        }

        return [PSCustomObject]@{ Succeeded = $false; Final = $false; Failure = "exit $($run.ExitCode). $tail" }
    }

    $refreshSource = {
        $refresh = Invoke-BoundedWinget -WingetPath $WingetPath -TimeoutSeconds 300 `
            -Arguments @('source', 'update', '--name', $Source, '--disable-interactivity')
        if ($refresh.TimedOut) { return "winget source update --name $Source ran out of time" }
        if ($refresh.ExitCode -ne 0) { return "winget source update --name $Source exited $($refresh.ExitCode)" }
        return ''
    }

    $retry = Invoke-PackageManagerRetry -Package $PackageId -Attempt $installOnce -Refresh $refreshSource `
        -Retries $Retries -DelaySeconds $RetryPauseSeconds
    $status = if ($retry.Succeeded) { 'installed' } else { 'failed' }
    return [PSCustomObject]@{ Package = $PackageId; Status = $status; Detail = $retry.Detail }
}

function Install-ChocolateyPackage {
    <#
    .SYNOPSIS
        Installs one Chocolatey package in this process, under the shared retry rule.
    .DESCRIPTION
        Runs inside the elevated child Install-ChocolateyPackageBatch starts, which dot-sources this
        file for it. Chocolatey has no package index like apt's. What it keeps is an HTTP cache of
        the feed's answers, valid for 30 minutes, which `choco cache remove` empties, the User HTTP
        Cache always and the System HTTP Cache when elevated (choco 2.1.0 and later, see
        https://docs.chocolatey.org/en-us/choco/commands/cache/ and
        https://docs.chocolatey.org/en-us/choco/features/http-caching/). So that is the refresh
        before a retry. On an older Chocolatey it fails, which is reported, and the retry still runs.

        choco's output is written to the host as it arrives, so the child's transcript keeps it.
        Returns Package, Status, ExitCode, Attempts and Detail.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $PackageId,
        [ValidateRange(0, 10)] [int] $Retries = $script:PackageRetryCount,
        [ValidateRange(0, 300)] [int] $RetryPauseSeconds = $script:PackageRetryDelaySeconds
    )

    $previousNative = $PSNativeCommandUseErrorActionPreference
    try {
        # A non-zero exit from choco is an answer to report, not a fault to throw on.
        $PSNativeCommandUseErrorActionPreference = $false

        $installOnce = {
            Write-Host "  ... choco install $PackageId"
            $lines = @(& choco install $PackageId -y --no-progress --limit-output --execution-timeout=600 2>&1 |
                       ForEach-Object { "$_" })
            $code = $LASTEXITCODE
            foreach ($line in $lines) { Write-Host $line }
            Write-Host "      choco exited $code for $PackageId"
            if ($code -eq 0) {
                # Chocolatey 2 exits 0 with "Chocolatey installed 0/0 packages." when the feed answers
                # 503, so exit 0 counts only when Chocolatey then lists the package as installed.
                $listed = @(& choco list --local-only --limit-output --exact $PackageId 2>&1 | ForEach-Object { "$_" })
                if (@($listed | Where-Object { $_ -match ('^' + [regex]::Escape($PackageId) + '\|') }).Count -gt 0) {
                    return [PSCustomObject]@{ Succeeded = $true; Final = $false; Failure = ''; ExitCode = 0 }
                }
                $said = ($lines | Where-Object { $_.Trim() } | Select-Object -Last 1)
                return [PSCustomObject]@{ Succeeded = $false; Final = $false; ExitCode = 0
                                          Failure = "choco exited 0 and does not list $PackageId as installed. $said".Trim() }
            }
            $tail = (($lines | Where-Object { $_.Trim() } | Select-Object -Last 2) -join ' ')
            return [PSCustomObject]@{ Succeeded = $false; Final = $false; Failure = "choco exited $code. $tail"; ExitCode = $code }
        }

        $refreshCache = {
            $said = (@(& choco cache remove -y --limit-output 2>&1 | ForEach-Object { "$_" }) | Where-Object { $_.Trim() } | Select-Object -Last 1)
            if ($LASTEXITCODE -ne 0) { return "choco cache remove exited $LASTEXITCODE. $said".Trim() }
            return ''
        }

        $retry = Invoke-PackageManagerRetry -Package $PackageId -Attempt $installOnce -Refresh $refreshCache `
            -Retries $Retries -DelaySeconds $RetryPauseSeconds
    } finally {
        $PSNativeCommandUseErrorActionPreference = $previousNative
    }

    return [PSCustomObject]@{
        Package  = $PackageId
        Status   = $(if ($retry.Succeeded) { 'installed' } else { 'failed' })
        ExitCode = $retry.Outcome.ExitCode
        Attempts = $retry.Attempts
        Detail   = $retry.Detail
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
        batched into a single elevated child process, run through Invoke-ElevatedPowerShell. That
        is one consent prompt for the whole batch instead of one per package. The child dot-sources
        this file and installs each package through Install-ChocolateyPackage, so the retries follow
        the same rule as every other package manager, and writes each package's result back as
        JSON. Packages is that result by package id, for every package the child reached, and empty
        when it reached none.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string[]] $PackageId
    )

    if (-not $PSCmdlet.ShouldProcess(($PackageId -join ', '), 'elevated choco install')) {
        return [PSCustomObject]@{ Status = 'skipped'; Detail = 'WhatIf'; Packages = @{} }
    }

    # Bootstraps Chocolatey when absent, then installs the batch. Runs in the child so the
    # bootstrap also gets the elevation it needs.
    # Quoted one by one so a package name can never be read as two arguments, the same shape
    # Enable-WindowsFeatureSet uses for its feature names.
    $packageLiterals = ($PackageId | ForEach-Object { "'$_'" }) -join ', '

    # The child writes its own transcript, because none of its output reaches this process. It runs
    # as a separate elevated process and, when the wizard is not already elevated, through -Verb
    # RunAs, which forbids output redirection entirely. So on 2026-08-22 the parent could say
    # "nodejs (nvm): choco exited -1" and nothing more: not which command, not what Chocolatey
    # printed, not why. Start-Transcript inside the child is the one route that works in both the
    # elevated and the RunAs case, and the tail of it is quoted in the failure below.
    $childLog = Join-Path ([System.IO.Path]::GetTempPath()) ('installation-helper-choco-' + [guid]::NewGuid().ToString('N') + '.log')
    $resultFile = Join-Path ([System.IO.Path]::GetTempPath()) ('installation-helper-choco-' + [guid]::NewGuid().ToString('N') + '.json')

    $inner = @"
`$ErrorActionPreference = 'Stop'
Start-Transcript -Path '$childLog' -Force | Out-Null
. $(ConvertTo-PowerShellLiteral -Value $script:WindowsSoftwarePath)
if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
    Set-ExecutionPolicy Bypass -Scope Process -Force
    [System.Net.ServicePointManager]::SecurityProtocol = 3072
    `$bootstrap = Invoke-PackageManagerRetry -Package 'Chocolatey' -Attempt {
        try {
            Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1')) | Out-Host
            [PSCustomObject]@{ Succeeded = `$true; Final = `$false; Failure = '' }
        } catch {
            [PSCustomObject]@{ Succeeded = `$false; Final = `$false; Failure = "the Chocolatey install script failed: `$(`$_.Exception.Message)" }
        }
    }
    if (-not `$bootstrap.Succeeded) { throw "Chocolatey is not installed, so none of its packages can be: `$(`$bootstrap.Detail)" }
}
# One package per call, each with its own deadline, rather than one call for the batch.
#
# The batch hit the wizard's 30 minute kill on both Windows software cells of 2026-08-22 and took
# every package in it down: nvm, geforce-experience and razer-synapse-4 were all reported as not
# installed because something in the batch never returned, and nothing said which something. One
# call per package with --execution-timeout means Chocolatey itself gives up on the package that
# hangs, says so, and the ones after it still get their turn.
#
# 600 seconds each. A Chocolatey package that has not finished in ten minutes on a machine with a
# fast link is waiting on something, and the default of 2700 is longer than the wizard's own patience
# for the whole phase, which is how one package ate the other five. Install-ChocolateyPackage passes it.
`$worst = 0
`$results = [System.Collections.Generic.List[object]]::new()
foreach (`$package in @($packageLiterals)) {
    `$result = Install-ChocolateyPackage -PackageId `$package
    `$results.Add(`$result)
    if (`$result.Status -ne 'installed') { `$worst = if (`$result.ExitCode) { `$result.ExitCode } else { 1 } }
}
ConvertTo-Json -InputObject @(`$results) -Depth 3 | Set-Content -LiteralPath $(ConvertTo-PowerShellLiteral -Value $resultFile) -Encoding utf8
Stop-Transcript | Out-Null
exit `$worst
"@

    # Bounded, never -Wait, so this cannot block forever. It is on the critical path for
    # install_nodejs and install_flutter as well as the mapped Chocolatey packages, and it hangs when
    # choco prompts inside the elevated child despite -y.
    # Sized against the loop inside the child rather than picked. Each package there gets
    # --execution-timeout=600, ten minutes, so a child with n packages can legitimately take ten
    # minutes times n plus Chocolatey's own start-up. 30 minutes covered three packages, and both
    # Windows software cells of 2026-08-22 had more than that and were killed while still working:
    # nvm, geforce-experience and razer-synapse-4 all reported as not installed because the clock ran
    # out on the batch rather than because anything failed.
    #
    # Ten minutes for each attempt the shared retry rule allows a package, one more for its pauses
    # and refreshes, plus ten for the bootstrap, and never less than 30.
    $perPackageMinutes = (($script:PackageRetryCount + 1) * 10) + 1
    $timeoutMinutes = [Math]::Max(30, ($PackageId.Count * $perPackageMinutes) + 10)
    try {
        $child = Invoke-ElevatedPowerShell -Script $inner -TimeoutSeconds ($timeoutMinutes * 60)

        # What the child reported for each package it reached, read before any return below.
        $packages = @{}
        if (Test-Path -LiteralPath $resultFile) {
            foreach ($entry in @(Get-Content -LiteralPath $resultFile -Raw | ConvertFrom-Json)) {
                $packages[[string]$entry.Package] = $entry
            }
        }

        # A refused consent prompt lands here, and is a user decision rather than a fault.
        if ($child.StartError) {
            return [PSCustomObject]@{ Status = 'failed'; Detail = "could not run choco: $($child.StartError)"; Packages = $packages }
        }
        if ($child.TimedOut) {
            return [PSCustomObject]@{
                Status   = 'failed'
                Packages = $packages
                Detail   = "the Chocolatey batch was still running after $timeoutMinutes minutes and was killed, so those packages are NOT installed. Most likely a prompt inside the elevated child, or an unanswered consent dialog. Run 'choco install $($PackageId -join ' ') -y' by hand to see it."
            }
        }
        if ($child.ExitCode -eq 0) {
            return [PSCustomObject]@{ Status = 'installed'; Detail = "$($PackageId.Count) package(s)"; Packages = $packages }
        }
        # The last lines of the child's own transcript, because an exit code alone has never once
        # been enough to act on. Chocolatey says what it could not do, and that sentence is what the
        # reader needs, not the number.
        $tail = ''
        if (Test-Path -LiteralPath $childLog) {
            $tail = ((Get-Content -LiteralPath $childLog -Tail 12 -ErrorAction SilentlyContinue |
                      Where-Object { $_.Trim() }) -join ' | ')
            Remove-Item -LiteralPath $childLog -Force -ErrorAction SilentlyContinue
        }
        return [PSCustomObject]@{
            Status   = 'failed'
            Packages = $packages
            Detail   = "choco exited $($child.ExitCode)$(if ($tail) { ". It said: $tail" } else { '. Its transcript is missing, so there is nothing more to report.' })"
        }
    } catch {
        return [PSCustomObject]@{ Status = 'failed'; Detail = "could not run choco: $($_.Exception.Message)"; Packages = @{} }
    } finally {
        Remove-Item -LiteralPath $resultFile -Force -ErrorAction SilentlyContinue
    }
}

function Get-ChocolateyInstalledPackage {
    <#
    .SYNOPSIS
        The package ids Chocolatey itself reports as installed on this machine.
    .DESCRIPTION
        Asked rather than assumed. Install-ChocolateyPackageBatch returns one status for the whole
        batch, and stamping that onto every package meant a single bad id reported all of them as
        failed, so the summary lied about what the user lost. This is the same move the Arch path
        makes when it asks `pacman -Qq` instead of trusting the module's own answer, see
        docs/regression_ledger.md.

        `--local-only` is passed even though Chocolatey 2 lists local packages by default, because
        Chocolatey 1's bare `list` searches the remote feed instead, and a remote hit would report a
        package as installed when it is absent. Chocolatey 2 still accepts the switch.

        Returns an empty list when choco is not on PATH, which is the honest answer rather than an
        error: it means the bootstrap inside the elevated child never finished, so nothing from the
        batch is installed. Comparison at the callsite is `-contains`, which is case-insensitive for
        strings, because Chocolatey reports ids in the casing the package author used and the
        mappings are written lowercase.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param()

    if (-not (Get-Command choco -CommandType Application -ErrorAction SilentlyContinue)) {
        Write-Verbose 'choco is not on PATH, so no package can be installed'
        return @()
    }

    $previous = $PSNativeCommandUseErrorActionPreference
    try {
        # A non-zero exit is an answer here, not a fault.
        $PSNativeCommandUseErrorActionPreference = $false
        $output = & choco list --limit-output --local-only 2>&1 | Out-String
    } finally {
        $PSNativeCommandUseErrorActionPreference = $previous
    }

    # id|version, one per line. Chocolatey mixes its own retry chatter into the same stream, so the
    # lines are selected by shape rather than by position.
    $ids = [System.Collections.Generic.List[string]]::new()
    foreach ($line in ($output -split "`r?`n")) {
        if ($line -match '^(?<id>[^|\s]+)\|') { $ids.Add($Matches['id']) }
    }
    Write-Verbose "Chocolatey reports $($ids.Count) installed package(s)"
    return $ids.ToArray()
}

function Get-FreeDiskByte {
    <#
    .SYNOPSIS
        Free bytes on the volume that holds a path, or -1 when the volume cannot be asked.
    .DESCRIPTION
        DriveInfo rather than Get-PSDrive, because this is called before and after a deletion and
        the two answers have to come from the same place to be worth subtracting. -1 rather than 0
        for the failure, so a caller can tell "could not measure" from "nothing free".
    #>
    [CmdletBinding()]
    [OutputType([long])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Path
    )

    try {
        $free = [System.IO.DriveInfo]::new($Path).AvailableFreeSpace
        # Two different failures, and only one of them throws. An unmounted drive letter constructs a
        # DriveInfo perfectly well and then hands back nothing at all when asked how much is free,
        # measured on 2026-08-26 against Q: on a machine with no Q: drive. Casting that would answer
        # zero, which reads as a full disk rather than as a question that could not be answered.
        if ($null -eq $free) { throw "the volume behind $Path did not report its free space" }
        return [long]$free
    } catch {
        Write-Verbose "Could not read the free space on $Path ($($_.Exception.Message))"
        return [long]-1
    }
}

function Get-ChocolateyCachePath {
    <#
    .SYNOPSIS
        The directory Chocolatey downloads its installers into.
    .DESCRIPTION
        Read out of Chocolatey's own configuration file rather than assumed, and rather than asked
        through `choco config get cacheLocation`, which needs the process and prompts: asked that
        way on 2026-08-26 it answered "Do you want to continue?([Y]es/[N]o)" and then timed out on
        the empty selection. The file is the same source of truth with none of that.

        An empty cacheLocation means the default, and the key's own description in that file says
        what the default is: it "Replaces `$env:TEMP value for choco.exe process". So the payload
        lands under <temp>\chocolatey\<package>\<version>, and a real run's log confirms that rather
        than inferring it:

            Downloading https://download.virtualbox.org/virtualbox/7.2.14/VirtualBox-7.2.14-174565-Win.exe
              to C:\Users\<user>\AppData\Local\Temp\chocolatey\virtualbox\7.2.14\VirtualBox-7.2.14-174565-Win.exe

        Chocolatey installs from that path and leaves the file where it is, so 170 MB of that one
        installer stays on the disk for the rest of the run. Joining chocolatey onto the root is
        right in both cases: a configured cacheLocation replaces the temporary directory, not the
        chocolatey folder inside it.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [string] $ConfigPath
    )

    if (-not $ConfigPath) {
        $installRoot = if ($env:ChocolateyInstall) { $env:ChocolateyInstall } else { Join-Path $env:ProgramData 'chocolatey' }
        $ConfigPath = Join-Path $installRoot 'config\chocolatey.config'
    }

    $configured = ''
    if (Test-Path -LiteralPath $ConfigPath) {
        try {
            $xml = [xml](Get-Content -LiteralPath $ConfigPath -Raw)
            $entry = @($xml.SelectNodes('/chocolateyConfig/config/add')) |
                Where-Object { $_.GetAttribute('key') -eq 'cacheLocation' } |
                Select-Object -First 1
            if ($entry) { $configured = [string]$entry.GetAttribute('value') }
        } catch {
            # Not fatal, and not silent either. A configuration file this cannot read means the
            # default location is in use, which is where Chocolatey puts its downloads on any
            # machine that has never set the key, so the fallback is the common case.
            Write-Verbose "Could not read $ConfigPath ($($_.Exception.Message)), using the temporary directory"
        }
    }

    $root = if ($configured) { $configured } else { [System.IO.Path]::GetTempPath() }
    return (Join-Path $root 'chocolatey')
}

function Clear-WindowsPackageCache {
    <#
    .SYNOPSIS
        Deletes the installer payloads winget and Chocolatey leave behind, and reports what that
        freed.
    .DESCRIPTION
        Runs between the package phases and the phases that need room: the SDK installers, which
        unzip the Android command line tools, and `wsl --install`, which needs a distribution image.

        It exists because of one measured failure. In the all-apps Windows cell of run 32864564543
        the pre-run cleanup freed 17 GB, taking the runner from 29.2 to 46.1 GB free, and the
        software set still exhausted the disk:

            setup_wsl (Ubuntu): wsl --install exited -1. There is not enough space on the disk.
                                Error code: Wsl/InstallDistro/0x80070070

        The two failures either side of it were the same cause wearing different clothes, an access
        violation out of the Arduino installer and the Android SDK dying at 85 per cent while
        unzipping, and neither message mentions disk. Widening the pre-run cleanup fixed that run,
        which then finished with 91.6 GB free, so this is headroom rather than the fix, and it is
        deliberately the kind that cannot fail the run: every failure is named in the result and
        nothing throws.

        It does not estimate how much there is to free. It reads the volume before and after and
        reports both, so the number comes from the run rather than from anybody's idea of how big an
        installer set is.

        Two things are deliberately left alone.

        `choco cache` is not the command for this, and that is measured rather than assumed. Asked
        on 2.7.3, it answers that it works on the User HTTP Cache and, when elevated, the System
        HTTP Cache. That is the NuGet metadata, kilobytes of it, and not the installer payload, so
        the payload is removed as files.

        winget's own <temp>\WinGet\cache holds the source index, the manifests and the version data
        it resolves package ids against. The verification phase runs `winget list` after this, and
        deleting the index only makes it fetch another one. Every sibling of that directory is a
        per-package download folder and goes.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([PSCustomObject])]
    param(
        [string] $ChocolateyCachePath = (Get-ChocolateyCachePath),
        [string] $WingetCachePath     = (Join-Path ([System.IO.Path]::GetTempPath()) 'WinGet'),
        [string] $MeasuredPath        = ($env:SystemDrive + '\'),
        [string[]] $KeepInWingetCache = @('cache')
    )

    $freeBefore = Get-FreeDiskByte -Path $MeasuredPath

    $locations = [System.Collections.Generic.List[object]]::new()
    $failures  = [System.Collections.Generic.List[object]]::new()

    $targets = @(
        [PSCustomObject]@{ Name = 'Chocolatey'; Path = $ChocolateyCachePath; Keep = @() }
        [PSCustomObject]@{ Name = 'winget';     Path = $WingetCachePath;     Keep = @($KeepInWingetCache) }
    )

    foreach ($target in $targets) {
        if (-not $target.Path -or -not (Test-Path -LiteralPath $target.Path)) {
            $locations.Add([PSCustomObject]@{
                    Name   = $target.Name
                    Path   = $target.Path
                    Bytes  = [long]0
                    Items  = 0
                    Detail = 'nothing cached here'
                })
            continue
        }

        $entries = @(Get-ChildItem -LiteralPath $target.Path -Force -ErrorAction SilentlyContinue |
            Where-Object { $target.Keep -notcontains $_.Name })

        $bytes = [long]0
        $items = 0
        foreach ($entry in $entries) {
            # Sized before it is deleted, because afterwards there is nothing left to ask. The free
            # space either side is the honest total; this is the attribution, which cache held it.
            $size = [long]0
            try {
                if ($entry.PSIsContainer) {
                    $size = [long]((Get-ChildItem -LiteralPath $entry.FullName -Recurse -File -Force -ErrorAction SilentlyContinue |
                            Measure-Object -Property Length -Sum).Sum)
                } else {
                    $size = [long]$entry.Length
                }
            } catch {
                Write-Verbose "Could not size $($entry.FullName) ($($_.Exception.Message))"
            }

            if (-not $PSCmdlet.ShouldProcess($entry.FullName, 'remove cached download')) { continue }

            try {
                Remove-Item -LiteralPath $entry.FullName -Recurse -Force -ErrorAction Stop
                $bytes += $size
                $items++
            } catch {
                # A file another process still holds open, or one written by an account this session
                # is not, cannot be removed. Named rather than swallowed, and never fatal: the run
                # carries on with exactly the disk it had a moment ago, which is the state this step
                # is insurance against needing.
                $failures.Add([PSCustomObject]@{ Path = $entry.FullName; Detail = $_.Exception.Message })
            }
        }

        $locations.Add([PSCustomObject]@{
                Name   = $target.Name
                Path   = $target.Path
                Bytes  = $bytes
                Items  = $items
                Detail = ''
            })
    }

    return [PSCustomObject]@{
        Locations  = $locations.ToArray()
        Bytes      = [long]($locations | Measure-Object -Property Bytes -Sum).Sum
        Items      = [int]($locations | Measure-Object -Property Items -Sum).Sum
        FreeBefore = $freeBefore
        FreeAfter  = (Get-FreeDiskByte -Path $MeasuredPath)
        Failed     = $failures.ToArray()
    }
}

# Syncthing's three ports, from docs.syncthing.net users/firewall.rst, "Local Firewall": 22000/TCP
# for the sync protocol, 22000/UDP for the same over QUIC and 21027/UDP for local discovery. By port
# and not by program, because winget extracts each Syncthing version into its own versioned folder,
# so a program rule matches one version only, and a rule on the stable link in WinGet\Links matches
# nothing: a process started through a symbolic link runs under the target's path, measured on
# 2026-10-11 with Get-Process and Win32_Process, which both reported the target.
$script:SyncthingFirewallRules = @(
    [PSCustomObject]@{ Name = 'InstallationHelper-Syncthing-TCP-22000'; Protocol = 'TCP'; Port = 22000; Purpose = 'sync protocol' }
    [PSCustomObject]@{ Name = 'InstallationHelper-Syncthing-UDP-22000'; Protocol = 'UDP'; Port = 22000; Purpose = 'sync protocol over QUIC' }
    [PSCustomObject]@{ Name = 'InstallationHelper-Syncthing-UDP-21027'; Protocol = 'UDP'; Port = 21027; Purpose = 'local discovery' }
)

# The flags docs.syncthing.net users/autostart.rst gives for "Run at user log on using the Startup
# folder", plus --no-upgrade, because a standard user cannot write the binary under Program Files
# and winget upgrades it instead. All three are serve options in Syncthing v2.1.6, cmd/syncthing.
$script:SyncthingStartupArguments = '--no-console --no-browser --no-upgrade'

function New-ShellShortcut {
    <#
    .SYNOPSIS
        The WScript.Shell shortcut object for a .lnk path, existing or not, so tests can replace it.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $Path)

    $shell = New-Object -ComObject WScript.Shell
    return $shell.CreateShortcut($Path)
}

function Set-SyncthingStartupShortcut {
    <#
    .SYNOPSIS
        Puts a Syncthing shortcut in this user's Startup folder, so Syncthing starts at their logon.
    .DESCRIPTION
        The shortcut points at the link winget keeps in %ProgramFiles%\WinGet\Links, which follows
        every upgrade, and not at the versioned folder behind it. A shortcut to a link keeps the link
        path and starts whatever the link points at now, measured on 2026-10-11 by moving a link to a
        second target and starting it through the same shortcut. Configuration goes to the user's own
        %LOCALAPPDATA%\Syncthing, which is Syncthing's default.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string] $LinkPath = (Join-Path $env:ProgramFiles 'WinGet\Links\syncthing.exe'),
        [string] $StartupDirectory = (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup')
    )

    $result = { param($status, $detail)
        [PSCustomObject]@{ Key = 'syncthing'; Manager = 'winget'; Package = 'Startup folder shortcut'; Status = $status; Detail = $detail } }

    if (-not (Test-Path -LiteralPath $LinkPath)) {
        return (& $result 'failed' "there is no $LinkPath, which is where winget links a machine-wide portable, so there is nothing to start at logon")
    }

    $shortcutPath = Join-Path $StartupDirectory 'Syncthing.lnk'
    try {
        if (Test-Path -LiteralPath $shortcutPath) {
            $existing = New-ShellShortcut -Path $shortcutPath
            if ($existing.TargetPath -eq $LinkPath -and $existing.Arguments -eq $script:SyncthingStartupArguments) {
                return (& $result 'present' $shortcutPath)
            }
        }
        if (-not $PSCmdlet.ShouldProcess($shortcutPath, 'create the Syncthing logon shortcut')) {
            return (& $result 'skipped' 'WhatIf')
        }
        if (-not (Test-Path -LiteralPath $StartupDirectory)) {
            New-Item -ItemType Directory -Path $StartupDirectory -Force -ErrorAction Stop | Out-Null
        }
        $shortcut = New-ShellShortcut -Path $shortcutPath
        $shortcut.TargetPath  = $LinkPath
        $shortcut.Arguments   = $script:SyncthingStartupArguments
        $shortcut.Description = 'Syncthing, started at logon with no console and no browser'
        # 7 is a minimised window, so nothing flashes up at logon even before --no-console hides it.
        $shortcut.WindowStyle = 7
        $shortcut.Save()
        return (& $result 'installed' "$shortcutPath, which starts Syncthing at your next logon. Its web interface is http://localhost:8384")
    } catch {
        return (& $result 'failed' "could not write $shortcutPath ($($_.Exception.Message)), so Syncthing will not start at logon")
    }
}

function Set-SyncthingFirewallRule {
    <#
    .SYNOPSIS
        Opens Syncthing's three ports inbound on the Private and Domain profiles.
    .DESCRIPTION
        Reading the rules needs no elevation, so a machine that has them is never asked for consent.
        Creating them does, so the missing ones are made in one elevated child and then read back,
        and the result is what the read says rather than what the child believed. Not on the Public
        profile, so a laptop on a public network does not accept sync connections from strangers.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param()

    $result = { param($status, $detail)
        [PSCustomObject]@{ Key = 'syncthing'; Manager = 'winget'; Package = 'Windows Firewall ports'; Status = $status; Detail = $detail } }
    $missingRules = { @($script:SyncthingFirewallRules | Where-Object { -not (Get-NetFirewallRule -Name $_.Name -ErrorAction SilentlyContinue) }) }
    $describe = { param($rules) (@($rules) | ForEach-Object { "$($_.Protocol) $($_.Port)" }) -join ', ' }

    # @( ) at the call site, docs/regression_ledger.md defect class 4: the block's own @( ) does not survive the
    # return, and the first draft of this function died on .Count exactly that way.
    $missing = @(& $missingRules)
    if ($missing.Count -eq 0) {
        return (& $result 'present' "inbound $(& $describe $script:SyncthingFirewallRules) already allowed")
    }
    if (-not $PSCmdlet.ShouldProcess((& $describe $missing), 'allow inbound for Syncthing')) {
        return (& $result 'skipped' 'WhatIf')
    }

    $lines = foreach ($rule in $missing) {
        "New-NetFirewallRule -Name $(ConvertTo-PowerShellLiteral -Value $rule.Name) -DisplayName $(ConvertTo-PowerShellLiteral -Value "Syncthing $($rule.Purpose) ($($rule.Protocol) $($rule.Port))") -Group 'Syncthing (InstallationHelper)' -Direction Inbound -Action Allow -Protocol $($rule.Protocol) -LocalPort $($rule.Port) -Profile Private, Domain | Out-Null"
    }
    $inner = "`$ErrorActionPreference = 'Stop'`n" + ($lines -join "`n")
    $child = Invoke-ElevatedPowerShell -Script $inner -TimeoutSeconds 300

    $still = @(& $missingRules)
    if ($still.Count -eq 0) {
        return (& $result 'installed' "inbound $(& $describe $missing) allowed on the Private and Domain profiles, by port, so the rules survive every Syncthing upgrade")
    }
    $why = if ($child.StartError) { "the elevated child did not start: $($child.StartError)" }
           elseif ($child.TimedOut) { 'the elevated child did not finish in five minutes' }
           else { "the elevated child exited $($child.ExitCode)" }
    return (& $result 'failed' "inbound $(& $describe $still) is still not allowed, because $why. Syncthing still syncs through its relays, more slowly, and other devices cannot connect to this one directly.")
}

function Get-SyncthingLegacyInstall {
    <#
    .SYNOPSIS
        A result naming the BillStewart Syncthing package when it is still installed, or nothing.
    .DESCRIPTION
        That package was this wizard's Syncthing until 2026-10-11. It starts its own copy at logon
        through a scheduled task, so leaving it beside the new one gives two Syncthing processes
        fighting over the same ports and the same %LOCALAPPDATA%\Syncthing configuration. Nothing in
        this wizard migrates or removes another package, so it is reported with the command that
        removes it. Its uninstaller keeps the configuration folder, which the new Syncthing reads.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $WingetPath)

    $legacy = 'BillStewart.SyncthingWindowsSetup'
    if (-not (Test-WingetPackageInstalled -WingetPath $WingetPath -PackageId $legacy)) { return $null }
    return [PSCustomObject]@{
        Key = 'syncthing'; Manager = 'winget'; Package = $legacy; Status = 'skipped'
        Detail = "the older per-user Syncthing package is still installed and starts its own Syncthing at logon, which will fight the new one for the same ports and configuration. Remove it with 'winget uninstall --exact --id $legacy'. Its uninstaller keeps %LOCALAPPDATA%\Syncthing, so devices and folders carry over."
    }
}

function Invoke-SyncthingUserSetup {
    <#
    .SYNOPSIS
        What Syncthing needs after winget has installed it machine-wide, as one result per step.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)] [string] $WingetPath)

    $results = [System.Collections.Generic.List[object]]::new()
    $results.Add((Set-SyncthingStartupShortcut))
    $results.Add((Set-SyncthingFirewallRule))
    $legacy = Get-SyncthingLegacyInstall -WingetPath $WingetPath
    if ($legacy) { $results.Add($legacy) }
    return $results.ToArray()
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
        [string[]] $OnlyKeys,
        [hashtable] $ToggleOverride
    )

    $toggles  = Get-WindowsSoftwareToggle `
        -AllVarsPath     (Join-Path $AnsibleDir 'group_vars\all.yaml') `
        -WindowsVarsPath (Join-Path $AnsibleDir 'group_vars\windows.yaml') `
        -ToggleOverride  $ToggleOverride
    $mappings = Get-WindowsSoftwareMapping `
        -WindowsMappingPath (Join-Path $AnsibleDir 'vars\Windows.yaml')

    $plan = Resolve-WindowsSoftwarePlan -Toggles $toggles -Mappings $mappings -OnlyKeys $OnlyKeys

    $results = [System.Collections.Generic.List[object]]::new()

    $wingetItems = @($plan.Planned | Where-Object { $_.Manager -eq 'winget' })
    if ($wingetItems.Count -gt 0) {
        # Get-WingetPath throws when App Installer is absent, and setup.ps1 runs with
        # $ErrorActionPreference = 'Stop', so letting that out of here ended the whole wizard: a
        # machine without winget lost the Chocolatey batch, the npm tools, every custom install and
        # every summary line, none of which need winget. One failed result per affected package
        # instead, so the summary names exactly what was lost, and the run carries on.
        $winget = $null
        try {
            $winget = Get-WingetPath
            Write-Verbose "Using winget at $winget"
        } catch {
            foreach ($item in $wingetItems) {
                $results.Add([PSCustomObject]@{
                    Key = $item.Key; Manager = 'winget'; Package = $item.Package
                    Status = 'failed'; Detail = $_.Exception.Message
                })
            }
        }

        if ($winget) {
            # One line per package, before and after, because this phase used to print nothing at all
            # between its header and its summary. Two cells were cancelled at 150 minutes inside it on
            # 2026-08-22 and the transcript could not say which package they were on. A phase that can
            # run for an hour has to say what it is doing while it does it.
            # Asked once rather than per package. Both answers are properties of this machine and
            # this process, and neither changes between packages.
            $machineFact = Get-WindowsMachineFact

            $index = 0
            foreach ($item in $wingetItems) {
                $index++

                # A package this machine cannot run is skipped with the reason rather than
                # attempted and failed. The reason comes from Test-WindowsPackageSkip, which the
                # Chocolatey path and the verification also ask, so the three cannot disagree.
                $skipReason = Test-WindowsPackageSkip -Item $item -Fact $machineFact
                if ($skipReason) {
                    Write-Host ("  ... [{0}/{1}] {2} skipped" -f $index, $wingetItems.Count, $item.Key)
                    $results.Add([PSCustomObject]@{
                        Key = $item.Key; Manager = 'winget'; Package = $item.Package; Status = 'skipped'
                        Detail = $skipReason
                    })
                    continue
                }
                Write-Host ("  ... [{0}/{1}] {2} ({3})" -f $index, $wingetItems.Count, $item.Key, $item.Package)
                $started = [datetime]::UtcNow
                $r = Install-WingetPackage -WingetPath $winget -PackageId $item.Package -Source $item.Source `
                    -Scope $item.Scope -InstallerType $item.InstallerType
                $seconds = [int]([datetime]::UtcNow - $started).TotalSeconds
                Write-Host ("      {0} after {1}s{2}" -f $r.Status, $seconds,
                    $(if ($r.Detail) { ": $($r.Detail)" } else { '' }))
                $results.Add([PSCustomObject]@{
                    Key = $item.Key; Manager = 'winget'; Package = $item.Package
                    Status = $r.Status; Detail = $r.Detail
                })

                # A machine-wide portable starts nowhere on its own, so Syncthing's per-user start
                # and its firewall ports follow its install, and only once it is really there.
                if ($item.Key -eq 'syncthing' -and $r.Status -in @('installed', 'present')) {
                    foreach ($step in @(Invoke-SyncthingUserSetup -WingetPath $winget)) {
                        Write-Host ("      {0}: {1}{2}" -f $step.Package, $step.Status,
                            $(if ($step.Detail) { ": $($step.Detail)" } else { '' }))
                        $results.Add($step)
                    }
                }
            }
        }
    }

    $chocoItems = @($plan.Planned | Where-Object { $_.Manager -eq 'choco' })

    # Decided before the batch rather than inside it, because Chocolatey installs these in one child
    # process and a package that cannot run here would take its exit code back to the parent as a
    # batch failure.
    #
    # All three conditions, not just the hardware one. This block used to ask about
    # RequiresNvidiaGpu alone, so a Chocolatey package carrying client_only was installed anyway
    # while the verification, reading the same key, reported it as not applicable. Run 32778481303
    # shows both halves of that: razer-synapse-4 installed and exited 0, and the verification called
    # it not applicable in the same run.
    if ($chocoItems.Count -gt 0) {
        $chocoFact = Get-WindowsMachineFact
        $chocoSkipped = @()
        foreach ($item in $chocoItems) {
            $reason = Test-WindowsPackageSkip -Item $item -Fact $chocoFact
            if ($reason) {
                $chocoSkipped += $item.Key
                $results.Add([PSCustomObject]@{
                    Key = $item.Key; Manager = 'choco'; Package = $item.Package; Status = 'skipped'
                    Detail = $reason
                })
            }
        }
        if ($chocoSkipped.Count -gt 0) {
            $chocoItems = @($chocoItems | Where-Object { $_.Key -notin $chocoSkipped })
        }
    }

    if ($chocoItems.Count -gt 0) {
        # Asked before and after, so present, installed and failed can be told apart per package.
        # The batch's single status used to be stamped onto all of them, which meant one bad package
        # id marked every package in the batch failed and the summary named losses that were not
        # lost, while a batch that exited zero with one package silently absent named nothing.
        $before = @(Get-ChocolateyInstalledPackage)
        $batch  = Install-ChocolateyPackageBatch -PackageId ($chocoItems.Package)

        if ($batch.Status -eq 'skipped') {
            # WhatIf. Nothing ran, so asking Chocolatey what is installed would report the machine's
            # existing state as work this dry run did.
            foreach ($item in $chocoItems) {
                $results.Add([PSCustomObject]@{
                    Key = $item.Key; Manager = 'choco'; Package = $item.Package
                    Status = 'skipped'; Detail = $batch.Detail
                })
            }
        } else {
            $after = @(Get-ChocolateyInstalledPackage)
            foreach ($item in $chocoItems) {
                if ($before -contains $item.Package) {
                    $status = 'present'
                    $detail = ''
                } elseif ($after -contains $item.Package) {
                    $status = 'installed'
                    $detail = ''
                } else {
                    $status = 'failed'
                    $own = $batch.Packages[$item.Package]
                    if ($own -and $own.Status -ne 'installed') {
                        $detail = "Chocolatey does not list $($item.Package) as installed after its install, which failed on $($own.Attempts) attempt(s): $($own.Detail)"
                    } else {
                        $sessionOutcome = if ($batch.Status -eq 'installed') { 'choco exited 0' } else { $batch.Detail }
                        $detail = "Chocolatey does not list $($item.Package) as installed after its install. The elevated Chocolatey session shared by all $($chocoItems.Count) Chocolatey package(s) of this run ended with: $sessionOutcome. That is the shared session's result, not a failure of every package in it"
                    }
                }
                $results.Add([PSCustomObject]@{
                    Key = $item.Key; Manager = 'choco'; Package = $item.Package
                    Status = $status; Detail = $detail
                })
            }
        }
    }

    return [PSCustomObject]@{
        Planned   = $plan.Planned
        Unmapped  = $plan.Unmapped
        Results   = $results
        Installed = @($results | Where-Object { $_.Status -eq 'installed' })
        Present   = @($results | Where-Object { $_.Status -eq 'present' })
        # Only -WhatIf produces this, and it has to be counted rather than dropped: without it a dry
        # run reported "0 installed, 74 present, 0 failed" and said nothing at all about the seven
        # Chocolatey packages it would have installed.
        Skipped   = @($results | Where-Object { $_.Status -eq 'skipped' })
        Failed    = @($results | Where-Object { $_.Status -eq 'failed' })
    }
}
