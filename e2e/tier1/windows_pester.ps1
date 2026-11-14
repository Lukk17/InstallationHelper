<#
.SYNOPSIS
    Runs the Pester suite over the Windows installer, windows/WindowsSoftware.Tests.ps1 next to this file, without the Slow and Network tagged tests, and decides whether the run passed.

.DESCRIPTION
    The one copy of that rule. windows_pester.sh next to it runs this in the gate container, and
    .github/actions/windows-pester/action.yml runs it on a Windows runner. Why it reads every Pester count
    is docs/regression_ledger.md 10.345.

    It imports exactly the Pester that gate_pester_version pins, read through
    setup/pinned_values/PinnedValues.psm1, the version the gate image carries and the shared action
    installs on the runner, never the newest one it finds (owner decision 53, docs/regression_ledger.md
    10.348). When that version is not installed here, nothing runs and the verdict is fail.

    Prints on standard output:
      PESTER version=<version>                the Pester that ran the suite, always the pinned one
      TOTALS total=<n> passed=<n> failed=<n> skipped=<n> notrun=<n> inconclusive=<n> failedblocks=<n> failedcontainers=<n> notrunbytag=<n>
      FAILED, FAILEDBLOCK, FAILEDCONTAINER, NOTRUN or INCONCLUSIVE <path>[: <error>], one line for each test, block or file that did not pass
      PROBLEM <sentence>, one line for each reason the run did not pass
      VERDICT pass or VERDICT fail
    Exits 0 after VERDICT pass and 1 otherwise. A pin that cannot be read and a pinned Pester that is
    not installed are each a PROBLEM line.

.PARAMETER Verbosity
    Pester's own output: None in the gate, Detailed on the runner.
#>
[CmdletBinding()]
param(
    [ValidateSet('None', 'Normal', 'Detailed', 'Diagnostic')] [string] $Verbosity = 'None'
)

$ErrorActionPreference = 'Stop'

$suite = Join-Path $PSScriptRoot 'windows' 'WindowsSoftware.Tests.ps1'
$pinnedValues = Join-Path $PSScriptRoot '..' '..' 'setup' 'pinned_values' 'PinnedValues.psm1'
$excludedTags = @('Slow', 'Network')
$countProperties = [ordered]@{
    total            = 'TotalCount'
    passed           = 'PassedCount'
    failed           = 'FailedCount'
    skipped          = 'SkippedCount'
    notrun           = 'NotRunCount'
    inconclusive     = 'InconclusiveCount'
    failedblocks     = 'FailedBlocksCount'
    failedcontainers = 'FailedContainersCount'
}

function Format-OneLine([object] $ErrorRecord) {
    return ("$ErrorRecord" -replace '\s+', ' ').Trim()
}

function Test-LeftOutByTag([object] $Test) {
    $tags = @($Test.Tag)
    for ($block = $Test.Block; $null -ne $block; $block = $block.Parent) {
        $tags += @($block.Tag)
    }

    return (@($tags | Where-Object { $_ -in $excludedTags }).Count -gt 0)
}

$problems = [System.Collections.Generic.List[string]]::new()

$wanted = $null
try {
    Import-Module $pinnedValues -Force
    $wanted = [Version](Get-PinnedValue -Key gate_pester_version)
} catch {
    $problems.Add("the pinned Pester version gate_pester_version cannot be read through $pinnedValues, so no test ran: $(Format-OneLine $_)")
}

if ($null -ne $wanted) {
    $pester = Get-Module -ListAvailable -Name Pester |
        Where-Object { $_.Version -eq [Version]$wanted } |
        Select-Object -First 1
    if (-not $pester) {
        $installed = @(Get-Module -ListAvailable -Name Pester | ForEach-Object { "$($_.Version)" }) -join ', '
        $problems.Add("Pester $wanted, the version gate_pester_version pins, is not installed here, so no test ran. Installed: $(if ($installed) { $installed } else { 'none' })")
    }
}

if (-not (Test-Path -LiteralPath $suite -PathType Leaf)) {
    $problems.Add("the Pester suite is missing, so nothing can be proved: $suite")
}

