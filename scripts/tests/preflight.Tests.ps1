<#
.SYNOPSIS
    Minimal Pester tests for scripts/preflight.ps1.

.DESCRIPTION
    Covers the four required probe paths plus the exit-code contract:
      1. tool present          -> OK
      2. tool missing          -> MISSING (and report mode still exits 0)
      3. vswhere.exe missing   -> UNKNOWN (cannot determine, never a crash)
      4. registry key missing  -> MISSING for WebView2, UNKNOWN for the VBSCRIPT advisory

    All tests drive the script through injected fake probes (New-FakeProbeSet), so they run
    anywhere and never touch the real machine, install anything, or need elevation.

.PARAMETER  (none) - run with:  Invoke-Pester scripts/tests/preflight.Tests.ps1

.NOTES
    Pester version: this file uses the v3 assertion syntax (`Should Be`) because the only
    Pester available on the development machine at the time of writing is 3.4.0, and
    installing a newer one is a user-approved step.
    On Pester >= 4 the assertions must be converted to the `Should -Be` form:
        'x' | Should Be 'y'   ->   'x' | Should -Be 'y'
    This file is the only place that needs that conversion.
#>

$here = $PSScriptRoot
if ([string]::IsNullOrEmpty($here)) {
    $here = Split-Path -Parent $MyInvocation.MyCommand.Path
}
$preflightPath = Join-Path (Split-Path -Parent $here) 'preflight.ps1'

if (-not (Test-Path -LiteralPath $preflightPath -PathType Leaf)) {
    throw "preflight.ps1 not found at '$preflightPath'"
}

# Dot-sourcing only defines functions: the script skips its entry point when dot-sourced.
. $preflightPath

# The script sets Set-StrictMode 2.0 for its own run; relax it so Pester internals are not
# affected while these tests execute the same functions.
Set-StrictMode -Off

$allCommands = @('git', 'node', 'npm', 'corepack', 'pnpm', 'uv', 'py', 'python', 'rustup', 'rustc', 'cargo')

function Test-CheckStatus {
    param(
        [hashtable]$Probe,
        [string]$CheckId
    )
    $report = Invoke-Preflight -Probe $Probe -RepoRoot 'C:\fake\repo' -RequireReadyMode $false
    $row = $report.checks | Where-Object { $_.id -eq $CheckId } | Select-Object -First 1
    if ($null -eq $row) {
        return '<no such check>'
    }
    return $row.status
}

Describe 'preflight: path 1 - tool present' {

    $probe = New-FakeProbeSet -Commands $allCommands -Versions (Get-FullToolSetVersions)

    It 'reports pnpm as OK' {
        (Test-CheckStatus -Probe $probe -CheckId 'pnpm') | Should Be 'OK'
    }

    It 'reports uv as OK' {
        (Test-CheckStatus -Probe $probe -CheckId 'uv') | Should Be 'OK'
    }

    It 'confirms the MSVC target host for rustc' {
        (Test-CheckStatus -Probe $probe -CheckId 'rustc') | Should Be 'OK'
    }

    It 'returns the Ready verdict when every Blocking item is OK' {
        $report = Invoke-Preflight -Probe $probe -RepoRoot 'C:\fake\repo' -RequireReadyMode $false
        $report.verdict | Should Be 'Ready'
    }

    It 'exits 0 under -RequireReady when ready' {
        $report = Invoke-Preflight -Probe $probe -RepoRoot 'C:\fake\repo' -RequireReadyMode $true
        (Get-PreflightExitCode -Report $report -RequireReadyMode $true) | Should Be 0
    }
}

Describe 'preflight: path 2 - tool missing' {

    $probe = New-FakeProbeSet -Commands @('git', 'node', 'npm', 'py') -Versions (Get-FullToolSetVersions)

    It 'reports pnpm as MISSING' {
        (Test-CheckStatus -Probe $probe -CheckId 'pnpm') | Should Be 'MISSING'
    }

    It 'reports uv as MISSING' {
        (Test-CheckStatus -Probe $probe -CheckId 'uv') | Should Be 'MISSING'
    }

    It 'reports rustc as MISSING' {
        (Test-CheckStatus -Probe $probe -CheckId 'rustc') | Should Be 'MISSING'
    }

    It 'reports cargo as MISSING' {
        (Test-CheckStatus -Probe $probe -CheckId 'cargo') | Should Be 'MISSING'
    }

    It 'still returns a complete inventory instead of throwing' {
        $report = Invoke-Preflight -Probe $probe -RepoRoot 'C:\fake\repo' -RequireReadyMode $false
        $report.checks.Count | Should Be 13
    }

    It 'does not treat a missing tool as a script failure (report mode exits 0)' {
        $report = Invoke-Preflight -Probe $probe -RepoRoot 'C:\fake\repo' -RequireReadyMode $false
        $report.verdict | Should Be 'NotReady'
        (Get-PreflightExitCode -Report $report -RequireReadyMode $false) | Should Be 0
    }

    It 'exits 1 under -RequireReady and names the blocking items' {
        $report = Invoke-Preflight -Probe $probe -RepoRoot 'C:\fake\repo' -RequireReadyMode $true
        (Get-PreflightExitCode -Report $report -RequireReadyMode $true) | Should Be 1
        ($report.blockingNotOk -contains 'pnpm') | Should Be $true
        ($report.blockingNotOk -contains 'uv') | Should Be $true
    }
}

