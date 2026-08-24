#Requires -Version 7.2
<#
.SYNOPSIS
    The Windows installs that a single package mapping cannot express.

.DESCRIPTION
    vars/Windows.yaml maps a toggle to one package, which covers 89 of them. Five toggles need
    more than that, and every one of them had an Ansible task file for Windows that can never
    run, because the playbook is invoked from inside WSL and reports os_family Debian. See
    docs/regression_ledger.md.

      install_java          four JDKs plus JAVA_HOME, not one package
      install_nodejs        a version manager, then a Node version inside it
      install_flutter       a version manager, then a channel inside it, then a global pin
      install_gridcoin      a direct installer download, no package anywhere

    Every version comes from the pinned values, read through setup/pinned_values, so the pins
    stay a single source of truth with the Unix path. Nothing here writes to the console: the
    caller renders, which keeps the functions testable.

    Depends on Get-WingetPath, Install-WingetPackage and Install-ChocolateyPackageBatch from
    WindowsSoftware.ps1, which setup.ps1 dot-sources first.
#>

Set-StrictMode -Version Latest

# The pinned versions and download locations, read through the one adapter allowed to reach them.
# This file used to carry its own resolver over the YAML, one of three hand-written parsers of the
# same data that could disagree with each other. Nothing here parses anything now.
Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'pinned_values\PinnedValues.psm1')

# The toggles this file is responsible for. Declared as data rather than left implicit in the
# dispatch below, so e2e/tier1/toggle_coverage.sh can ask what is covered here instead of inferring
# it. Without that, an install_ toggle whose only consumer is an unreachable Windows Ansible task
# counts as covered, which is how eleven toggles sat enabled and installing nothing while the gate
# reported full coverage.
$script:CustomInstallKeys = @('java', 'nodejs', 'flutter', 'android_sdk', 'gridcoin')

# Where the Android SDK goes on Windows. Chosen by Lukk, and it works without elevation: the default
# ACL on the root of C: grants Authenticated Users AppendData on the folder itself, so a standard
# user can create a directory there and owns what it creates. Measured on this machine, where
# C:\tools already exists with Modify for Authenticated Users because Chocolatey created it.
#
# Declared here rather than inside the installer because three things have to agree about it: the
# installer that writes it, the proof table the verification reads, and the environment variables
# pointed at it. That is the same drift that left ANDROID_SDK_ROOT on Linux pointing at /opt/android
# while the installer wrote to ~/Android/Sdk for years.
$script:AndroidSdkRoot = 'C:\tools\android'

# The pins that name the four JDKs, in the order they are installed. Read twice, once to derive the
# packages and once to derive the directories those packages have to leave behind, so the list is
# declared rather than written out at both sites.
$script:JavaPinKeys = @('java11_id', 'java17_id', 'java21_id', 'java25_id')

function Get-WindowsCustomInstallKey {
    <#
    .SYNOPSIS
        The toggles handled by this file, so the coverage check and the installer read one list.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param()
    return $script:CustomInstallKeys
}

function Get-FlutterChannel {
    <#
    .SYNOPSIS
        The Flutter channel this run installs, falling back to stable when nothing pins one.
    .DESCRIPTION
        Read by the installer for the argument it passes to fvm and by the proof table for the
        directory that argument has to produce. One expression, because a fallback that differs
        between the two would have the verification look for a channel the install never asked for.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [hashtable] $Versions)

    if ($Versions.ContainsKey('flutter_channel') -and $Versions['flutter_channel']) {
        return [string] $Versions['flutter_channel']
    }
    return 'stable'
}

function Get-WindowsCustomInstallProof {
    <#
    .SYNOPSIS
        What has to exist on disk for each custom install to count as done.
    .DESCRIPTION
        Ledger rule 5 in one table: an install that exits zero and leaves nothing behind is still a
        bug. Install-DirectInstaller already refuses to call a run successful without its ProofPath,
        and setup/windows/WindowsVerify.ps1 asks the same question again after the whole run, from
        the same table, so the installer's idea of proof and the verification's cannot drift. A
        drifted proof path reports a working install as missing, and a false failure nobody can
        reproduce is how a verification stops being read.

        Each entry carries one or more paths, which Test-Path accepts with a wildcard, and a mode.
        All means every path has to exist, which is how four JDKs are one verdict. Any means one is
        enough, which is how a tool with more than one documented install location is asked about
        without guessing which one this machine used.

        Two entries are read by the verification only, and they are the two the installer proves
        differently as it goes. Java is proved by discovering the directory it points JAVA_HOME at,
        and Node by nvm's own exit codes, neither of which survives the end of the run.

        The Node paths are the nvm-windows defaults rather than a verified observation, and they are
        ordered so an installation that set NVM_HOME answers from that first. If a machine with a
        working nvm reports this missing, the path is wrong rather than the install, which is the
        safe direction: a false failure gets investigated and a false success does not.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param([Parameter(Mandatory)] [hashtable] $Versions)

    $adoptium = Join-Path $env:ProgramFiles 'Eclipse Adoptium'

    # A pin that names no major version yields no path rather than a wrong one. The verification
    # reports an entry with nothing to look for as unverifiable, which is the honest answer: the
    # same broken pin also stopped the install from happening.
    $jdkPaths = [System.Collections.Generic.List[string]]::new()
    foreach ($key in $script:JavaPinKeys) {
        if (-not $Versions.ContainsKey($key)) { continue }
        try {
            $jdkPaths.Add((Join-Path $adoptium "jdk-$(Get-TemurinMajor -SdkmanId $Versions[$key])*"))
        } catch {
            Write-Verbose "no Temurin directory could be derived from ${key}: $($_.Exception.Message)"
        }
    }

    $nvmHome = if ($env:NVM_HOME) { $env:NVM_HOME } else { Join-Path $env:ProgramData 'nvm' }
    $channel = Get-FlutterChannel -Versions $Versions

    return [ordered]@{
        java = [PSCustomObject]@{
            Path        = $jdkPaths.ToArray()
            Mode        = 'All'
            Description = "the pinned Temurin JDKs under $adoptium"
        }
        nodejs = [PSCustomObject]@{
            Path        = @((Join-Path $nvmHome 'nvm.exe'), (Join-Path $env:APPDATA 'nvm\nvm.exe'))
            Mode        = 'Any'
            Description = 'nvm-windows, which is what install_nodejs installs Node inside'
        }
        flutter = [PSCustomObject]@{
            Path        = @(Join-Path $env:USERPROFILE "fvm\versions\$channel\bin\flutter.bat")
            Mode        = 'All'
            Description = "the Flutter $channel channel installed by FVM"
        }
        android_sdk = [PSCustomObject]@{
            Path        = @((Join-Path $script:AndroidSdkRoot 'cmdline-tools\latest\bin\sdkmanager.bat'),
                            (Join-Path $script:AndroidSdkRoot 'platform-tools\adb.exe'))
            Mode        = 'All'
            Description = "the Android command line tools and platform-tools under $script:AndroidSdkRoot"
        }
        gridcoin = [PSCustomObject]@{
            Path        = @(Join-Path $env:ProgramFiles 'Gridcoin')
            Mode        = 'All'
            Description = 'the Gridcoin installation directory'
        }
    }
}

