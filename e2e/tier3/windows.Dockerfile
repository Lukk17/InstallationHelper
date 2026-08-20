# Tier 3 base image for Windows scenario runs.
#
# This one is not like the other four, and it is worth knowing why before using it.
#
# What it can test: the logic in setup/windows/WindowsSoftware.ps1, on a clean Windows with
# no packages installed and nothing inherited from a developer machine. That is the parsing
# of the toggle and mapping YAML, the plan that comes out of it, the winget resolution
# failure path, the pinned values adapter in setup/pinned_values/PinnedValues.psm1, and the
# Chocolatey bootstrap. Driven by Pester, see e2e/tier3/windows/WindowsSoftware.Tests.ps1.
#
# What it cannot test: any winget install. winget ships as an MSIX package and depends on the
# AppX deployment subsystem, which Server Core and Nano Server do not have. As of 2026-08-16
# that is 82 of the 89 Windows mappings, 7 of those 82 being Microsoft Store product ids which
# need the Store itself and are even further out of reach. Chocolatey works because it is only
# PowerShell and NuGet, which covers the remaining 7 mappings. There is no way around this in a
# container, so winget installation needs a real Windows machine or a hosted runner.
#
# Nor can it test setup/windows/WindowsCustomInstalls.ps1 beyond its planning. Java is four
# winget JDKs, Node and Flutter are Chocolatey managers followed by commands that download
# gigabytes, and Gridcoin and Razer Cortex run downloaded installers. Only the Chocolatey half
# of that could run here at all.
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

# Python from the official embeddable zip, for the same reason PowerShell comes from a zip: a
# self-contained extract that cannot half-succeed and needs no installer service. It is here
# because setup/pinned_values/pinned_values.py is the only reader of the pinned versions and
# download locations, and PinnedValues.psm1 shims PowerShell onto it. With no interpreter in the
# image those tests would report SKIP, and a skip proves nothing, so this step is not optional.
#
# tomllib is what the reader needs and it entered the standard library in 3.11. The embeddable
# distribution carries it inside python313.zip, verified by importing it rather than assumed.
# Note that this distribution ships python.exe and no python3.exe, which is one of the reasons the
# adapter tries several names before giving up.
ARG PYTHON_VERSION=3.13.7
RUN Invoke-WebRequest -Uri \"https://www.python.org/ftp/python/$env:PYTHON_VERSION/python-$env:PYTHON_VERSION-embed-amd64.zip\" -OutFile C:\python.zip ; \
    Expand-Archive -Path C:\python.zip -DestinationPath 'C:\Python' ; \
    Remove-Item C:\python.zip

# On PATH so the adapter finds it by name, which is what it does on a real machine too.
RUN $p = [Environment]::GetEnvironmentVariable('PATH', 'Machine') ; \
    [Environment]::SetEnvironmentVariable('PATH', ($p + ';C:\Python'), 'Machine')

# Proven at build time rather than discovered by a failing test: an image that cannot read the
# pinned values is a broken image, and this fails the build instead of six tests.
RUN & 'C:\Python\python.exe' -c \"import tomllib\" ; \
    if ($LASTEXITCODE -ne 0) { throw 'the embeddable Python cannot import tomllib, so the pinned values reader cannot run here' }

# Deliberately absent, and each for a reason.
#
#   winget      cannot work here, no AppX subsystem. Tests assert it is absent and that the
#               resolver fails with a usable message rather than a null reference.
#   Chocolatey  the script under test is supposed to bootstrap it. Preinstalling it would
#               hide that step breaking, the same reasoning as base-devel on the Arch image.
#   the repo    copied in at run time by the driver, so an edit does not need a rebuild.

WORKDIR C:\work
CMD ["pwsh", "-NoProfile", "-Command", "Write-Output 'idle, driven by Invoke-WindowsE2E.ps1'; Start-Sleep -Seconds 86400"]