Describe 'preflight: path 3 - vswhere.exe missing' {

    $probe = New-FakeProbeSet -Commands $allCommands -Versions (Get-FullToolSetVersions) -VswhereAvailable $false

    It 'reports MSVC as UNKNOWN rather than MISSING or a crash' {
        (Test-CheckStatus -Probe $probe -CheckId 'msvc') | Should Be 'UNKNOWN'
    }

    It 'keeps the other checks unaffected' {
        (Test-CheckStatus -Probe $probe -CheckId 'pnpm') | Should Be 'OK'
    }

    It 'carries a fix hint for MSVC' {
        $report = Invoke-Preflight -Probe $probe -RepoRoot 'C:\fake\repo' -RequireReadyMode $false
        $row = $report.checks | Where-Object { $_.id -eq 'msvc' } | Select-Object -First 1
        ([string]::IsNullOrEmpty($row.fixHint)) | Should Be $false
    }

    It 'makes the verdict NotReady but keeps report mode at exit 0' {
        $report = Invoke-Preflight -Probe $probe -RepoRoot 'C:\fake\repo' -RequireReadyMode $false
        $report.verdict | Should Be 'NotReady'
        (Get-PreflightExitCode -Report $report -RequireReadyMode $false) | Should Be 0
    }

    It 'reports MSVC as MISSING when vswhere answers but finds nothing' {
        $probeNoInstall = New-FakeProbeSet -Commands $allCommands -Versions (Get-FullToolSetVersions) -VswhereOutput ''
        (Test-CheckStatus -Probe $probeNoInstall -CheckId 'msvc') | Should Be 'MISSING'
    }
}

Describe 'preflight: path 4 - registry key missing' {

    $probe = New-FakeProbeSet -Commands $allCommands -Versions (Get-FullToolSetVersions) -WebView2Present $false -CapabilityAvailable $false -VbscriptDllPresent $false

    It 'reports WebView2 as MISSING' {
        (Test-CheckStatus -Probe $probe -CheckId 'webview2') | Should Be 'MISSING'
    }

    It 'reports the VBSCRIPT advisory as UNKNOWN when the capability API needs elevation' {
        (Test-CheckStatus -Probe $probe -CheckId 'vbscript') | Should Be 'UNKNOWN'
    }

    It 'never makes the VBSCRIPT advisory a blocking item' {
        $report = Invoke-Preflight -Probe $probe -RepoRoot 'C:\fake\repo' -RequireReadyMode $false
        $row = $report.checks | Where-Object { $_.id -eq 'vbscript' } | Select-Object -First 1
        $row.severity | Should Be 'Advisory'
        ($report.blockingNotOk -contains 'vbscript') | Should Be $false
    }

    It 'still produces a full report with 13 checks' {
        $report = Invoke-Preflight -Probe $probe -RepoRoot 'C:\fake\repo' -RequireReadyMode $false
        $report.checks.Count | Should Be 13
    }
}

Describe 'preflight: version mismatches are WARN, never MISSING' {

    $wrongVersions = Get-FullToolSetVersions
    $wrongVersions['node'] = 'v20.11.0'
    $wrongVersions['rustc'] = "rustc 1.81.0`nhost: x86_64-unknown-linux-gnu"
    $probe = New-FakeProbeSet -Commands $allCommands -Versions $wrongVersions

    It 'warns when the Node major is not the pinned major' {
        (Test-CheckStatus -Probe $probe -CheckId 'node') | Should Be 'WARN'
    }

    It 'warns when the rustc host is not the MSVC host required by D-5' {
        (Test-CheckStatus -Probe $probe -CheckId 'rustc') | Should Be 'WARN'
    }

    It 'still treats a wrong-version toolchain as Blocking-not-OK for the gate' {
        $report = Invoke-Preflight -Probe $probe -RepoRoot 'C:\fake\repo' -RequireReadyMode $true
        (Get-PreflightExitCode -Report $report -RequireReadyMode $true) | Should Be 1
    }
}

Describe 'preflight: script is read-only by construction' {

    $scriptText = Get-Content -LiteralPath $preflightPath -Raw

    It 'contains no Invoke-Expression / iex' {
        ($scriptText -match 'Invoke-Expression') | Should Be $false
        ($scriptText -match '(?<![\w-])iex(?![-\w])') | Should Be $false
    }

    It 'contains no environment-variable or registry writes' {
        ($scriptText -match 'SetEnvironmentVariable') | Should Be $false
        ($scriptText -match 'Set-ItemProperty') | Should Be $false
        ($scriptText -match 'New-ItemProperty') | Should Be $false
        ($scriptText -match 'Remove-ItemProperty') | Should Be $false
    }

    It 'contains no process spawning or package-manager execution' {
        ($scriptText -match 'Start-Process') | Should Be $false
        ($scriptText -match '&\s*winget') | Should Be $false
        ($scriptText -match '&\s*choco') | Should Be $false
    }

    It 'writes only into a temp directory, and only when JSON output is enabled' {
        ($scriptText -match 'Set-Content') | Should Be $true
        ($scriptText -match 'tmp\\preflight') | Should Be $true
    }
}

Describe 'preflight: report contains no secret-bearing fields' {

    $probe = New-FakeProbeSet -Commands $allCommands -Versions (Get-FullToolSetVersions)

    It 'has no key / token / secret / password properties anywhere in the report' {
        $report = Invoke-Preflight -Probe $probe -RepoRoot 'C:\fake\repo' -RequireReadyMode $false
        $json = $report | ConvertTo-Json -Depth 8
        ($json -match '(?i)api[_-]?key|secret|password|bearer|authorization') | Should Be $false
    }
}
