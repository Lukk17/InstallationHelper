#Requires -Version 7.2
<#
.SYNOPSIS
    Runs the Windows tier 3 tests inside a Windows container.

.DESCRIPTION
    The Linux scenarios are driven by e2e/run.sh from inside WSL. This one cannot be, because a
    Docker daemon serves one container platform at a time and this needs a Windows one. So it is a
    separate entry point, driven from Windows, and it runs only where a Windows daemon is already
    answering.

    It never changes the daemon platform, and nothing here asks anybody else to. The daemon on this
    project's machine serves the Linux containers every other tier depends on, and taking that away
    is not this script's decision to make.

    What it covers is the logic in setup/windows/WindowsSoftware.ps1 on a clean Windows with
    nothing installed, which is the state a real user starts from and the one a developer
    machine can never reproduce. It does not and cannot install a winget package: winget ships
    as an MSIX and needs the AppX subsystem, which Server Core does not have. See
    e2e/tier3/windows.Dockerfile for the full list of what is and is not reachable here.

.PARAMETER SkipSlow
    Skip the tests tagged Slow and Network, which is the Chocolatey bootstrap. Use it for a
    quick logic-only pass.

.PARAMETER KeepContainer
    Leave the container running afterwards so you can inspect it.

.EXAMPLE
    pwsh e2e/tier3/Invoke-WindowsE2E.ps1

.EXAMPLE
    pwsh e2e/tier3/Invoke-WindowsE2E.ps1 -SkipSlow
#>
[CmdletBinding()]
param(
    [switch] $SkipSlow,
    [switch] $KeepContainer
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Tier3Dir  = Split-Path -Parent $PSCommandPath
$RepoRoot  = Split-Path -Parent (Split-Path -Parent $Tier3Dir)
$Image     = 'installationhelper-e2e-windows:latest'
$Container = "e2e-windows-$PID"
$RunsDir   = Join-Path $RepoRoot 'e2e\runs'
$RunId     = "{0}_windows_pester" -f ([DateTime]::UtcNow.ToString('yyyy-MM-ddTHH-mm-ssZ'))
$RunDir    = Join-Path $RunsDir $RunId

function Write-Step { param([string]$Text) Write-Host ">> $Text" -ForegroundColor Cyan }
function Write-Bad  { param([string]$Text) Write-Host "!! $Text" -ForegroundColor Red }

# --- environment -------------------------------------------------------------
Write-Step 'Checking the Docker daemon platform'
$serverOs = (& docker version --format '{{.Server.Os}}' 2>&1) -join ''
if ($LASTEXITCODE -ne 0) {
    Write-Bad 'Cannot reach the Docker daemon. Start Docker Desktop and try again.'
    exit 2
}
if ($serverOs -notmatch 'windows') {
    Write-Bad "The Docker daemon here is serving '$serverOs' containers, so this cannot run on this machine."
    Write-Host ''
    Write-Host '  Leave the daemon as it is. It serves the Linux containers every other tier needs,' -ForegroundColor Yellow
    Write-Host '  and this script will not take that away for a Pester suite.' -ForegroundColor Yellow
    Write-Host ''
    Write-Host '  The same suite runs without any container in two places, and between them they' -ForegroundColor Yellow
    Write-Host '  cover every test that does not need a machine with nothing installed:' -ForegroundColor Yellow
    Write-Host '    bash e2e/run.sh          the windows_pester check, on this machine' -ForegroundColor Yellow
    Write-Host '    the stage 1 job of .github/workflows/e2e-matrix.yml, on a Windows runner' -ForegroundColor Yellow
    exit 2
}
Write-Host "   daemon platform: $serverOs"

New-Item -ItemType Directory -Path $RunDir -Force | Out-Null
$pesterLog = Join-Path $RunDir 'pester.log'
$resultXml = Join-Path $RunDir 'pester-results.xml'
$resultTxt = Join-Path $RunDir 'result.txt'

# --- build -------------------------------------------------------------------
Write-Step 'Building the Windows base image (cached after the first run)'
& docker build -f (Join-Path $Tier3Dir 'windows.Dockerfile') -t $Image $Tier3Dir 2>&1 |
    Tee-Object -FilePath (Join-Path $RunDir 'build.log') | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Bad "Image build failed, see $(Join-Path $RunDir 'build.log')"
    exit 1
}

# --- run ---------------------------------------------------------------------
# Hyper-V isolation rather than process isolation: ltsc2025 is build 26100 and this project's
# host is 26200, and process isolation wants those to match closely.
Write-Step 'Starting the container with Hyper-V isolation'
& docker run -d --name $Container --isolation hyperv $Image | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Bad 'Could not start the container. Is nested virtualisation available?'
    exit 1
}

