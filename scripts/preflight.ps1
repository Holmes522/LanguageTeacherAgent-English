<#
.SYNOPSIS
    Read-only development environment preflight for the EngMentor desktop client (M00 / T010).

.DESCRIPTION
    Inventories the local toolchain required by docs/specs/SPEC-M00-foundation-contracts.md
    section 3.2 and reports, per item: status (OK / MISSING / WARN / UNKNOWN / SKIP),
    severity (Blocking / Advisory / Info), detected version, resolved path, details and a
    recommended fix.

    The script is READ-ONLY and side-effect free:
      * never installs anything (no winget / choco / npm install / corepack enable / rustup update)
      * never modifies environment variables, the registry, Git configuration or user profile
      * never reads, prints or persists secrets

    The only write is the optional machine-readable JSON report, which goes to an ignored
    temp directory (tmp/preflight/ by default). Use -NoJson to disable even that.

    Guardrails against misdiagnosis:
      * a missing tool is reported as MISSING, never as a script failure
      * default (report) mode always exits 0, even when everything is missing
      * -RequireReady exits 1 when any Blocking item is not OK - use it as a gate before
        install/build steps, never as the default

.PARAMETER RequireReady
    Exit with code 1 if any Blocking check is not OK. Without this switch the script always
    exits 0 in report mode, because "not installed yet" is a finding, not a failure.

.PARAMETER SelfTest
    Run the four built-in probe scenarios (tools present / tools missing / vswhere missing /
    registry key missing) using fake probes only. Touches nothing real and writes no JSON.

.PARAMETER LibraryOnly
    Define functions and exit without running checks. Used by the Pester test file.
    Dot-sourcing the script has the same effect.

.PARAMETER NoJson
    Do not write the JSON report. The script then performs no writes at all.

.PARAMETER OutputDirectory
    Directory for the JSON report. Defaults to <repo root>/tmp/preflight (gitignored).

.PARAMETER Quiet
    Suppress the human-readable summary (JSON report is still written unless -NoJson).

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File scripts/preflight.ps1

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File scripts/preflight.ps1 -RequireReady

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File scripts/preflight.ps1 -SelfTest

.NOTES
    Version : 1.0.0
    Target  : Windows PowerShell 5.1+ and PowerShell 7+
    Encoding: ASCII only on purpose, so Windows PowerShell 5.1 reads it correctly regardless
              of the active code page.
