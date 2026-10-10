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
#>

Set-StrictMode -Version Latest

# The same npm packages roles/ai_tools/tasks/*_unix.yaml install everywhere else, and
# e2e/tier1/windows_npm_parity.sh fails if the two lists ever disagree. The Windows task files this
# once mirrored were deleted on 2026-08-20 because none of them could run, so the Unix files are the
# reference now. Keyed by the group_vars toggle name without its install_ prefix, so it lines up
# with the software mapping keys. Replaces names an older package that claims the same bin, which
# Install-NpmToolPackage removes first, because npm refuses the new one with EEXIST while it is there.
$script:NpmToolPackages = [ordered]@{
    claude_code = @{ Package = '@anthropic-ai/claude-code'; Display = 'Claude Code' }
    opencode    = @{ Package = '@opencode/cli';             Display = 'OpenCode'; Replaces = 'opencode-ai' }
    openspec    = @{ Package = '@fission-ai/openspec';      Display = 'OpenSpec' }
    codex       = @{ Package = '@openai/codex';             Display = 'Codex' }
    grok        = @{ Package = '@xai-official/grok';        Display = 'Grok' }
    bruno_cli   = @{ Package = '@usebruno/cli';             Display = 'Bruno CLI' }
}

function Get-NpmToolPackage {
    <#
    .SYNOPSIS
        The npm package table, so the parity check and the installer read one definition.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param()
    return $script:NpmToolPackages
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
        [string] $ReplacesPackage = ''
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
                    Detail  = "npm uninstall -g $ReplacesPackage exited $LASTEXITCODE, so $PackageName was not attempted. $(($removal -split "`n" | Where-Object { $_.Trim() } | Select-Object -Last 2) -join ' ')"
                }
            }
            if ($removal -match 'removed \d+ package') {
                $replacedDetail = "removed $ReplacesPackage, which it replaces"
                $replacedRemoved = $true
            }
        }

        # Two attempts, because the npm registry flakes and a single transient failure should not
        # lose the tool. Same shape as the retries on the Ansible helper.
        $output = ''
        $installExit = 0
        for ($attempt = 1; $attempt -le 2; $attempt++) {
            $output = & npm install -g $PackageName 2>&1 | Out-String
            $installExit = $LASTEXITCODE
            if ($installExit -eq 0) {
                return [PSCustomObject]@{ Display = $DisplayName; Package = $PackageName; Status = 'installed'; Detail = $replacedDetail }
            }
            if ($attempt -lt 2) { Start-Sleep -Seconds 15 }
        }
        $detail = "npm exited $installExit. $(($output -split "`n" | Where-Object { $_.Trim() } | Select-Object -Last 2) -join ' ')"

        # The replaced package was removed before the new one was proven to install, because npm
        # refuses the new one while the old one holds the bin. So a failed install after a removal
        # installs the old one again and says so, rather than leaving the machine with neither.
        if ($replacedRemoved) {
            $restore = & npm install -g $ReplacesPackage 2>&1 | Out-String
            if ($LASTEXITCODE -eq 0) {
                $detail += " $ReplacesPackage had been removed to make room and was installed again, so the earlier $DisplayName is still on this machine."
            } else {
                $detail += " $ReplacesPackage had been removed to make room and could not be installed again either (npm exited $LASTEXITCODE), so there is no $DisplayName on this machine now. $(($restore -split "`n" | Where-Object { $_.Trim() } | Select-Object -Last 2) -join ' ')"
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
        [string[]] $OnlyKeys
    )

    $wanted = [System.Collections.Generic.List[object]]::new()
    foreach ($key in $script:NpmToolPackages.Keys) {
        if (-not ($Toggles.ContainsKey($key) -and $Toggles[$key])) { continue }
        if ($OnlyKeys -and $key -notin $OnlyKeys) { continue }
        $entry = $script:NpmToolPackages[$key]
        $wanted.Add([PSCustomObject]@{ Key = $key; Package = $entry.Package; Display = $entry.Display
                                       Replaces = if ($entry.ContainsKey('Replaces')) { $entry.Replaces } else { '' } })
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
        $results.Add((Install-NpmToolPackage -PackageName $tool.Package -DisplayName $tool.Display -ReplacesPackage $tool.Replaces))
    }

    return [PSCustomObject]@{
        Results    = $results
        Installed  = @($results | Where-Object { $_.Status -eq 'installed' })
        Present    = @($results | Where-Object { $_.Status -eq 'present' })
        Failed     = @($results | Where-Object { $_.Status -eq 'failed' })
        NpmMissing = $false
    }
}
