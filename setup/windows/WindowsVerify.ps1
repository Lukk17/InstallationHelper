#Requires -Version 7.2
<#
.SYNOPSIS
    Asks Windows what actually landed after a wizard run, and changes nothing.

.DESCRIPTION
    setup.sh ends every Linux and macOS run in setup/ansible/verify_install.yaml, which asks the
    machine what it holds and exits non-zero when something the user requested is absent. That play
    refuses to run on Windows and says Windows has its own reporting. Until this file existed that
    was not true: the Windows wizard printed what its own installer believed it had done, which is a
    different claim. An installer that exited zero is not a package on the disk, and every
    silent-failure entry in docs/regression_ledger.md lives in the gap between the two.

    One entry point, Invoke-WindowsVerification. Everything else here is its helper. Nothing writes
    to the console: the caller renders, which is the same contract the other four Windows modules
    keep and what makes this testable.

    It reads, and only reads. Four questions, one per way this wizard installs something, and a fifth
    for Gradle.

      winget mappings   winget list --exact --id <id>, whose exit status is the answer, or the
                        verify_path on disk when the mapping carries one
      choco mappings    the ids Chocolatey itself reports as installed locally
      npm CLI tools     npm ls -g --depth=0 --json, one call for the whole set
      custom installs   the paths on disk that the install has to have produced
      Gradle            gradle --version in a new process with the user's environment, because
                        Gradle that Chocolatey lists still cannot start without a Java runtime,
                        docs/regression_ledger.md 10.368

    The winget question is asked once per package rather than by matching one `winget list` dump,
    which costs about two seconds each and is worth it: the dump is a column-formatted table that
    truncates the Id column with an ellipsis on a narrow console, so matching against it would report
    a package as missing because of the window width. An exit status cannot be truncated.

    The Chocolatey question goes through Get-ChocolateyInstalledPackage in WindowsSoftware.ps1, which
    already asks Chocolatey what is installed locally and is what the install phase compares against.
    One reader means the install and the verification cannot disagree about what Chocolatey said.
    A Chocolatey mapping with a version or a verify_path, KiCad 9 pinned at the version of its kicad9
    mapping, is asked through
    Get-ChocolateyInstallVerdict instead, the rule the install decides by: that version, a Chocolatey
    pin on it, and the path on disk.

    The custom-install proof paths come from Get-WindowsCustomInstallProof in
    WindowsCustomInstalls.ps1, for the same reason: the installer proves its own work with that
    table, so a path corrected in one place cannot go stale in the other. A drifted proof path
    reports a working install as missing, and a false failure that nobody can reproduce is how a
    verification stops being read.

    Not covered, and not claimed to be: the three Windows system settings, the optional features, the
    WSL distribution and the Ansible install inside it. Those are applied by WindowsSettings.ps1 and
    reported by it, and several of them are only true after a reboot, so a verdict taken in the same
    run would be wrong as often as right.

    Depends on Get-WindowsSoftwareToggle, Get-WindowsSoftwareMapping, Get-WingetPath,
    Get-WingetInstallVerdict, Get-ChocolateyInstalledPackage, Get-ChocolateyInstallVerdict, Test-WindowsToggleWanted,
    Get-WindowsTogglePrerequisite, Resolve-WindowsBroughtInToggle and Get-CommandOutputTail from
    WindowsSoftware.ps1, Get-NpmToolPackage from WindowsNpmTools.ps1, and Get-WindowsCustomInstallKey,
    Get-WindowsCustomInstallProof and Get-WindowsUserEnvironment from WindowsCustomInstalls.ps1.
    setup.ps1 dot-sources all three before this one.
#>

Set-StrictMode -Version Latest

# The verdicts, spelled once. The failing ones are upper case in the report for the same reason the
# Ansible report does it: a reader skimming a hundred lines finds them without reading any of them.
$script:VerdictInstalled    = 'installed'
$script:VerdictMissing      = 'MISSING'
$script:VerdictNotRequested = 'not requested'
$script:VerdictUnverifiable = 'UNVERIFIABLE'
$script:VerdictNotMapped    = 'not mapped'
# Requested, mapped, and correctly not installed, because the machine cannot run it. The three
# conditions behind it are the same three the install phase skips on, and they are properties of the
# machine rather than of the run: a client-only package on Windows Server, an installer that refuses
# an administrator context, and graphics software with no NVIDIA adapter to drive. Before this
# existed the wizard skipped them for good reason and then failed its own verification for the
# absence it had just explained, which is the two-sources-of-truth shape this repository keeps
# paying for.
$script:VerdictNotApplicable = 'not applicable'
# The other OpenCode version, which a run removes because the two cannot sit side by side. Absent is the pass,
# STILL THERE fails the run like MISSING does, and is spelled differently because the fix is a removal.
$script:VerdictAbsent     = 'absent'
$script:VerdictStillThere = 'STILL THERE'
# Installed, and it does not run: Gradle whose gradle --version fails or names no version and no JVM.
# It fails the run like MISSING does, and is spelled differently because the fix is the Java beside it.
$script:VerdictDoesNotStart = 'DOES NOT START'

