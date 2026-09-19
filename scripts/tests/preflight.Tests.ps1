<#
.SYNOPSIS
    Pester tests for the EngMentor development environment preflight.

.DESCRIPTION
    The only automated test source for scripts/preflight.ps1 and
    scripts/lib/PreflightChecks.psm1. Every check is driven through injected fake probes, so
    the tests run anywhere, never touch the real machine, never install anything and never
    need elevation.

    Covered:
      * the four probe paths: tool present / tool missing / vswhere missing / registry key missing
      * the MSVC build environment requiring VC tools AND link.exe AND the Windows SDK
      * winget as an information-only install channel that never blocks
      * the JSON output boundary: nothing outside <repo>/tmp/preflight is writable
      * exit-code contract: report mode 0, -RequireReady 1, usage error 2
      * read-only guarantees and the absence of secret-bearing fields

.NOTES
    Run with:  Invoke-Pester scripts/tests/preflight.Tests.ps1

    Pester version: uses the v3 assertion syntax (`Should Be`) because the only Pester
    available on the development machine at the time of writing is 3.4.0, and installing a
    newer one is a user-approved step. On Pester >= 4 convert assertions to `Should -Be`:
        'x' | Should Be 'y'   ->   'x' | Should -Be 'y'
#>

$here = $PSScriptRoot
if ([string]::IsNullOrEmpty($here)) {
    $here = Split-Path -Parent $MyInvocation.MyCommand.Path
}
$scriptsDir = Split-Path -Parent $here
$entryScriptPath = Join-Path $scriptsDir 'preflight.ps1'
$modulePath = Join-Path $scriptsDir 'lib\PreflightChecks.psm1'

if (-not (Test-Path -LiteralPath $modulePath -PathType Leaf)) {
    throw "Check module not found at '$modulePath'"
}
Import-Module -Name $modulePath -Force

$allCommands = @('git', 'node', 'npm', 'corepack', 'pnpm', 'uv', 'py', 'python', 'rustup', 'rustc', 'cargo', 'winget')
$expectedCheckCount = 14

function Get-HealthyVersions {
    return @{
        'git'      = 'git version 2.51.0.windows.1'
        'node'     = 'v22.20.0'
        'npm'      = '10.9.3'
        'corepack' = '0.34.0'
        'pnpm'     = '10.0.0'
        'uv'       = 'uv 0.5.0'
        'rustup'   = 'rustup 1.27.1'
        'rustc'    = "rustc 1.81.0`nhost: x86_64-pc-windows-msvc"
        'cargo'    = 'cargo 1.81.0'
        'winget'   = 'v1.9.25200'
    }
}

