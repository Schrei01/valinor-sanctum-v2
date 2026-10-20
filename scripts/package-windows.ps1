param(
    [string]$Version = '',
    [string]$ReleasePath = 'build\windows\x64\runner\Release'
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
function Assert-ProjectPath([string]$Candidate) {
    $absolute = [IO.Path]::GetFullPath($Candidate)
    $boundary = [IO.Path]::GetFullPath($projectRoot).TrimEnd('\')
    if (-not ($absolute.Equals($boundary, [StringComparison]::OrdinalIgnoreCase) -or $absolute.StartsWith($boundary + '\', [StringComparison]::OrdinalIgnoreCase))) {
        throw ('La ruta sale del proyecto nuevo: ' + $Candidate)
    }
    $current = $absolute
    while ($current) {
        if (Test-Path -LiteralPath $current) {
            $item = Get-Item -LiteralPath $current -Force
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw ('No se admiten enlaces o junctions: ' + $current) }
        }
        $parent = Split-Path -Parent $current
        if ($parent -eq $current) { break }
        $current = $parent
    }
}
function Get-BundleFiles([string]$BundleRoot) {
    $queue = [Collections.Generic.Queue[string]]::new()
    $queue.Enqueue($BundleRoot)
    while ($queue.Count -gt 0) {
        foreach ($item in Get-ChildItem -LiteralPath $queue.Dequeue() -Force) {
            $relative = $item.FullName.Substring($BundleRoot.Length + 1)
            if ($relative -match '^data[\\/](development|test)([\\/]|$)') { continue }
            # A prior `build bundle --debug` can leave these in shared assets.
            # The Release engine uses data/app.so instead of JIT snapshots.
            if ($relative -match '^data[\\/]flutter_assets[\\/](kernel_blob\.bin|isolate_snapshot_data|vm_snapshot_data|\.last_build_id)$') { continue }
            Assert-ProjectPath $item.FullName
            if ($item.PSIsContainer) { $queue.Enqueue($item.FullName) } else { $item }
        }
    }
}
$releaseDirectory = if ([IO.Path]::IsPathRooted($ReleasePath)) {
    [IO.Path]::GetFullPath($ReleasePath)
} else {
    [IO.Path]::GetFullPath((Join-Path $projectRoot $ReleasePath))
}
$releaseDirectory = $releaseDirectory.TrimEnd('\', '/')
Assert-ProjectPath $releaseDirectory
foreach ($required in @('valinor_sanctum_2.exe', 'flutter_windows.dll', 'sqlite3.dll', 'data\app.so', 'data\icudtl.dat', 'data\flutter_assets')) {
    if (-not (Test-Path -LiteralPath (Join-Path $releaseDirectory $required))) { throw ('Falta un archivo del bundle nativo: ' + $required) }
}
if (-not $Version) {
    $versionLine = Get-Content -LiteralPath (Join-Path $projectRoot 'pubspec.yaml') | Where-Object { $_ -match '^version:\s*' } | Select-Object -First 1
    $Version = ($versionLine -replace '^version:\s*', '').Split('+')[0].Trim()
}
if ($Version -notmatch '^\d+\.\d+\.\d+(?:[-A-Za-z0-9.]+)?$') { throw 'Versión de paquete inválida.' }
$vswhere = Join-Path ([Environment]::GetFolderPath('ProgramFilesX86')) 'Microsoft Visual Studio\Installer\vswhere.exe'
if (-not (Test-Path -LiteralPath $vswhere)) { throw 'No se encuentra vswhere para localizar los runtimes C++.' }
$visualStudio = (& $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath | Select-Object -First 1)
if (-not $visualStudio) { throw 'No hay toolchain C++ instalado.' }
$redistRoot = Join-Path $visualStudio 'VC\Redist\MSVC'
$runtimeDirectory = Get-ChildItem -LiteralPath $redistRoot -Directory | Sort-Object Name -Descending | ForEach-Object {
    Get-ChildItem -LiteralPath (Join-Path $_.FullName 'x64') -Directory -Filter 'Microsoft.VC*.CRT' -ErrorAction SilentlyContinue
} | Select-Object -First 1
if (-not $runtimeDirectory) { throw 'No se encuentran los runtimes x64 redistribuibles de Microsoft.' }
foreach ($runtime in @('msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll')) {
    $runtimeSource = Join-Path $runtimeDirectory.FullName $runtime
    if (-not (Test-Path -LiteralPath $runtimeSource)) { throw ('Falta el runtime ' + $runtime) }
    Assert-ProjectPath (Join-Path $releaseDirectory $runtime)
    Copy-Item -LiteralPath $runtimeSource -Destination (Join-Path $releaseDirectory $runtime)
}
$distributionDirectory = Join-Path $projectRoot 'dist'
$stagingDirectory = Join-Path $projectRoot ('tmp\packages\' + [Guid]::NewGuid().ToString('N'))
$bundleDirectory = Join-Path $stagingDirectory 'ValinorSanctum2'
Assert-ProjectPath $distributionDirectory
Assert-ProjectPath $bundleDirectory
New-Item -ItemType Directory -Force -Path $distributionDirectory,$bundleDirectory | Out-Null
$copiedFiles = 0
foreach ($file in Get-BundleFiles $releaseDirectory) {
    $relative = $file.FullName.Substring($releaseDirectory.Length + 1)
    # Preserve Flutter data assets; exclude only mutable runtime profiles.
    if ($relative -match '^data[\\/](development|test)[\\/]') { continue }
    $destination = Join-Path $bundleDirectory $relative
    Assert-ProjectPath $destination
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination) | Out-Null
    Copy-Item -LiteralPath $file.FullName -Destination $destination
    $copiedFiles++
}
$instructions = @'
Valinor Sanctum 2.0 - Versión de desarrollo

Extrae la carpeta completa y abre valinor_sanctum_2.exe.
Conserva las DLL y la carpeta data junto al ejecutable.
Configura tu perfil. En Compras ingresa nombre, costo unitario, PVP, proveedor,
categoría, SKU opcional y cantidad. Puedes crear el producto o reponer uno existente.
Elige Efectivo o Nequi para pagar: el ingreso y la salida de dinero se guardan juntos.
Registra el saldo inicial real antes del primer movimiento de cada cuenta si corresponde.
Consulta el Historial de ingresos desde la misma sección Compras.
En Ventas crea varias cuentas, agrega productos y elige la forma de pago por línea.
Registrar venta guarda entrega, stock, costo y cobro de contado en una sola operación.
Las cuentas de mostrador se guardan automáticamente mientras las preparas.
Ventas es la única pantalla de ventas; no hay acceso al formulario anterior.
Las confirmaciones pendientes se recuperan al reabrir para reintentar sin duplicar.
Configura cuentas y medios locales y registra cobros o abonos de las ventas.
Los cobros pendientes de confirmar se recuperan al reabrir sin duplicarse.
Registra pagos y abonos a proveedores con saldo disponible, incluso por varios medios.
Las solicitudes de pago guardadas se recuperan al reabrir sin duplicarse.
Caja/arqueo y ajustes de inventario siguen pendientes.
No contiene datos del POS original ni está habilitado para producción.
El almacenamiento de desarrollo permanece limitado al repositorio autorizado
C:\proyectos\valinor_sanctum_2; ejecuta el bundle dentro de ese proyecto.
'@
$instructions | Set-Content -LiteralPath (Join-Path $bundleDirectory 'LEEME.txt') -Encoding utf8
$zipPath = Join-Path $distributionDirectory ('valinor-sanctum-2-' + $Version + '-windows-x64.zip')
Assert-ProjectPath $zipPath
if (Test-Path -LiteralPath $zipPath) { throw 'El ZIP ya existe; usa otra versión o conserva la entrega previa.' }
Compress-Archive -LiteralPath $bundleDirectory -DestinationPath $zipPath -CompressionLevel Optimal
& (Join-Path $PSScriptRoot 'publish-local-bundle.ps1') -ArchivePath $zipPath | Out-Null
[pscustomobject]@{
    archive = $zipPath
    files = $copiedFiles + 1
    bytes = (Get-Item -LiteralPath $zipPath).Length
    sha256 = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash
    includes_synthetic_profiles = $false
    excludes_flutter_debug_artifacts = $true
    current_executable = (Join-Path $distributionDirectory 'ValinorSanctum2\valinor_sanctum_2.exe')
} | ConvertTo-Json
