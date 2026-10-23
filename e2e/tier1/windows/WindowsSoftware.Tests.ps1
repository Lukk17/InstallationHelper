#Requires -Version 7.2
<#
.SYNOPSIS
    Pester tests for the native Windows installer.

.DESCRIPTION
    These assert the parts of the wizard that can be answered without installing anything: the
    reading of the toggle and mapping files, the plan that comes out of them, the machine-condition
    skips, the pinned values adapters and the cache reclaim.

    Two callers, and they run the same file rather than a copy of it. The windows_pester check in
    tier 1 runs it on a developer machine, and the stage 1 job of .github/workflows/e2e-matrix.yml
    runs it on a hosted Windows runner. It lived under tier3/windows until 2026-08-26, driven by a
    Server Core container that was retired for being unable to install a single winget package.

    Installing anything for real is a different job, and it belongs to the hosted runner cells or
    to Windows Sandbox, see e2e/manual_test_matrix.md.
#>

BeforeAll {
    # The repository root is found by walking up from this file rather than assumed, so the suite
    # works from a checkout at any path and from a copy at any depth. E2E_REPO_ROOT stays as an
    # explicit override for a caller that has moved the file away from its tree, which is what the
    # retired container harness did when it copied this one file to C:\work. Nothing here hardcodes
    # a path, so a developer running it straight from a checkout gets a real answer.
    function Find-RepositoryRoot {
        [OutputType([string])]
        param([Parameter(Mandatory)] [string] $StartPath)

        $dir = Get-Item -LiteralPath $StartPath
        while ($dir) {
            if (Test-Path -LiteralPath (Join-Path $dir.FullName 'setup\windows\WindowsSoftware.ps1')) {
                return $dir.FullName
            }
            $dir = $dir.Parent
        }
        return $null
    }

    $script:RepoRoot = $env:E2E_REPO_ROOT
    if (-not $script:RepoRoot) {
        $script:RepoRoot = Find-RepositoryRoot -StartPath $PSScriptRoot
    }
    if (-not $script:RepoRoot) {
        throw "Could not find the repository root by walking up from $PSScriptRoot, and E2E_REPO_ROOT is not set."
    }

    $script:AnsibleDir        = Join-Path $script:RepoRoot 'setup\ansible'
    $script:PsFile            = Join-Path $script:RepoRoot 'setup\windows\WindowsSoftware.ps1'
    $script:CustomInstallFile = Join-Path $script:RepoRoot 'setup\windows\WindowsCustomInstalls.ps1'
    $script:PinnedValuesFile  = Join-Path $script:RepoRoot 'setup\pinned_values\PinnedValues.psm1'

    if (-not (Test-Path -LiteralPath $script:PsFile)) {
        throw "WindowsSoftware.ps1 not found at $script:PsFile. Was the repository copied in?"
    }
    if (-not (Test-Path -LiteralPath $script:CustomInstallFile)) {
        throw "WindowsCustomInstalls.ps1 not found at $script:CustomInstallFile. Was the repository copied in?"
    }
    if (-not (Test-Path -LiteralPath $script:PinnedValuesFile)) {
        throw "PinnedValues.psm1 not found at $script:PinnedValuesFile. Was the repository copied in?"
    }
    . $script:PsFile
    . $script:CustomInstallFile
    # Imported here as well as by WindowsCustomInstalls.ps1, so the adapter tests below state their
    # own dependency instead of relying on a dot-source side effect.
    Import-Module $script:PinnedValuesFile -Force
}

Describe 'Get-WindowsSoftwareToggle' {

    It 'reads toggles from both group_vars files' {
        $t = Get-WindowsSoftwareToggle `
            -AllVarsPath     (Join-Path $script:AnsibleDir 'group_vars\all.yaml') `
            -WindowsVarsPath (Join-Path $script:AnsibleDir 'group_vars\windows.yaml')
        $t.Count | Should -BeGreaterThan 80
    }

    It 'strips the install_ prefix so keys line up with the mapping keys' {
        $t = Get-WindowsSoftwareToggle `
            -AllVarsPath     (Join-Path $script:AnsibleDir 'group_vars\all.yaml') `
            -WindowsVarsPath (Join-Path $script:AnsibleDir 'group_vars\windows.yaml')
        $t.Keys | Where-Object { $_ -like 'install_*' } | Should -BeNullOrEmpty
        $t.ContainsKey('chrome') | Should -BeTrue
    }

    # The defect that shipped in the bash wizard for months: a trailing comment on a toggle
    # line desynced the key from its value. This parser must not repeat it.
    It 'reads a toggle correctly when the line carries a trailing comment' {
        $tmp = Join-Path $TestDrive 'commented.yaml'
        @(
            '---'
            'install_withcomment: true  # this comment must not change the value'
            'install_plain: false'
        ) | Set-Content -LiteralPath $tmp
        $t = Get-WindowsSoftwareToggle -AllVarsPath $tmp -WindowsVarsPath $tmp
        $t['withcomment'] | Should -BeTrue
        $t['plain']       | Should -BeFalse
    }

    It 'lets the Windows file override the cross-platform file' {
        $all = Join-Path $TestDrive 'all.yaml'
        $win = Join-Path $TestDrive 'win.yaml'
        @('---', 'install_overridden: true')  | Set-Content -LiteralPath $all
        @('---', 'install_overridden: false') | Set-Content -LiteralPath $win
        $t = Get-WindowsSoftwareToggle -AllVarsPath $all -WindowsVarsPath $win
        $t['overridden'] | Should -BeFalse
    }

    It 'throws rather than returning a partial set when a file is missing' {
        { Get-WindowsSoftwareToggle -AllVarsPath (Join-Path $TestDrive 'nope.yaml') -WindowsVarsPath (Join-Path $TestDrive 'nope.yaml') } |
            Should -Throw -ExpectedMessage '*not found*'
    }
}

