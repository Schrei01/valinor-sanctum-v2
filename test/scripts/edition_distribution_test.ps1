$ErrorActionPreference='Stop'
$projectRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$fixture=Join-Path $projectRoot ('tmp\edition-distribution-'+[Guid]::NewGuid().ToString('N'))
if(-not $fixture.StartsWith((Join-Path $projectRoot 'tmp')+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Unsafe fixture'}
New-Item -ItemType Directory -Path $fixture | Out-Null
$dev=Join-Path $projectRoot 'dist\ValinorSanctum2\valinor_sanctum_2.exe'
$prod=Join-Path $projectRoot 'dist\ValinorSanctum2-Produccion\valinor_sanctum_2.exe'
$prodVersion=((Get-Item -LiteralPath $prod).VersionInfo.ProductVersion).Split('+')[0]
$prodArchive=Join-Path $projectRoot ('dist\valinor-sanctum-2-'+$prodVersion+'-production-windows-x64.zip')
$devVersion=((Get-Item -LiteralPath $dev).VersionInfo.ProductVersion).Split('+')[0]
$devArchive=Join-Path $projectRoot ('dist\valinor-sanctum-2-'+$devVersion+'-development-windows-x64.zip')
foreach($folder in @('ValinorSanctum2','ValinorSanctum2-Produccion','0.0.1\ValinorSanctum2')){New-Item -ItemType Directory -Path (Join-Path $fixture $folder) -Force | Out-Null}
Copy-Item -LiteralPath $dev -Destination (Join-Path $fixture 'ValinorSanctum2\valinor_sanctum_2.exe')
Copy-Item -LiteralPath $prod -Destination (Join-Path $fixture 'ValinorSanctum2-Produccion\valinor_sanctum_2.exe')
Copy-Item -LiteralPath $dev -Destination (Join-Path $fixture '0.0.1\ValinorSanctum2\valinor_sanctum_2.exe')
Copy-Item -LiteralPath $devArchive -Destination (Join-Path $fixture 'valinor-sanctum-2-0.0.1-development-windows-x64.zip')
Copy-Item -LiteralPath $devArchive -Destination (Join-Path $fixture 'valinor-sanctum-2-0.30.0-development-windows-x64.zip')
Copy-Item -LiteralPath $prodArchive -Destination (Join-Path $fixture ('valinor-sanctum-2-'+$prodVersion+'-production-windows-x64.zip'))
Copy-Item -LiteralPath $prodArchive -Destination (Join-Path $fixture 'valinor-sanctum-2-0.0.1-production-windows-x64.zip')
Set-Content -LiteralPath (Join-Path $fixture 'Valinor-Sanctum-0.0.1-Produccion-Instalar.exe') -Value 'Synthetic fixture; never executed'
$cleanup=Join-Path $projectRoot 'scripts\clean-old-distributions.ps1'
$preview=& $cleanup -DistributionPath $fixture -Edition Installed -DryRun | ConvertFrom-Json
if($preview.artifacts -ne 2){throw 'Production preview crossed edition boundaries'}
$cleaned=& $cleanup -DistributionPath $fixture -Edition Installed | ConvertFrom-Json
if($cleaned.artifacts -ne 2){throw 'Wrong production deletion set'}
foreach($name in @('ValinorSanctum2','0.0.1','valinor-sanctum-2-0.0.1-development-windows-x64.zip','valinor-sanctum-2-0.30.0-development-windows-x64.zip')){if(-not (Test-Path -LiteralPath (Join-Path $fixture $name))){throw ('Development was removed: '+$name)}}
$devPreview=& $cleanup -DistributionPath $fixture -Edition Development -DryRun | ConvertFrom-Json
$expectedDevCandidates=if([version]$devVersion -gt [version]'0.30.0'){3}else{2}
if($devPreview.artifacts -ne $expectedDevCandidates){throw 'Development preview selected production'}
# A new development release may retire previous development, including 0.30.
Copy-Item -LiteralPath $prod -Destination (Join-Path $fixture 'ValinorSanctum2\valinor_sanctum_2.exe') -Force
$newerDevPreview=& $cleanup -DistributionPath $fixture -Edition Development -DryRun | ConvertFrom-Json
if($newerDevPreview.artifacts -ne 3){throw 'Obsolete development 0.30.0 was not selected for cleanup'}

# Exercise the real publisher on an isolated tree while preserving its dev bundle.
$publishRoot=Join-Path $fixture 'publisher'
New-Item -ItemType Directory -Path (Join-Path $publishRoot 'scripts'),(Join-Path $publishRoot 'dist\ValinorSanctum2') -Force | Out-Null
foreach($file in @('publish-local-bundle.ps1','clean-old-distributions.ps1')){Copy-Item -LiteralPath (Join-Path $projectRoot ('scripts\'+$file)) -Destination (Join-Path $publishRoot ('scripts\'+$file))}
Set-Content -LiteralPath (Join-Path $publishRoot 'pubspec.yaml') -Value ('version: '+$prodVersion)
$preservedExe=Join-Path $publishRoot 'dist\ValinorSanctum2\valinor_sanctum_2.exe'
Copy-Item -LiteralPath $dev -Destination $preservedExe
$devHash=(Get-FileHash -LiteralPath $preservedExe).Hash
$publishedArchive=Join-Path $publishRoot ('dist\valinor-sanctum-2-'+$prodVersion+'-production-windows-x64.zip')
Copy-Item -LiteralPath $prodArchive -Destination $publishedArchive
$result=& (Join-Path $publishRoot 'scripts\publish-local-bundle.ps1') -ArchivePath $publishedArchive -Edition Installed | ConvertFrom-Json
if((Get-FileHash -LiteralPath $preservedExe).Hash -ne $devHash){throw 'Production publication changed development'}
if(-not (Test-Path -LiteralPath (Join-Path $publishRoot 'dist\ValinorSanctum2-Produccion\valinor_sanctum_2.exe'))){throw 'Production did not publish separately'}
$refused=$false
try {& (Join-Path $publishRoot 'scripts\publish-local-bundle.ps1') -ArchivePath $publishedArchive -Edition Development | Out-Null} catch {$refused=$true}
if(-not $refused -or (Get-FileHash -LiteralPath $preservedExe).Hash -ne $devHash){throw 'Wrong edition was not rejected before mutation'}

# Resolve and inspect the complete temporary tree before recursive removal.
$resolved=[IO.Path]::GetFullPath($fixture)
if($resolved -ne $fixture -or -not $resolved.StartsWith((Join-Path $projectRoot 'tmp')+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Unsafe cleanup target'}
foreach($item in Get-ChildItem -LiteralPath $resolved -Force -Recurse){if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Fixture link detected'}}
Remove-Item -LiteralPath $resolved -Recurse -Force
[pscustomobject]@{productionCleanupPreservesDevelopment=$true;developmentCleanupPreservesProduction=$true;productionPublicationPreservesDevelopment=$true;wrongEditionPublicationRejected=$true;latestDevelopmentPreservedByProduction=$true;obsoleteDevelopmentCanBeRetired=$true} | ConvertTo-Json
