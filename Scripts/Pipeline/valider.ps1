<#
.SYNOPSIS
  Chaîne complète de vérification : à lancer avant de rendre la main (et par la CI).

.DESCRIPTION
  1. Qualité du GDScript (gdlint, gdformat)
  2. Ressources libres (importer-ressources)
  3. Compilation C++ (debug et release)
  4. Import Godot
  5. Construction des scènes générées
  6. Tests GUT
  7. Mesures de performance et captures d'écran de chaque carte (sauf -SansRendu)
.PARAMETER SansRendu
  Pour une machine sans affichage (CI Windows) : pas de mesures ni de captures.
.PARAMETER SansBudgets
  Mesure sans vérifier les budgets : uniquement hors de la machine de développement (CI).
#>
[CmdletBinding()]
param(
    [switch]$SansRendu,
    [switch]$SansBudgets,
    [string[]]$Cartes = @('sandbox', 'vitrine_personnage')
)
. "$PSScriptRoot/commun.ps1"

$debut = Get-Date

Write-Etape 'Qualité du GDScript'
$scripts = @(Get-ChildItem -Path $Jeu -Recurse -Filter '*.gd' | Where-Object { $_.FullName -notmatch '[\\/]addons[\\/]' } | ForEach-Object { $_.FullName })
Push-Location $Jeu
try {
    Invoke-Outil $PythonOutils (@('-m', 'gdtoolkit.linter') + $scripts)
    Invoke-Outil $PythonOutils (@('-m', 'gdtoolkit.formatter', '--check', '--line-length', '140') + $scripts)
} finally {
    Pop-Location
}
Write-Ok "$($scripts.Count) scripts conformes"

& (Join-Path $PSScriptRoot 'importer-ressources.ps1')
& (Join-Path $PSScriptRoot 'compiler.ps1') -Cible toutes
& (Join-Path $PSScriptRoot 'importer.ps1')
& (Join-Path $PSScriptRoot 'construire.ps1')
& (Join-Path $PSScriptRoot 'tester.ps1')

if (-not $SansRendu) {
    foreach ($carte in $Cartes) {
        & (Join-Path $PSScriptRoot 'mesurer.ps1') -Carte $carte -SansBudgets:$SansBudgets
        & (Join-Path $PSScriptRoot 'capturer.ps1') -Carte $carte
    }
}

Write-Etape 'Validation terminée'
Write-Ok ("Tout est vert en {0:N0} s" -f ((Get-Date) - $debut).TotalSeconds)