try {
    # Copied in, not bind-mounted, so a run can never modify the working tree it is testing.
    Write-Step 'Copying the repository into the container'
    & docker cp (Join-Path $RepoRoot 'setup') "${Container}:C:\work\setup" | Out-Null
    & docker cp (Join-Path $Tier3Dir 'windows\WindowsSoftware.Tests.ps1') "${Container}:C:\work\WindowsSoftware.Tests.ps1" | Out-Null

    # A configuration property, not a command-line parameter. This used to interpolate the string
    # "-ExcludeTagFilter @('Slow','Network')" onto a line of its own inside the generated script,
    # where PowerShell reads a leading hyphen as an operator it does not have, so the whole script
    # was a parse error and every -SkipSlow run failed before Pester started. Proven by feeding that
    # exact line to [scriptblock]::Create, which throws at the character where the array begins.
    $excludeTag = if ($SkipSlow) { "`$cfg.Filter.ExcludeTag = @('Slow','Network')" } else { '' }

    # PassThru is what makes Invoke-Pester return the result object. Without it the call returns
    # nothing, $r is null, $r.FailedCount is null, and `exit $null` exits 0, so this gate reported
    # success no matter how many tests failed. Measured: `$r = $null; exit $r.FailedCount` gives
    # exit code 0. The explicit null guard below covers the other way this can go wrong, which is
    # Pester failing to produce a result at all, and reports that as a failure rather than a pass.
    $pesterCmd = @"
`$ErrorActionPreference = 'Stop'
if (`$PSStyle) { `$PSStyle.OutputRendering = 'PlainText' }
Import-Module Pester -MinimumVersion 5.0
`$cfg = New-PesterConfiguration
`$cfg.Run.Path = 'C:\work\WindowsSoftware.Tests.ps1'
`$cfg.Run.PassThru = `$true
`$cfg.Output.Verbosity = 'Detailed'
`$cfg.TestResult.Enabled = `$true
`$cfg.TestResult.OutputPath = 'C:\work\pester-results.xml'
$excludeTag
`$r = Invoke-Pester -Configuration `$cfg
if (`$null -eq `$r) {
    Write-Host 'Invoke-Pester returned no result object, so nothing can be proved about this run.'
    exit 99
}
Write-Host "pester totals: total=`$(`$r.TotalCount) passed=`$(`$r.PassedCount) failed=`$(`$r.FailedCount) skipped=`$(`$r.SkippedCount)"
if (`$r.TotalCount -eq 0) {
    Write-Host 'Pester discovered no tests, which is a failure of this gate rather than a clean run.'
    exit 98
}
exit `$r.FailedCount
"@

    Write-Step 'Running the Pester suite'
    & docker exec -e E2E_REPO_ROOT='C:\work' $Container pwsh -NoProfile -Command $pesterCmd 2>&1 |
        Tee-Object -FilePath $pesterLog
    $pesterExit = $LASTEXITCODE

    & docker cp "${Container}:C:\work\pester-results.xml" $resultXml 2>&1 | Out-Null

    $summary = @(
        "run_id:      $RunId"
        "image:       $Image"
        "isolation:   hyperv"
        "skip_slow:   $($SkipSlow.IsPresent)"
        "failed_count: $pesterExit"
        ''
        'Not covered here, and not claimed to be:'
        '  winget installation. winget is an MSIX package and Server Core has no AppX'
        '  subsystem, so 77 of the 83 Windows mappings cannot be exercised in any container.'
        '  Those need a real Windows machine or a hosted runner.'
        '  The wizard interface. setup.ps1 uses Out-ConsoleGridView, which needs a real console.'
    )
    $summary | Set-Content -LiteralPath $resultTxt
    $summary | ForEach-Object { Write-Host $_ }

    if ($pesterExit -eq 0) {
        Write-Host ''
        Write-Host "PASS windows pester: no failures. Records in $RunDir" -ForegroundColor Green
        exit 0
    }
    Write-Host ''
    # 99 and 98 are this script's own codes for a run that proved nothing, as opposed to a run that
    # found failing tests. They are called out separately because the first reads as a pass to
    # anyone skimming for a failure count.
    switch ($pesterExit) {
        99 { Write-Bad "windows pester: Pester returned no result object, so the suite proved nothing. See $pesterLog" }
        98 { Write-Bad "windows pester: no tests were discovered, so the suite proved nothing. See $pesterLog" }
        default { Write-Bad "windows pester: $pesterExit failing test(s). See $pesterLog" }
    }
    exit 1
}
finally {
    if ($KeepContainer) {
        Write-Host "   container $Container left running on purpose" -ForegroundColor DarkGray
    } else {
        & docker rm -f $Container 2>&1 | Out-Null
    }
}
