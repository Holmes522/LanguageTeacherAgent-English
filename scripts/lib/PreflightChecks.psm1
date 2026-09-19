<#
.SYNOPSIS
    Check logic for the EngMentor development environment preflight (M00 / T010).

.DESCRIPTION
    Read-only toolchain inventory for docs/specs/SPEC-M00-foundation-contracts.md section 3.2.
    The CLI entry point lives in scripts/preflight.ps1; this module holds the checks so the
    entry script stays short and the checks stay testable.

    Nothing here installs, modifies or deletes anything. Probes only: resolve commands, run
    version-style commands, read registry values, test paths, query optional Windows
    capabilities. No secrets are read, printed or persisted.

    Automated tests live in scripts/tests/preflight.Tests.ps1 (Pester) and drive these
    functions through injected fake probes via the -Probe parameter.

.NOTES
    Version : 2.0.0
    Target  : Windows PowerShell 5.1+ and PowerShell 7+
    Encoding: ASCII only, so Windows PowerShell 5.1 reads it correctly under any code page.
#>

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Continue'

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

$script:PreflightVersion = '2.0.1'
$script:SchemaVersion = '1.0'
$script:JsonSchemaFileName = 'preflight.schema.json'

$script:SeverityBlocking = 'Blocking'
$script:SeverityAdvisory = 'Advisory'
$script:SeverityInfo = 'Info'
$script:SeverityOrder = @($script:SeverityBlocking, $script:SeverityAdvisory, $script:SeverityInfo)

$script:StatusOk = 'OK'
$script:StatusMissing = 'MISSING'
$script:StatusWarn = 'WARN'
$script:StatusUnknown = 'UNKNOWN'
$script:StatusSkip = 'SKIP'

$script:ExpectedNodeMajor = 22
$script:ExpectedPythonMinor = '3.12'
$script:ExpectedRustHost = 'x86_64-pc-windows-msvc'

# Windows SDK: the installer records its root here; Include\ and Lib\ are then verified.
$script:WindowsSdkRegistryPaths = @(
    'HKLM:\SOFTWARE\Microsoft\Windows Kits\Installed Roots',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows Kits\Installed Roots'
)
$script:WindowsSdkRegistryValueName = 'KitsRoot10'

# WebView2 Evergreen Runtime product GUID used by the EdgeUpdate client registry keys.
$script:WebView2ClientGuid = '{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}'
$script:WebView2RegistryPaths = @(
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\$($script:WebView2ClientGuid)",
    "HKLM:\SOFTWARE\Microsoft\EdgeUpdate\Clients\$($script:WebView2ClientGuid)",
    "HKCU:\Software\Microsoft\EdgeUpdate\Clients\$($script:WebView2ClientGuid)"
)

$script:VcToolsComponent = 'Microsoft.VisualStudio.Component.VC.Tools.x86.x64'

$script:PackageIdHints = @{
    'pnpm'   = 'pnpm@<exact version> via `npm install -g pnpm` (or Corepack). Verify the recommended channel with `winget search pnpm` in the install phase.'
    'uv'     = 'astral-sh.uv - verify with `winget search uv` in the install phase.'
    'rustup' = 'Rustlang.Rustup - verify with `winget search rustup` in the install phase.'
    'msvc'   = 'Microsoft.VisualStudio.2022.BuildTools with workload Microsoft.VisualStudio.Workload.VCTools - verify in the install phase.'
    'webview2' = 'Microsoft.EdgeWebView2Runtime - verify with `winget search webview2` in the install phase.'
}

