#Requires -Version 7.2
<#
.SYNOPSIS
    Installs the npm-based CLI tools on Windows, natively.

.DESCRIPTION
    The ai_tools Ansible role has a Windows task file for each of these, and none of them can ever
    run: the playbook is invoked from inside WSL against localhost, so ansible_os_family reports
    Debian and every Windows-gated task is skipped. See docs/regression_ledger.md.

    This is the native replacement. The toggles stay in group_vars as the single source of truth and
    the package list here mirrors the role's own Windows task files one for one, so the two cannot
    disagree about what gets installed. e2e/tier1/windows_npm_parity.sh fails if they ever do.

    The .npmrc defence is carried over from the Ansible helper deliberately. npm walks upward from
    the working directory looking for a .npmrc, so an .npmrc in any ancestor of wherever the wizard
    happened to be launched could redirect the registry to a hostile mirror. Every npm call here runs
    with the user profile root as its working directory, which anchors that lookup.

    Depends on Invoke-PackageManagerRetry from WindowsSoftware.ps1, which setup.ps1 dot-sources first.
#>

Set-StrictMode -Version Latest

# The same npm packages roles/ai_tools/tasks/*_unix.yaml install everywhere else, and
# e2e/tier1/windows_npm_parity.sh fails if the two lists ever disagree. The Windows task files this
# once mirrored were deleted on 2026-08-20 because none of them could run, so the Unix files are the
# reference now. Keyed by the group_vars toggle name without its install_ prefix, so it lines up
# with the software mapping keys. Replaces names an older package that claims the same bin, which
# Install-NpmToolPackage removes first, because npm refuses the new one with EEXIST while it is there.
# OpenCode's two command line packages, by version. Get-OpenCodeVersion picks one, Get-NpmToolPackage puts it in
# the opencode row and names the other as the package it replaces, because both claim the opencode command. The
# same pair as ih_opencode_cli in setup/ansible/tasks/opencode_version.yaml, which windows_npm_parity.sh compares.
$script:OpenCodeCliPackages = [ordered]@{ v2 = '@opencode/cli'; v1 = 'opencode-ai' }

$script:NpmToolPackages = [ordered]@{
    claude_code = @{ Package = '@anthropic-ai/claude-code'; Display = 'Claude Code' }
    opencode    = @{ Display = 'OpenCode' }
    kilo_code   = @{ Package = '@kilocode/cli';             Display = 'Kilo Code' }
    openspec    = @{ Package = '@fission-ai/openspec';      Display = 'OpenSpec' }
    codex       = @{ Package = '@openai/codex';             Display = 'Codex' }
    grok        = @{ Package = '@xai-official/grok';        Display = 'Grok' }
    bruno_cli   = @{ Package = '@usebruno/cli';             Display = 'Bruno CLI' }
}

function Get-NpmToolPackage {
    <#
    .SYNOPSIS
        The npm package table for one OpenCode version, so the installer, the plan and the verification read one definition.
    .DESCRIPTION
        A copy, with the opencode row filled in from $script:OpenCodeCliPackages: Package is the selected version's
        package, Replaces the other one's, and ReplacedReason the words the result line uses when it removed it.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param([ValidateSet('v1', 'v2')] [string] $OpenCodeVersion = 'v2')

    $other = if ($OpenCodeVersion -eq 'v1') { 'v2' } else { 'v1' }
    $table = [ordered]@{}
    foreach ($key in $script:NpmToolPackages.Keys) {
        $table[$key] = $script:NpmToolPackages[$key].Clone()
    }
    $table['opencode']['Package']        = $script:OpenCodeCliPackages[$OpenCodeVersion]
    $table['opencode']['Replaces']       = $script:OpenCodeCliPackages[$other]
    $table['opencode']['ReplacedReason'] = "OpenCode $other command line tool, $($script:OpenCodeCliPackages[$other]), because $OpenCodeVersion is selected"
    return $table
}

function Test-NpmAvailable {
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    return [bool](Get-Command npm -CommandType Application -ErrorAction SilentlyContinue)
}