function Get-NpmGlobalPackage {
    <#
    .SYNOPSIS
        The globally installed npm package names, or null when npm cannot be asked.
    .DESCRIPTION
        Null and an empty list are different answers and the caller needs the difference: null means
        npm is not on this machine, so every CLI tool is unverifiable, while an empty list means npm
        answered and holds nothing, so every requested tool is missing. Reporting the first as the
        second would blame the wizard for a machine with no Node.

        --json rather than the tree npm prints by default. The tree renders a scoped package as
        `+-- @anthropic-ai/claude-code@2.1.224`, where the name, the scope separator and the version
        separator are all the same kinds of character, so pulling the name back out means guessing
        where the version starts. The JSON hands over the names.

        Runs with the user profile root as its working directory, which is the .npmrc defence
        WindowsNpmTools.ps1 documents: npm walks upward looking for a .npmrc, and this must not
        inherit whichever one happens to sit above the directory the wizard was launched from.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param()

    if (-not (Get-Command npm -CommandType Application -ErrorAction SilentlyContinue)) {
        Write-Verbose 'npm is not on PATH, so no global package can be listed'
        return $null
    }

    $anchor = $env:USERPROFILE
    if (-not $anchor -or -not (Test-Path -LiteralPath $anchor)) {
        Write-Verbose 'USERPROFILE is not set or does not exist, refusing to run npm without a safe working directory'
        return $null
    }

    $previous = $PSNativeCommandUseErrorActionPreference
    $here = Get-Location
    try {
        # A non-zero exit from npm is an answer, not a fault. `npm ls` exits non-zero on any tree
        # problem, an unmet peer dependency for instance, while still printing the list.
        $PSNativeCommandUseErrorActionPreference = $false
        Set-Location -LiteralPath $anchor

        $output = & npm ls -g --depth=0 --json 2>$null | Out-String
    } finally {
        Set-Location -LiteralPath $here
        $PSNativeCommandUseErrorActionPreference = $previous
    }

    if (-not $output.Trim()) {
        Write-Verbose 'npm answered with nothing at all, which is not a list of zero packages'
        return $null
    }

    try {
        $parsed = $output | ConvertFrom-Json
    } catch {
        Write-Verbose "npm did not answer with JSON: $($_.Exception.Message)"
        return $null
    }

    if (-not ($parsed.PSObject.Properties.Name -contains 'dependencies') -or $null -eq $parsed.dependencies) {
        Write-Verbose 'npm answered with JSON carrying no dependencies, so nothing is installed globally'
        return @()
    }

    $names = @($parsed.dependencies.PSObject.Properties.Name)
    Write-Verbose "npm reports $($names.Count) global package(s)"
    return $names
}

function Invoke-UserEnvironmentCommand {
    <#
    .SYNOPSIS
        Runs one program in a new process with exactly the environment it is given, with a deadline.
    .DESCRIPTION
        The new process gets the variables handed to it and none of this process's own. Its input is
        closed at once, so a prompt reads the end of input instead of waiting, and both output streams
        are read while it runs, so a program that writes more than a pipe holds cannot stall. A process
        still running at the deadline is ended together with every process it started.

        Returns Started, false when the program could not be started at all, Output, the standard
        output followed by the standard error, ExitCode, -1 when it was not started or was ended, and
        TimedOut.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $FilePath,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [string[]] $ArgumentList,
        [Parameter(Mandatory)] [System.Collections.IDictionary] $Environment,
        [ValidateRange(1, 3600)] [int] $TimeoutSeconds = 120
    )

    $info = [System.Diagnostics.ProcessStartInfo]::new($FilePath)
    foreach ($argument in $ArgumentList) {
        $info.ArgumentList.Add($argument)
    }
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardInput = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.Environment.Clear()
    foreach ($name in @($Environment.Keys)) {
        $info.Environment[[string] $name] = [string] $Environment[$name]
    }

    try {
        $process = [System.Diagnostics.Process]::Start($info)
    } catch {
        return [PSCustomObject]@{ Started = $false; Output = $_.Exception.Message; ExitCode = -1; TimedOut = $false }
    }

    try {
        $process.StandardInput.Close()
        $readers = @($process.StandardOutput.ReadToEndAsync(), $process.StandardError.ReadToEndAsync())
        $timedOut = -not $process.WaitForExit($TimeoutSeconds * 1000)
        if ($timedOut) {
            try { $process.Kill($true) } catch { Write-Verbose "could not end $($process.Id): $($_.Exception.Message)" }
            $null = $process.WaitForExit(30000)
        } else {
            $process.WaitForExit()
        }

        $text = @(foreach ($reader in $readers) { if ($reader.Wait(30000)) { $reader.Result } }) -join "`n"

        return [PSCustomObject]@{
            Started  = $true
            Output   = $text
            ExitCode = $(if ($timedOut) { -1 } else { $process.ExitCode })
            TimedOut = $timedOut
        }
    } finally {
        $process.Dispose()
    }
}

