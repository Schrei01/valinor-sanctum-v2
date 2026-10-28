param(
    [string]$Version = '',
    [string]$DistributionPath = 'dist',
    [switch]$DryRun
)
$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot)).TrimEnd('\')
function Assert-CleanupPath([string]$Candidate) {
    $absolute = [IO.Path]::GetFullPath($Candidate)
    if (-not $absolute.StartsWith($projectRoot + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'La limpieza debe permanecer dentro del proyecto nuevo.' }
    $ancestor = $absolute
    while ($ancestor) {
        if ((Test-Path -LiteralPath $ancestor) -and ((Get-Item -LiteralPath $ancestor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'La limpieza no admite enlaces ni junctions.' }
        $ancestor = Split-Path -Parent $ancestor
    }
}
function Assert-NoRuntimeData([string]$Relative) {
    if ($Relative -match '(?i)\.(db|sqlite|sqlite3)(-|$)' -or
        $Relative -match '(?i)(^|[\\/])data[\\/](development|test)([\\/]|$)' -or
        $Relative -match '(?i)(^|[\\/])(active-workspace|legacy-treasury|reference-inventory)\.json$') {
        throw ('No se elimina una entrega que contiene datos privados: ' + $Relative)
    }
}
$distribution = if ([IO.Path]::IsPathRooted($DistributionPath)) { [IO.Path]::GetFullPath($DistributionPath) } else { [IO.Path]::GetFullPath((Join-Path $projectRoot $DistributionPath)) }
$distribution = $distribution.TrimEnd('\')
Assert-CleanupPath $distribution
if ($distribution -ne (Join-Path $projectRoot 'dist') -and -not $distribution.StartsWith((Join-Path $projectRoot 'tmp') + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Solo se limpia dist o una carpeta sintética dentro de tmp.' }
$currentExecutable = Join-Path $distribution 'ValinorSanctum2\valinor_sanctum_2.exe'
Assert-CleanupPath $currentExecutable
if (-not (Test-Path -LiteralPath $currentExecutable -PathType Leaf)) { throw 'Falta la entrega estable; no se elimina ninguna versión.' }
$installedVersion = ((Get-Item -LiteralPath $currentExecutable).VersionInfo.ProductVersion).Split('+')[0]
if (-not $Version) { $Version = $installedVersion }
if ($Version -notmatch '^\d+\.\d+\.\d+$' -or $Version -ne $installedVersion) { throw 'La versión a conservar debe coincidir con la entrega estable.' }
$currentVersion = [version]$Version
$candidates = @(
    foreach ($item in Get-ChildItem -LiteralPath $distribution -Force) {
        $candidateVersion = $null
        if ($item.PSIsContainer -and $item.Name -match '^\d+\.\d+\.\d+$') { $candidateVersion = [version]$item.Name }
        elseif (-not $item.PSIsContainer -and $item.Name -match '^valinor-sanctum-2-(\d+\.\d+\.\d+)-windows-x64\.zip$') { $candidateVersion = [version]$Matches[1] }
        elseif (-not $item.PSIsContainer -and $item.Name -match '^Valinor-Sanctum-(\d+\.\d+\.\d+)-Instalar\.exe$') { $candidateVersion = [version]$Matches[1] }
        if ($null -ne $candidateVersion -and $candidateVersion -lt $currentVersion) { $item }
    }
)
$runningApps = @(Get-CimInstance Win32_Process -Filter "Name = 'valinor_sanctum_2.exe'" | Where-Object { $_.ExecutablePath })
$bytes = [long]0
Add-Type -AssemblyName System.IO.Compression.FileSystem
# Preflight the complete deletion set before removing even one artifact.
foreach ($candidate in $candidates) {
    Assert-CleanupPath $candidate.FullName
    if ((Split-Path -Parent $candidate.FullName) -ne $distribution) { throw 'Un destino no es hijo directo de la carpeta de entregas.' }
    if ($candidate.PSIsContainer) {
        if (-not (Test-Path -LiteralPath (Join-Path $candidate.FullName 'ValinorSanctum2\valinor_sanctum_2.exe') -PathType Leaf)) { throw ('Carpeta de versión no reconocida: ' + $candidate.Name) }
        foreach ($app in $runningApps) {
            if ($app.ExecutablePath.StartsWith($candidate.FullName + '\', [StringComparison]::OrdinalIgnoreCase)) { throw ('Cierra la versión anterior antes de limpiarla: ' + $candidate.Name) }
        }
        $pending = [Collections.Generic.Queue[string]]::new()
        $pending.Enqueue($candidate.FullName)
        while ($pending.Count -gt 0) {
            foreach ($child in Get-ChildItem -LiteralPath $pending.Dequeue() -Force) {
                Assert-CleanupPath $child.FullName
                Assert-NoRuntimeData $child.FullName.Substring($candidate.FullName.Length + 1)
                if ($child.PSIsContainer) { $pending.Enqueue($child.FullName) } else { $bytes += $child.Length }
            }
        }
    } elseif ($candidate.Extension -eq '.zip') {
        $zip = [IO.Compression.ZipFile]::OpenRead($candidate.FullName)
        try { foreach ($entry in $zip.Entries) { Assert-NoRuntimeData $entry.FullName } } finally { $zip.Dispose() }
        $bytes += $candidate.Length
    } else {
        $bytes += $candidate.Length
    }
}
foreach ($candidate in $candidates) {
    # Resolved absolute targets were checked as direct children, without links or data.
    if (-not $DryRun) { Remove-Item -LiteralPath $candidate.FullName -Recurse -Force }
}
[pscustomobject]@{
    currentVersion = $Version
    dryRun = [bool]$DryRun
    artifacts = $candidates.Count
    bytes = $bytes
    names = @($candidates | ForEach-Object { $_.Name })
} | ConvertTo-Json -Depth 3