Describe 'Get-WindowsSoftwareMapping' {

    It 'parses every mapping in the real vars file' {
        $m = Get-WindowsSoftwareMapping -WindowsMappingPath (Join-Path $script:AnsibleDir 'vars\Windows.yaml')
        $m.Count | Should -BeGreaterThan 80
    }

    It 'defaults the source to winget when the entry does not name one' {
        $m = Get-WindowsSoftwareMapping -WindowsMappingPath (Join-Path $script:AnsibleDir 'vars\Windows.yaml')
        $m['chrome'].Source | Should -Be 'winget'
    }

    It 'keeps an explicit source override' {
        $tmp = Join-Path $TestDrive 'map.yaml'
        @(
            '---'
            'software_mapping:'
            '  storeapp: { manager: "winget", package: "9NKSQGP7F2NH", source: "msstore" }'
        ) | Set-Content -LiteralPath $tmp
        $m = Get-WindowsSoftwareMapping -WindowsMappingPath $tmp
        $m['storeapp'].Source  | Should -Be 'msstore'
        $m['storeapp'].Package | Should -Be '9NKSQGP7F2NH'
    }

    # The three optional keys that say a package cannot install on some machines. Each one is a
    # property of the machine rather than of the run, and the install phase and the verification both
    # read them, so a parser that dropped one would make the wizard attempt an install that refuses
    # and then fail its own verification for the absence.
    It 'reads client_only, user_context and requires_nvidia_gpu, and defaults all three to false' {
        $tmp = Join-Path $TestDrive 'flags.yaml'
        @(
            '---'
            'software_mapping:'
            '  plain: { manager: "winget", package: "Vendor.Plain" }'
            '  desktoponly: { manager: "winget", package: "Vendor.Desktop", client_only: true }'
            '  asuser: { manager: "winget", package: "Vendor.User", user_context: true }'
            '  graphics: { manager: "choco", package: "vendor-gpu", requires_nvidia_gpu: true }'
        ) | Set-Content -LiteralPath $tmp
        $m = Get-WindowsSoftwareMapping -WindowsMappingPath $tmp

        $m['plain'].ClientOnly        | Should -BeFalse
        $m['plain'].UserContext       | Should -BeFalse
        $m['plain'].RequiresNvidiaGpu | Should -BeFalse

        $m['desktoponly'].ClientOnly  | Should -BeTrue
        $m['asuser'].UserContext      | Should -BeTrue
        $m['graphics'].RequiresNvidiaGpu | Should -BeTrue
    }

    It 'reads verify_path, and leaves it empty when the entry does not carry one' {
        $tmp = Join-Path $TestDrive 'verify.yaml'
        @(
            '---'
            'software_mapping:'
            '  plain: { manager: "winget", package: "Vendor.Plain" }'
            '  folderdrop: { manager: "winget", package: "Vendor.Drop", verify_path: "%USERPROFILE%/Desktop/Vendor Drop" }'
        ) | Set-Content -LiteralPath $tmp
        $m = Get-WindowsSoftwareMapping -WindowsMappingPath $tmp

        $m['plain'].VerifyPath      | Should -BeNullOrEmpty
        $m['folderdrop'].VerifyPath | Should -Be '%USERPROFILE%/Desktop/Vendor Drop'
    }

    # Forward slashes, and the test says why: this file is read by Ansible, which unescapes a
    # double-quoted YAML scalar, and by the PowerShell reader, which takes the raw text. A backslash
    # arrives as one character in one and two in the other, so a path with backslashes silently fails
    # every Test-Path against it.
    It 'carries a verify_path with no backslash in it, so both parsers agree' {
        $m = Get-WindowsSoftwareMapping -WindowsMappingPath (Join-Path $script:AnsibleDir 'vars\Windows.yaml')
        $withPaths = @($m.Keys | Where-Object { $m[$_].VerifyPath })
        $withPaths.Count | Should -BeGreaterThan 0
        foreach ($key in $withPaths) {
            $m[$key].VerifyPath | Should -Not -Match ([regex]::Escape("\"))
        }
    }

    It 'reads installer_type after scope, and leaves it empty when the entry does not carry one' {
        $tmp = Join-Path $TestDrive 'installertype.yaml'
        @(
            '---'
            'software_mapping:'
            '  plain: { manager: "winget", package: "Vendor.Plain", scope: "user" }'
            '  packaged: { manager: "winget", package: "Vendor.Packaged", scope: "machine", installer_type: "msix" }'
        ) | Set-Content -LiteralPath $tmp
        $m = Get-WindowsSoftwareMapping -WindowsMappingPath $tmp

        $m['plain'].InstallerType    | Should -BeNullOrEmpty
        $m['packaged'].Scope         | Should -Be 'machine'
        $m['packaged'].InstallerType | Should -Be 'msix'
    }

    It 'carries requires_nvidia_gpu through on the real mapping file' {
        $m = Get-WindowsSoftwareMapping -WindowsMappingPath (Join-Path $script:AnsibleDir 'vars\Windows.yaml')
        $m['nvidia_app'].RequiresNvidiaGpu | Should -BeTrue
        $m['chrome'].RequiresNvidiaGpu     | Should -BeFalse
    }

    # A silently skipped mapping is a package the user asked for and did not get, which is the
    # failure this whole file exists to end, so it has to be loud.
    It 'throws on a mapping-shaped line it cannot parse, rather than skipping it' {
        $tmp = Join-Path $TestDrive 'broken.yaml'
        @(
            '---'
            'software_mapping:'
            '  goodone: { manager: "winget", package: "Vendor.Good" }'
            '  brokenone: { manager: winget, package: Vendor.Missing.Quotes }'
        ) | Set-Content -LiteralPath $tmp
        { Get-WindowsSoftwareMapping -WindowsMappingPath $tmp } |
            Should -Throw -ExpectedMessage '*does not parse*'
    }

    It 'ignores comment lines' {
        $tmp = Join-Path $TestDrive 'comments.yaml'
        @(
            '---'
            'software_mapping:'
            '  # commented: { manager: "winget", package: "Should.Be.Ignored" }'
            '  real: { manager: "choco", package: "realpkg" }'
        ) | Set-Content -LiteralPath $tmp
        $m = Get-WindowsSoftwareMapping -WindowsMappingPath $tmp
        $m.Count | Should -Be 1
        $m.ContainsKey('real') | Should -BeTrue
    }
}

# One function decides whether a package can run on this machine, and the winget path, the Chocolatey
# path and the verification all ask it. They used to decide separately, and on run 32778401303 the
# Chocolatey path installed razer-synapse-4 while the verification called it not applicable in the
# same run, because client_only was honoured in one and not the other.
Describe 'Test-WindowsPackageSkip' {

    BeforeAll {
        $script:Client = [PSCustomObject]@{ InstallationType = 'Client'; IsElevated = $false; NvidiaAdapters = @('NVIDIA GeForce RTX 2080') }
        $script:Server = [PSCustomObject]@{ InstallationType = 'Server'; IsElevated = $true;  NvidiaAdapters = @() }
    }

    It 'says nothing about a package carrying none of the three keys' {
        $item = [PSCustomObject]@{ Key = 'plain'; Manager = 'winget'; Package = 'Vendor.Plain' }
        Test-WindowsPackageSkip -Item $item -Fact $script:Server | Should -BeNullOrEmpty
    }

    It 'skips a client-only package on Server and installs it on Client' {
        $item = [PSCustomObject]@{ Key = 'd'; Manager = 'winget'; Package = 'V.D'; ClientOnly = $true }
        Test-WindowsPackageSkip -Item $item -Fact $script:Server | Should -Match 'client editions'
        Test-WindowsPackageSkip -Item $item -Fact $script:Client | Should -BeNullOrEmpty
    }

    It 'skips a user-context package when elevated and installs it when not' {
        $item = [PSCustomObject]@{ Key = 'u'; Manager = 'winget'; Package = 'V.U'; UserContext = $true }
        Test-WindowsPackageSkip -Item $item -Fact $script:Server | Should -Match 'administrator context'
        Test-WindowsPackageSkip -Item $item -Fact $script:Client | Should -BeNullOrEmpty
    }

    It 'skips NVIDIA software with no adapter and installs it with one' {
        $item = [PSCustomObject]@{ Key = 'g'; Manager = 'choco'; Package = 'v-gpu'; RequiresNvidiaGpu = $true }
        Test-WindowsPackageSkip -Item $item -Fact $script:Server | Should -Match 'NVIDIA display adapter'
        Test-WindowsPackageSkip -Item $item -Fact $script:Client | Should -BeNullOrEmpty
    }

    # The Pester suite is the caller that hands it mappings built by hand, so this is the shape that
    # crashes under Set-StrictMode -Version Latest if a property is read without a guard.
    It 'does not crash on a mapping that carries none of the optional properties' {
        $item = [PSCustomObject]@{ Key = 'bare'; Manager = 'winget'; Package = 'V.Bare' }
        { Test-WindowsPackageSkip -Item $item -Fact $script:Client } | Should -Not -Throw
    }

    It 'decides the real mapping file the way a Server runner with no NVIDIA adapter would' {
        $m = Get-WindowsSoftwareMapping -WindowsMappingPath (Join-Path $script:AnsibleDir 'vars\Windows.yaml')
        Test-WindowsPackageSkip -Item $m['partition_wizard'] -Fact $script:Server | Should -Not -BeNullOrEmpty
        Test-WindowsPackageSkip -Item $m['spotify']          -Fact $script:Server | Should -Not -BeNullOrEmpty
        Test-WindowsPackageSkip -Item $m['nvidia_app']       -Fact $script:Server | Should -Not -BeNullOrEmpty
        # Measured on run 32778481303: it installs on a Server runner and exits 0.
        Test-WindowsPackageSkip -Item $m['synapse']          -Fact $script:Server | Should -BeNullOrEmpty
        Test-WindowsPackageSkip -Item $m['chrome']           -Fact $script:Server | Should -BeNullOrEmpty
    }
}

Describe 'Resolve-WindowsSoftwarePlan' {

    BeforeAll {
        $script:toggles = @{ wanted = $true; notwanted = $false; nomapping = $true }
        $script:mappings = @{
            wanted    = [PSCustomObject]@{ Manager = 'winget'; Package = 'Vendor.Wanted'; Source = 'winget' }
            notwanted = [PSCustomObject]@{ Manager = 'winget'; Package = 'Vendor.NotWanted'; Source = 'winget' }
        }
    }

    It 'plans only what is both enabled and mapped' {
        $p = Resolve-WindowsSoftwarePlan -Toggles $script:toggles -Mappings $script:mappings
        $p.Planned.Count | Should -Be 1
        $p.Planned[0].Key | Should -Be 'wanted'
    }

    # The important half of the result. An enabled toggle with nowhere to go means the user
    # asked for software, the run reports success, and the software is absent.
    It 'reports an enabled toggle that has no mapping instead of dropping it' {
        $p = Resolve-WindowsSoftwarePlan -Toggles $script:toggles -Mappings $script:mappings
        $p.Unmapped | Should -Contain 'nomapping'
    }

    It 'never plans a disabled toggle even when it is mapped' {
        $p = Resolve-WindowsSoftwarePlan -Toggles $script:toggles -Mappings $script:mappings
        $p.Planned.Key | Should -Not -Contain 'notwanted'
    }

    It 'narrows to OnlyKeys when the wizard checklist supplied a selection' {
        $p = Resolve-WindowsSoftwarePlan -Toggles $script:toggles -Mappings $script:mappings -OnlyKeys @('somethingelse')
        $p.Planned.Count | Should -Be 0
    }

    It 'produces a plan from the real files that matches the real managers' {
        $t = Get-WindowsSoftwareToggle `
            -AllVarsPath     (Join-Path $script:AnsibleDir 'group_vars\all.yaml') `
            -WindowsVarsPath (Join-Path $script:AnsibleDir 'group_vars\windows.yaml')
        $m = Get-WindowsSoftwareMapping -WindowsMappingPath (Join-Path $script:AnsibleDir 'vars\Windows.yaml')
        $p = Resolve-WindowsSoftwarePlan -Toggles $t -Mappings $m

        $p.Planned.Count | Should -BeGreaterThan 60
        # Only these two managers exist for Windows. A third means someone added a dispatch
        # path the installer does not implement.
        ($p.Planned.Manager | Sort-Object -Unique) | Should -Be @('choco', 'winget')
    }
}

Describe 'Get-WingetPath on a machine without winget' {

    # Server Core has no AppX subsystem, so winget genuinely cannot be here. Asserting the
    # failure is actionable matters more than pretending it can be tested: a null reference
    # would send the next person hunting the wrong thing.
    It 'throws a message that names what to install' {
        if (Get-Command winget -CommandType Application -ErrorAction SilentlyContinue) {
            Set-ItResult -Skipped -Because 'winget is present, so this is not a clean container'
            return
        }
        { Get-WingetPath } | Should -Throw -ExpectedMessage '*App Installer*'
    }
}

Describe 'PinnedValues module' {

    # These do not test the resolver, they test the adapter over it. The resolver lives in
    # setup/pinned_values/pinned_values.py and is the only one in the repository, so what is worth
    # asserting here is that PowerShell gets what the resolver produced without a second parser
    # between them. The module needs a Python 3.11 or newer to reach, which the Windows image pins
    # in from the embeddable zip. If that step ever disappears these fail rather than skip, because
    # a skipped check proves nothing.

    # The two answers this adapter must keep apart. A pin nobody wrote and a pin written as nothing
    # are different faults with different fixes, and Invoke-WindowsCustomInstall reports each as its
    # own named result. An adapter that flattened both into an empty string would make a download
    # location that renders to nothing look like a pin somebody forgot.
    Context 'absence and emptiness are different answers' {

        BeforeAll {
            $script:Fixture = Join-Path $TestDrive 'pins.toml'
            @('[pins]', 'flutter_channel = ""', 'java21_id = "21.0.11-tem"', '[checksums]') |
                Set-Content -LiteralPath $script:Fixture
            # The reader's own override, which is why no test carries the real file's path.
            $env:INSTALLATION_HELPER_PINS_FILE = $script:Fixture
        }

        AfterAll {
            Remove-Item Env:INSTALLATION_HELPER_PINS_FILE -ErrorAction SilentlyContinue
        }

        It 'reads a pin whose value is empty as an empty string, not as absent' {
            $map = Get-PinnedValueMap
            $map.ContainsKey('flutter_channel') | Should -BeTrue
            $map['flutter_channel'] | Should -Be ''
            Get-PinnedValue -Key flutter_channel | Should -Be ''
        }

        It 'has no entry for a pin that is absent from the file' {
            (Get-PinnedValueMap).ContainsKey('java25_id') | Should -BeFalse
        }

        # Absence is the one case that must not come back as a value. It throws, and the message
        # names both the pin and the file it was looked for in, so nobody has to guess which file
        # was read.
        It 'throws on an absent pin, naming the pin and the file it was looked for in' {
            { Get-PinnedValue -Key java25_id } | Should -Throw -ExpectedMessage '*java25_id*pins.toml*'
        }
    }

    Context 'the real pinned values file' {

        It 'hands back a resolved set with no template left in any value' {
            $map = Get-PinnedValueMap
            $map.Count | Should -BeGreaterThan 0
            @($map.Values | Where-Object { $_ -match '\{\{' }) | Should -BeNullOrEmpty
        }

        # default_java is written as a reference to another pin, which is the shape that needed a
        # resolver in the first place. Compared against what it points at rather than against a
        # literal version, so bumping the pin does not need this test edited.
        It 'resolves default_java to the identifier java21_id pins' {
            $map = Get-PinnedValueMap
            $map['default_java'] | Should -Not -Match '\{\{'
            $map['default_java'] | Should -Be $map['java21_id']
        }

        It 'gives one value the same answer as the whole set' {
            Get-PinnedValue -Key default_java | Should -Be (Get-PinnedValueMap)['default_java']
        }
    }
}

Describe 'Install-WingetPackage retries under the shared rule, refreshing its source first' {

    # A stub winget rather than a Pester mock, because the code under test never calls winget through
    # PowerShell: Invoke-BoundedWinget starts a process and reads two redirected files, so a mock
    # would prove nothing about the path that actually runs. The stub answers the `list` probe as
    # "not installed", leaves a marker file per install attempt, so the file count is the attempt
    # count, which is the only state that survives between two separate processes, and appends one
    # line per install or `source update` to calls.log, so the order of the two can be read back.
    #
    # Defined as a global function in BeforeAll, and every It owns its own directory. Pester 5 runs
    # the Describe body at discovery and each It at run time, so a plain function in the body does not
    # exist when the test runs, and `$script:` variables set in one block are not reliably visible in
    # another. Both of those were hit while writing this.
    BeforeAll {
        function global:New-WingetStub {
            param(
                [Parameter(Mandatory)] [string] $Directory,
                [Parameter(Mandatory)] [int] $FailFirstN,
                [switch] $Hang
            )

            $marker1 = Join-Path $Directory 'a1'
            $marker2 = Join-Path $Directory 'a2'
            $marker3 = Join-Path $Directory 'a3'
            $marker4 = Join-Path $Directory 'a4'
            $callLog = Join-Path $Directory 'calls.log'

            if ($IsWindows) {
                $stub = Join-Path $Directory 'winget.cmd'

                if ($Hang) {
                    $body = @"
@echo off
if "%1"=="list" exit /b 1
echo x>"$marker1"
ping -n 300 127.0.0.1 >nul
exit /b 0
"@
                } else {
                    $body = @"
@echo off
if "%1"=="list" exit /b 1
if "%1"=="source" (
  echo refresh %2 %3 %4>>"$callLog"
  exit /b 0
)
echo install>>"$callLog"
if not exist "$marker1" (
  echo x>"$marker1"
  set ATTEMPT=1
) else if not exist "$marker2" (
  echo x>"$marker2"
  set ATTEMPT=2
) else if not exist "$marker3" (
  echo x>"$marker3"
  set ATTEMPT=3
) else (
  echo x>"$marker4"
  set ATTEMPT=4
)
if %ATTEMPT% LEQ $FailFirstN (
  echo Installer failed with exit code: 3221225477
  exit /b 1
)
echo Successfully installed
exit /b 0
"@
                }

                Set-Content -LiteralPath $stub -Value $body -Encoding ascii
            } else {
                # Start-Process execs this file directly on a non-Windows host, which needs a shebang
                # and the execute bit rather than the .cmd extension Windows resolves through its own
                # association, so the stub is a POSIX translation of the same state machine rather
                # than the batch file made executable. 52 of the 58 tests in this suite never touch
                # an external process at all, so there is no existing stub pattern to reuse: this is
                # the one it sets.
                $stub = Join-Path $Directory 'winget'

                if ($Hang) {
                    $body = @"
#!/usr/bin/env bash
if [ "`$1" = "list" ]; then exit 1; fi
echo x > "$marker1"
sleep 300
exit 0
"@
                } else {
                    $body = @"
#!/usr/bin/env bash
if [ "`$1" = "list" ]; then exit 1; fi
if [ "`$1" = "source" ]; then echo "refresh `$2 `$3 `$4" >> "$callLog"; exit 0; fi
echo install >> "$callLog"
if [ ! -f "$marker1" ]; then
  echo x > "$marker1"; attempt=1
elif [ ! -f "$marker2" ]; then
  echo x > "$marker2"; attempt=2
elif [ ! -f "$marker3" ]; then
  echo x > "$marker3"; attempt=3
else
  echo x > "$marker4"; attempt=4
fi
if [ "`$attempt" -le "$FailFirstN" ]; then
  echo "Installer failed with exit code: 3221225477"
  exit 1
fi
echo "Successfully installed"
exit 0
"@
                }

                Set-Content -LiteralPath $stub -Value $body -Encoding ascii
                & chmod +x $stub
            }

            return [PSCustomObject]@{ Path = $stub }
        }

        function global:New-StubDirectory {
            $dir = Join-Path ([System.IO.Path]::GetTempPath()) ('wingetstub-' + [guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            return $dir
        }

        # One marker file per attempt, counted here. @() around Get-ChildItem on purpose: a single
        # file comes back as one object rather than an array, and .Count on that is a terminating
        # error under Set-StrictMode -Version Latest, which is defect class 4 in docs/regression_ledger.md and was
        # hit by the first draft of these very tests.
        function global:Get-StubAttemptCount {
            param([Parameter(Mandatory)] [string] $Directory)
            return @(Get-ChildItem -LiteralPath $Directory -Filter 'a?' -File -ErrorAction SilentlyContinue).Count
        }

        # The install and refresh calls in the order the stub saw them, trimmed of the trailing
        # space a batch echo leaves.
        function global:Get-StubCall {
            param([Parameter(Mandatory)] [string] $Directory)
            $log = Join-Path $Directory 'calls.log'
            if (-not (Test-Path -LiteralPath $log)) { return @() }
            return @(Get-Content -LiteralPath $log | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        }

        Mock Write-Host { }
    }

    It 'never refreshes the source when the first attempt installs' {
        $dir = New-StubDirectory
        try {
            $stub = New-WingetStub -Directory $dir -FailFirstN 0

            $r = Install-WingetPackage -WingetPath $stub.Path -PackageId 'Vendor.Thing' -RetryPauseSeconds 0

            $r.Status | Should -Be 'installed'
            $r.Detail | Should -BeNullOrEmpty
            @(Get-StubCall -Directory $dir) | Should -Be @('install') -Because 'a first attempt runs against the source winget already holds'
        } finally { Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'refreshes the package source before the retry, and names the first failure once the retry installs it' {
        $dir = New-StubDirectory
        try {
            $stub = New-WingetStub -Directory $dir -FailFirstN 1

            $r = Install-WingetPackage -WingetPath $stub.Path -PackageId 'Vendor.Thing' -Source 'winget' -RetryPauseSeconds 0

            $r.Status | Should -Be 'installed'
            $r.Detail | Should -BeLike 'installed on attempt 2 of 4, after attempt 1 said exit 1.*3221225477*'
            @(Get-StubCall -Directory $dir) | Should -Be @('install', 'refresh update --name winget', 'install')
        } finally { Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'stops after the first attempt and three retries, refreshing before each retry, and counts them' {
        $dir = New-StubDirectory
        try {
            $stub = New-WingetStub -Directory $dir -FailFirstN 9

            $r = Install-WingetPackage -WingetPath $stub.Path -PackageId 'Vendor.Thing' -RetryPauseSeconds 0

            $r.Package | Should -Be 'Vendor.Thing'
            $r.Status | Should -Be 'failed'
            $r.Detail | Should -BeLike '*3221225477 (attempt 4 of 4; attempts 1, 2 and 3 said exit 1.*3221225477)'
            Get-StubAttemptCount -Directory $dir | Should -Be 4
            @(Get-StubCall -Directory $dir) | Should -Be @(
                'install', 'refresh update --name winget', 'install', 'refresh update --name winget',
                'install', 'refresh update --name winget', 'install')
        } finally { Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'honours -Retries 0, one attempt and no refresh' {
        $dir = New-StubDirectory
        try {
            $stub = New-WingetStub -Directory $dir -FailFirstN 9

            $r = Install-WingetPackage -WingetPath $stub.Path -PackageId 'Vendor.Thing' -Retries 0 -RetryPauseSeconds 0

            $r.Status | Should -Be 'failed'
            $r.Detail | Should -Not -BeLike '*said*'
            @(Get-StubCall -Directory $dir) | Should -Be @('install')
        } finally { Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'never retries a timeout, because the deadline exists to stop a hang' -Tag 'Slow' {
        $dir = New-StubDirectory
        try {
            $stub = New-WingetStub -Directory $dir -FailFirstN 0 -Hang

            # 30 is the smallest deadline the parameter accepts. A retry would cost that again,
            # which is exactly what a deadline is meant to prevent.
            $r = Install-WingetPackage -WingetPath $stub.Path -PackageId 'Vendor.Thing' -TimeoutSeconds 30 -RetryPauseSeconds 0

            $r.Status | Should -Be 'failed'
            $r.Detail | Should -BeLike '*gave up after 30 seconds*'
            Get-StubAttemptCount -Directory $dir | Should -Be 1
        } finally { Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue }
    }
}


Describe 'Invoke-BoundedWinget reads the output only once the program has finished writing it' {

    # The stub exits at once and leaves a child that still holds its output open and writes one line
    # half a second later, so a read that does not wait for the end of the output finds nothing every
    # time, rather than in about one call of 140 as the plain stub did, entry 10.183 of
    # docs/regression_ledger.md. Skipped on Windows, where Start-Process hands the files to the
    # program itself and that wait does not exist.
    It 'returns a line the program wrote after it exited, while its output was still open' -Skip:$IsWindows {
        $dir = Join-Path ([System.IO.Path]::GetTempPath()) ('boundedwinget-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        try {
            $stub = Join-Path $dir 'winget'
            Set-Content -LiteralPath $stub -Encoding ascii -Value @'
#!/usr/bin/env bash
( sleep 0.5; echo "Installer failed with exit code: 3221225477" ) &
exit 1
'@
            & chmod +x $stub

            $r = Invoke-BoundedWinget -WingetPath $stub -Arguments @('install') -TimeoutSeconds 30

            $r.TimedOut | Should -BeFalse
            $r.ExitCode | Should -Be 1
            $r.Output | Should -BeLike '*Installer failed with exit code: 3221225477*'
        } finally { Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue }
    }
}


Describe 'Every other bounded wait reads the output only once the program has finished writing it' {

    # The same late writer as the Invoke-BoundedWinget test above, one per function that starts a
    # program with redirected output and reads it after a deadline wait, entry 10.183 of
    # docs/regression_ledger.md. Each stub exits 1 at once, so the function reads the files to
    # explain the failure, and the line it must find arrives half a second after the exit. Skipped
    # on Windows, where Start-Process hands the files to the program itself and that wait does not
    # exist. WindowsSettings.ps1 is dot-sourced after WindowsSoftware.ps1, the order setup.ps1 uses.
    BeforeAll {
        . (Join-Path $script:RepoRoot 'setup\windows\WindowsSettings.ps1')

        function global:New-LateWriterStub {
            param([Parameter(Mandatory)] [string] $Path)

            New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force | Out-Null
            Set-Content -LiteralPath $Path -Encoding ascii -Value @'
#!/usr/bin/env bash
( sleep 0.5; echo "late line from a child that still holds the output" ) &
exit 1
'@
            & chmod +x $Path
        }
    }

    AfterAll {
        Remove-Item -LiteralPath Function:\global:New-LateWriterStub -ErrorAction SilentlyContinue
    }

    BeforeEach {
        $script:StubDir = Join-Path ([System.IO.Path]::GetTempPath()) ('boundedwait-' + [guid]::NewGuid().ToString('N'))
    }

    AfterEach {
        Remove-Item -LiteralPath $script:StubDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'Invoke-ManagedTool reports a line the tool wrote after it exited' -Skip:$IsWindows {
        $stub = Join-Path $script:StubDir 'managedtool'
        New-LateWriterStub -Path $stub

        $r = Invoke-ManagedTool -Key 'k' -FilePath $stub -ArgumentList @('install') -TimeoutMinutes 1

        $r.Status | Should -Be 'failed'
        $r.Detail | Should -BeLike 'exit 1.*late line from a child that still holds the output*'
    }

    It 'Invoke-AndroidSdkManager reports a line sdkmanager wrote after it exited' -Skip:$IsWindows {
        $saved = $script:AndroidSdkRoot
        try {
            $script:AndroidSdkRoot = $script:StubDir
            New-LateWriterStub -Path (Join-Path $script:AndroidSdkRoot 'cmdline-tools\latest\bin\sdkmanager.bat')

            $r = Invoke-AndroidSdkManager -Arguments @('platform-tools') -TimeoutMinutes 1
        } finally {
            $script:AndroidSdkRoot = $saved
        }

        $r.Status | Should -Be 'failed'
        $r.Detail | Should -BeLike 'exit 1.*late line from a child that still holds the output*'
    }

    It 'Install-WslDistribution reports a line wsl wrote after it exited' -Skip:$IsWindows {
        $stub = Join-Path $script:StubDir 'wsl.exe'
        New-LateWriterStub -Path $stub
        Mock Get-Command { [PSCustomObject]@{ Source = 'wsl.exe' } } -ParameterFilter { $Name -contains 'wsl' }
        Mock Get-WslDistributionName { @() }
        Mock Start-Sleep { }
        Mock Write-Host { }
        $savedPath = $env:PATH
        try {
            $env:PATH = $script:StubDir + [System.IO.Path]::PathSeparator + $savedPath
            # Defect class 16: the stub must be the wsl.exe Start-Process finds, proven before it runs.
            (Microsoft.PowerShell.Core\Get-Command -Name 'wsl.exe' -CommandType Application -ErrorAction Stop)[0].Source | Should -Be $stub

            $r = @(Install-WslDistribution -TimeoutMinutes 1)
        } finally {
            $env:PATH = $savedPath
        }

        $r[0].Status | Should -Be 'failed'
        $r[0].Detail | Should -BeLike 'wsl --install exited 1. late line from a child that still holds the output*'
    }

    # Read from the syntax tree, so a new function that reads redirected output after its own
    # deadline wait fails here by name rather than now and then in the gate.
    It 'waits through Wait-BoundedProcess in every function that redirects a program''s output' {
        $files = @(
            (Join-Path $script:RepoRoot 'setup\setup.ps1')
            @(Get-ChildItem -LiteralPath (Join-Path $script:RepoRoot 'setup\windows') -Filter '*.ps1' | ForEach-Object FullName)
        )
        $redirecting = foreach ($file in $files) {
            $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($file, [ref]$null, [ref]$errors)
            if ($errors) { throw "$file does not parse: $($errors[0].Message)" }
            foreach ($function in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) {
                $redirects = $function.Body.FindAll({ param($n)
                    $n -is [System.Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'Start-Process' -and
                    @($n.CommandElements | Where-Object { $_ -is [System.Management.Automation.Language.CommandParameterAst] -and $_.ParameterName -eq 'RedirectStandardOutput' }).Count -gt 0 }, $true)
                if (@($redirects).Count -eq 0) { continue }
                $ownWaits = $function.Body.FindAll({ param($n)
                    $n -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and $n.Member.Extent.Text -eq 'WaitForExit' }, $true)
                $sharedWaits = $function.Body.FindAll({ param($n)
                    $n -is [System.Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'Wait-BoundedProcess' }, $true)
                [PSCustomObject]@{ Name = $function.Name; OwnWaits = @($ownWaits).Count; SharedWaits = @($sharedWaits).Count }
            }
        }

        @($redirecting.Name) | Should -Contain 'Invoke-BoundedWinget'
        @($redirecting.Name) | Should -Contain 'Invoke-ManagedTool'
        @($redirecting.Name) | Should -Contain 'Invoke-AndroidSdkManager'
        @($redirecting.Name) | Should -Contain 'Install-WslDistribution'
        @($redirecting | Where-Object { $_.OwnWaits -gt 0 -or $_.SharedWaits -eq 0 } | ForEach-Object Name) | Should -BeNullOrEmpty
    }
}


Describe 'Get-CommandOutputTail' {

    # On Windows, Out-String and the file Start-Process redirects into end each line with a carriage
    # return and a line feed. On Linux both end it with a line feed only, so the winget and npm tests
    # cannot show a carriage return there, and run 39168859916 showed it only on the Windows runner.
    It 'drops the carriage return Windows ends every line with' {
        Get-CommandOutputTail -Text "npm error code E404`r`nnpm error 404 Not Found`r`n" |
            Should -BeExactly 'npm error code E404 npm error 404 Not Found'
    }

    It 'keeps the last two lines that carry text' {
        Get-CommandOutputTail -Text "first`nsecond`n   `nthird`n" | Should -BeExactly 'second third'
    }

    It 'returns an empty string when the program wrote nothing' {
        Get-CommandOutputTail -Text $null | Should -BeExactly ''
    }
}

Describe 'Invoke-PackageManagerRetry, the one retry rule every package manager follows' {

    BeforeEach {
        $global:RetryCalls = [System.Collections.Generic.List[string]]::new()
        $global:RetryFailuresLeft = 0
        Mock Start-Sleep { $global:RetryCalls.Add("wait $Seconds") }
        Mock Write-Host { }
        $script:FailingAttempt = {
            $global:RetryCalls.Add('install')
            if ($global:RetryFailuresLeft -gt 0) {
                $global:RetryFailuresLeft--
                return [PSCustomObject]@{ Succeeded = $false; Final = $false; Failure = 'mirror answered 404' }
            }
            return [PSCustomObject]@{ Succeeded = $true; Final = $false; Failure = '' }
        }
        $script:Refresh = { $global:RetryCalls.Add('refresh'); '' }
    }

    It 'uses the retries and the delay of the Ansible package helper' {
        $helper = Get-Content -LiteralPath (Join-Path $script:AnsibleDir 'tasks\install_role_packages.yaml') -Raw

        $helper | Should -Match "(?m)^\s+retries: $([regex]::Escape([string]$script:PackageRetryCount))\s*$" -Because 'one rule, so the Windows count must be one the Ansible helper uses'
        $helper | Should -Match ([regex]::Escape("role_packages_retry_delay | default($script:PackageRetryDelaySeconds)"))
    }

    It 'never refreshes when the first attempt succeeds' {
        $r = Invoke-PackageManagerRetry -Package 'pkg' -Attempt $script:FailingAttempt -Refresh $script:Refresh

        $r.Succeeded | Should -BeTrue
        $r.Attempts | Should -Be 1
        $r.Detail | Should -BeNullOrEmpty
        @($global:RetryCalls) | Should -Be @('install')
    }

    It 'waits the shared delay, then refreshes, then retries, in that order' {
        $global:RetryFailuresLeft = 1

        $r = Invoke-PackageManagerRetry -Package 'pkg' -Attempt $script:FailingAttempt -Refresh $script:Refresh

        $r.Succeeded | Should -BeTrue
        $r.Attempts | Should -Be 2
        $r.Detail | Should -Be 'installed on attempt 2 of 4, after attempt 1 said mirror answered 404'
        @($global:RetryCalls) | Should -Be @('install', 'wait 20', 'refresh', 'install')
    }

    It 'names and counts a package that fails every attempt, after the first attempt and three retries' {
        $global:RetryFailuresLeft = 99

        $r = Invoke-PackageManagerRetry -Package 'pkg' -Attempt $script:FailingAttempt -Refresh $script:Refresh

        $r.Package | Should -Be 'pkg'
        $r.Succeeded | Should -BeFalse
        $r.Attempts | Should -Be 4
        $r.MaxAttempts | Should -Be 4
        @($r.Failures).Count | Should -Be 4
        $r.Detail | Should -Be 'mirror answered 404 (attempt 4 of 4; attempts 1, 2 and 3 said mirror answered 404)'
        @($global:RetryCalls | Where-Object { $_ -eq 'refresh' }).Count | Should -Be 3
        $global:RetryCalls[-1] | Should -Be 'install' -Because 'there is no refresh after the last attempt'
    }

    It 'stops at a final failure without waiting or refreshing' {
        $final = { $global:RetryCalls.Add('install'); [PSCustomObject]@{ Succeeded = $false; Final = $true; Failure = 'killed after its deadline' } }

        $r = Invoke-PackageManagerRetry -Package 'pkg' -Attempt $final -Refresh $script:Refresh

        $r.Attempts | Should -Be 1
        $r.Detail | Should -Be 'killed after its deadline'
        @($global:RetryCalls) | Should -Be @('install')
    }

    It 'reports a refresh that failed and still runs the retry' {
        $global:RetryFailuresLeft = 1
        $broken = { $global:RetryCalls.Add('refresh'); 'source update exited 2' }

        $r = Invoke-PackageManagerRetry -Package 'pkg' -Attempt $script:FailingAttempt -Refresh $broken

        $r.Succeeded | Should -BeTrue
        @($r.RefreshFailures) | Should -Be @('source update exited 2')
        $r.Detail | Should -BeLike '*The refresh before a retry failed: source update exited 2'
    }

    It 'only waits for a manager with no refresh step' {
        $global:RetryFailuresLeft = 1

        $r = Invoke-PackageManagerRetry -Package 'pkg' -Attempt $script:FailingAttempt

        $r.Succeeded | Should -BeTrue
        @($global:RetryCalls) | Should -Be @('install', 'wait 20', 'install')
    }
}

Describe 'Install-ChocolateyPackage retries under the shared rule, emptying the HTTP cache first' {

    # A global choco function, for the reason the npm tests use one: `& choco` resolves a function
    # before an application, and the function can set LASTEXITCODE the way choco does.
    BeforeAll {
        function global:choco {
            $global:ChocoStubCalls.Add(($args -join ' '))
            if ($args[0] -eq 'cache') {
                $global:LASTEXITCODE = $global:ChocoStubCacheExit
                return 'removed 3 cached items'
            }
            if ($args[0] -eq 'list') {
                $global:LASTEXITCODE = 0
                if ($global:ChocoStubInstalled -contains $args[-1]) { return "$($args[-1])|1.0.0" }
                return
            }
            if ($global:ChocoStubFailuresLeft -gt 0) {
                $global:ChocoStubFailuresLeft--
                $global:LASTEXITCODE = 1
                return 'The remote file either does not exist, is unauthorized, or is forbidden for url'
            }
            $global:LASTEXITCODE = 0
            # What Chocolatey 2 prints, and the exit code it gives, when the feed answers 503.
            if ($global:ChocoStubSilentLeft -gt 0) {
                $global:ChocoStubSilentLeft--
                return @('Installing the following packages:', $args[1], 'Chocolatey installed 0/0 packages.')
            }
            $global:ChocoStubInstalled.Add($args[1])
            return 'The install of thing was successful.'
        }
    }

    AfterAll {
        Remove-Item -LiteralPath Function:\global:choco -ErrorAction SilentlyContinue
    }

    BeforeEach {
        $global:ChocoStubCalls = [System.Collections.Generic.List[string]]::new()
        $global:ChocoStubInstalled = [System.Collections.Generic.List[string]]::new()
        $global:ChocoStubFailuresLeft = 0
        $global:ChocoStubSilentLeft = 0
        $global:ChocoStubCacheExit = 0
        Mock Start-Sleep { }
        Mock Write-Host { }
    }

    It 'never empties the cache when the first attempt installs' {
        $r = Install-ChocolateyPackage -PackageId 'thing'

        $r.Status | Should -Be 'installed'
        $r.Attempts | Should -Be 1
        @($global:ChocoStubCalls) | Should -Be @('install thing -y --no-progress --limit-output --execution-timeout=600'
                                                 'list --local-only --limit-output --exact thing')
    }

    It 'empties the HTTP cache before the retry' {
        $global:ChocoStubFailuresLeft = 1

        $r = Install-ChocolateyPackage -PackageId 'thing'

        $r.Status | Should -Be 'installed'
        $r.Detail | Should -BeLike 'installed on attempt 2 of 4, after attempt 1 said choco exited 1.*'
        @($global:ChocoStubCalls | ForEach-Object { ($_ -split ' ')[0] }) | Should -Be @('install', 'cache', 'install', 'list')
        $global:ChocoStubCalls[1] | Should -Be 'cache remove -y --limit-output'
    }

    It 'names and counts a package that fails every attempt, with its exit code' {
        $global:ChocoStubFailuresLeft = 99

        $r = Install-ChocolateyPackage -PackageId 'thing'

        $r.Package | Should -Be 'thing'
        $r.Status | Should -Be 'failed'
        $r.ExitCode | Should -Be 1
        $r.Attempts | Should -Be 4
        $r.Detail | Should -BeLike 'choco exited 1.*(attempt 4 of 4; attempts 1, 2 and 3 said choco exited 1.*)'
        @($global:ChocoStubCalls | Where-Object { $_ -like 'install *' }).Count | Should -Be 4
        @($global:ChocoStubCalls | Where-Object { $_ -like 'cache *' }).Count | Should -Be 3
        Should -Invoke Start-Sleep -Times 3 -Exactly -ParameterFilter { $Seconds -eq 20 }
    }

    It 'still retries when an older Chocolatey has no cache command, and says so' {
        $global:ChocoStubFailuresLeft = 1
        $global:ChocoStubCacheExit = 1

        $r = Install-ChocolateyPackage -PackageId 'thing'

        $r.Status | Should -Be 'installed'
        $r.Detail | Should -BeLike '*The refresh before a retry failed: choco cache remove exited 1*'
    }

    It 'retries, after emptying the cache, a package Chocolatey exits 0 for without installing it' {
        $global:ChocoStubSilentLeft = 1

        $r = Install-ChocolateyPackage -PackageId 'thing'

        $r.Status | Should -Be 'installed'
        $r.Attempts | Should -Be 2
        $r.Detail | Should -Be 'installed on attempt 2 of 4, after attempt 1 said choco exited 0 and does not list thing as installed. Chocolatey installed 0/0 packages.'
        @($global:ChocoStubCalls | ForEach-Object { ($_ -split ' ')[0] }) | Should -Be @('install', 'list', 'cache', 'install', 'list')
    }

    It 'names a package Chocolatey exits 0 for on every attempt without installing it as failed' {
        $global:ChocoStubSilentLeft = 99

        $r = Install-ChocolateyPackage -PackageId 'thing'

        $r.Status | Should -Be 'failed'
        $r.Attempts | Should -Be 4
        $r.ExitCode | Should -Be 0
        $r.Detail | Should -BeLike 'choco exited 0 and does not list thing as installed. Chocolatey installed 0/0 packages. (attempt 4 of 4; attempts 1, 2 and 3 said*'
        @($global:ChocoStubCalls | Where-Object { $_ -like 'install *' }).Count | Should -Be 4
        @($global:ChocoStubCalls | Where-Object { $_ -like 'cache *' }).Count | Should -Be 3
    }
}

Describe 'Install-ChocolateyPackageBatch runs the shared rule in its elevated child' {

    # The child script is run for real, in a separate pwsh, with a choco function and a no-op
    # Start-Sleep defined ahead of it, so what is tested is the text the wizard hands to the elevated
    # process, including its dot-source of this file and the result file it writes back.
    BeforeEach {
        $global:ChildCallLog = Join-Path $TestDrive 'choco-calls.log'
        Remove-Item -LiteralPath $global:ChildCallLog -Force -ErrorAction SilentlyContinue
        Mock Invoke-ElevatedPowerShell {
            $logLiteral = "'" + ($global:ChildCallLog -replace "'", "''") + "'"
            $prelude = @"
function Start-Sleep { }
function choco {
    Add-Content -LiteralPath $logLiteral -Value (`$args -join ' ')
    if (`$args[0] -eq 'cache') { `$global:LASTEXITCODE = 0; return }
    if (`$args[0] -eq 'list') { `$global:LASTEXITCODE = 0; if (`$args[-1] -eq 'good-pkg') { return 'good-pkg|1.0.0' }; return }
    if (`$args[1] -eq 'broken-pkg') { `$global:LASTEXITCODE = 42; return 'ERROR: Running installer failed' }
    `$global:LASTEXITCODE = 0
    if (`$args[1] -eq 'silent-pkg') { return 'Chocolatey installed 0/0 packages.' }
}
"@
            $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($prelude + "`n" + $Script))
            & (Join-Path $PSHOME 'pwsh') -NoProfile -NonInteractive -EncodedCommand $encoded *> $null
            [PSCustomObject]@{ ExitCode = $LASTEXITCODE; TimedOut = $false; StartError = ''; Refused = $false }
        }
    }

    It 'installs each package through Install-ChocolateyPackage and hands back each one''s result' {
        $batch = Install-ChocolateyPackageBatch -PackageId @('good-pkg', 'broken-pkg')

        $batch.Status | Should -Be 'failed'
        $batch.Detail | Should -BeLike 'choco exited 42*' -Because 'the child exits with the code of its last failed package'
        $batch.Packages['good-pkg'].Status | Should -Be 'installed'
        $batch.Packages['good-pkg'].Attempts | Should -Be 1
        $batch.Packages['broken-pkg'].Status | Should -Be 'failed'
        $batch.Packages['broken-pkg'].Attempts | Should -Be 4
        $batch.Packages['broken-pkg'].Detail | Should -BeLike 'choco exited 42. ERROR: Running installer failed (attempt 4 of 4; attempts 1, 2 and 3 said*'
        $calls = @(Get-Content -LiteralPath $global:ChildCallLog)
        @($calls | Where-Object { $_ -like 'install broken-pkg *' }).Count | Should -Be 4
        @($calls | Where-Object { $_ -like 'install good-pkg *' }).Count | Should -Be 1
        @($calls | Where-Object { $_ -like 'cache remove*' }).Count | Should -Be 3
    }

    It 'fails the session when Chocolatey exits 0 for a package it never installs' {
        $batch = Install-ChocolateyPackageBatch -PackageId @('good-pkg', 'silent-pkg')

        $batch.Status | Should -Be 'failed' -Because 'a package that is not installed must not leave the child exiting 0'
        $batch.Packages['good-pkg'].Status | Should -Be 'installed'
        $batch.Packages['silent-pkg'].Status | Should -Be 'failed'
        $batch.Packages['silent-pkg'].Attempts | Should -Be 4
        $batch.Packages['silent-pkg'].Detail | Should -BeLike 'choco exited 0 and does not list silent-pkg as installed. Chocolatey installed 0/0 packages. (attempt 4 of 4;*'
        $calls = @(Get-Content -LiteralPath $global:ChildCallLog)
        @($calls | Where-Object { $_ -like 'install silent-pkg *' }).Count | Should -Be 4
    }

    It 'names the failing package with its own attempts in the software phase result' {
        Mock Get-WindowsMachineFact { [PSCustomObject]@{ InstallationType = 'Client'; IsElevated = $false; NvidiaAdapters = @() } }
        $global:ChocoListed = @()
        Mock Get-ChocolateyInstalledPackage { $global:ChocoListed }
        Mock Install-ChocolateyPackageBatch {
            $global:ChocoListed = @('maven')
            [PSCustomObject]@{
                Status   = 'failed'
                Detail   = 'choco exited 1'
                Packages = @{
                    'maven'  = [PSCustomObject]@{ Package = 'maven'; Status = 'installed'; ExitCode = 0; Attempts = 1; Detail = '' }
                    'gradle' = [PSCustomObject]@{ Package = 'gradle'; Status = 'failed'; ExitCode = 1; Attempts = 4; Detail = 'choco exited 1. 404 (attempt 4 of 4; attempts 1, 2 and 3 said choco exited 1. 404)' }
                }
            }
        }

        $summary = Invoke-WindowsSoftwareInstall -AnsibleDir $script:AnsibleDir -OnlyKeys @('maven', 'gradle') `
            -ToggleOverride @{ install_maven = $true; install_gradle = $true }

        @($summary.Installed).Package | Should -Be @('maven')
        @($summary.Failed).Count | Should -Be 1
        $summary.Failed[0].Package | Should -Be 'gradle'
        $summary.Failed[0].Detail | Should -Be 'Chocolatey does not list gradle as installed after its install, which failed on 4 attempt(s): choco exited 1. 404 (attempt 4 of 4; attempts 1, 2 and 3 said choco exited 1. 404)'
    }
}


# The owner's rule of 2026-10-11 moved Slack, Claude Desktop and Syncthing to machine scope, and
# GitHub sweep 38130934506 sent Slack and Claude Desktop back to user scope after Windows Server
# refused their machine-wide msix. Syncthing stays machine-wide, and winget refuses a machine-scope msix or portable unless winget itself is elevated, while the wizard
# refuses to run elevated. These are the decision and the route around it.
Describe 'Test-WingetElevationRequired' {

    It 'elevates a machine-scope install of every type winget refuses unelevated' {
        Mock Test-IsAdministrator { $false }
        foreach ($type in @('msix', 'portable', 'msstore', 'font')) {
            Test-WingetElevationRequired -Scope 'machine' -InstallerType $type | Should -BeTrue -Because "$type is in DoesInstallerTypeRequireAdminForMachineScopeInstall"
        }
    }

    It 'leaves every installer that elevates itself in this process' {
        Mock Test-IsAdministrator { $false }
        foreach ($type in @('exe', 'inno', 'nullsoft', 'wix', 'burn', 'msi')) {
            Test-WingetElevationRequired -Scope 'machine' -InstallerType $type | Should -BeFalse -Because "$type asks for elevation itself"
        }
    }

    It 'never elevates a user-scope or unscoped install' {
        Mock Test-IsAdministrator { $false }
        Test-WingetElevationRequired -Scope 'user' -InstallerType 'msix' | Should -BeFalse
        Test-WingetElevationRequired -Scope '' -InstallerType 'msix' | Should -BeFalse
    }

    It 'never elevates when the wizard already is, which is the GitHub runner' {
        Mock Test-IsAdministrator { $true }
        Test-WingetElevationRequired -Scope 'machine' -InstallerType 'msix' | Should -BeFalse
    }

    It 'elevates exactly Syncthing out of the real mapping file' {
        Mock Test-IsAdministrator { $false }
        $m = Get-WindowsSoftwareMapping -WindowsMappingPath (Join-Path $script:AnsibleDir 'vars\Windows.yaml')
        $elevated = @($m.Keys | Where-Object {
                $m[$_].Manager -eq 'winget' -and (Test-WingetElevationRequired -Scope $m[$_].Scope -InstallerType $m[$_].InstallerType)
            } | Sort-Object)
        $elevated | Should -Be @('syncthing')
    }
}

Describe 'Install-WingetPackage asks about a machine-wide copy by scope and elevates winget when it must' {

    BeforeAll {
        # The winget calls are recorded rather than run, one entry per call with its route, so each
        # test can say which question went where. A global list because Pester 5 runs the mocks in
        # their own scope.
        function global:Get-WingetVerb { param([string[]] $Arguments) $Arguments[0] }
        function global:Get-WingetScope {
            param([string[]] $Arguments)
            $at = [array]::IndexOf($Arguments, '--scope')
            if ($at -ge 0) { return $Arguments[$at + 1] }
            return ''
        }
    }

    BeforeEach {
        $global:WingetCalls = [System.Collections.Generic.List[string]]::new()
        $global:MachineCopy = $false
        $global:UserCopy = $false
        $global:InstallFailuresLeft = 0
        Mock Start-Sleep { }
        Mock Write-Host { }
        Mock Test-IsAdministrator { $false }

        function global:Invoke-WingetAnswer {
            param([string] $Route, [string[]] $Arguments)
            $verb = Get-WingetVerb -Arguments $Arguments
            $scope = Get-WingetScope -Arguments $Arguments
            $global:WingetCalls.Add("$Route $verb $scope".Trim())
            if ($verb -eq 'list') {
                $found = switch ($scope) {
                    'machine' { $global:MachineCopy }
                    'user'    { $global:UserCopy }
                    default   { $global:MachineCopy -or $global:UserCopy }
                }
                return [PSCustomObject]@{ Output = ''; ExitCode = $(if ($found) { 0 } else { -1978335212 }); TimedOut = $false }
            }
            if ($global:InstallFailuresLeft -gt 0) {
                $global:InstallFailuresLeft--
                return [PSCustomObject]@{ Output = 'Installer failed with exit code: 3221225477'; ExitCode = 1; TimedOut = $false }
            }
            return [PSCustomObject]@{ Output = 'Successfully installed'; ExitCode = 0; TimedOut = $false }
        }
        Mock Invoke-BoundedWinget { Invoke-WingetAnswer -Route 'bounded' -Arguments $Arguments }
        Mock Invoke-ElevatedWinget { Invoke-WingetAnswer -Route 'elevated' -Arguments $Arguments }
    }

    It 'runs the machine probe and the install of a machine-scope msix in the elevated child' {
        $r = Install-WingetPackage -WingetPath 'winget' -PackageId 'SlackTechnologies.Slack' -Scope 'machine' -InstallerType 'msix' -RetryPauseSeconds 0

        $r.Status | Should -Be 'installed'
        @($global:WingetCalls) | Should -Be @('elevated list machine', 'bounded list user', 'elevated install machine')
    }

    It 'elevates only the install of a machine-scope portable, whose machine copy any user can list' {
        $r = Install-WingetPackage -WingetPath 'winget' -PackageId 'Syncthing.Syncthing' -Scope 'machine' -InstallerType 'portable' -RetryPauseSeconds 0

        $r.Status | Should -Be 'installed'
        @($global:WingetCalls) | Should -Be @('bounded list machine', 'bounded list user', 'elevated install machine')
    }

    It 'keeps a machine-scope installer that elevates itself in this process' {
        $r = Install-WingetPackage -WingetPath 'winget' -PackageId 'Git.Git' -Scope 'machine' -InstallerType 'inno' -RetryPauseSeconds 0

        $r.Status | Should -Be 'installed'
        Should -Invoke Invoke-ElevatedWinget -Times 0 -Exactly
        @($global:WingetCalls) | Should -Be @('bounded list machine', 'bounded list user', 'bounded install machine')
    }

    It 'runs everything in this process when the wizard is already elevated' {
        Mock Test-IsAdministrator { $true }
        $r = Install-WingetPackage -WingetPath 'winget' -PackageId 'Syncthing.Syncthing' -Scope 'machine' -InstallerType 'portable' -RetryPauseSeconds 0

        $r.Status | Should -Be 'installed'
        Should -Invoke Invoke-ElevatedWinget -Times 0 -Exactly
    }

    It 'retries an elevated install the way it retries any other, and names the first failure' {
        $global:InstallFailuresLeft = 1
        $r = Install-WingetPackage -WingetPath 'winget' -PackageId 'Anthropic.Claude' -Scope 'machine' -InstallerType 'msix' -RetryPauseSeconds 0

        $r.Status | Should -Be 'installed'
        $r.Detail | Should -BeLike '*attempt 2*3221225477*'
        @($global:WingetCalls | Where-Object { $_ -eq 'elevated install machine' }).Count | Should -Be 2
    }

    It 'reports a machine-wide copy as present and installs nothing' {
        $global:MachineCopy = $true
        $r = Install-WingetPackage -WingetPath 'winget' -PackageId 'Git.Git' -Scope 'machine' -InstallerType 'inno'

        $r.Status | Should -Be 'present'
        @($global:WingetCalls) | Should -Be @('bounded list machine')
    }

    It 'reports a per-user copy of a machine-pinned package by name, with the uninstall command, and installs and removes nothing' {
        $global:UserCopy = $true
        $r = Install-WingetPackage -WingetPath 'winget' -PackageId 'Microsoft.VisualStudioCode' -Scope 'machine' -InstallerType 'inno'

        $r.Status | Should -Be 'skipped'
        $r.Detail | Should -BeLike 'installed for this user only, the machine-wide install was skipped*'
        $r.Detail | Should -BeLike "*winget uninstall --exact --id Microsoft.VisualStudioCode --scope user*"
        @($global:WingetCalls) | Should -Be @('bounded list machine', 'bounded list user')
    }

    It 'still counts any copy as present for a package pinned to user or not pinned at all' {
        $global:UserCopy = $true
        (Install-WingetPackage -WingetPath 'winget' -PackageId 'Discord.Discord' -Scope 'user').Status | Should -Be 'present'
        (Install-WingetPackage -WingetPath 'winget' -PackageId 'Google.Chrome').Status | Should -Be 'present'
        @($global:WingetCalls) | Should -Be @('bounded list', 'bounded list')
    }
}

Describe 'Invoke-ElevatedWinget and Invoke-ElevatedPowerShell' {

    BeforeEach {
        $global:StubDir = Join-Path ([System.IO.Path]::GetTempPath()) ('elevstub-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $global:StubDir -Force | Out-Null
    }

    AfterEach {
        Remove-Item -LiteralPath $global:StubDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    # The child's script is real and runs for real, in this process rather than behind a consent
    # prompt: it dot-sources WindowsSoftware.ps1, runs Invoke-BoundedWinget against a stub winget and
    # writes JSON back. Only the elevation is replaced.
    It 'runs the bounded winget in the child and hands back its output, exit code and arguments' -Skip:(-not $IsWindows) {
        $stub = Join-Path $global:StubDir 'winget.cmd'
        $argsFile = Join-Path $global:StubDir 'args.txt'
        Set-Content -LiteralPath $stub -Encoding ascii -Value @"
@echo off
echo %*>"$argsFile"
echo Successfully installed
exit /b 7
"@
        Mock Invoke-ElevatedPowerShell {
            & ([scriptblock]::Create($Script))
            [PSCustomObject]@{ ExitCode = 0; TimedOut = $false; StartError = '' }
        }

        $r = Invoke-ElevatedWinget -WingetPath $stub -TimeoutSeconds 60 -Arguments @('install', '--exact', '--id', "Vendor.It's", '--scope', 'machine')

        $r.ExitCode | Should -Be 7
        $r.TimedOut | Should -BeFalse
        $r.Output   | Should -BeLike '*Successfully installed*'
        (Get-Content -LiteralPath $argsFile -Raw) | Should -BeLike "*--id Vendor.It's --scope machine*"
        Should -Invoke Invoke-ElevatedPowerShell -Times 1 -Exactly -ParameterFilter { $TimeoutSeconds -eq 360 }
    }

    It 'turns a refused consent prompt into a failed run that says why' {
        Mock Invoke-ElevatedPowerShell { [PSCustomObject]@{ ExitCode = -1; TimedOut = $false; StartError = 'The operation was canceled by the user.' } }
        $r = Invoke-ElevatedWinget -WingetPath 'winget' -Arguments @('install', '--id', 'X')
        $r.ExitCode | Should -Be -1
        $r.TimedOut | Should -BeFalse
        $r.Output   | Should -BeLike '*could not start winget elevated*canceled by the user*'
    }

    It 'turns an unanswered prompt into a timeout, which Install-WingetPackage never retries' {
        Mock Invoke-ElevatedPowerShell { [PSCustomObject]@{ ExitCode = -1; TimedOut = $true; StartError = '' } }
        (Invoke-ElevatedWinget -WingetPath 'winget' -Arguments @('install', '--id', 'X')).TimedOut | Should -BeTrue
    }

    It 'says so when the child wrote nothing back' {
        Mock Invoke-ElevatedPowerShell { [PSCustomObject]@{ ExitCode = 3; TimedOut = $false; StartError = '' } }
        $r = Invoke-ElevatedWinget -WingetPath 'winget' -Arguments @('install', '--id', 'X')
        $r.ExitCode | Should -Be -1
        $r.Output   | Should -BeLike '*exited 3 without writing a result*'
    }

    It 'asks for elevation through RunAs when the wizard is not elevated' {
        Mock Test-IsAdministrator { $false }
        Mock Start-Process {
            $p = [PSCustomObject]@{ ExitCode = 0; Id = 1 }
            $p | Add-Member -MemberType ScriptMethod -Name WaitForExit -Value { param($ms) $true }
            $p
        }
        $r = Invoke-ElevatedPowerShell -Script 'exit 0' -TimeoutSeconds 30
        $r.StartError | Should -BeNullOrEmpty
        Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter { $Verb -eq 'RunAs' -and -not $NoNewWindow }
    }

    It 'runs in this console when the wizard is already elevated, because RunAs needs a desktop' {
        Mock Test-IsAdministrator { $true }
        Mock Start-Process {
            $p = [PSCustomObject]@{ ExitCode = 0; Id = 1 }
            $p | Add-Member -MemberType ScriptMethod -Name WaitForExit -Value { param($ms) $true }
            $p
        }
        $null = Invoke-ElevatedPowerShell -Script 'exit 0' -TimeoutSeconds 30
        Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter { $NoNewWindow -and -not $Verb }
    }

    It 'reports a refused prompt as a refused start rather than throwing' {
        Mock Test-IsAdministrator { $false }
        Mock Start-Process { throw 'The operation was canceled by the user.' }
        $r = Invoke-ElevatedPowerShell -Script 'exit 0' -TimeoutSeconds 30
        $r.StartError | Should -BeLike 'the administrator consent prompt was refused*canceled by the user*'
        $r.Refused    | Should -BeTrue
    }

    It 'reports any other failure to start as a start error that is not a refusal' {
        Mock Test-IsAdministrator { $false }
        Mock Start-Process { throw [System.ComponentModel.Win32Exception]::new(2) }
        $r = Invoke-ElevatedPowerShell -Script 'exit 0' -TimeoutSeconds 30
        $r.StartError | Should -Not -BeNullOrEmpty
        $r.Refused    | Should -BeFalse
    }

    It 'tells a refused consent prompt from any other failure to start' {
        Test-ConsentRefusal -Exception ([System.ComponentModel.Win32Exception]::new(1223)) | Should -BeTrue
        Test-ConsentRefusal -Exception ([System.InvalidOperationException]::new('outer', [System.ComponentModel.Win32Exception]::new(1223))) | Should -BeTrue
        Test-ConsentRefusal -Exception ([System.ComponentModel.Win32Exception]::new(2)) | Should -BeFalse
    }
}

# A machine-scope msix already provisioned for every user is also registered for this one, so
# winget list --scope user finds it. When the elevated machine check never ran, falling through to
# that user check reported Slack as "installed for this user only", which is the wrong verdict about
# a machine-wide install.
Describe 'Install-WingetPackage reports an unanswered machine-wide check as unknown' {

    BeforeEach {
        $global:BoundedCalls = [System.Collections.Generic.List[string]]::new()
        Mock Start-Sleep { }
        Mock Write-Host { }
        Mock Test-IsAdministrator { $false }
        Mock Invoke-BoundedWinget {
            $global:BoundedCalls.Add(($Arguments -join ' '))
            # The provisioned copy is registered for this user, so every unelevated list finds it.
            [PSCustomObject]@{ Output = ''; ExitCode = 0; TimedOut = $false }
        }
    }

    It 'says the machine-wide check of an already provisioned msix was refused, never that it is installed for this user only' {
        Mock Invoke-ElevatedPowerShell {
            [PSCustomObject]@{ ExitCode = -1; TimedOut = $false; StartError = 'the administrator consent prompt was refused (The operation was canceled by the user.)'; Refused = $true }
        }

        $r = Install-WingetPackage -WingetPath 'winget' -PackageId 'SlackTechnologies.Slack' -Scope 'machine' -InstallerType 'msix' -RetryPauseSeconds 0

        $r.Detail | Should -Not -BeLike '*installed for this user only*'
        $r.Status | Should -Be 'failed'
        $r.Detail | Should -BeLike 'the machine-wide check was refused, so whether SlackTechnologies.Slack is installed for all users is unknown*'
        Should -Invoke Invoke-ElevatedPowerShell -Times 1 -Exactly -Because 'nothing is installed and nothing is asked again after a refusal'
        $global:BoundedCalls.Count | Should -Be 0 -Because 'the per-user answer cannot tell a provisioned copy from a per-user one'
    }

    It 'says the machine-wide check could not run, and why, when the elevated child failed for another reason' {
        Mock Invoke-ElevatedPowerShell { [PSCustomObject]@{ ExitCode = 3; TimedOut = $false; StartError = ''; Refused = $false } }

        $r = Install-WingetPackage -WingetPath 'winget' -PackageId 'Anthropic.Claude' -Scope 'machine' -InstallerType 'msix' -RetryPauseSeconds 0

        $r.Status | Should -Be 'failed'
        $r.Detail | Should -BeLike 'the machine-wide check could not run, so whether Anthropic.Claude is installed for all users is unknown*exited 3 without writing a result*'
        $global:BoundedCalls.Count | Should -Be 0
    }

    It 'does not retry an elevated install that never ran, because a retry would only ask again after a refusal' {
        Mock Invoke-BoundedWinget { [PSCustomObject]@{ Output = ''; ExitCode = -1978335212; TimedOut = $false } }
        Mock Invoke-ElevatedPowerShell {
            [PSCustomObject]@{ ExitCode = -1; TimedOut = $false; StartError = 'the administrator consent prompt was refused (The operation was canceled by the user.)'; Refused = $true }
        }

        $r = Install-WingetPackage -WingetPath 'winget' -PackageId 'Syncthing.Syncthing' -Scope 'machine' -InstallerType 'portable' -RetryPauseSeconds 0

        $r.Status | Should -Be 'failed'
        $r.Detail | Should -BeLike 'could not start winget elevated*consent prompt was refused*'
        Should -Invoke Invoke-ElevatedPowerShell -Times 1 -Exactly
    }
}

Describe 'Syncthing after its machine-wide install' {

    BeforeAll {
        # Windows has these cmdlets and a Linux pwsh does not, and Pester can only mock a command
        # that exists, so the gaps are filled with empty functions for the mocks to replace.
        if (-not (Get-Command Get-NetFirewallRule -ErrorAction SilentlyContinue)) {
            function global:Get-NetFirewallRule { [CmdletBinding()] param([string] $Name) }
        }
    }

    BeforeEach {
        $script:Link = Join-Path $TestDrive 'Links\syncthing.exe'
        $script:Startup = Join-Path $TestDrive 'Startup'
        New-Item -ItemType Directory -Path (Split-Path $script:Link) -Force | Out-Null
        Set-Content -LiteralPath $script:Link -Value 'stub'
        Remove-Item -LiteralPath $script:Startup -Recurse -Force -ErrorAction SilentlyContinue

        $global:Saved = [System.Collections.Generic.List[object]]::new()
        $global:Existing = $null
        Mock New-ShellShortcut {
            if ($global:Existing -and (Test-Path -LiteralPath $Path)) { return $global:Existing }
            $lnk = [PSCustomObject]@{ Path = $Path; TargetPath = ''; Arguments = ''; Description = ''; WindowStyle = 1 }
            $lnk | Add-Member -MemberType ScriptMethod -Name Save -Value { $global:Saved.Add($this); Set-Content -LiteralPath $this.Path -Value 'lnk' }
            return $lnk
        }
    }

    It 'puts a shortcut to the WinGet link in the Startup folder with the documented flags and --no-upgrade' {
        $r = Set-SyncthingStartupShortcut -LinkPath $script:Link -StartupDirectory $script:Startup

        $r.Status | Should -Be 'installed'
        $global:Saved.Count | Should -Be 1
        $global:Saved[0].Path        | Should -Be (Join-Path $script:Startup 'Syncthing.lnk')
        $global:Saved[0].TargetPath  | Should -Be $script:Link
        $global:Saved[0].Arguments   | Should -Be '--no-console --no-browser --no-upgrade'
    }

    It 'leaves a shortcut that already says the same thing alone' {
        New-Item -ItemType Directory -Path $script:Startup -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $script:Startup 'Syncthing.lnk') -Value 'lnk'
        $global:Existing = [PSCustomObject]@{ TargetPath = $script:Link; Arguments = '--no-console --no-browser --no-upgrade' }

        (Set-SyncthingStartupShortcut -LinkPath $script:Link -StartupDirectory $script:Startup).Status | Should -Be 'present'
        $global:Saved.Count | Should -Be 0
    }

    It 'fails by name and writes nothing when winget left no link to start' {
        Remove-Item -LiteralPath $script:Link -Force
        $r = Set-SyncthingStartupShortcut -LinkPath $script:Link -StartupDirectory $script:Startup

        $r.Status | Should -Be 'failed'
        $r.Detail | Should -BeLike "*$($script:Link)*"
        Should -Invoke New-ShellShortcut -Times 0 -Exactly
    }

    It 'asks for no elevation when all three firewall rules are already there' {
        Mock Get-NetFirewallRule { [PSCustomObject]@{ Name = $Name } }
        Mock Invoke-ElevatedPowerShell { throw 'must not be called' }

        (Set-SyncthingFirewallRule).Status | Should -Be 'present'
        Should -Invoke Invoke-ElevatedPowerShell -Times 0 -Exactly
    }

    It 'creates only the missing port rules, on Private and Domain, and believes the read-back rather than the child' {
        $global:Created = $false
        Mock Get-NetFirewallRule {
            if ($Name -eq 'InstallationHelper-Syncthing-TCP-22000' -or $global:Created) { return [PSCustomObject]@{ Name = $Name } }
        }
        Mock Invoke-ElevatedPowerShell { $global:Created = $true; [PSCustomObject]@{ ExitCode = 0; TimedOut = $false; StartError = '' } }

        $r = Set-SyncthingFirewallRule

        $r.Status | Should -Be 'installed'
        Should -Invoke Invoke-ElevatedPowerShell -Times 1 -Exactly -ParameterFilter {
            $Script -notmatch 'TCP-22000' -and
            $Script -match "InstallationHelper-Syncthing-UDP-22000'.*-Protocol UDP -LocalPort 22000 -Profile Private, Domain" -and
            $Script -match "InstallationHelper-Syncthing-UDP-21027'.*-Protocol UDP -LocalPort 21027 -Profile Private, Domain"
        }
    }

    It 'fails with the reason when the rules are still missing afterwards' {
        Mock Get-NetFirewallRule { }
        Mock Invoke-ElevatedPowerShell { [PSCustomObject]@{ ExitCode = -1; TimedOut = $false; StartError = 'The operation was canceled by the user.' } }

        $r = Set-SyncthingFirewallRule
        $r.Status | Should -Be 'failed'
        $r.Detail | Should -BeLike '*TCP 22000, UDP 22000, UDP 21027*canceled by the user*'
    }

    It 'reports a leftover BillStewart install with its uninstall command and removes nothing' {
        Mock Test-WingetPackageInstalled { $PackageId -eq 'BillStewart.SyncthingWindowsSetup' }
        $r = Get-SyncthingLegacyInstall -WingetPath 'winget'
        $r.Status | Should -Be 'skipped'
        $r.Detail | Should -BeLike "*winget uninstall --exact --id BillStewart.SyncthingWindowsSetup*"
    }

    It 'says nothing about BillStewart when it is not installed' {
        Mock Test-WingetPackageInstalled { $false }
        Get-SyncthingLegacyInstall -WingetPath 'winget' | Should -BeNullOrEmpty
    }
}

Describe 'Get-ChocolateyCachePath' {

    BeforeAll {
        $script:CacheProbe = Join-Path ([System.IO.Path]::GetTempPath()) ('chococfg-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:CacheProbe -Force | Out-Null
    }

    AfterAll {
        if (Test-Path -LiteralPath $script:CacheProbe) {
            Remove-Item -LiteralPath $script:CacheProbe -Recurse -Force
        }
    }

    It 'falls back to the temporary directory when there is no configuration file' {
        $missing = Join-Path $script:CacheProbe 'no-such.config'
        Get-ChocolateyCachePath -ConfigPath $missing |
            Should -Be (Join-Path ([System.IO.Path]::GetTempPath()) 'chocolatey')
    }

    It 'falls back to the temporary directory when cacheLocation is empty, which is the shipped default' {
        $path = Join-Path $script:CacheProbe 'empty.config'
        @'
<?xml version="1.0" encoding="utf-8"?>
<chocolateyConfig>
  <config>
    <add key="cacheLocation" value="" description="Cache location if not TEMP folder." />
  </config>
</chocolateyConfig>
'@ | Set-Content -LiteralPath $path -Encoding utf8

        Get-ChocolateyCachePath -ConfigPath $path |
            Should -Be (Join-Path ([System.IO.Path]::GetTempPath()) 'chocolatey')
    }

    It 'reads a configured cacheLocation and still joins chocolatey onto it' {
        # The key replaces $env:TEMP for the choco process rather than replacing the whole path, so
        # the payload still lands in a chocolatey folder underneath whatever is configured.
        #
        # A Windows drive letter on purpose: Chocolatey only ever runs on Windows, so this is the
        # only shape of absolute path the real config file holds. Join-Path resolves "D:" through a
        # PSDrive, which every real Windows machine has for its own drive letters and no Linux host
        # ever does, so this one assertion is skipped off Windows rather than rewritten around a
        # path shape production code never sees.
        if (-not $IsWindows) {
            Set-ItResult -Skipped -Because 'a Windows drive letter has no PSDrive on this platform, and Chocolatey never configures one here'
            return
        }
        $path = Join-Path $script:CacheProbe 'set.config'
        @'
<?xml version="1.0" encoding="utf-8"?>
<chocolateyConfig>
  <config>
    <add key="cacheLocation" value="D:\choco-cache" />
    <add key="commandExecutionTimeoutSeconds" value="2700" />
  </config>
</chocolateyConfig>
'@ | Set-Content -LiteralPath $path -Encoding utf8

        Get-ChocolateyCachePath -ConfigPath $path | Should -Be 'D:\choco-cache\chocolatey'
    }

    It 'falls back rather than throwing on a configuration file it cannot parse' {
        $path = Join-Path $script:CacheProbe 'broken.config'
        'this is not xml at all <<<' | Set-Content -LiteralPath $path -Encoding utf8

        Get-ChocolateyCachePath -ConfigPath $path |
            Should -Be (Join-Path ([System.IO.Path]::GetTempPath()) 'chocolatey')
    }
}

Describe 'Clear-WindowsPackageCache' {

    BeforeEach {
        $script:CacheRoot   = Join-Path ([System.IO.Path]::GetTempPath()) ('cacheclear-' + [guid]::NewGuid().ToString('N'))
        $script:ChocoCache  = Join-Path $script:CacheRoot 'chocolatey'
        $script:WingetCache = Join-Path $script:CacheRoot 'WinGet'

        New-Item -ItemType Directory -Path (Join-Path $script:ChocoCache 'virtualbox\7.2.14') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $script:WingetCache 'Foo.Bar.1.0') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $script:WingetCache 'cache\V2_M') -Force | Out-Null

        # Sized rather than empty, because the point of the step is the bytes.
        [System.IO.File]::WriteAllBytes((Join-Path $script:ChocoCache 'virtualbox\7.2.14\vb.exe'), (New-Object byte[] 3145728))
        [System.IO.File]::WriteAllBytes((Join-Path $script:WingetCache 'Foo.Bar.1.0\foo.exe'), (New-Object byte[] 1048576))
        [System.IO.File]::WriteAllBytes((Join-Path $script:WingetCache 'cache\V2_M\index.msix'), (New-Object byte[] 4096))
    }

    AfterEach {
        if (Test-Path -LiteralPath $script:CacheRoot) {
            Remove-Item -LiteralPath $script:CacheRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'removes the payload from both caches and reports the bytes per cache' {
        $r = Clear-WindowsPackageCache -ChocolateyCachePath $script:ChocoCache -WingetCachePath $script:WingetCache

        $r.Items | Should -Be 2
        $r.Bytes | Should -Be 4194304
        ($r.Locations | Where-Object { $_.Name -eq 'Chocolatey' }).Bytes | Should -Be 3145728
        ($r.Locations | Where-Object { $_.Name -eq 'winget' }).Bytes     | Should -Be 1048576
        Test-Path -LiteralPath (Join-Path $script:ChocoCache 'virtualbox')  | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $script:WingetCache 'Foo.Bar.1.0') | Should -BeFalse
    }

    It 'keeps the winget source index, because the verification phase queries winget after this runs' {
        Clear-WindowsPackageCache -ChocolateyCachePath $script:ChocoCache -WingetCachePath $script:WingetCache | Out-Null

        Test-Path -LiteralPath (Join-Path $script:WingetCache 'cache\V2_M\index.msix') | Should -BeTrue
    }

    It 'leaves both caches alone under -WhatIf and reports nothing removed' {
        $r = Clear-WindowsPackageCache -ChocolateyCachePath $script:ChocoCache -WingetCachePath $script:WingetCache -WhatIf

        $r.Items | Should -Be 0
        $r.Bytes | Should -Be 0
        Test-Path -LiteralPath (Join-Path $script:ChocoCache 'virtualbox\7.2.14\vb.exe') | Should -BeTrue
    }

    It 'says a cache holds nothing rather than failing when the directory does not exist' {
        $r = Clear-WindowsPackageCache `
            -ChocolateyCachePath (Join-Path $script:CacheRoot 'absent-choco') `
            -WingetCachePath     (Join-Path $script:CacheRoot 'absent-winget')

        $r.Items  | Should -Be 0
        $r.Failed | Should -HaveCount 0
        @($r.Locations | Where-Object { $_.Detail -eq 'nothing cached here' }) | Should -HaveCount 2
    }

    It 'names a file it could not remove and still returns, because the run must not die over a cache' {
        # A real cause rather than a mocked one: an installer another process still holds open cannot
        # be deleted, and the wizard has to carry on with the disk it already had. FileShare.None is
        # a mandatory lock on Windows, which is the platform this function ever runs on, and only an
        # advisory one on Linux, where the same open handle does not stop the delete this test means
        # to provoke, so it is skipped rather than asserting a rename of what it actually covers.
        if (-not $IsWindows) {
            Set-ItResult -Skipped -Because 'FileShare.None does not block a delete on this platform, so there is nothing here to fail'
            return
        }
        $held = Join-Path $script:ChocoCache 'locked\held.exe'
        New-Item -ItemType Directory -Path (Split-Path $held -Parent) -Force | Out-Null
        [System.IO.File]::WriteAllBytes($held, (New-Object byte[] 1024))
        $stream = [System.IO.File]::Open($held, 'Open', 'Read', 'None')
        try {
            $r = Clear-WindowsPackageCache -ChocolateyCachePath $script:ChocoCache -WingetCachePath $script:WingetCache

            $r.Failed | Should -HaveCount 1
            $r.Failed[0].Path   | Should -BeLike '*locked*'
            $r.Failed[0].Detail | Should -Not -BeNullOrEmpty
            # The rest of the cache still went, which is the whole point of not stopping.
            Test-Path -LiteralPath (Join-Path $script:ChocoCache 'virtualbox') | Should -BeFalse
        } finally {
            $stream.Dispose()
        }
    }

    It 'reports free space on the measured volume as a real number' {
        $r = Clear-WindowsPackageCache `
            -ChocolateyCachePath $script:ChocoCache -WingetCachePath $script:WingetCache `
            -MeasuredPath ([System.IO.Path]::GetTempPath())

        $r.FreeBefore | Should -BeGreaterThan 0
        $r.FreeAfter  | Should -BeGreaterThan 0
    }
}

Describe 'Get-FreeDiskByte' {

    It 'answers a positive number for the temporary directory' {
        Get-FreeDiskByte -Path ([System.IO.Path]::GetTempPath()) | Should -BeGreaterThan 0
    }

    It 'answers -1 rather than throwing when the path is not a volume at all' {
        # -1 is the "could not measure" answer, and a caller has to be able to tell it apart from a
        # full disk. A UNC path is never a volume root, so DriveInfo refuses it on every machine.
        Get-FreeDiskByte -Path '\\no-such-host\no-such-share' | Should -Be -1
    }

    It 'answers -1 for a drive letter that is not mounted, which reports nothing instead of throwing' {
        # The letter is found at run time rather than written down, because any letter can be in use
        # on somebody's machine and a test that assumes otherwise fails for the wrong reason. An
        # unmounted drive is the case that made the null check necessary: DriveInfo constructs
        # happily, and AvailableFreeSpace then hands back nothing at all.
        $unmounted = 90..67 | ForEach-Object { [char]$_ } | Where-Object { -not (Test-Path -LiteralPath ($_ + ':\')) } | Select-Object -First 1
        $unmounted | Should -Not -BeNullOrEmpty -Because 'a machine with all 24 drive letters mounted cannot prove this'

        Get-FreeDiskByte -Path ($unmounted + ':\nowhere') | Should -Be -1
    }
}

Describe 'Get-TemurinMajor' {

    It 'extracts the major version out of an SDKMAN identifier' {
        Get-TemurinMajor -SdkmanId '21.0.11-tem' | Should -Be '21'
    }

    It 'extracts a two-digit major version' {
        Get-TemurinMajor -SdkmanId '25.0.3-tem' | Should -Be '25'
    }

    # The reader refuses to hand out a value it could not resolve, so this shape can no longer
    # arrive from the pinned values. It is still asserted, because this function is also the thing
    # that decides what a malformed pin does, and answering "major 21" to anything unrecognisable
    # would install the wrong JDK silently.
    It 'throws on a pin that is still an unresolved {{ ref }}' {
        { Get-TemurinMajor -SdkmanId '{{ default_java }}' } |
            Should -Throw -ExpectedMessage "*'{{ default_java }}'*"
    }

    # The error must name the value that failed, so whoever reads it can go straight to the
    # offending pin instead of guessing which of the four broke.
    It 'names the malformed value in the thrown error' {
        { Get-TemurinMajor -SdkmanId 'tem-21.0.11' } |
            Should -Throw -ExpectedMessage "*'tem-21.0.11'*"
    }

    It 'throws on an identifier with no major version at all' {
        { Get-TemurinMajor -SdkmanId 'not-a-version' } |
            Should -Throw -ExpectedMessage "*'not-a-version'*"
    }

    # ValidateNotNullOrEmpty rejects this before the function body runs, which is the
    # "missing pin" shape: a name present in the pins table with an empty value.
    It 'throws on an empty identifier' {
        { Get-TemurinMajor -SdkmanId '' } | Should -Throw
    }
}

Describe 'Install-NpmToolPackage removes the package a tool replaces' {

    # A global npm function rather than a Pester mock of the executable, because a function wins over
    # an application of the same name for `& npm`, which is exactly how the code under test calls it,
    # and because the function can set LASTEXITCODE the way the real npm does. The call log is the
    # observable: it says which npm verbs ran and in what order.
    BeforeAll {
        . (Join-Path $script:RepoRoot 'setup\windows\WindowsNpmTools.ps1')

        $script:SavedUserProfile = $env:USERPROFILE
        $env:USERPROFILE = $TestDrive

        function global:npm {
            $global:NpmStubCalls.Add(($args -join ' '))
            $verb = $args[0]
            if ($verb -eq 'list') {
                $global:LASTEXITCODE = 1
                return ''
            }
            if ($verb -eq 'uninstall') {
                $global:LASTEXITCODE = $global:NpmStubUninstallExit
                return $global:NpmStubUninstallOutput
            }
            if ($global:NpmStubInstallExits.ContainsKey($args[2])) {
                $global:LASTEXITCODE = $global:NpmStubInstallExits[$args[2]]
                if ($global:LASTEXITCODE -ne 0) { return 'npm error code E404' }
                return 'added 3 packages in 6s'
            }
            $global:LASTEXITCODE = 0
            return 'added 3 packages in 6s'
        }
    }

    AfterAll {
        Remove-Item -LiteralPath Function:\global:npm -ErrorAction SilentlyContinue
        $env:USERPROFILE = $script:SavedUserProfile
    }

    BeforeEach {
        $global:NpmStubCalls = [System.Collections.Generic.List[string]]::new()
        $global:NpmStubUninstallExit = 0
        $global:NpmStubUninstallOutput = 'removed 3 packages in 1s'
        $global:NpmStubInstallExits = @{}
        Mock Start-Sleep { }
        Mock Write-Host { }
    }

    It 'uninstalls the replaced package before installing, and says so' {
        $result = Install-NpmToolPackage -PackageName '@opencode/cli' -DisplayName 'OpenCode' -ReplacesPackage 'opencode-ai'

        $result.Status | Should -Be 'installed'
        $result.Detail | Should -Be 'removed opencode-ai, which it replaces'
        $global:NpmStubCalls[1] | Should -Be 'uninstall -g opencode-ai'
        $global:NpmStubCalls[2] | Should -Be 'install -g @opencode/cli'
    }

    It 'reports nothing replaced when the old package was not there' {
        $global:NpmStubUninstallOutput = 'up to date in 932ms'

        $result = Install-NpmToolPackage -PackageName '@opencode/cli' -DisplayName 'OpenCode' -ReplacesPackage 'opencode-ai'

        $result.Status | Should -Be 'installed'
        $result.Detail | Should -BeNullOrEmpty
    }

    It 'fails without attempting the install when the uninstall fails' {
        $global:NpmStubUninstallExit = 1
        $global:NpmStubUninstallOutput = 'npm error code EPERM'

        $result = Install-NpmToolPackage -PackageName '@opencode/cli' -DisplayName 'OpenCode' -ReplacesPackage 'opencode-ai'

        $result.Status | Should -Be 'failed'
        $result.Detail | Should -Match 'npm uninstall -g opencode-ai exited 1'
        @($global:NpmStubCalls | Where-Object { $_ -like 'install *' }).Count | Should -Be 0
    }

    It 'runs no uninstall for a tool that replaces nothing' {
        $result = Install-NpmToolPackage -PackageName '@fission-ai/openspec' -DisplayName 'OpenSpec'

        $result.Status | Should -Be 'installed'
        @($global:NpmStubCalls | Where-Object { $_ -like 'uninstall *' }).Count | Should -Be 0
    }

    # Until 2026-10-10 the replaced package was removed and nothing put it back, so a failed
    # @opencode/cli install left no OpenCode CLI at all on a machine that had a working one.
    It 'installs the replaced package again when the new one fails, and says the old one is still there' {
        $global:NpmStubInstallExits = @{ '@opencode/cli' = 1 }

        $result = Install-NpmToolPackage -PackageName '@opencode/cli' -DisplayName 'OpenCode' -ReplacesPackage 'opencode-ai'

        $result.Status | Should -Be 'failed'
        $result.Detail | Should -Match 'opencode-ai had been removed to make room and was installed again'
        $result.Detail | Should -Match 'the earlier OpenCode is still on this machine'
        $global:NpmStubCalls[-1] | Should -Be 'install -g opencode-ai'
        @($global:NpmStubCalls | Where-Object { $_ -eq 'install -g @opencode/cli' }).Count | Should -Be 4 -Because 'the first attempt and the three retries of the shared rule'
    }

    It 'retries a failing install under the shared rule with no refresh step, and names and counts the failure' {
        $global:NpmStubInstallExits = @{ '@fission-ai/openspec' = 1 }

        $result = Install-NpmToolPackage -PackageName '@fission-ai/openspec' -DisplayName 'OpenSpec'

        $result.Status | Should -Be 'failed'
        $result.Package | Should -Be '@fission-ai/openspec'
        $result.Detail | Should -Be 'npm exited 1. npm error code E404 (attempt 4 of 4; attempts 1, 2 and 3 said npm exited 1. npm error code E404)'
        @($global:NpmStubCalls | Where-Object { $_ -eq 'install -g @fission-ai/openspec' }).Count | Should -Be 4
        @($global:NpmStubCalls | Where-Object { $_ -like 'cache*' }).Count | Should -Be 0 -Because 'npm keeps no package list to refresh'
        Should -Invoke Start-Sleep -Times 3 -Exactly -ParameterFilter { $Seconds -eq 20 }
    }

    It 'says there is no CLI left when the replaced package cannot be installed again either' {
        $global:NpmStubInstallExits = @{ '@opencode/cli' = 1; 'opencode-ai' = 1 }

        $result = Install-NpmToolPackage -PackageName '@opencode/cli' -DisplayName 'OpenCode' -ReplacesPackage 'opencode-ai'

        $result.Status | Should -Be 'failed'
        $result.Detail | Should -Match 'could not be installed again either'
        $result.Detail | Should -Match 'there is no OpenCode on this machine now'
    }

    It 'installs nothing back when the replaced package was not there to begin with' {
        $global:NpmStubUninstallOutput = 'up to date in 932ms'
        $global:NpmStubInstallExits = @{ '@opencode/cli' = 1 }

        $result = Install-NpmToolPackage -PackageName '@opencode/cli' -DisplayName 'OpenCode' -ReplacesPackage 'opencode-ai'

        $result.Status | Should -Be 'failed'
        $result.Detail | Should -Not -Match 'installed again'
        $global:NpmStubCalls | Should -Not -Contain 'install -g opencode-ai'
    }

    It 'passes the replaced package from the table through Invoke-WindowsNpmToolInstall' {
        Mock Test-NpmAvailable { $true }

        $summary = Invoke-WindowsNpmToolInstall -Toggles @{ opencode = $true } -OnlyKeys @('opencode')

        @($summary.Installed).Count | Should -Be 1
        $global:NpmStubCalls | Should -Contain 'uninstall -g opencode-ai'
        $global:NpmStubCalls | Should -Contain 'install -g @opencode/cli'
    }
}

Describe 'Install-AnsibleInWsl in setup.ps1 retries each step under the shared rule' {

    # Lifted out of setup.ps1's syntax tree for the reason the Install-ConsoleGuiTools tests give.
    # wsl is a global function, which `wsl ...` resolves before the application, recording each call
    # and failing the steps a test names.
    BeforeAll {
        $setupScript = Join-Path $script:RepoRoot 'setup\setup.ps1'
        $parseErrors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($setupScript, [ref]$null, [ref]$parseErrors)
        if ($parseErrors) { throw "setup.ps1 does not parse: $($parseErrors[0].Message)" }
        $wanted = @('Install-AnsibleInWsl', 'New-WslResult', 'Write-Status', 'Write-Hint')
        $definitions = @($ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $wanted -contains $node.Name
        }, $true))
        if ($definitions.Count -ne $wanted.Count) {
            throw "Expected $($wanted.Count) function definitions in setup.ps1 and found $($definitions.Count)."
        }
        foreach ($definition in $definitions) {
            . ([scriptblock]::Create($definition.Extent.Text))
        }

        function global:Get-WslDistributionName { 'Ubuntu' }
        function global:wsl {
            # PowerShell consumes the `--` of a function call, so the command starts after the four
            # arguments that name the distribution and the user.
            $command = (@($args | Select-Object -Skip 4) | ForEach-Object { "$_" }) -join ' '
            $global:WslCalls.Add($command)
            if ($command -eq 'cat /etc/os-release') { $global:LASTEXITCODE = 0; return 'ID=ubuntu' }
            if ($command -eq 'which ansible-playbook') {
                $global:LASTEXITCODE = $(if ($global:WslAnsibleThere) { 0 } else { 1 })
                return
            }
            if ($global:WslFailuresLeft.ContainsKey($command) -and $global:WslFailuresLeft[$command] -gt 0) {
                $global:WslFailuresLeft[$command]--
                $global:LASTEXITCODE = 100
                return 'E: Failed to fetch'
            }
            if ($command -eq 'apt-get install -y ansible') { $global:WslAnsibleThere = $true }
            $global:LASTEXITCODE = 0
        }
    }

    AfterAll {
        Remove-Item -LiteralPath Function:\global:wsl, Function:\global:Get-WslDistributionName -ErrorAction SilentlyContinue
    }

    BeforeEach {
        $global:WslCalls = [System.Collections.Generic.List[string]]::new()
        $global:WslFailuresLeft = @{}
        $global:WslAnsibleThere = $false
        Mock Get-Command { [PSCustomObject]@{ Source = 'wsl.exe' } } -ParameterFilter { $Name -eq 'wsl' }
        Mock Start-Sleep { }
        Mock Write-Host { }
    }

    It 'runs every step once and refreshes nothing extra when each first attempt works' {
        $r = Install-AnsibleInWsl

        @($r.Installed).Count | Should -Be 1
        @($global:WslCalls | Where-Object { $_ -eq 'apt-get update -q' }).Count | Should -Be 1 -Because 'only the first step itself updates the package list'
    }

    It 'refreshes the package list before retrying a failed install step' {
        $global:WslFailuresLeft = @{ 'apt-get install -y ansible' = 1 }

        $r = Install-AnsibleInWsl

        @($r.Installed).Count | Should -Be 1
        $at = $global:WslCalls.IndexOf('apt-get install -y ansible')
        @($global:WslCalls)[$at..($at + 2)] | Should -Be @('apt-get install -y ansible', 'apt-get update -q', 'apt-get install -y ansible')
    }

    It 'names the step that failed every attempt, with its attempts, and installs nothing after it' {
        $global:WslFailuresLeft = @{ 'apt-get install -y software-properties-common' = 99 }

        $r = Install-AnsibleInWsl

        @($r.Failed).Count | Should -Be 1
        $r.Failed[0].Detail | Should -BeLike "'apt-get install -y software-properties-common' exited 100 (attempt 4 of 4; attempts 1, 2 and 3 said*), inside 'Ubuntu', so Ansible is not installed in there*"
        @($global:WslCalls | Where-Object { $_ -eq 'apt-get install -y software-properties-common' }).Count | Should -Be 4
        $global:WslCalls | Should -Not -Contain 'apt-get install -y ansible'
    }
}

Describe 'Install-ConsoleGuiTools in setup.ps1' {

    # Until 2026-10-10 a failed install of the picker module threw, and setup.ps1 runs with
    # $ErrorActionPreference = 'Stop', so the wizard ended before it had installed anything although
    # only the customise screen needs the module. It now returns whether the module is available, and
    # Invoke-Main falls back to the default software list when it is not.
    #
    # setup.ps1 runs Invoke-Main when it is loaded, so it cannot be dot-sourced the way the module
    # files are. The functions under test are lifted out of its syntax tree instead, which still tests
    # the code that ships rather than a copy of it.
    BeforeAll {
        $setupScript = Join-Path $script:RepoRoot 'setup\setup.ps1'
        $parseErrors = $null
        $script:SetupAst = [System.Management.Automation.Language.Parser]::ParseFile($setupScript, [ref]$null, [ref]$parseErrors)
        if ($parseErrors) { throw "setup.ps1 does not parse: $($parseErrors[0].Message)" }

        $wanted = @('Install-ConsoleGuiTools', 'Write-Status', 'Write-Hint')
        $definitions = @($script:SetupAst.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $wanted -contains $node.Name
        }, $true))
        if ($definitions.Count -ne $wanted.Count) {
            throw "Expected $($wanted.Count) function definitions in setup.ps1 and found $($definitions.Count)."
        }
        foreach ($definition in $definitions) {
            . ([scriptblock]::Create($definition.Extent.Text))
        }

        # A function shadows the cmdlet of the same name, so every test below mocks this one and none
        # of them can reach the PowerShell Gallery, whether or not PowerShellGet is installed here.
        function Install-Module {
            param([string] $Name, [string] $Scope, [switch] $Force, [switch] $AcceptLicense)
        }
    }

    It 'returns true without installing anything when the module is already there' {
        Mock Get-Module { [PSCustomObject]@{ Name = 'Microsoft.PowerShell.ConsoleGuiTools' } }
        Mock Install-Module { }

        Install-ConsoleGuiTools | Should -BeTrue
        Should -Invoke Install-Module -Times 0 -Exactly
    }

    It 'returns true after installing a module that was missing, without waiting' {
        Mock Get-Module { }
        Mock Install-Module { }
        Mock Write-Host { }
        Mock Start-Sleep { }

        Install-ConsoleGuiTools | Should -BeTrue
        Should -Invoke Install-Module -Times 1 -Exactly
        Should -Invoke Start-Sleep -Times 0 -Exactly
    }

    It 'waits and tries the gallery again after a failed install' {
        Mock Get-Module { }
        $global:GalleryFailuresLeft = 1
        Mock Install-Module { if ($global:GalleryFailuresLeft-- -gt 0) { throw 'Unable to resolve package source' } }
        Mock Write-Host { }
        Mock Start-Sleep { }

        Install-ConsoleGuiTools | Should -BeTrue
        Should -Invoke Install-Module -Times 2 -Exactly
        Should -Invoke Start-Sleep -Times 1 -Exactly -ParameterFilter { $Seconds -eq 20 }
    }

    It 'returns false instead of throwing when every attempt fails, and says what the run does instead' {
        Mock Get-Module { }
        Mock Install-Module { throw 'No match was found for the specified search criteria and module name' }
        Mock Write-Host { }
        Mock Start-Sleep { }

        { Install-ConsoleGuiTools } | Should -Not -Throw
        Should -Invoke Install-Module -Times 4 -Exactly
        Install-ConsoleGuiTools | Should -BeFalse
        Should -Invoke Write-Host -ParameterFilter { "$Object" -like '*Could not install Microsoft.PowerShell.ConsoleGuiTools*No match was found*attempt 4 of 4*' }
        Should -Invoke Write-Host -ParameterFilter { "$Object" -like '*default software list*-NonInteractive*' }
    }

    It 'makes Invoke-Main ask for a software selection only when the picker module is available' {
        $main = $script:SetupAst.Find({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Invoke-Main'
        }, $true)
        $main | Should -Not -BeNullOrEmpty

        $selectionCalls = @($main.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.CommandAst] -and $node.GetCommandName() -eq 'Get-SoftwareSelection'
        }, $true))
        $selectionCalls.Count | Should -Be 1

        $guard = $selectionCalls[0].Parent
        while ($guard -and -not ($guard -is [System.Management.Automation.Language.IfStatementAst])) {
            $guard = $guard.Parent
        }
        $guard | Should -Not -BeNullOrEmpty -Because 'the selection must sit inside an if that asks whether the picker module is available'
        $guard.Clauses[0].Item1.Extent.Text | Should -Match 'Install-ConsoleGuiTools'
    }
}

Describe 'Assert-NotAdmin in setup.ps1' {

    # The Windows wizard refuses an elevated run unless -AllowAdministrator is passed, and until
    # 2026-10-11 nothing had ever executed that refusal. The elevation question is asked through
    # Test-IsAdministrator, which WindowsSoftware.ps1 defines and the top-level BeforeAll has already
    # loaded, so it can be mocked here. The setup.ps1 functions are lifted out of the syntax tree for
    # the same reason as the Describe above: setup.ps1 runs Invoke-Main when it is loaded.
    BeforeAll {
        $setupScript = Join-Path $script:RepoRoot 'setup\setup.ps1'
        $parseErrors = $null
        $script:GuardAst = [System.Management.Automation.Language.Parser]::ParseFile($setupScript, [ref]$null, [ref]$parseErrors)
        if ($parseErrors) { throw "setup.ps1 does not parse: $($parseErrors[0].Message)" }

        $wanted = @('Assert-NotAdmin', 'Write-Err', 'Write-Hint')
        $definitions = @($script:GuardAst.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $wanted -contains $node.Name
        }, $true))
        if ($definitions.Count -ne $wanted.Count) {
            throw "Expected $($wanted.Count) function definitions in setup.ps1 and found $($definitions.Count)."
        }
        foreach ($definition in $definitions) {
            . ([scriptblock]::Create($definition.Extent.Text))
        }

        $script:RefusalText = 'Do not run this script as Administrator. Open a normal PowerShell 7 window and run it there. It asks for administrator rights itself, one Windows prompt per step that needs them. Pass -AllowAdministrator only on a throwaway machine such as a CI runner.'
    }

    It 'refuses an elevated run with the message that says what to do instead' {
        Mock Test-IsAdministrator { $true }
        Mock Write-Host { }
        $AllowAdministrator = $false

        { Assert-NotAdmin } | Should -Throw -ExpectedMessage $script:RefusalText
        Should -Invoke Write-Host -ParameterFilter { "$Object" -eq "  [!] $($script:RefusalText)" }
    }

    It 'lets an elevated run through when -AllowAdministrator is passed, and says what that costs' {
        Mock Test-IsAdministrator { $true }
        Mock Write-Host { }
        $AllowAdministrator = $true

        { Assert-NotAdmin } | Should -Not -Throw
        Should -Invoke Write-Host -ParameterFilter { "$Object" -like '*-AllowAdministrator was passed*' }
    }

    It 'says nothing and lets a normal run through' {
        Mock Test-IsAdministrator { $false }
        Mock Write-Host { }
        $AllowAdministrator = $false

        { Assert-NotAdmin } | Should -Not -Throw
        Should -Invoke Write-Host -Times 0 -Exactly
    }

    It 'is the first thing Invoke-Main does, before anything can change the machine' {
        $main = $script:GuardAst.Find({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Invoke-Main'
        }, $true)
        $main | Should -Not -BeNullOrEmpty

        $firstStatement = $main.Body.EndBlock.Statements[0]
        $firstStatement.Extent.Text | Should -Be 'Assert-NotAdmin'
    }
}

Describe 'Test-IsAdministrator is the only elevation check' {

    # setup.ps1, WindowsSettings.ps1 and WindowsSoftware.ps1 each asked the WindowsPrincipal question
    # on their own until 2026-10-11, which is defect class 2 in docs/regression_ledger.md waiting to happen. Every
    # IsInRole call and every WindowsBuiltInRole Administrator reference under setup/ must sit inside
    # the one Test-IsAdministrator in WindowsSoftware.ps1.
    It 'finds no elevation check under setup/ outside Test-IsAdministrator' {
        $owner = Join-Path $script:RepoRoot 'setup\windows\WindowsSoftware.ps1'
        $ownerAst = [System.Management.Automation.Language.Parser]::ParseFile($owner, [ref]$null, [ref]$null)
        $definitions = @($ownerAst.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Test-IsAdministrator'
        }, $true))
        $definitions.Count | Should -Be 1 -Because 'WindowsSoftware.ps1 must define Test-IsAdministrator exactly once'
        $extent = $definitions[0].Extent

        $files = @(Get-ChildItem -LiteralPath (Join-Path $script:RepoRoot 'setup') -Recurse -File -Include '*.ps1', '*.psm1')
        $files.Count | Should -BeGreaterThan 0 -Because 'a scan of no files proves nothing'

        $stray = [System.Collections.Generic.List[string]]::new()
        foreach ($file in $files) {
            $text = [System.IO.File]::ReadAllText($file.FullName)
            foreach ($match in [regex]::Matches($text, 'IsInRole\s*\(|WindowsBuiltInRole\]::Administrator')) {
                $inside = $file.FullName -eq $owner -and
                    $match.Index -ge $extent.StartOffset -and $match.Index -lt $extent.EndOffset
                if (-not $inside) {
                    $line = $text.Substring(0, $match.Index).Split("`n").Count
                    $stray.Add("$($file.FullName):$line $($match.Value)")
                }
            }
        }
        $stray | Should -BeNullOrEmpty -Because 'a second elevation check can disagree with Test-IsAdministrator, so call it instead'
    }
}

Describe 'Invoke-ElevatedPowerShell is the only route to elevation' {

    # The Chocolatey batch and the optional features step each carried their own copy of the RunAs
    # start until 2026-10-11, which is defect class 2 in docs/regression_ledger.md: three implementations of one
    # elevation, and three places a refusal or a deadline could be handled differently. Every RunAs
    # under setup/ must sit inside the one Invoke-ElevatedPowerShell in WindowsSoftware.ps1. Comments
    # are not code and are not counted.
    It 'finds no RunAs under setup/ outside Invoke-ElevatedPowerShell' {
        $owner = Join-Path $script:RepoRoot 'setup\windows\WindowsSoftware.ps1'
        $ownerAst = [System.Management.Automation.Language.Parser]::ParseFile($owner, [ref]$null, [ref]$null)
        $definitions = @($ownerAst.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Invoke-ElevatedPowerShell'
        }, $true))
        $definitions.Count | Should -Be 1 -Because 'WindowsSoftware.ps1 must define Invoke-ElevatedPowerShell exactly once'
        $extent = $definitions[0].Extent

        $files = @(Get-ChildItem -LiteralPath (Join-Path $script:RepoRoot 'setup') -Recurse -File -Include '*.ps1', '*.psm1')
        $files.Count | Should -BeGreaterThan 0 -Because 'a scan of no files proves nothing'

        $inOwner = 0
        $stray = [System.Collections.Generic.List[string]]::new()
        foreach ($file in $files) {
            $tokens = $null
            $null = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$null)
            foreach ($token in $tokens) {
                if ($token.Kind -eq [System.Management.Automation.Language.TokenKind]::Comment) { continue }
                if ($token.Text -notmatch 'RunAs') { continue }
                $inside = $file.FullName -eq $owner -and
                    $token.Extent.StartOffset -ge $extent.StartOffset -and $token.Extent.EndOffset -le $extent.EndOffset
                if ($inside) { $inOwner++ } else { $stray.Add("$($file.FullName):$($token.Extent.StartLineNumber) $($token.Text)") }
            }
        }
        $inOwner | Should -BeGreaterThan 0 -Because 'a check that cannot find the one RunAs it allows would pass on anything'
        $stray | Should -BeNullOrEmpty -Because 'a second RunAs is a second way to handle a refusal or a deadline, so call Invoke-ElevatedPowerShell instead'
    }
}

Describe 'Get-WindowsInstallationType is the only edition check' {

    # WindowsSoftware.ps1 and WindowsSettings.ps1 each read the InstallationType registry value in a
    # function of their own until 2026-10-11, so whether a client-only package and a client-only
    # optional feature are skipped was decided twice. Every read of that value under setup/, and
    # every other way of asking client versus server, must sit inside the one
    # Get-WindowsInstallationType in WindowsSoftware.ps1.
    It 'finds no edition check under setup/ outside Get-WindowsInstallationType' {
        $owner = Join-Path $script:RepoRoot 'setup\windows\WindowsSoftware.ps1'
        $ownerAst = [System.Management.Automation.Language.Parser]::ParseFile($owner, [ref]$null, [ref]$null)
        $definitions = @($ownerAst.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Get-WindowsInstallationType'
        }, $true))
        $definitions.Count | Should -Be 1 -Because 'WindowsSoftware.ps1 must define Get-WindowsInstallationType exactly once'
        $extent = $definitions[0].Extent

        $files = @(Get-ChildItem -LiteralPath (Join-Path $script:RepoRoot 'setup') -Recurse -File -Include '*.ps1', '*.psm1')
        $files.Count | Should -BeGreaterThan 0 -Because 'a scan of no files proves nothing'

        $stray = [System.Collections.Generic.List[string]]::new()
        foreach ($file in $files) {
            $text = [System.IO.File]::ReadAllText($file.FullName)
            foreach ($match in [regex]::Matches($text, "['""]InstallationType['""]|-Name\s+InstallationType\b|(?<!Get-)WindowsInstallationType|ProductType|OperatingSystemSKU|Win32_OperatingSystem|function\s+Get-WindowsInstallationType")) {
                $inside = $file.FullName -eq $owner -and
                    $match.Index -ge $extent.StartOffset -and $match.Index -lt $extent.EndOffset
                if (-not $inside) {
                    $line = $text.Substring(0, $match.Index).Split("`n").Count
                    $stray.Add("$($file.FullName):$line $($match.Value)")
                }
            }
        }
        $stray | Should -BeNullOrEmpty -Because 'a second edition check can disagree with Get-WindowsInstallationType, so call it instead'
    }
}

Describe 'Chocolatey bootstrap' -Tag 'Slow', 'Network' {

    # The one install path a Windows container can genuinely exercise, because Chocolatey is
    # only PowerShell and NuGet. Tagged so a quick run can skip it.
    It 'is absent to begin with, which is what makes the bootstrap worth testing' {
        Get-Command choco -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
    }

    It 'installs a small package end to end' {
        $result = Install-ChocolateyPackageBatch -PackageId @('7zip.install')
        $result.Status | Should -Be 'installed'
        Get-Command choco -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }
}

Describe 'Install-PipxWithPip' {

    # Mocks rather than a real pip: the code under test decides what to run and what to believe, and a
    # real pip would make this a network test of PyPI instead.
    BeforeEach {
        $script:PipxProof = Join-Path $TestDrive 'Python\Python3*\Scripts\pipx.exe'
        $script:PipxExe   = Join-Path $TestDrive 'Python\Python311\Scripts\pipx.exe'
        Remove-Item -LiteralPath (Join-Path $TestDrive 'Python') -Recurse -Force -ErrorAction SilentlyContinue
        Mock Update-ProcessPath { }
        Mock Get-Command { [PSCustomObject]@{ Source = 'py' } } -ParameterFilter { $Name -contains 'py' }
        Mock Start-Sleep { }
        Mock Write-Host { }
        $global:PipCalls = [System.Collections.Generic.List[string]]::new()
        $global:PipFailuresLeft = 0
    }

    It 'is one of the custom installs' {
        Get-WindowsCustomInstallKey | Should -Contain 'pipx'
    }

    # Windows only, because the proof table joins paths under C:\, which no other platform has a drive for.
    It 'has a proof entry the verification reads' -Skip:(-not $IsWindows) {
        (Get-WindowsCustomInstallProof -Versions @{ unused = '' }).Contains('pipx') | Should -BeTrue
    }

    It 'reports present and runs nothing when pipx is already there' {
        New-Item -ItemType File -Path $script:PipxExe -Force | Out-Null
        Mock Invoke-ManagedTool { throw 'nothing should run' }

        $r = Install-PipxWithPip -ProofPath $script:PipxProof

        $r.Status | Should -Be 'present'
        Should -Invoke Invoke-ManagedTool -Times 0
    }

    It 'fails, naming install_python, when the Python launcher is missing' {
        Mock Get-Command { $null } -ParameterFilter { $Name -contains 'py' }
        Mock Invoke-ManagedTool { throw 'nothing should run' }

        $r = Install-PipxWithPip -ProofPath $script:PipxProof

        $r.Status | Should -Be 'failed'
        $r.Detail | Should -BeLike '*install_python*'
        Should -Invoke Invoke-ManagedTool -Times 0
    }

    It 'installs with pip into the user site, then runs ensurepath, then proves the file exists' {
        Mock Invoke-ManagedTool {
            if ($ArgumentList -contains 'ensurepath') { New-Item -ItemType File -Path $script:PipxExe -Force | Out-Null }
            [PSCustomObject]@{ Key = 'pipx'; Package = "py $($ArgumentList -join ' ')"; Status = 'installed'; Detail = '' }
        }

        $r = Install-PipxWithPip -ProofPath $script:PipxProof

        $r.Status | Should -Be 'installed'
        Should -Invoke Invoke-ManagedTool -Times 1 -Exactly -ParameterFilter { $FilePath -eq 'py' -and ($ArgumentList -join ' ') -eq '-m pip install --user pipx' }
        Should -Invoke Invoke-ManagedTool -Times 1 -Exactly -ParameterFilter { $FilePath -eq 'py' -and ($ArgumentList -join ' ') -eq '-m pipx ensurepath' }
    }

    It 'names a pip install that fails every one of its four attempts, and does not run ensurepath' {
        Mock Invoke-ManagedTool { [PSCustomObject]@{ Key = 'pipx'; Package = 'py -m pip install --user pipx'; Status = 'failed'; Detail = 'exit 1.' } }

        $r = Install-PipxWithPip -ProofPath $script:PipxProof

        $r.Status | Should -Be 'failed'
        $r.Package | Should -Be 'py -m pip install --user pipx'
        $r.Detail | Should -Be 'exit 1. (attempt 4 of 4; attempts 1, 2 and 3 said exit 1.)'
        Should -Invoke Invoke-ManagedTool -Times 4 -Exactly -ParameterFilter { $ArgumentList -contains 'install' }
        Should -Invoke Invoke-ManagedTool -Times 0 -Exactly -ParameterFilter { $ArgumentList -contains 'ensurepath' }
        Should -Invoke Start-Sleep -Times 3 -Exactly -ParameterFilter { $Seconds -eq 20 }
    }

    # pip 26.2 caches the index answers by their Cache-Control header and refreshes one package's with
    # --refresh-package. The bundled pip of Python 3.11.9 is 24.0, which revalidates every index
    # request and ignores a PIP_ variable for an option it does not have, so the variable is the one
    # refresh both of them accept.
    It 'asks pip to refresh the pipx index answer only on a retry, and waits first' {
        Mock Invoke-ManagedTool {
            if ($ArgumentList -contains 'ensurepath') {
                New-Item -ItemType File -Path $script:PipxExe -Force | Out-Null
                return [PSCustomObject]@{ Key = 'pipx'; Package = 'py -m pipx ensurepath'; Status = 'installed'; Detail = '' }
            }
            $global:PipCalls.Add($(if ($Environment.ContainsKey('PIP_REFRESH_PACKAGE')) { "install refresh=$($Environment['PIP_REFRESH_PACKAGE'])" } else { 'install' }))
            if ($global:PipFailuresLeft -gt 0) {
                $global:PipFailuresLeft--
                return [PSCustomObject]@{ Key = 'pipx'; Package = 'py -m pip install --user pipx'; Status = 'failed'; Detail = 'exit 1. Connection reset by peer' }
            }
            [PSCustomObject]@{ Key = 'pipx'; Package = 'py -m pip install --user pipx'; Status = 'installed'; Detail = '' }
        }
        $global:PipFailuresLeft = 1

        $r = Install-PipxWithPip -ProofPath $script:PipxProof

        $r.Status | Should -Be 'installed'
        @($global:PipCalls) | Should -Be @('install', 'install refresh=pipx')
        Should -Invoke Start-Sleep -Times 1 -Exactly -ParameterFilter { $Seconds -eq 20 }
    }

    It 'neither waits nor refreshes when the first pip install works' {
        Mock Invoke-ManagedTool {
            if ($ArgumentList -contains 'ensurepath') { New-Item -ItemType File -Path $script:PipxExe -Force | Out-Null }
            else { $global:PipCalls.Add($(if ($Environment.ContainsKey('PIP_REFRESH_PACKAGE')) { 'install refresh' } else { 'install' })) }
            [PSCustomObject]@{ Key = 'pipx'; Package = 'py'; Status = 'installed'; Detail = '' }
        }

        $r = Install-PipxWithPip -ProofPath $script:PipxProof

        $r.Status | Should -Be 'installed'
        @($global:PipCalls) | Should -Be @('install')
        Should -Invoke Start-Sleep -Times 0 -Exactly
    }

    It 'fails when pip and ensurepath both succeed and nothing is left behind' {
        Mock Invoke-ManagedTool { [PSCustomObject]@{ Key = 'pipx'; Package = 'py'; Status = 'installed'; Detail = '' } }

        $r = Install-PipxWithPip -ProofPath $script:PipxProof

        $r.Status | Should -Be 'failed'
        $r.Detail | Should -BeLike '*nothing usable*'
    }
}

Describe 'Install-OpenCodeDesktop' {

    # Mocks rather than a real installer: the code under test decides whether to install and with which
    # switches, and a real run would make this a network test of opencode.ai.
    BeforeEach {
        $script:OpenCodeExe = Join-Path $TestDrive 'Programs/OpenCode/OpenCode.exe'
        $script:OpenCodePins = @{ opencode_desktop_win_installer_url = 'https://example.invalid/opencode-desktop-win-x64.exe' }
        Mock Install-DirectInstaller { [PSCustomObject]@{ Key = $Key; Package = $Url; Status = 'installed'; Detail = $ProofPath } }
    }

    It 'is one of the custom installs' {
        Get-WindowsCustomInstallKey | Should -Contain 'opencode_desktop'
    }

    # Windows only, because the proof table joins paths under LOCALAPPDATA, which no other platform sets.
    It 'has a proof entry the verification reads' -Skip:(-not $IsWindows) {
        (Get-WindowsCustomInstallProof -Versions @{ unused = '' }).Contains('opencode_desktop') | Should -BeTrue
    }

    It 'reports present and runs nothing when version 2 or later is already installed' {
        Mock Get-FileProductMajorVersion { 2 }

        $r = Install-OpenCodeDesktop -Versions $script:OpenCodePins -ProofPath $script:OpenCodeExe

        $r.Status | Should -Be 'present'
        Should -Invoke Install-DirectInstaller -Times 0 -Exactly
    }

    It 'runs the installer over version 1, which shares its uninstall entry, and says it removed version 1' {
        $script:OpenCodeMajors = [System.Collections.Generic.Queue[int]]::new([int[]]@(1, 1, 2))
        Mock Get-FileProductMajorVersion { $script:OpenCodeMajors.Dequeue() }

        $r = Install-OpenCodeDesktop -Versions $script:OpenCodePins -ProofPath $script:OpenCodeExe

        $r.Status | Should -Be 'installed'
        $r.Detail | Should -BeLike 'removed OpenCode v1 desktop because v2 is selected*'
        Should -Invoke Install-DirectInstaller -Times 1 -Exactly
    }

    It 'fails when the installer reports success and version 1 is still at the path' {
        Mock Get-FileProductMajorVersion { 1 }

        $r = Install-OpenCodeDesktop -Versions $script:OpenCodePins -ProofPath $script:OpenCodeExe

        $r.Status | Should -Be 'failed'
        $r.Detail | Should -BeLike '*is not OpenCode v2'
    }

    It 'installs silently into the directory the proof names, with the signature check left on' {
        Mock Get-FileProductMajorVersion { 0 }
        $expectedDir = Split-Path -Parent $script:OpenCodeExe

        Install-OpenCodeDesktop -Versions $script:OpenCodePins -ProofPath $script:OpenCodeExe | Out-Null

        Should -Invoke Install-DirectInstaller -Times 1 -Exactly -ParameterFilter {
            $Key -eq 'opencode_desktop' -and
            $Url -eq 'https://example.invalid/opencode-desktop-win-x64.exe' -and
            ($SilentArgument -join ' ') -eq "/S /D=$expectedDir" -and
            $ProofPath -eq $script:OpenCodeExe -and
            -not $AllowUnsigned
        }
    }

    It 'names the missing pin instead of downloading anything' {
        Mock Get-FileProductMajorVersion { 0 }

        $r = Install-OpenCodeDesktop -Versions @{ unrelated = 'x' } -ProofPath $script:OpenCodeExe

        $r.Status | Should -Be 'failed'
        $r.Detail | Should -Be 'nothing pins opencode_desktop_win_installer_url, so there is no installer to download'
        Should -Invoke Install-DirectInstaller -Times 0 -Exactly
    }
}

Describe 'Install-OpenCodeDesktop with opencode_use_v1' {

    # The version 1 desktop app comes from winget, and winget calls an installed version 2 a newer copy of the
    # same package because both register one uninstall entry, so version 2 has to be uninstalled first. Every
    # winget call is mocked: this decides what runs, a real run would change the machine.
    BeforeEach {
        $script:OpenCodeExe = Join-Path $TestDrive 'Programs/OpenCode/OpenCode.exe'
        $script:V1Mapping = [PSCustomObject]@{ Manager = 'winget'; Package = 'SST.OpenCodeDesktop'; Scope = 'user' }
        Mock Get-WingetPath { 'winget.exe' }
        Mock Invoke-BoundedWinget { [PSCustomObject]@{ Output = 'Successfully uninstalled'; ExitCode = 0; TimedOut = $false } }
        Mock Install-WingetPackage { [PSCustomObject]@{ Package = $PackageId; Status = 'installed'; Detail = '' } }
        Mock Install-DirectInstaller { throw 'the version 2 installer must not run when version 1 is selected' }
    }

    It 'uninstalls version 2, installs version 1 per user into the proof directory, and says so' {
        # Version 2 before, 2 again for the "was the other one here" question, gone after the uninstall, 1 after the install.
        $script:OpenCodeMajors = [System.Collections.Generic.Queue[int]]::new([int[]]@(2, 2, 0, 1))
        Mock Get-FileProductMajorVersion { $script:OpenCodeMajors.Dequeue() }
        $expectedDir = Split-Path -Parent $script:OpenCodeExe

        $r = Install-OpenCodeDesktop -Versions @{} -ProofPath $script:OpenCodeExe -Version 'v1' -V1Mapping $script:V1Mapping

        $r.Status | Should -Be 'installed'
        $r.Detail | Should -Be 'removed OpenCode v2 desktop because v1 is selected'
        Should -Invoke Invoke-BoundedWinget -Times 1 -Exactly -ParameterFilter {
            ($Arguments -join ' ') -like 'uninstall --product-code d074f30d-5f88-5885-b075-be1348cc7676 *--silent*'
        }
        Should -Invoke Install-WingetPackage -Times 1 -Exactly -ParameterFilter {
            $PackageId -eq 'SST.OpenCodeDesktop' -and $Scope -eq 'user' -and $Location -eq $expectedDir
        }
    }

    It 'reports present and runs nothing when version 1 is already installed' {
        Mock Get-FileProductMajorVersion { 1 }

        $r = Install-OpenCodeDesktop -Versions @{} -ProofPath $script:OpenCodeExe -Version 'v1' -V1Mapping $script:V1Mapping

        $r.Status | Should -Be 'present'
        Should -Invoke Invoke-BoundedWinget -Times 0 -Exactly
        Should -Invoke Install-WingetPackage -Times 0 -Exactly
    }

    It 'installs nothing when version 2 could not be removed' {
        Mock Get-FileProductMajorVersion { 2 }

        $r = Install-OpenCodeDesktop -Versions @{} -ProofPath $script:OpenCodeExe -Version 'v1' -V1Mapping $script:V1Mapping

        $r.Status | Should -Be 'failed'
        $r.Detail | Should -BeLike 'OpenCode v2 desktop could not be removed, so version 1 was not installed:*'
        Should -Invoke Install-WingetPackage -Times 0 -Exactly
    }

    It 'names the missing mapping instead of installing anything' {
        Mock Get-FileProductMajorVersion { 0 }

        $r = Install-OpenCodeDesktop -Versions @{} -ProofPath $script:OpenCodeExe -Version 'v1'

        $r.Status | Should -Be 'failed'
        $r.Detail | Should -BeLike '*maps no opencode_desktop_v1*'
    }

    It 'reads the version 1 package from vars/Windows.yaml, which no toggle names' {
        $mappings = Get-WindowsSoftwareMapping -WindowsMappingPath (Join-Path $script:AnsibleDir 'vars\Windows.yaml')

        $mappings['opencode_desktop_v1'].Package | Should -Be 'SST.OpenCodeDesktop'
        $mappings['opencode_desktop_v1'].Scope | Should -Be 'user'
        Get-WindowsCustomInstallMappingKey | Should -Contain 'opencode_desktop_v1'
    }
}

Describe 'Get-OpenCodeVersion' {

    BeforeAll {
        $script:AllVarsFile     = Join-Path $script:AnsibleDir 'group_vars\all.yaml'
        $script:WindowsVarsFile = Join-Path $script:AnsibleDir 'group_vars\windows.yaml'
    }

    It 'is v2 with group_vars as they ship' {
        Get-OpenCodeVersion -AllVarsPath $script:AllVarsFile -WindowsVarsPath $script:WindowsVarsFile | Should -Be 'v2'
    }

    It 'is v1 when the selection turns opencode_use_v1 on' {
        Get-OpenCodeVersion -AllVarsPath $script:AllVarsFile -WindowsVarsPath $script:WindowsVarsFile `
            -ToggleOverride @{ opencode_use_v1 = $true } | Should -Be 'v1'
    }

    It 'is v2 when the checklist left opencode_use_v1 unticked' {
        Get-OpenCodeVersion -AllVarsPath $script:AllVarsFile -WindowsVarsPath $script:WindowsVarsFile `
            -ToggleOverride @{ opencode_use_v1 = $true } -OnlyKeys @('opencode', 'opencode_desktop') | Should -Be 'v2'
    }
}

Describe 'The OpenCode command line tool follows the selected version' {

    # The same global npm stub as the Install-NpmToolPackage tests above, so the call log says which verbs ran.
    BeforeAll {
        . (Join-Path $script:RepoRoot 'setup\windows\WindowsNpmTools.ps1')

        $script:SavedUserProfile = $env:USERPROFILE
        $env:USERPROFILE = $TestDrive

        function global:npm {
            $global:NpmStubCalls.Add(($args -join ' '))
            if ($args[0] -eq 'list') {
                $global:LASTEXITCODE = 1
                return ''
            }
            $global:LASTEXITCODE = 0
            if ($args[0] -eq 'uninstall') {
                return 'removed 2 packages in 1s'
            }
            return 'added 3 packages in 6s'
        }
    }

    AfterAll {
        Remove-Item -LiteralPath Function:\global:npm -ErrorAction SilentlyContinue
        $env:USERPROFILE = $script:SavedUserProfile
    }

    BeforeEach {
        $global:NpmStubCalls = [System.Collections.Generic.List[string]]::new()
        Mock Test-NpmAvailable { $true }
        Mock Write-Host { }
    }

    It 'names @opencode/cli and replaces opencode-ai for v2, and the other way round for v1' {
        $v2 = Get-NpmToolPackage -OpenCodeVersion 'v2'
        $v1 = Get-NpmToolPackage -OpenCodeVersion 'v1'

        $v2['opencode'].Package  | Should -Be '@opencode/cli'
        $v2['opencode'].Replaces | Should -Be 'opencode-ai'
        $v1['opencode'].Package  | Should -Be 'opencode-ai'
        $v1['opencode'].Replaces | Should -Be '@opencode/cli'
        (Get-NpmToolPackage)['opencode'].Package | Should -Be '@opencode/cli' -Because 'version 2 is the default'
    }

    It 'removes version 1 and installs version 2 by default, and says so' {
        $summary = Invoke-WindowsNpmToolInstall -Toggles @{ opencode = $true }

        ($global:NpmStubCalls -join ' | ') | Should -Be 'list -g @opencode/cli --depth=0 | uninstall -g opencode-ai | install -g @opencode/cli'
        @($summary.Installed)[0].Detail | Should -Be 'removed OpenCode v1 command line tool, opencode-ai, because v2 is selected'
    }

    It 'removes version 2 and installs version 1 when it is selected, and says so' {
        $summary = Invoke-WindowsNpmToolInstall -Toggles @{ opencode = $true } -OpenCodeVersion 'v1'

        ($global:NpmStubCalls -join ' | ') | Should -Be 'list -g opencode-ai --depth=0 | uninstall -g @opencode/cli | install -g opencode-ai'
        @($summary.Installed)[0].Detail | Should -Be 'removed OpenCode v2 command line tool, @opencode/cli, because v1 is selected'
    }
}

Describe 'Move-OpenCodeData' {

    # Fake data folders carrying only the text the real databases carry, CREATE TABLE `session` for version 1
    # and CREATE TABLE `session_v2` for version 2, read out of the databases opencode-ai 1.19.1 and
    # @opencode/cli 2.0.29 created on 2026-10-15. roles/ai_tools/tasks/opencode_data.yaml is held to the same
    # cases by e2e/tier1/opencode_switch.sh.
    BeforeAll {
        function New-FakeOpenCodeData {
            param([string] $Path, [ValidateSet('v1', 'v2', 'v2-wal', 'migrated')] [string] $Kind, [string] $Marker)
            $null = New-Item -ItemType Directory -Path $Path -Force
            switch ($Kind) {
                'v1'     { Set-Content -LiteralPath (Join-Path $Path 'opencode.db') -Value 'SQLite format 3 CREATE TABLE `session` (' -NoNewline }
                'v2'     { Set-Content -LiteralPath (Join-Path $Path 'opencode.db') -Value 'SQLite format 3 CREATE TABLE `session_v2` (' -NoNewline }
                'migrated' { Set-Content -LiteralPath (Join-Path $Path 'opencode.db') -Value 'SQLite format 3 CREATE TABLE `session` ( CREATE TABLE `session_v2` (' -NoNewline }
                'v2-wal' {
                    Set-Content -LiteralPath (Join-Path $Path 'opencode.db') -Value 'SQLite format 3' -NoNewline
                    Set-Content -LiteralPath (Join-Path $Path 'opencode.db-wal') -Value 'WAL CREATE TABLE `session_v2` (' -NoNewline
                }
            }
            Set-Content -LiteralPath (Join-Path $Path 'marker') -Value $Marker
        }
    }

    BeforeEach {
        $script:DataHome = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $null = New-Item -ItemType Directory -Path $script:DataHome
        $script:Folder = Join-Path $script:DataHome 'opencode'
    }

    It 'moves version 2 data aside when version 1 is selected, deleting nothing' {
        New-FakeOpenCodeData -Path $script:Folder -Kind 'v2' -Marker 'v2 data'

        $r = Move-OpenCodeData -Version 'v1' -DataHome $script:DataHome -Stamp '20261015-120000'

        $r.Status | Should -Be 'installed'
        $r.Detail | Should -BeLike "moved $script:Folder to *opencode.v2-backup-20261015-120000, because it holds OpenCode v2 data and v1 is selected"
        Test-Path -LiteralPath $script:Folder | Should -BeFalse
        Get-Content -LiteralPath (Join-Path $script:DataHome 'opencode.v2-backup-20261015-120000\marker') | Should -Be 'v2 data'
    }

    It 'brings no version 1 backup back when version 1 is selected, so version 1 starts clean' {
        New-FakeOpenCodeData -Path $script:Folder -Kind 'v2' -Marker 'v2 data'
        New-FakeOpenCodeData -Path (Join-Path $script:DataHome 'opencode.v1-backup-20260101-000000') -Kind 'v1' -Marker 'older v1'
        New-FakeOpenCodeData -Path (Join-Path $script:DataHome 'opencode.v1-backup-20260202-000000') -Kind 'v1' -Marker 'newer v1'

        $r = Move-OpenCodeData -Version 'v1' -DataHome $script:DataHome -Stamp '20261015-120000'

        $r.Status | Should -Be 'installed'
        @($r.Detail -split '; ').Count | Should -Be 1
        Test-Path -LiteralPath $script:Folder | Should -BeFalse
        Get-Content -LiteralPath (Join-Path $script:DataHome 'opencode.v2-backup-20261015-120000\marker') | Should -Be 'v2 data'
        Get-Content -LiteralPath (Join-Path $script:DataHome 'opencode.v1-backup-20260101-000000\marker') | Should -Be 'older v1'
        Get-Content -LiteralPath (Join-Path $script:DataHome 'opencode.v1-backup-20260202-000000\marker') | Should -Be 'newer v1'
    }

    It 'leaves a version 1 backup where it is when version 1 is selected and there is no data folder' {
        New-FakeOpenCodeData -Path (Join-Path $script:DataHome 'opencode.v1-backup-20260101-000000') -Kind 'v1' -Marker 'v1 backup'

        $r = Move-OpenCodeData -Version 'v1' -DataHome $script:DataHome -Stamp '20261015-120000'

        $r.Status | Should -Be 'present'
        Test-Path -LiteralPath $script:Folder | Should -BeFalse
        Get-Content -LiteralPath (Join-Path $script:DataHome 'opencode.v1-backup-20260101-000000\marker') | Should -Be 'v1 backup'
    }

    It 'sets version 1 data aside and brings the newest version 2 backup back when version 2 is selected' {
        New-FakeOpenCodeData -Path $script:Folder -Kind 'v1' -Marker 'v1 data'
        New-FakeOpenCodeData -Path (Join-Path $script:DataHome 'opencode.v2-backup-20260101-000000') -Kind 'v2-wal' -Marker 'older v2'
        New-FakeOpenCodeData -Path (Join-Path $script:DataHome 'opencode.v2-backup-20260202-000000') -Kind 'v2' -Marker 'newer v2'

        $r = Move-OpenCodeData -Version 'v2' -DataHome $script:DataHome -Stamp '20261015-120000'

        $r.Status | Should -Be 'installed'
        Get-Content -LiteralPath (Join-Path $script:Folder 'marker') | Should -Be 'newer v2'
        Get-Content -LiteralPath (Join-Path $script:DataHome 'opencode.v1-backup-20261015-120000\marker') | Should -Be 'v1 data'
        Get-Content -LiteralPath (Join-Path $script:DataHome 'opencode.v2-backup-20260101-000000\marker') | Should -Be 'older v2'
        @($r.Detail -split '; ').Count | Should -Be 2
    }

    It 'leaves version 1 data for version 2 to migrate when no version 2 backup exists' {
        New-FakeOpenCodeData -Path $script:Folder -Kind 'v1' -Marker 'v1 data'

        $r = Move-OpenCodeData -Version 'v2' -DataHome $script:DataHome -Stamp '20261015-120000'

        $r.Status | Should -Be 'present'
        Get-Content -LiteralPath (Join-Path $script:Folder 'marker') | Should -Be 'v1 data'
    }

    It 'keeps data version 2 migrated from version 1, which carries both tables, when version 2 is selected' {
        New-FakeOpenCodeData -Path $script:Folder -Kind 'migrated' -Marker 'migrated data'
        New-FakeOpenCodeData -Path (Join-Path $script:DataHome 'opencode.v2-backup-20260101-000000') -Kind 'v2' -Marker 'older v2'

        $r = Move-OpenCodeData -Version 'v2' -DataHome $script:DataHome -Stamp '20261015-120000'

        $r.Status | Should -Be 'present'
        Get-Content -LiteralPath (Join-Path $script:Folder 'marker') | Should -Be 'migrated data'
    }

    It 'reads a version 2 database whose tables are still in the write-ahead log' {
        New-FakeOpenCodeData -Path $script:Folder -Kind 'v2-wal' -Marker 'v2 data'

        Get-OpenCodeDataVersion -Directory $script:Folder | Should -Be 'v2'
    }

    It 'finds the table text across the boundary between two blocks it reads' {
        $null = New-Item -ItemType Directory -Path $script:Folder
        $needle = [System.Text.Encoding]::ASCII.GetBytes('CREATE TABLE `session_v2`')
        $bytes = [byte[]]::new(1MB + 64)
        [Array]::Copy($needle, 0, $bytes, 1MB - 10, $needle.Length)
        [System.IO.File]::WriteAllBytes((Join-Path $script:Folder 'opencode.db'), $bytes)

        Test-OpenCodeDatabaseTable -Directory $script:Folder -Table 'session_v2' | Should -BeTrue
        Test-OpenCodeDatabaseTable -Directory $script:Folder -Table 'session' | Should -BeFalse
    }

    It 'moves nothing the second time' {
        New-FakeOpenCodeData -Path $script:Folder -Kind 'v2' -Marker 'v2 data'
        Move-OpenCodeData -Version 'v1' -DataHome $script:DataHome -Stamp '20261015-120000' | Out-Null

        $r = Move-OpenCodeData -Version 'v1' -DataHome $script:DataHome -Stamp '20261015-120001'

        $r.Status | Should -Be 'present'
        @(Get-ChildItem -LiteralPath $script:DataHome -Directory).Count | Should -Be 1
    }

    It 'refuses to move onto a backup that already exists, and moves nothing' {
        New-FakeOpenCodeData -Path $script:Folder -Kind 'v2' -Marker 'v2 data'
        New-FakeOpenCodeData -Path (Join-Path $script:DataHome 'opencode.v2-backup-20261015-120000') -Kind 'v2' -Marker 'earlier'

        $r = Move-OpenCodeData -Version 'v1' -DataHome $script:DataHome -Stamp '20261015-120000'

        $r.Status | Should -Be 'failed'
        Get-Content -LiteralPath (Join-Path $script:Folder 'marker') | Should -Be 'v2 data'
        Get-Content -LiteralPath (Join-Path $script:DataHome 'opencode.v2-backup-20261015-120000\marker') | Should -Be 'earlier'
    }
}

Describe 'Resolve-PickedSelection in setup.ps1' {

    # Lifted out of the syntax tree for the reason the Install-ConsoleGuiTools tests give: setup.ps1 runs
    # Invoke-Main when it is loaded. Until 2026-10-15 the ticked keys only narrowed the group_vars set, so a
    # toggle that ships off, opencode_use_v1 among them, could not be turned on from the checklist.
    BeforeAll {
        $setupScript = Join-Path $script:RepoRoot 'setup\setup.ps1'
        $parseErrors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($setupScript, [ref]$null, [ref]$parseErrors)
        if ($parseErrors) { throw "setup.ps1 does not parse: $($parseErrors[0].Message)" }
        $wanted = @('Resolve-PickedSelection', 'Resolve-ToggleOverride', 'Split-KeyList')
        $definitions = @($ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $wanted -contains $node.Name
        }, $true))
        if ($definitions.Count -ne $wanted.Count) {
            throw "Expected $($wanted.Count) function definitions in setup.ps1 and found $($definitions.Count)."
        }
        foreach ($definition in $definitions) {
            . ([scriptblock]::Create($definition.Extent.Text))
        }
        # The list Resolve-ToggleOverride reads for -Software all, taken from setup.ps1 rather than restated.
        $script:KeepsOffAssignment = @($ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
                $node.Left.Extent.Text -eq '$AllSoftwareKeepsOff'
        }, $false))
        if ($script:KeepsOffAssignment.Count -eq 1) {
            . ([scriptblock]::Create($script:KeepsOffAssignment[0].Extent.Text))
        }
        $script:Offered = @(
            [PSCustomObject]@{ Key = 'install_chrome'; Enabled = $true }
            [PSCustomObject]@{ Key = 'install_opencode'; Enabled = $true }
            [PSCustomObject]@{ Key = 'opencode_use_v1'; Enabled = $false }
            [PSCustomObject]@{ Key = 'setup_wsl'; Enabled = $true }
        )
    }

    It 'turns a ticked toggle that ships off on, and an unticked one that ships on off' {
        $picked = Resolve-PickedSelection -PickedKeys @('install_opencode', 'opencode_use_v1') -Selectable $script:Offered

        $picked.ToggleOverride['opencode_use_v1'] | Should -BeTrue
        $picked.ToggleOverride['install_opencode'] | Should -BeTrue
        $picked.ToggleOverride['install_chrome'] | Should -BeFalse
        $picked.ToggleOverride['setup_wsl'] | Should -BeFalse
        ($picked.OnlyKeys -join ' ') | Should -Be 'opencode opencode_use_v1'
    }

    It 'declares the list -Software all leaves off once, with opencode_use_v1 in it' {
        $script:KeepsOffAssignment.Count | Should -Be 1
        $AllSoftwareKeepsOff | Should -Contain 'opencode_use_v1'
    }

    It 'leaves opencode_use_v1 off under -Software all, so install all keeps OpenCode on version 2' {
        $override = Resolve-ToggleOverride -Selectable $script:Offered -Baseline 'all'

        $override['opencode_use_v1'] | Should -BeFalse
        $override['install_opencode'] | Should -BeTrue
        $override['install_chrome'] | Should -BeTrue
        $override['setup_wsl'] | Should -BeTrue
    }

    It 'turns opencode_use_v1 on under -Software all when -EnableKey names it' {
        $override = Resolve-ToggleOverride -Selectable $script:Offered -Baseline 'all' -EnableKey 'opencode_use_v1'

        $override['opencode_use_v1'] | Should -BeTrue
    }

    It 'makes Get-OpenCodeVersion answer v2 under -Software all' {
        $override = Resolve-ToggleOverride -Selectable $script:Offered -Baseline 'all'

        Get-OpenCodeVersion -AllVarsPath (Join-Path $script:AnsibleDir 'group_vars\all.yaml') `
            -WindowsVarsPath (Join-Path $script:AnsibleDir 'group_vars\windows.yaml') `
            -ToggleOverride $override | Should -Be 'v2'
    }

    It 'makes Get-OpenCodeVersion answer v1 when the switch is ticked' {
        $picked = Resolve-PickedSelection -PickedKeys @('install_opencode', 'opencode_use_v1') -Selectable $script:Offered

        Get-OpenCodeVersion -AllVarsPath (Join-Path $script:AnsibleDir 'group_vars\all.yaml') `
            -WindowsVarsPath (Join-Path $script:AnsibleDir 'group_vars\windows.yaml') `
            -ToggleOverride $picked.ToggleOverride -OnlyKeys $picked.OnlyKeys | Should -Be 'v1'
    }

    It 'leaves opencode_use_v1 off when every offered key is ticked, which is how select-all answers' {
        $picked = Resolve-PickedSelection -PickedKeys @($script:Offered.Key) -Selectable $script:Offered

        $picked.ToggleOverride['opencode_use_v1'] | Should -BeFalse
        $picked.ToggleOverride['install_opencode'] | Should -BeTrue
        $picked.ToggleOverride['install_chrome'] | Should -BeTrue
        $picked.ToggleOverride['setup_wsl'] | Should -BeTrue
        $picked.OnlyKeys | Should -Not -Contain 'opencode_use_v1'
    }

    It 'keeps opencode_use_v1 on when it is ticked on its own' {
        $picked = Resolve-PickedSelection -PickedKeys @('opencode_use_v1') -Selectable $script:Offered

        $picked.ToggleOverride['opencode_use_v1'] | Should -BeTrue
        ($picked.OnlyKeys -join ' ') | Should -Be 'opencode_use_v1'
    }

    It 'keeps opencode_use_v1 on when everything but one other key is ticked with it' {
        $picked = Resolve-PickedSelection -PickedKeys @('install_opencode', 'opencode_use_v1', 'setup_wsl') -Selectable $script:Offered

        $picked.ToggleOverride['opencode_use_v1'] | Should -BeTrue
        $picked.ToggleOverride['install_chrome'] | Should -BeFalse
    }
}

Describe 'Show-SoftwarePicker in setup.ps1 with every row selected' {

    # The grid is replaced by a stand-in that hands back every row it was given, which is what its select-all
    # does, and records the title it was shown. Lifted out of the syntax tree for the reason above.
    BeforeAll {
        $setupScript = Join-Path $script:RepoRoot 'setup\setup.ps1'
        $parseErrors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($setupScript, [ref]$null, [ref]$parseErrors)
        if ($parseErrors) { throw "setup.ps1 does not parse: $($parseErrors[0].Message)" }
        $wanted = @('Show-SoftwarePicker', 'Resolve-PickedSelection', 'Resolve-ToggleOverride', 'Split-KeyList')
        $definitions = @($ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $wanted -contains $node.Name
        }, $true))
        if ($definitions.Count -ne $wanted.Count) {
            throw "Expected $($wanted.Count) function definitions in setup.ps1 and found $($definitions.Count)."
        }
        foreach ($definition in $definitions) {
            . ([scriptblock]::Create($definition.Extent.Text))
        }
        $assignments = @($ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
                ($node.Left.Extent.Text -eq '$AllSoftwareKeepsOff' -or $node.Left.Extent.Text -eq '$LabelOverrides')
        }, $false))
        foreach ($assignment in $assignments) {
            . ([scriptblock]::Create($assignment.Extent.Text))
        }
        function Import-Module { }
        function Out-ConsoleGridView {
            param([Parameter(ValueFromPipeline)] $InputObject, [string] $Title, [string] $OutputMode)
            begin { $script:GridTitle = $Title }
            process { $InputObject }
        }
        $script:Items = @(
            [PSCustomObject]@{ Key = 'install_chrome'; Label = 'Chrome'; Enabled = $true }
            [PSCustomObject]@{ Key = 'install_opencode'; Label = 'Opencode'; Enabled = $true }
            [PSCustomObject]@{ Key = 'opencode_use_v1'; Label = $LabelOverrides['opencode_use_v1']; Enabled = $false }
        )
    }

    It 'says in the grid title that select-all leaves the switch off and that it is ticked on its own' {
        $null = Show-SoftwarePicker -Items $script:Items

        $script:GridTitle | Should -Match ([regex]::Escape($LabelOverrides['opencode_use_v1']))
        $script:GridTitle | Should -Match 'on its own'
    }

    It 'turns select-all into every key on but opencode_use_v1' {
        $keys = Show-SoftwarePicker -Items $script:Items
        $picked = Resolve-PickedSelection -PickedKeys $keys -Selectable $script:Items

        $picked.ToggleOverride['opencode_use_v1'] | Should -BeFalse
        $picked.ToggleOverride['install_chrome'] | Should -BeTrue
        $picked.ToggleOverride['install_opencode'] | Should -BeTrue
    }
}

