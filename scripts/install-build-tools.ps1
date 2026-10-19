param([switch]$Install)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$installer = Join-Path $projectRoot '.tooling\installers\vs_BuildTools.exe'
if (-not $Install) {
    Write-Output 'Acción pendiente de autorización: instalar Visual Studio Build Tools con C++, CMake y Windows SDK.'
    Write-Output 'Aunque el directorio principal sea local, el instalador modifica componentes compartidos y el registro de Windows.'
    Write-Output 'Tras recibir autorización expresa: ./scripts/install-build-tools.ps1 -Install'
    exit 0
}
if (-not (Test-Path -LiteralPath $installer)) {
    throw 'Descarga el instalador oficial en .tooling/installers/vs_BuildTools.exe. Consulta docs/10-incremento-01.md.'
}
$signature = Get-AuthenticodeSignature -LiteralPath $installer
if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'O=Microsoft Corporation') {
    throw 'El instalador no tiene una firma Microsoft válida.'
}
$installDirectory = Join-Path $projectRoot '.tooling\visual-studio'
$arguments = @('--quiet', '--wait', '--norestart', '--add', 'Microsoft.VisualStudio.Workload.VCTools', '--includeRecommended', '--installPath', ('"' + $installDirectory + '"'))
$process = Start-Process -FilePath $installer -ArgumentList $arguments -WindowStyle Hidden -PassThru -Wait
if ($process.ExitCode -eq 3010) {
    Write-Output 'Instalación terminada; Windows indica que necesita reiniciarse. No se reinició automáticamente.'
    exit 0
}
if ($process.ExitCode -ne 0) { throw ('El instalador devolvió ' + $process.ExitCode) }
Write-Output 'Herramientas instaladas. Ejecutar ./scripts/flutter.ps1 doctor -v y volver a compilar.'
