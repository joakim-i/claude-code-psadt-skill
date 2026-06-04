BeforeAll { . "$PSScriptRoot/_helpers.ps1" }
Describe 'Get-PsadtConfig' {
    BeforeEach {
        $script:root = New-TempSkillRoot
        $script:run  = { & (Join-Path $script:root 'scripts/Get-PsadtConfig.ps1') -SkillRoot $script:root }
    }
    AfterEach  { Remove-TempSkillRoot $script:root }

    It 'reports Exists=$false and all required fields missing when no config' {
        $r = & $script:run
        $r.Exists | Should -BeFalse
        $r.Missing | Should -Contain 'paths.packageRoot'
        $r.Missing | Should -Contain 'author.person'
    }

    It 'returns Exists=$true and empty Missing for a complete config' {
        @{
            version=1
            paths=@{ packageRoot='c:\p'; outputRoot='c:\o'; intuneWinAppUtil='c:\t\x.exe' }
            language=@{ script='EN'; dossier='DE' }
            author=@{ person='Pat'; company='PHAT' }
        } | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $script:root 'config.json')
        $r = & $script:run
        $r.Exists | Should -BeTrue
        $r.Missing | Should -BeNullOrEmpty
    }

    It 'requires intune fields only when uploadEnabled is true' {
        @{
            version=1
            paths=@{ packageRoot='c:\p'; outputRoot='c:\o'; intuneWinAppUtil='c:\t\x.exe' }
            language=@{ script='EN'; dossier='DE' }
            author=@{ person='Pat'; company='PHAT' }
            intune=@{ uploadEnabled=$true; secretRef='secret.dpapi' }
        } | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $script:root 'config.json')
        $r = & $script:run
        $r.Missing | Should -Contain 'intune.tenantId'
        $r.Missing | Should -Contain 'intune.secret'
    }
}