Describe 'Get-FileProductMajorVersion' {

    It 'answers 0 for a file that is not there' {
        Get-FileProductMajorVersion -Path (Join-Path $TestDrive 'absent.exe') | Should -Be 0
    }

    It 'answers 0 for a file that carries no product version' {
        $plain = Join-Path $TestDrive 'plain.exe'
        Set-Content -LiteralPath $plain -Value 'MZ'

        Get-FileProductMajorVersion -Path $plain | Should -Be 0
    }
}

Describe 'Invoke-InstallStepWithRetry, the shared retry rule for an install step that returns a result row' {

    BeforeEach {
        $global:StepCalls = [System.Collections.Generic.List[string]]::new()
        $global:StepFailuresLeft = 0
        Mock Start-Sleep { $global:StepCalls.Add("wait $Seconds") }
        Mock Write-Host { }
        $script:Step = {
            $global:StepCalls.Add('step')
            if ($global:StepFailuresLeft -gt 0) {
                $global:StepFailuresLeft--
                return [PSCustomObject]@{ Key = 'k'; Package = 'tool install'; Status = 'failed'; Detail = 'exit 1.' }
            }
            [PSCustomObject]@{ Key = 'k'; Package = 'tool install'; Status = 'installed'; Detail = '' }
        }
        $script:StepRefresh = { $global:StepCalls.Add('refresh'); '' }
    }

    It 'returns the first result untouched, with no wait and no refresh, when the first attempt works' {
        $r = Invoke-InstallStepWithRetry -Package 'tool install' -Step $script:Step -Refresh $script:StepRefresh

        $r.Status | Should -Be 'installed'
        $r.Detail | Should -BeNullOrEmpty
        @($global:StepCalls) | Should -Be @('step')
    }

    It 'waits, refreshes, then retries a transient failure, and says so in the result' {
        $global:StepFailuresLeft = 1

        $r = Invoke-InstallStepWithRetry -Package 'tool install' -Step $script:Step -Refresh $script:StepRefresh

        $r.Status | Should -Be 'installed'
        $r.Detail | Should -Be 'installed on attempt 2 of 4, after attempt 1 said exit 1.'
        @($global:StepCalls) | Should -Be @('step', 'wait 20', 'refresh', 'step')
    }

    It 'names a step that fails every one of its four attempts' {
        $global:StepFailuresLeft = 99

        $r = Invoke-InstallStepWithRetry -Package 'tool install' -Step $script:Step

        $r.Status | Should -Be 'failed'
        $r.Package | Should -Be 'tool install'
        $r.Detail | Should -Be 'exit 1. (attempt 4 of 4; attempts 1, 2 and 3 said exit 1.)'
        @($global:StepCalls | Where-Object { $_ -eq 'step' }).Count | Should -Be 4
        @($global:StepCalls | Where-Object { $_ -eq 'wait 20' }).Count | Should -Be 3
    }

    It 'does not retry a failure the step marks Final, such as a deadline' {
        $final = { $global:StepCalls.Add('step'); [PSCustomObject]@{ Key = 'k'; Package = 'p'; Status = 'failed'; Detail = 'killed after 15 minutes'; Final = $true } }

        $r = Invoke-InstallStepWithRetry -Package 'p' -Step $final -Refresh $script:StepRefresh

        $r.Detail | Should -Be 'killed after 15 minutes'
        @($global:StepCalls) | Should -Be @('step')
    }

    It 'does not retry a step that was skipped' {
        $skipped = { $global:StepCalls.Add('step'); [PSCustomObject]@{ Key = 'k'; Package = 'p'; Status = 'skipped'; Detail = 'WhatIf' } }

        $r = Invoke-InstallStepWithRetry -Package 'p' -Step $skipped

        $r.Status | Should -Be 'skipped'
        $r.Detail | Should -Be 'WhatIf'
        @($global:StepCalls) | Should -Be @('step')
    }
}

