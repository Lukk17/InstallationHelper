<#
.SYNOPSIS
    Reports every Pester It block that builds a path with Join-Path from a child holding a forward slash and then expects that forward slash in one of its own assertions.

.DESCRIPTION
    The reasoning, and the failure that prompted this, are in pester_path_separators.sh next to it.

    Prints one line per finding as "<file>:<line>: It '<name>' expects '<a/b>' from '<child>', which
    Join-Path at line <n> writes with a backslash on Windows", then one line
    "READ files=<n> its=<n> joins=<n> slashed=<n>". Exit status is always 0: the caller decides what a
    finding means.

.PARAMETER Path
    The Pester files to parse.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0, ValueFromRemainingArguments)] [ValidateNotNullOrEmpty()] [string[]] $Path
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$comparison = '^[IC](eq|ne|like|notlike|match|notmatch)$'

function Test-JoinPathCommand([System.Management.Automation.Language.Ast] $Node) {
    return ($Node -is [System.Management.Automation.Language.CommandAst] -and $Node.GetCommandName() -eq 'Join-Path')
}

# A string is an expectation when it is an operand of a comparison, or sits anywhere inside a Should
# command, its -ParameterFilter included. A Join-Path child inside Should builds a path, it expects none.
function Test-IsExpectation([System.Management.Automation.Language.Ast] $Node) {
    $parent = $Node.Parent
    if (Test-JoinPathCommand $parent) { return $false }
    if ($parent -is [System.Management.Automation.Language.BinaryExpressionAst] -and $parent.Operator.ToString() -match $comparison) { return $true }
    for ($up = $parent; $null -ne $up; $up = $up.Parent) {
        if ($up -is [System.Management.Automation.Language.CommandAst] -and $up.GetCommandName() -eq 'Should') { return $true }
    }
    return $false
}

$files = 0
$its = 0
$joins = 0
$slashed = 0
$findings = [System.Collections.Generic.List[string]]::new()

foreach ($file in $Path) {
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path -LiteralPath $file).ProviderPath, [ref]$null, [ref]$errors)
    if ($errors) {
        $findings.Add("${file}: does not parse, $($errors[0].Message)")
        continue
    }
    $files++

    $itCommands = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'It' }, $true)
    foreach ($itCommand in $itCommands) {
        $bodies = @($itCommand.CommandElements | Where-Object { $_ -is [System.Management.Automation.Language.ScriptBlockExpressionAst] })
        if ($bodies.Count -eq 0) { continue }
        $its++
        $name = @($itCommand.CommandElements | Select-Object -Skip 1 | Where-Object { $_ -is [System.Management.Automation.Language.StringConstantExpressionAst] } | Select-Object -First 1)
        $itName = if ($name.Count -gt 0) { $name[0].Value } else { '' }

        foreach ($body in $bodies) {
            $children = [System.Collections.Generic.List[System.Management.Automation.Language.StringConstantExpressionAst]]::new()
            foreach ($join in $body.FindAll({ param($n) Test-JoinPathCommand $n }, $true)) {
                $joins++
                $withSlash = @($join.CommandElements | Select-Object -Skip 1 | Where-Object { $_ -is [System.Management.Automation.Language.StringConstantExpressionAst] -and $_.Value.Contains('/') })
                if ($withSlash.Count -gt 0) { $slashed++ }
                foreach ($child in $withSlash) { $children.Add($child) }
            }
            if ($children.Count -eq 0) { continue }

            $strings = $body.FindAll({ param($n) $n -is [System.Management.Automation.Language.StringConstantExpressionAst] -or $n -is [System.Management.Automation.Language.ExpandableStringExpressionAst] }, $true)
            foreach ($string in $strings) {
                if (-not (Test-IsExpectation $string)) { continue }
                $hit = $null
                foreach ($child in $children) {
                    $segments = $child.Value -split '/'
                    for ($i = 0; $i -lt $segments.Count - 1 -and -not $hit; $i++) {
                        if (-not $segments[$i] -or -not $segments[$i + 1]) { continue }
                        $pair = $segments[$i] + '/' + $segments[$i + 1]
                        if ($string.Value.IndexOf($pair, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
                            $hit = "${file}:$($string.Extent.StartLineNumber): It '$itName' expects '$pair' from '$($child.Value)', which Join-Path at line $($child.Extent.StartLineNumber) writes with a backslash on Windows"
                        }
                    }
                    if ($hit) { break }
                }
                if ($hit) { $findings.Add($hit) }
            }
        }
    }
}

foreach ($finding in $findings) { Write-Output $finding }
Write-Output "READ files=$files its=$its joins=$joins slashed=$slashed"
