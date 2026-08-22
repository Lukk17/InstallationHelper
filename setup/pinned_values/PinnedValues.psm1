#Requires -Version 7.2
<#
.SYNOPSIS
    The PowerShell end of the pinned values port.

.DESCRIPTION
    Import this module and ask for pinned values by name:

        Import-Module ./setup/pinned_values/PinnedValues.psm1
        $url = Get-PinnedValue -Key gridcoin_win_installer_url

    Nothing here parses the pinned values file. setup/pinned_values/pinned_values.py is the only
    reader in the repository and the only place allowed to resolve a reference, and this module is a
    shim over its command line, so PowerShell cannot drift from what Ansible and the shell callers
    see. Three hand-written parsers of the file this replaced is what made that rule necessary, and
    e2e/tier1/pinned_values.sh fails the gate if a fourth appears.

    Two functions, matching the two things a caller ever needs:

      Get-PinnedValueMap  every pinned value at once, resolved, as a hashtable
      Get-PinnedValue     one value, throwing when nothing pins that name

    Absence and emptiness stay different answers. A name pinned to an empty string comes back as an
    empty string, and only an unpinned name throws. The Windows installer depends on that: it tells
    a pin nobody wrote from a pin that renders to nothing, and reports each as its own named result.

    The interpreter is located once per session, in the order python3, python, py -3, then
    wsl.exe python3. Finding none throws and names what to install, because a silently empty map
    would make five Windows installs quietly do nothing instead of saying why.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# A native command that exits non-zero becomes a terminating error, everywhere except the scopes
# below that read an exit code as an answer. This setting is inert on PowerShell 7.2 and 7.3, where
# it was still an experimental feature, and assigning it there quietly creates an ordinary variable
# that nothing consults. The requirement above stays at 7.2 rather than rising to 7.4, because this
# repository supports machines that ship 7.2 and refusing to import on them would be worse than the
# gap. What actually makes the module safe on every supported version is that every callsite reads
# $LASTEXITCODE itself instead of trusting this line to raise.
$PSNativeCommandUseErrorActionPreference = $true

# The reader sits beside this module, which is the same anchoring the reader uses for its own data
# file, so no caller of either one carries a copy of a path.
$script:CorePath = Join-Path $PSScriptRoot 'pinned_values.py'

# The reader's exit code for a name nobody pinned. It is an answer rather than a crash, which is
# why the callsites below read exit codes instead of letting a non-zero exit throw.
$script:AbsentExitCode = 3

# One token with no spaces, so it survives being handed to wsl.exe unchanged. tomllib is what the
# reader needs and it entered the standard library in Python 3.11. Running the interpreter rather
# than trusting its name also rejects the Windows App Execution Alias stub, which is on PATH as
# python3.exe on a machine with no Store Python and then fails to start at all.
$script:VersionProbe = 'import sys;sys.exit(sys.version_info<(3,11))'

# Located once per session. The search costs up to four process launches, and this module is
# imported by a wizard that asks for pinned values more than once.
$script:Interpreter = $null

# The failure is remembered for the same reason the success is. On a machine with no Python at all
# every call would otherwise pay the whole four-launch search again before throwing, and the wizard
# asks more than once. The sentence is built once, where the search gives up, and replayed from
# here, so the second throw says exactly what the first one said.
$script:InterpreterFailure = $null

function Test-PinnedValuesInterpreter {
    <#
    .SYNOPSIS
        Whether a candidate interpreter really runs and is Python 3.11 or newer.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $FilePath,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [string[]] $Prefix
    )

    # An exit code is the answer here, not a failure, so the native command preference is turned off
    # for this scope alone. A launch that fails outright, which is exactly what the App Execution
    # Alias stub does, raises instead of exiting, and is caught.
    $PSNativeCommandUseErrorActionPreference = $false
    try {
        & $FilePath @Prefix '-c' $script:VersionProbe *> $null
        return ($LASTEXITCODE -eq 0)
    } catch {
        Write-Verbose "$FilePath is on PATH but did not run: $($_.Exception.Message)"
        return $false
    }
}

function Convert-PinnedValuesPathForWsl {
    <#
    .SYNOPSIS
        The reader's path as WSL sees it, with the exit code of the conversion.

    .DESCRIPTION
        A Windows path means nothing inside WSL, and wslpath is asked rather than the drive letter
        rewritten by hand, because a checkout on a network path, or a mount configured somewhere
        other than /mnt, would make a hand-rolled conversion point at nothing.

        This is a function rather than four lines inside the search loop because a PowerShell loop
        body is not its own scope. Relaxing the preferences below in the loop leaves them relaxed
        for the rest of the enclosing function, so from the first WSL candidate onward any later
        native call would run without the protection the top of this module sets up. A function
        body does scope them, so they end where this returns.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $FilePath,
        [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $WindowsPath
    )

    # A non-zero exit is data here rather than a failure, and stderr is wanted because it carries
    # the reason WSL could not see the path. Merging stderr into stdout with 2>&1 while
    # $ErrorActionPreference is 'Stop' is what turns the first stderr line of a native command into
    # a terminating NativeCommandError, so both preferences are relaxed together in this scope.
    $PSNativeCommandUseErrorActionPreference = $false
    $ErrorActionPreference = 'Continue'

    $printed = (& $FilePath 'wslpath' '-a' ($WindowsPath -replace '\\', '/') 2>&1) -join ''
    return [pscustomobject]@{
        ExitCode = [int] $LASTEXITCODE
        Text     = [string] $printed
    }
}