Describe 'The steps that end a retry early say so' {

    It 'marks a command that is not on PATH as Final' {
        $r = Invoke-ManagedTool -Key 'k' -FilePath 'no-such-tool-installationhelper' -ArgumentList @('install')

        $r.Status | Should -Be 'failed'
        $r.Final | Should -BeTrue
    }

    It 'marks a missing sdkmanager as Final' {
        $saved = $script:AndroidSdkRoot
        try {
            $script:AndroidSdkRoot = Join-Path $TestDrive 'android'
            $r = Invoke-AndroidSdkManager -Arguments @('platform-tools')
        } finally {
            $script:AndroidSdkRoot = $saved
        }

        $r.Status | Should -Be 'failed'
        $r.Final | Should -BeTrue
    }
}

Describe 'Install-FvmFromPub retries the pub.dev activation' {

    # pub resolves against pub.dev on every activation and reads its on-disk version listing only for
    # advisories and --offline, so there is nothing to refresh, and the retry only waits.
    BeforeEach {
        $script:SavedLocalAppData = $env:LOCALAPPDATA
        $env:LOCALAPPDATA = Join-Path $TestDrive 'local'
        $script:FvmBat = Join-Path $env:LOCALAPPDATA 'Pub\Cache\bin\fvm.bat'
        Remove-Item -LiteralPath $env:LOCALAPPDATA -Recurse -Force -ErrorAction SilentlyContinue
        $global:PubFailuresLeft = 0
        Mock Get-Command { [PSCustomObject]@{ Source = 'dart' } } -ParameterFilter { $Name -contains 'dart' }
        Mock Add-ToUserPath { }
        Mock Start-Sleep { }
        Mock Write-Host { }
        Mock Invoke-ManagedTool {
            if ($global:PubFailuresLeft -gt 0) {
                $global:PubFailuresLeft--
                return [PSCustomObject]@{ Key = 'flutter'; Package = 'dart pub global activate fvm'; Status = 'failed'; Detail = 'exit 69. Got socket error trying to find package fvm' }
            }
            New-Item -ItemType File -Path $script:FvmBat -Force | Out-Null
            [PSCustomObject]@{ Key = 'flutter'; Package = 'dart pub global activate fvm'; Status = 'installed'; Detail = '' }
        }
    }

    AfterEach {
        $env:LOCALAPPDATA = $script:SavedLocalAppData
    }

    It 'activates once and never waits when the first attempt works' {
        (Install-FvmFromPub).Status | Should -Be 'installed'
        Should -Invoke Invoke-ManagedTool -Times 1 -Exactly
        Should -Invoke Start-Sleep -Times 0 -Exactly
    }

    It 'waits and activates again after a transient failure' {
        $global:PubFailuresLeft = 1

        (Install-FvmFromPub).Status | Should -Be 'installed'
        Should -Invoke Invoke-ManagedTool -Times 2 -Exactly
        Should -Invoke Start-Sleep -Times 1 -Exactly -ParameterFilter { $Seconds -eq 20 }
    }

    It 'names an activation that fails every one of its four attempts' {
        $global:PubFailuresLeft = 99

        $r = Install-FvmFromPub

        $r.Status | Should -Be 'failed'
        $r.Detail | Should -BeLike 'exit 69. Got socket error trying to find package fvm (attempt 4 of 4; attempts 1, 2 and 3 said*'
        Should -Invoke Invoke-ManagedTool -Times 4 -Exactly
    }
}