function Get-TemurinMajor {
    <#
    .SYNOPSIS
        The major version out of an SDKMAN Java identifier such as 21.0.11-tem.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $SdkmanId
    )

    if ($SdkmanId -notmatch '^(?<major>\d+)\.') {
        throw "Java identifier '$SdkmanId' does not start with a major version, so no Temurin package can be derived from it"
    }
    return $Matches['major']
}

function Install-TemurinJdk {
    <#
    .SYNOPSIS
        Installs the pinned Temurin JDKs and points JAVA_HOME at the default one.
    .DESCRIPTION
        SDKMAN needs bash and cannot run on Windows, so there is no version manager here. The four
        pinned majors are installed as four winget packages instead, which is the same vendor and
        the same four versions the Unix path gets.

        The dead sdkman_windows.yaml named Chocolatey packages temurin11, temurin17, temurin21 and
        temurin. None of those exist on the Chocolatey feed, and it then set JAVA_HOME machine-wide
        to the hardcoded path C:\Program Files\Eclipse Adoptium\jdk-21.0.6+7-hotspot, which pins a
        patch version that will not be what gets installed. JAVA_HOME is discovered here instead,
        by looking for the directory the install actually produced.

        JAVA_HOME is set for the user, not the machine, because setup.ps1 refuses to run elevated
        and a machine-level environment variable needs administrator rights.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [hashtable] $Versions
    )

    $results = [System.Collections.Generic.List[object]]::new()
    $majors  = [System.Collections.Generic.List[string]]::new()

    # Each derivation is caught, because Get-TemurinMajor throws on an identifier that does not start
    # with a major version and this function's contract is that one bad item never takes the others
    # down. That contract was broken: an unthrown exception here propagated out of
    # Invoke-WindowsCustomInstall, which setup.ps1 does not wrap, so a malformed java pin killed
    # nodejs, flutter and gridcoin with it and stopped the wizard before the WSL
    # playbook ran. The reader now refuses to hand out an unresolved reference, so that exact shape
    # cannot arrive any more, but a pin bumped to anything a major version cannot be read out of
    # still lands here, and it must not take the other four items down with it.
    foreach ($key in $script:JavaPinKeys) {
        if (-not $Versions.ContainsKey($key)) {
            $results.Add([PSCustomObject]@{ Key = 'java'; Package = $key; Status = 'failed'
                                            Detail = "nothing pins $key, so no Temurin package could be derived" })
            continue
        }
        try {
            $majors.Add((Get-TemurinMajor -SdkmanId $Versions[$key]))
        } catch {
            $results.Add([PSCustomObject]@{ Key = 'java'; Package = $key; Status = 'failed'
                                            Detail = $_.Exception.Message })
        }
    }

    # Get-WingetPath throws when App Installer is absent, and this function's contract, stated
    # eleven lines above, is that one bad item never takes the others down. It was broken here in
    # the same way it was broken for the java pins: setup.ps1 runs with $ErrorActionPreference
    # 'Stop' and does not wrap this call, so a machine without winget lost nodejs, flutter,
    # gridcoin and every summary line along with the four JDKs. One failed result per
    # JDK instead, then JAVA_HOME is still attempted, because a JDK installed by some earlier means
    # is worth pointing at and finding none is already reported below.
    $winget = $null
    try {
        $winget = Get-WingetPath
    } catch {
        foreach ($major in $majors) {
            $results.Add([PSCustomObject]@{ Key = 'java'; Package = "EclipseAdoptium.Temurin.$major.JDK"
                                            Status = 'failed'; Detail = $_.Exception.Message })
        }
    }

    if ($winget) {
        foreach ($major in $majors) {
            $r = Install-WingetPackage -WingetPath $winget -PackageId "EclipseAdoptium.Temurin.$major.JDK"
            $results.Add([PSCustomObject]@{ Key = 'java'; Package = $r.Package; Status = $r.Status; Detail = $r.Detail })
        }
    }

    # JAVA_HOME last, so it points at something that exists. Discovered rather than constructed:
    # the directory carries the full patch version and the hotspot suffix, neither of which the
    # pin knows. Falls back to 21 when default_java is unpinned or malformed, which is the pinned
    # default itself, rather than throwing out of the whole phase.
    $defaultMajor = '21'
    if ($Versions.ContainsKey('default_java')) {
        try {
            $defaultMajor = Get-TemurinMajor -SdkmanId $Versions['default_java']
        } catch {
            $results.Add([PSCustomObject]@{ Key = 'java'; Package = 'default_java'; Status = 'failed'
                                            Detail = "$($_.Exception.Message) Falling back to major 21 for JAVA_HOME." })
        }
    }
    $adoptium = Join-Path $env:ProgramFiles 'Eclipse Adoptium'
    $jdkDir = Get-ChildItem -Path $adoptium -Directory -Filter "jdk-$defaultMajor*" -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending | Select-Object -First 1

    if (-not $jdkDir) {
        # Under -WhatIf the winget installs above were never really run, so no jdk-$defaultMajor*
        # directory existing yet is the expected shape of a dry run, not a failure. Reporting it as
        # failed here is exactly the lie a dry run must not tell: a clean machine that has never run
        # this wizard before would show a false failure on its very first -WhatIf.
        if ($WhatIfPreference) {
            $results.Add([PSCustomObject]@{ Key = 'java'; Package = 'JAVA_HOME'; Status = 'skipped'
                                            Detail = "WhatIf, would look for a jdk-$defaultMajor* directory under $adoptium and point JAVA_HOME at it" })
            return $results
        }
        $results.Add([PSCustomObject]@{ Key = 'java'; Package = 'JAVA_HOME'; Status = 'failed'
                                        Detail = "no jdk-$defaultMajor* directory under $adoptium, so JAVA_HOME was left alone rather than pointed at nothing" })
        return $results
    }

    if ($PSCmdlet.ShouldProcess("JAVA_HOME=$($jdkDir.FullName)", 'set user environment variable')) {
        [Environment]::SetEnvironmentVariable('JAVA_HOME', $jdkDir.FullName, 'User')
        $results.Add([PSCustomObject]@{ Key = 'java'; Package = 'JAVA_HOME'; Status = 'installed'; Detail = $jdkDir.FullName })
    } else {
        $results.Add([PSCustomObject]@{ Key = 'java'; Package = 'JAVA_HOME'; Status = 'skipped'; Detail = 'WhatIf' })
    }

    return $results
}

