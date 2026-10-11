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

Describe 'Install-WingetPackage retries a failed install once' {

    # A stub winget rather than a Pester mock, because the code under test never calls winget through
    # PowerShell: Invoke-BoundedWinget starts a process and reads two redirected files, so a mock
    # would prove nothing about the path that actually runs. The stub answers the `list` probe as
    # "not installed" and appends a line per install attempt, so the line count is the attempt count,
    # which is the only state that survives between two separate processes.
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
if not exist "$marker1" (
  echo x>"$marker1"
  set ATTEMPT=1
) else if not exist "$marker2" (
  echo x>"$marker2"
  set ATTEMPT=2
) else (
  echo x>"$marker3"
  set ATTEMPT=3
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
if [ ! -f "$marker1" ]; then
  echo x > "$marker1"; attempt=1
elif [ ! -f "$marker2" ]; then
  echo x > "$marker2"; attempt=2
else
  echo x > "$marker3"; attempt=3
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
        # error under Set-StrictMode -Version Latest, which is defect class 4 in AGENTS.md and was
        # hit by the first draft of these very tests.
        function global:Get-StubAttemptCount {
            param([Parameter(Mandatory)] [string] $Directory)
            return @(Get-ChildItem -LiteralPath $Directory -Filter 'a?' -File -ErrorAction SilentlyContinue).Count
        }
    }

    It 'reports installed when the first attempt fails and the second succeeds' {
        $dir = New-StubDirectory
        try {
            $stub = New-WingetStub -Directory $dir -FailFirstN 1

            $r = Install-WingetPackage -WingetPath $stub.Path -PackageId 'Vendor.Thing' -RetryPauseSeconds 0

            $r.Status | Should -Be 'installed'
            $r.Detail | Should -BeLike '*attempt 2*'
            $r.Detail | Should -BeLike '*3221225477*' -Because 'the first failure stays visible even though the package landed'
            Get-StubAttemptCount -Directory $dir | Should -Be 2
        } finally { Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'stops at two attempts and names both when neither works' {
        $dir = New-StubDirectory
        try {
            $stub = New-WingetStub -Directory $dir -FailFirstN 9

            $r = Install-WingetPackage -WingetPath $stub.Path -PackageId 'Vendor.Thing' -RetryPauseSeconds 0

            $r.Status | Should -Be 'failed'
            $r.Detail | Should -BeLike '*attempt 2 of 2*'
            Get-StubAttemptCount -Directory $dir | Should -Be 2 -Because 'two attempts, never three'
        } finally { Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'does not retry a package that installs first time' {
        $dir = New-StubDirectory
        try {
            $stub = New-WingetStub -Directory $dir -FailFirstN 0

            $r = Install-WingetPackage -WingetPath $stub.Path -PackageId 'Vendor.Thing' -RetryPauseSeconds 0

            $r.Status | Should -Be 'installed'
            $r.Detail | Should -BeNullOrEmpty
            Get-StubAttemptCount -Directory $dir | Should -Be 1
        } finally { Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'honours -Attempts 1, which is the no-retry behaviour this replaced' {
        $dir = New-StubDirectory
        try {
            $stub = New-WingetStub -Directory $dir -FailFirstN 9

            $r = Install-WingetPackage -WingetPath $stub.Path -PackageId 'Vendor.Thing' -Attempts 1 -RetryPauseSeconds 0

            $r.Status | Should -Be 'failed'
            $r.Detail | Should -Not -BeLike '*the first said*'
            Get-StubAttemptCount -Directory $dir | Should -Be 1
        } finally { Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'never retries a timeout, because the deadline exists to stop a hang' -Tag 'Slow' {
        $dir = New-StubDirectory
        try {
            $stub = New-WingetStub -Directory $dir -FailFirstN 0 -Hang

            # 30 is the smallest deadline the parameter accepts. Two attempts would cost twice that,
            # which is exactly what a deadline is meant to prevent.
            $r = Install-WingetPackage -WingetPath $stub.Path -PackageId 'Vendor.Thing' -TimeoutSeconds 30 -RetryPauseSeconds 0

            $r.Status | Should -Be 'failed'
            $r.Detail | Should -BeLike '*gave up after 30 seconds*'
            Get-StubAttemptCount -Directory $dir | Should -Be 1
        } finally { Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue }
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
        @($global:NpmStubCalls | Where-Object { $_ -eq 'install -g @opencode/cli' }).Count | Should -Be 2
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

    It 'returns true after installing a module that was missing' {
        Mock Get-Module { }
        Mock Install-Module { }
        Mock Write-Host { }

        Install-ConsoleGuiTools | Should -BeTrue
        Should -Invoke Install-Module -Times 1 -Exactly
    }

    It 'returns false instead of throwing when the install fails, and says what the run does instead' {
        Mock Get-Module { }
        Mock Install-Module { throw 'No match was found for the specified search criteria and module name' }
        Mock Write-Host { }

        { Install-ConsoleGuiTools } | Should -Not -Throw
        Install-ConsoleGuiTools | Should -BeFalse
        Should -Invoke Write-Host -ParameterFilter { "$Object" -like '*Could not install Microsoft.PowerShell.ConsoleGuiTools*No match was found*' }
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
    # on their own until 2026-10-11, which is defect class 2 in AGENTS.md waiting to happen. Every
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
    # start until 2026-10-11, which is defect class 2 in AGENTS.md: three implementations of one
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