Describe 'Install-NodeViaNvm and Install-FlutterViaFvm retry the download, not the local step after it' {

    BeforeEach {
        $global:ToolCalls = [System.Collections.Generic.List[string]]::new()
        $global:ToolFailuresLeft = 0
        Mock Start-Sleep { }
        Mock Write-Host { }
        Mock Invoke-ManagedTool {
            $command = "$FilePath $($ArgumentList -join ' ')"
            $global:ToolCalls.Add($command)
            if ($ArgumentList[0] -eq 'install' -and $global:ToolFailuresLeft -gt 0) {
                $global:ToolFailuresLeft--
                return [PSCustomObject]@{ Key = $Key; Package = $command; Status = 'failed'; Detail = 'exit 1. download failed' }
            }
            [PSCustomObject]@{ Key = $Key; Package = $command; Status = 'installed'; Detail = '' }
        }
        Mock Get-WingetPath { 'winget' }
        Mock Install-WingetPackage { [PSCustomObject]@{ Package = 'CoreyButler.NVMforWindows'; Status = 'present'; Detail = '' } }
        Mock Update-ProcessEnvironment { }
        Mock Update-ProcessPath { }
        Mock Resolve-NvmExecutable { 'nvm' }
        Mock Install-FvmFromPub { [PSCustomObject]@{ Status = 'present'; Detail = 'fvm.bat' } }
        Mock Get-WindowsCustomInstallProof { @{ flutter = [PSCustomObject]@{ Path = @(Join-Path $TestDrive 'no-flutter-here') } } }
    }

    It 'runs nvm install lts once and never waits when it works' {
        $r = @(Install-NodeViaNvm)

        @($r | Where-Object Status -eq 'failed').Count | Should -Be 0
        @($global:ToolCalls) | Should -Be @('nvm install lts', 'nvm use lts')
        Should -Invoke Start-Sleep -Times 0 -Exactly
    }

    It 'waits and runs nvm install lts again after a transient failure, then nvm use lts once' {
        $global:ToolFailuresLeft = 1

        $r = @(Install-NodeViaNvm)

        @($r | Where-Object Status -eq 'failed').Count | Should -Be 0
        @($global:ToolCalls) | Should -Be @('nvm install lts', 'nvm install lts', 'nvm use lts')
        Should -Invoke Start-Sleep -Times 1 -Exactly -ParameterFilter { $Seconds -eq 20 }
    }

    It 'names nvm install lts when it fails every one of its four attempts' {
        $global:ToolFailuresLeft = 99

        $r = @(Install-NodeViaNvm)

        $failed = @($r | Where-Object Status -eq 'failed')
        $failed.Count | Should -Be 1
        $failed[0].Package | Should -Be 'nvm install lts'
        $failed[0].Detail | Should -Be 'exit 1. download failed (attempt 4 of 4; attempts 1, 2 and 3 said exit 1. download failed)'
        @($global:ToolCalls | Where-Object { $_ -eq 'nvm install lts' }).Count | Should -Be 4
    }

    It 'runs fvm install once and never waits when it works' {
        $r = @(Install-FlutterViaFvm -Versions @{ flutter_channel = 'stable' })

        @($r | Where-Object Status -eq 'failed').Count | Should -Be 0
        @($global:ToolCalls) | Should -Be @('fvm install stable', 'fvm global stable')
        Should -Invoke Start-Sleep -Times 0 -Exactly
    }

    It 'waits and runs fvm install again after a transient failure, then fvm global once' {
        $global:ToolFailuresLeft = 1

        $r = @(Install-FlutterViaFvm -Versions @{ flutter_channel = 'stable' })

        @($r | Where-Object Status -eq 'failed').Count | Should -Be 0
        @($global:ToolCalls) | Should -Be @('fvm install stable', 'fvm install stable', 'fvm global stable')
        Should -Invoke Start-Sleep -Times 1 -Exactly -ParameterFilter { $Seconds -eq 20 }
    }

    It 'names fvm install when it fails every one of its four attempts' {
        $global:ToolFailuresLeft = 99

        $r = @(Install-FlutterViaFvm -Versions @{ flutter_channel = 'stable' })

        $failed = @($r | Where-Object { $_.Status -eq 'failed' -and $_.Package -eq 'fvm install stable' })
        $failed.Count | Should -Be 1
        $failed[0].Detail | Should -BeLike '*(attempt 4 of 4; attempts 1, 2 and 3 said*'
        @($global:ToolCalls | Where-Object { $_ -eq 'fvm install stable' }).Count | Should -Be 4
    }
}

