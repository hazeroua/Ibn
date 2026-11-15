<#
.SYNOPSIS
  Importe les ressources du projet Godot (textures, modèles, sons…) en ligne de commande.
#>
[CmdletBinding()]
param()
. "$PSScriptRoot/commun.ps1"

Write-Etape 'Import des ressources Godot'
$null = Invoke-Godot -Arguments @('--headless', '--path', $Jeu, '--import') -Journal (Join-Path $DossierMesures 'journaux/import.log')
Write-Ok 'Import terminé'
