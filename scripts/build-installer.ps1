param([string]$Version = '')
$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot)).TrimEnd('\')
if (-not $Version) {
    $Version = ((Get-Content (Join-Path $projectRoot 'pubspec.yaml') | Where-Object { $_ -match '^version:' }) -replace '^version:\s*','').Split('+')[0].Trim()
}
if ($Version -notmatch '^\d+\.\d+\.\d+$') { throw 'Versión inválida' }
$payload = Join-Path $projectRoot ('dist\valinor-sanctum-2-' + $Version + '-production-windows-x64.zip')
if (-not (Test-Path -LiteralPath $payload)) { throw 'Primero genera y verifica el bundle con package-windows.ps1.' }
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [IO.Compression.ZipFile]::OpenRead($payload)
try {
    $editionEntry = $archive.GetEntry('ValinorSanctum2/EDICION.json')
    if ($null -eq $editionEntry) { throw 'El paquete no identifica su edición.' }
    $editionReader = [IO.StreamReader]::new($editionEntry.Open())
    try { $edition = $editionReader.ReadToEnd() | ConvertFrom-Json } finally { $editionReader.Dispose() }
    if ($edition.environment -ne 'installed' -or $edition.version -ne $Version) { throw 'El instalador requiere la edición de producción y su misma versión.' }
    foreach ($entry in $archive.Entries) {
        $name = $entry.FullName.Replace('\','/')
        if (-not $name.StartsWith('ValinorSanctum2/') -or $name.Contains('..') -or $name.Contains(':') -or
            $name -match '(?i)\.(db|sqlite|sqlite3)(-|$)' -or
            $name -match '(?i)/data/(development|test)/' -or
            $name -match '(?i)(active-workspace|reference-inventory|legacy-treasury)\.json$') { throw ('Entrada no admitida: ' + $name) }
    }
} finally { $archive.Dispose() }
$compiler = Join-Path ([Environment]::GetFolderPath('Windows')) 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path -LiteralPath $compiler)) { throw 'Falta el compilador .NET Framework de Windows.' }
$temporary = Join-Path $projectRoot ('tmp\installer-build\' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temporary -Force | Out-Null
$source = (Get-Content -LiteralPath (Join-Path $projectRoot 'installer\ValinorInstaller.cs') -Raw).Replace('__VERSION__',$Version).Replace('__TEST_BOUNDARY__',(Join-Path $projectRoot 'tmp'))
$sourcePath = Join-Path $temporary 'ValinorInstaller.cs'
$source | Set-Content -LiteralPath $sourcePath -Encoding UTF8
$uninstaller = Join-Path $temporary 'Desinstalar.exe'
$output = Join-Path $projectRoot ('dist\Valinor-Sanctum-' + $Version + '-Produccion-Instalar.exe')
if (Test-Path -LiteralPath $output) { throw 'El instalador ya existe. No se reemplaza una entrega sin cambiar versión.' }
$references = @('/r:System.Windows.Forms.dll','/r:System.Drawing.dll','/r:System.IO.Compression.dll','/r:System.IO.Compression.FileSystem.dll','/r:Microsoft.CSharp.dll')
$icon = Join-Path $projectRoot 'windows\runner\resources\app_icon.ico'
& $compiler /nologo /target:winexe /platform:x64 /optimize+ @references ('/win32icon:' + $icon) /define:UNINSTALLER ('/out:' + $uninstaller) $sourcePath
if ($LASTEXITCODE -ne 0) { throw 'Falló la compilación del desinstalador.' }
& $compiler /nologo /target:winexe /platform:x64 /optimize+ @references ('/win32icon:' + $icon) ('/resource:' + $payload + ',Payload.zip') ('/resource:' + $uninstaller + ',Uninstaller.exe') ('/out:' + $output) $sourcePath
if ($LASTEXITCODE -ne 0) { throw 'Falló la compilación del instalador.' }
[pscustomobject]@{installer=$output; bytes=(Get-Item -LiteralPath $output).Length; sha256=(Get-FileHash -LiteralPath $output -Algorithm SHA256).Hash; version=$Version; includesDatabase=$false} | ConvertTo-Json
