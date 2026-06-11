#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
<#
    Tests for scripts/Get-GraphToken.ps1 (DPAPI client-secret path). Verifies the DPAPI round-trip
    (Set -> stored -> decrypted -> used in the token request) and that the decrypted secret is NEVER
    part of the returned object. The token endpoint is mocked - no network.

    Note: DPAPI is CurrentUser-bound, so this round-trips only as the user running the test (by design).
#>

BeforeAll {
    . (Join-Path $PSScriptRoot '_helpers.ps1')
    $script:TokenScript = (Resolve-Path (Join-Path $PSScriptRoot '..\scripts\Get-GraphToken.ps1')).Path
}

Describe 'Get-GraphToken (DPAPI secret path)' {
    It 'decrypts the DPAPI secret, requests a token, and returns Token/Tenant/Client (no secret leak)' {
        $tmp = New-TempSkillRoot
        try {
            @{ version = 1; intune = @{ tenantId = 'tenant-123'; clientId = 'client-456'; secretRef = 'secret.dpapi'; uploadEnabled = $true } } |
                ConvertTo-Json | Set-Content -Path (Join-Path $tmp 'config.json') -Encoding UTF8
            # Store a DPAPI secret exactly as Set-PsadtConfig would.
            $secret = 'super-secret-value'
            ConvertFrom-SecureString (ConvertTo-SecureString $secret -AsPlainText -Force) |
                Set-Content -Path (Join-Path $tmp 'secret.dpapi') -Encoding ASCII -NoNewline

            Mock Invoke-RestMethod {
                return [pscustomobject]@{ access_token = 'fake-access-token'; expires_in = 3600 }
            } -ParameterFilter { $Uri -like '*oauth2/v2.0/token' }

            $result = & $script:TokenScript -SkillRoot $tmp

            $result.Token | Should -Be 'fake-access-token'
            $result.TenantId | Should -Be 'tenant-123'
            $result.ClientId | Should -Be 'client-456'
            # The decrypted secret must have reached the token request (proves the DPAPI round-trip).
            Should -Invoke Invoke-RestMethod -Times 1 -Exactly -ParameterFilter { $Body.client_secret -eq 'super-secret-value' }
            # ...but must NOT be exposed on the returned object.
            ($result.PSObject.Properties.Value -join '|') | Should -Not -Match ([regex]::Escape($secret))
        }
        finally { Remove-TempSkillRoot $tmp }
    }

    It 'throws a clear error when tenantId/clientId are missing' {
        $tmp = New-TempSkillRoot
        try {
            @{ version = 1; intune = @{ uploadEnabled = $true } } | ConvertTo-Json |
                Set-Content -Path (Join-Path $tmp 'config.json') -Encoding UTF8
            { & $script:TokenScript -SkillRoot $tmp -ErrorAction Stop } | Should -Throw -ExpectedMessage '*missing*'
        }
        finally { Remove-TempSkillRoot $tmp }
    }
}