$script:FixHints = @{
    'corepack' = 'Optional bootstrap path: `corepack enable` then `corepack prepare pnpm@<version> --activate` (Node 22 still bundles corepack).'
    'pnpm'     = 'Official: `npm install -g pnpm`, or corepack as above. Pin the exact version in the root package.json "packageManager" field. See https://pnpm.io/installation'
    'uv'       = 'Official: `winget install --id=astral-sh.uv -e`, or https://docs.astral.sh/uv/getting-started/installation/ . Do not pipe remote scripts into a shell on a project machine.'
    'python312' = 'Preferred: let uv manage it - `uv python install 3.12` (project pins 3.12 via .python-version). Alternative: python.org 3.12 installer. Do NOT point the project at the system 3.13 interpreter.'
    'rustup'   = 'Official: `winget install --id=Rustlang.Rustup -e`, or https://rustup.rs/'
    'rustc'    = 'Install the Rust toolchain via rustup, then `rustup default <exact version>-x86_64-pc-windows-msvc`. SPEC-M00 D-5 requires an exact version in rust-toolchain.toml, not "stable".'
    'cargo'    = 'Ships with the Rust toolchain installed by rustup.'
    'msvc'     = 'Install Visual Studio 2022 Build Tools with the "Desktop development with C++" workload (provides the VC tools, link.exe and the Windows SDK). Workload id Microsoft.VisualStudio.Workload.VCTools.'
    'webview2' = 'Install the Microsoft Edge WebView2 Evergreen Runtime (usually preinstalled on Windows 11).'
    'vbscript' = 'MSI packaging prerequisite only, not a current development blocker. Enable the VBSCRIPT optional feature from an ELEVATED shell, or compare against the NSIS packaging route in the T001 ADR.'
    'winget'   = 'Info only: the install phase may use winget as one channel. If absent, install pnpm via npm/Corepack and uv/Rust via their official installers.'
}

# ---------------------------------------------------------------------------
# Result and report construction (pure data)
# ---------------------------------------------------------------------------

function New-PreflightCheck {
    <#
    .SYNOPSIS
        Build one check result row.
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

    if (-not $RequireReadyMode) { return 0 }
    if ($Report.verdict -eq 'Ready') { return 0 }
    return 1
}

function New-PreflightReport {
    <#
    .SYNOPSIS
        Assemble the report object from check rows.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Checks,
        [Parameter(Mandatory = $true)][object]$HostInfo,
        [Parameter(Mandatory = $true)][bool]$RequireReadyMode
    )

    $blockingNotOk = @($Checks | Where-Object { $_.severity -eq $script:SeverityBlocking -and $_.status -ne $script:StatusOk })
    $verdict = 'Ready'
    if ($blockingNotOk.Count -gt 0) { $verdict = 'NotReady' }

    $counts = [pscustomobject]@{
        total   = $Checks.Count
        ok      = @($Checks | Where-Object { $_.status -eq $script:StatusOk }).Count
        missing = @($Checks | Where-Object { $_.status -eq $script:StatusMissing }).Count
        warn    = @($Checks | Where-Object { $_.status -eq $script:StatusWarn }).Count
        unknown = @($Checks | Where-Object { $_.status -eq $script:StatusUnknown }).Count
        skip    = @($Checks | Where-Object { $_.status -eq $script:StatusSkip }).Count
    }

    $report = [pscustomobject]@{
        schemaVersion  = $script:SchemaVersion
        tool           = 'scripts/preflight.ps1'
        toolVersion    = $script:PreflightVersion
        generatedAtUtc = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        host           = $HostInfo
        verdict        = $verdict
        exitCode       = 0
        counts         = $counts
        blockingNotOk  = @($blockingNotOk | ForEach-Object { $_.id })
        checks         = $Checks
    }
    $report.exitCode = Get-PreflightExitCode -Report $report -RequireReadyMode $RequireReadyMode
    return $report
}

# ---------------------------------------------------------------------------
# Real probes (the injectable seam). Tests replace these with fakes.
# ---------------------------------------------------------------------------

function Get-VswhereCandidatePaths {
    <#
    .SYNOPSIS
        Candidate locations of vswhere.exe. The Visual Studio Installer ships it under the
        32-bit Program Files root even on 64-bit Windows, so both roots are offered.
    #>
    [CmdletBinding()]
    param()

    $candidates = @()
    foreach ($root in @(${env:ProgramFiles(x86)}, $env:ProgramFiles)) {
        if (-not [string]::IsNullOrEmpty($root)) {
            $candidates += (Join-Path $root 'Microsoft Visual Studio\Installer\vswhere.exe')
        }
    }
    return $candidates
}

