BeforeAll { . "$PSScriptRoot/_helpers.ps1" }
Describe 'Set-PsadtConfig' {
    BeforeEach {
        $script:root = New-TempSkillRoot
        $script:set  = { param($h) & (Join-Path $script:root 'scripts/Set-PsadtConfig.ps1') -SkillRoot $script:root @h }
    }
    AfterEach { Remove-TempSkillRoot $script:root }

    It 'creates config.json with nested values' {
        & $script:set @{ Updates = @{ 'paths.packageRoot'='c:\p'; 'author.person'='Pat' } }
        $cfg = Get-Content (Join-Path $script:root 'config.json') -Raw | ConvertFrom-Json
        $cfg.paths.packageRoot | Should -Be 'c:\p'
        $cfg.author.person     | Should -Be 'Pat'
        $cfg.version           | Should -Be 1
    }

    It 'merges into an existing config without dropping prior keys' {
        & $script:set @{ Updates = @{ 'paths.packageRoot'='c:\p' } }
        & $script:set @{ Updates = @{ 'author.company'='PHAT' } }
        $cfg = Get-Content (Join-Path $script:root 'config.json') -Raw | ConvertFrom-Json
        $cfg.paths.packageRoot | Should -Be 'c:\p'
        $cfg.author.company    | Should -Be 'PHAT'
    }

    It 'DPAPI-encrypts the secret to secret.dpapi and never to config.json' {
        $sec = ConvertTo-SecureString 'p@ss-w0rd!' -AsPlainText -Force
        & $script:set @{ Secret = $sec }
        $blob = Get-Content (Join-Path $script:root 'secret.dpapi') -Raw
        $blob | Should -Not -BeNullOrEmpty
        $blob | Should -Not -Match 'p@ss-w0rd'
        (Get-Content (Join-Path $script:root 'config.json') -Raw) | Should -Not -Match 'p@ss-w0rd'
        $back = ConvertTo-SecureString $blob
        [System.Net.NetworkCredential]::new('', $back).Password | Should -Be 'p@ss-w0rd!'
    }
}
