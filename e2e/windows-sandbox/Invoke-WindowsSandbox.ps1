#Requires -Version 7.2
<#
.SYNOPSIS
    Writes a Windows Sandbox configuration for this repository and starts the sandbox.

.DESCRIPTION
    Windows Sandbox is a throwaway desktop built from the files of the Windows already running on
    this machine. It is the same build and the same edition, so there is no image to download and
    no version to match, and everything inside it is destroyed when the window closes.

    That is what makes it the right place to run the Windows wizard by hand. It is client Windows,
    so the packages a Server runner has to skip install properly. It has the AppX subsystem, so
    winget works once it is installed, which is 80 of the 89 Windows mappings. And it is a real
    desktop, so the interactive checklist can be clicked through, which no automated run has ever
    done.

    What it cannot do is in e2e/manual_test_matrix.md, and the two hard walls are worth knowing
    before you start: a sandbox cannot reboot, and it has no nested virtualisation, so the optional
    features, WSL and anything else wanting a restart or a hypervisor stay out of reach.

    The configuration file cannot be committed ready to use, because a .wsb carries absolute host
    paths and has no variables. So it is generated here from where this script sits, which means it
    is correct on any machine and for any checkout.

.PARAMETER Software
    Passed through to the message the sandbox prints at logon, so the wizard command is ready to
    paste. Nothing is installed automatically: an install of the whole set is over an hour of
    downloads and that is a decision, not a side effect of opening a window.

.PARAMETER MemoryInMB
    Memory for the sandbox. The installers here are heavy and the default is stingy.

.PARAMETER ConfigOnly
    Write the .wsb and print where it is, without starting anything.

.EXAMPLE
    pwsh e2e/windows-sandbox/Invoke-WindowsSandbox.ps1

.EXAMPLE
    pwsh e2e/windows-sandbox/Invoke-WindowsSandbox.ps1 -Software all -MemoryInMB 12288
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet('defaults', 'all', 'none')]
    [string] $Software = 'defaults',

    [ValidateRange(2048, 65536)]
    [int] $MemoryInMB = 8192,

    [switch] $ConfigOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$SandboxDir = Split-Path -Parent $PSCommandPath
$RepoRoot   = Split-Path -Parent (Split-Path -Parent $SandboxDir)
$OutDir     = Join-Path $RepoRoot 'e2e\runs\windows-sandbox'
$ConfigPath = Join-Path $OutDir 'installation_helper.wsb'

function Write-Step { param([string]$Text) Write-Host ">> $Text" -ForegroundColor Cyan }
function Write-Bad  { param([string]$Text) Write-Host "!! $Text" -ForegroundColor Red }

if (-not (Test-Path -LiteralPath (Join-Path $RepoRoot 'setup\setup.ps1'))) {
    Write-Bad "Could not find setup\setup.ps1 above $SandboxDir, so this is not a checkout of this repository."
    exit 2
}

New-Item -ItemType Directory -Path $OutDir -Force | Out-Null

# The mapped repository is read only on purpose. A run inside the sandbox must not be able to
# change the tree it is testing, which is the same rule the Linux container harness follows by
# copying rather than mounting. The second mapping is the way anything gets out: the sandbox's own
# disk is destroyed on close, so a transcript or a verification log has to be copied to C:\out.
$config = @"
<Configuration>
  <VGpu>Default</VGpu>
  <Networking>Default</Networking>
  <MemoryInMB>$MemoryInMB</MemoryInMB>
  <MappedFolders>
    <MappedFolder>
      <HostFolder>$RepoRoot</HostFolder>
      <SandboxFolder>C:\repo</SandboxFolder>
      <ReadOnly>true</ReadOnly>
    </MappedFolder>
    <MappedFolder>
      <HostFolder>$OutDir</HostFolder>
      <SandboxFolder>C:\out</SandboxFolder>
      <ReadOnly>false</ReadOnly>
    </MappedFolder>
  </MappedFolders>
  <LogonCommand>
    <Command>C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -NoExit -NoProfile -ExecutionPolicy Bypass -File C:\repo\e2e\windows-sandbox\Initialize-Sandbox.ps1 -Software $Software</Command>
  </LogonCommand>
</Configuration>
"@

Set-Content -LiteralPath $ConfigPath -Value $config -Encoding utf8
Write-Step "Configuration written to $ConfigPath"
Write-Host "   repository mapped read only at C:\repo"
Write-Host "   results folder mapped read write at C:\out, which is $OutDir on this machine"
Write-Host "   memory: $MemoryInMB MB, wizard command prepared for -Software $Software"

if ($ConfigOnly) {
    Write-Host ''
    Write-Host 'Not starting anything, -ConfigOnly was given. Open the file above to start the sandbox.'
    exit 0
}

# Asked rather than assumed, and never enabled from here. Turning a Windows feature on is a change
# to the machine with a reboot attached, so this names the command and stops.
$sandboxExe = Join-Path $env:SystemRoot 'System32\WindowsSandbox.exe'
if (-not (Test-Path -LiteralPath $sandboxExe)) {
    Write-Bad "Windows Sandbox is not present on this machine ($sandboxExe is missing)."
    Write-Host ''
    Write-Host '  It needs Windows 10 or 11, Pro or Enterprise. On a supported edition it is an'
    Write-Host '  optional feature, and this is the command that turns it on, from an elevated'
    Write-Host '  PowerShell. It asks for a reboot. Run it yourself rather than expecting this'
    Write-Host '  script to change your machine:'
    Write-Host ''
    Write-Host '    Enable-WindowsOptionalFeature -Online -FeatureName Containers-DisposableClientVM -All'
    exit 2
}

if (-not $PSCmdlet.ShouldProcess($ConfigPath, 'start Windows Sandbox')) { exit 0 }

Write-Step 'Starting Windows Sandbox'
& $sandboxExe $ConfigPath
if ($LASTEXITCODE -ne 0) {
    Write-Bad "Windows Sandbox exited $LASTEXITCODE without starting."
    Write-Host '  The usual cause is the optional feature being present but not enabled. See the'
    Write-Host '  Enable-WindowsOptionalFeature line above, and note it wants a reboot.'
    exit 1
}

Write-Host ''
Write-Host 'The sandbox window is opening. It bootstraps winget and PowerShell 7 at logon and then'
Write-Host 'prints the wizard command, so nothing installs until you run it yourself.'
Write-Host "Anything you copy to C:\out inside the sandbox appears in $OutDir out here."