function Resolve-PinnedValuesInterpreter {
    <#
    .SYNOPSIS
        The interpreter that runs the reader, found once and remembered for the session.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    if ($script:Interpreter) { return $script:Interpreter }

    # A search that already failed is replayed, not repeated. Four launches that found nothing will
    # find nothing again inside one session, because the remedy the message names is to install
    # Python and reopen the shell, and repeating them is how a machine with no Python pays four
    # process launches for every pinned value read.
    if ($script:InterpreterFailure) { throw $script:InterpreterFailure }

    $candidates = @(
        [pscustomobject]@{ FilePath = 'python3'; Prefix = @();          Wsl = $false }
        [pscustomobject]@{ FilePath = 'python';  Prefix = @();          Wsl = $false }
        [pscustomobject]@{ FilePath = 'py';      Prefix = @('-3');      Wsl = $false }
        [pscustomobject]@{ FilePath = 'wsl.exe'; Prefix = @('python3'); Wsl = $true }
    )

    foreach ($candidate in $candidates) {
        $label = (@($candidate.FilePath) + $candidate.Prefix) -join ' '

        # No -CommandType filter. A python3 surfaced as a function or an alias is how a virtual
        # environment is commonly put on a shell, and refusing it here would send the search off to
        # WSL on a machine that has a working interpreter right in front of it. Whether the
        # candidate actually runs, and is new enough, is settled by Test-PinnedValuesInterpreter
        # below, which is the only thing that matters.
        if (-not (Get-Command $candidate.FilePath -ErrorAction SilentlyContinue)) {
            Write-Verbose "$label is not on PATH"
            continue
        }
        if (-not (Test-PinnedValuesInterpreter -FilePath $candidate.FilePath -Prefix $candidate.Prefix)) {
            Write-Verbose "$label is not a usable Python 3.11 or newer"
            continue
        }

        $core = $script:CorePath
        if ($candidate.Wsl) {
            $conversion = Convert-PinnedValuesPathForWsl -FilePath $candidate.FilePath -WindowsPath $script:CorePath
            if ($conversion.ExitCode -ne 0 -or -not $conversion.Text) {
                Write-Verbose "$label cannot see $($script:CorePath): $($conversion.Text)"
                continue
            }
            $core = $conversion.Text
        }

        $script:Interpreter = [pscustomobject]@{
            FilePath = [string] $candidate.FilePath
            Prefix   = [string[]] $candidate.Prefix
            Core     = [string] $core
            Label    = [string] $label
        }
        Write-Verbose "pinned values will be read with '$label'"
        return $script:Interpreter
    }

    $script:InterpreterFailure = (
        "pinned values: no Python 3.11 or newer could be found, having tried python3, python, " +
        "py -3 and wsl.exe python3, so $script:CorePath cannot be read. Install Python 3.11 or " +
        "newer from https://www.python.org/downloads/windows/ and reopen the shell, or make " +
        "python3 reachable inside WSL.")
    throw $script:InterpreterFailure
}

function Invoke-PinnedValuesCore {
    <#
    .SYNOPSIS
        Runs the reader once and returns its exit code together with everything it printed.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string[]] $Argument
    )

    $interpreter = Resolve-PinnedValuesInterpreter

    # Both streams are wanted: the value on success, and the reader's own sentence on failure, which
    # is where the offending name and the file it was looked for in come from. As in the probe, a
    # non-zero exit is data rather than a terminating error, so the preference is off in this scope.
    #
    # $ErrorActionPreference is relaxed alongside it, and it has to be. Merging stderr into stdout
    # with 2>&1 while the 'Stop' from the top of this module is still in force is the shape that
    # turns the first stderr line of a native command into a terminating NativeCommandError, and
    # every failing read of this reader writes its sentence to stderr. Get-PinnedValue would then
    # throw a PowerShell complaint about a command having written to stderr, instead of reporting
    # exit 3 with the reader's own naming of the pin and the file it was looked for in.
    $PSNativeCommandUseErrorActionPreference = $false
    $ErrorActionPreference = 'Continue'
    $printed = & $interpreter.FilePath @($interpreter.Prefix) $interpreter.Core @Argument 2>&1
    $status = $LASTEXITCODE

    return [pscustomobject]@{
        ExitCode = [int] $status
        # Rejoined here because --json prints a multi-line document, and this is the only place that
        # can put it back together. The separator cannot change a value: the reader refuses at load
        # any value holding a line feed or a carriage return, so --get prints exactly one line and
        # --sh one line per pin, and no pinned value can straddle two of these elements. That closes
        # the platform separator question at the source rather than needing a second guard here.
        # Nothing downstream assumes otherwise either. Get-PinnedValue hands this text back
        # unchanged, and Get-PinnedValueMap only feeds it to ConvertFrom-Json, which reads either
        # line ending.
        Text     = (@($printed) | ForEach-Object { [string] $_ }) -join [Environment]::NewLine
    }
}