function Get-RealProbes {
    <#
    .SYNOPSIS
        Build the default probe set. Every probe is read-only.

    .PARAMETER VswhereCandidates
        vswhere.exe locations to probe. Defaults to Get-VswhereCandidatePaths; injectable so
        the probe can be tested without depending on this machine's Visual Studio layout.

    .NOTES
        Each probe is a closure created with GetNewClosure(), which copies the *local*
        variables in scope. Anything a probe needs must therefore be a local variable (a
        parameter works); module-scope values are not visible from inside a closure.
    #>
    [CmdletBinding()]
    param([string[]]$VswhereCandidates = $null)

    if ($null -eq $VswhereCandidates) { $VswhereCandidates = Get-VswhereCandidatePaths }

    $probes = @{}

    $probes['Command'] = {
        param($Name)
        $cmd = Get-Command -Name $Name -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($null -eq $cmd) { return $null }
        return [pscustomobject]@{ name = $Name; path = [string]$cmd.Source; type = [string]$cmd.CommandType }
    }.GetNewClosure()

    $probes['Exec'] = {
        param($FilePath, $Arguments)
        try {
            $LASTEXITCODE = 0
            $output = & $FilePath @Arguments 2>&1
            return [pscustomobject]@{ ran = $true; exitCode = [int]$LASTEXITCODE; output = (($output | Out-String).Trim()) }
        }
        catch {
            return [pscustomobject]@{ ran = $false; exitCode = -1; output = [string]$_.Exception.Message }
        }
    }.GetNewClosure()

    $probes['Vswhere'] = {
        param($Arguments)
        $found = ''
        # $VswhereCandidates is the enclosing function's parameter, which GetNewClosure()
        # captures. Do not read a $script:-scoped value here: it is not visible the moment
        # this block is rebound into its own module.
        foreach ($candidate in $VswhereCandidates) {
            if ($null -ne $candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf -ErrorAction SilentlyContinue)) {
                $found = $candidate
                break
            }
        }
        if ([string]::IsNullOrEmpty($found)) {
            return [pscustomobject]@{ available = $false; path = ''; exitCode = -1; output = '' }
        }
        $exec = & $probes['Exec'] $found $Arguments
        return [pscustomobject]@{ available = $true; path = $found; exitCode = $exec.exitCode; output = $exec.output }
    }.GetNewClosure()

    $probes['Registry'] = {
        param($Path, $ValueName)
        try {
            if (-not (Test-Path -LiteralPath $Path -ErrorAction SilentlyContinue)) {
                return [pscustomobject]@{ readable = $false; value = ''; error = 'key not present' }
            }
            $item = Get-ItemProperty -LiteralPath $Path -Name $ValueName -ErrorAction Stop
            return [pscustomobject]@{ readable = $true; value = [string]$item.$ValueName; error = '' }
        }
        catch {
            return [pscustomobject]@{ readable = $false; value = ''; error = [string]$_.Exception.Message }
        }
    }.GetNewClosure()

    $probes['File'] = {
        param($Path)
        if ([string]::IsNullOrEmpty($Path)) { return $false }
        return (Test-Path -LiteralPath $Path -PathType Leaf -ErrorAction SilentlyContinue)
    }.GetNewClosure()

    $probes['Directory'] = {
        param($Path)
        if ([string]::IsNullOrEmpty($Path)) { return $false }
        return (Test-Path -LiteralPath $Path -PathType Container -ErrorAction SilentlyContinue)
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

# ---------------------------------------------------------------------------
# Checks. Each returns exactly one New-PreflightCheck row.
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
        $details = $MissingDetails
        if ([string]::IsNullOrEmpty($details)) { $details = "Command '$CommandName' was not found on PATH." }
        return New-PreflightCheck -Id $Id -Title $Title -Severity $Severity -Status $script:StatusMissing `
            -Details $details -FixHint ([string]$script:FixHints[$Id])
    }

    $exec = & $Probe['Exec'] $resolved.path $VersionArguments
    if (-not $exec.ran) {
        return New-PreflightCheck -Id $Id -Title $Title -Severity $Severity -Status $script:StatusWarn `
            -Path $resolved.path `
            -Details "Command found but '$CommandName $($VersionArguments -join ' ')' could not be executed: $($exec.output)" `
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

    $uv = & $Probe['Command'] 'uv'
    if ($null -ne $uv) {
        $exec = & $Probe['Exec'] $uv.path @('python', 'list')
        if ($exec.ran -and $exec.output -match [regex]::Escape($ExpectedMinor)) {
            $sources += "uv-managed interpreter matching $ExpectedMinor"
        }
    }

    $py = & $Probe['Command'] 'py'
    if ($null -ne $py) {
        $exec = & $Probe['Exec'] $py.path @("-$ExpectedMinor", '--version')
        if ($exec.ran -and $exec.output -match [regex]::Escape($ExpectedMinor)) {
            $sources += "py launcher -$ExpectedMinor"
        }
    }

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
        -Status $script:StatusOk -Version $ExpectedMinor -Details ("Available via: " + ($sources -join '; ') + ".")
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
        Windows C++ build environment. Three things must all hold:
          1. vswhere reports an installation with the VC tools component
          2. link.exe is present in that installation
          3. the Windows SDK root is registered with Include\ and Lib\ directories
        Any one of them missing makes this Blocking-not-ready (MISSING). A vswhere that
        cannot answer is UNKNOWN, which is deliberately distinct from "missing".
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][hashtable]$Probe,
        [string]$Component = 'Microsoft.VisualStudio.Component.VC.Tools.x86.x64',
        [string]$SdkRegistryValueName = 'KitsRoot10',
        [string[]]$SdkRegistryPaths = $null
    )

    if ($null -eq $SdkRegistryPaths) { $SdkRegistryPaths = $script:WindowsSdkRegistryPaths }

    $installArgs = @('-latest', '-products', '*', '-requires', $Component, '-property', 'installationPath')
    $vswhere = & $Probe['Vswhere'] $installArgs

    if (-not $vswhere.available) {
        return New-PreflightCheck -Id 'msvc' -Title 'MSVC C++ build environment' -Severity $script:SeverityBlocking `
            -Status $script:StatusUnknown `
            -Details 'vswhere.exe was not found in the Visual Studio Installer directories, so the VC tools, link.exe and the Windows SDK cannot be confirmed either way.' `
            -FixHint ([string]$script:FixHints['msvc'])
    }

    if ($vswhere.exitCode -ne 0) {
        return New-PreflightCheck -Id 'msvc' -Title 'MSVC C++ build environment' -Severity $script:SeverityBlocking `
            -Status $script:StatusUnknown -Path $vswhere.path `
            -Details "vswhere.exe exists but returned exit code $($vswhere.exitCode) when asked for the VC tools installation path." `
            -FixHint ([string]$script:FixHints['msvc'])
    }

    $installPath = Get-FirstLine $vswhere.output
    if ([string]::IsNullOrEmpty($installPath)) {
        return New-PreflightCheck -Id 'msvc' -Title 'MSVC C++ build environment' -Severity $script:SeverityBlocking `
            -Status $script:StatusMissing -Path $vswhere.path `
            -Details "vswhere.exe reports no Visual Studio installation with component $Component (the C++ build tools workload is missing)." `
            -FixHint ([string]$script:FixHints['msvc'])
    }

    # link.exe: the MSVC linker must exist inside the detected installation.
    $linkProbeArgs = @('-latest', '-products', '*', '-requires', $Component, '-find', '**/VC/Tools/MSVC/**/bin/Hostx64/x64/link.exe')
    $linkResult = & $Probe['Vswhere'] $linkProbeArgs
    $linkPaths = @()
    if ($linkResult.available -and $linkResult.exitCode -eq 0 -and -not [string]::IsNullOrEmpty($linkResult.output)) {
        $linkPaths = @($linkResult.output -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_.Trim() })
    }

    if ($linkPaths.Count -eq 0) {
        # Older or non-standard layouts: accept any link.exe that vswhere can find.
        $anyLink = & $Probe['Vswhere'] @('-latest', '-products', '*', '-requires', $Component, '-find', '**/link.exe')
        if ($anyLink.available -and $anyLink.exitCode -eq 0 -and -not [string]::IsNullOrEmpty($anyLink.output)) {
            $linkPaths = @($anyLink.output -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_.Trim() })
        }
    }

    if ($linkPaths.Count -eq 0) {
        return New-PreflightCheck -Id 'msvc' -Title 'MSVC C++ build environment' -Severity $script:SeverityBlocking `
            -Status $script:StatusMissing -Path $installPath `
            -Details "VC tools component is installed at '$installPath' but link.exe was not found by vswhere, so the MSVC linker is not usable." `
            -FixHint ([string]$script:FixHints['msvc'])
    }

    # Windows SDK: the installer records its root in the registry.
    $sdkRoot = ''
    $sdkRegistryPath = ''
    foreach ($regPath in $SdkRegistryPaths) {
        $read = & $Probe['Registry'] $regPath $SdkRegistryValueName
        if ($read.readable -and -not [string]::IsNullOrEmpty($read.value)) {
            $sdkRoot = $read.value
            $sdkRegistryPath = $regPath
            break
        }
    }

    if ([string]::IsNullOrEmpty($sdkRoot)) {
        return New-PreflightCheck -Id 'msvc' -Title 'MSVC C++ build environment' -Severity $script:SeverityBlocking `
            -Status $script:StatusMissing -Path $installPath `
            -Details "VC tools and link.exe are present, but no Windows SDK root ('$SdkRegistryValueName') was found in the registry, so SDK headers and libraries are not usable." `
            -FixHint ([string]$script:FixHints['msvc'])
    }

    $sdkInclude = Join-Path $sdkRoot 'Include'
    $sdkLib = Join-Path $sdkRoot 'Lib'
    $hasInclude = & $Probe['Directory'] $sdkInclude
    $hasLib = & $Probe['Directory'] $sdkLib
    if (-not $hasInclude -or -not $hasLib) {
        $missingParts = @()
        if (-not $hasInclude) { $missingParts += $sdkInclude }
        if (-not $hasLib) { $missingParts += $sdkLib }
        return New-PreflightCheck -Id 'msvc' -Title 'MSVC C++ build environment' -Severity $script:SeverityBlocking `
            -Status $script:StatusMissing -Path $installPath `
            -Details ("SDK root '$sdkRoot' is registered but these directories are missing: " + ($missingParts -join ', ')) `
            -FixHint ([string]$script:FixHints['msvc'])
    }

    # Presence check only: a real compile is proven later by `cargo build --locked`.
    return New-PreflightCheck -Id 'msvc' -Title 'MSVC C++ build environment' -Severity $script:SeverityBlocking `
        -Status $script:StatusOk -Version "SDK $sdkRoot" -Path $installPath `
        -Details ("VC tools, link.exe ($($linkPaths[0])) and the Windows SDK ($sdkRegistryPath -> $sdkRoot with Include\ and Lib\) are all present. Presence check only; a real link is proven by the T010 build.")
}