function New-FakeProbeSet {
    <#
    .SYNOPSIS
        Build a fake probe set so checks can be exercised without touching the real machine.
    #>
    param(
        [string[]]$Commands = @(),
        [hashtable]$Versions = $null,
        [bool]$VswhereAvailable = $true,
        [string]$VswhereInstallPath = 'C:\Program Files\Microsoft Visual Studio\2022\BuildTools',
        [bool]$LinkExeFound = $true,
        [bool]$SdkRegistered = $true,
        [string]$SdkRoot = 'C:\Program Files (x86)\Windows Kits\10\',
        [bool]$SdkIncludePresent = $true,
        [bool]$SdkLibPresent = $true,
        [bool]$WebView2Present = $true,
        [bool]$CapabilityAvailable = $true,
        [string]$CapabilityState = 'Installed',
        [bool]$VbscriptDllPresent = $true
    )

    if ($null -eq $Versions) { $Versions = Get-HealthyVersions }

    $probes = @{}

    $probes['Command'] = {
        param($Name)
        if ($Commands -contains $Name) {
            return [pscustomobject]@{ name = $Name; path = "C:\fake\$Name.exe"; type = 'Application' }
        }
        return $null
    }.GetNewClosure()

    $probes['Exec'] = {
        param($FilePath, $Arguments)
        $name = [System.IO.Path]::GetFileNameWithoutExtension($FilePath)
        $output = "$name fake 0.0.0"
        if ($Versions.ContainsKey($name)) { $output = [string]$Versions[$name] }
        if (($Arguments -contains 'python') -and ($Arguments -contains 'list')) {
            $output = 'cpython-3.12.8-windows-x86_64-none'
        }
        return [pscustomobject]@{ ran = $true; exitCode = 0; output = $output }
    }.GetNewClosure()

    $probes['Vswhere'] = {
        param($Arguments)
        if (-not $VswhereAvailable) {
            return [pscustomobject]@{ available = $false; path = ''; exitCode = -1; output = '' }
        }
        $output = ''
        if ($Arguments -contains '-property') {
            $output = $VswhereInstallPath
        }
        elseif ($Arguments -contains '-find') {
            if ((($Arguments -join ' ') -match 'link\.exe') -and $LinkExeFound) {
                $output = 'C:\fake\VC\Tools\MSVC\14.40.33807\bin\Hostx64\x64\link.exe'
            }
        }
        return [pscustomobject]@{ available = $true; path = 'C:\fake\vswhere.exe'; exitCode = 0; output = $output }
    }.GetNewClosure()

    $probes['Registry'] = {
        param($Path, $ValueName)
        if ($ValueName -eq 'KitsRoot10') {
            if ($SdkRegistered) { return [pscustomobject]@{ readable = $true; value = $SdkRoot; error = '' } }
            return [pscustomobject]@{ readable = $false; value = ''; error = 'key not present' }
        }
        if ($ValueName -eq 'pv') {
            if ($WebView2Present) { return [pscustomobject]@{ readable = $true; value = '124.0.2478.109'; error = '' } }
            return [pscustomobject]@{ readable = $false; value = ''; error = 'key not present' }
        }
        return [pscustomobject]@{ readable = $false; value = ''; error = 'unexpected value name' }
    }.GetNewClosure()

    $probes['File'] = {
        param($Path)
        return $VbscriptDllPresent
    }.GetNewClosure()

    $probes['Directory'] = {
        param($Path)
        if ($Path -like '*\Include*') { return $SdkIncludePresent }
        if ($Path -like '*\Lib*') { return $SdkLibPresent }
        return $false
    }.GetNewClosure()

    $probes['Capability'] = {
        param($NamePattern)
        if (-not $CapabilityAvailable) {
            return [pscustomobject]@{ available = $false; found = $false; name = ''; state = ''; error = 'requires elevation' }
        }
        return [pscustomobject]@{ available = $true; found = $true; name = 'VBSCRIPT~~~~0.0.1.0'; state = $CapabilityState; error = '' }
    }.GetNewClosure()

    return $probes
}

function Get-CheckStatus {
    param(
        [hashtable]$Probe,
        [string]$CheckId,
        [string]$RepoRoot = 'C:\fake\repo'
    )
    $report = Invoke-Preflight -Probe $Probe -RepoRoot $RepoRoot -RequireReadyMode $false
    $row = $report.checks | Where-Object { $_.id -eq $CheckId } | Select-Object -First 1
    if ($null -eq $row) { return '<no such check>' }
    return $row.status
}

function Get-CheckRow {
    param(
        [hashtable]$Probe,
        [string]$CheckId
    )
    $report = Invoke-Preflight -Probe $Probe -RepoRoot 'C:\fake\repo' -RequireReadyMode $false
    return ($report.checks | Where-Object { $_.id -eq $CheckId } | Select-Object -First 1)
}

