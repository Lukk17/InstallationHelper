#Requires -Version 7.2
<#
.SYNOPSIS
    Pester tests for the native Windows installer, run inside a clean Windows container.

.DESCRIPTION
    These assert behaviour on a machine with nothing installed, which is the state a real user
    starts from and the one a developer machine can never reproduce. They deliberately do not
    install any winget package, because winget cannot run on Server Core at all: it ships as
    an MSIX and needs the AppX subsystem. See e2e/tier3/windows.Dockerfile.

    Run through e2e/tier3/Invoke-WindowsE2E.ps1 rather than directly, so the repository is in
    the expected place and Docker is in the right mode.
#>

BeforeAll {
    # The repository root is found by walking up from this file rather than assumed, because this
    # suite runs from two places that put it at a different depth: a real checkout, where it sits
    # three levels under the root at e2e\tier3\windows, and the tier 3 container, where
    # Invoke-WindowsE2E.ps1 copies just this one file straight to C:\work with none of that nesting.
    # E2E_REPO_ROOT stays as an explicit override, which is how the container script already pins
    # it to C:\work, but nothing here hardcodes C:\work or any other path as the only place this can
    # find the repository, so a developer running this straight from a checkout gets a real answer
    # instead of a path that only exists inside a container.
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

    if (-not (Test-Path -LiteralPath $script:PsFile)) {
        throw "WindowsSoftware.ps1 not found at $script:PsFile. Was the repository copied in?"
    }
    if (-not (Test-Path -LiteralPath $script:CustomInstallFile)) {
        throw "WindowsCustomInstalls.ps1 not found at $script:CustomInstallFile. Was the repository copied in?"
    }
    . $script:PsFile
    . $script:CustomInstallFile
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

Describe 'Get-PinnedVersion' {

    It 'resolves a plain scalar pin' {
        $tmp = Join-Path $TestDrive 'plain.yaml'
        @('---', 'java21_id: "21.0.11-tem"') | Set-Content -LiteralPath $tmp
        $v = Get-PinnedVersion -VersionsPath $tmp
        $v['java21_id'] | Should -Be '21.0.11-tem'
    }

    It 'resolves a {{ ref }} pin to the value it points at' {
        $tmp = Join-Path $TestDrive 'ref.yaml'
        @('---', 'java21_id: "21.0.11-tem"', 'default_java: "{{ java21_id }}"') | Set-Content -LiteralPath $tmp
        $v = Get-PinnedVersion -VersionsPath $tmp
        $v['default_java'] | Should -Be '21.0.11-tem'
    }

    # This is the shape default_java is written in today, and the one Install-TemurinJdk's
    # own comments call out by name as reachable without a typo. A reference to a key that
    # is not in the file must stay visibly unresolved rather than resolving to an empty
    # string, so a caller downstream sees "{{ nope }}" and can say so instead of silently
    # treating it as blank.
    It 'leaves an unresolved {{ ref }} pin intact rather than blanking it' {
        $tmp = Join-Path $TestDrive 'unresolved.yaml'
        @('---', 'default_java: "{{ nope }}"') | Set-Content -LiteralPath $tmp
        $v = Get-PinnedVersion -VersionsPath $tmp
        $v['default_java'] | Should -Be '{{ nope }}'
    }

    # A pin absent from the file entirely, as opposed to present with a bad value. There is
    # nothing to resolve, so this must not throw, and the caller sees it through
    # ContainsKey rather than a KeyNotFoundException.
    It 'has no entry for a pin that is absent from the file' {
        $tmp = Join-Path $TestDrive 'absent.yaml'
        @('---', 'java21_id: "21.0.11-tem"') | Set-Content -LiteralPath $tmp
        $v = Get-PinnedVersion -VersionsPath $tmp
        $v.ContainsKey('java25_id') | Should -BeFalse
    }

    It 'reads a pin whose value is empty as an empty string, not as absent' {
        $tmp = Join-Path $TestDrive 'empty.yaml'
        @('---', 'flutter_channel: ""') | Set-Content -LiteralPath $tmp
        $v = Get-PinnedVersion -VersionsPath $tmp
        $v.ContainsKey('flutter_channel') | Should -BeTrue
        $v['flutter_channel'] | Should -Be ''
    }

    It 'throws rather than returning an empty map when the versions file does not exist' {
        { Get-PinnedVersion -VersionsPath (Join-Path $TestDrive 'nope.yaml') } |
            Should -Throw -ExpectedMessage '*not found*'
    }

    It 'parses the real group_vars/versions.yaml without throwing' {
        $versionsPath = Join-Path $script:AnsibleDir 'group_vars\versions.yaml'
        $v = Get-PinnedVersion -VersionsPath $versionsPath
        $v['default_java'] | Should -Not -Match '\{\{'
    }
}

Describe 'Get-TemurinMajor' {

    It 'extracts the major version out of an SDKMAN identifier' {
        Get-TemurinMajor -SdkmanId '21.0.11-tem' | Should -Be '21'
    }

    It 'extracts a two-digit major version' {
        Get-TemurinMajor -SdkmanId '25.0.3-tem' | Should -Be '25'
    }

    # The malformed shape Install-TemurinJdk's own comments warn is reachable without a
    # typo: an unresolved "{{ ref }}" pin passed straight through, since Get-PinnedVersion
    # deliberately leaves it that way instead of blanking it.
    It 'throws on a pin that is still an unresolved {{ ref }}' {
        { Get-TemurinMajor -SdkmanId '{{ default_java }}' } |
            Should -Throw -ExpectedMessage "*'{{ default_java }}'*"
    }

    # The error must name the value that failed, so whoever reads it can go straight to the
    # offending line in versions.yaml instead of guessing which of four pins broke.
    It 'names the malformed value in the thrown error' {
        { Get-TemurinMajor -SdkmanId 'tem-21.0.11' } |
            Should -Throw -ExpectedMessage "*'tem-21.0.11'*"
    }

    It 'throws on an identifier with no major version at all' {
        { Get-TemurinMajor -SdkmanId 'not-a-version' } |
            Should -Throw -ExpectedMessage "*'not-a-version'*"
    }

    # ValidateNotNullOrEmpty rejects this before the function body runs, which is the
    # "missing pin" shape: a key present in versions.yaml with nothing after the colon.
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
