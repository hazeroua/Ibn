<#
.SYNOPSIS
  Exporte la version jouable Windows dans Build/windows/ (extension C++ en version release).
#>
[CmdletBinding()]
param()
. "$PSScriptRoot/commun.ps1"

if (-not $Outils.godot.modeles_export -or -not (Test-Path (Join-Path $Outils.godot.modeles_export 'version.txt'))) {
    throw "Modèles d'export de Godot absents : relancez Tools/installer.ps1."
}
& (Join-Path $PSScriptRoot 'compiler.ps1') -Cible release

$dossier = Join-Path $Racine 'Build/windows'
New-Item -ItemType Directory -Force -Path $dossier | Out-Null
$exe = Join-Path $dossier 'IbnKhaldoun.exe'
Write-Etape 'Export Windows'
$null = Invoke-Godot -Arguments @('--headless', '--path', $Jeu, '--export-release', 'Windows Desktop', $exe) `
    -Journal (Join-Path $DossierMesures 'journaux/export.log')
foreach ($attendu in @($exe, (Join-Path $dossier 'IbnKhaldoun.pck'), (Join-Path $dossier 'libibn.windows.template_release.x86_64.dll'))) {
    if (-not (Test-Path $attendu)) { throw "Fichier attendu absent après l'export : $attendu" }
}
Write-Ok "Version jouable : $exe"
