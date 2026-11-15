<#
.SYNOPSIS
  Lance tous les tests automatisés (GUT) en ligne de commande. Échoue si un test échoue.
#>
[CmdletBinding()]
param(
    # Un seul fichier de tests (ex. res://tests/unit/test_input_load.gd) ; vide = tous les tests.
    [string]$Fichier = ''
)
. "$PSScriptRoot/commun.ps1"

Write-Etape 'Tests automatisés (GUT)'
$dossierRapport = Join-Path $DossierMesures 'tests'
New-Item -ItemType Directory -Force -Path $dossierRapport | Out-Null
$junit = Join-Path $dossierRapport 'junit.xml'
$arguments = @(
    '--headless', '--path', $Jeu,
    '-s', 'res://addons/gut/gut_cmdln.gd',
    '-gexit', '-glog=2',
    "-gjunit_xml_file=$junit"
)
if ($Fichier) { $arguments += "-gtest=$Fichier" } else { $arguments += @('-gdir=res://tests/unit', '-ginclude_subdirs') }
$null = Invoke-Godot -Arguments $arguments -Journal (Join-Path $dossierRapport 'tests.log')
if (-not (Test-Path $junit)) { throw "Rapport de tests absent : $junit" }
[xml]$rapport = Get-Content -Raw -Encoding UTF8 $junit
$total = [int]$rapport.testsuites.tests
$echecs = [int]$rapport.testsuites.failures
if ($total -eq 0) { throw 'Aucun test exécuté.' }
if ($echecs -gt 0) { throw "$echecs test(s) en échec sur $total." }
Write-Ok "$total tests réussis (rapport : $junit)"