#>
[CmdletBinding()]
param(
    [switch]$RequireReady,
    [switch]$SelfTest,
    [switch]$LibraryOnly,
    [switch]$NoJson,
    [string]$OutputDirectory,
    [switch]$Quiet
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Continue'

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

$script:PreflightVersion = '1.0.0'
$script:SchemaVersion = '1.0'

$script:SeverityBlocking = 'Blocking'
$script:SeverityAdvisory = 'Advisory'
$script:SeverityInfo = 'Info'

$script:StatusOk = 'OK'
$script:StatusMissing = 'MISSING'
$script:StatusWarn = 'WARN'
$script:StatusUnknown = 'UNKNOWN'
$script:StatusSkip = 'SKIP'

$script:SeverityOrder = @($script:SeverityBlocking, $script:SeverityAdvisory, $script:SeverityInfo)

$script:ExpectedNodeMajor = 22
$script:ExpectedPythonMinor = '3.12'
$script:ExpectedRustHost = 'x86_64-pc-windows-msvc'

# WebView2 Evergreen Runtime product GUID used by the EdgeUpdate client registry keys.
$script:WebView2ClientGuid = '{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}'
$script:WebView2RegistryPaths = @(
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\$($script:WebView2ClientGuid)",
    "HKLM:\SOFTWARE\Microsoft\EdgeUpdate\Clients\$($script:WebView2ClientGuid)",
    "HKCU:\Software\Microsoft\EdgeUpdate\Clients\$($script:WebView2ClientGuid)"
)

# vswhere.exe locations: the Visual Studio Installer ships it in these two places.
$script:VswhereCandidates = @(
    (Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'),
    (Join-Path $env:ProgramFiles 'Microsoft Visual Studio\Installer\vswhere.exe')
)

# Recommended install methods. Package ids are marked "verify" because this script does not
# run winget; confirm the exact id with `winget search` during the install step (T010).
$script:FixHints = @{
    'corepack' = 'Optional bootstrap path: `corepack enable` then `corepack prepare pnpm@<version> --activate` (Node 22 still bundles corepack; newer Node releases removed it).'
    'pnpm'     = 'Official: `npm install -g pnpm`, or corepack as above. Pin the exact version via the root package.json "packageManager" field. See https://pnpm.io/installation (verify before installing).'
    'uv'       = 'Official: `winget install --id=astral-sh.uv -e` (verify id with `winget search uv`), or https://docs.astral.sh/uv/getting-started/installation/ . Do not pipe remote scripts into a shell on a project machine.'
    'python312' = 'Preferred: let uv manage it - `uv python install 3.12` (project pins 3.12 via .python-version). Alternative: python.org 3.12 installer. Do NOT point the project at the system 3.13 interpreter.'
    'rustup'   = 'Official: `winget install --id=Rustlang.Rustup -e` (verify id with `winget search rustup`), or https://rustup.rs/ .'
    'rustc'    = 'Install the Rust toolchain via rustup, then `rustup default <exact version>-x86_64-pc-windows-msvc`. SPEC-M00 D-5 requires an exact version in rust-toolchain.toml, not "stable".'
    'cargo'    = 'Ships with the Rust toolchain installed by rustup.'
    'msvc'     = 'Install Visual Studio 2022 Build Tools with the "Desktop development with C++" workload, which provides link.exe and the Windows SDK. `winget install --id=Microsoft.VisualStudio.2022.BuildTools -e` (verify id) with workload Microsoft.VisualStudio.Workload.VCTools. This also installs vswhere.exe.'
    'webview2' = 'Install the Microsoft Edge WebView2 Evergreen Runtime (usually preinstalled on Windows 11). `winget install --id=Microsoft.EdgeWebView2Runtime -e` (verify id), or the Evergreen bootstrapper from Microsoft.'
    'vbscript' = 'MSI packaging prerequisite only, not a current development blocker. Enable the VBSCRIPT optional feature from an ELEVATED shell (exact capability name is printed by the probe when available). Compare against the NSIS packaging route in the T001 ADR.'
}

# ---------------------------------------------------------------------------
# Result construction
# ---------------------------------------------------------------------------

function New-PreflightCheck {
    <#
    .SYNOPSIS
        Build one check result row. Pure data, no probing.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Id,
        [Parameter(Mandatory = $true)][string]$Title,
        [Parameter(Mandatory = $true)][ValidateSet('Blocking', 'Advisory', 'Info')][string]$Severity,
        [Parameter(Mandatory = $true)][ValidateSet('OK', 'MISSING', 'WARN', 'UNKNOWN', 'SKIP')][string]$Status,
        [string]$Version = '',
        [string]$Path = '',
        [string]$Details = '',
        [string]$FixHint = ''
    )

    [pscustomobject]@{
        id       = $Id
        title    = $Title
        severity = $Severity
        status   = $Status
        version  = $Version
        path     = $Path
        details  = $Details
        fixHint  = $FixHint
    }
}

function New-PreflightReport {
    <#
    .SYNOPSIS
        Assemble the report object from check rows. Pure data, no probing.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Checks,
        [Parameter(Mandatory = $true)][object]$HostInfo,
        [Parameter(Mandatory = $true)][bool]$RequireReadyMode
    )

    $blockingNotOk = @($Checks | Where-Object { $_.severity -eq $script:SeverityBlocking -and $_.status -ne $script:StatusOk })
    $verdict = 'Ready'
    if ($blockingNotOk.Count -gt 0) {
        $verdict = 'NotReady'
    }

    $counts = [pscustomobject]@{
        total   = $Checks.Count
        ok      = @($Checks | Where-Object { $_.status -eq $script:StatusOk }).Count
        missing = @($Checks | Where-Object { $_.status -eq $script:StatusMissing }).Count
        warn    = @($Checks | Where-Object { $_.status -eq $script:StatusWarn }).Count
        unknown = @($Checks | Where-Object { $_.status -eq $script:StatusUnknown }).Count
        skip    = @($Checks | Where-Object { $_.status -eq $script:StatusSkip }).Count
    }

    [pscustomobject]@{
        schemaVersion  = $script:SchemaVersion
        tool           = 'scripts/preflight.ps1'
        toolVersion    = $script:PreflightVersion
        generatedAtUtc = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        host           = $HostInfo
        verdict        = $verdict
        exitCode       = (Get-PreflightExitCode -Report ([pscustomobject]@{ verdict = $verdict; checks = $Checks }) -RequireReadyMode $RequireReadyMode)
        counts         = $counts
        blockingNotOk  = @($blockingNotOk | ForEach-Object { $_.id })
        checks         = $Checks
    }
}

function Get-PreflightExitCode {
    <#
    .SYNOPSIS
        Decide the process exit code. Report mode always returns 0; -RequireReady gates on
        Blocking items. Kept separate so tests can assert the gate without running anything.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$Report,
        [Parameter(Mandatory = $true)][bool]$RequireReadyMode
    )

    if (-not $RequireReadyMode) {
        return 0
    }
    if ($Report.verdict -eq 'Ready') {
        return 0
    }
    return 1
}

# ---------------------------------------------------------------------------
# Real probes (the injectable seam)
#
# Every check receives a $Probe hashtable. Tests replace entries with fakes, so the four
# required paths (tool present, tool missing, vswhere missing, registry key missing) are
# exercised without depending on the machine's real state.
# ---------------------------------------------------------------------------