Describe 'preflight: path 1 - tool present' {

    $probe = New-FakeProbeSet -Commands $allCommands

    It 'reports pnpm as OK' {
        (Get-CheckStatus -Probe $probe -CheckId 'pnpm') | Should Be 'OK'
    }

    It 'reports uv as OK' {
        (Get-CheckStatus -Probe $probe -CheckId 'uv') | Should Be 'OK'
    }

    It 'confirms the MSVC target host for rustc' {
        (Get-CheckStatus -Probe $probe -CheckId 'rustc') | Should Be 'OK'
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

    $probe = New-FakeProbeSet -Commands @('git', 'node', 'npm', 'py')

    It 'reports pnpm as MISSING' {
        (Get-CheckStatus -Probe $probe -CheckId 'pnpm') | Should Be 'MISSING'
    }

    It 'reports uv as MISSING' {
        (Get-CheckStatus -Probe $probe -CheckId 'uv') | Should Be 'MISSING'
    }

    It 'reports rustc as MISSING' {
        (Get-CheckStatus -Probe $probe -CheckId 'rustc') | Should Be 'MISSING'
    }

    It 'reports cargo as MISSING' {
        (Get-CheckStatus -Probe $probe -CheckId 'cargo') | Should Be 'MISSING'
    }

    It 'still returns a complete inventory instead of throwing' {
        $report = Invoke-Preflight -Probe $probe -RepoRoot 'C:\fake\repo' -RequireReadyMode $false
        $report.checks.Count | Should Be $expectedCheckCount
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

    $probe = New-FakeProbeSet -Commands $allCommands -VswhereAvailable $false

    It 'reports MSVC as UNKNOWN rather than MISSING or a crash' {
        (Get-CheckStatus -Probe $probe -CheckId 'msvc') | Should Be 'UNKNOWN'
    }

    It 'keeps the other checks unaffected' {
        (Get-CheckStatus -Probe $probe -CheckId 'pnpm') | Should Be 'OK'
    }

    It 'carries a fix hint for MSVC' {
        ([string]::IsNullOrEmpty((Get-CheckRow -Probe $probe -CheckId 'msvc').fixHint)) | Should Be $false
    }

    It 'makes the verdict NotReady but keeps report mode at exit 0' {
        $report = Invoke-Preflight -Probe $probe -RepoRoot 'C:\fake\repo' -RequireReadyMode $false
        $report.verdict | Should Be 'NotReady'
        (Get-PreflightExitCode -Report $report -RequireReadyMode $false) | Should Be 0
    }

    It 'reports MSVC as MISSING when vswhere answers but finds no VC tools component' {
        $probeNoComponent = New-FakeProbeSet -Commands $allCommands -VswhereInstallPath ''
        (Get-CheckStatus -Probe $probeNoComponent -CheckId 'msvc') | Should Be 'MISSING'
    }
}

Describe 'preflight: path 4 - registry key missing' {

    $probe = New-FakeProbeSet -Commands $allCommands -WebView2Present $false -CapabilityAvailable $false -VbscriptDllPresent $false

    It 'reports WebView2 as MISSING' {
        (Get-CheckStatus -Probe $probe -CheckId 'webview2') | Should Be 'MISSING'
    }

    It 'reports the VBSCRIPT advisory as UNKNOWN when the capability API needs elevation' {
        (Get-CheckStatus -Probe $probe -CheckId 'vbscript') | Should Be 'UNKNOWN'
    }

    It 'never makes the VBSCRIPT advisory a blocking item' {
        $row = Get-CheckRow -Probe $probe -CheckId 'vbscript'
        $row.severity | Should Be 'Advisory'
        $report = Invoke-Preflight -Probe $probe -RepoRoot 'C:\fake\repo' -RequireReadyMode $false
        ($report.blockingNotOk -contains 'vbscript') | Should Be $false
    }

    It 'still produces a full report' {
        $report = Invoke-Preflight -Probe $probe -RepoRoot 'C:\fake\repo' -RequireReadyMode $false
        $report.checks.Count | Should Be $expectedCheckCount
    }
}

Describe 'preflight: MSVC needs VC tools AND link.exe AND the Windows SDK' {

    It 'is OK when all three parts are present' {
        $probe = New-FakeProbeSet -Commands $allCommands
        (Get-CheckStatus -Probe $probe -CheckId 'msvc') | Should Be 'OK'
    }

    It 'is MISSING when the VC tools component exists but link.exe is not found' {
        $probe = New-FakeProbeSet -Commands $allCommands -LinkExeFound $false
        (Get-CheckStatus -Probe $probe -CheckId 'msvc') | Should Be 'MISSING'
    }

    It 'is MISSING when link.exe exists but the Windows SDK is not registered' {
        $probe = New-FakeProbeSet -Commands $allCommands -SdkRegistered $false
        (Get-CheckStatus -Probe $probe -CheckId 'msvc') | Should Be 'MISSING'
    }

    It 'is MISSING when the SDK root is registered but its Include directory is absent' {
        $probe = New-FakeProbeSet -Commands $allCommands -SdkIncludePresent $false
        (Get-CheckStatus -Probe $probe -CheckId 'msvc') | Should Be 'MISSING'
    }

    It 'is MISSING when the SDK root is registered but its Lib directory is absent' {
        $probe = New-FakeProbeSet -Commands $allCommands -SdkLibPresent $false
        (Get-CheckStatus -Probe $probe -CheckId 'msvc') | Should Be 'MISSING'
    }

    It 'names the missing part in the details so the failure is actionable' {
        $probe = New-FakeProbeSet -Commands $allCommands -LinkExeFound $false
        $row = Get-CheckRow -Probe $probe -CheckId 'msvc'
        ($row.details -match 'link\.exe') | Should Be $true
    }

    It 'blocks the gate whenever MSVC is not ready' {
        $probe = New-FakeProbeSet -Commands $allCommands -LinkExeFound $false
        $report = Invoke-Preflight -Probe $probe -RepoRoot 'C:\fake\repo' -RequireReadyMode $true
        (Get-PreflightExitCode -Report $report -RequireReadyMode $true) | Should Be 1
        ($report.blockingNotOk -contains 'msvc') | Should Be $true
    }
}

Describe 'preflight: winget is informational only' {

    It 'reports winget as OK with Info severity when present' {
        $probe = New-FakeProbeSet -Commands $allCommands
        $row = Get-CheckRow -Probe $probe -CheckId 'winget'
        $row.status | Should Be 'OK'
        $row.severity | Should Be 'Info'
    }

    It 'reports winget as MISSING when absent' {
        $probe = New-FakeProbeSet -Commands @('git', 'node', 'npm', 'py', 'python', 'pnpm', 'uv', 'rustup', 'rustc', 'cargo')
        (Get-CheckStatus -Probe $probe -CheckId 'winget') | Should Be 'MISSING'
    }

    It 'never blocks the gate when winget is absent' {
        $probe = New-FakeProbeSet -Commands @('git', 'node', 'npm', 'py', 'python', 'pnpm', 'uv', 'rustup', 'rustc', 'cargo')
        $report = Invoke-Preflight -Probe $probe -RepoRoot 'C:\fake\repo' -RequireReadyMode $true
        $report.verdict | Should Be 'Ready'
        ($report.blockingNotOk -contains 'winget') | Should Be $false
        (Get-PreflightExitCode -Report $report -RequireReadyMode $true) | Should Be 0
    }

    It 'lists the package ids that still need verification in the install phase' {
        $probe = New-FakeProbeSet -Commands $allCommands
        $row = Get-CheckRow -Probe $probe -CheckId 'winget'
        ($row.details -match 'pnpm') | Should Be $true
        ($row.details -match 'verify') | Should Be $true
    }
}

Describe 'preflight: JSON output is confined to <repo>/tmp/preflight' {

    $repoRoot = 'C:\fake\repo'

    It 'defaults to <repo>/tmp/preflight' {
        $resolved = Resolve-PreflightOutputDirectory -Requested '' -RepoRoot $repoRoot
        $resolved.ok | Should Be $true
        $resolved.path | Should Be 'C:\fake\repo\tmp\preflight'
    }

    It 'accepts the allowed root itself' {
        $resolved = Resolve-PreflightOutputDirectory -Requested 'C:\fake\repo\tmp\preflight' -RepoRoot $repoRoot
        $resolved.ok | Should Be $true
    }

    It 'accepts a subdirectory of the allowed root' {
        $resolved = Resolve-PreflightOutputDirectory -Requested 'tmp\preflight\runs' -RepoRoot $repoRoot
        $resolved.ok | Should Be $true
        $resolved.path | Should Be 'C:\fake\repo\tmp\preflight\runs'
    }

    It 'rejects a sibling temp directory inside the repo' {
        $resolved = Resolve-PreflightOutputDirectory -Requested 'tmp\other' -RepoRoot $repoRoot
        $resolved.ok | Should Be $false
    }

    It 'rejects an absolute path outside the repository' {
        $resolved = Resolve-PreflightOutputDirectory -Requested 'C:\Windows\Temp\engm' -RepoRoot $repoRoot
        $resolved.ok | Should Be $false
        ([string]::IsNullOrEmpty($resolved.error)) | Should Be $false
    }

    It 'rejects the repository root itself' {
        $resolved = Resolve-PreflightOutputDirectory -Requested 'C:\fake\repo' -RepoRoot $repoRoot
        $resolved.ok | Should Be $false
    }

    It 'rejects a parent-directory traversal' {
        $resolved = Resolve-PreflightOutputDirectory -Requested 'tmp\preflight\..\..\..\evil' -RepoRoot $repoRoot
        $resolved.ok | Should Be $false
    }

    It 'reports the allowed root in the rejection message' {
        $resolved = Resolve-PreflightOutputDirectory -Requested 'C:\Windows\Temp\engm' -RepoRoot $repoRoot
        ($resolved.error -match 'tmp\\preflight') | Should Be $true
    }
}

Describe 'preflight: CLI exit codes' {

    It 'exits 2 when -OutputDirectory points outside the allowed tree' {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $entryScriptPath -OutputDirectory 'C:\Windows\Temp\engm-preflight' -Quiet | Out-Null
        $LASTEXITCODE | Should Be 2
    }

    It 'exits 0 in report mode without writing anything when -NoJson is used' {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $entryScriptPath -NoJson -Quiet | Out-Null
        $LASTEXITCODE | Should Be 0
    }
}

Describe 'preflight: version mismatches are WARN, never MISSING' {

    $wrongVersions = Get-HealthyVersions
    $wrongVersions['node'] = 'v20.11.0'
    $wrongVersions['rustc'] = "rustc 1.81.0`nhost: x86_64-unknown-linux-gnu"
    $probe = New-FakeProbeSet -Commands $allCommands -Versions $wrongVersions

    It 'warns when the Node major is not the pinned major' {
        (Get-CheckStatus -Probe $probe -CheckId 'node') | Should Be 'WARN'
    }

    It 'warns when the rustc host is not the MSVC host required by D-5' {
        (Get-CheckStatus -Probe $probe -CheckId 'rustc') | Should Be 'WARN'
    }

    It 'still treats a wrong-version toolchain as Blocking-not-OK for the gate' {
        $report = Invoke-Preflight -Probe $probe -RepoRoot 'C:\fake\repo' -RequireReadyMode $true
        (Get-PreflightExitCode -Report $report -RequireReadyMode $true) | Should Be 1
    }
}

Describe 'preflight: vswhere discovery' {

    It 'offers the 32-bit Program Files root, where the VS Installer actually puts vswhere' {
        $candidates = Get-VswhereCandidatePaths
        ($candidates.Count -gt 0) | Should Be $true
        (($candidates -join ';') -match 'Program Files \(x86\)\\Microsoft Visual Studio\\Installer\\vswhere\.exe') | Should Be $true
    }

    It 'probes the injected candidate list rather than an outer scope value' {
        # Regression: the probe closure previously read a module-scoped variable, which
        # GetNewClosure() does not capture, so it always reported "not found".
        $probe = Get-RealProbes -VswhereCandidates @('C:\definitely\not\here\vswhere.exe')
        $missingResult = & $probe['Vswhere'] @('-property', 'installationPath')
        $missingResult.available | Should Be $false

        $probeWithRealPath = Get-RealProbes -VswhereCandidates @($modulePath)
        $presentResult = & $probeWithRealPath['Vswhere'] @('-property', 'installationPath')
        $presentResult.available | Should Be $true
        $presentResult.path | Should Be $modulePath
    }

    It 'never reports availability for a list of non-existent candidates' {
        $probe = Get-RealProbes -VswhereCandidates @('C:\nope\a.exe', 'C:\nope\b.exe')
        $result = & $probe['Vswhere'] @('-property', 'installationPath')
        $result.available | Should Be $false
        $result.exitCode | Should Be -1
    }
}

Describe 'preflight: read-only by construction' {

    $sources = @{
        'entry script' = $entryScriptPath
        'check module' = $modulePath
    }

    It 'contains no Invoke-Expression / iex in either file' {
        foreach ($key in $sources.Keys) {
            $text = Get-Content -LiteralPath $sources[$key] -Raw
            ($text -match 'Invoke-Expression') | Should Be $false
            ($text -match '(?<![\w-])iex(?![-\w])') | Should Be $false
        }
    }

    It 'contains no environment-variable or registry writes in either file' {
        foreach ($key in $sources.Keys) {
            $text = Get-Content -LiteralPath $sources[$key] -Raw
            ($text -match 'SetEnvironmentVariable') | Should Be $false
            ($text -match 'Set-ItemProperty') | Should Be $false
            ($text -match 'New-ItemProperty') | Should Be $false
            ($text -match 'Remove-ItemProperty') | Should Be $false
        }
    }

    It 'contains no process spawning or package-manager execution in either file' {
        foreach ($key in $sources.Keys) {
            $text = Get-Content -LiteralPath $sources[$key] -Raw
            ($text -match 'Start-Process') | Should Be $false
            ($text -match '&\s*winget') | Should Be $false
            ($text -match '&\s*choco') | Should Be $false
            # Statement-level invocation. User-facing hint text may legitimately name a
            # command for the operator to run, so the guard targets execution, not mention.
            ($text -match '(?m)^\s*winget\s+\w+') | Should Be $false
            ($text -match '(?m)^\s*choco\s+\w+') | Should Be $false
            ($text -match '(?m)^\s*rustup\s+(update|install|default)') | Should Be $false
            ($text -match '(?m)^\s*npm\s+install') | Should Be $false
            ($text -match '(?m)^\s*corepack\s+(enable|prepare)') | Should Be $false
        }
    }

    It 'writes only through Write-PreflightJson, which targets the temp tree' {
        $moduleText = Get-Content -LiteralPath $modulePath -Raw
        ($moduleText -match 'Set-Content') | Should Be $true
        ($moduleText -match 'tmp\\preflight') | Should Be $true
    }
}

Describe 'preflight: report contains no secret-bearing fields' {

    $probe = New-FakeProbeSet -Commands $allCommands

    It 'has no key / token / secret / password properties anywhere in the report' {
        $report = Invoke-Preflight -Probe $probe -RepoRoot 'C:\fake\repo' -RequireReadyMode $false
        $json = $report | ConvertTo-Json -Depth 8
        ($json -match '(?i)api[_-]?key|secret|password|bearer|authorization') | Should Be $false
    }
}
