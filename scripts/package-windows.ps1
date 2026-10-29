param(
    [string]$Version = '',
    [string]$ReleasePath = 'build\windows\x64\runner\Release',
    [ValidateSet('Installed','Development')][string]$Edition = 'Installed',
    [switch]$ArchiveOnly
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
            # Dart CLI hooks can leave an absolute-path development manifest.
            # Flutter Release uses data/flutter_assets/NativeAssetsManifest.json.
            if ($relative -eq 'native_assets.json') { continue }
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
if ($ReleasePath -eq 'build\windows\x64\runner\Release') {
    $generatedConfig = Join-Path $projectRoot 'windows\flutter\ephemeral\generated_config.cmake'
    $defineMatch = [regex]::Match((Get-Content -LiteralPath $generatedConfig -Raw), '"DART_DEFINES=([^"]*)"')
    if (-not $defineMatch.Success) { throw 'No se pudo verificar la configuración de la compilación.' }
    $definedConstants = @($defineMatch.Groups[1].Value.Split(',') | Where-Object { $_ } | ForEach-Object {
        [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($_))
    })
    if ($Edition -eq 'Installed' -and 'SANCTUM_ENV=installed' -notin $definedConstants) { throw 'La compilación no es installed. Compila con --dart-define=SANCTUM_ENV=installed o elige Development.' }
    if ($Edition -eq 'Development' -and @($definedConstants | Where-Object { $_ -match '^SANCTUM_(ENV|PROFILE|DATA_ROOT|WORKSPACE_ROOT)=' }).Count -gt 0) { throw 'La edición Development requiere una compilación sin overrides de Sanctum para usar el selector local.' }
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
Valinor Sanctum 2.0 - Edición para Windows x64

Extrae la carpeta completa y abre valinor_sanctum_2.exe.
Conserva las DLL y la carpeta data junto al ejecutable.
La app abre en Ventas. El menú contiene Catálogo, Compras, Ventas, Deudores,
Tesorería, Eventos y Reportes. Si la base es nueva, Valinor se configura
automáticamente con COP, 0 decimales y hora de Bogotá, sin formularios de alta.
En Compras ingresa nombre, costo total de las unidades, cantidad, PVP, proveedor,
categoría Comestible o Artículo y SKU opcional. Puedes crear el producto o reponer uno existente.
Al elegir un producto se completan SKU, categoría, PVP y proveedor y se muestra
el PVP anterior. Ingresa lo pagado por todas las unidades: se sugiere un PVP
con total/cantidad/0,65. Puedes escribir un precio menor; la sugerencia no limita.
El PVP elegido aplica a todas las existencias y sus cambios quedan en historial.
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
En Ventas crea varias cuentas, agrega productos y elige la forma de pago junto al total.
El selector muestra existencias y ofrece productos físicos activos con unidades;
los agotados se ocultan. Pasadía y eventos activos se muestran como Ilimitado.
Elige Efectivo, Transferencia o Deudas. Transferencia usa la cuenta de Nequi;
ese nombre aparece en el selector, resumen e historial de Ventas.
Registrar venta guarda entrega, stock, costo y cobro en una sola operación.
En Cuenta puedes escribir un nombre libre, buscar una persona registrada o
abrir el selector de Deudores. Elegirla llena el nombre y vincula la cuenta.
Para fiar, registra primero la persona en Deudores y selecciónala en Cuenta.
Editar el nombre manualmente retira esa vinculación; vuelve a elegir la persona.
La parte a Deudas de una cuenta pertenece a esa persona.
Dividir cuenta reparte el total entre los medios y bloquea el selector con Pago dividido.
Editar división permite revisar los importes; Volver a pago único limpia el reparto
y exige seleccionar un medio. Si cambia el consumo, revisa y guarda de nuevo la división.
Puedes combinar pagos y deuda: solo lo pagado entra a Caja o Nequi.
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
El resultado se presenta como comprobante compacto con saldos, ventas y egresos.
Incluye transferencias del rango agrupadas por origen y destino, número de
movimientos y total trasladado; no se suman otra vez a ventas ni egresos.
Los egresos suman salidas registradas de Caja y Nequi; no incluyen transferencias
internas, Caja mayor ni ajustes de deuda. Los totales se muestran por separado.
Repite con el final y pulsa Generar reporte para consultar los saldos iniciales
y finales de Caja y Nequi. Los momentos corresponden al horario de Bogotá.
Los saldos sin respaldo histórico se muestran Sin información.
También muestra ingresos por ventas a Caja, Nequi/Transferencia, ventas a Deudas
y Total vendido, sin sumar abonos ni transferencias entre cuentas.
Las ventas antiguas se calculan como cantidad por PVP archivado en la copia y
se identifican como estimadas. Los valores parciales excluyen registros sin
producto o precio válido y muestran cuántos siguen Sin información.
Si la base fue convertida, Reportes usa sus saldos históricos antes de la apertura,
sin sumar de nuevo inventario ni dinero. Las fechas antiguas se interpretan en Bogotá.
El paquete no contiene bases de datos ni datos de ejemplo.
La edición instalada usa Documents\sanctum2.sqlite3 dentro de la carpeta del
usuario de Windows (por ejemplo C:\Users\ValinorPC\Documents\sanctum2.sqlite3).
Su nombre visible es Valinor Sanctum - Producción. El historial de Tesorería
se lee de Documents\legacy-treasury.json, que debe corresponder a esa base.
Si no existe, crea una base vacía y configura Valinor, COP y 0 decimales.
Si existe, la valida y continúa sobre ella; no la reemplaza ni la reinicia.
Una base incompatible o dañada produce un error y debe conservarse para revisión.
No se copian automáticamente los datos del proyecto de desarrollo.
Los respaldos previos a migraciones se guardan en Documents\ValinorSanctum2-backups.
El instalador crea accesos en Inicio y escritorio para el usuario actual.
La desinstalación conserva la base de Documentos y sus respaldos.
'@
if ($Edition -eq 'Development') {
    $installedInstructions = $instructions.IndexOf('La edición instalada usa Documents')
    if ($installedInstructions -lt 0) { throw 'No se encontró la sección de almacenamiento para preparar las instrucciones.' }
    $instructions = $instructions.Substring(0, $installedInstructions) + @'
Edición de desarrollo portable: no instala accesos ni usa la base de Documentos.
Conserva la carpeta completa dentro de C:\proyectos\valinor_sanctum_2.
Abre Iniciar Valinor Sanctum.cmd desde la raíz del proyecto.
El selector data\development\active-workspace.json elige el perfil de desarrollo.
El perfil activo valinor usa data\development\valinor\sanctum2.sqlite3.
La base existente permanece en su ubicación; no va incluida en el ZIP.
No abras el ejecutable directamente desde build: ese directorio usa un perfil
aislado junto a la compilación. Usa siempre el acceso de la raíz o dist.
'@
}
if ($ArchiveOnly -and $Edition -eq 'Development') {
    $instructions = $instructions.Replace('Abre Iniciar Valinor Sanctum.cmd desde la raíz del proyecto.',
        'Entrega independiente: extrae la carpeta completa bajo dist y abre su ejecutable o el acceso específico de esta versión.')
}
$instructions | Set-Content -LiteralPath (Join-Path $bundleDirectory 'LEEME.txt') -Encoding utf8
[ordered]@{
    version = $Version
    environment = if ($Edition -eq 'Installed') { 'installed' } else { 'development' }
    label = if ($Edition -eq 'Installed') { 'Producción' } else { 'Desarrollo' }
    databaseLocation = if ($Edition -eq 'Installed') { 'Documents/sanctum2.sqlite3' } else { 'data/development/<perfil>/sanctum2.sqlite3' }
    historyLocation = if ($Edition -eq 'Installed') { 'Documents/legacy-treasury.json' } else { 'data/development/<perfil>/legacy-treasury.json' }
} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $bundleDirectory 'EDICION.json') -Encoding utf8
$editionSuffix = if ($Edition -eq 'Development') { '-development' } else { '-production' }
$zipPath = Join-Path $distributionDirectory ('valinor-sanctum-2-' + $Version + $editionSuffix + '-windows-x64.zip')
Assert-ProjectPath $zipPath
if (Test-Path -LiteralPath $zipPath) { throw 'El ZIP ya existe; usa otra versión o conserva la entrega previa.' }
Compress-Archive -LiteralPath $bundleDirectory -DestinationPath $zipPath -CompressionLevel Optimal
if (-not $ArchiveOnly) {
    & (Join-Path $PSScriptRoot 'publish-local-bundle.ps1') -ArchivePath $zipPath -Edition $Edition | Out-Null
}
Assert-ProjectPath $stagingDirectory
Remove-Item -LiteralPath $stagingDirectory -Recurse -Force
[pscustomobject]@{
    archive = $zipPath
    edition = $Edition
    files = $copiedFiles + 2
    bytes = (Get-Item -LiteralPath $zipPath).Length
    sha256 = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash
    includes_synthetic_profiles = $false
    excludes_flutter_debug_artifacts = $true
    current_executable = if ($ArchiveOnly) { $null } else { (Join-Path $distributionDirectory ($(if ($Edition -eq 'Installed') { 'ValinorSanctum2-Produccion' } else { 'ValinorSanctum2' }) + '\valinor_sanctum_2.exe')) }
} | ConvertTo-Json