function Install-NpmToolPackage {
    <#
    .SYNOPSIS
        Installs one global npm package, skipping it when already present.
    .DESCRIPTION
        Runs from the user profile root so npm cannot pick up an .npmrc from an ancestor of the
        launch directory. Returns a result object rather than printing, so the caller renders.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $PackageName,
        [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $DisplayName,
        [string] $ReplacesPackage = '',
        # The words the result uses for what was removed and why. Empty means "<package>, which it replaces".
        [string] $ReplacedReason = ''
    )

    $anchor = $env:USERPROFILE
    if (-not $anchor -or -not (Test-Path -LiteralPath $anchor)) {
        return [PSCustomObject]@{ Display = $DisplayName; Package = $PackageName; Status = 'failed'
                                  Detail = 'USERPROFILE is not set or does not exist, refusing to run npm without a safe working directory' }
    }

    $previous = $PSNativeCommandUseErrorActionPreference
    $here = Get-Location
    try {
        # A non-zero exit from npm is an answer, not a fault, so it must not throw.
        $PSNativeCommandUseErrorActionPreference = $false
        Set-Location -LiteralPath $anchor

        $listed = & npm list -g $PackageName --depth=0 2>&1 | Out-String
        if ($LASTEXITCODE -eq 0 -and $listed -match [regex]::Escape($PackageName)) {
            return [PSCustomObject]@{ Display = $DisplayName; Package = $PackageName; Status = 'present'; Detail = '' }
        }

        if (-not $PSCmdlet.ShouldProcess($PackageName, 'npm install -g')) {
            return [PSCustomObject]@{ Display = $DisplayName; Package = $PackageName; Status = 'skipped'; Detail = 'WhatIf' }
        }

        # Measured on 2026-10-10 with npm 11.19.0 in a throwaway prefix: with opencode-ai installed,
        # `npm install -g @opencode/cli` exits 1 with "EEXIST: file already exists" on opencode.cmd
        # and changes nothing. `npm uninstall -g` prints "removed <n> packages" when it removed
        # something and "up to date" when the package was absent, exit 0 both times.
        $replacedDetail = ''
        $replacedRemoved = $false
        if ($ReplacesPackage) {
            $removal = & npm uninstall -g $ReplacesPackage 2>&1 | Out-String
            if ($LASTEXITCODE -ne 0) {
                return [PSCustomObject]@{
                    Display = $DisplayName; Package = $PackageName; Status = 'failed'
                    Detail  = "npm uninstall -g $ReplacesPackage exited $LASTEXITCODE, so $PackageName was not attempted. $(Get-CommandOutputTail -Text $removal)"
                }
            }
            if ($removal -match 'removed \d+ package') {
                $replacedDetail = if ($ReplacedReason) { "removed $ReplacedReason" } else { "removed $ReplacesPackage, which it replaces" }
                $replacedRemoved = $true
            }
        }

        # The shared retry rule with no refresh step. npm keeps no package list to refresh: its cache
        # verifies everything it stores and refetches what fails, and its own documentation says
        # clearing it is only ever for reclaiming disk space (npm 11.19.0, docs/content/commands/npm-cache.md).
        $installOnce = {
            $output = & npm install -g $PackageName 2>&1 | Out-String
            $installExit = $LASTEXITCODE
            if ($installExit -eq 0) {
                return [PSCustomObject]@{ Succeeded = $true; Final = $false; Failure = '' }
            }
            return [PSCustomObject]@{ Succeeded = $false; Final = $false
                Failure = "npm exited $installExit. $(Get-CommandOutputTail -Text $output)" }
        }
        $retry = Invoke-PackageManagerRetry -Package $PackageName -Attempt $installOnce
        if ($retry.Succeeded) {
            $installedDetail = (@($replacedDetail, $retry.Detail) | Where-Object { $_ }) -join ', '
            return [PSCustomObject]@{ Display = $DisplayName; Package = $PackageName; Status = 'installed'; Detail = $installedDetail }
        }
        $detail = $retry.Detail

        # The replaced package was removed before the new one was proven to install, because npm
        # refuses the new one while the old one holds the bin. So a failed install after a removal
        # installs the old one again and says so, rather than leaving the machine with neither.
        if ($replacedRemoved) {
            $restore = & npm install -g $ReplacesPackage 2>&1 | Out-String
            if ($LASTEXITCODE -eq 0) {
                $detail += " $ReplacesPackage had been removed to make room and was installed again, so the earlier $DisplayName is still on this machine."
            } else {
                $detail += " $ReplacesPackage had been removed to make room and could not be installed again either (npm exited $LASTEXITCODE), so there is no $DisplayName on this machine now. $(Get-CommandOutputTail -Text $restore)"
            }
        }
        return [PSCustomObject]@{ Display = $DisplayName; Package = $PackageName; Status = 'failed'; Detail = $detail }
    } finally {
        Set-Location -LiteralPath $here
        $PSNativeCommandUseErrorActionPreference = $previous
    }
}

function Invoke-WindowsNpmToolInstall {
    <#
    .SYNOPSIS
        Installs every enabled npm-based CLI tool and returns a summary.
    .DESCRIPTION
        Takes the already-resolved toggle map from Get-WindowsSoftwareToggle, so the toggle source of
        truth stays in one place. Never throws for one tool: the others still install and the summary
        names every failure.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [hashtable] $Toggles,
        [string[]] $OnlyKeys,
        # From Get-OpenCodeVersion, the answer the custom installs and the verification are given too.
        [ValidateSet('v1', 'v2')] [string] $OpenCodeVersion = 'v2'
    )

    $packages = Get-NpmToolPackage -OpenCodeVersion $OpenCodeVersion
    $wanted = [System.Collections.Generic.List[object]]::new()
    foreach ($key in $packages.Keys) {
        if (-not ($Toggles.ContainsKey($key) -and $Toggles[$key])) { continue }
        if ($OnlyKeys -and $key -notin $OnlyKeys) { continue }
        $entry = $packages[$key]
        $wanted.Add([PSCustomObject]@{ Key = $key; Package = $entry.Package; Display = $entry.Display
                                       Replaces = if ($entry.ContainsKey('Replaces')) { $entry.Replaces } else { '' }
                                       ReplacedReason = if ($entry.ContainsKey('ReplacedReason')) { $entry.ReplacedReason } else { '' } })
    }

    if ($wanted.Count -eq 0) {
        return [PSCustomObject]@{ Results = @(); Installed = @(); Present = @(); Failed = @(); NpmMissing = $false }
    }

    if (-not (Test-NpmAvailable)) {
        # Reported rather than silently skipped, because the tools genuinely are not installed and a
        # quiet skip would leave the user believing they were.
        return [PSCustomObject]@{
            Results = @(); Installed = @(); Present = @(); Failed = @()
            NpmMissing = $true
            Wanted = $wanted
        }
    }

    $results = [System.Collections.Generic.List[object]]::new()
    foreach ($tool in $wanted) {
        $results.Add((Install-NpmToolPackage -PackageName $tool.Package -DisplayName $tool.Display -ReplacesPackage $tool.Replaces -ReplacedReason $tool.ReplacedReason))
    }

    return [PSCustomObject]@{
        Results    = $results
        Installed  = @($results | Where-Object { $_.Status -eq 'installed' })
        Present    = @($results | Where-Object { $_.Status -eq 'present' })
        Failed     = @($results | Where-Object { $_.Status -eq 'failed' })
        NpmMissing = $false
    }
}
