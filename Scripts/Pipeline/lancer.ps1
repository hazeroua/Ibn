<#
.SYNOPSIS
  Lance le jeu (depuis le projet) ; construit d'abord ce qui manque.
.PARAMETER Scene
  Scène à ouvrir (ex. res://world/sandbox/sandbox.tscn). Par défaut : la scène du projet.
.PARAMETER Export
  Lance la version exportée (Build/windows/IbnKhaldoun.exe) au lieu du projet.
#>
[CmdletBinding()]
param(
    [string]$Scene = '',
    [switch]$Export
)
. "$PSScriptRoot/commun.ps1"

if ($Export) {
    $exe = Join-Path $Racine 'Build/windows/IbnKhaldoun.exe'
    if (-not (Test-Path $exe)) { & (Join-Path $PSScriptRoot 'exporter.ps1') }
    $argumentsExport = @()
    if ($Scene) { $argumentsExport = @('--', "--scene=$Scene") }
    & $exe @argumentsExport
    exit $LASTEXITCODE
}

$extension = if ($EstWindows) { 'libibn.windows.template_debug.x86_64.dll' } else { 'libibn.linux.template_debug.x86_64.so' }
if (-not (Test-Path (Join-Path $Jeu "bin/$extension"))) { & (Join-Path $PSScriptRoot 'compiler.ps1') -Cible debug }
if (-not (Test-Path (Join-Path $Jeu 'assets/textures/polyhaven'))) { & (Join-Path $PSScriptRoot 'importer-ressources.ps1') }
if (-not (Test-Path (Join-Path $Jeu '.godot'))) { & (Join-Path $PSScriptRoot 'importer.ps1') }
$scenesManquantes = @(Get-ChildItem -Path (Join-Path $Jeu 'tools/builders') -Filter 'build_*.gd' | Where-Object {
        $nom = $_.BaseName.Substring('build_'.Length)
        -not (Test-Path (Join-Path $Jeu "world/$nom/$nom.tscn"))
    })
if ($scenesManquantes.Count -gt 0) { & (Join-Path $PSScriptRoot 'construire.ps1') }

$arguments = @('--path', $Jeu)
if ($Scene) { $arguments += @('--', "--scene=$Scene") }
& $GodotEditeur @arguments
exit $LASTEXITCODE