if ($problems.Count -eq 0) {
    Import-Module $pester.Path -Force
    Write-Output "PESTER version=$($pester.Version)"

    $configuration = New-PesterConfiguration
    $configuration.Run.Path = $suite
    $configuration.Run.PassThru = $true
    $configuration.Filter.ExcludeTag = $excludedTags
    $configuration.Output.Verbosity = $Verbosity

    $run = Invoke-Pester -Configuration $configuration

    $missing = @($countProperties.Values | Where-Object { $null -eq $run -or -not $run.PSObject.Properties[$_] })
    if ($null -eq $run) {
        $problems.Add('Invoke-Pester returned no result object, so nothing can be proved about this run')
    } elseif ($missing.Count -gt 0) {
        $problems.Add("Pester $($pester.Version) keeps no $($missing -join ', ') on its result, so this run cannot be read")
    } else {
        $count = @{}
        foreach ($name in $countProperties.Keys) {
            $count[$name] = [int]$run.($countProperties[$name])
        }

        $notRunUntagged = [System.Collections.Generic.List[string]]::new()
        $notRunByTag = 0
        foreach ($test in @($run.Tests | Where-Object { $_.Result -eq 'NotRun' })) {
            if (Test-LeftOutByTag $test) {
                $notRunByTag++
            } else {
                $notRunUntagged.Add($test.ExpandedPath)
            }
        }
        $inconclusive = @($run.Tests | Where-Object { $_.Result -eq 'Inconclusive' } | ForEach-Object { $_.ExpandedPath })
        $failedTests = @($run.Failed | ForEach-Object { '{0}: {1}' -f $_.ExpandedPath, (Format-OneLine $_.ErrorRecord) })
        $failedBlocks = @($run.FailedBlocks | ForEach-Object { '{0}: {1}' -f ($_.Path -join '.'), (Format-OneLine $_.ErrorRecord) })
        $failedContainers = @($run.FailedContainers | ForEach-Object { '{0}: {1}' -f $_.Item, (Format-OneLine $_.ErrorRecord) })

        Write-Output ('TOTALS total={0} passed={1} failed={2} skipped={3} notrun={4} inconclusive={5} failedblocks={6} failedcontainers={7} notrunbytag={8}' -f `
            $count.total, $count.passed, $count.failed, $count.skipped, $count.notrun, $count.inconclusive, $count.failedblocks, $count.failedcontainers, $notRunByTag)
        foreach ($line in $failedTests) { Write-Output "FAILED $line" }
        foreach ($line in $failedBlocks) { Write-Output "FAILEDBLOCK $line" }
        foreach ($line in $failedContainers) { Write-Output "FAILEDCONTAINER $line" }
        foreach ($line in $notRunUntagged) { Write-Output "NOTRUN $line" }
        foreach ($line in $inconclusive) { Write-Output "INCONCLUSIVE $line" }

        if ($count.total -eq 0) {
            $problems.Add('Pester discovered no tests, which is a broken gate rather than a clean run')
        }
        if ($count.failed -gt 0) {
            $problems.Add("$($count.failed) failed: $($failedTests -join ' | ')")
        }
        if ($count.failedblocks -gt 0 -or $count.failedcontainers -gt 0) {
            $problems.Add("a BeforeAll, an AfterAll or a whole test file failed, so the tests under it never ran: $(@($failedBlocks + $failedContainers) -join ' | ')")
        }
        if ($count.notrun -ne $notRunByTag) {
            $problems.Add("$($count.notrun - $notRunByTag) did not run although no $($excludedTags -join ' or ') tag leaves them out: $($notRunUntagged -join ' | ')")
        }
        if ($count.inconclusive -gt 0) {
            $problems.Add("$($count.inconclusive) ended inconclusive, which proves nothing: $($inconclusive -join ' | ')")
        }
        if ($count.passed + $count.failed + $count.skipped + $count.notrun + $count.inconclusive -ne $count.total) {
            $problems.Add('passed, failed, skipped, not run and inconclusive do not make the total, so a test ended in a result this script does not read')
        }
    }
}

foreach ($problem in $problems) {
    Write-Output "PROBLEM $problem"
}
if ($problems.Count -gt 0) {
    Write-Output 'VERDICT fail'
    exit 1
}

Write-Output 'VERDICT pass'
exit 0