function Get-PinnedValueMap {
    <#
    .SYNOPSIS
        Every pinned value, fully resolved, as a hashtable of name to string.

    .DESCRIPTION
        The whole set in one call, for a caller that reads several values, or that needs to tell a
        pin nobody wrote from a pin that renders to nothing. No value contains a reference, because
        the reader resolves them all before printing and refuses to print one it could not resolve.

        Throws rather than returning an empty hashtable when no interpreter can be found or when the
        reader rejects the file. An empty map would read as "nothing is pinned" and turn a broken
        setup into a silent no-op.

    .EXAMPLE
        Import-Module ./setup/pinned_values/PinnedValues.psm1
        (Get-PinnedValueMap)['default_java']

        Prints the pinned Temurin identifier.

    .OUTPUTS
        System.Collections.Hashtable
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    $result = Invoke-PinnedValuesCore -Argument @('--json')
    if ($result.ExitCode -ne 0) {
        throw "pinned values: the reader exited $($result.ExitCode) instead of printing the set. $($result.Text)"
    }

    try {
        $parsed = $result.Text | ConvertFrom-Json -AsHashtable
    } catch {
        throw "pinned values: the reader printed something that is not JSON. $($_.Exception.Message)"
    }

    # Copied into a plain hashtable of strings rather than handed on as parsed. Callers declare
    # [hashtable] parameters and index it with a string name, and this keeps every value a string
    # instead of whatever a JSON scalar would otherwise convert to.
    $map = @{}
    foreach ($name in $parsed.Keys) { $map[$name] = [string] $parsed[$name] }

    Write-Verbose "read $($map.Count) pinned values with '$((Resolve-PinnedValuesInterpreter).Label)'"
    return $map
}

function Get-PinnedValue {
    <#
    .SYNOPSIS
        One pinned value, resolved.

    .DESCRIPTION
        Throws when nothing pins the name, naming both the name and the file it was looked for in,
        because an empty string handed back for an unpinned name is how a wrong download location
        reaches a real machine. A name pinned to an empty value returns the empty string, which is a
        different answer and stays one.

    .PARAMETER Key
        The pinned name, spelled as it is in the pins table.

    .EXAMPLE
        Get-PinnedValue -Key gridcoin_win_installer_url

        Prints the pinned Gridcoin installer location, with its version reference already resolved.

    .OUTPUTS
        System.String
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [ValidatePattern('^[A-Za-z0-9_]+$')]
        [string] $Key
    )

    $result = Invoke-PinnedValuesCore -Argument @('--get', $Key)

    if ($result.ExitCode -eq $script:AbsentExitCode) {
        throw "pinned values: $($result.Text)"
    }
    if ($result.ExitCode -ne 0) {
        throw "pinned values: reading '$Key' exited $($result.ExitCode). $($result.Text)"
    }

    return [string] $result.Text
}

function Get-PinnedChecksum {
    <#
    .SYNOPSIS
        The pinned checksum for one artefact, or nothing when none is pinned.

    .DESCRIPTION
        The same reader, the same single source, and the same distinction the pins themselves make:
        a name with no checksum is a legal answer and comes back as an empty string, while a broken
        or unreadable pinned values file throws. A caller that could not tell those apart would treat
        a corrupt file as "no verification wanted" and install whatever the URL returned.

        Returns the raw pinned string, which is `sha256:<hex>`. The caller splits it, because the
        algorithm is part of what was pinned rather than an assumption to make here.

    .PARAMETER Name
        The artefact name in the [checksums] table, which is the artefact rather than the toggle.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $Name
    )

    $result = Invoke-PinnedValuesCore -Argument @('--checksum', $Name)
    if ($result.ExitCode -eq 0) { return $result.Text.Trim() }
    if ($result.ExitCode -eq 3) { return '' }
    throw "reading the pinned checksum for '$Name' failed with exit $($result.ExitCode): $($result.Text)"
}

Export-ModuleMember -Function Get-PinnedValueMap, Get-PinnedValue, Get-PinnedChecksum