function Test-WebView2Check {
    <#
    .SYNOPSIS
        WebView2 Evergreen Runtime via the EdgeUpdate client registry keys.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][hashtable]$Probe,
        [string[]]$RegistryPaths = $null
    )

    if ($null -eq $RegistryPaths) { $RegistryPaths = $script:WebView2RegistryPaths }

    $attempted = 0
    foreach ($regPath in $RegistryPaths) {
        $attempted++
        $read = & $Probe['Registry'] $regPath 'pv'
        if ($read.readable -and -not [string]::IsNullOrEmpty($read.value)) {
            return New-PreflightCheck -Id 'webview2' -Title 'WebView2 Runtime' -Severity $script:SeverityBlocking `
                -Status $script:StatusOk -Version $read.value -Path $regPath `
                -Details 'Evergreen WebView2 Runtime detected via the EdgeUpdate client registry key.'
        }
    }

    return New-PreflightCheck -Id 'webview2' -Title 'WebView2 Runtime' -Severity $script:SeverityBlocking `
        -Status $script:StatusMissing `
        -Details "No 'pv' value found under any of the expected EdgeUpdate client keys ($attempted checked)." `
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

function Test-WingetCheck {
    <#
    .SYNOPSIS
        Install-channel availability. INFO ONLY: winget may be one channel for installing the
        missing toolchain, but its absence is not a T010 blocker (pnpm can come from npm or
        Corepack, uv and Rust have official installers).

        This check never runs `winget search` or any install command. It only reports that the
        package ids in the summary still need verification during the install phase.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][hashtable]$Probe)

    $row = Test-ToolCommandCheck -Probe $Probe -Id 'winget' -Title 'winget (install channel)' -CommandName 'winget' `
        -Severity $script:SeverityInfo -VersionArguments @('--version') `
        -MissingDetails 'winget was not found on PATH. Not a blocker: pnpm can come from npm/Corepack, and uv and Rust ship official installers.'

    if ($row.status -eq $script:StatusOk) {
        $packageIds = @()
        foreach ($key in @('pnpm', 'uv', 'rustup', 'msvc', 'webview2')) {
            $packageIds += "$key -> $($script:PackageIdHints[$key])"
        }
        $row.details = 'winget is available as one install channel. Package ids still need verification in the install phase: ' + ($packageIds -join ' | ')
    }

    return $row
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

    $checks = New-Object System.Collections.ArrayList
    $null = $checks.Add((Test-ToolCommandCheck -Probe $Probe -Id 'git' -Title 'Git' -CommandName 'git' `
        -Severity $script:SeverityBlocking -VersionArguments @('--version') -MissingDetails 'Git was not found on PATH.'))
    $null = $checks.Add((Test-NodeCheck -Probe $Probe))
    $null = $checks.Add((Test-ToolCommandCheck -Probe $Probe -Id 'npm' -Title 'npm' -CommandName 'npm' `
        -Severity $script:SeverityInfo -VersionArguments @('--version') -MissingDetails 'npm was not found on PATH (only needed to bootstrap pnpm).'))
    $null = $checks.Add((Test-ToolCommandCheck -Probe $Probe -Id 'corepack' -Title 'Corepack' -CommandName 'corepack' `
        -Severity $script:SeverityAdvisory -VersionArguments @('--version') -MissingDetails 'corepack was not found on PATH. Alternative: npm install -g pnpm.'))
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
    $null = $checks.Add((Test-WingetCheck -Probe $Probe))

    return New-PreflightReport -Checks $checks.ToArray() -HostInfo (Get-PreflightHostInfo -RepoRoot $RepoRoot) `
        -RequireReadyMode $RequireReadyMode
}

# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------

function Get-PreflightSeverityLabel {
    [CmdletBinding()]
    param([string]$Severity)

    switch ($Severity) {
        'Blocking' { return 'BLOCKING' }
        'Advisory' { return 'ADVISORY' }
        default { return 'INFO' }
    }
}

function Format-PreflightSummary {
    <#
    .SYNOPSIS
        Human-readable summary. ASCII only.
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

        $groupHeading = "$(Get-PreflightSeverityLabel $severity) (not a blocker)"
        if ($severity -eq $script:SeverityBlocking) { $groupHeading = 'BLOCKING (required for T010)' }
        $null = $lines.Add("[$groupHeading]")

        foreach ($row in $rows) {
            $version = $row.version
            if ([string]::IsNullOrEmpty($version)) { $version = '-' }
            $null = $lines.Add(("  {0,-7} {1,-8} {2,-12} {3}" -f $row.status, (Get-PreflightSeverityLabel $row.severity), $row.id, $version).TrimEnd())
            if ($row.status -ne $script:StatusOk) {
                if (-not [string]::IsNullOrEmpty($row.path)) {
                    $null = $lines.Add("           path: $($row.path)")
                }
                $null = $lines.Add("           note: $($row.details)")
                if (-not [string]::IsNullOrEmpty($row.fixHint)) {
                    $null = $lines.Add("           fix : $($row.fixHint)")
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

function Get-PreflightDefaultOutputDirectory {
    <#
    .SYNOPSIS
        Default JSON destination: <repo>/tmp/preflight (gitignored).
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$RepoRoot)

    return (Join-Path $RepoRoot 'tmp\preflight')
}

function Resolve-PreflightOutputDirectory {
    <#
    .SYNOPSIS
        Constrain JSON output to the repository's tmp/preflight tree.

    .DESCRIPTION
        Returns a result object with ok/path/error. An empty request resolves to the default
        (repo/tmp/preflight). Any other request, relative or absolute, is resolved and then
        required to be the allowed root itself or a subdirectory of it; anything else is
        rejected so the script cannot be pointed at an arbitrary location on disk.

        This is a lexical containment check via Path.GetFullPath: it normalizes '..' but does
        not resolve reparse points (symlinks/junctions). Acceptable for a local dev script.
    #>
    [CmdletBinding()]
    param(
        [AllowEmptyString()][string]$Requested = '',
        [Parameter(Mandatory = $true)][string]$RepoRoot
    )

    $allowedRoot = Get-PreflightDefaultOutputDirectory -RepoRoot $RepoRoot

    if ([string]::IsNullOrWhiteSpace($Requested)) {
        return [pscustomobject]@{ ok = $true; path = $allowedRoot; error = ''; allowedRoot = $allowedRoot }
    }

    $candidate = $Requested
    if (-not [System.IO.Path]::IsPathRooted($candidate)) {
        $candidate = Join-Path $RepoRoot $candidate
    }

    $allowedFull = ''
    $targetFull = ''
    try {
        $allowedFull = [System.IO.Path]::GetFullPath($allowedRoot).TrimEnd('\')
        $targetFull = [System.IO.Path]::GetFullPath($candidate).TrimEnd('\')
    }
    catch {
        return [pscustomobject]@{
            ok          = $false
            path        = ''
            error       = "The requested output directory '$Requested' is not a valid path: $($_.Exception.Message)"
            allowedRoot = $allowedRoot
        }
    }

    if ($targetFull -eq $allowedFull) {
        return [pscustomobject]@{ ok = $true; path = $allowedRoot; error = ''; allowedRoot = $allowedRoot }
    }

    $prefix = $allowedFull + '\'
    if ($targetFull.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        return [pscustomobject]@{ ok = $true; path = $targetFull; error = ''; allowedRoot = $allowedRoot }
    }

    return [pscustomobject]@{
        ok          = $false
        path        = ''
        error       = "Refusing to write outside '$allowedRoot'. Requested: '$Requested'."
        allowedRoot = $allowedRoot
    }
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

Export-ModuleMember -Function @(
    'New-PreflightCheck',
    'New-PreflightReport',
    'Get-PreflightExitCode',
    'Get-VswhereCandidatePaths',
    'Get-RealProbes',
    'Test-ToolCommandCheck',
    'Test-NodeCheck',
    'Test-PythonCheck',
    'Test-RustHostCheck',
    'Test-MsvcBuildToolsCheck',
    'Test-WebView2Check',
    'Test-VbscriptCheck',
    'Test-WingetCheck',
    'Invoke-Preflight',
    'Format-PreflightSummary',
    'Get-PreflightDefaultOutputDirectory',
    'Resolve-PreflightOutputDirectory',
    'Write-PreflightJson'
)
