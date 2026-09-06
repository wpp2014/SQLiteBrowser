[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet("build", "check", "clean")]
    [string]$Action = "build",

    [Parameter(Position = 1)]
    [ValidateSet("all", "debug", "release")]
    [string]$Configuration = "all"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = [IO.Path]::GetFullPath((Join-Path $scriptRoot ".."))
$outputRoot = Join-Path $projectRoot "output"
$requiredSdk = "10.0.26100.0"
$dependencyNames = @("brotli", "zlib", "zstd", "openssl", "sqlcipher")
$selectedConfigurations = if ($Configuration -eq "all") {
    @("debug", "release")
} else {
    @($Configuration)
}

$dependencyIdentity = @{
    brotli = @(
        "Brotli tag: v1.2.0",
        "Brotli commit: 028fb5a23661f123017c060daa546b55cf4bde29"
    )
    zlib = @(
        "zlib tag: v1.3.2",
        "zlib commit: da607da739fa6047df13e66a2af6b8bec7c2a498"
    )
    zstd = @(
        "zstd tag: v1.5.7",
        "zstd commit: f8745da6ff1ad1e7bab384bd1f9d742439278e99"
    )
    openssl = @(
        "OpenSSL tag: openssl-3.5.7",
        "OpenSSL commit: 8cf17aaeb4599f8af87fefd810b5b5fee90fe69e",
        "Brotli tag: v1.2.0",
        "Brotli commit: 028fb5a23661f123017c060daa546b55cf4bde29"
    )
    sqlcipher = @(
        "SQLCipher tag: v4.18.0",
        "SQLCipher commit: 63697beb0fafcb61faa7a3e6fd267036548ab11b",
        "SQLite baseline: 3.53.4",
        "OpenSSL tag: openssl-3.5.7",
        "OpenSSL commit: 8cf17aaeb4599f8af87fefd810b5b5fee90fe69e"
    )
}

$stageProductFiles = @{
    brotli = @(
        "bin/brotlicommon.dll", "bin/brotlicommon.pdb", "lib/brotlicommon.lib",
        "bin/brotlidec.dll", "bin/brotlidec.pdb", "lib/brotlidec.lib",
        "bin/brotlienc.dll", "bin/brotlienc.pdb", "lib/brotlienc.lib"
    )
    zlib = @("bin/zlib1.dll", "bin/zlib1.pdb", "lib/zlib1.lib")
    zstd = @("bin/libzstd.dll", "bin/libzstd.pdb", "lib/libzstd.lib")
    openssl = @(
        "bin/libcrypto-3-x64.dll", "bin/libcrypto-3-x64.pdb", "lib/libcrypto.lib",
        "bin/libssl-3-x64.dll", "bin/libssl-3-x64.pdb", "lib/libssl.lib"
    )
    sqlcipher = @("bin/sqlcipher.dll", "bin/sqlcipher.pdb", "lib/sqlcipher.lib")
}