function Get-RealProbes {
    <#
    .SYNOPSIS
        Build the default probe set. All probes are read-only: they inspect commands, run
        version-style commands, read registry values, test file paths, and query optional
        Windows capabilities. None of them install or modify anything.
    #>
    [CmdletBinding()]
    param()

    $probes = @{}

    $probes['Command'] = {
        param($Name)
        $cmd = Get-Command -Name $Name -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($null -eq $cmd) {
            return $null
        }
        return [pscustomobject]@{
            name = $Name
            path = [string]$cmd.Source
            type = [string]$cmd.CommandType
        }
    }.GetNewClosure()

    $probes['Exec'] = {
        param($FilePath, $Arguments)
        $result = [pscustomobject]@{ ran = $false; exitCode = -1; output = '' }
        try {
            $LASTEXITCODE = 0
            $output = & $FilePath @Arguments 2>&1
            $result = [pscustomobject]@{
                ran      = $true
                exitCode = [int]$LASTEXITCODE
                output   = (($output | Out-String).Trim())
            }
        }
        catch {
            $result = [pscustomobject]@{ ran = $false; exitCode = -1; output = [string]$_.Exception.Message }
        }
        return $result
    }.GetNewClosure()

    $probes['Vswhere'] = {
        param($Arguments)
        $found = ''
        foreach ($candidate in $script:VswhereCandidates) {
            if ($null -ne $candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf -ErrorAction SilentlyContinue)) {
                $found = $candidate
                break
            }
        }
        if ([string]::IsNullOrEmpty($found)) {
            return [pscustomobject]@{ available = $false; path = ''; exitCode = -1; output = '' }
        }
        $exec = & $probes['Exec'] $found $Arguments
        return [pscustomobject]@{
            available = $true
            path      = $found
            exitCode  = $exec.exitCode
            output    = $exec.output
        }
    }.GetNewClosure()

    $probes['Registry'] = {
        param($Path, $ValueName)
        try {
            if (-not (Test-Path -LiteralPath $Path -ErrorAction SilentlyContinue)) {
                return [pscustomobject]@{ readable = $false; value = ''; error = 'key not present' }
            }
            $item = Get-ItemProperty -LiteralPath $Path -Name $ValueName -ErrorAction Stop
            $value = [string]$item.$ValueName
            return [pscustomobject]@{ readable = $true; value = $value; error = '' }
        }
        catch {
            return [pscustomobject]@{ readable = $false; value = ''; error = [string]$_.Exception.Message }
        }
    }.GetNewClosure()

    $probes['File'] = {
        param($Path)
        if ([string]::IsNullOrEmpty($Path)) {
            return $false
        }
        return (Test-Path -LiteralPath $Path -PathType Leaf -ErrorAction SilentlyContinue)
    }.GetNewClosure()

    $probes['Capability'] = {
        param($NamePattern)
        try {
            $cap = Get-WindowsCapability -Online -Name $NamePattern -ErrorAction Stop | Select-Object -First 1
            if ($null -eq $cap) {
                return [pscustomobject]@{ available = $true; found = $false; name = ''; state = 'NotPresent'; error = '' }
            }
            return [pscustomobject]@{ available = $true; found = $true; name = [string]$cap.Name; state = [string]$cap.State; error = '' }
        }
        catch {
            # -Online requires an elevated shell; report as indeterminate rather than failed.
            return [pscustomobject]@{ available = $false; found = $false; name = ''; state = ''; error = [string]$_.Exception.Message }
        }
    }.GetNewClosure()

    return $probes
}

function Get-HostProbes {
    <#
    .SYNOPSIS
        The original probe functions, so tests can pass explicit fakes.
    #>
    [CmdletBinding()]
    param()

    return Get-RealProbes
}

# ---------------------------------------------------------------------------
# Individual checks. Each returns exactly one New-PreflightCheck row.
# ---------------------------------------------------------------------------

function Get-FirstLine {
    [CmdletBinding()]
    param([string]$Text)

    if ([string]::IsNullOrEmpty($Text)) { return '' }
    $lines = $Text -split "`r?`n"
    if ($lines.Count -eq 0) { return '' }
    return ([string]$lines[0]).Trim()
}

function Test-ToolCommandCheck {
    <#
    .SYNOPSIS
        Generic "is this command on PATH, and what version does it report" check.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][hashtable]$Probe,
        [Parameter(Mandatory = $true)][string]$Id,
        [Parameter(Mandatory = $true)][string]$Title,
        [Parameter(Mandatory = $true)][string]$CommandName,
        [Parameter(Mandatory = $true)][ValidateSet('Blocking', 'Advisory', 'Info')][string]$Severity,
        [string[]]$VersionArguments = @('--version'),
        [string]$MissingDetails = ''
    )

    $resolved = & $Probe['Command'] $CommandName
    if ($null -eq $resolved) {
        return New-PreflightCheck -Id $Id -Title $Title -Severity $Severity -Status $script:StatusMissing `
            -Details $(if ([string]::IsNullOrEmpty($MissingDetails)) { "Command '$CommandName' was not found on PATH." } else { $MissingDetails }) `
            -FixHint ([string]$script:FixHints[$Id])
    }

    $exec = & $Probe['Exec'] $resolved.path $VersionArguments
    if (-not $exec.ran) {
        return New-PreflightCheck -Id $Id -Title $Title -Severity $Severity -Status $script:StatusWarn `
            -Path $resolved.path -Details "Command found but '$CommandName $($VersionArguments -join ' ')' could not be executed: $($exec.output)" `
            -FixHint ([string]$script:FixHints[$Id])
    }

    return New-PreflightCheck -Id $Id -Title $Title -Severity $Severity -Status $script:StatusOk `
        -Version (Get-FirstLine $exec.output) -Path $resolved.path -Details "Resolved from PATH ($($resolved.type))."
}

function Test-NodeCheck {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][hashtable]$Probe)

    $row = Test-ToolCommandCheck -Probe $Probe -Id 'node' -Title 'Node.js' -CommandName 'node' -Severity $script:SeverityBlocking
    if ($row.status -ne $script:StatusOk) { return $row }

    # Report mode must not fail because a tool is the wrong version; downgrade to WARN.
    $match = [regex]::Match($row.version, '^v?(\d+)\.')
    if (-not $match.Success) {
        return New-PreflightCheck -Id 'node' -Title 'Node.js' -Severity $script:SeverityBlocking -Status $script:StatusWarn `
            -Version $row.version -Path $row.path -Details 'Could not parse the Node.js major version.'
    }
    $major = [int]$match.Groups[1].Value
    if ($major -ne $script:ExpectedNodeMajor) {
        return New-PreflightCheck -Id 'node' -Title 'Node.js' -Severity $script:SeverityBlocking -Status $script:StatusWarn `
            -Version $row.version -Path $row.path `
            -Details ("Major version {0} is not the pinned major {1}. SPEC-M00 pins Node {1} via .node-version." -f $major, $script:ExpectedNodeMajor)
    }

    return $row
}