Describe 'Install-DirectInstaller retries the download, which has no index to refresh' {

    # Get-AuthenticodeSignature exists only on Windows, so a function stands in for it everywhere and
    # every test mocks it. Answering NotSigned without -AllowUnsigned stops each run right after the
    # download, which is the part under test, before anything is executed.
    BeforeAll {
        function Get-AuthenticodeSignature { param([string] $LiteralPath) }
    }

    BeforeEach {
        $global:DownloadFailuresLeft = 0
        Mock Get-AuthenticodeSignature { [PSCustomObject]@{ Status = 'NotSigned'; SignerCertificate = $null } }
        Mock Start-Sleep { }
        Mock Write-Host { }
        Mock Invoke-WebRequest {
            if ($global:DownloadFailuresLeft -gt 0) {
                $global:DownloadFailuresLeft--
                throw 'The SSL connection could not be established'
            }
            Set-Content -LiteralPath $OutFile -Value 'MZ'
        }
        $script:Direct = @{ Key = 'gridcoin'; Url = 'https://example.invalid/setup.exe'; SilentArgument = @('/S'); ProofPath = (Join-Path $TestDrive 'nothing') }
    }

    It 'downloads once and never waits when the first download works' {
        $r = Install-DirectInstaller @script:Direct

        $r.Detail | Should -BeLike 'refusing to run it*' -Because 'the download succeeded, so the run reached the signature check'
        Should -Invoke Invoke-WebRequest -Times 1 -Exactly
        Should -Invoke Start-Sleep -Times 0 -Exactly
    }

    It 'waits and downloads again after a transient failure' {
        $global:DownloadFailuresLeft = 1

        $r = Install-DirectInstaller @script:Direct

        $r.Detail | Should -BeLike 'refusing to run it*'
        Should -Invoke Invoke-WebRequest -Times 2 -Exactly
        Should -Invoke Start-Sleep -Times 1 -Exactly -ParameterFilter { $Seconds -eq 20 }
    }

    It 'names a download that fails every one of its four attempts' {
        $global:DownloadFailuresLeft = 99

        $r = Install-DirectInstaller @script:Direct

        $r.Status | Should -Be 'failed'
        $r.Package | Should -Be 'https://example.invalid/setup.exe'
        $r.Detail | Should -Be 'download failed: The SSL connection could not be established (attempt 4 of 4; attempts 1, 2 and 3 said download failed: The SSL connection could not be established)'
        Should -Invoke Invoke-WebRequest -Times 4 -Exactly
        Should -Invoke Get-AuthenticodeSignature -Times 0 -Exactly
    }
}