function ConvertFrom-GradleVersionOutput {
    <#
    .SYNOPSIS
        Decides from one run of gradle --version whether Gradle started, and the Gradle version and JVM it named.
    .DESCRIPTION
        Gradle started when the run exited 0 and its output holds a line "Gradle <version>" and a line
        naming the JVM it runs on, "Launcher JVM:" from Gradle 9 and "JVM:" before it. The rule and
        the wording of Note are the ones the task "Read whether Gradle started" in
        setup/ansible/verify_install.yaml uses, and e2e/tier1/gradle_version_fixtures feeds both the
        same outputs. The lines are split on '\r?\n', because on Windows every line ends in both.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)] [ValidateNotNull()] [PSCustomObject] $Run,
        [Parameter(Mandatory)] [ValidateRange(1, 3600)] [int] $TimeoutSeconds
    )

    $version = ''
    $jvm = ''
    foreach ($line in @(([string] $Run.Output) -split '\r?\n')) {
        if (-not $version -and $line -cmatch '^Gradle\s+(\S+)\s*$') { $version = $Matches[1] }
        if (-not $jvm -and $line -cmatch '^(?:Launcher )?JVM:\s+(\S.*?)\s*$') { $jvm = $Matches[1] }
    }

    $started = $Run.Started -and -not $Run.TimedOut -and $Run.ExitCode -eq 0 -and $version -and $jvm
    $tail = Get-CommandOutputTail -Text ([string] $Run.Output)
    $note = if ($started) { "gradle --version: Gradle $version, JVM $jvm" }
            elseif (-not $Run.Started) { "gradle --version could not be started: $($Run.Output)" }
            elseif ($Run.TimedOut) { "gradle --version did not finish within $TimeoutSeconds seconds and was stopped" }
            elseif ($Run.ExitCode -ne 0) { "gradle --version exited $($Run.ExitCode): $(if ($tail) { $tail } else { 'and printed nothing' })" }
            elseif (-not $version) { 'gradle --version exited 0 and named no Gradle version' }
            else { 'gradle --version exited 0 and named no JVM' }

    return [PSCustomObject]@{ Started = [bool] $started; Gradle = $version; Jvm = $jvm; Note = $note }
}

