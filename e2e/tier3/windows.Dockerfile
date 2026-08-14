# Tier 3 base image for Windows scenario runs.
#
# This one is not like the other four, and it is worth knowing why before using it.
#
# What it can test: the logic in setup/windows/WindowsSoftware.ps1, on a clean Windows with
# no packages installed and nothing inherited from a developer machine. That is the parsing
# of the toggle and mapping YAML, the plan that comes out of it, the winget resolution
# failure path, and the Chocolatey bootstrap. Driven by Pester, see
# e2e/tier3/windows/WindowsSoftware.Tests.ps1.
#
# What it cannot test: any winget install. winget ships as an MSIX package and depends on the
# AppX deployment subsystem, which Server Core and Nano Server do not have. That is 77 of the
# 83 Windows mappings. Chocolatey works because it is only PowerShell and NuGet, which covers
# the remaining 6. There is no way around this in a container, so winget installation needs a
# real Windows machine or a hosted runner.
#
# It also cannot test the wizard's own interface. setup.ps1 uses Out-ConsoleGridView from
# ConsoleGuiTools, which needs a real console.
#
# Running it requires Docker Desktop switched to Windows containers, and that switch turns
# OFF the Linux daemon, so no Arch, Debian, Ubuntu or Fedora scenario can run at the same
# time. Use e2e/tier3/Invoke-WindowsE2E.ps1, which checks for the right mode and says so
# rather than failing obscurely.
#
# ltsc2025 is build 26100, the closest published Server Core to this project's Windows 11
# host at build 26200. Prefer Hyper-V isolation over process isolation, because process
# isolation wants the container and host builds to match closely and these do not.
FROM mcr.microsoft.com/windows/servercore:ltsc2025

SHELL ["powershell", "-NoProfile", "-Command", "$ErrorActionPreference = 'Stop'; $ProgressPreference = 'SilentlyContinue';"]

# PowerShell 7 from the zip rather than the MSI. An MSI in a container needs the Windows
# Installer service and leaves a rollback footprint, while the zip is a self-contained
# extract that cannot half-succeed. Version pinned for the same reason the Linux base images
# are: a moving toolchain means the harness quietly starts testing something else.
ARG PWSH_VERSION=7.4.6
RUN Invoke-WebRequest -Uri \"https://github.com/PowerShell/PowerShell/releases/download/v$env:PWSH_VERSION/PowerShell-$env:PWSH_VERSION-win-x64.zip\" -OutFile C:\pwsh.zip ; \
    Expand-Archive -Path C:\pwsh.zip -DestinationPath 'C:\Program Files\PowerShell\7' ; \
    Remove-Item C:\pwsh.zip

# On PATH so the driver and the tests can call pwsh without a full path.
RUN $p = [Environment]::GetEnvironmentVariable('PATH', 'Machine') ; \
    [Environment]::SetEnvironmentVariable('PATH', ($p + ';C:\Program Files\PowerShell\7'), 'Machine')

# Pester 5 is the test runner. Installed at build time so a run needs no network of its own,
# which also means a failing test is a failing test rather than a flaky gallery fetch.
ARG PESTER_VERSION=5.6.1
RUN & 'C:\Program Files\PowerShell\7\pwsh.exe' -NoProfile -Command \
      \"Set-PSRepository -Name PSGallery -InstallationPolicy Trusted; \
        Install-Module -Name Pester -RequiredVersion $env:PESTER_VERSION -Force -SkipPublisherCheck -Scope AllUsers\"

# Deliberately absent, and each for a reason.
#
#   winget      cannot work here, no AppX subsystem. Tests assert it is absent and that the
#               resolver fails with a usable message rather than a null reference.
#   Chocolatey  the script under test is supposed to bootstrap it. Preinstalling it would
#               hide that step breaking, the same reasoning as base-devel on the Arch image.
#   the repo    copied in at run time by the driver, so an edit does not need a rebuild.

WORKDIR C:\work
CMD ["pwsh", "-NoProfile", "-Command", "Write-Output 'idle, driven by Invoke-WindowsE2E.ps1'; Start-Sleep -Seconds 86400"]