function Test-PythonCheck {
    <#
    .SYNOPSIS
        Python 3.12 availability. The project never uses the system interpreter directly;
        uv manages 3.12, so uv's own list is the primary source of truth.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][hashtable]$Probe,
        [string]$ExpectedMinor = '3.12'
    )

    $sources = @()
    $warnings = @()

    # Source 1: uv-managed interpreters.
    $uv = & $Probe['Command'] 'uv'
    if ($null -ne $uv) {
        $exec = & $Probe['Exec'] $uv.path @('python', 'list')
        if ($exec.ran -and $exec.output -match [regex]::Escape($ExpectedMinor)) {
            $sources += "uv-managed interpreter matching $ExpectedMinor"
        }
    }

    # Source 2: the Windows py launcher.
    $py = & $Probe['Command'] 'py'
    if ($null -ne $py) {
        $exec = & $Probe['Exec'] $py.path @("-$ExpectedMinor", '--version')
        if ($exec.ran -and $exec.output -match [regex]::Escape($ExpectedMinor)) {
            $sources += "py launcher -$ExpectedMinor"
        }
    }

    # Source 3: a python on PATH that already is 3.12.
    $python = & $Probe['Command'] 'python'
    $systemVersion = ''
    if ($null -ne $python) {
        $exec = & $Probe['Exec'] $python.path @('--version')
        if ($exec.ran) {
            $systemVersion = Get-FirstLine $exec.output
            if ($systemVersion -match [regex]::Escape($ExpectedMinor)) {
                $sources += "python on PATH ($systemVersion)"
            }
        }
    }

    if ($sources.Count -eq 0) {
        $detail = "No Python $ExpectedMinor interpreter found."
        if (-not [string]::IsNullOrEmpty($systemVersion)) {
            $detail += " Default python on PATH reports '$systemVersion', which is NOT the project interpreter."
        }
        return New-PreflightCheck -Id 'python312' -Title "Python $ExpectedMinor" -Severity $script:SeverityBlocking `
            -Status $script:StatusMissing -Version $systemVersion -Details $detail `
            -FixHint ([string]$script:FixHints['python312'])
    }

    return New-PreflightCheck -Id 'python312' -Title "Python $ExpectedMinor" -Severity $script:SeverityBlocking `
        -Status $script:StatusOk -Version $ExpectedMinor `
        -Details ("Available via: " + ($sources -join '; ') + ".")
}

function Test-RustHostCheck {
    <#
    .SYNOPSIS
        rustc presence and target host. SPEC-M00 D-5 requires the MSVC host.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][hashtable]$Probe,
        [string]$ExpectedHost = 'x86_64-pc-windows-msvc'
    )

    $row = Test-ToolCommandCheck -Probe $Probe -Id 'rustc' -Title 'rustc' -CommandName 'rustc' `
        -Severity $script:SeverityBlocking -VersionArguments @('--version', '--verbose')
    if ($row.status -ne $script:StatusOk) { return $row }

    $exec = & $Probe['Exec'] $row.path @('--version', '--verbose')
    $hostMatch = [regex]::Match($exec.output, '(?im)^\s*host:\s*(\S+)\s*$')
    if (-not $hostMatch.Success) {
        return New-PreflightCheck -Id 'rustc' -Title 'rustc' -Severity $script:SeverityBlocking -Status $script:StatusWarn `
            -Version $row.version -Path $row.path -Details 'Could not determine the rustc target host from `rustc --version --verbose`.'
    }

    $hostName = $hostMatch.Groups[1].Value
    if ($hostName -ne $ExpectedHost) {
        return New-PreflightCheck -Id 'rustc' -Title 'rustc' -Severity $script:SeverityBlocking -Status $script:StatusWarn `
            -Version $row.version -Path $row.path `
            -Details ("Target host is '$hostName' but SPEC-M00 D-5 requires '$ExpectedHost'.") `
            -FixHint ([string]$script:FixHints['rustc'])
    }

    return New-PreflightCheck -Id 'rustc' -Title 'rustc' -Severity $script:SeverityBlocking -Status $script:StatusOk `
        -Version $row.version -Path $row.path -Details ("MSVC target host confirmed: $hostName")
}