Describe 'Install-AndroidSdk retries the command line tools download' {

    BeforeEach {
        $script:SavedSdkRoot = $script:AndroidSdkRoot
        $script:AndroidSdkRoot = Join-Path $TestDrive 'android'
        Remove-Item -LiteralPath $script:AndroidSdkRoot -Recurse -Force -ErrorAction SilentlyContinue
        $global:ZipFailuresLeft = 0
        Mock Start-Sleep { }
        Mock Write-Host { }
        Mock Invoke-WebRequest {
            if ($global:ZipFailuresLeft -gt 0) {
                $global:ZipFailuresLeft--
                throw 'Response status code does not indicate success: 503 (Service Unavailable).'
            }
            Set-Content -LiteralPath $OutFile -Value 'zip'
        }
        Mock Expand-Archive { New-Item -ItemType Directory -Path (Join-Path $DestinationPath 'cmdline-tools\bin') -Force | Out-Null }
        $script:AndroidPins = @{ android_cmdline_tools_build = '1'; android_api_level = '36'; android_build_tools_version = '36.0.0' }
    }

    AfterEach {
        $script:AndroidSdkRoot = $script:SavedSdkRoot
    }

    It 'downloads once and never waits when the first download works' {
        $r = @(Install-AndroidSdk -Versions $script:AndroidPins)

        $r[0].Status | Should -Be 'installed'
        Should -Invoke Invoke-WebRequest -Times 1 -Exactly
        Should -Invoke Start-Sleep -Times 0 -Exactly
    }

    It 'waits and downloads again after a transient failure' {
        $global:ZipFailuresLeft = 1

        $r = @(Install-AndroidSdk -Versions $script:AndroidPins)

        $r[0].Status | Should -Be 'installed'
        Should -Invoke Invoke-WebRequest -Times 2 -Exactly
        Should -Invoke Start-Sleep -Times 1 -Exactly -ParameterFilter { $Seconds -eq 20 }
    }

    It 'names a download that fails every one of its four attempts' {
        $global:ZipFailuresLeft = 99

        $r = @(Install-AndroidSdk -Versions $script:AndroidPins)

        $r.Count | Should -Be 1
        $r[0].Status | Should -Be 'failed'
        $r[0].Package | Should -Be 'command line tools'
        $r[0].Detail | Should -BeLike 'download failed: Response status code does not indicate success: 503 (Service Unavailable). (attempt 4 of 4; attempts 1, 2 and 3 said*'
        Should -Invoke Invoke-WebRequest -Times 4 -Exactly
    }
}

