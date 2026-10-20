param([Parameter(Mandatory = $true)][string]$ArchivePath)
$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot)).TrimEnd('\')

function Assert-ProjectPath([string]$Candidate) {
    $absolute = [IO.Path]::GetFullPath($Candidate)
    if (-not $absolute.StartsWith($projectRoot + '\', [StringComparison]::OrdinalIgnoreCase)) { throw ('La ruta sale del proyecto: ' + $Candidate) }
    $ancestor = $absolute
    while ($ancestor) {
        if (Test-Path -LiteralPath $ancestor) {
            if (((Get-Item -LiteralPath $ancestor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw ('No se admiten enlaces: ' + $ancestor) }
        }
        $parent = Split-Path -Parent $ancestor
        if ($parent -eq $ancestor) { break }
        $ancestor = $parent
    }
}

function Assert-BundleTree([string]$Directory) {
    $pending = [Collections.Generic.Queue[string]]::new()
    $pending.Enqueue($Directory)
    while ($pending.Count -gt 0) {
        foreach ($item in Get-ChildItem -LiteralPath $pending.Dequeue() -Force) {
            Assert-ProjectPath $item.FullName
            if ($item.PSIsContainer) { $pending.Enqueue($item.FullName) }
        }
    }
}

$archive = if ([IO.Path]::IsPathRooted($ArchivePath)) { [IO.Path]::GetFullPath($ArchivePath) } else { [IO.Path]::GetFullPath((Join-Path $projectRoot $ArchivePath)) }
Assert-ProjectPath $archive
if (-not (Test-Path -LiteralPath $archive -PathType Leaf)) { throw 'No se encuentra el ZIP de la entrega.' }
$stagingRoot = Join-Path $projectRoot ('tmp\local-bundles\' + [Guid]::NewGuid().ToString('N'))
$stagedBundle = Join-Path $stagingRoot 'ValinorSanctum2'
$currentBundle = Join-Path $projectRoot 'dist\ValinorSanctum2'
$previousBundle = Join-Path $stagingRoot 'previous\ValinorSanctum2'
foreach ($candidate in @($stagingRoot, $stagedBundle, $currentBundle, $previousBundle)) { Assert-ProjectPath $candidate }

Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [IO.Compression.ZipFile]::OpenRead($archive)
try {
    foreach ($entry in $zip.Entries) {
        $name = $entry.FullName.Replace('\', '/')
        $parts = $name.TrimEnd('/').Split('/')
        if (-not $name.StartsWith('ValinorSanctum2/') -or $name.Contains(':') -or
            @($parts | Where-Object { $_ -eq '..' -or $_ -match '[\x00-\x1f]' -or $_ -match '^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(\.|$)' }).Count -gt 0 -or
            (($entry.ExternalAttributes -shr 16) -band 0xF000) -eq 0xA000) { throw ('Entrada ZIP no admitida: ' + $name) }
        $destination = [IO.Path]::GetFullPath((Join-Path $stagingRoot $name))
        if (-not $destination.StartsWith($stagingRoot + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Una entrada ZIP sale del staging.' }
        if ($name -match '\.(db|sqlite|sqlite3)(-journal|-wal|-shm)?$' -or $name -match '/data/(development|test)/' -or $name -match '(^|/)reference-inventory\.json$') { throw 'No se publican bases, perfiles runtime ni snapshots privados.' }
    }
}
finally { $zip.Dispose() }
New-Item -ItemType Directory -Path $stagingRoot -Force | Out-Null
Expand-Archive -LiteralPath $archive -DestinationPath $stagingRoot
Assert-BundleTree $stagedBundle
foreach ($required in @('valinor_sanctum_2.exe', 'flutter_windows.dll', 'sqlite3.dll', 'msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll', 'data\app.so', 'data\icudtl.dat', 'data\flutter_assets')) {
    if (-not (Test-Path -LiteralPath (Join-Path $stagedBundle $required))) { throw ('Falta en la entrega: ' + $required) }
}
$versionLine = Get-Content -LiteralPath (Join-Path $projectRoot 'pubspec.yaml') | Where-Object { $_ -match '^version:\s*' } | Select-Object -First 1
$projectVersion = [version](($versionLine -replace '^version:\s*', '').Split('+')[0].Trim())
$bundleVersionText = (Get-Item -LiteralPath (Join-Path $stagedBundle 'valinor_sanctum_2.exe')).VersionInfo.FileVersion
if ([version]($bundleVersionText.Split('+')[0]) -lt $projectVersion) { throw 'El ZIP contiene una version anterior al proyecto. No se publica.' }
$currentExecutable = Join-Path $currentBundle 'valinor_sanctum_2.exe'
if (Test-Path -LiteralPath $currentExecutable) {
    Assert-ProjectPath $currentExecutable
    $currentVersion = (Get-Item -LiteralPath $currentExecutable).VersionInfo.FileVersion
    if ([version]($bundleVersionText.Split('+')[0]) -lt [version]($currentVersion.Split('+')[0])) { throw 'El ZIP es anterior a la entrega publicada. No se permite retroceder.' }
}
$projectBoundary = [IO.Path]::GetFullPath($projectRoot).TrimEnd('\') + '\'
$runningProjectApps = @(Get-CimInstance Win32_Process -Filter "Name = 'valinor_sanctum_2.exe'" | Where-Object {
    $_.ExecutablePath -and $_.ExecutablePath.StartsWith($projectBoundary, [StringComparison]::OrdinalIgnoreCase)
})
if ($runningProjectApps.Count -gt 0) { throw 'Cierra las ventanas de Valinor Sanctum 2.0 de este proyecto, incluidas las copias versionadas, antes de actualizar la entrega y su base compartida.' }

$preservedPrevious = $false
if (Test-Path -LiteralPath $currentBundle) {
    Assert-BundleTree $currentBundle
    New-Item -ItemType Directory -Path (Split-Path -Parent $previousBundle) -Force | Out-Null
    # Both resolved absolute paths were checked inside this repository above.
    Move-Item -LiteralPath $currentBundle -Destination $previousBundle
    $preservedPrevious = $true
}
try {
    Move-Item -LiteralPath $stagedBundle -Destination $currentBundle
}
catch {
    if ($preservedPrevious -and -not (Test-Path -LiteralPath $currentBundle)) {
        Assert-ProjectPath $previousBundle
        Assert-ProjectPath $currentBundle
        Move-Item -LiteralPath $previousBundle -Destination $currentBundle
    }
    throw
}
[pscustomobject]@{
    executable = $currentExecutable
    version = $bundleVersionText
    previousBundle = $(if ($preservedPrevious) { $previousBundle } else { $null })
    archiveSha256 = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash
} | ConvertTo-Json