function Test-MsvcBuildToolsCheck {
    <#
    .SYNOPSIS
        MSVC C++ Build Tools via vswhere. Covers the "vswhere.exe missing" path: that is
        reported as UNKNOWN (cannot determine), never as a crash.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][hashtable]$Probe)

    $vswhereArgs = @(
        '-latest', '-products', '*',
        '-requires', 'Microsoft.VisualStudio.Component.VC.Tools.x86.x64',
        '-property', 'installationPath'
    )
    $vswhere = & $Probe['Vswhere'] $vswhereArgs

    if (-not $vswhere.available) {
        return New-PreflightCheck -Id 'msvc' -Title 'MSVC C++ Build Tools' -Severity $script:SeverityBlocking `
            -Status $script:StatusUnknown `
            -Details 'vswhere.exe was not found in the Visual Studio Installer directories, so MSVC cannot be confirmed either way.' `
            -FixHint ([string]$script:FixHints['msvc'])
    }

    if ($vswhere.exitCode -ne 0) {
        return New-PreflightCheck -Id 'msvc' -Title 'MSVC C++ Build Tools' -Severity $script:SeverityBlocking `
            -Status $script:StatusUnknown -Path $vswhere.path `
            -Details "vswhere.exe exists but returned exit code $($vswhere.exitCode)." `
            -FixHint ([string]$script:FixHints['msvc'])
    }

    $installPath = (Get-FirstLine $vswhere.output)
    if ([string]::IsNullOrEmpty($installPath)) {
        return New-PreflightCheck -Id 'msvc' -Title 'MSVC C++ Build Tools' -Severity $script:SeverityBlocking `
            -Status $script:StatusMissing -Path $vswhere.path `
            -Details 'vswhere.exe is present but reports no installation with the C++ build tools component.' `
            -FixHint ([string]$script:FixHints['msvc'])
    }

    return New-PreflightCheck -Id 'msvc' -Title 'MSVC C++ Build Tools' -Severity $script:SeverityBlocking `
        -Status $script:StatusOk -Path $installPath `
        -Details ("Component Microsoft.VisualStudio.Component.VC.Tools.x86.x64 found; vswhere: " + $vswhere.path)
}

function Test-WebView2Check {
    <#
    .SYNOPSIS
        WebView2 Evergreen Runtime via the EdgeUpdate client registry keys. Covers the
        "registry key missing" path: reported as MISSING with a fix hint, without failing
        the script in report mode.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][hashtable]$Probe,
        [string[]]$RegistryPaths = $null
    )

    if ($null -eq $RegistryPaths) { $RegistryPaths = $script:WebView2RegistryPaths }

    $attempted = @()
    foreach ($regPath in $RegistryPaths) {
        $read = & $Probe['Registry'] $regPath 'pv'
        $attempted += $regPath
        if ($read.readable -and -not [string]::IsNullOrEmpty($read.value)) {
            return New-PreflightCheck -Id 'webview2' -Title 'WebView2 Runtime' -Severity $script:SeverityBlocking `
                -Status $script:StatusOk -Version $read.value -Path $regPath `
                -Details 'Evergreen WebView2 Runtime detected via the EdgeUpdate client registry key.'
        }
    }

    return New-PreflightCheck -Id 'webview2' -Title 'WebView2 Runtime' -Severity $script:SeverityBlocking `
        -Status $script:StatusMissing `
        -Details ("No 'pv' value found under any of the expected EdgeUpdate client keys ($($attempted.Count) checked).") `
        -FixHint ([string]$script:FixHints['webview2'])
}

