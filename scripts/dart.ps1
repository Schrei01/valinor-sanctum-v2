# Ejecuta únicamente el SDK y las cachés portátiles de este repositorio.
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$sdkCommand = Join-Path $projectRoot '.tooling\flutter\bin\dart.bat'
if (-not (Test-Path -LiteralPath $sdkCommand)) {
    throw 'Falta el SDK portable. Consulta README.md para preparar .tooling/flutter.'
}
$localEnvironment = @{
    'PUB_CACHE' = (Join-Path $projectRoot '.tooling\pub-cache')
    'APPDATA' = (Join-Path $projectRoot '.tooling\profile\AppData\Roaming')
    'LOCALAPPDATA' = (Join-Path $projectRoot '.tooling\profile\AppData\Local')
    'USERPROFILE' = (Join-Path $projectRoot '.tooling\profile')
    'TEMP' = (Join-Path $projectRoot '.tooling\temp')
    'TMP' = (Join-Path $projectRoot '.tooling\temp')
    'CI' = 'true'
    'FLUTTER_SUPPRESS_ANALYTICS' = 'true'
    'DART_SUPPRESS_ANALYTICS' = 'true'
}
$previousEnvironment = @{}
foreach ($name in $localEnvironment.Keys) {
    $previousEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
    [Environment]::SetEnvironmentVariable($name, $localEnvironment[$name], 'Process')
}
foreach ($relativePath in @('.tooling\pub-cache', '.tooling\profile\AppData\Roaming', '.tooling\profile\AppData\Local', '.tooling\temp', 'tmp')) {
    New-Item -ItemType Directory -Force -Path (Join-Path $projectRoot $relativePath) | Out-Null
}
Push-Location -LiteralPath $projectRoot
$commandExitCode = 1
try {
    & $sdkCommand --suppress-analytics @args
    $commandExitCode = $LASTEXITCODE
}
finally {
    Pop-Location
    foreach ($name in $previousEnvironment.Keys) {
        [Environment]::SetEnvironmentVariable($name, $previousEnvironment[$name], 'Process')
    }
}
exit $commandExitCode

