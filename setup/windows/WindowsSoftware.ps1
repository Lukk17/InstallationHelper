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

    # Bounded like the install below it, and for the same reason. This runs once per package before
    # anything is installed, it talks to a remote source, and an unbounded call here hangs the run
    # just as thoroughly as an unbounded install does. A probe that runs out of time answers false,
    # which is the safe direction: the worst case is that winget is asked to install something that
    # is already there, and it says so and exits.
    $run = Invoke-BoundedWinget -WingetPath $WingetPath -TimeoutSeconds 180 -Arguments @(
        'list', '--exact', '--id', $PackageId, '--accept-source-agreements')
    if ($run.TimedOut) {
        Write-Verbose "winget list for $PackageId ran out of time, treating it as not installed"
        return $false
    }
    return ($run.ExitCode -eq 0)
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
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            try { $process.Kill($true) } catch { Write-Verbose "could not kill winget: $($_.Exception.Message)" }
            $null = $process.WaitForExit(30000)
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

function Install-WingetPackage {
    <#
    .SYNOPSIS
        Installs one winget package, skipping it when already present.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [string] $WingetPath,
        [Parameter(Mandatory)] [string] $PackageId,
        [string] $Source = 'winget',
        [ValidateRange(30, 7200)] [int] $TimeoutSeconds = 900
    )

    if (Test-WingetPackageInstalled -WingetPath $WingetPath -PackageId $PackageId) {
        Write-Verbose "$PackageId already installed"
        return [PSCustomObject]@{ Package = $PackageId; Status = 'present'; Detail = '' }
    }

    if (-not $PSCmdlet.ShouldProcess($PackageId, 'winget install')) {
        return [PSCustomObject]@{ Package = $PackageId; Status = 'skipped'; Detail = 'WhatIf' }
    }

    $run = Invoke-BoundedWinget -WingetPath $WingetPath -TimeoutSeconds $TimeoutSeconds -Arguments @(
        'install', '--exact', '--id', $PackageId, '--source', $Source, '--silent',
        '--accept-source-agreements', '--accept-package-agreements', '--disable-interactivity')
    $output = $run.Output
    $code   = $run.ExitCode

    if ($run.TimedOut) {
        return [PSCustomObject]@{
            Package = $PackageId
            Status  = 'failed'
            Detail  = "gave up after $TimeoutSeconds seconds and killed winget, so this package is not installed and the run was not left hanging on it"
        }
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
    # Quoted one by one so a package name can never be read as two arguments, the same shape
    # Enable-WindowsFeatureSet uses for its feature names.
    $packageLiterals = ($PackageId | ForEach-Object { "'$_'" }) -join ', '
    $inner = @"
`$ErrorActionPreference = 'Stop'
if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
    Set-ExecutionPolicy Bypass -Scope Process -Force
    [System.Net.ServicePointManager]::SecurityProtocol = 3072
    Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
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
# for the whole phase, which is how one package ate the other five.
foreach (`$package in @($packageLiterals)) {
    Write-Host "  ... choco install `$package"
    choco install `$package -y --no-progress --limit-output --execution-timeout=600
    Write-Host "      choco exited `$LASTEXITCODE for `$package"
}
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
    # Sized against the loop inside the child rather than picked. Each package there gets
    # --execution-timeout=600, ten minutes, so a child with n packages can legitimately take ten
    # minutes times n plus Chocolatey's own start-up. 30 minutes covered three packages, and both
    # Windows software cells of 2026-08-22 had more than that and were killed while still working:
    # nvm, geforce-experience and razer-synapse-4 all reported as not installed because the clock ran
    # out on the batch rather than because anything failed.
    #
    # Ten minutes per package plus ten for the bootstrap, and never less than 30.
    $timeoutMinutes = [Math]::Max(30, ($PackageId.Count * 10) + 10)
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
            $index = 0
            foreach ($item in $wingetItems) {
                $index++
                Write-Host ("  ... [{0}/{1}] {2} ({3})" -f $index, $wingetItems.Count, $item.Key, $item.Package)
                $started = [datetime]::UtcNow
                $r = Install-WingetPackage -WingetPath $winget -PackageId $item.Package -Source $item.Source
                $seconds = [int]([datetime]::UtcNow - $started).TotalSeconds
                Write-Host ("      {0} after {1}s{2}" -f $r.Status, $seconds,
                    $(if ($r.Detail) { ": $($r.Detail)" } else { '' }))
                $results.Add([PSCustomObject]@{
                    Key = $item.Key; Manager = 'winget'; Package = $item.Package
                    Status = $r.Status; Detail = $r.Detail
                })
            }
        }
    }

    $chocoItems = @($plan.Planned | Where-Object { $_.Manager -eq 'choco' })
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
                    $detail = "Chocolatey does not list it as installed after the batch. The batch reported $($batch.Status): $($batch.Detail)"
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
