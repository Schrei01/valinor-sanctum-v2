param([string]$Version = '1.0.0', [string]$ExistingDatabase = '', [string]$ExistingHistory = '')
$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot)).TrimEnd('\')
$setup = Join-Path $projectRoot ('dist\Valinor-Sanctum-' + $Version + '-Produccion-Instalar.exe')
$sandbox = Join-Path $projectRoot ('tmp\installer-verification\' + [Guid]::NewGuid().ToString('N'))
$target = Join-Path $sandbox 'Application'
$homeDirectory = Join-Path $sandbox 'SyntheticUser'
$databasePath = Join-Path $homeDirectory 'Documents\sanctum2.sqlite3'
New-Item -ItemType Directory -Path $sandbox,$homeDirectory -Force | Out-Null
$expectedRoot = Join-Path $sandbox 'Expected'
Expand-Archive -LiteralPath (Join-Path $projectRoot ('dist\valinor-sanctum-2-' + $Version + '-production-windows-x64.zip')) -DestinationPath $expectedRoot
$bundle = Join-Path $expectedRoot 'ValinorSanctum2'
function Run-Setup {
    $process = Start-Process -FilePath $setup -ArgumentList @('--quiet','--test-root',('"'+$target+'"')) -PassThru -Wait -WindowStyle Hidden
    return $process.ExitCode
}
function Assert-Files {
    $count = 0
    foreach ($source in Get-ChildItem -LiteralPath $bundle -Recurse -File) {
        $relative = $source.FullName.Substring($bundle.Length + 1)
        $destination = Join-Path $target $relative
        if ((Get-FileHash -LiteralPath $source.FullName).Hash -ne (Get-FileHash -LiteralPath $destination).Hash) { throw ('Archivo distinto: '+$relative) }
        $count++
    }
    return $count
}
if ((Run-Setup) -ne 0) { throw 'Falló la instalación sintética' }
$fileCount = Assert-Files
$application = $null
try {
    $application = Start-Process -FilePath (Join-Path $target 'valinor_sanctum_2.exe') -WorkingDirectory $target -Environment @{USERPROFILE=$homeDirectory} -PassThru -WindowStyle Normal
    $limit = [DateTime]::UtcNow.AddSeconds(45)
    while (-not (Test-Path -LiteralPath $databasePath) -and [DateTime]::UtcNow -lt $limit) {
        if ($application.HasExited) { throw 'La app de prueba se cerró antes de crear la base' }
        Start-Sleep -Milliseconds 300
    }
    Start-Sleep -Seconds 3
    $application.Refresh()
    if (-not (Test-Path -LiteralPath $databasePath) -or $application.HasExited -or -not $application.Responding) { throw 'La app instalada no inició correctamente' }
    if ((Run-Setup) -eq 0) { throw 'El instalador no bloqueó la actualización con la app abierta' }
} finally {
    if ($application -and -not $application.HasExited) {
        $application.Refresh()
        if (-not $application.CloseMainWindow() -or -not $application.WaitForExit(30000)) { throw 'La ventana sintética no cerró de forma ordenada' }
    }
}
$initialDatabaseHash = (Get-FileHash -LiteralPath $databasePath).Hash
if ((Run-Setup) -ne 0) { throw 'Falló la reinstalación sintética' }
$null = Assert-Files
if ((Get-FileHash -LiteralPath $databasePath).Hash -ne $initialDatabaseHash) { throw 'La actualización modificó la base de Documentos' }
$application = Start-Process -FilePath (Join-Path $target 'valinor_sanctum_2.exe') -WorkingDirectory $target -Environment @{USERPROFILE=$homeDirectory} -PassThru -WindowStyle Normal
try {
    Start-Sleep -Seconds 5
    $application.Refresh()
    if ($application.HasExited -or -not $application.Responding) { throw 'No reabrió la app instalada' }
} finally {
    if (-not $application.HasExited) {
        if (-not $application.CloseMainWindow() -or -not $application.WaitForExit(30000)) { throw 'No cerró la reapertura de prueba' }
    }
}
$beforeUninstall = (Get-FileHash -LiteralPath $databasePath).Hash
$existingDataVerified = $false
if ($ExistingDatabase -or $ExistingHistory) {
    foreach ($source in @($ExistingDatabase,$ExistingHistory)) {
        $absolute = [IO.Path]::GetFullPath($source)
        if (-not $absolute.StartsWith($projectRoot + '\', [StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $absolute -PathType Leaf)) { throw 'Las fuentes del ensayo deben existir dentro del proyecto.' }
    }
    Copy-Item -LiteralPath $ExistingDatabase -Destination $databasePath -Force
    $historyPath = Join-Path $homeDirectory 'Documents\legacy-treasury.json'
    Copy-Item -LiteralPath $ExistingHistory -Destination $historyPath
    $seedDatabaseHash = (Get-FileHash -LiteralPath $databasePath).Hash
    $seedHistoryHash = (Get-FileHash -LiteralPath $historyPath).Hash
    $application = Start-Process -FilePath (Join-Path $target 'valinor_sanctum_2.exe') -WorkingDirectory $target -Environment @{USERPROFILE=$homeDirectory} -PassThru -WindowStyle Normal
    try {
        [void]$application.WaitForInputIdle(15000)
        Start-Sleep -Seconds 5
        $application.Refresh()
        if ($application.HasExited -or -not $application.Responding -or $application.MainWindowTitle -ne 'Valinor Sanctum - Producción') { throw 'No abrió la edición Producción con la base existente.' }
    } finally {
        if (-not $application.HasExited) {
            if (-not $application.CloseMainWindow() -or -not $application.WaitForExit(30000)) { throw 'No cerró el ensayo con base existente.' }
        }
    }
    if ((Get-FileHash -LiteralPath $databasePath).Hash -ne $seedDatabaseHash -or (Get-FileHash -LiteralPath $historyPath).Hash -ne $seedHistoryHash) { throw 'El arranque modificó los archivos existentes del ensayo.' }
    if ((Run-Setup) -ne 0) { throw 'Falló la reinstalación con datos existentes.' }
    if ((Get-FileHash -LiteralPath $databasePath).Hash -ne $seedDatabaseHash -or (Get-FileHash -LiteralPath $historyPath).Hash -ne $seedHistoryHash) { throw 'La reinstalación modificó la base o el historial.' }
    $beforeUninstall = $seedDatabaseHash
    $existingDataVerified = $true
}
$uninstaller = Start-Process -FilePath (Join-Path $target 'Desinstalar.exe') -ArgumentList @('--quiet','--test-root',('"'+$target+'"')) -PassThru -Wait -WindowStyle Hidden
if ($uninstaller.ExitCode -ne 0) { throw 'Falló el desinstalador' }
$limit = [DateTime]::UtcNow.AddSeconds(25)
while ((Test-Path -LiteralPath $target) -and [DateTime]::UtcNow -lt $limit) { Start-Sleep -Milliseconds 250 }
if (Test-Path -LiteralPath $target) { throw 'El desinstalador no retiró el programa' }
if ((Get-FileHash -LiteralPath $databasePath).Hash -ne $beforeUninstall) { throw 'La desinstalación modificó la base' }
if ($existingDataVerified -and (Get-FileHash -LiteralPath $historyPath).Hash -ne $seedHistoryHash) { throw 'La desinstalación modificó el historial.' }
[pscustomobject]@{installedFilesVerified=$fileCount; nativeStartup=$true; updateWhileRunningRejected=$true; reinstallPreservesDatabase=$true; nativeReopen=$true; existingDatabaseAndHistoryVerified=$existingDataVerified; productionWindowTitleVerified=$existingDataVerified; uninstallRemovesProgram=$true; uninstallPreservesDatabase=$true; testRegistryAndShortcutsSkipped=$true; syntheticDatabase=$databasePath} | ConvertTo-Json
