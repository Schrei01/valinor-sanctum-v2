$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$fixtureRoot = Join-Path $projectRoot ('tmp\distribution-cleanup-test-' + [Guid]::NewGuid().ToString('N'))
if (-not $fixtureRoot.StartsWith((Join-Path $projectRoot 'tmp') + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Fixture fuera de tmp.' }
New-Item -ItemType Directory -Path $fixtureRoot -Force | Out-Null
$stable = Join-Path $fixtureRoot 'ValinorSanctum2'
$old = Join-Path $fixtureRoot '0.0.1\ValinorSanctum2'
New-Item -ItemType Directory -Path $stable,$old -Force | Out-Null
$executable = Join-Path $projectRoot 'dist\ValinorSanctum2\valinor_sanctum_2.exe'
Copy-Item -LiteralPath $executable -Destination (Join-Path $stable 'valinor_sanctum_2.exe')
Copy-Item -LiteralPath $executable -Destination (Join-Path $old 'valinor_sanctum_2.exe')
$keepVersion = ((Get-Item -LiteralPath $executable).VersionInfo.ProductVersion).Split('+')[0]
$oldZip = Join-Path $fixtureRoot 'valinor-sanctum-2-0.0.1-windows-x64.zip'
Compress-Archive -LiteralPath $old -DestinationPath $oldZip
New-Item -ItemType Directory -Path (Join-Path $fixtureRoot $keepVersion),(Join-Path $fixtureRoot '9.0.0') -Force | Out-Null
Set-Content -LiteralPath (Join-Path $fixtureRoot 'notas.txt') -Value 'No borrar'
$cleanupScript = Join-Path $projectRoot 'scripts\clean-old-distributions.ps1'
$preview = & $cleanupScript -DistributionPath $fixtureRoot -DryRun | ConvertFrom-Json
if ($preview.artifacts -ne 2 -or -not (Test-Path -LiteralPath $oldZip)) { throw 'DryRun modificó datos o eligió mal las versiones.' }
$result = & $cleanupScript -DistributionPath $fixtureRoot | ConvertFrom-Json
if ($result.artifacts -ne 2 -or (Test-Path -LiteralPath $oldZip) -or (Test-Path -LiteralPath $old)) { throw 'No se limpiaron las dos entregas obsoletas.' }
foreach ($preserved in @('ValinorSanctum2',$keepVersion,'9.0.0','notas.txt')) {
    if (-not (Test-Path -LiteralPath (Join-Path $fixtureRoot $preserved))) { throw ('Se eliminó un destino protegido: ' + $preserved) }
}
# Any private data blocks the entire deletion set, including otherwise valid ZIPs.
New-Item -ItemType Directory -Path $old -Force | Out-Null
Copy-Item -LiteralPath $executable -Destination (Join-Path $old 'valinor_sanctum_2.exe')
Set-Content -LiteralPath (Join-Path $old 'synthetic.sqlite3') -Value 'Solo fixture sintético'
$refused = $false
try { & $cleanupScript -DistributionPath $fixtureRoot | Out-Null } catch { $refused = $true }
if (-not $refused -or -not (Test-Path -LiteralPath (Join-Path $old 'synthetic.sqlite3'))) { throw 'No se protegió el archivo de datos sintético.' }
$refused = $false
try { & $cleanupScript -DistributionPath $fixtureRoot -Version '0.0.1' | Out-Null } catch { $refused = $true }
if (-not $refused) { throw 'Se permitió conservar una versión distinta de la instalada.' }
# Exercise the real publisher with a separate synthetic project root.
$publishRoot = Join-Path $fixtureRoot 'publisher'
$publishScripts = Join-Path $publishRoot 'scripts'
$publishDist = Join-Path $publishRoot 'dist'
New-Item -ItemType Directory -Path $publishScripts,$publishDist -Force | Out-Null
foreach ($script in @('publish-local-bundle.ps1','clean-old-distributions.ps1')) {
    Copy-Item -LiteralPath (Join-Path $projectRoot ('scripts\' + $script)) -Destination (Join-Path $publishScripts $script)
}
Set-Content -LiteralPath (Join-Path $publishRoot 'pubspec.yaml') -Value ("version: " + $keepVersion)
$publishOld = Join-Path $publishDist '0.0.1\ValinorSanctum2'
$publishStable = Join-Path $publishDist 'ValinorSanctum2'
New-Item -ItemType Directory -Path $publishOld,$publishStable -Force | Out-Null
Copy-Item -LiteralPath $executable -Destination (Join-Path $publishOld 'valinor_sanctum_2.exe')
Copy-Item -LiteralPath $executable -Destination (Join-Path $publishStable 'valinor_sanctum_2.exe')
Compress-Archive -LiteralPath $publishOld -DestinationPath (Join-Path $publishDist 'valinor-sanctum-2-0.0.1-windows-x64.zip')
$archive = Join-Path $publishDist ("valinor-sanctum-2-" + $keepVersion + "-windows-x64.zip")
Copy-Item -LiteralPath (Join-Path $projectRoot ("dist\valinor-sanctum-2-" + $keepVersion + "-windows-x64.zip")) -Destination $archive
$published = & (Join-Path $publishScripts 'publish-local-bundle.ps1') -ArchivePath $archive | ConvertFrom-Json
if ($published.obsoleteArtifactsRemoved -ne 2 -or $null -ne $published.previousBundle) { throw 'La publicación no limpió las entregas anteriores.' }
if ((Get-FileHash -LiteralPath (Join-Path $publishStable 'valinor_sanctum_2.exe')).Hash -ne (Get-FileHash -LiteralPath $executable).Hash) { throw 'La entrega publicada no coincide.' }
if (@(Get-ChildItem -LiteralPath (Join-Path $publishRoot 'tmp') -File -Recurse).Count -ne 0) { throw 'Quedaron binarios anteriores en tmp tras publicar.' }
$resolvedFixture = [IO.Path]::GetFullPath($fixtureRoot)
if ($resolvedFixture -ne $fixtureRoot -or -not $resolvedFixture.StartsWith((Join-Path $projectRoot 'tmp') + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Destino de limpieza del fixture inválido.' }
$fixtureQueue = [Collections.Generic.Queue[string]]::new()
$fixtureQueue.Enqueue($resolvedFixture)
while ($fixtureQueue.Count -gt 0) {
    $directory = $fixtureQueue.Dequeue()
    if (((Get-Item -LiteralPath $directory -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Enlace en fixture.' }
    foreach ($item in Get-ChildItem -LiteralPath $directory -Force) {
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Enlace en fixture.' }
        if ($item.PSIsContainer) { $fixtureQueue.Enqueue($item.FullName) }
    }
}
Remove-Item -LiteralPath $resolvedFixture -Recurse -Force
[pscustomobject]@{ passed = 5; dryRun = $true; versionRetention = $true; privateDataGuard = $true; versionMismatchGuard = $true; automaticPublicationCleanup = $true } | ConvertTo-Json
