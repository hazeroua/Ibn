<#
.SYNOPSIS
  Génère la médina de Tunis (Game/data/tunis/) à partir de sa description.

.DESCRIPTION
  Lit Game/data/tunis/generation/medina.json (plan décrit en mots-clés : voies, place, emplacements),
  la graine de Game/data/tunis/city.json et le catalogue, puis écrit les cellules, city.json, le plan
  généré (medina_layout.json) et le verrou (medina_lock.json). Rien n'est écrit si une vérification
  échoue (bornes, graphe, chevauchements, remparts, budgets). Les instances ajoutées à la main sont
  conservées ; les retouches d'instances générées vont dans generation/medina_overrides.json.
.PARAMETER Verifier
  Vérifie seulement que les fichiers versionnés sont à jour (aucune écriture).
.PARAMETER Confirmer
  Autorise le remplacement d'instances générées modifiées directement dans les cellules.
#>
[CmdletBinding()]
param(
    [switch]$Verifier,
    [switch]$Confirmer
)
. "$PSScriptRoot/commun.ps1"

Write-Etape $(if ($Verifier) { 'Médina de Tunis : vérification' } else { 'Médina de Tunis : génération' })
$options = @()
if ($Verifier) { $options += '--check' }
if ($Confirmer) { $options += '--confirm' }
$arguments = @('--headless', '--path', $Jeu, '--script', 'res://tools/medina/generate_medina.gd')
if ($options.Count -gt 0) { $arguments += @('--') + $options }
$null = Invoke-Godot -Arguments $arguments -Journal (Join-Path $DossierMesures 'journaux/generer-medina.log')
Write-Ok $(if ($Verifier) { 'Données de la médina à jour' } else { 'Médina générée' })
