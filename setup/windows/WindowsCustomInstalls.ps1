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
      install_razer_cortex  the same, and Razer ships no unattended switch it will admit to

    Every version comes from group_vars/versions.yaml so the pins stay a single source of
    truth with the Unix path. Nothing here writes to the console: the caller renders, which
    keeps the functions testable.

    Depends on Get-WingetPath, Install-WingetPackage and Install-ChocolateyPackageBatch from
    WindowsSoftware.ps1, which setup.ps1 dot-sources first.
#>

Set-StrictMode -Version Latest

# The toggles this file is responsible for. Declared as data rather than left implicit in the
# dispatch below, so e2e/tier1/toggle_coverage.sh can ask what is covered here instead of inferring
# it. Without that, an install_ toggle whose only consumer is an unreachable Windows Ansible task
# counts as covered, which is how eleven toggles sat enabled and installing nothing while the gate
# reported full coverage.
$script:CustomInstallKeys = @('java', 'nodejs', 'flutter', 'gridcoin', 'razer_cortex')

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

# A scalar assignment in group_vars/versions.yaml. Only quoted and bare scalars, because that is
# all the file contains, and anything structured would be a change worth failing on rather than
# half-reading. The template form "{{ other_key }}" is captured so it can be resolved afterwards.
$script:VersionLinePattern = '^(?<key>[a-z0-9_]+):\s*"?(?<value>[^"#]*?)"?\s*(#.*)?$'

