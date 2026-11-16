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

function Start-Jeu([string]$Executable, [string[]]$Arguments) {
    # Le jeu est une application à fenêtre : PowerShell ne l'attend pas et ne reçoit pas son code de
    # retour si on l'appelle directement. Start-Process -Wait attend la fermeture du jeu.
    $ligne = ($Arguments | ForEach-Object { '"' + ($_ -replace '"', '\"') + '"' }) -join ' '
    $parametres = @{ FilePath = $Executable; Wait = $true; PassThru = $true }
    if ($ligne) { $parametres['ArgumentList'] = $ligne }
    $processus = Start-Process @parametres
    if ($processus.ExitCode -ne 0) { throw "Le jeu s'est terminé avec le code $($processus.ExitCode)." }
}

if ($Export) {
    $exe = Join-Path $Racine 'Build/windows/IbnKhaldoun.exe'
    if (-not (Test-Path $exe)) { & (Join-Path $PSScriptRoot 'exporter.ps1') }
    $argumentsExport = @()
    if ($Scene) { $argumentsExport = @('--', "--scene=$Scene") }
    Start-Jeu $exe $argumentsExport
    return
}

# Avant chaque lancement : tout ce qui a pu changer depuis le dernier « git pull » est remis à jour
# (compilation C++ incrémentale, import, scènes générées). Aucun test : ils se lancent avec valider.ps1.
if (-not (Test-Path (Join-Path $Jeu 'assets/textures/polyhaven'))) { & (Join-Path $PSScriptRoot 'importer-ressources.ps1') }
& (Join-Path $PSScriptRoot 'compiler.ps1') -Cible debug
& (Join-Path $PSScriptRoot 'importer.ps1')
& (Join-Path $PSScriptRoot 'construire.ps1')

# Journal du jeu : en cas de plantage, c'est ce fichier qu'il faut transmettre.
$dossierJournal = Join-Path $Racine 'Mesures/journaux'
New-Item -ItemType Directory -Force -Path $dossierJournal | Out-Null
$journalJeu = Join-Path $dossierJournal 'jeu.log'
$arguments = @('--path', $Jeu, '--log-file', $journalJeu)
if ($Scene) { $arguments += @('--', "--scene=$Scene") }
Write-Host "  Journal du jeu : $journalJeu"
Start-Jeu $GodotEditeur $arguments