function Test-VbscriptCheck {
    <#
    .SYNOPSIS
        VBSCRIPT optional feature. ADVISORY ONLY: SPEC-M00 section 3.3 makes this an MSI
        packaging prerequisite, not a current development blocker. When the capability API
        needs elevation the result is UNKNOWN, which never blocks.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][hashtable]$Probe,
        [string]$CapabilityPattern = '*VBSCRIPT*'
    )

    $cap = & $Probe['Capability'] $CapabilityPattern
    $dllPath = Join-Path $env:SystemRoot 'System32\vbscript.dll'
    $dllPresent = & $Probe['File'] $dllPath

    if ($cap.available) {
        if ($cap.state -eq 'Installed') {
            return New-PreflightCheck -Id 'vbscript' -Title 'VBSCRIPT optional feature (MSI prerequisite)' `
                -Severity $script:SeverityAdvisory -Status $script:StatusOk -Version $cap.state -Path $cap.name `
                -Details 'Reported Installed by Get-WindowsCapability. MSI packaging prerequisite satisfied.'
        }
        return New-PreflightCheck -Id 'vbscript' -Title 'VBSCRIPT optional feature (MSI prerequisite)' `
            -Severity $script:SeverityAdvisory -Status $script:StatusMissing -Version $cap.state -Path $cap.name `
            -Details "Capability state is '$($cap.state)'. MSI (WiX) packaging may fail on Windows 11 24H2 and later." `
            -FixHint ([string]$script:FixHints['vbscript'])
    }

    $detail = 'Get-WindowsCapability -Online requires an elevated shell, so the optional-feature state could not be read.'
    if ($dllPresent) {
        $detail += ' vbscript.dll is present in System32, but presence alone does not prove the feature is enabled.'
    }
    else {
        $detail += ' vbscript.dll was not found in System32 either.'
    }
    return New-PreflightCheck -Id 'vbscript' -Title 'VBSCRIPT optional feature (MSI prerequisite)' `
        -Severity $script:SeverityAdvisory -Status $script:StatusUnknown `
        -Details $detail -FixHint ([string]$script:FixHints['vbscript'])
}

# ---------------------------------------------------------------------------
# Orchestration
# ---------------------------------------------------------------------------

function Get-PreflightHostInfo {
    [CmdletBinding()]
    param([string]$RepoRoot)

    $os = $null
    try { $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop } catch { $os = $null }

    $isElevated = $false
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $isElevated = (New-Object Security.Principal.WindowsPrincipal($identity)).IsInRole(
            [Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch { $isElevated = $false }

    $caption = ''
    $version = [string][System.Environment]::OSVersion.Version
    if ($null -ne $os) {
        $caption = [string]$os.Caption
        $version = [string]$os.Version
    }

    return [pscustomobject]@{
        computerName      = [string]$env:COMPUTERNAME
        osCaption         = $caption
        osVersion         = $version
        powerShellVersion = [string]$PSVersionTable.PSVersion
        isElevated        = $isElevated
        repoRoot          = $RepoRoot
    }
}

function Invoke-Preflight {
    <#
    .SYNOPSIS
        Run every check and return the report object. Takes the probe set as a parameter so
        tests can inject fakes.
    #>
    [CmdletBinding()]
    param(
        [hashtable]$Probe = $null,
        [string]$RepoRoot = '',
        [bool]$RequireReadyMode = $false
    )

    if ($null -eq $Probe) { $Probe = Get-RealProbes }
    if ([string]::IsNullOrEmpty($RepoRoot)) { $RepoRoot = (Get-PreflightRepoRoot) }

    $checks = New-Object System.Collections.ArrayList
    $null = $checks.Add((Test-ToolCommandCheck -Probe $Probe -Id 'git' -Title 'Git' -CommandName 'git' `
        -Severity $script:SeverityBlocking -VersionArguments @('--version') -MissingDetails 'Git was not found on PATH.'))
    $null = $checks.Add((Test-NodeCheck -Probe $Probe))
    $null = $checks.Add((Test-ToolCommandCheck -Probe $Probe -Id 'npm' -Title 'npm' -CommandName 'npm' `
        -Severity $script:SeverityInfo -VersionArguments @('--version') -MissingDetails 'npm was not found on PATH (only needed to bootstrap pnpm).'))
    $null = $checks.Add((Test-ToolCommandCheck -Probe $Probe -Id 'corepack' -Title 'Corepack' -CommandName 'corepack' `
        -Severity $script:SeverityAdvisory -VersionArguments @('--version') -MissingDetails 'corepack was not found on PATH. Alternatives: npm install -g pnpm.'))
    $null = $checks.Add((Test-ToolCommandCheck -Probe $Probe -Id 'pnpm' -Title 'pnpm' -CommandName 'pnpm' `
        -Severity $script:SeverityBlocking -VersionArguments @('--version') -MissingDetails 'pnpm was not found on PATH.'))
    $null = $checks.Add((Test-ToolCommandCheck -Probe $Probe -Id 'uv' -Title 'uv' -CommandName 'uv' `
        -Severity $script:SeverityBlocking -VersionArguments @('--version') -MissingDetails 'uv was not found on PATH.'))
    $null = $checks.Add((Test-PythonCheck -Probe $Probe -ExpectedMinor $script:ExpectedPythonMinor))
    $null = $checks.Add((Test-ToolCommandCheck -Probe $Probe -Id 'rustup' -Title 'rustup' -CommandName 'rustup' `
        -Severity $script:SeverityAdvisory -VersionArguments @('--version') -MissingDetails 'rustup was not found on PATH.'))
    $null = $checks.Add((Test-RustHostCheck -Probe $Probe -ExpectedHost $script:ExpectedRustHost))
    $null = $checks.Add((Test-ToolCommandCheck -Probe $Probe -Id 'cargo' -Title 'cargo' -CommandName 'cargo' `
        -Severity $script:SeverityBlocking -VersionArguments @('--version') -MissingDetails 'cargo was not found on PATH.'))
    $null = $checks.Add((Test-MsvcBuildToolsCheck -Probe $Probe))
    $null = $checks.Add((Test-WebView2Check -Probe $Probe))
    $null = $checks.Add((Test-VbscriptCheck -Probe $Probe))

    return New-PreflightReport -Checks $checks.ToArray() -HostInfo (Get-PreflightHostInfo -RepoRoot $RepoRoot) `
        -RequireReadyMode $RequireReadyMode
}

function Get-PreflightRepoRoot {
    [CmdletBinding()]
    param()

    if (-not [string]::IsNullOrEmpty($PSScriptRoot)) {
        $parent = Split-Path -Path $PSScriptRoot -Parent
        if (-not [string]::IsNullOrEmpty($parent)) {
            return $parent
        }
        return $PSScriptRoot
    }
    return (Get-Location).Path
}

function Get-PreflightSeverityLabel {
    [CmdletBinding()]
    param([string]$Severity)

    switch ($Severity) {
        'Blocking' { return 'BLOCKING ' }
        'Advisory' { return 'ADVISORY ' }
        default { return 'INFO     ' }
    }
}

function Format-PreflightSummary {
    <#
    .SYNOPSIS
        Human-readable summary. ASCII only, so it renders correctly in any Windows console.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Report)

    $lines = New-Object System.Collections.ArrayList
    $null = $lines.Add("EngMentor development environment preflight (read-only)  v$($Report.toolVersion)")
    $null = $lines.Add("Generated (UTC): $($Report.generatedAtUtc)")
    if ($null -ne $Report.host) {
        $null = $lines.Add("Host: $($Report.host.osCaption) $($Report.host.osVersion) | PowerShell $($Report.host.powerShellVersion) | elevated: $($Report.host.isElevated)")
        $null = $lines.Add("Repo: $($Report.host.repoRoot)")
    }
    $null = $lines.Add('Mode: report (no installs, no environment changes)')
    $null = $lines.Add('')

    foreach ($severity in $script:SeverityOrder) {
        $rows = @($Report.checks | Where-Object { $_.severity -eq $severity })
        if ($rows.Count -eq 0) { continue }

        $groupHeading = "$severity (not a blocker)"
        if ($severity -eq $script:SeverityBlocking) {
            $groupHeading = 'BLOCKING (required for T010)'
        }
        $null = $lines.Add("[$groupHeading]")

        foreach ($row in $rows) {
            $version = $row.version
            if ([string]::IsNullOrEmpty($version)) { $version = '-' }
            $line = "  {0,-7} {1,-11} {2,-26} {3}" -f $row.status, (Get-PreflightSeverityLabel $row.severity).Trim(), $row.id, $version
            $null = $lines.Add($line.TrimEnd())
            if ($row.status -ne $script:StatusOk) {
                if (-not [string]::IsNullOrEmpty($row.path)) {
                    $null = $lines.Add("          path: $($row.path)")
                }
                $null = $lines.Add("          note: $($row.details)")
                if (-not [string]::IsNullOrEmpty($row.fixHint)) {
                    $null = $lines.Add("          fix : $($row.fixHint)")
                }
            }
        }
        $null = $lines.Add('')
    }

    $null = $lines.Add("COUNTS  total=$($Report.counts.total) ok=$($Report.counts.ok) missing=$($Report.counts.missing) warn=$($Report.counts.warn) unknown=$($Report.counts.unknown) skip=$($Report.counts.skip)")
    if ($Report.verdict -eq 'Ready') {
        $null = $lines.Add('VERDICT Ready - every Blocking item is OK.')
    }
    else {
        $null = $lines.Add("VERDICT NotReady - Blocking items not OK: $($Report.blockingNotOk -join ', ')")
        $null = $lines.Add('        Each item above carries its recommended install method. Installation is a separate, user-approved step.')
    }

    return ($lines -join [Environment]::NewLine)
}

function Write-PreflightJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$Report,
        [Parameter(Mandatory = $true)][string]$Directory
    )

    if (-not (Test-Path -LiteralPath $Directory -PathType Container)) {
        $null = New-Item -ItemType Directory -Path $Directory -Force
    }
    $stamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
    $file = Join-Path $Directory ("preflight-$stamp.json")
    $Report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $file -Encoding UTF8
    return $file
}

function Get-PreflightDefaultOutputDirectory {
    [CmdletBinding()]
    param([string]$RepoRoot)

    if ([string]::IsNullOrEmpty($RepoRoot)) { $RepoRoot = Get-PreflightRepoRoot }
    return (Join-Path $RepoRoot 'tmp\preflight')
}

# ---------------------------------------------------------------------------
# Self test: the four required paths, driven entirely by fake probes.
# ---------------------------------------------------------------------------

function New-FakeProbeSet {
    <#
    .SYNOPSIS
        Build a fake probe set. $Commands lists the command names that "exist" on PATH;
        $Versions maps a command name to the version string it reports.
    #>
    [CmdletBinding()]
    param(
        [string[]]$Commands = @(),
        [hashtable]$Versions = @{},
        [bool]$VswhereAvailable = $true,
        [string]$VswhereOutput = 'C:\Program Files\Microsoft Visual Studio\2022\BuildTools',
        [bool]$WebView2Present = $true,
        [bool]$CapabilityAvailable = $true,
        [string]$CapabilityState = 'Installed',
        [bool]$VbscriptDllPresent = $true
    )

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
        $output = ''
        if ($Versions.ContainsKey($name)) {
            $output = [string]$Versions[$name]
        }
        else {
            $output = "$name fake 0.0.0"
        }
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
        return [pscustomobject]@{ available = $true; path = 'C:\fake\vswhere.exe'; exitCode = 0; output = $VswhereOutput }
    }.GetNewClosure()

    $probes['Registry'] = {
        param($Path, $ValueName)
        if ($WebView2Present) {
            return [pscustomobject]@{ readable = $true; value = '124.0.2478.109'; error = '' }
        }
        return [pscustomobject]@{ readable = $false; value = ''; error = 'key not present' }
    }.GetNewClosure()

    $probes['File'] = {
        param($Path)
        return $VbscriptDllPresent
    }.GetNewClosure()

    $probes['Capability'] = {
        param($NamePattern)
        if (-not $CapabilityAvailable) {
            return [pscustomobject]@{ available = $false; found = $false; name = ''; state = ''; error = 'requires elevation' }
        }
        return [pscustomobject]@{ available = $true; found = $true; name = "VBSCRIPT~~~~0.0.1.0"; state = $CapabilityState; error = '' }
    }.GetNewClosure()

    return $probes
}

function Get-FullToolSetVersions {
    [CmdletBinding()]
    param()

    return @{
        'git'      = 'git version 2.51.0.windows.1'
        'node'     = 'v22.20.0'
        'npm'      = '10.9.3'
        'corepack' = '0.29.4'
        'pnpm'     = '10.0.0'
        'uv'       = 'uv 0.5.0'
        'rustup'   = 'rustup 1.27.1 (fake)'
        'rustc'    = "rustc 1.81.0`nhost: x86_64-pc-windows-msvc"
        'cargo'    = 'cargo 1.81.0'
    }
}