function Get-NormalizedRelativePath {
    param([Parameter(Mandatory = $true)][string]$Path)

    $normalized = $Path.Replace("\", "/").TrimStart("/")
    if ([string]::IsNullOrWhiteSpace($normalized) -or
        [IO.Path]::IsPathRooted($normalized) -or
        $normalized -match "(^|/)\.\.(/|$)" -or
        $normalized -notmatch "^(include|bin|metadata)/") {
        throw "Unsafe public relative path: $Path"
    }
    return $normalized
}

function Resolve-PublicPath {
    param(
        [Parameter(Mandatory = $true)][string]$ConfigurationRoot,
        [Parameter(Mandatory = $true)][string]$RelativePath
    )

    $safeRelative = Get-NormalizedRelativePath $RelativePath
    $candidate = [IO.Path]::GetFullPath((Join-Path $ConfigurationRoot $safeRelative.Replace("/", "\")))
    $rootPrefix = [IO.Path]::GetFullPath($ConfigurationRoot).TrimEnd("\") + "\"
    if (-not $candidate.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Public path escapes the configuration root: $RelativePath"
    }
    return $candidate
}

function Get-Sha256 {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Cannot hash missing file: $Path"
    }
    $stream = [IO.File]::OpenRead($Path)
    $sha256 = [Security.Cryptography.SHA256]::Create()
    try {
        $hashBytes = $sha256.ComputeHash($stream)
        return ([BitConverter]::ToString($hashBytes)).Replace("-", "").ToLowerInvariant()
    } finally {
        $sha256.Dispose()
        $stream.Dispose()
    }
}

function Assert-File {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Required file is missing: $Path"
    }
}

function Assert-ManifestLine {
    param(
        [Parameter(Mandatory = $true)][string[]]$Lines,
        [Parameter(Mandatory = $true)][string]$Expected,
        [Parameter(Mandatory = $true)][string]$ManifestPath
    )

    if ($Lines -notcontains $Expected) {
        throw "Manifest contract mismatch in ${ManifestPath}: missing '$Expected'"
    }
}

function Remove-ExactWorkTree {
    param(
        [Parameter(Mandatory = $true)][string]$Target,
        [Parameter(Mandatory = $true)][string]$AllowedParent
    )

    $targetFull = [IO.Path]::GetFullPath($Target).TrimEnd("\")
    $parentFull = [IO.Path]::GetFullPath($AllowedParent).TrimEnd("\")
    if ($targetFull -eq $parentFull -or
        -not $targetFull.StartsWith($parentFull + "\", [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to remove an unsafe work directory: $targetFull"
    }
    if (Test-Path -LiteralPath $targetFull) {
        Remove-Item -LiteralPath $targetFull -Recurse -Force
    }
}

function Read-OwnershipManifest {
    param(
        [Parameter(Mandatory = $true)][string]$ManifestPath,
        [Parameter(Mandatory = $true)][string]$ConfigurationRoot
    )

    Assert-File $ManifestPath
    $entries = [System.Collections.Generic.List[object]]::new()
    foreach ($line in Get-Content -LiteralPath $ManifestPath) {
        if ($line -match "^([0-9a-fA-F]{64})`t(.+)$") {
            $relative = Get-NormalizedRelativePath $Matches[2]
            $fullPath = Resolve-PublicPath $ConfigurationRoot $relative
            $entries.Add([pscustomobject]@{
                Hash = $Matches[1].ToLowerInvariant()
                RelativePath = $relative
                FullPath = $fullPath
            })
        }
    }
    if ($entries.Count -eq 0) {
        throw "Ownership manifest contains no file entries: $ManifestPath"
    }
    return $entries
}

function Assert-OwnedFilesUnchanged {
    param([Parameter(Mandatory = $true)][object[]]$Entries)

    foreach ($entry in $Entries) {
        Assert-File $entry.FullPath
        $actual = Get-Sha256 $entry.FullPath
        if ($actual -ne $entry.Hash) {
            throw "Public dependency file was modified outside the aggregator: $($entry.FullPath)"
        }
    }
}

function Remove-EmptyPublicDirectories {
    param([Parameter(Mandatory = $true)][string]$ConfigurationRoot)

    foreach ($rootName in @("include", "bin", "metadata")) {
        $root = Join-Path $ConfigurationRoot $rootName
        if (-not (Test-Path -LiteralPath $root -PathType Container)) {
            continue
        }
        Get-ChildItem -LiteralPath $root -Directory -Recurse -Force |
            Sort-Object { $_.FullName.Length } -Descending |
            ForEach-Object {
                if (-not (Get-ChildItem -LiteralPath $_.FullName -Force | Select-Object -First 1)) {
                    Remove-Item -LiteralPath $_.FullName -Force
                }
            }
    }
}

function Validate-DependencyStages {
    param([Parameter(Mandatory = $true)][string]$ConfigName)

    $displayConfig = if ($ConfigName -eq "debug") { "Debug" } else { "Release" }
    $expectedCrt = if ($ConfigName -eq "debug") { "/MDd" } else { "/MD" }
    $configurationRoot = Join-Path $outputRoot "x64-shared-$ConfigName"
    $stages = @{}

    foreach ($dependency in $dependencyNames) {
        $stage = Join-Path $configurationRoot "build\$dependency\stage"
        $buildManifest = Join-Path $stage "build-manifest.txt"
        Assert-File $buildManifest
        $manifestLines = @(Get-Content -LiteralPath $buildManifest)

        foreach ($identityLine in $dependencyIdentity[$dependency]) {
            Assert-ManifestLine $manifestLines $identityLine $buildManifest
        }

        $expectedConfigurationLine = if ($dependency -eq "openssl") {
            "Configuration: $ConfigName"
        } else {
            "Configuration: $displayConfig"
        }
        Assert-ManifestLine $manifestLines $expectedConfigurationLine $buildManifest

        $sdkLine = $manifestLines | Where-Object { $_ -like "Windows SDK: $requiredSdk*" } | Select-Object -First 1
        if (-not $sdkLine) {
            throw "Manifest SDK mismatch in $buildManifest; expected $requiredSdk"
        }
        if ($dependency -ne "openssl") {
            Assert-ManifestLine $manifestLines "Architecture: x64" $buildManifest
            Assert-ManifestLine $manifestLines "CRT: $expectedCrt" $buildManifest
        }

        foreach ($relativePath in $stageProductFiles[$dependency]) {
            Assert-File (Join-Path $stage $relativePath.Replace("/", "\"))
        }

        $testManifest = Join-Path $stage "test-manifest.txt"
        $testStatus = "not present"
        if (Test-Path -LiteralPath $testManifest -PathType Leaf) {
            $buildHash = Get-Sha256 $buildManifest
            $testLines = @(Get-Content -LiteralPath $testManifest)
            Assert-ManifestLine $testLines "Build manifest SHA-256: $buildHash" $testManifest
            $testStatus = "present and bound"
        }

        $stages[$dependency] = [pscustomobject]@{
            Root = $stage
            BuildManifest = $buildManifest
            TestManifest = $testManifest
            TestStatus = $testStatus
        }
    }

    foreach ($brotliDll in @("brotlicommon.dll", "brotlidec.dll", "brotlienc.dll")) {
        $brotliPath = Join-Path $stages.brotli.Root "bin\$brotliDll"
        $opensslPath = Join-Path $stages.openssl.Root "bin\$brotliDll"
        Assert-File $opensslPath
        if ((Get-Sha256 $brotliPath) -ne (Get-Sha256 $opensslPath)) {
            throw "OpenSSL and Brotli stages contain different $brotliDll files for $ConfigName"
        }
    }

    $opensslBuildHash = Get-Sha256 $stages.openssl.BuildManifest
    $sqlcipherLines = @(Get-Content -LiteralPath $stages.sqlcipher.BuildManifest)
    Assert-ManifestLine $sqlcipherLines "OpenSSL manifest SHA-256: $opensslBuildHash" $stages.sqlcipher.BuildManifest

    return [pscustomobject]@{
        ConfigurationRoot = $configurationRoot
        DisplayConfiguration = $displayConfig
        ExpectedCrt = $expectedCrt
        Stages = $stages
    }
}

function New-PublicCopyPlan {
    param([Parameter(Mandatory = $true)][object]$Validation)

    $plan = [System.Collections.Generic.Dictionary[string, string]]::new([StringComparer]::OrdinalIgnoreCase)
    function Add-PlanFile {
        param([string]$Source, [string]$Destination)

        Assert-File $Source
        $relative = Get-NormalizedRelativePath $Destination
        if ($plan.ContainsKey($relative)) {
            throw "Two dependency artifacts map to the same public path: $relative"
        }
        $plan.Add($relative, [IO.Path]::GetFullPath($Source))
    }

    $stages = $Validation.Stages

    foreach ($header in Get-ChildItem -LiteralPath (Join-Path $stages.brotli.Root "include\brotli") -Filter "*.h" -File) {
        Add-PlanFile $header.FullName "include/brotli/$($header.Name)"
    }
    foreach ($requiredHeader in @("decode.h", "encode.h", "port.h", "shared_dictionary.h", "types.h")) {
        if (-not $plan.ContainsKey("include/brotli/$requiredHeader")) {
            throw "Required Brotli public header is missing: $requiredHeader"
        }
    }

    foreach ($header in Get-ChildItem -LiteralPath (Join-Path $stages.openssl.Root "include\openssl") -Filter "*.h" -File) {
        Add-PlanFile $header.FullName "include/openssl/$($header.Name)"
    }
    foreach ($requiredHeader in @("opensslconf.h", "opensslv.h", "ssl.h", "crypto.h")) {
        if (-not $plan.ContainsKey("include/openssl/$requiredHeader")) {
            throw "Required OpenSSL public header is missing: $requiredHeader"
        }
    }

    foreach ($name in @("zlib.h", "zconf.h")) {
        Add-PlanFile (Join-Path $stages.zlib.Root "include\$name") "include/$name"
    }
    foreach ($name in @("zstd.h", "zdict.h", "zstd_errors.h")) {
        Add-PlanFile (Join-Path $stages.zstd.Root "include\$name") "include/$name"
    }
    foreach ($name in @("sqlite3.h", "sqlite3ext.h", "sqlite3session.h")) {
        Add-PlanFile (Join-Path $stages.sqlcipher.Root "include\sqlcipher\$name") "include/sqlcipher/$name"
    }

    foreach ($dependency in $dependencyNames) {
        foreach ($relativePath in $stageProductFiles[$dependency]) {
            $fileName = [IO.Path]::GetFileName($relativePath)
            Add-PlanFile (Join-Path $stages[$dependency].Root $relativePath.Replace("/", "\")) "bin/$fileName"
        }
    }

    foreach ($dependency in $dependencyNames) {
        Add-PlanFile $stages[$dependency].BuildManifest "metadata/manifests/$dependency/build-manifest.txt"
        if (Test-Path -LiteralPath $stages[$dependency].TestManifest -PathType Leaf) {
            Add-PlanFile $stages[$dependency].TestManifest "metadata/manifests/$dependency/test-manifest.txt"
        }
    }

    Add-PlanFile (Join-Path $stages.brotli.Root "share\licenses\brotli\LICENSE") "metadata/licenses/brotli/LICENSE"
    Add-PlanFile (Join-Path $stages.zlib.Root "share\doc\zlib\zlib\LICENSE") "metadata/licenses/zlib/LICENSE"
    Add-PlanFile (Join-Path $projectRoot "third_party\zstd\src\LICENSE") "metadata/licenses/zstd/LICENSE"
    Add-PlanFile (Join-Path $projectRoot "third_party\openssl\src\LICENSE.txt") "metadata/licenses/openssl/LICENSE.txt"
    Add-PlanFile (Join-Path $stages.sqlcipher.Root "share\licenses\sqlcipher\LICENSE.md") "metadata/licenses/sqlcipher/LICENSE.md"
    Add-PlanFile (Join-Path $stages.sqlcipher.Root "share\licenses\sqlcipher\SQLITE_LICENSE.md") "metadata/licenses/sqlcipher/SQLITE_LICENSE.md"

    return $plan
}

function Write-AggregateTree {
    param(
        [Parameter(Mandatory = $true)][object]$Validation,
        [Parameter(Mandatory = $true)][System.Collections.Generic.Dictionary[string, string]]$Plan,
        [Parameter(Mandatory = $true)][string]$TreeRoot
    )

    foreach ($entry in $Plan.GetEnumerator()) {
        $destination = Resolve-PublicPath $TreeRoot $entry.Key
        $parent = Split-Path -Parent $destination
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
        Copy-Item -LiteralPath $entry.Value -Destination $destination -Force
    }

    $aggregateManifest = Join-Path $TreeRoot "metadata\dependency-aggregate-manifest.txt"
    New-Item -ItemType Directory -Path (Split-Path -Parent $aggregateManifest) -Force | Out-Null
    $aggregateLines = [System.Collections.Generic.List[string]]::new()
    $aggregateLines.Add("SQLiteBrowser dependency aggregate manifest")
    $aggregateLines.Add("Format version: 1")
    $aggregateLines.Add("Configuration: $($Validation.DisplayConfiguration)")
    $aggregateLines.Add("Architecture: x64")
    $aggregateLines.Add("Windows SDK: $requiredSdk")
    $aggregateLines.Add("CRT: $($Validation.ExpectedCrt)")
    $aggregateLines.Add("Generated UTC: $([DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ'))")
    foreach ($dependency in $dependencyNames) {
        $stage = $Validation.Stages[$dependency]
        $aggregateLines.Add("$dependency build manifest SHA-256: $(Get-Sha256 $stage.BuildManifest)")
        $aggregateLines.Add("$dependency test manifest: $($stage.TestStatus)")
    }
    $aggregateLines.Add("Public include policy: dependency headers only; Qt headers excluded")
    $aggregateLines.Add("Public bin policy: DLL, import LIB, and linker PDB only; test and CLI tools excluded")
    $aggregateLines.Add("OpenSSL Brotli runtime source: matching Brotli stage after byte-for-byte validation")
    [IO.File]::WriteAllLines($aggregateManifest, $aggregateLines, [Text.UTF8Encoding]::new($false))

    $ownedFiles = Get-ChildItem -LiteralPath $TreeRoot -File -Recurse |
        Where-Object { $_.FullName -ne (Join-Path $TreeRoot "metadata\dependency-ownership-manifest.txt") } |
        Sort-Object FullName
    $ownershipManifest = Join-Path $TreeRoot "metadata\dependency-ownership-manifest.txt"
    $ownershipLines = [System.Collections.Generic.List[string]]::new()
    $ownershipLines.Add("SQLiteBrowser dependency public ownership manifest")
    $ownershipLines.Add("Format version: 1")
    $ownershipLines.Add("Configuration: $($Validation.DisplayConfiguration)")
    $ownershipLines.Add("Hash format: SHA-256<TAB>relative/path")
    $ownershipLines.Add("Files:")
    foreach ($file in $ownedFiles) {
        $relative = $file.FullName.Substring($TreeRoot.TrimEnd("\").Length + 1).Replace("\", "/")
        $ownershipLines.Add("$(Get-Sha256 $file.FullName)`t$relative")
    }
    [IO.File]::WriteAllLines($ownershipManifest, $ownershipLines, [Text.UTF8Encoding]::new($false))
}

function Publish-AggregateTree {
    param(
        [Parameter(Mandatory = $true)][object]$Validation,
        [Parameter(Mandatory = $true)][string]$TreeRoot,
        [Parameter(Mandatory = $true)][string]$WorkRoot
    )

    $configurationRoot = $Validation.ConfigurationRoot
    $publicOwnership = Join-Path $configurationRoot "metadata\dependency-ownership-manifest.txt"
    $newOwnership = Join-Path $TreeRoot "metadata\dependency-ownership-manifest.txt"
    $newEntries = @(Read-OwnershipManifest $newOwnership $TreeRoot)
    $oldEntries = @()
    $oldOwnedPaths = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)

    if (Test-Path -LiteralPath $publicOwnership -PathType Leaf) {
        $oldEntries = @(Read-OwnershipManifest $publicOwnership $configurationRoot)
        Assert-OwnedFilesUnchanged $oldEntries
        foreach ($entry in $oldEntries) {
            [void]$oldOwnedPaths.Add($entry.RelativePath)
        }
    }

    foreach ($entry in $newEntries) {
        $destination = Resolve-PublicPath $configurationRoot $entry.RelativePath
        if ((Test-Path -LiteralPath $destination) -and -not $oldOwnedPaths.Contains($entry.RelativePath)) {
            throw "Refusing to overwrite a public file not owned by the dependency aggregator: $destination"
        }
    }

    $backupRoot = Join-Path $WorkRoot "backup"
    if (Test-Path -LiteralPath $backupRoot) {
        throw "A previous aggregation backup still exists; inspect and recover it before retrying: $backupRoot"
    }
    New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
    $copiedNewPaths = [System.Collections.Generic.List[string]]::new()

    try {
        foreach ($entry in $oldEntries) {
            $backupPath = Resolve-PublicPath $backupRoot $entry.RelativePath
            New-Item -ItemType Directory -Path (Split-Path -Parent $backupPath) -Force | Out-Null
            Move-Item -LiteralPath $entry.FullPath -Destination $backupPath
        }
        if (Test-Path -LiteralPath $publicOwnership -PathType Leaf) {
            $backupOwnership = Resolve-PublicPath $backupRoot "metadata/dependency-ownership-manifest.txt"
            New-Item -ItemType Directory -Path (Split-Path -Parent $backupOwnership) -Force | Out-Null
            Move-Item -LiteralPath $publicOwnership -Destination $backupOwnership
        }

        foreach ($entry in $newEntries) {
            $source = Resolve-PublicPath $TreeRoot $entry.RelativePath
            $destination = Resolve-PublicPath $configurationRoot $entry.RelativePath
            New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
            Copy-Item -LiteralPath $source -Destination $destination -Force
            $copiedNewPaths.Add($destination)
        }
        New-Item -ItemType Directory -Path (Split-Path -Parent $publicOwnership) -Force | Out-Null
        Copy-Item -LiteralPath $newOwnership -Destination $publicOwnership -Force
        $copiedNewPaths.Add($publicOwnership)

        $publishedEntries = @(Read-OwnershipManifest $publicOwnership $configurationRoot)
        Assert-OwnedFilesUnchanged $publishedEntries
        Remove-ExactWorkTree $backupRoot $WorkRoot
        Remove-EmptyPublicDirectories $configurationRoot
    } catch {
        foreach ($path in $copiedNewPaths) {
            if (Test-Path -LiteralPath $path -PathType Leaf) {
                Remove-Item -LiteralPath $path -Force
            }
        }
        foreach ($entry in $oldEntries) {
            $backupPath = Resolve-PublicPath $backupRoot $entry.RelativePath
            if (Test-Path -LiteralPath $backupPath -PathType Leaf) {
                New-Item -ItemType Directory -Path (Split-Path -Parent $entry.FullPath) -Force | Out-Null
                Move-Item -LiteralPath $backupPath -Destination $entry.FullPath
            }
        }
        $backupOwnership = Resolve-PublicPath $backupRoot "metadata/dependency-ownership-manifest.txt"
        if (Test-Path -LiteralPath $backupOwnership -PathType Leaf) {
            New-Item -ItemType Directory -Path (Split-Path -Parent $publicOwnership) -Force | Out-Null
            Move-Item -LiteralPath $backupOwnership -Destination $publicOwnership
        }
        throw
    }
}

function Clean-PublicAggregate {
    param([Parameter(Mandatory = $true)][string]$ConfigName)

    $configurationRoot = Join-Path $outputRoot "x64-shared-$ConfigName"
    $ownershipManifest = Join-Path $configurationRoot "metadata\dependency-ownership-manifest.txt"
    if (-not (Test-Path -LiteralPath $ownershipManifest -PathType Leaf)) {
        Write-Host "[aggregate] No owned public dependency files exist for $ConfigName."
        return
    }

    $entries = @(Read-OwnershipManifest $ownershipManifest $configurationRoot)
    Assert-OwnedFilesUnchanged $entries
    $workRoot = Join-Path $configurationRoot "build\dependency-aggregate\work"
    $backupRoot = Join-Path $workRoot "clean-backup"
    if (Test-Path -LiteralPath $backupRoot) {
        throw "A previous clean backup still exists; inspect it before retrying: $backupRoot"
    }
    New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null

    foreach ($entry in $entries) {
        $backupPath = Resolve-PublicPath $backupRoot $entry.RelativePath
        New-Item -ItemType Directory -Path (Split-Path -Parent $backupPath) -Force | Out-Null
        Move-Item -LiteralPath $entry.FullPath -Destination $backupPath
    }
    $backupOwnership = Resolve-PublicPath $backupRoot "metadata/dependency-ownership-manifest.txt"
    New-Item -ItemType Directory -Path (Split-Path -Parent $backupOwnership) -Force | Out-Null
    Move-Item -LiteralPath $ownershipManifest -Destination $backupOwnership
    Remove-ExactWorkTree $backupRoot $workRoot
    Remove-EmptyPublicDirectories $configurationRoot
    Write-Host "[aggregate] Cleaned owned public dependency files for $ConfigName."
}

Write-Host "[aggregate] Project root:  $projectRoot"
Write-Host "[aggregate] Action:        $Action"
Write-Host "[aggregate] Configuration: $Configuration"

foreach ($configName in $selectedConfigurations) {
    if ($Action -eq "clean") {
        Clean-PublicAggregate $configName
        continue
    }

    Write-Host "[aggregate] Validating $configName dependency stages..."
    $validation = Validate-DependencyStages $configName
    $configurationRoot = $validation.ConfigurationRoot
    $ownershipManifest = Join-Path $configurationRoot "metadata\dependency-ownership-manifest.txt"

    if ($Action -eq "check") {
        if (Test-Path -LiteralPath $ownershipManifest -PathType Leaf) {
            $entries = @(Read-OwnershipManifest $ownershipManifest $configurationRoot)
            Assert-OwnedFilesUnchanged $entries
            Write-Host "[aggregate] $configName stages and $($entries.Count) owned public files are valid."
        } else {
            Write-Host "[aggregate] $configName stages are valid; no public aggregate exists yet."
        }
        continue
    }

    $workRoot = Join-Path $configurationRoot "build\dependency-aggregate\work"
    $nextRoot = Join-Path $workRoot "next"
    New-Item -ItemType Directory -Path $workRoot -Force | Out-Null
    Remove-ExactWorkTree $nextRoot $workRoot
    New-Item -ItemType Directory -Path $nextRoot -Force | Out-Null

    try {
        $plan = New-PublicCopyPlan $validation
        Write-AggregateTree $validation $plan $nextRoot
        Publish-AggregateTree $validation $nextRoot $workRoot
        $publishedEntries = @(Read-OwnershipManifest $ownershipManifest $configurationRoot)
        Write-Host "[aggregate] Published $($publishedEntries.Count) dependency files for $configName."
        Write-Host "[aggregate] Public include: $(Join-Path $configurationRoot 'include')"
        Write-Host "[aggregate] Public bin:     $(Join-Path $configurationRoot 'bin')"
        Write-Host "[aggregate] Metadata:       $(Join-Path $configurationRoot 'metadata')"
    } finally {
        if (Test-Path -LiteralPath $nextRoot) {
            Remove-ExactWorkTree $nextRoot $workRoot
        }
    }
}

Write-Host "[aggregate] Requested action completed successfully."
