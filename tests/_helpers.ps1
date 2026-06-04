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
