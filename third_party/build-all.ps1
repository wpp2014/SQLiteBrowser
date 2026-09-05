<#
.SYNOPSIS
Builds or tests all repository-pinned binary dependencies.

.DESCRIPTION
This script is the orchestration entry point for zlib, zstd, Brotli, OpenSSL,
and SQLCipher. It delegates all dependency-specific work to each dependency's
build.cmd so those scripts remain the source of truth.

SQLCipher's upstream source-generation step does not support paths containing
spaces. When SQLCipher is selected, the repository's absolute path must not
contain any whitespace.

Build compiles, stages (publishes), and verifies product artifacts. Test is a
separate invocation that requires an existing matching build. No invocation
can build and test at the same time.

.EXAMPLE
powershell -NoProfile -ExecutionPolicy Bypass -File third_party\build-all.ps1 -Action Check

.EXAMPLE
powershell -NoProfile -ExecutionPolicy Bypass -File third_party\build-all.ps1 -Action Build -Configuration Debug,Release

.EXAMPLE
powershell -NoProfile -ExecutionPolicy Bypass -File third_party\build-all.ps1 -Action Test -Configuration Debug,Release

.EXAMPLE
powershell -NoProfile -ExecutionPolicy Bypass -File third_party\build-all.ps1 -Action Build -Configuration Release -Dependency Brotli,OpenSSL,SQLCipher
#>

[CmdletBinding()]
param(
    [ValidateSet('Check', 'Build', 'Test')]
    [string]$Action = 'Build',

    [string[]]$Configuration = @('Debug', 'Release'),

    [string[]]$Dependency = @(
        'zlib', 'zstd', 'brotli', 'openssl', 'sqlcipher'
    ),

    [ValidateSet('Safe', 'Full')]
    [string]$OpenSSLTestMode = 'Safe'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = [IO.Path]::GetFullPath((Join-Path $scriptRoot '..'))
$dependencyOrder = @('zlib', 'zstd', 'brotli', 'openssl', 'sqlcipher')
$results = [System.Collections.Generic.List[object]]::new()

function Resolve-Selection {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Values,

        [Parameter(Mandatory = $true)]
        [string[]]$AllowedValues,

        [Parameter(Mandatory = $true)]
        [string]$ParameterName
    )

    $resolved = [System.Collections.Generic.List[string]]::new()
    foreach ($value in $Values) {
        foreach ($part in $value.Split(',')) {
            $candidate = $part.Trim()
            if ([string]::IsNullOrWhiteSpace($candidate)) {
                continue
            }

            $canonical = $AllowedValues |
                Where-Object { $_ -eq $candidate } |
                Select-Object -First 1
            if (-not $canonical) {
                throw "Invalid $ParameterName '$candidate'. Allowed values: $($AllowedValues -join ', ')."
            }
            if ($canonical -notin $resolved) {
                $resolved.Add($canonical)
            }
        }
    }

    if ($resolved.Count -eq 0) {
        throw "$ParameterName must select at least one value."
    }
    return @($resolved)
}

# powershell.exe -File passes comma-separated array arguments as one string.
# Accept both that form and native PowerShell arrays so the documented commands
# work in Windows PowerShell 5.1 as well as newer PowerShell versions.
$selectedConfigurations = @(Resolve-Selection -Values $Configuration `
    -AllowedValues @('Debug', 'Release') -ParameterName 'Configuration')
$selectedDependencies = @(Resolve-Selection -Values $Dependency `
    -AllowedValues $dependencyOrder -ParameterName 'Dependency')

if ($selectedDependencies -contains 'sqlcipher' -and $projectRoot -match '\s') {
    throw @"
SQLCipher cannot be built from a repository path containing spaces.
Current repository path: $projectRoot
Move or clone the repository to a path without spaces before running this script.
"@
}

function Invoke-DependencyScript {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DependencyName,

        [Parameter(Mandatory = $true)]
        [string]$ConfigurationName
    )

    $buildScript = Join-Path $scriptRoot "$DependencyName\build.cmd"
    if (-not (Test-Path -LiteralPath $buildScript -PathType Leaf)) {
        throw "Dependency build script is missing: $buildScript"
    }

    $configurationArgument = $ConfigurationName.ToLowerInvariant()
    $actionArgument = $Action.ToLowerInvariant()
    $arguments = @($actionArgument, $configurationArgument)
    if ($Action -eq 'Test' -and $DependencyName -eq 'openssl') {
        $arguments += $OpenSSLTestMode.ToLowerInvariant()
    }

    $displayAction = if ($Action -eq 'Build') {
        'build, stage, and verify'
    } elseif ($Action -eq 'Test') {
        'run tests'
    } else {
        'check prerequisites'
    }

    Write-Host ''
    Write-Host ('=' * 80)
    Write-Host "[$DependencyName] $displayAction ($ConfigurationName x64)"
    Write-Host ('=' * 80)

    $startedAt = Get-Date
    & $buildScript @arguments
    $exitCode = $LASTEXITCODE
    $elapsed = (Get-Date) - $startedAt

    if ($null -eq $exitCode) {
        throw "Dependency script did not return an exit code: $buildScript"
    }
    if ($exitCode -ne 0) {
        throw "$DependencyName $ConfigurationName $Action failed with exit code $exitCode."
    }

    $results.Add([pscustomobject]@{
        Dependency = $DependencyName
        Configuration = $ConfigurationName
        Action = $Action
        Elapsed = $elapsed
    })
}

try {
    Push-Location -LiteralPath $projectRoot

    foreach ($currentConfiguration in $selectedConfigurations) {
        foreach ($currentDependency in $dependencyOrder) {
            if ($currentDependency -notin $selectedDependencies) {
                continue
            }

            Invoke-DependencyScript -DependencyName $currentDependency `
                -ConfigurationName $currentConfiguration
        }
    }
} finally {
    Pop-Location
}

Write-Host ''
Write-Host 'Dependency orchestration completed successfully.'
foreach ($result in $results) {
    Write-Host ('  {0,-7} {1,-7} {2,-5} {3:hh\:mm\:ss}' -f `
        $result.Dependency, $result.Configuration, $result.Action,
        $result.Elapsed)
}

if ($Action -eq 'Build') {
    Write-Host ''
    Write-Host 'Product artifacts were staged and verified. Tests were not run.'
    Write-Host 'Run this script again with -Action Test to execute tests separately.'
} elseif ($Action -eq 'Test') {
    Write-Host ''
    Write-Host 'Tests completed against the existing matching product stages.'
    if ($selectedDependencies -contains 'openssl') {
        Write-Host "OpenSSL test mode: $OpenSSLTestMode"
    }
}