function Get-PreflightSelfTestScenarios {
    <#
    .SYNOPSIS
        The four required scenarios. Pure data: probers are injected, nothing real is touched.
    #>
    [CmdletBinding()]
    param()

    $allCommands = @('git', 'node', 'npm', 'corepack', 'pnpm', 'uv', 'py', 'python', 'rustup', 'rustc', 'cargo')

    return @(
        [pscustomobject]@{
            name        = 'tools-present'
            description = 'Every tool resolves; vswhere, registry and capability probes all answer.'
            probe       = (New-FakeProbeSet -Commands $allCommands -Versions (Get-FullToolSetVersions))
            expect      = @{ 'pnpm' = 'OK'; 'uv' = 'OK'; 'rustc' = 'OK'; 'msvc' = 'OK'; 'webview2' = 'OK'; 'vbscript' = 'OK'; 'verdict' = 'Ready' }
        },
        [pscustomobject]@{
            name        = 'tools-missing'
            description = 'pnpm, uv, rustup, rustc and cargo are absent; the script must still finish and report them.'
            probe       = (New-FakeProbeSet -Commands @('git', 'node', 'npm', 'py') -Versions (Get-FullToolSetVersions))
            expect      = @{ 'pnpm' = 'MISSING'; 'uv' = 'MISSING'; 'rustc' = 'MISSING'; 'cargo' = 'MISSING'; 'msvc' = 'OK'; 'verdict' = 'NotReady' }
        },
        [pscustomobject]@{
            name        = 'vswhere-missing'
            description = 'vswhere.exe is absent, so MSVC must be UNKNOWN rather than a crash or a false MISSING.'
            probe       = (New-FakeProbeSet -Commands $allCommands -Versions (Get-FullToolSetVersions) -VswhereAvailable $false)
            expect      = @{ 'msvc' = 'UNKNOWN'; 'pnpm' = 'OK'; 'verdict' = 'NotReady' }
        },
        [pscustomobject]@{
            name        = 'registry-key-missing'
            description = 'WebView2 registry keys are absent and the capability API needs elevation; neither may crash.'
            probe       = (New-FakeProbeSet -Commands $allCommands -Versions (Get-FullToolSetVersions) -WebView2Present $false -CapabilityAvailable $false -VbscriptDllPresent $false)
            expect      = @{ 'webview2' = 'MISSING'; 'vbscript' = 'UNKNOWN'; 'pnpm' = 'OK'; 'verdict' = 'NotReady' }
        }
    )
}

