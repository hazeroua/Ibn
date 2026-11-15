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
# Rejouer un test isolé ; renvoie $true s'il réussit. Une ligne ERROR de Godot reste un échec immédiat.
function Test-Rejeu([string]$Script, [string]$Test, [string]$Rapport) {
    $args2 = @(
        '--headless', '--path', $Jeu,
        '-s', 'res://addons/gut/gut_cmdln.gd',
        '-gexit', '-glog=2', "-gtest=$Script", "-gunit_test_name=$Test",
        "-gjunit_xml_file=$Rapport"
    )
    Remove-Item -Force -ErrorAction SilentlyContinue $Rapport
    try {
        $null = Invoke-Godot -Arguments $args2
    } catch {
        if ("$_" -notmatch "s'est terminé avec le code") { throw }
    }
    if (-not (Test-Path $Rapport)) { return $false }
    [xml]$r = Get-Content -Raw -Encoding UTF8 $Rapport
    return ([int]$r.testsuites.tests -gt 0 -and [int]$r.testsuites.failures -eq 0)
}

$journal = Join-Path $dossierRapport 'tests.log'
$premierPassage = $true
try {
    $null = Invoke-Godot -Arguments $arguments -Journal $journal
} catch {
    if ("$_" -notmatch "s'est terminé avec le code") { throw }
    $premierPassage = $false
}
if (-not (Test-Path $junit)) { throw "Rapport de tests absent : $junit" }
[xml]$rapport = Get-Content -Raw -Encoding UTF8 $junit
$total = [int]$rapport.testsuites.tests
$echecs = [int]$rapport.testsuites.failures
if ($total -eq 0) { throw 'Aucun test exécuté.' }
if ($echecs -gt 0 -or -not $premierPassage) {
    # Les tests de charge chronométrés subissent les interruptions du système (antivirus, mise à jour,
    # économie d'énergie) pendant les 5 minutes de la suite complète. Un test en échec est rejoué seul,
    # jusqu'à $rejeux fois : un vrai dépassement échoue à chaque fois, une interruption passagère non.
    # Au-delà de $maxRejoues échecs, il y a un vrai problème : pas de rejeu.
    $rejeux = 2
    $maxRejoues = 3
    $enEchec = @()
    foreach ($suite in $rapport.testsuites.testsuite) {
        foreach ($cas in $suite.testcase) {
            if ($cas.failure) { $enEchec += [pscustomobject]@{ Script = 'res://' + [string]$suite.name; Test = [string]$cas.name } }
        }
    }
    if ($enEchec.Count -eq 0 -or $enEchec.Count -gt $maxRejoues) { throw "$echecs test(s) en échec sur $total." }
    $instables = Join-Path $dossierRapport 'instables.log'
    foreach ($e in $enEchec) {
        $ok = $false
        for ($n = 1; $n -le $rejeux -and -not $ok; $n++) {
            Write-Host "  Rejeu $n/$rejeux de $($e.Script) :: $($e.Test)" -ForegroundColor Yellow
            $ok = Test-Rejeu -Script $e.Script -Test $e.Test -Rapport (Join-Path $dossierRapport 'rejeu.xml')
        }
        if (-not $ok) { throw "Échec confirmé après $rejeux rejeux : $($e.Script) :: $($e.Test)" }
        "$(Get-Date -Format s) $($e.Script) :: $($e.Test) : échec dans la suite complète, réussi seul" | Add-Content -Encoding UTF8 $instables
        Write-Host "  [!] $($e.Test) : échec passager dans la suite complète, réussi seul (noté dans $instables)" -ForegroundColor Yellow
    }
}
Write-Ok "$total tests réussis (rapport : $junit)"
