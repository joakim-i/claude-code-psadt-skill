BeforeAll { . "$PSScriptRoot/_helpers.ps1" }
Describe 'Update-PsadtSkill' {
    BeforeEach {
        $script:root = New-TempSkillRoot
        Set-Content (Join-Path $script:root 'CHANGELOG.md') "# Changelog`n`n## 0.4.0 - x`n- local"
        $script:run = { param($extra) . (Join-Path $script:root 'scripts/Update-PsadtSkill.ps1') -SkillRoot $script:root @extra }
    }
    AfterEach { Remove-TempSkillRoot $script:root }

    It 'reports UpToDate when remote version equals local' {
        Mock -CommandName Invoke-RestMethod -MockWith { "# Changelog`n## 0.4.0 - y`n- remote" }
        $r = & $script:run @{}
        $r.LocalVersion    | Should -Be '0.4.0'
        $r.RemoteVersion   | Should -Be '0.4.0'
        $r.UpdateAvailable | Should -BeFalse
        $r.Action          | Should -Be 'UpToDate'
    }

    It 'flags UpdateAvailable but does NOT apply without -Apply' {
        Mock -CommandName Invoke-RestMethod -MockWith { "# Changelog`n## 0.5.0 - y`n- newer" }
        Mock -CommandName Invoke-WebRequest -MockWith { }
        $r = & $script:run @{}
        $r.UpdateAvailable | Should -BeTrue
        $r.Applied         | Should -BeFalse
        Should -Invoke Invoke-WebRequest -Times 0
        (Get-Content (Join-Path $script:root 'CHANGELOG.md') -Raw) | Should -Match '0\.4\.0'  # unchanged
    }

    It 'reports CheckFailed when GitHub is unreachable' {
        Mock -CommandName Invoke-RestMethod -MockWith { throw 'no network' }
        $r = & $script:run @{}
        $r.UpdateAvailable | Should -BeFalse
        $r.Action          | Should -Be 'CheckFailed'
        $r.Error           | Should -Match 'GitHub'
    }

    It 'applies via the archive method and updates the local version' {
        Mock -CommandName Invoke-RestMethod -MockWith { "# Changelog`n## 0.5.0 - y`n- newer" }
        Mock -CommandName Invoke-WebRequest -MockWith { }
        Mock -CommandName Expand-Archive -MockWith {
            $ex = Join-Path ([IO.Path]::GetTempPath()) 'psadt-skill-extract\claude-code-psadt-skill-main'
            New-Item $ex -ItemType Directory -Force | Out-Null
            Set-Content (Join-Path $ex 'CHANGELOG.md') "# Changelog`n## 0.5.0 - y`n- newer"
        }
        $r = & $script:run @{ Apply = $true }
        $r.Method   | Should -Be 'archive'   # temp root has no .git
        $r.Applied  | Should -BeTrue
        $r.LocalVersion | Should -Be '0.5.0'
        (Get-Content (Join-Path $script:root 'CHANGELOG.md') -Raw) | Should -Match '0\.5\.0'
    }
}
