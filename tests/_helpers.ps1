function New-TempSkillRoot {
    $root = Join-Path ([System.IO.Path]::GetTempPath()) ("psadtskill_" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $root -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $root 'scripts')    -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $root 'tools')      -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $root 'references') -Force | Out-Null
    $srcScripts = Join-Path $PSScriptRoot '..\scripts'
    if (Test-Path $srcScripts) { Copy-Item "$srcScripts\*" (Join-Path $root 'scripts') -Force }
    return $root
}
function Remove-TempSkillRoot([string]$Path) {
    if ($Path -and (Test-Path $Path)) { Remove-Item $Path -Recurse -Force -ErrorAction SilentlyContinue }
}

# Returns the source text of a single named function defined inside a script file, WITHOUT executing the
# script's (side-effecting) top-level body. Used to unit-test internal helpers of script-style .ps1 files:
#   . ([scriptblock]::Create((Get-ScriptFunctionText -Path $s -Name 'Resolve-GroupName')))
function Get-ScriptFunctionText {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Name)
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$null, [ref]$null)
    $fn = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $Name }, $true) |
        Select-Object -First 1
    if (-not $fn) { throw "Function [$Name] not found in $Path" }
    return $fn.Extent.Text
}
