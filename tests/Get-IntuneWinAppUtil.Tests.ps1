BeforeAll { . "$PSScriptRoot/_helpers.ps1" }
Describe 'Get-IntuneWinAppUtil' {
    BeforeEach {
        $script:root = New-TempSkillRoot
        $script:run  = { . (Join-Path $script:root 'scripts/Get-IntuneWinAppUtil.ps1') -SkillRoot $script:root }
    }
    AfterEach { Remove-TempSkillRoot $script:root }

    It 'downloads the exe when missing and records version' {
        Mock -CommandName Invoke-RestMethod -MockWith { @{ tag_name = 'v1.8.7' } }
        Mock -CommandName Invoke-WebRequest -MockWith { Set-Content (Join-Path $script:root 'tools/IntuneWinAppUtil.exe') 'MZ' }
        $r = & $script:run
        Should -Invoke Invoke-WebRequest -Times 1
        $r.Action  | Should -Be 'Downloaded'
        $r.Version | Should -Be 'v1.8.7'
        (Test-Path (Join-Path $script:root 'tools/IntuneWinAppUtil.exe')) | Should -BeTrue
    }

    It 'is a no-op when present and version matches config' {
        Set-Content (Join-Path $script:root 'tools/IntuneWinAppUtil.exe') 'MZ'
        @{ version=1; tooling=@{ intuneWinAppUtilVersion='v1.8.7' } } |
            ConvertTo-Json -Depth 5 | Set-Content (Join-Path $script:root 'config.json')
        Mock -CommandName Invoke-RestMethod -MockWith { @{ tag_name = 'v1.8.7' } }
        Mock -CommandName Invoke-WebRequest -MockWith { }
        $r = & $script:run
        Should -Invoke Invoke-WebRequest -Times 0
        $r.Action | Should -Be 'AlreadyCurrent'
    }
}