function Test-PreflightSelfTest {
    <#
    .SYNOPSIS
        Run the four scenarios and assert expected statuses plus exit-code behaviour.
        Returns $true when every assertion passes.
    #>
    [CmdletBinding()]
    param()

    $passed = 0
    $failed = 0

    foreach ($scenario in (Get-PreflightSelfTestScenarios)) {
        Write-Host ("[scenario] {0} - {1}" -f $scenario.name, $scenario.description)
        $report = Invoke-Preflight -Probe $scenario.probe -RepoRoot 'C:\fake\repo' -RequireReadyMode $false

        foreach ($expectedId in $scenario.expect.Keys) {
            $expected = $scenario.expect[$expectedId]
            if ($expectedId -eq 'verdict') {
                $actual = $report.verdict
            }
            else {
                $row = $report.checks | Where-Object { $_.id -eq $expectedId } | Select-Object -First 1
                if ($null -eq $row) {
                    $actual = '<no such check>'
                }
                else {
                    $actual = $row.status
                }
            }

            if ($actual -eq $expected) {
                $passed++
                Write-Host ("  PASS  {0} = {1}" -f $expectedId, $actual)
            }
            else {
                $failed++
                Write-Host ("  FAIL  {0} = {1} (expected {2})" -f $expectedId, $actual, $expected)
            }
        }

        # Report mode must never fail, even for the NotReady scenarios.
        $reportExit = Get-PreflightExitCode -Report $report -RequireReadyMode $false
        if ($reportExit -eq 0) {
            $passed++
            Write-Host "  PASS  report-mode exit code = 0"
        }
        else {
            $failed++
            Write-Host ("  FAIL  report-mode exit code = {0} (expected 0)" -f $reportExit)
        }

        # -RequireReady must fail exactly when the verdict is NotReady.
        $gateExit = Get-PreflightExitCode -Report $report -RequireReadyMode $true
        $expectedGate = 0
        if ($report.verdict -eq 'NotReady') { $expectedGate = 1 }
        if ($gateExit -eq $expectedGate) {
            $passed++
            Write-Host ("  PASS  -RequireReady exit code = {0}" -f $gateExit)
        }
        else {
            $failed++
            Write-Host ("  FAIL  -RequireReady exit code = {0} (expected {1})" -f $gateExit, $expectedGate)
        }
        Write-Host ''
    }

    Write-Host ("[self-test] passed={0} failed={1}" -f $passed, $failed)
    return ($failed -eq 0)
}

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

function Invoke-PreflightMain {
    [CmdletBinding()]
    param(
        [bool]$RequireReadyMode,
        [bool]$WriteJson,
        [string]$Directory,
        [bool]$SuppressSummary,
        [hashtable]$Probe = $null,
        [string]$RepoRoot = ''
    )

    if ($null -eq $Probe) { $Probe = Get-RealProbes }
    if ([string]::IsNullOrEmpty($RepoRoot)) { $RepoRoot = Get-PreflightRepoRoot }
    if ([string]::IsNullOrEmpty($Directory)) { $Directory = Get-PreflightDefaultOutputDirectory -RepoRoot $RepoRoot }

    $report = Invoke-Preflight -Probe $Probe -RepoRoot $RepoRoot -RequireReadyMode $RequireReadyMode

    if (-not $SuppressSummary) {
        Write-Host (Format-PreflightSummary -Report $report)
        Write-Host ''
    }

    if ($WriteJson) {
        try {
            $file = Write-PreflightJson -Report $report -Directory $Directory
            if (-not $SuppressSummary) {
                Write-Host "JSON report: $file"
                Write-Host '(temp directory is gitignored; nothing else was written)'
                Write-Host ''
            }
        }
        catch {
            # A report write failure must not be mistaken for a toolchain failure.
            Write-Warning "Could not write the JSON report to '$Directory': $($_.Exception.Message)"
        }
    }

    return (Get-PreflightExitCode -Report $report -RequireReadyMode $RequireReadyMode)
}

$isDotSourced = $false
if ($MyInvocation.InvocationName -eq '.') { $isDotSourced = $true }

if (-not $LibraryOnly -and -not $isDotSourced) {
    if ($SelfTest) {
        $selfTestPassed = Test-PreflightSelfTest
        if ($selfTestPassed) { exit 0 }
        exit 2
    }

    $exitCode = Invoke-PreflightMain -RequireReadyMode ([bool]$RequireReady) -WriteJson (-not $NoJson) `
        -Directory $OutputDirectory -SuppressSummary ([bool]$Quiet)
    exit $exitCode
}
