<#
.SYNOPSIS
    Read-only development environment preflight for the EngMentor desktop client (M00 / T010).

.DESCRIPTION
    CLI entry point. Loads the check module (scripts/lib/PreflightChecks.psm1), runs the
    inventory and prints a human-readable summary plus an optional JSON report.

    Read-only and side-effect free:
      * never installs anything (no winget / choco / npm install / corepack enable / rustup update)
      * never modifies environment variables, the registry, Git configuration or user profile
      * never reads, prints or persists secrets

    The only write is the JSON report, which is constrained to <repo>/tmp/preflight (an
    ignored temp tree). Use -NoJson to disable even that.

    Exit codes:
      0  report mode always, and -RequireReady when every Blocking item is OK
      1  -RequireReady only: at least one Blocking item is not OK
      2  invalid usage (for example an -OutputDirectory outside <repo>/tmp/preflight)
      3  the preflight itself failed to run (never used for a missing toolchain)

.PARAMETER RequireReady
    Exit 1 when any Blocking item is not OK. Without this switch missing tools are reported
    and the process still exits 0, because "not installed yet" is a finding, not a failure.

.PARAMETER NoJson
    Do not write the JSON report. The script then performs no writes at all.

.PARAMETER OutputDirectory
    JSON destination. Must be <repo>/tmp/preflight or a subdirectory of it; any other path is
    rejected with exit code 2. Defaults to <repo>/tmp/preflight.

.PARAMETER Quiet
    Suppress the human-readable summary (the JSON report is still written unless -NoJson).

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File scripts/preflight.ps1

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File scripts/preflight.ps1 -RequireReady

.NOTES
    Version : 2.0.0
    Checks  : scripts/lib/PreflightChecks.psm1
    Tests   : scripts/tests/preflight.Tests.ps1 (Pester)
    Encoding: ASCII only, for Windows PowerShell 5.1 under any code page.
#>
[CmdletBinding()]
param(
    [switch]$RequireReady,
    [switch]$NoJson,
    [string]$OutputDirectory,
    [switch]$Quiet
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$exitCode = 0

try {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $modulePath = Join-Path $PSScriptRoot 'lib\PreflightChecks.psm1'
    if (-not (Test-Path -LiteralPath $modulePath -PathType Leaf)) {
        Write-Error "Check module not found at '$modulePath'."
        exit 3
    }
    Import-Module -Name $modulePath -Force -ErrorAction Stop

    # Resolve and validate the JSON destination before doing any work, so a bad path fails
    # fast instead of after the inventory.
    $resolvedDirectory = $null
    if (-not $NoJson) {
        $resolvedDirectory = Resolve-PreflightOutputDirectory -Requested $OutputDirectory -RepoRoot $repoRoot
        if (-not $resolvedDirectory.ok) {
            Write-Host $resolvedDirectory.error
            Write-Host "Allowed root: $($resolvedDirectory.allowedRoot)"
            exit 2
        }
    }

    $report = Invoke-Preflight -RepoRoot $repoRoot -RequireReadyMode ([bool]$RequireReady)

    if (-not $Quiet) {
        Write-Host (Format-PreflightSummary -Report $report)
        Write-Host ''
    }

    if (-not $NoJson) {
        try {
            $file = Write-PreflightJson -Report $report -Directory $resolvedDirectory.path
            if (-not $Quiet) {
                Write-Host "JSON report: $file"
                Write-Host '(inside the gitignored tmp/preflight tree; nothing else was written)'
                Write-Host ''
            }
        }
        catch {
            # A report write failure must not be confused with a toolchain finding.
            Write-Warning "Could not write the JSON report to '$($resolvedDirectory.path)': $($_.Exception.Message)"
        }
    }

    $exitCode = Get-PreflightExitCode -Report $report -RequireReadyMode ([bool]$RequireReady)
}
catch {
    Write-Error "Preflight failed to run: $($_.Exception.Message)"
    exit 3
}

exit $exitCode
