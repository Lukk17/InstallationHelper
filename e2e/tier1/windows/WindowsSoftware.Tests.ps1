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
        # be deleted, and the wizard has to carry on with the disk it already had.
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