Describe 'Install-AndroidSdkPackageSet runs sdkmanager once per package' {

    # One sdkmanager call for three packages lost all three to one bad Platform-Tools download on
    # Pop!_OS in sweep run 39260381281, and could not say which package broke.
    BeforeEach {
        $global:SdkCalls = [System.Collections.Generic.List[string]]::new()
        Mock Start-Sleep { }
        Mock Write-Host { }
        Mock Invoke-AndroidSdkManager {
            $global:SdkCalls.Add($Arguments -join ' ')
            if ($Arguments -contains 'platform-tools') {
                return [PSCustomObject]@{ Key = 'android_sdk'; Package = "sdkmanager $($Arguments -join ' ')"; Status = 'failed'
                                          Detail = 'exit 1. Warning: An error occurred while preparing SDK package Android SDK Platform-Tools: Error reading Zip content from a SeekableByteChannel.' }
            }
            [PSCustomObject]@{ Key = 'android_sdk'; Package = "sdkmanager $($Arguments -join ' ')"; Status = 'installed'; Detail = '' }
        }
        $script:SdkPackages = @('platforms;android-36', 'build-tools;36.0.0', 'platform-tools')
    }

    It 'hands sdkmanager one package per call' {
        $null = @(Install-AndroidSdkPackageSet -Packages $script:SdkPackages)

        @($global:SdkCalls | Where-Object { $_.Contains(' ') }) | Should -BeNullOrEmpty
        @($global:SdkCalls | Select-Object -Unique) | Should -Be $script:SdkPackages
    }

    It 'installs the packages that work when another one never does, and names the one that failed' {
        $r = @(Install-AndroidSdkPackageSet -Packages $script:SdkPackages)

        $r.Count | Should -Be 3
        @($r | ForEach-Object Package) | Should -Be @('sdkmanager platforms;android-36', 'sdkmanager build-tools;36.0.0', 'sdkmanager platform-tools')
        @($r | ForEach-Object Status) | Should -Be @('installed', 'installed', 'failed')
        $r[2].Detail | Should -BeLike '*(attempt 4 of 4; attempts 1, 2 and 3 said*'
    }

    It 'retries only the package that failed, four attempts twenty seconds apart' {
        $null = @(Install-AndroidSdkPackageSet -Packages $script:SdkPackages)

        @($global:SdkCalls | Where-Object { $_ -eq 'platforms;android-36' }).Count | Should -Be 1
        @($global:SdkCalls | Where-Object { $_ -eq 'build-tools;36.0.0' }).Count | Should -Be 1
        @($global:SdkCalls | Where-Object { $_ -eq 'platform-tools' }).Count | Should -Be 4
        Should -Invoke Start-Sleep -Times 3 -Exactly -ParameterFilter { $Seconds -eq 20 }
    }
}

Describe 'Install-WslDistribution retries wsl --install' {

    # WindowsSettings.ps1 reads its toggles through WindowsSoftware.ps1, which the top-level BeforeAll
    # has already loaded, so it is dot-sourced here in the order setup.ps1 uses.
    BeforeAll {
        . (Join-Path $script:RepoRoot 'setup\windows\WindowsSettings.ps1')
    }

    BeforeEach {
        $global:WslExitCodes = [System.Collections.Generic.Queue[int]]::new()
        $global:WslHangs = $false
        Mock Get-Command { [PSCustomObject]@{ Source = 'wsl.exe' } } -ParameterFilter { $Name -contains 'wsl' }
        Mock Get-WslDistributionName { @() }
        Mock Start-Sleep { }
        Mock Write-Host { }
        Mock Start-Process {
            $code = if ($global:WslExitCodes.Count -gt 0) { $global:WslExitCodes.Dequeue() } else { 0 }
            $process = [PSCustomObject]@{ ExitCode = $code; Id = 1 }
            $process | Add-Member -MemberType ScriptMethod -Name WaitForExit -Value { param($milliseconds) -not $global:WslHangs }
            $process | Add-Member -MemberType ScriptMethod -Name Kill -Value { param($tree) }
            $process
        }
    }

    It 'runs wsl --install once and never waits when it works' {
        $r = @(Install-WslDistribution)

        $r[0].Status | Should -Be 'installed'
        Should -Invoke Start-Process -Times 1 -Exactly
        Should -Invoke Start-Sleep -Times 0 -Exactly
    }

    It 'waits and runs wsl --install again after a transient failure' {
        $global:WslExitCodes.Enqueue(1)

        $r = @(Install-WslDistribution)

        $r[0].Status | Should -Be 'installed'
        $r[0].RebootRequired | Should -BeTrue
        Should -Invoke Start-Process -Times 2 -Exactly
        Should -Invoke Start-Sleep -Times 1 -Exactly -ParameterFilter { $Seconds -eq 20 }
    }

    It 'names wsl --install when it fails every one of its four attempts' {
        foreach ($attempt in 1..4) { $global:WslExitCodes.Enqueue(1) }

        $r = @(Install-WslDistribution)

        $r[0].Status | Should -Be 'failed'
        $r[0].Package | Should -Be 'Ubuntu'
        $r[0].Detail | Should -BeLike 'wsl --install exited 1.*(attempt 4 of 4; attempts 1, 2 and 3 said*'
        Should -Invoke Start-Process -Times 4 -Exactly
    }

    It 'does not retry a wsl --install that ran out of time' {
        $global:WslHangs = $true

        $r = @(Install-WslDistribution)

        $r[0].Status | Should -Be 'failed'
        $r[0].Detail | Should -BeLike '*still running after 20 minutes*'
        Should -Invoke Start-Process -Times 1 -Exactly
    }
}

Describe 'The Chocolatey bootstrap in the elevated child' {

    It 'runs the install script under the shared retry rule, after the file that defines it is loaded' {
        $body = (Get-Command Install-ChocolateyPackageBatch).Definition

        $dotSource = $body.IndexOf('. $(ConvertTo-PowerShellLiteral -Value $script:WindowsSoftwarePath)')
        $bootstrap = $body.IndexOf("DownloadString('https://community.chocolatey.org/install.ps1')")
        $dotSource | Should -BeGreaterThan -1
        $bootstrap | Should -BeGreaterThan $dotSource -Because 'Invoke-PackageManagerRetry is defined by the file the child dot-sources'
        $body | Should -Match "Invoke-PackageManagerRetry -Package 'Chocolatey'"
    }
}

Describe 'Every network install in the Windows wizard sits inside the shared retry rule' {

    # Read from the syntax tree, so a new download or a new install step that forgets the retry fails
    # here by name. A call that reaches the network must sit, inline, inside a script block handed to
    # Invoke-InstallStepWithRetry or Invoke-PackageManagerRetry. A version manager or sdkmanager call
    # outside one must be a local step, which is named here, so a new network step cannot pass as one.
    BeforeAll {
        $script:LocalSteps = @("@('use', 'lts')", "@('global', `$channel)", "@('-m', 'pipx', 'ensurepath')", "@('--licenses')")
        $script:WizardFiles = @(
            (Join-Path $script:RepoRoot 'setup\setup.ps1')
            @(Get-ChildItem -LiteralPath (Join-Path $script:RepoRoot 'setup\windows') -Filter '*.ps1' | ForEach-Object FullName)
        )

        function global:Test-InsideRetry {
            param([Parameter(Mandatory)] $Node)

            $retryCommands = @('Invoke-InstallStepWithRetry', 'Invoke-PackageManagerRetry')
            $at = $Node.Parent
            while ($at) {
                if ($at -is [System.Management.Automation.Language.ScriptBlockExpressionAst] -and
                    $at.Parent -is [System.Management.Automation.Language.CommandAst] -and
                    $retryCommands -contains $at.Parent.GetCommandName()) {
                    return $true
                }
                $at = $at.Parent
            }
            return $false
        }

        $script:Calls = foreach ($file in $script:WizardFiles) {
            $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($file, [ref]$null, [ref]$errors)
            if ($errors) { throw "$file does not parse: $($errors[0].Message)" }
            foreach ($call in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true)) {
                [PSCustomObject]@{ File = Split-Path -Leaf $file; Line = $call.Extent.StartLineNumber; Name = $call.GetCommandName(); Node = $call; Text = $call.Extent.Text }
            }
        }
    }

    AfterAll {
        Remove-Item -LiteralPath Function:\global:Test-InsideRetry -ErrorAction SilentlyContinue
    }

    It 'finds the downloads and the gallery install it is meant to guard' {
        @($script:Calls | Where-Object { $_.Name -in @('Invoke-WebRequest', 'Install-Module') }).Count | Should -BeGreaterOrEqual 3
    }

    It 'retries every download and every gallery install' {
        $bare = @($script:Calls | Where-Object { $_.Name -in @('Invoke-WebRequest', 'Install-Module') -and -not (Test-InsideRetry -Node $_.Node) } |
            ForEach-Object { "$($_.File):$($_.Line) $($_.Name)" })

        $bare | Should -BeNullOrEmpty
    }

    It 'retries every version manager and sdkmanager step except the named local ones' {
        $bare = foreach ($call in $script:Calls) {
            if ($call.Name -notin @('Invoke-ManagedTool', 'Invoke-AndroidSdkManager')) { continue }
            if (Test-InsideRetry -Node $call.Node) { continue }
            if (@($script:LocalSteps | Where-Object { $call.Text.Contains($_) }).Count -gt 0) { continue }
            "$($call.File):$($call.Line) $($call.Text)"
        }

        @($bare) | Should -BeNullOrEmpty
    }
}

Describe 'docs/manual/windows/install.ps1 follows the same retry rule' {

    # The manual script cannot import the wizard's files, so it carries its own copy of the rule. Its
    # functions are lifted out of its syntax tree, because loading the script would run it.
    BeforeAll {
        $script:ManualScript = Join-Path $script:RepoRoot 'docs\manual\windows\install.ps1'
        $parseErrors = $null
        $script:ManualAst = [System.Management.Automation.Language.Parser]::ParseFile($script:ManualScript, [ref]$null, [ref]$parseErrors)
        if ($parseErrors) { throw "install.ps1 does not parse: $($parseErrors[0].Message)" }
        $wanted = @('Invoke-InstallWithRetry', 'Format-Literal', 'Get-WingetArgument', 'Get-InstallExpression', 'New-ElevatedScript')
        $definitions = @($script:ManualAst.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $wanted -contains $node.Name
        }, $true))
        if ($definitions.Count -ne $wanted.Count) {
            throw "Expected $($wanted.Count) function definitions in install.ps1 and found $($definitions.Count): $(@($definitions | ForEach-Object Name) -join ', ')"
        }
        foreach ($definition in $definitions) {
            . ([scriptblock]::Create($definition.Extent.Text))
        }

        # Stand-ins for both managers, defined as text so the same definitions can travel into the
        # child process the elevated step starts. Each records its call and fails the first
        # ManualFailures installs.
        $script:ManagerStubs = @'
$global:ManualCalls = [System.Collections.Generic.List[string]]::new()
function winget { $global:ManualCalls.Add("winget $($args -join ' ')"); if ($args[0] -eq 'source') { $global:LASTEXITCODE = 0; return }; if ($global:ManualFailures -gt 0) { $global:ManualFailures--; $global:LASTEXITCODE = 1; return 'Installer failed' }; $global:LASTEXITCODE = 0 }
function choco { $global:ManualCalls.Add("choco $($args -join ' ')"); if ($args[0] -eq 'cache') { $global:LASTEXITCODE = 0; return }; if ($args[0] -eq 'list') { $global:LASTEXITCODE = 0; if ($global:ManualInstalled -contains $args[-1]) { return "$($args[-1])|1.0.0" }; return }; if ($global:ManualFailures -gt 0) { $global:ManualFailures--; $global:LASTEXITCODE = 1; return 'The remote file either does not exist' }; $global:LASTEXITCODE = 0; if ($global:ManualSilent -gt 0) { $global:ManualSilent--; return 'Chocolatey installed 0/0 packages.' }; $global:ManualInstalled += @($args[1]) }
'@
    }

    BeforeEach {
        . ([scriptblock]::Create($script:ManagerStubs))
        $global:ManualFailures = 0
        $global:ManualSilent = 0
        $global:ManualInstalled = @()
        Mock Start-Sleep { $global:ManualCalls.Add("wait $Seconds") }
        Mock Write-Host { }
    }

    AfterAll {
        Remove-Item -LiteralPath Function:\global:winget, Function:\global:choco -ErrorAction SilentlyContinue
    }

    It 'uses the attempt count and the pause of the wizard' {
        $defaults = @{}
        foreach ($p in (Get-Command Invoke-InstallWithRetry).ScriptBlock.Ast.Body.ParamBlock.Parameters) {
            if ($p.DefaultValue) { $defaults[$p.Name.VariablePath.UserPath] = $p.DefaultValue.Extent.Text }
        }
        $defaults['Retries'] | Should -Be ([string]$script:PackageRetryCount)
        $defaults['DelaySeconds'] | Should -Be ([string]$script:PackageRetryDelaySeconds)
    }

    It 'installs a winget package once, with no wait and no refresh, when it works' {
        $code = & ([scriptblock]::Create((Get-InstallExpression @{ Manager = 'winget'; Id = 'Git.Git'; Scope = 'machine' })))

        $code | Should -Be 0
        @($global:ManualCalls) | Should -Be @("winget install --exact --id Git.Git --source winget --silent --accept-source-agreements --accept-package-agreements --disable-interactivity --scope machine")
    }

    It 'waits, updates the package source, then installs a winget package again after a failure' {
        $global:ManualFailures = 1

        $code = & ([scriptblock]::Create((Get-InstallExpression @{ Manager = 'winget'; Id = '9WZDNCRFJ3TJ'; Source = 'msstore' })))

        $code | Should -Be 0
        @($global:ManualCalls | ForEach-Object { ($_ -split ' ')[0..1] -join ' ' }) | Should -Be @('winget install', 'wait 20', 'winget source', 'winget install')
        $global:ManualCalls[2] | Should -Be 'winget source update --name msstore --disable-interactivity'
    }

    It 'empties the Chocolatey HTTP cache before a Chocolatey retry' {
        $global:ManualFailures = 1

        $code = & ([scriptblock]::Create((Get-InstallExpression @{ Manager = 'choco'; Id = 'maven' })))

        $code | Should -Be 0
        @($global:ManualCalls) | Should -Be @('choco install maven -y --no-progress', 'wait 20', 'choco cache remove -y', 'choco install maven -y --no-progress', 'choco list --local-only --limit-output --exact maven')
    }

    It 'retries a Chocolatey package that exits 0 without being installed, and fails it when that never changes' {
        $global:ManualSilent = 1

        $retried = & ([scriptblock]::Create((Get-InstallExpression @{ Manager = 'choco'; Id = 'hwinfo.install' })))

        $retried | Should -Be 0
        @($global:ManualCalls) | Should -Be @('choco install hwinfo.install -y --no-progress', 'choco list --local-only --limit-output --exact hwinfo.install', 'wait 20', 'choco cache remove -y', 'choco install hwinfo.install -y --no-progress', 'choco list --local-only --limit-output --exact hwinfo.install')

        $global:ManualSilent = 99
        $never = & ([scriptblock]::Create((Get-InstallExpression @{ Manager = 'choco'; Id = 'dart-sdk' })))

        $never | Should -Be 1
        @($global:ManualCalls | Where-Object { $_ -eq 'choco install dart-sdk -y --no-progress' }).Count | Should -Be 4
    }

    It 'names a package that fails every one of its four attempts and returns its exit code' {
        $global:ManualFailures = 99

        $code = & ([scriptblock]::Create((Get-InstallExpression @{ Manager = 'winget'; Id = 'Git.Git' })))

        $code | Should -Be 1
        @($global:ManualCalls | Where-Object { $_ -like 'winget install *' }).Count | Should -Be 4
        @($global:ManualCalls | Where-Object { $_ -like 'winget source *' }).Count | Should -Be 3
        Should -Invoke Write-Host -ParameterFilter { "$Object" -like '*Git.Git failed all 4 attempts*' }
    }

    It 'treats winget answering already installed as success, without a retry' {
        function global:winget { $global:ManualCalls.Add("winget $($args -join ' ')"); $global:LASTEXITCODE = -1978335189 }

        $code = & ([scriptblock]::Create((Get-InstallExpression @{ Manager = 'winget'; Id = 'Git.Git' })))

        $code | Should -Be 0
        $global:ManualCalls.Count | Should -Be 1
    }

    It 'carries the retry into the elevated window, which counts a package that failed every attempt' {
        $pwsh = (Get-Process -Id $PID).Path
        $lines = @(
            $script:ManagerStubs
            'function Start-Sleep { param($Seconds) }'
            '$global:ManualFailures = 1'
            "if (($(Get-InstallExpression @{ Manager = 'choco'; Id = 'maven' })) -ne 0) { `$failed++ }"
            '$global:ManualFailures = 99'
            "if (($(Get-InstallExpression @{ Manager = 'choco'; Id = 'gradle' })) -ne 0) { `$failed++ }"
        )
        $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes((New-ElevatedScript -Lines $lines)))

        $out = & $pwsh -NoProfile -NonInteractive -EncodedCommand $encoded 2>&1

        $LASTEXITCODE | Should -Be 1 -Because "maven succeeds on its retry and gradle fails all four attempts: $($out -join ' ')"
        "$out" | Should -BeLike '*gradle failed all 4 attempts*'
    }

    It 'sends every install in the script through the retry' {
        $text = Get-Content -LiteralPath $script:ManualScript -Raw
        $text | Should -Not -Match '(?m)^\s*& winget @arguments' -Because 'the plain winget loop must go through Get-InstallExpression'
        $text | Should -Not -Match 'choco install \$\(' -Because 'the Chocolatey lines must go through Get-InstallExpression'
        $text | Should -Match "Invoke-InstallWithRetry -Package 'Chocolatey'" -Because 'the Chocolatey bootstrap is a download as well'
    }
}
