<#
.SYNOPSIS
    Reports every variable that a PowerShell file reads without ever assigning it.

.DESCRIPTION
    The reasoning, and the failure that prompted this, are in powershell_variables.sh next to it.
    This half exists as its own file rather than as a here-string inside the shell check because a
    PowerShell script quoted inside bash is the kind of thing that ends up with one escaping bug
    nobody notices until it silently matches nothing.

    Prints the single word "clean", or one line per finding as "<file>:<line>: $name is read but
    never assigned". Exit status is always 0: the caller decides what a finding means.

.PARAMETER Path
    Directory to walk. Every *.ps1 under it is parsed.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $Path
)

$ErrorActionPreference = 'Stop'

# PowerShell provides these itself, so reading one without assigning it is normal.
$automatic = @(
    '_', 'psitem', 'args', 'true', 'false', 'null', 'input', 'foreach', 'switch', 'matches',
    'pscmdlet', 'psboundparameters', 'psscriptroot', 'pscommandpath', 'myinvocation', 'error',
    'lastexitcode', 'pwd', 'host', 'home', 'pid', 'profile', 'psversiontable', 'stacktrace',
    'iswindows', 'islinux', 'ismacos', 'iscoreclr', 'nestedpromptlevel', 'executioncontext',
    'shellid', 'psculture', 'psuiculture', 'psedition', 'ofs', 'psdefaultparametervalues',
    'erroractionpreference', 'warningpreference', 'verbosepreference', 'debugpreference',
    'informationpreference', 'progresspreference', 'confirmpreference', 'whatifpreference',
    'psnativecommanduseerroractionpreference', 'this'
)

$findings = [System.Collections.Generic.List[string]]::new()

foreach ($file in (Get-ChildItem -LiteralPath $Path -Recurse -Filter '*.ps1')) {
    $errs = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$null, [ref]$errs)
    if ($errs) {
        $findings.Add("$($file.Name): does not parse, $($errs[0].Message)")
        continue
    }

    $assigned = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)

    # An assignment binds the name, and so does every scope-qualified spelling of it.
    foreach ($a in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] }, $true)) {
        foreach ($v in $a.Left.FindAll({ param($n) $n -is [System.Management.Automation.Language.VariableExpressionAst] }, $true)) {
            $null = $assigned.Add($v.VariablePath.UserPath)
            $null = $assigned.Add(($v.VariablePath.UserPath -split ':')[-1])
        }
    }
    foreach ($p in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.ParameterAst] }, $true)) {
        $null = $assigned.Add($p.Name.VariablePath.UserPath)
    }
    foreach ($f in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.ForEachStatementAst] }, $true)) {
        $null = $assigned.Add($f.Variable.VariablePath.UserPath)
    }
    foreach ($d in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.DataStatementAst] }, $true)) {
        if ($d.Variable) { $null = $assigned.Add($d.Variable) }
    }
    # [ref]$x writes through the reference, which is how Parser::ParseFile hands back its errors.
    foreach ($c in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.ConvertExpressionAst] }, $true)) {
        if ($c.Type.TypeName.Name -eq 'ref' -and
            $c.Child -is [System.Management.Automation.Language.VariableExpressionAst]) {
            $null = $assigned.Add($c.Child.VariablePath.UserPath)
        }
    }

    foreach ($v in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.VariableExpressionAst] }, $true)) {
        if ($v.VariablePath.IsDriveQualified) { continue }        # $env:PATH and friends
        $name = $v.VariablePath.UserPath
        $bare = ($name -split ':')[-1]
        if ($automatic -contains $bare.ToLower()) { continue }
        if ($assigned.Contains($name) -or $assigned.Contains($bare)) { continue }
        $findings.Add("$($file.Name):$($v.Extent.StartLineNumber): `$$name is read but never assigned")
    }
}

if ($findings.Count -gt 0) {
    $findings | Sort-Object -Unique | ForEach-Object { Write-Output $_ }
} else {
    Write-Output 'clean'
}
