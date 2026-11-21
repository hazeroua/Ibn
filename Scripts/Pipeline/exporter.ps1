<#
.SYNOPSIS
  Exporte la version jouable native dans Build/windows/ ou Build/macos/ (extension C++ en version release).
.PARAMETER Plateforme
  windows ou macos. Par défaut : la plateforme hôte, Windows restant la cible sur Linux/CI.
#>
[CmdletBinding()]
param(
    [ValidateSet('windows', 'macos')][string]$Plateforme = ''
)
. "$PSScriptRoot/commun.ps1"

if (-not $Plateforme) { $Plateforme = if ($EstMacOS) { 'macos' } else { 'windows' } }
if ($Plateforme -eq 'macos' -and -not $EstMacOS) {
    throw "L'export macOS doit être produit sur macOS."
}

if (-not $Outils.godot.modeles_export -or -not (Test-Path (Join-Path $Outils.godot.modeles_export 'version.txt'))) {
    $installateur = if ($EstMacOS) { 'Tools/installer-macos.command' } else { 'Tools/installer.ps1' }
    throw "Modèles d'export de Godot absents : relancez $installateur."
}
& (Join-Path $PSScriptRoot 'compiler.ps1') -Cible release

$dossier = Join-Path $Racine "Build/$Plateforme"
New-Item -ItemType Directory -Force -Path $dossier | Out-Null
$journalExport = Join-Path $DossierMesures "journaux/export-$Plateforme.log"
$journalDemarrage = Join-Path $DossierMesures "journaux/export-$Plateforme-demarrage.log"

if ($Plateforme -eq 'windows') {
    $exe = Join-Path $dossier 'IbnKhaldoun.exe'
    Write-Etape 'Export Windows'
    $null = Invoke-Godot -Arguments @('--headless', '--path', $Jeu, '--export-release', 'Windows Desktop', $exe) -Journal $journalExport
    $console = Join-Path $dossier 'IbnKhaldoun.console.exe'
    $attendus = @($exe, $console, (Join-Path $dossier 'IbnKhaldoun.pck'), (Join-Path $dossier 'libibn.windows.template_release.x86_64.dll'))
    $executableTest = $console
} else {
    $app = Join-Path $dossier 'IbnKhaldoun.app'
    $exe = Join-Path $app "Contents/MacOS/Les Chemins d'Ibn Khaldoun"
    Write-Etape 'Export macOS Apple silicon'
    $null = Invoke-Godot -Arguments @('--headless', '--path', $Jeu, '--export-release', 'macOS', $app) -Journal $journalExport
    $attendus = @($app, $exe, (Join-Path $app 'Contents/Frameworks/libibn.macos.template_release.arm64.dylib'))
    $executableTest = $exe
}
foreach ($attendu in $attendus) {
    if (-not (Test-Path $attendu)) { throw "Fichier attendu absent après l'export : $attendu" }
}

Write-Etape 'Démarrage de la version exportée'
# 120 images sans fenêtre : chargement de l'extension C++, des données, de la scène par défaut.
$null = Invoke-Godot -Executable $executableTest -Arguments @('--headless', '--quit-after', '120') -Journal $journalDemarrage
Write-Ok "Version jouable : $exe"