function Get-PinnedVersion {
    <#
    .SYNOPSIS
        Returns group_vars/versions.yaml as a key to value map, with one level of {{ ref }} resolved.
    .DESCRIPTION
        Two shapes of reference appear in that file and only handling the first is a trap I walked
        into. default_java is the whole value, "{{ java21_id }}". But gridcoin_win_installer_url
        embeds one mid-string, ".../download/{{ gridcoin_version }}/gridcoin-{{ gridcoin_version
        }}-win64-setup.exe", and antigravity_cdn_base nests a reference inside a value that other
        values then reference. So substitution is textual and repeated until nothing changes, with a
        pass limit so a circular reference cannot spin.

        A reference that does not resolve is left with its braces intact rather than blanked, so a
        caller can see it is unresolved and say so instead of silently fetching a broken URL.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $VersionsPath
    )

    if (-not (Test-Path -LiteralPath $VersionsPath)) {
        throw "Versions file not found: $VersionsPath"
    }

    $versions = @{}
    foreach ($line in (Get-Content -LiteralPath $VersionsPath)) {
        if ($line -match '^\s*#') { continue }
        if ($line -notmatch $script:VersionLinePattern) { continue }
        $versions[$Matches['key']] = $Matches['value'].Trim()
    }

    for ($pass = 1; $pass -le 5; $pass++) {
        $changed = $false
        foreach ($key in @($versions.Keys)) {
            $value = $versions[$key]
            if ($value -notmatch '\{\{') { continue }
            $resolved = [regex]::Replace($value, '\{\{\s*(?<ref>[a-z0-9_]+)\s*\}\}', {
                param($m)
                $ref = $m.Groups['ref'].Value
                # Left alone when it names nothing, so it stays visibly unresolved.
                if ($versions.ContainsKey($ref) -and $versions[$ref] -notmatch '\{\{') { return $versions[$ref] }
                return $m.Value
            })
            if ($resolved -ne $value) { $versions[$key] = $resolved; $changed = $true }
        }
        if (-not $changed) { break }
    }

    Write-Verbose "Read $($versions.Count) pinned versions"
    return $versions
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
        majors pinned in versions.yaml are installed as four winget packages instead, which is the
        same vendor and the same four versions the Unix path gets.

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
    # nodejs, flutter, gridcoin and razer_cortex with it and stopped the wizard before the WSL
    # playbook ran. It is reachable without a typo, since Get-PinnedVersion deliberately leaves an
    # unresolvable {{ ref }} intact and default_java is written in exactly that shape.
    foreach ($key in @('java11_id', 'java17_id', 'java21_id', 'java25_id')) {
        if (-not $Versions.ContainsKey($key)) {
            $results.Add([PSCustomObject]@{ Key = 'java'; Package = $key; Status = 'failed'
                                            Detail = "versions.yaml has no $key, so no Temurin package could be derived" })
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
    # gridcoin, razer_cortex and every summary line along with the four JDKs. One failed result per
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
    # pin in versions.yaml knows. Falls back to 21 when default_java is missing or malformed, which
    # is the pinned default in versions.yaml, rather than throwing out of the whole phase.
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

        nvm_version in versions.yaml pins nvm.sh and does not apply here: nvm-windows is a separate
        project with its own versioning, and Chocolatey carries it as `nvm`.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param()

    $results = [System.Collections.Generic.List[object]]::new()

    $choco = Install-ChocolateyPackageBatch -PackageId @('nvm')
    $results.Add([PSCustomObject]@{ Key = 'nodejs'; Package = 'nvm'; Status = $choco.Status; Detail = $choco.Detail })
    if ($choco.Status -eq 'failed') { return $results }

    # Skipped rather than attempted when the manager itself was skipped. Under -WhatIf nvm was never
    # installed, so running the next two steps for real reported two failures for a plan that had not
    # done anything yet, which is a lie about the plan.
    if ($choco.Status -eq 'skipped') {
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

function Install-FlutterViaFvm {
    <#
    .SYNOPSIS
        Installs FVM, then the pinned Flutter channel, then pins it globally.
    .DESCRIPTION
        Mirrors fvm_windows.yaml, which had the shape right. Two things it noted are carried over:
        winget has no FVM manifest and no Flutter SDK manifest, so Chocolatey is the route, and
        `fvm global` creates a symlink under %USERPROFILE%\fvm\default, which needs Developer Mode
        enabled or an elevated run. That last one is reported rather than treated as fatal, because
        the channel is installed and usable through `fvm use` either way.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [hashtable] $Versions
    )

    $channel = if ($Versions.ContainsKey('flutter_channel')) { $Versions['flutter_channel'] } else { 'stable' }
    $results = [System.Collections.Generic.List[object]]::new()

    $choco = Install-ChocolateyPackageBatch -PackageId @('fvm')
    $results.Add([PSCustomObject]@{ Key = 'flutter'; Package = 'fvm'; Status = $choco.Status; Detail = $choco.Detail })
    if ($choco.Status -eq 'failed') { return $results }

    if ($choco.Status -eq 'skipped') {
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

    $installed = Join-Path $env:USERPROFILE "fvm\versions\$channel\bin\flutter.bat"
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

        # A path that must exist afterwards for the install to count. Ledger rule 5: an install that
        # exits zero and leaves nothing behind is still a bug. Razer Cortex matters most here, since
        # its /S switch is corroborated by the Chocolatey Synapse package and not documented anywhere.
        [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $ProofPath,

        [ValidateRange(1, 60)] [int] $TimeoutMinutes = 15,
        [ValidateRange(30, 3600)] [int] $DownloadTimeoutSeconds = 300
    )

    if (-not $PSCmdlet.ShouldProcess($Url, 'download and run installer')) {
        return [PSCustomObject]@{ Key = $Key; Package = $Url; Status = 'skipped'; Detail = 'WhatIf' }
    }

    # Scheme checked before anything is fetched. These URLs are built by textual {{ ref }}
    # substitution out of versions.yaml, so a bad edit there can point this somewhere unintended, and
    # what arrives is then executed. http would also mean an installer any network position can
    # replace. Neither vendor needs it.
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
        # An Authenticode check is the only integrity evidence available here, since neither vendor
        # publishes a hash for these evergreen URLs. Both do sign their installers, so this is
        # enforceable today rather than aspirational, and it is the difference between running a
        # verified vendor binary and running whatever the URL returned.
        $sig = Get-AuthenticodeSignature -LiteralPath $target
        if ($sig.Status -ne 'Valid') {
            return [PSCustomObject]@{ Key = $Key; Package = $Url; Status = 'failed'
                                      Detail = "refusing to run it: Authenticode status is $($sig.Status), signer '$($sig.SignerCertificate.Subject)'" }
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
                                      Detail = "the installer exited 0 and $ProofPath does not exist, so it did not install. For Razer Cortex this most likely means /S is not its silent switch." }
        }
        return [PSCustomObject]@{ Key = $Key; Package = $Url; Status = 'installed'; Detail = $ProofPath }
    } finally {
        Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
    }
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
        [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $VersionsPath,
        [string[]] $OnlyKeys
    )

    $versions = Get-PinnedVersion -VersionsPath $VersionsPath
    $results  = [System.Collections.Generic.List[object]]::new()

    $wanted = {
        param([string] $key)
        if (-not ($Toggles.ContainsKey($key) -and $Toggles[$key])) { return $false }
        if ($OnlyKeys -and $key -notin $OnlyKeys) { return $false }
        return $true
    }

    if (& $wanted 'java')   { $results.AddRange((Install-TemurinJdk   -Versions $versions)) }
    if (& $wanted 'nodejs') { $results.AddRange((Install-NodeViaNvm)) }
    if (& $wanted 'flutter'){ $results.AddRange((Install-FlutterViaFvm -Versions $versions)) }

    # Gridcoin's installer is NSIS, confirmed by finding Nullsoft.NSIS.exehead in the downloaded
    # binary rather than by assuming it. NSIS takes /S.
    if (& $wanted 'gridcoin') {
        $url = $versions['gridcoin_win_installer_url']
        if ($url -and $url -notmatch '\{\{') {
            # NSIS installs to Program Files by default and the package name is Gridcoin, confirmed
            # from the installer's own version resources when its framework was identified.
            $results.Add((Install-DirectInstaller -Key 'gridcoin' -Url $url -SilentArgument @('/S') `
                -ProofPath (Join-Path $env:ProgramFiles 'Gridcoin')))
        } else {
            $results.Add([PSCustomObject]@{ Key = 'gridcoin'; Package = 'gridcoin_win_installer_url'; Status = 'failed'
                                            Detail = "versions.yaml does not give a usable URL, it reads '$url'" })
        }
    }

    # Razer Cortex has no package on winget, no package on Chocolatey, and its installer carries no
    # framework signature: the metadata says only "Razer Installer". /S is the switch the Chocolatey
    # razer-synapse-4 package uses against the same installer family, which is corroboration and not
    # proof, so the timeout matters more here than anywhere else in this file. If Cortex ignores it,
    # the run is not lost, the user is told to install it by hand.
    if (& $wanted 'razer_cortex') {
        $url = $versions['razer_cortex_win_installer_url']
        if ($url -and $url -notmatch '\{\{') {
            # The proof path is a guess and is labelled as one. Razer Cortex is a 32-bit installer so
            # Program Files (x86) is the right root, but the exact directory has not been verified on a
            # real install because nothing here has ever run it. If this reports a failure while Cortex
            # is visibly installed, the path is wrong rather than the install, and the message says so.
            # That direction is the safe one: a false failure gets investigated, a false success does not.
            $results.Add((Install-DirectInstaller -Key 'razer_cortex' -Url $url -SilentArgument @('/S') `
                -TimeoutMinutes 10 `
                -ProofPath (Join-Path ${env:ProgramFiles(x86)} 'Razer\Razer Cortex')))
        } else {
            $results.Add([PSCustomObject]@{ Key = 'razer_cortex'; Package = 'razer_cortex_win_installer_url'; Status = 'failed'
                                            Detail = "versions.yaml does not give a usable URL, it reads '$url'" })
        }
    }

    return [PSCustomObject]@{
        Results   = $results
        Installed = @($results | Where-Object { $_.Status -eq 'installed' })
        Present   = @($results | Where-Object { $_.Status -eq 'present' })
        Failed    = @($results | Where-Object { $_.Status -eq 'failed' })
    }
}
