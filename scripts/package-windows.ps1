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
            if ($item.Name -in @('reference-inventory.json', 'active-workspace.json', 'legacy-treasury.json')) { throw 'Un snapshot o selector privado está fuera de las rutas runtime excluidas.' }
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
La app abre en Ventas. El menú contiene Catálogo, Compras, Ventas, Deudores,
Tesorería, Eventos y Reportes. Si el espacio es nuevo, indica solo su nombre:
COP con 0 decimales y hora de Bogotá quedan fijos, sin selector de precisión.
En Compras ingresa nombre, costo unitario, PVP, proveedor,
categoría Comestible o Artículo, SKU opcional y cantidad. Puedes crear el producto o reponer uno existente.
Al elegir un producto se completan SKU, categoría, PVP, proveedor y último costo
conocido. Puedes modificarlos antes de ingresar la compra; completa la cantidad.
Elige Efectivo o Nequi para pagar: el ingreso y la salida de dinero se guardan juntos.
Registra el saldo inicial real antes del primer movimiento de cada cuenta si corresponde.
Consulta el Historial de ingresos desde la misma sección Compras.
Catálogo muestra productos: filtra por Categoría y Proveedor, y busca por nombre o SKU.
Sus columnas son Producto, PVP, Unidades y Proveedor.
Todos los productos limpia los filtros y la búsqueda. Catálogo consulta los productos
y permite desactivar eventos conservando sus costos e historial.
Catálogo muestra eventos activos y productos con unidades disponibles; los agotados se conservan
para reponerlos desde Compras. Un inventario inicial confirmado está disponible en Ventas.
Si hay una copia de inventario cargada localmente, Catálogo permite consultarla
en Inventario de la copia y volver al Catálogo de esta app con el selector de origen.
La copia muestra su corte, cantidades, PVP y lotes; no está disponible para vender.
En Ventas crea varias cuentas, agrega productos y elige la forma de pago por línea.
Elige Efectivo, Transferencia o Deudas. Transferencia usa la cuenta de Nequi;
ese nombre aparece en las líneas, resumen e historial de Ventas.
Registrar venta guarda entrega, stock, costo y cobro en una sola operación.
Para fiar, registra primero la persona en Deudores y selecciónala en la cuenta de Ventas.
Todas las líneas Deudas de una cuenta pertenecen a esa persona.
Puedes combinar líneas pagadas y fiadas: solo lo pagado entra a Caja o Nequi.
Lo fiado aumenta la deuda de esa persona y Deudas en Tesorería.
En Deudores selecciona la persona, valor del abono y Efectivo o Transferencia.
Puedes pagar parcial o totalmente. El abono reduce su deuda y aumenta Caja o Nequi juntos.
Al registrar deuda anterior indica si ya estaba incluida en la cartera importada
o si es deuda adicional, para no duplicar el total.
Las cuentas de mostrador se guardan automáticamente mientras las preparas.
Ventas es la única pantalla de ventas; no hay acceso al formulario anterior.
En Eventos crea pasadías, torneos o ligas con categoría Evento automática.
Indica mínimo de personas, costo fijo opcional desde Caja o Nequi y varios
productos del catálogo con sus cantidades. Si hay costos o productos, mínimo 1.
El PU se calcula con costo FIFO y mínimo de personas; introduce el PVP que cobrarás.
Crear evento descuenta dinero y productos una sola vez. Luego vende sus inscripciones
desde Ventas, sin límite de stock y sin repetir costos. Reintenta las solicitudes
pendientes desde Eventos si se interrumpe el guardado.
Desactivar retira el evento de Catálogo y Ventas, sin devolver dinero ni productos.
Tesorería reemplaza Pagos: consulta Caja, Nequi, Caja mayor y Deudas de clientes.
Total disponible suma Caja y Nequi; la reserva y las deudas se muestran aparte.
En Tesorería usa Registrar gasto para pagar Arriendo, Aseo, Servicios u Otro
desde Caja o Nequi. Indica valor, motivo y una observación opcional.
Transferir dinero permite elegir cuentas de origen y destino distintas,
incluyendo Caja mayor. El dinero sale del origen y entra al destino junto.
Las dos opciones requieren saldo suficiente en la cuenta de origen.
Filtra los últimos movimientos por cuenta y pulsa Actualizar para consultar de nuevo.
Los pagos anteriores a proveedores permanecen en un panel secundario de Tesorería.
Los saldos de una copia verificada se cargan como apertura única, no como ventas.
Deudas identifica la cartera anterior sin detalle cuando la fuente no trae clientes.
Historial de la copia es consulta separada y no vuelve a mover dinero.
Las confirmaciones pendientes se recuperan al reabrir para reintentar sin duplicar.
Los cobros pendientes de confirmar se recuperan al reabrir sin duplicarse.
Registra pagos y abonos a proveedores con saldo disponible, incluso por varios medios.
Las solicitudes de pago guardadas se recuperan al reabrir sin duplicarse.
En Reportes elige la fecha inicial y, al aceptar, la hora en formato AM/PM.
Repite con el final y pulsa Generar reporte para consultar los saldos iniciales
y finales de Caja y Nequi. Los momentos corresponden al horario de Bogotá.
Los saldos sin respaldo histórico se muestran Sin información.
Si la base fue convertida, Reportes usa sus saldos históricos antes de la apertura,
sin sumar de nuevo inventario ni dinero. Las fechas antiguas se interpretan en Bogotá.
Caja/arqueo y ajustes de inventario siguen pendientes.
El paquete no contiene datos privados ni está habilitado para producción.
El almacenamiento de desarrollo permanece limitado al repositorio autorizado
C:\proyectos\valinor_sanctum_2; ejecuta el bundle dentro de ese proyecto.
'@
$instructions | Set-Content -LiteralPath (Join-Path $bundleDirectory 'LEEME.txt') -Encoding utf8
$zipPath = Join-Path $distributionDirectory ('valinor-sanctum-2-' + $Version + '-windows-x64.zip')
Assert-ProjectPath $zipPath
if (Test-Path -LiteralPath $zipPath) { throw 'El ZIP ya existe; usa otra versión o conserva la entrega previa.' }
Compress-Archive -LiteralPath $bundleDirectory -DestinationPath $zipPath -CompressionLevel Optimal
& (Join-Path $PSScriptRoot 'publish-local-bundle.ps1') -ArchivePath $zipPath | Out-Null
Assert-ProjectPath $stagingDirectory
Remove-Item -LiteralPath $stagingDirectory -Recurse -Force
[pscustomobject]@{
    archive = $zipPath
    files = $copiedFiles + 1
    bytes = (Get-Item -LiteralPath $zipPath).Length
    sha256 = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash
    includes_synthetic_profiles = $false
    excludes_flutter_debug_artifacts = $true
    current_executable = (Join-Path $distributionDirectory 'ValinorSanctum2\valinor_sanctum_2.exe')
} | ConvertTo-Json
