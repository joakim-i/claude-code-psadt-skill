#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
<#
    Tests for scripts/_GraphCommon.ps1 - the shared Graph helpers (extracted from the three Graph scripts).
    These are the safety net for the de-duplication refactor: they prove Invoke-Graph still retries only
    transient failures and that the PS7-safe Retry-After / StatusCode reads work for both header shapes.
#>

BeforeAll {
    . (Join-Path $PSScriptRoot '..\scripts\_GraphCommon.ps1')

    # Build an ErrorRecord-like object whose .Exception.Response mimics a failed HTTP response.
    function New-FakeHttpError {
        param([int]$Status, $Headers)
        $resp = [pscustomobject]@{ StatusCode = [System.Net.HttpStatusCode]$Status; Headers = $Headers }
        $ex = [System.Exception]::new("HTTP $Status")
        $ex | Add-Member -NotePropertyName Response -NotePropertyValue $resp -Force
        # An ErrorRecord wraps the exception; Get-Graph* read $_.Exception.*
        return [System.Management.Automation.ErrorRecord]::new($ex, 'FakeHttp', 'NotSpecified', $null)
    }
}

Describe 'Get-GraphStatusCode' {
    It 'returns the integer status when a response is present' {
        (Get-GraphStatusCode (New-FakeHttpError -Status 429 -Headers @{})) | Should -Be 429
        (Get-GraphStatusCode (New-FakeHttpError -Status 503 -Headers @{})) | Should -Be 503
    }
    It 'returns $null when there is no response (e.g. raw HttpRequestException)' {
        $ex = [System.Exception]::new('boom')
        $err = [System.Management.Automation.ErrorRecord]::new($ex, 'NoResp', 'NotSpecified', $null)
        (Get-GraphStatusCode $err) | Should -BeNullOrEmpty
    }
}

Describe 'Get-GraphRetryAfterSeconds' {
    It 'parses the PS5.1 string header form (Headers[''Retry-After''])' {
        $err = New-FakeHttpError -Status 429 -Headers @{ 'Retry-After' = '5' }
        (Get-GraphRetryAfterSeconds $err) | Should -Be 5
    }
    It 'parses the PS7 strongly-typed RetryAfter.Delta form' {
        $headers = [pscustomobject]@{ RetryAfter = [pscustomobject]@{ Delta = [TimeSpan]::FromSeconds(7); Date = $null } }
        $err = New-FakeHttpError -Status 429 -Headers $headers
        (Get-GraphRetryAfterSeconds $err) | Should -Be 7
    }
    It 'returns 0 when no Retry-After is present' {
        (Get-GraphRetryAfterSeconds (New-FakeHttpError -Status 500 -Headers @{})) | Should -Be 0
    }
}

Describe 'Invoke-Graph retry behaviour' {
    BeforeEach { Mock Start-Sleep {} -ModuleName $null }

    It 'retries a 429 then succeeds (transient)' {
        $script:calls = 0
        Mock Invoke-RestMethod {
            $script:calls++
            if ($script:calls -lt 3) { throw (New-FakeHttpError -Status 429 -Headers @{ 'Retry-After' = '1' }) }
            return [pscustomobject]@{ ok = $true }
        }
        $r = Invoke-Graph -Method GET -Uri 'https://graph/x' -Headers @{}
        $r.ok | Should -BeTrue
        $script:calls | Should -Be 3
    }

    It 'retries 5xx as transient' {
        $script:calls = 0
        Mock Invoke-RestMethod {
            $script:calls++
            if ($script:calls -lt 2) { throw (New-FakeHttpError -Status 503 -Headers @{}) }
            return [pscustomobject]@{ ok = $true }
        }
        (Invoke-Graph -Method GET -Uri 'https://graph/x' -Headers @{}).ok | Should -BeTrue
        $script:calls | Should -Be 2
    }

    It 'does NOT retry a 4xx (e.g. 403) - throws immediately' {
        $script:calls = 0
        Mock Invoke-RestMethod { $script:calls++; throw (New-FakeHttpError -Status 403 -Headers @{}) }
        { Invoke-Graph -Method POST -Uri 'https://graph/x' -Body @{ a = 1 } -Headers @{} } | Should -Throw
        $script:calls | Should -Be 1
    }

    It 'gives up after 4 attempts on persistent 5xx' {
        $script:calls = 0
        Mock Invoke-RestMethod { $script:calls++; throw (New-FakeHttpError -Status 500 -Headers @{}) }
        { Invoke-Graph -Method GET -Uri 'https://graph/x' -Headers @{} } | Should -Throw
        $script:calls | Should -Be 4
    }
}

Describe 'Get-GraphErr' {
    It 'extracts the .error object from a JSON body in ErrorDetails (PS7 path)' {
        $ex = [System.Exception]::new('bad')
        $err = [System.Management.Automation.ErrorRecord]::new($ex, 'X', 'NotSpecified', $null)
        $err.ErrorDetails = [System.Management.Automation.ErrorDetails]::new('{"error":{"code":"BadRequest","message":"nope"}}')
        $e = Get-GraphErr $err
        $e.code | Should -Be 'BadRequest'
        $e.message | Should -Be 'nope'
    }
    It 'falls back to a synthetic object when there is no parseable body' {
        $ex = [System.Exception]::new('raw failure')
        $err = [System.Management.Automation.ErrorRecord]::new($ex, 'X', 'NotSpecified', $null)
        (Get-GraphErr $err).code | Should -Be 'Unknown'
    }
}
