# SCOPE NOTE: these tests exercise the in-process logic (loop, detection-state, exit-code mapping). The
# pwsh7 -> Windows PowerShell 5.1 re-exec branch (PSScheduledJob is 5.1-only) is bypassed via the
# PSADT_SYSTEMTEST_NOREEXEC backdoor and is intentionally NOT unit-tested here - it depends on a real
# elevated 5.1 host + Invoke-CommandAs and is covered by the manual DEV-VM run (SKILL.md Phase 6).
BeforeAll {
    . "$PSScriptRoot/_helpers.ps1"
    Import-Module PowerShellGet -ErrorAction SilentlyContinue
    function Invoke-CommandAs { param([switch]$AsSystem, $ScriptBlock, $ArgumentList) }  # stub so Mock can bind
    # Test the in-process logic on any host: bypass the pwsh7 -> WinPS 5.1 re-exec (real runs never set this).
    $env:PSADT_SYSTEMTEST_NOREEXEC = '1'
}
AfterAll { Remove-Item Env:\PSADT_SYSTEMTEST_NOREEXEC -ErrorAction SilentlyContinue }
Describe 'Invoke-PsadtSystemTest' {
    BeforeEach {
        $script:root   = New-TempSkillRoot
        $script:logdir = Join-Path $script:root 'logs'; New-Item $script:logdir -ItemType Directory -Force | Out-Null
        $script:pkg    = Join-Path $script:root 'pkg';  New-Item $script:pkg    -ItemType Directory -Force | Out-Null
        Set-Content (Join-Path $script:pkg 'Invoke-AppDeployToolkit.exe') 'stub'
        $script:invoke = {
            param($extra)
            $p = @{ PackagePath = $script:pkg; LogDirectory = $script:logdir; IsElevated = $true; SkillRoot = $script:root } + $extra
            . (Join-Path $script:root 'scripts/Invoke-PsadtSystemTest.ps1') @p
        }
    }
    AfterEach { Remove-TempSkillRoot $script:root }

    It 'throws when not elevated' {
        { . (Join-Path $script:root 'scripts/Invoke-PsadtSystemTest.ps1') -PackagePath $script:pkg -DeploymentType Install -IsElevated $false } |
            Should -Throw -ExpectedMessage '*ELEVATED*'
    }

    It 'self-heals the Invoke-CommandAs module when missing' {
        Mock Get-Module -MockWith { @() }
        Mock Install-Module -MockWith { }
        Mock Import-Module -MockWith { }
        Mock Invoke-CommandAs -MockWith { [pscustomobject]@{ DeployExitCode=0; DeployOutput='ok'; DetectExitCode=$null; DetectOutput=$null } }
        & $script:invoke @{ DeploymentType = 'Install' }
        Should -Invoke Install-Module -Times 1
    }

    It 'reports Success + installed for a clean install with detection' {
        Mock Get-Module -MockWith { [pscustomobject]@{ Name='Invoke-CommandAs' } }
        Mock Import-Module -MockWith { }
        Mock Invoke-CommandAs -MockWith { [pscustomobject]@{ DeployExitCode=0; DeployOutput='ok'; DetectExitCode=0; DetectOutput='Detected v1' } }
        Set-Content (Join-Path $script:logdir 'App_PSAppDeployToolkit_Install.log') "Installation complete`n[Info] done"
        $r = & $script:invoke @{ DeploymentType='Install'; DetectionScript='C:\det.ps1' }
        $r.Success        | Should -BeTrue
        $r.DetectionState | Should -Be 'installed'
        $r.ExitCode       | Should -Be 0
        $r.LogPath        | Should -Not -BeNullOrEmpty
    }

    It 'reports failure + error lines for a bad install' {
        Mock Get-Module -MockWith { [pscustomobject]@{ Name='Invoke-CommandAs' } }
        Mock Import-Module -MockWith { }
        Mock Invoke-CommandAs -MockWith { [pscustomobject]@{ DeployExitCode=1; DeployOutput='boom'; DetectExitCode=1; DetectOutput='' } }
        Set-Content (Join-Path $script:logdir 'App_PSAppDeployToolkit_Install.log') "starting`n[Error] something failed"
        $r = & $script:invoke @{ DeploymentType='Install'; DetectionScript='C:\det.ps1' }
        $r.Success        | Should -BeFalse
        $r.DetectionState | Should -Be 'not-installed'
        ($r.ErrorLines -join ' ') | Should -Match 'something failed'
    }

    It 'reports Success for a clean uninstall (detection shows not-installed)' {
        Mock Get-Module -MockWith { [pscustomobject]@{ Name='Invoke-CommandAs' } }
        Mock Import-Module -MockWith { }
        Mock Invoke-CommandAs -MockWith { [pscustomobject]@{ DeployExitCode=0; DeployOutput='removed'; DetectExitCode=0; DetectOutput='' } }
        Set-Content (Join-Path $script:logdir 'App_PSAppDeployToolkit_Uninstall.log') "Uninstall complete"
        $r = & $script:invoke @{ DeploymentType='Uninstall'; DetectionScript='C:\det.ps1' }
        $r.Success        | Should -BeTrue
        $r.DetectionState | Should -Be 'not-installed'
    }
}