function Get-GradleStartVerdict {
    <#
    .SYNOPSIS
        Starts gradle --version the way the user's terminal would, and says whether Gradle started.
    .DESCRIPTION
        Chocolatey listing gradle says only that the package unzipped. Gradle needs a Java runtime,
        from JAVA_HOME or a java on PATH, and the installs write both into the registry, which this
        process does not read again. So the command runs through cmd in a new process with the
        environment Get-WindowsUserEnvironment builds, which is what a new terminal gets, and the
        answer comes from ConvertFrom-GradleVersionOutput. TimeoutSeconds bounds a JVM that hangs.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [ValidateRange(1, 3600)] [int] $TimeoutSeconds = 120
    )

    $environment = Get-WindowsUserEnvironment
    $shell = if ($environment.ContainsKey('ComSpec') -and $environment['ComSpec']) { $environment['ComSpec'] } else { 'cmd.exe' }
    $run = Invoke-UserEnvironmentCommand -FilePath $shell -ArgumentList @('/d', '/c', 'gradle', '--version') `
        -Environment $environment -TimeoutSeconds $TimeoutSeconds
    return ConvertFrom-GradleVersionOutput -Run $run -TimeoutSeconds $TimeoutSeconds
}

function Format-WindowsVerificationReport {
    <#
    .SYNOPSIS
        Turns the verdict rows into the report a person reads, one line per application.
    .DESCRIPTION
        Every application gets a line, not only the failures. A report that prints what went wrong
        and stays silent about the rest cannot be used to answer "did it install Chrome", which is
        the question somebody actually has, and it hides the case this whole file exists for: a run
        where the verification itself examined nothing and said so by printing nothing.

        Returned rather than written, so the caller decides between the console, the log, or both.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [PSCustomObject[]] $Row,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [PSCustomObject[]] $Failure
    )

    $rule = '-' * 78
    $lines = [System.Collections.Generic.List[string]]::new()

    $lines.Add('=' * 78)
    $lines.Add("Installation verification: $([Environment]::OSVersion.VersionString), native Windows installer")
    $lines.Add("Taken at $([DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')). This asked the machine and changed nothing.")
    $lines.Add($rule)
    $lines.Add(('{0,-30} {1,-14} {2}' -f 'APPLICATION', 'VERDICT', 'HOW IT WAS ASKED'))
    $lines.Add($rule)

    # The loop variable is deliberately not a case-insensitive spelling of $Row. PowerShell treats
    # $row and $Row as one variable, so a loop over its own parameter leaves that parameter holding
    # the last item, and every count below it then measured a single row while the report above it
    # looked perfectly correct. Measured, not theorised: it read "requested 0 of 1 known items" under
    # a run that had just listed a hundred.
    # Note is what a row learned beyond the package being there, the Gradle and JVM gradle --version
    # named, and a row built without one prints none.
    foreach ($entry in $Row) {
        $note = if ($entry.PSObject.Properties['Note'] -and $entry.Note) { " ($($entry.Note))" } else { '' }
        $lines.Add(('{0,-30} {1,-14} {2}' -f $entry.Key, $entry.Verdict, "$($entry.Source): $($entry.Package)$note"))
    }

    $requested = @($Row | Where-Object { $_.Verdict -notin @($script:VerdictNotRequested, $script:VerdictNotMapped, $script:VerdictNotApplicable, $script:VerdictAbsent, $script:VerdictStillThere) })
    $notHere   = @($Row | Where-Object { $_.Verdict -eq $script:VerdictNotApplicable })
    $missing   = @($Row | Where-Object { $_.Verdict -in @($script:VerdictMissing, $script:VerdictDoesNotStart) })
    $unknown   = @($Row | Where-Object { $_.Verdict -eq $script:VerdictUnverifiable })
    $unmapped  = @($Row | Where-Object { $_.Verdict -eq $script:VerdictNotMapped })
    $stillHere = @($Row | Where-Object { $_.Verdict -eq $script:VerdictStillThere })

    $lines.Add($rule)
    $lines.Add("requested $($requested.Count) of $($Row.Count) known items: $($requested.Count - $missing.Count - $unknown.Count) installed, $($missing.Count) missing, $($unknown.Count) unverifiable")
    $lines.Add("missing: $(if ($missing.Count) { ($missing.Key | Sort-Object) -join ', ' } else { 'none' })")
    $lines.Add("unverifiable: $(if ($unknown.Count) { ($unknown.Key | Sort-Object) -join ', ' } else { 'none' })")
    $lines.Add("removed because another version is selected, and still there: $(if ($stillHere.Count) { ($stillHere.Key | Sort-Object) -join ', ' } else { 'none' })")

    # Named rather than counted away. Each one is a package the user asked for and will not get on
    # this machine, and the row above carries the reason, so a reader who wants to know why looks up
    # one line rather than at a number.
    $lines.Add("requested and not applicable to this machine: $(if ($notHere.Count) { ($notHere.Key | Sort-Object) -join ', ' } else { 'none' })")

    # Enabled, and nothing anywhere in this wizard installs it. Reported because the user asked for
    # it and will not get it, and not counted as a failure because most of these are Linux-only
    # toggles that a Windows run is right to ignore. e2e/tier1/toggle_coverage.sh is what fails when
    # one of them should have had a home.
    $lines.Add("enabled with nothing to install them: $(if ($unmapped.Count) { ($unmapped.Key | Sort-Object) -join ', ' } else { 'none' })")

    foreach ($failure in $Failure) {
        $lines.Add("  $($failure.Key) ($($failure.Package)): $($failure.Detail)")
    }

    if ($requested.Count -eq 0) {
        $lines.Add('Nothing was requested, so this verification proves nothing about this machine.')
    }
    $lines.Add('=' * 78)

    return $lines.ToArray()
}

function Invoke-WindowsVerification {
    <#
    .SYNOPSIS
        Verifies that everything this run asked for is on the machine, and returns the verdicts.
    .DESCRIPTION
        The Windows half of what setup/ansible/verify_install.yaml does everywhere else. It asks the
        machine rather than trusting the installer, it writes its full answer to a log beside the one
        the Unix wizard writes, and it returns a result whose Failed collection is what the caller
        folds into the exit code. A verification that cannot fail is decoration.

        It changes nothing. There is no install here, no registry write, no configuration, and no
        network fetch: every question is a list, a query or a Test-Path, and the only thing it
        creates is its own log file. e2e/tier1/verify_wiring.sh fails if a state-changing command
        ever appears in this file.

        Two verdicts fail the run and they are different. MISSING is an application that was asked
        for and is not here. UNVERIFIABLE is an application nothing could be asked about, because
        winget, Chocolatey or npm is not on this machine. The second is a failure for the reason the
        Ansible play gives for its own unreadable checks: an unverifiable claim is not a verified
        one, and a verification that quietly passes what it could not look at is the defect this
        whole harness exists to prevent. DOES NOT START fails the run as well: Gradle is installed and
        gradle --version did not name a Gradle version and a JVM.

    .PARAMETER AnsibleDir
        setup/ansible, from which the toggles and the Windows package mappings are read. The same
        directory the install phases read, so the selection this verifies against and the selection
        that was installed come from one place.

    .PARAMETER OnlyKeys
        The interactive checklist's narrowed selection, exactly as the install phases were given it.
        Not a filter this function invents: an application the user unticked must be reported as not
        requested rather than demanded and reported missing, which is what makes the whole step noise
        on the first customised install.

    .PARAMETER ToggleOverride
        The scripted selection from -Software, -EnableKey and -DisableKey, again exactly as the
        install phases were given it.

    .PARAMETER LogPath
        Where the full report is written. Defaults to installation_verify.log in the user profile,
        which is the name and the place the Unix wizard uses, so a person who has run both looks in
        one place.

    .EXAMPLE
        Invoke-WindowsVerification -AnsibleDir (Join-Path $PSScriptRoot '..\ansible')
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $AnsibleDir,

        [string[]] $OnlyKeys,

        [hashtable] $ToggleOverride,

        [ValidateNotNullOrEmpty()]
        [string] $LogPath = (Join-Path ([string]::IsNullOrEmpty($env:USERPROFILE) ? $HOME : $env:USERPROFILE) 'installation_verify.log')
    )

    $toggles = Get-WindowsSoftwareToggle `
        -AllVarsPath     (Join-Path $AnsibleDir 'group_vars\all.yaml') `
        -WindowsVarsPath (Join-Path $AnsibleDir 'group_vars\windows.yaml') `
        -ToggleOverride  $ToggleOverride
    $mappings = Get-WindowsSoftwareMapping -WindowsMappingPath (Join-Path $AnsibleDir 'vars\Windows.yaml')

    $rows = [System.Collections.Generic.List[object]]::new()
    $add = {
        param([string] $Key, [string] $Source, [string] $Package, [string] $Verdict, [string] $Detail)
        $rows.Add([PSCustomObject]@{
            Key = $Key; Source = $Source; Package = $Package; Verdict = $Verdict; Detail = $Detail; Note = ''
        })
    }

    # The same shape Invoke-WindowsCustomInstall uses to decide what it installs, so this asks about
    # exactly the set that was installed. Two spellings of the same question would drift, and the
    # drift would show up as an application reported missing because this half of the wizard never
    # heard that the user unticked it.
    $wanted = {
        param([string] $key)
        Test-WindowsToggleWanted -Toggles $toggles -OnlyKeys $OnlyKeys -Key $key
    }

    # What a requested app brought in, asked of the function the install asked, so the JDK Gradle
    # brought in is checked rather than reported as not requested, owner decision 61.
    $broughtIn = @(Resolve-WindowsBroughtInToggle -Toggles $toggles -OnlyKeys $OnlyKeys `
        -Prerequisite @(Get-WindowsTogglePrerequisite -AllVarsPath (Join-Path $AnsibleDir 'group_vars\all.yaml')) |
        ForEach-Object { $_.Needs -replace '^install_', '' })

    # --- the mapped software ------------------------------------------------
    # An empty mapping table would make every comparison below pass while examining nothing, which
    # reads exactly like a clean machine. Get-WindowsSoftwareMapping throws on a line it cannot
    # parse, so this covers the other shape: a file that parsed and held nothing.
    if ($mappings.Count -eq 0) {
        & $add 'windows package mappings' 'file' (Join-Path $AnsibleDir 'vars\Windows.yaml') `
            $script:VerdictUnverifiable 'the mapping file parsed to zero entries, so nothing could be checked against it'
    }

    $mappedKeys = @($mappings.Keys | Sort-Object)

    $wingetKeys = @($mappedKeys | Where-Object { $mappings[$_].Manager -eq 'winget' -and (& $wanted $_) })
    $winget     = $null
    $wingetWhy  = ''
    if ($wingetKeys.Count -gt 0) {
        # Get-WingetPath throws when App Installer is absent. That is one machine-wide answer rather
        # than a fault, and it must not end the run: the Chocolatey, npm and custom-install verdicts
        # below are all still obtainable, and losing them would leave the user with less information
        # than before this step existed.
        try {
            $winget = Get-WingetPath
            Write-Verbose "Asking winget at $winget about $($wingetKeys.Count) package(s)"
        } catch {
            $wingetWhy = $_.Exception.Message
        }
    }

    $chocoKeys = @($mappedKeys | Where-Object { $mappings[$_].Manager -eq 'choco' -and (& $wanted $_) })
    $chocoHere = [bool] (Get-Command choco -CommandType Application -ErrorAction SilentlyContinue)
    $chocoIds  = @()
    if ($chocoKeys.Count -gt 0 -and $chocoHere) {
        $chocoIds = @(Get-ChocolateyInstalledPackage)
        Write-Verbose "Chocolatey reports $($chocoIds.Count) installed package(s)"
    }

    # The same facts the install phase decided its skips on, and below, the same function deciding
    # from them. Not a copy of the rule: a second copy is what made the install phase install a
    # package this phase then called not applicable. Both live in WindowsSoftware.ps1, which
    # setup.ps1 dot-sources before this file precisely because the others read the mappings
    # through it.
    $machineFact = Get-WindowsMachineFact

    foreach ($key in $mappedKeys) {
        $mapping = $mappings[$key]
        $label   = "$($mapping.Manager): $($mapping.Package)"

        if (-not (& $wanted $key)) {
            & $add $key $mapping.Manager $mapping.Package $script:VerdictNotRequested ''
            continue
        }

        $skipReason = Test-WindowsPackageSkip -Item $mapping -Fact $machineFact
        if ($skipReason) {
            & $add $key $mapping.Manager $mapping.Package $script:VerdictNotApplicable `
                "$skipReason, so the install phase skipped it"
            continue
        }

        switch ($mapping.Manager) {
            'winget' {
                if (-not $winget) {
                    & $add $key 'winget' $mapping.Package $script:VerdictUnverifiable $wingetWhy
                } else {
                    # The rule the install asks after a winget exit 0, so the two cannot disagree. A
                    # package that registers nothing in Programs and Features, Tor Browser above all,
                    # is answered by the verify_path its mapping carries.
                    $probe = if ($mapping.PSObject.Properties['VerifyPath']) { $mapping.VerifyPath } else { '' }
                    $verdict = Get-WingetInstallVerdict -WingetPath $winget -PackageId $mapping.Package -VerifyPath $probe
                    if ($verdict.Installed) {
                        & $add $key 'winget' $mapping.Package $script:VerdictInstalled ''
                    } else {
                        & $add $key 'winget' $mapping.Package $script:VerdictMissing $verdict.Reason
                    }
                }
            }
            'choco' {
                if (-not $chocoHere) {
                    & $add $key 'choco' $mapping.Package $script:VerdictUnverifiable `
                        'choco is not on PATH, so Chocolatey cannot be asked whether this is installed'
                } elseif (($mapping.PSObject.Properties['Version'] -and $mapping.Version) -or ($mapping.PSObject.Properties['VerifyPath'] -and $mapping.VerifyPath)) {
                    $verdict = Get-ChocolateyInstallVerdict -PackageId $mapping.Package `
                        -Version $(if ($mapping.PSObject.Properties['Version']) { $mapping.Version } else { '' }) `
                        -VerifyPath $(if ($mapping.PSObject.Properties['VerifyPath']) { $mapping.VerifyPath } else { '' })
                    if ($verdict.Installed) {
                        & $add $key 'choco' $mapping.Package $script:VerdictInstalled ''
                    } else {
                        & $add $key 'choco' $mapping.Package $script:VerdictMissing $verdict.Reason
                    }
                } elseif ($chocoIds -contains $mapping.Package) {
                    & $add $key 'choco' $mapping.Package $script:VerdictInstalled ''
                } else {
                    & $add $key 'choco' $mapping.Package $script:VerdictMissing `
                        'Chocolatey does not list it among its locally installed packages'
                }
            }
            default {
                # vars/Windows.yaml holds winget and choco entries only. A third manager arriving
                # here without a question to ask about it is a package the wizard installs and
                # nothing checks, which is exactly the shape of defect this file exists to end.
                & $add $key $mapping.Manager $mapping.Package $script:VerdictUnverifiable `
                    "no verification knows how to ask about the '$($mapping.Manager)' manager, so this package is installed and checked by nothing"
            }
        }
        Write-Verbose "asked about $key ($label)"
    }

    # --- Gradle has to start --------------------------------------------------
    # Chocolatey listing gradle says the package unzipped, and that Gradle cannot start without a Java
    # runtime, docs/regression_ledger.md 10.360 and 10.368. So the row counts as installed only when
    # gradle --version starts, and it names the Gradle and the JVM either way.
    $gradleRows = @($rows | Where-Object { $_.Key -eq 'gradle' -and $_.Verdict -eq $script:VerdictInstalled })
    if ($gradleRows.Count -eq 1) {
        $gradleStart = Get-GradleStartVerdict
        $gradleRows[0].Note = $gradleStart.Note
        if (-not $gradleStart.Started) {
            $gradleRows[0].Verdict = $script:VerdictDoesNotStart
            $gradleRows[0].Detail = $gradleStart.Note
        }
    }

    # --- the npm CLI tools ---------------------------------------------------
    $npmPackages = Get-NpmToolPackage
    $npmKeys     = @(@($npmPackages.Keys) | Where-Object { & $wanted $_ })
    $npmGlobals  = $null
    if ($npmKeys.Count -gt 0) {
        $npmGlobals = Get-NpmGlobalPackage
    }

    foreach ($key in $npmPackages.Keys) {
        $package = $npmPackages[$key].Package
        if ($key -notin $npmKeys) {
            & $add $key 'npm' $package $script:VerdictNotRequested ''
        } elseif ($null -eq $npmGlobals) {
            & $add $key 'npm' $package $script:VerdictUnverifiable `
                'npm is not on PATH or did not answer, so whether this tool is installed is unknown. Install Node.js first, then rerun.'
        } elseif ($npmGlobals -contains $package) {
            & $add $key 'npm' $package $script:VerdictInstalled ''
        } else {
            & $add $key 'npm' $package $script:VerdictMissing 'npm ls -g does not list it among the global packages'
        }

        # The package this one replaces, which the npm phase removed.
        $replaced = if ($npmPackages[$key].ContainsKey('Replaces')) { $npmPackages[$key].Replaces } else { '' }
        if (-not $replaced -or $key -notin $npmKeys) { continue }
        if ($null -eq $npmGlobals) {
            & $add "$key, replaced" 'npm' $replaced $script:VerdictUnverifiable 'npm is not on PATH or did not answer, so whether it is gone is unknown'
        } elseif ($npmGlobals -contains $replaced) {
            & $add "$key, replaced" 'npm' $replaced $script:VerdictStillThere "npm ls -g still lists it, and it claims the same command as $package"
        } else {
            & $add "$key, replaced" 'npm' $replaced $script:VerdictAbsent ''
        }
    }

    # --- the installs no package mapping can express -------------------------
    # The pinned values decide two of the five proof paths, the Java majors and the Flutter channel.
    # A reader that cannot load them leaves those two with nothing to look for, which is reported as
    # unverifiable below rather than passed over.
    $versions = @{}
    $pinsWhy  = ''
    try {
        $versions = Get-PinnedValueMap
    } catch {
        $pinsWhy = $_.Exception.Message
    }
    $proofs = Get-WindowsCustomInstallProof -Versions $versions -DefaultJavaOnly:('java' -in $broughtIn)

    foreach ($key in (Get-WindowsCustomInstallKey)) {
        if (-not (& $wanted $key) -and $key -notin $broughtIn) {
            & $add $key 'custom' 'installed by setup/windows/WindowsCustomInstalls.ps1' $script:VerdictNotRequested ''
            continue
        }

        if (-not $proofs.Contains($key)) {
            & $add $key 'custom' 'no proof path' $script:VerdictUnverifiable `
                'WindowsCustomInstalls.ps1 installs this and declares nothing that must exist afterwards, so it cannot be checked'
            continue
        }

        $proof = $proofs[$key]
        $paths = @($proof.Path)

        # An empty path list makes the -All test below true over nothing, which passes and reads
        # exactly like a proven install. That is how the Ansible play's own expected-set assertion
        # came to exist, and it is the only reason a broken pins load is visible here at all.
        if ($paths.Count -eq 0) {
            & $add $key 'custom' $proof.Description $script:VerdictUnverifiable `
                "nothing to look for: $(if ($pinsWhy) { $pinsWhy } else { 'the pinned values name no version for this' })"
            continue
        }

        $found = @($paths | Where-Object { Test-Path -Path $_ })
        $ok = if ($proof.Mode -eq 'Any') { $found.Count -gt 0 } else { $found.Count -eq $paths.Count }

        # The OpenCode desktop app: an older major version sits at the same path, so the path alone cannot say which.
        if ($ok -and $key -eq 'opencode_desktop' -and -not (Test-OpenCodeDesktopVersion -Path $paths[0])) {
            & $add $key 'custom' $proof.Description $script:VerdictMissing `
                "$($paths[0]) is there and is not OpenCode version 2"
            continue
        }

        if ($ok) {
            & $add $key 'custom' $proof.Description $script:VerdictInstalled ($found -join '; ')
        } else {
            & $add $key 'custom' $proof.Description $script:VerdictMissing `
                "$($paths.Count - $found.Count) of $($paths.Count) path(s) that this install has to produce do not exist: $((@($paths | Where-Object { $_ -notin $found })) -join '; ')"
        }
    }

    # --- enabled, and nothing installs it ------------------------------------
    $handledElsewhere = @(@($npmPackages.Keys) + @(Get-WindowsCustomInstallKey))
    foreach ($key in ($toggles.Keys | Sort-Object)) {
        if (-not (& $wanted $key)) { continue }
        if ($mappings.ContainsKey($key)) { continue }
        if ($key -in $handledElsewhere) { continue }
        & $add $key 'nothing' 'no winget or Chocolatey mapping, no npm package, no custom install' `
            $script:VerdictNotMapped 'enabled, and no part of this wizard installs it on Windows'
    }

    # --- the verdict the caller acts on --------------------------------------
    $all     = $rows.ToArray()
    $missing = @($all | Where-Object { $_.Verdict -in @($script:VerdictMissing, $script:VerdictStillThere, $script:VerdictDoesNotStart) })
    $unknown = @($all | Where-Object { $_.Verdict -eq $script:VerdictUnverifiable })

    # Shaped like the Key, Package and Detail rows every install phase returns for its failures, so
    # the caller renders one kind of failure line rather than two.
    $failed = @(@($missing) + @($unknown) | ForEach-Object {
        [PSCustomObject]@{ Key = $_.Key; Package = $_.Package; Detail = $_.Detail }
    })

    $report = Format-WindowsVerificationReport -Row $all -Failure $failed

    # The log is written before the result is returned, so a caller that throws on the way to
    # rendering still leaves the full answer on disk. The failure to write is reported inside the
    # result rather than thrown, because losing the log is not a reason to lose the verdict.
    #
    # This one line is the only thing in this file that writes anything anywhere, and
    # e2e/tier1/verify_wiring.sh fails if a second write ever appears or if this one stops naming
    # the log.
    $logWritten = $true
    try {
        Set-Content -LiteralPath $LogPath -Value $report -Encoding utf8
    } catch {
        $logWritten = $false
        Write-Verbose "could not write $LogPath : $($_.Exception.Message)"
    }

    return [PSCustomObject]@{
        Results      = $all
        Installed    = @($all | Where-Object { $_.Verdict -eq $script:VerdictInstalled })
        Missing      = $missing
        Unverifiable = $unknown
        NotRequested = @($all | Where-Object { $_.Verdict -eq $script:VerdictNotRequested })
        NotApplicable = @($all | Where-Object { $_.Verdict -eq $script:VerdictNotApplicable })
        Unmapped     = @($all | Where-Object { $_.Verdict -eq $script:VerdictNotMapped })
        Failed       = $failed
        Report       = $report
        LogPath      = $LogPath
        LogWritten   = $logWritten
    }
}
