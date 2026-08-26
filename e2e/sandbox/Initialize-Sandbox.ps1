<#
.SYNOPSIS
    Runs inside Windows Sandbox at logon. Installs winget and PowerShell 7, then prints the wizard
    command.

.DESCRIPTION
    Windows PowerShell 5.1 only, deliberately. This is the first thing that runs in a fresh
    sandbox and PowerShell 7 is not there yet, so nothing here may use 7-only syntax. That is why
    there is no ternary, no null-coalescing and no `#Requires -Version 7`.

    Two things a sandbox lacks that the wizard needs.

    There is no Microsoft Store, so winget is absent and cannot be installed from the Store. It is
    installed here from the winget-cli release assets instead, which is the route Microsoft
    publishes for machines with no Store: the dependency bundle first, then the App Installer
    package itself. Without it 80 of the 89 Windows mappings cannot install at all.

    And setup.ps1 declares `#Requires -Version 7`, while a sandbox ships 5.1. PowerShell 7 comes
    from winget once winget works, rather than from a second download route, so there is one way in
    and it is the same one the wizard itself uses for everything else.

    It installs nothing else and it does not run the wizard. An install of the whole software set
    is over an hour of downloading and that is a decision to take deliberately, not something a
    window should start doing because it opened.

.PARAMETER Software
    Only used to build the command line this prints at the end.
#>
[CmdletBinding()]
param(
    [ValidateSet('defaults', 'all', 'none')]
    [string] $Software = 'defaults'
)

$ErrorActionPreference = 'Stop'

# Both matter on 5.1. TLS 1.2 is not always the default there and GitHub serves nothing else, and
# the progress bar makes Invoke-WebRequest an order of magnitude slower in this host.
[Net.ServicePointManager]::SecurityProtocol = 3072
$ProgressPreference = 'SilentlyContinue'

function Write-Step { param([string]$Text) Write-Host ">> $Text" -ForegroundColor Cyan }
function Write-Bad  { param([string]$Text) Write-Host "!! $Text" -ForegroundColor Red }

$transcript = 'C:\out\sandbox-bootstrap.log'
try { Start-Transcript -Path $transcript -Force | Out-Null } catch { Write-Host "(no transcript: $($_.Exception.Message))" }

Write-Host ''
Write-Host '  Windows Sandbox, throwaway, same build as the host machine.'
Write-Host "  Repository mapped read only at C:\repo. Anything copied to C:\out survives the sandbox."
Write-Host ''

# --- winget ------------------------------------------------------------------------------------
if (Get-Command winget -ErrorAction SilentlyContinue) {
    Write-Step 'winget is already here'
} else {
    Write-Step 'Installing winget from the winget-cli release, because a sandbox has no Store'
    $base = 'https://github.com/microsoft/winget-cli/releases/latest/download'
    $deps = 'C:\winget-deps.zip'
    $bundle = 'C:\winget.msixbundle'
    try {
        Invoke-WebRequest -Uri "$base/DesktopAppInstaller_Dependencies.zip" -OutFile $deps -UseBasicParsing
        Invoke-WebRequest -Uri "$base/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle" -OutFile $bundle -UseBasicParsing

        Expand-Archive -Path $deps -DestinationPath 'C:\winget-deps' -Force
        # The dependency bundle carries one folder per architecture. Only this machine's own
        # architecture is installed, because Add-AppxPackage on a foreign one fails and the failure
        # says nothing useful.
        $arch = 'x64'
        if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { $arch = 'arm64' }
        $dependencyDir = Join-Path 'C:\winget-deps' $arch
        if (Test-Path -LiteralPath $dependencyDir) {
            Get-ChildItem -LiteralPath $dependencyDir -Filter *.appx | ForEach-Object {
                Write-Host "   dependency: $($_.Name)"
                Add-AppxPackage -Path $_.FullName
            }
        } else {
            Write-Bad "The dependency bundle has no $arch folder, so winget may fail to register."
        }

        Add-AppxPackage -Path $bundle
        Write-Step 'winget installed'
    } catch {
        Write-Bad "winget could not be installed: $($_.Exception.Message)"
        Write-Bad 'Without it only the 9 Chocolatey mappings can install. Chocolatey still bootstraps itself.'
    }
}

# --- PowerShell 7 ------------------------------------------------------------------------------
$pwshPath = 'C:\Program Files\PowerShell\7\pwsh.exe'
if (Test-Path -LiteralPath $pwshPath) {
    Write-Step 'PowerShell 7 is already here'
} elseif (Get-Command winget -ErrorAction SilentlyContinue) {
    Write-Step 'Installing PowerShell 7, because setup.ps1 requires it and a sandbox ships 5.1'
    & winget install --id Microsoft.PowerShell --exact --source winget --silent `
        --accept-package-agreements --accept-source-agreements
    if (-not (Test-Path -LiteralPath $pwshPath)) {
        Write-Bad 'PowerShell 7 did not land where the wizard expects it. Look above for what winget said.'
    }
} else {
    Write-Bad 'No winget, so PowerShell 7 cannot be installed this way and the wizard cannot start.'
}

try { Stop-Transcript | Out-Null } catch { }

# --- what to run next --------------------------------------------------------------------------
Write-Host ''
Write-Host '  Ready. Nothing has been installed from the software set yet.' -ForegroundColor Green
Write-Host ''
Write-Host '  Run the wizard, non-interactively:' -ForegroundColor Yellow
Write-Host "    & '$pwshPath' C:\repo\setup\setup.ps1 -NonInteractive -AllowAdministrator -Software $Software" -ForegroundColor Yellow
Write-Host ''
Write-Host '  Or drive the checklist by hand, which no automated run ever exercises:' -ForegroundColor Yellow
Write-Host "    & '$pwshPath' C:\repo\setup\setup.ps1 -AllowAdministrator" -ForegroundColor Yellow
Write-Host ''
Write-Host '  -AllowAdministrator is required here: the sandbox user is an administrator and the'
Write-Host '  wizard refuses an elevated run without it.'
Write-Host ''
Write-Host '  Afterwards, keep the evidence, because this whole machine disappears when you close it:'
Write-Host '    Copy-Item $env:USERPROFILE\installation_verify.log C:\out\'
Write-Host ''
Write-Host '  What this sandbox cannot prove: anything needing a reboot, the optional features, WSL,'
Write-Host '  any hypervisor, and the seven Microsoft Store ids. See C:\repo\e2e\manual_test_matrix.md.'
Write-Host ''
