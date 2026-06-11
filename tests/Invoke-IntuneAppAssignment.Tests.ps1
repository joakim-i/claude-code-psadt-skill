#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
<#
    Tests for scripts/Invoke-IntuneAppAssignment.ps1 - group-name resolution (the rules that bit us:
    no %intent% token, space-stripping) and the fail-fast when intune.groups is not configured.
#>

BeforeAll {
    . (Join-Path $PSScriptRoot '_helpers.ps1')
    $script:AssignScript = (Resolve-Path (Join-Path $PSScriptRoot '..\scripts\Invoke-IntuneAppAssignment.ps1')).Path

    # Pull Resolve-GroupName out of the script and define it here (without running the script body).
    . ([scriptblock]::Create((Get-ScriptFunctionText -Path $script:AssignScript -Name 'Resolve-GroupName')))
}

Describe 'Resolve-GroupName' {
    BeforeAll {
        $script:AppName = 'Norton Neo'   # tokens read these from the enclosing scope
        $script:AppVendor = 'Norton'
        $script:AppArch = 'x64'
        $script:AppVersion = '148.0.3893.97'
    }

    It 'substitutes %appname% and strips spaces' {
        Resolve-GroupName 'intune-win-app-required-%appname%' | Should -Be 'intune-win-app-required-NortonNeo'
    }
    It 'supports %appvendor%, %apparch% and %version% tokens' {
        Resolve-GroupName 'App-%appvendor%-%apparch%-%version%' | Should -Be 'App-Norton-x64-148.0.3893.97'
    }
    It 'is case-insensitive and supports the {Token} alias' {
        Resolve-GroupName 'g-{AppName}-%APPARCH%' | Should -Be 'g-NortonNeo-x64'
    }
    It 'leaves an unknown %intent% placeholder untouched (there is NO intent token)' {
        # The intent is the naming-template KEY, never a token - a %intent% would survive verbatim.
        Resolve-GroupName 'app-%intent%-%appname%' | Should -Be 'app-%intent%-NortonNeo'
    }
    It 'produces a name with no whitespace even from spacey input' {
        (Resolve-GroupName '  pre %appname% post ') -match '\s' | Should -BeFalse
    }
}

Describe 'intune.groups not configured' {
    It 'throws a clear error when the resolved config has no intune.groups' {
        $tmp = New-TempSkillRoot
        try {
            # Minimal config WITHOUT intune.groups -> the script must fail fast before any Graph call.
            @{ version = 1; intune = @{ uploadEnabled = $false } } | ConvertTo-Json |
                Set-Content -Path (Join-Path $tmp 'config.json') -Encoding UTF8
            { & $script:AssignScript -AppId '00000000-0000-0000-0000-000000000000' -AppName 'X' -SkillRoot $tmp -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*not enabled*'
        }
        finally { Remove-TempSkillRoot $tmp }
    }
}