function Update-ProcessPath {
    <#
    .SYNOPSIS
        Rebuilds PATH in this process from the machine and user values in the registry.
    .DESCRIPTION
        Chocolatey writes its shims and the tools' own entries into the registry PATH, and a
        process that was already running does not see them. So on a fresh machine `choco install
        nvm` succeeds and the very next `nvm install lts` reports command not found, which reads as
        a broken install rather than a stale environment. This is what Chocolatey's own refreshenv
        does, minus needing a new shell.

        The process value is rebuilt rather than appended to, because appending on every call grows
        PATH without bound across a long wizard run.
    #>
    [CmdletBinding()]
    param()

    $machine = [Environment]::GetEnvironmentVariable('PATH', 'Machine')
    $user    = [Environment]::GetEnvironmentVariable('PATH', 'User')
    $combined = @($machine, $user) | Where-Object { $_ } | ForEach-Object { $_.TrimEnd(';') }
    [Environment]::SetEnvironmentVariable('PATH', ($combined -join ';'), 'Process')
    Write-Verbose "PATH refreshed from the registry, $((($combined -join ';') -split ';').Count) entries"
}

function Invoke-ManagedTool {
    <#
    .SYNOPSIS
        Runs one command of a version manager and returns a result object.
    .DESCRIPTION
        Shared by the Node and Flutter paths, which are the same shape: install a manager through
        Chocolatey, then drive it. stdin is redirected from an empty file, so a prompt reads
        immediate EOF instead of blocking, and a timeout is enforced on top of that, because an
        interactive prompt inside one of these is exactly what stalled the Unix FVM path for eight
        hours with no signal. See docs/regression_ledger.md.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $Key,
        [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $FilePath,
        [Parameter(Mandatory)] [string[]] $ArgumentList,
        [ValidateRange(1, 120)] [int] $TimeoutMinutes = 30,
        [hashtable] $Environment = @{}
    )

    $label = "$FilePath $($ArgumentList -join ' ')"
    if (-not (Get-Command $FilePath -CommandType Application -ErrorAction SilentlyContinue)) {
        return [PSCustomObject]@{ Key = $Key; Package = $label; Status = 'failed'
                                  Detail = "$FilePath is not on PATH. Its installer may need a new shell before the command is visible, so rerun the wizard once." }
    }

    if (-not $PSCmdlet.ShouldProcess($label, 'run')) {
        return [PSCustomObject]@{ Key = $Key; Package = $label; Status = 'skipped'; Detail = 'WhatIf' }
    }

    $restore = @{}
    foreach ($name in $Environment.Keys) {
        $restore[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
        [Environment]::SetEnvironmentVariable($name, $Environment[$name], 'Process')
    }

    $stdin = New-TemporaryFile
    $stdout = New-TemporaryFile
    $stderr = New-TemporaryFile
    try {
        $p = Start-Process -FilePath $FilePath -ArgumentList $ArgumentList -NoNewWindow -PassThru `
            -RedirectStandardInput $stdin -RedirectStandardOutput $stdout -RedirectStandardError $stderr
        if (-not $p.WaitForExit($TimeoutMinutes * 60 * 1000)) {
            try { $p.Kill($true) } catch { Write-Verbose "could not kill $($p.Id): $($_.Exception.Message)" }
            return [PSCustomObject]@{ Key = $Key; Package = $label; Status = 'failed'
                                      Detail = "still running after $TimeoutMinutes minutes and was killed, so it is NOT installed. Run it by hand to see what it was waiting for." }
        }
        if ($p.ExitCode -eq 0) {
            return [PSCustomObject]@{ Key = $Key; Package = $label; Status = 'installed'; Detail = '' }
        }
        $tail = @(Get-Content -LiteralPath $stderr -ErrorAction SilentlyContinue
                  Get-Content -LiteralPath $stdout -ErrorAction SilentlyContinue) |
                Where-Object { $_ -and $_.Trim() } | Select-Object -Last 2
        return [PSCustomObject]@{ Key = $Key; Package = $label; Status = 'failed'
                                  Detail = "exit $($p.ExitCode). $($tail -join ' ')" }
    } finally {
        foreach ($name in $restore.Keys) { [Environment]::SetEnvironmentVariable($name, $restore[$name], 'Process') }
        Remove-Item -LiteralPath $stdin, $stdout, $stderr -Force -ErrorAction SilentlyContinue
    }
}

function Install-NodeViaNvm {
    <#
    .SYNOPSIS
        Installs nvm-windows, then the current Node LTS inside it.
    .DESCRIPTION
        nvm_windows.yaml installed the manager and stopped there, which leaves no Node behind and
        makes the toggle a no-op in practice. The Unix path runs `nvm install --lts`, so this does
        the equivalent. nvm-windows spells it `nvm install lts` with no dashes.

        The nvm_version pin is for nvm.sh and does not apply here: nvm-windows is a separate
        project with its own versioning.

        winget rather than Chocolatey, and that is measured. Chocolatey's `nvm` is a meta-package
        that only depends on `nvm.install`, and installing it exited -1 on both Windows cells of
        2026-08-22 with nothing in the log to say why. winget carries CoreyButler.NVMforWindows,
        which is the vendor's own installer with no dependency chain in front of it, and it is what
        winstall and the project's own README point people at.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param()

    $results = [System.Collections.Generic.List[object]]::new()

    $winget = $null
    try { $winget = Get-WingetPath } catch {
        $results.Add([PSCustomObject]@{ Key = 'nodejs'; Package = 'nvm'; Status = 'failed'
                                        Detail = "winget is not on this machine, so nvm-windows cannot be installed: $($_.Exception.Message)" })
        return $results
    }

    $manager = Install-WingetPackage -WingetPath $winget -PackageId 'CoreyButler.NVMforWindows'
    $results.Add([PSCustomObject]@{ Key = 'nodejs'; Package = 'nvm'; Status = $manager.Status; Detail = $manager.Detail })
    if ($manager.Status -eq 'failed') { return $results }

    # Skipped rather than attempted when the manager itself was skipped. Under -WhatIf nvm was never
    # installed, so running the next two steps for real reported two failures for a plan that had not
    # done anything yet, which is a lie about the plan.
    if ($manager.Status -eq 'skipped') {
        foreach ($step in @('install lts', 'use lts')) {
            $results.Add([PSCustomObject]@{ Key = 'nodejs'; Package = "nvm $step"; Status = 'skipped'
                                            Detail = 'not attempted because nvm itself was skipped' })
        }
        return $results
    }

    Update-ProcessPath
    $results.Add((Invoke-ManagedTool -Key 'nodejs' -FilePath 'nvm' -ArgumentList @('install', 'lts') -TimeoutMinutes 15))
    $results.Add((Invoke-ManagedTool -Key 'nodejs' -FilePath 'nvm' -ArgumentList @('use', 'lts') -TimeoutMinutes 5))
    return $results
}

function Add-ToUserPath {
    <#
    .SYNOPSIS
        Puts one directory on the user PATH, once, and on this process's PATH straight away.

    .DESCRIPTION
        The same read, compare and write the Android SDK environment step does, factored out because
        a second install needed it. A directory already there is left alone, so a rerun writes
        nothing, and the process PATH is updated too, because the wizard runs `fvm` a moment later
        and a variable written to the registry does not reach a process that is already running.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $Directory
    )

    $current = [Environment]::GetEnvironmentVariable('PATH', 'User')
    $entries = @($current -split ';' | Where-Object { $_ })
    if ($Directory -notin $entries) {
        if ($PSCmdlet.ShouldProcess($Directory, 'add to the user PATH')) {
            [Environment]::SetEnvironmentVariable('PATH', (($entries + $Directory) -join ';'), 'User')
        }
    }
    if (($env:PATH -split ';') -notcontains $Directory) {
        $env:PATH = "$Directory;$env:PATH"
    }
}

function Install-FvmFromPub {
    <#
    .SYNOPSIS
        Installs the FVM command line tool from pub.dev, through the Dart SDK.

    .DESCRIPTION
        pub.dev is Dart's package registry, run by Google, and it lists fvm under the verified
        publisher leoafarias.com. `dart pub global activate fvm` is what FVM's own documentation
        gives for a machine that already has Dart, and this repository installs the Dart SDK on
        Windows through Chocolatey in the software phase that runs before this one.

        Two things this deliberately avoids. A zip downloaded from a GitHub account, which is what
        an earlier version of this function did. And Chocolatey's `fvm` package, which declares
        `dart-sdk:[3.9.0]` as an exact dependency, so installing a 4 MB version manager pulled a
        whole second pinned Dart SDK in ahead of it and exited 1 on both Windows cells of
        2026-08-22.

        pub global activate puts the executable in the pub cache's bin directory, which is not on
        PATH by default, so that directory is added here.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param()

    $pubBin = Join-Path $env:LOCALAPPDATA 'Pub\Cache\bin'
    $exe    = Join-Path $pubBin 'fvm.bat'

    if (Test-Path -LiteralPath $exe) {
        Add-ToUserPath -Directory $pubBin
        return [PSCustomObject]@{ Status = 'present'; Detail = $exe }
    }

    if (-not (Get-Command dart -ErrorAction SilentlyContinue)) {
        Update-ProcessPath
    }
    if (-not (Get-Command dart -ErrorAction SilentlyContinue)) {
        return [PSCustomObject]@{ Status = 'failed'
                                  Detail = 'dart is not on PATH, so fvm cannot be activated from pub.dev. install_dart is what puts it there, and it runs in the software phase before this one.' }
    }

    if (-not $PSCmdlet.ShouldProcess('fvm', 'dart pub global activate')) {
        return [PSCustomObject]@{ Status = 'skipped'; Detail = 'WhatIf' }
    }

    $activate = Invoke-ManagedTool -Key 'flutter' -FilePath 'dart' `
        -ArgumentList @('pub', 'global', 'activate', 'fvm') -TimeoutMinutes 10
    if ($activate.Status -eq 'failed') {
        return [PSCustomObject]@{ Status = 'failed'; Detail = $activate.Detail }
    }

    Add-ToUserPath -Directory $pubBin
    if (-not (Test-Path -LiteralPath $exe)) {
        return [PSCustomObject]@{ Status = 'failed'
                                  Detail = "dart pub global activate fvm reported success and $exe is absent, so nothing usable was installed" }
    }
    return [PSCustomObject]@{ Status = 'installed'; Detail = $exe }
}

function Install-FlutterViaFvm {
    <#
    .SYNOPSIS
        Installs FVM, then the pinned Flutter channel, then pins it globally.
    .DESCRIPTION
        pub.dev through the Dart SDK, rather than Chocolatey or a downloaded archive. pub.dev is
        Google's registry for Dart packages and lists fvm under the verified publisher
        leoafarias.com, and the Dart SDK is already installed on Windows by install_dart in the
        software phase before this one. Chocolatey's `fvm` 4.1.5 was the previous route and it
        declares `dart-sdk:[3.9.0]` as an exact dependency, so a 4 MB version manager arrived behind
        a second pinned SDK and exited 1 on both Windows cells of 2026-08-22. winget has no FVM
        manifest at all, checked again on 2026-08-23.

        `fvm global` creates a symlink under %USERPROFILE%\fvm\default, which needs Developer Mode
        enabled or an elevated run. That is reported rather than treated as fatal, because the
        channel is installed and usable through `fvm use` either way.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [hashtable] $Versions
    )

    $channel = Get-FlutterChannel -Versions $Versions
    $results = [System.Collections.Generic.List[object]]::new()

    $manager = Install-FvmFromPub
    $results.Add([PSCustomObject]@{ Key = 'flutter'; Package = 'fvm'; Status = $manager.Status; Detail = $manager.Detail })
    if ($manager.Status -eq 'failed') { return $results }

    if ($manager.Status -eq 'skipped') {
        foreach ($step in @("install $channel", "global $channel")) {
            $results.Add([PSCustomObject]@{ Key = 'flutter'; Package = "fvm $step"; Status = 'skipped'
                                            Detail = 'not attempted because fvm itself was skipped' })
        }
        return $results
    }

    Update-ProcessPath

    # Flutter's first-run analytics prompt is what these two variables suppress. The Unix path
    # needed them and there is no reason to find out the hard way whether Windows does. Not named
    # $env, which would shadow the environment provider two lines below.
    $fvmEnv = @{ CI = 'true'; FLUTTER_SUPPRESS_ANALYTICS = 'true' }

    # The same path the verification looks for after the run, from the one table that holds it.
    $installed = @((Get-WindowsCustomInstallProof -Versions $Versions)['flutter'].Path)[0]
    if (Test-Path -LiteralPath $installed) {
        $results.Add([PSCustomObject]@{ Key = 'flutter'; Package = "fvm install $channel"; Status = 'present'; Detail = '' })
    } else {
        $results.Add((Invoke-ManagedTool -Key 'flutter' -FilePath 'fvm' -ArgumentList @('install', $channel) -TimeoutMinutes 30 -Environment $fvmEnv))
    }

    $global = Invoke-ManagedTool -Key 'flutter' -FilePath 'fvm' -ArgumentList @('global', $channel) -TimeoutMinutes 5 -Environment $fvmEnv
    if ($global.Status -eq 'failed') {
        $global.Detail = "$($global.Detail) `fvm global` needs a symlink, which needs Developer Mode enabled or an elevated shell. The channel itself is installed, so `fvm use $channel` works in a project without this."
    }
    $results.Add($global)
    return $results
}

function Install-DirectInstaller {
    <#
    .SYNOPSIS
        Downloads an installer and runs it unattended.
    .DESCRIPTION
        For the two products that have no package on any Windows source. The installer is fetched
        to a temporary file, run with the switch its framework understands, and deleted afterwards.

        A timeout is not optional here. An installer that ignores its silent switch puts up a
        window and waits forever, and this runs in a wizard nobody is watching. On a timeout the
        child is killed and the caller is told to install it by hand, which is a worse outcome than
        success and a far better one than a hung run.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $Key,
        [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $Url,
        [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string[]] $SilentArgument,

        # Waives the Authenticode requirement for one installer, by the caller naming it rather than
        # by the rule bending for everybody. Gridcoin is the only user: its release binary is
        # unsigned, the project publishes no hash, and the download is an HTTPS URL to the project's
        # own GitHub release, which is the integrity this switch accepts in place of a signature.
        [switch] $AllowUnsigned,

        # A path that must exist afterwards for the install to count. Ledger rule 5: an install that
        # exits zero and leaves nothing behind is still a bug. Gridcoin is the case that proves the
        # point: its NSIS installer takes /S and says nothing about whether it worked.
        [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $ProofPath,

        [ValidateRange(1, 60)] [int] $TimeoutMinutes = 15,
        [ValidateRange(30, 3600)] [int] $DownloadTimeoutSeconds = 300
    )

    if (-not $PSCmdlet.ShouldProcess($Url, 'download and run installer')) {
        return [PSCustomObject]@{ Key = $Key; Package = $Url; Status = 'skipped'; Detail = 'WhatIf' }
    }

    # Scheme checked before anything is fetched. These URLs are assembled from pinned values by
    # textual substitution, so a bad edit to a pin can point this somewhere unintended, and what
    # arrives is then executed. http would also mean an installer any network position can replace.
    # Neither vendor needs it.
    if ($Url -notmatch '^https://') {
        return [PSCustomObject]@{ Key = $Key; Package = $Url; Status = 'failed'
                                  Detail = 'refusing to download an installer over anything but https' }
    }

    # Written into a per-run directory rather than straight into the temp root. The old path was
    # predictable, and a predictable name in a shared writable directory is worth avoiding when the
    # file is about to be executed.
    $stage = Join-Path ([System.IO.Path]::GetTempPath()) ("installation-helper-" + [guid]::NewGuid().ToString('N'))
    $null = New-Item -ItemType Directory -Path $stage -Force
    $target = Join-Path $stage "$Key-installer.exe"
    try {
        # TimeoutSec is not optional. PowerShell 7 maps the default of 0 to an infinite timeout, so a
        # server that completes the handshake and then stalls mid-body blocks here forever, and unlike
        # the Start-Process below there is no watchdog to notice.
        Invoke-WebRequest -Uri $Url -OutFile $target -UseBasicParsing `
            -TimeoutSec $DownloadTimeoutSeconds -MaximumRedirection 5 -ErrorAction Stop
    } catch {
        Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
        return [PSCustomObject]@{ Key = $Key; Package = $Url; Status = 'failed'
                                  Detail = "download failed: $($_.Exception.Message)" }
    }

    try {
        # An Authenticode check on everything except what the caller has explicitly waived.
        #
        # A signature is the only integrity evidence available for these evergreen URLs, since no
        # vendor here publishes a hash, and where the vendor does sign, refusing an invalid signature
        # is the difference between running a verified binary and running whatever the URL returned.
        #
        # -AllowUnsigned exists for the one vendor that signs nothing. It is per callsite on purpose:
        # the rule stays intact for every other download, and a reader can see exactly which binary
        # is trusted on the strength of its HTTPS source alone.
        $sig = Get-AuthenticodeSignature -LiteralPath $target
        if ($AllowUnsigned -and $sig.Status -ne 'Valid') {
            Write-Verbose "$Key is allowed to be unsigned, and its signature status is $($sig.Status)"
        }
        elseif ($sig.Status -ne 'Valid') {
            # SignerCertificate is null on a file with no signature at all, and under
            # Set-StrictMode -Version Latest reading .Subject off null is a terminating error. So the
            # rejection path crashed instead of rejecting, which is the worst possible place for it:
            # the Windows defaults cell of 2026-08-22 died here, and everything after this call, the
            # rest of the SDKs and Gridcoin included, never ran. An unsigned binary is exactly the
            # case this check exists to catch, and it was the one case it could not report.
            $signer = if ($sig.SignerCertificate) { $sig.SignerCertificate.Subject } else { 'none, the file carries no signature' }
            return [PSCustomObject]@{ Key = $Key; Package = $Url; Status = 'failed'
                                      Detail = "refusing to run it: Authenticode status is $($sig.Status), signer '$signer'" }
        }

        $p = Start-Process -FilePath $target -ArgumentList $SilentArgument -PassThru -WindowStyle Hidden
        if (-not $p.WaitForExit($TimeoutMinutes * 60 * 1000)) {
            try { $p.Kill($true) } catch { Write-Verbose "could not kill $($p.Id): $($_.Exception.Message)" }
            return [PSCustomObject]@{ Key = $Key; Package = $Url; Status = 'failed'
                                      Detail = "the installer was still running after $TimeoutMinutes minutes and was killed, which means it ignored $($SilentArgument -join ' ') and put up a window. Download it from $Url and run it by hand." }
        }
        if ($p.ExitCode -ne 0) {
            return [PSCustomObject]@{ Key = $Key; Package = $Url; Status = 'failed'; Detail = "installer exited $($p.ExitCode)" }
        }
        if (-not (Test-Path -LiteralPath $ProofPath)) {
            return [PSCustomObject]@{ Key = $Key; Package = $Url; Status = 'failed'
                                      Detail = "the installer exited 0 and $ProofPath does not exist, so it did not install, which usually means the silent switch it was given is not the one it takes." }
        }
        return [PSCustomObject]@{ Key = $Key; Package = $Url; Status = 'installed'; Detail = $ProofPath }
    } finally {
        Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Resolve-PinnedInstallerUrl {
    <#
    .SYNOPSIS
        A pinned installer location, or an empty one carrying the reason it cannot be used.
    .DESCRIPTION
        Absence and emptiness are different answers and the reason says which, because "nobody
        pinned this" and "somebody pinned it to nothing" send whoever reads the failure to
        different places. Neither raises: Invoke-WindowsCustomInstall's contract is that one bad
        item never takes the others down, so an unusable location becomes one named failed result.

        There is no check for a leftover {{ ref }} here. The reader resolves every reference before
        a value leaves it and refuses to hand out one it could not resolve, which is the whole
        reason this file no longer carries a resolver of its own.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)] [hashtable] $Versions,
        [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $Name
    )

    if (-not $Versions.ContainsKey($Name)) {
        return [PSCustomObject]@{ Url = ''; Reason = "nothing pins $Name, so there is no installer to download" }
    }

    $url = [string] $Versions[$Name]
    if (-not $url) {
        return [PSCustomObject]@{ Url = ''; Reason = "$Name is pinned to an empty value, so there is no installer to download" }
    }
    return [PSCustomObject]@{ Url = $url; Reason = '' }
}

function Install-AndroidSdk {
    <#
    .SYNOPSIS
        Installs the pinned Android command line tools, accepts the licences and installs the same
        three SDK packages the Unix path installs.
    .DESCRIPTION
        install_android_sdk has been true in group_vars/all.yaml the whole time and nothing on the
        Windows path installed anything, so the toggle was a silent no-op there. The Unix side does
        this in roles/sdk_manager/tasks/android_sdk_unix.yaml and this follows it deliberately: the
        same pinned build number, the same cmdline-tools/latest layout Google requires, and the same
        three packages, so a Windows machine and a Linux machine end up with the same SDK.

        Google ships the tools as a zip with a single cmdline-tools directory inside it, and
        sdkmanager refuses to run unless that directory is named `latest` (or a version number) one
        level under `cmdline-tools`. So the zip is expanded to a staging directory and the inner
        directory is moved into place, which is exactly what the Unix task does with mv.

        sdkmanager is a Java program and will not start without a JDK. JAVA_HOME is whatever the
        Java install set, and if it is absent this reports that rather than running a batch file that
        would print a Java error and exit non-zero with no explanation.

        Every licence is accepted by feeding `y` on stdin, because sdkmanager --licenses asks once
        per licence and there is nobody watching. That is the same thing the Unix path does with a
        prepared answers file, and it is the only way this can run unattended.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [hashtable] $Versions
    )

    $results = [System.Collections.Generic.List[object]]::new()

    foreach ($pin in @('android_cmdline_tools_build', 'android_api_level', 'android_build_tools_version')) {
        if (-not $Versions.ContainsKey($pin) -or [string]::IsNullOrWhiteSpace($Versions[$pin])) {
            $results.Add([PSCustomObject]@{ Key = 'android_sdk'; Package = $pin; Status = 'failed'
                                            Detail = "the pinned values carry no value for this name, so nothing could be installed. Ask Get-PinnedValueMap what it has." })
            return $results
        }
    }

    $root = $script:AndroidSdkRoot
    $cmdlineRoot = Join-Path $root 'cmdline-tools'
    $latest = Join-Path $cmdlineRoot 'latest'
    $sdkmanager = Join-Path $latest 'bin\sdkmanager.bat'

    if (Test-Path -LiteralPath $sdkmanager) {
        $results.Add([PSCustomObject]@{ Key = 'android_sdk'; Package = 'command line tools'; Status = 'present'; Detail = $latest })
    } else {
        $url = "https://dl.google.com/android/repository/commandlinetools-win-$($Versions['android_cmdline_tools_build'])_latest.zip"

        if (-not $PSCmdlet.ShouldProcess($url, 'download and expand the Android command line tools')) {
            $results.Add([PSCustomObject]@{ Key = 'android_sdk'; Package = 'command line tools'; Status = 'skipped'
                                            Detail = "WhatIf, would expand $url into $latest" })
            return $results
        }

        $zip = Join-Path ([System.IO.Path]::GetTempPath()) "commandlinetools-win-$($Versions['android_cmdline_tools_build']).zip"
        $staging = Join-Path ([System.IO.Path]::GetTempPath()) "android-cmdline-tools-$PID"
        try {
            New-Item -ItemType Directory -Path $cmdlineRoot -Force | Out-Null
            # A bounded download, because a stalled socket here would hang the wizard with no signal.
            Invoke-WebRequest -Uri $url -OutFile $zip -TimeoutSec 900 -UseBasicParsing -ErrorAction Stop
            Expand-Archive -LiteralPath $zip -DestinationPath $staging -Force -ErrorAction Stop

            $inner = Join-Path $staging 'cmdline-tools'
            if (-not (Test-Path -LiteralPath $inner)) {
                $results.Add([PSCustomObject]@{ Key = 'android_sdk'; Package = 'command line tools'; Status = 'failed'
                                                Detail = "the zip did not contain a cmdline-tools directory, so the layout sdkmanager needs could not be built. Google may have changed the archive shape." })
                return $results
            }
            Move-Item -LiteralPath $inner -Destination $latest -Force -ErrorAction Stop
            $results.Add([PSCustomObject]@{ Key = 'android_sdk'; Package = 'command line tools'; Status = 'installed'; Detail = $latest })
        } catch {
            $results.Add([PSCustomObject]@{ Key = 'android_sdk'; Package = 'command line tools'; Status = 'failed'
                                            Detail = $_.Exception.Message })
            return $results
        } finally {
            Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    $javaHome = [Environment]::GetEnvironmentVariable('JAVA_HOME', 'User')
    if (-not $javaHome) { $javaHome = [Environment]::GetEnvironmentVariable('JAVA_HOME', 'Machine') }
    if (-not $javaHome -or -not (Test-Path -LiteralPath $javaHome)) {
        $results.Add([PSCustomObject]@{ Key = 'android_sdk'; Package = 'sdkmanager'; Status = 'failed'
                                        Detail = "JAVA_HOME is not set to a directory that exists, and sdkmanager is a Java program. Turn install_java on, or set JAVA_HOME, then rerun with -OnlyKey android_sdk." })
        return $results
    }

    # sdkmanager reads ANDROID_HOME to decide where to install. Setting it for these two calls means
    # the SDK lands beside the tools rather than in whatever the ambient value happens to be.
    $sdkEnv = @{ JAVA_HOME = $javaHome; ANDROID_HOME = $root; ANDROID_SDK_ROOT = $root }

    $results.Add((Invoke-AndroidSdkManager -Arguments @('--licenses') -Environment $sdkEnv -TimeoutMinutes 10 -AnswerYes))
    $results.Add((Invoke-AndroidSdkManager -Arguments @(
        "platforms;android-$($Versions['android_api_level'])",
        "build-tools;$($Versions['android_build_tools_version'])",
        'platform-tools') -Environment $sdkEnv -TimeoutMinutes 30))

    return $results
}

function Invoke-AndroidSdkManager {
    <#
    .SYNOPSIS
        Runs sdkmanager.bat once, with a timeout and with stdin under control.
    .DESCRIPTION
        Not Invoke-ManagedTool, for one reason: sdkmanager --licenses asks a question per licence and
        answers nothing but `y`, so it needs a stdin that says yes repeatedly rather than an empty
        file that reads EOF. Everything else about the shape is the same, including that a run which
        outlives its timeout is killed and reported as failed rather than left to hang the wizard.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [string[]] $Arguments,
        [hashtable] $Environment = @{},
        [ValidateRange(1, 120)] [int] $TimeoutMinutes = 30,
        [switch] $AnswerYes
    )

    $sdkmanager = Join-Path $script:AndroidSdkRoot 'cmdline-tools\latest\bin\sdkmanager.bat'
    $label = "sdkmanager $($Arguments -join ' ')"

    if (-not (Test-Path -LiteralPath $sdkmanager)) {
        return [PSCustomObject]@{ Key = 'android_sdk'; Package = $label; Status = 'failed'
                                  Detail = "$sdkmanager is not there, so the command line tools install did not leave what it should have" }
    }
    if (-not $PSCmdlet.ShouldProcess($label, 'run')) {
        return [PSCustomObject]@{ Key = 'android_sdk'; Package = $label; Status = 'skipped'; Detail = 'WhatIf' }
    }

    $restore = @{}
    foreach ($name in $Environment.Keys) {
        $restore[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
        [Environment]::SetEnvironmentVariable($name, $Environment[$name], 'Process')
    }

    $stdin = New-TemporaryFile
    $stdout = New-TemporaryFile
    $stderr = New-TemporaryFile
    try {
        if ($AnswerYes) {
            # One y per line, enough for far more licences than Android has ever shipped. sdkmanager
            # stops reading when it has asked its last question, so a surplus costs nothing.
            Set-Content -LiteralPath $stdin -Value ((1..50 | ForEach-Object { 'y' }) -join "`n") -NoNewline:$false
        }
        $p = Start-Process -FilePath $sdkmanager -ArgumentList $Arguments -NoNewWindow -PassThru `
            -RedirectStandardInput $stdin -RedirectStandardOutput $stdout -RedirectStandardError $stderr
        if (-not $p.WaitForExit($TimeoutMinutes * 60 * 1000)) {
            try { $p.Kill($true) } catch { Write-Verbose "could not kill $($p.Id): $($_.Exception.Message)" }
            return [PSCustomObject]@{ Key = 'android_sdk'; Package = $label; Status = 'failed'
                                      Detail = "still running after $TimeoutMinutes minutes and was killed, so the SDK is NOT complete." }
        }
        if ($p.ExitCode -eq 0) {
            return [PSCustomObject]@{ Key = 'android_sdk'; Package = $label; Status = 'installed'; Detail = '' }
        }
        $tail = @(Get-Content -LiteralPath $stderr -ErrorAction SilentlyContinue
                  Get-Content -LiteralPath $stdout -ErrorAction SilentlyContinue) |
                Where-Object { $_ -and $_.Trim() } | Select-Object -Last 2
        return [PSCustomObject]@{ Key = 'android_sdk'; Package = $label; Status = 'failed'
                                  Detail = "exit $($p.ExitCode). $($tail -join ' ')" }
    } finally {
        foreach ($name in $restore.Keys) { [Environment]::SetEnvironmentVariable($name, $restore[$name], 'Process') }
        Remove-Item -LiteralPath $stdin, $stdout, $stderr -Force -ErrorAction SilentlyContinue
    }
}

function Set-WindowsDevEnvironment {
    <#
    .SYNOPSIS
        Writes the development environment variables at user scope, the Windows half of what
        roles/env_variables does everywhere else.
    .DESCRIPTION
        The five apps_config variables plus the Android ones. env_windows.yaml held these and could
        never run, because the playbook is invoked from inside WSL and reports os_family Debian, so
        on Windows they were never written at all.

        User scope, not machine scope, and that is not a compromise. A process inherits the merge of
        HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment and HKCU\Environment, so
        anything the logged-in account launches, IntelliJ and JetBrains Toolbox included, already
        sees the user values. Machine scope would need administrator rights, and setup.ps1 refuses to
        run elevated by design, which is the same reason the Java install writes JAVA_HOME at user
        scope. Only a service or a process running as another account would miss these, and nothing
        here runs that way.

        PATH is handled separately from the rest, because it is the one variable Windows concatenates
        rather than replaces, so it is read, extended with anything missing, and written back. Adding
        an entry that is already there would grow the value on every run, which is the shape of a
        PATH that eventually stops working because it exceeded its limit.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param()

    $results = [System.Collections.Generic.List[object]]::new()
    $appsConfig = Join-Path $env:USERPROFILE 'apps_config'
    $sdk = $script:AndroidSdkRoot

    # The same five names and the same layout the Unix shell block writes, so a machine configured
    # by either one keeps its tool state in the same place.
    $variables = [ordered]@{
        GRADLE_USER_HOME = Join-Path $appsConfig '.gradle'
        DOCKER_CONFIG    = Join-Path $appsConfig '.docker'
        M2_HOME          = Join-Path $appsConfig '.m2'
        KUBECONFIG       = Join-Path $appsConfig '.kube\config'
        # ANDROID_USER_HOME names the preferences directory. ANDROID_SDK_HOME is the legacy variable
        # Android Studio 4.3 and earlier read for the same purpose, and it names the PARENT the
        # .android directory is created under, which is why the two differ by one level.
        ANDROID_USER_HOME = Join-Path $appsConfig '.android'
        ANDROID_SDK_HOME  = $appsConfig
        # Both names for the SDK directory, set to the same path on purpose: ANDROID_SDK_ROOT is
        # deprecated, and Android Studio and the Gradle plugin check the two agree when it is present.
        ANDROID_HOME     = $sdk
        ANDROID_SDK_ROOT = $sdk
    }

    if ($PSCmdlet.ShouldProcess($appsConfig, 'create the tool configuration directory')) {
        try {
            New-Item -ItemType Directory -Path $appsConfig -Force -ErrorAction Stop | Out-Null
        } catch {
            $results.Add([PSCustomObject]@{ Key = 'environment'; Package = 'apps_config'; Status = 'failed'
                                            Detail = $_.Exception.Message })
        }
    }

    foreach ($name in $variables.Keys) {
        $wanted = $variables[$name]
        $current = [Environment]::GetEnvironmentVariable($name, 'User')
        if ($current -eq $wanted) {
            $results.Add([PSCustomObject]@{ Key = 'environment'; Package = $name; Status = 'present'; Detail = $wanted })
            continue
        }
        if (-not $PSCmdlet.ShouldProcess("$name=$wanted", 'set user environment variable')) {
            $results.Add([PSCustomObject]@{ Key = 'environment'; Package = $name; Status = 'skipped'; Detail = 'WhatIf' })
            continue
        }
        try {
            [Environment]::SetEnvironmentVariable($name, $wanted, 'User')
            $results.Add([PSCustomObject]@{ Key = 'environment'; Package = $name; Status = 'installed'; Detail = $wanted })
        } catch {
            $results.Add([PSCustomObject]@{ Key = 'environment'; Package = $name; Status = 'failed'; Detail = $_.Exception.Message })
        }
    }

    $wantedPath = @(
        (Join-Path $sdk 'cmdline-tools\latest\bin')
        (Join-Path $sdk 'platform-tools')
        (Join-Path $sdk 'emulator')
    )
    $currentPath = [Environment]::GetEnvironmentVariable('PATH', 'User')
    $entries = @($currentPath -split ';' | Where-Object { $_ })
    $missing = @($wantedPath | Where-Object { $_ -notin $entries })

    if ($missing.Count -eq 0) {
        $results.Add([PSCustomObject]@{ Key = 'environment'; Package = 'PATH'; Status = 'present'
                                        Detail = 'the three Android tool directories are already there' })
    } elseif ($PSCmdlet.ShouldProcess(($missing -join '; '), 'add to the user PATH')) {
        try {
            [Environment]::SetEnvironmentVariable('PATH', (($entries + $missing) -join ';'), 'User')
            $results.Add([PSCustomObject]@{ Key = 'environment'; Package = 'PATH'; Status = 'installed'
                                            Detail = ($missing -join '; ') })
        } catch {
            $results.Add([PSCustomObject]@{ Key = 'environment'; Package = 'PATH'; Status = 'failed'; Detail = $_.Exception.Message })
        }
    } else {
        $results.Add([PSCustomObject]@{ Key = 'environment'; Package = 'PATH'; Status = 'skipped'; Detail = 'WhatIf' })
    }

    return $results
}

function Invoke-WindowsCustomInstall {
    <#
    .SYNOPSIS
        Runs every enabled custom install and returns a summary.
    .DESCRIPTION
        Takes the already-resolved toggle map from Get-WindowsSoftwareToggle, so the toggle source
        of truth stays in one place. Never throws for one item: the others still run and the summary
        names every failure.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [hashtable] $Toggles,
        [string[]] $OnlyKeys
    )

    $results = [System.Collections.Generic.List[object]]::new()

    # The whole set in one call, so a name nobody pinned is absent from the map instead of raising,
    # and every guard below reports it as one named failed result.
    #
    # The load itself is caught for the same reason those guards exist. setup.ps1 does not wrap this
    # call and runs with $ErrorActionPreference 'Stop', so throwing here would stop the wizard before
    # the WSL playbook ran, which is the shape of two regressions in the ledger. An empty map plus
    # this one named failure degrades into named failures per item rather than a wrong install.
    $versions = @{}
    try {
        $versions = Get-PinnedValueMap
    } catch {
        $results.Add([PSCustomObject]@{ Key = 'pinned values'; Package = 'PinnedValues.psm1'
                                        Status = 'failed'; Detail = $_.Exception.Message })
    }

    $wanted = {
        param([string] $key)
        if (-not ($Toggles.ContainsKey($key) -and $Toggles[$key])) { return $false }
        if ($OnlyKeys -and $key -notin $OnlyKeys) { return $false }
        return $true
    }

    # The paths an install has to leave behind, held in one table so the proof this phase demands and
    # the proof the verification looks for after the run are the same paths.
    $proofs = Get-WindowsCustomInstallProof -Versions $versions

    # [object[]]@( ) around each call, the same wrapper WindowsSettings.ps1 uses, and for a measured
    # reason. A function here returns a list of results normally and a single object when it gives
    # up early, and AddRange refuses a lone PSCustomObject: "Cannot convert argument collection ...
    # to type IEnumerable[Object]". The Windows defaults cell of 2026-08-22 died on exactly that
    # after its Chocolatey batch was killed at the 30 minute mark, so the wizard crashed while
    # reporting a failure it had handled correctly, and everything after this line, the Android SDK
    # and Gridcoin included, never ran. The array subexpression makes one object and many behave the
    # same way.
    if (& $wanted 'java')   { $results.AddRange([object[]]@(Install-TemurinJdk   -Versions $versions)) }
    if (& $wanted 'nodejs') { $results.AddRange([object[]]@(Install-NodeViaNvm)) }
    if (& $wanted 'flutter'){ $results.AddRange([object[]]@(Install-FlutterViaFvm -Versions $versions)) }

    # After java on purpose. sdkmanager is a Java program and reads the JAVA_HOME the Temurin
    # install above writes, so running it first would fail on a machine with no other JDK.
    if (& $wanted 'android_sdk') { $results.AddRange([object[]]@(Install-AndroidSdk -Versions $versions)) }

    # Gridcoin's installer is NSIS, confirmed by finding Nullsoft.NSIS.exehead in the downloaded
    # binary rather than by assuming it. NSIS takes /S.
    if (& $wanted 'gridcoin') {
        $pin = Resolve-PinnedInstallerUrl -Versions $versions -Name 'gridcoin_win_installer_url'
        if ($pin.Url) {
            # NSIS installs to Program Files by default and the package name is Gridcoin, confirmed
            # from the installer's own version resources when its framework was identified.
            # AllowUnsigned, because Gridcoin signs nothing and publishes no hash. What is left is
            # the HTTPS release URL itself, and at the owner's decision that is enough here: a
            # checksum would only have to be re-measured on every version bump, and it would fail
            # the install rather than protect it when nobody remembered.
            $results.Add((Install-DirectInstaller -Key 'gridcoin' -Url $pin.Url -SilentArgument @('/S') `
                -AllowUnsigned `
                -ProofPath @($proofs['gridcoin'].Path)[0]))
        } else {
            $results.Add([PSCustomObject]@{ Key = 'gridcoin'; Package = 'gridcoin_win_installer_url'; Status = 'failed'
                                            Detail = $pin.Reason })
        }
    }

    return [PSCustomObject]@{
        Results   = $results
        Installed = @($results | Where-Object { $_.Status -eq 'installed' })
        Present   = @($results | Where-Object { $_.Status -eq 'present' })
        Failed    = @($results | Where-Object { $_.Status -eq 'failed' })
    }
}
