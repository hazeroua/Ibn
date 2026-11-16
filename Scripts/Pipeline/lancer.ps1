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
# Ressources libres : tout est (re)téléchargé dès qu'une texture déclarée dans polyhaven.json manque (rien n'est retéléchargé si intact).
$texturesDeclarees = @((Get-Content -Raw -Encoding UTF8 (Join-Path $Jeu 'data/assets/polyhaven.json') | ConvertFrom-Json).textures)
$textureManquante = @($texturesDeclarees | Where-Object { -not (Test-Path (Join-Path $Jeu "assets/textures/polyhaven/$($_.id)")) }).Count -gt 0
if ($textureManquante) { & (Join-Path $PSScriptRoot 'importer-ressources.ps1') }
# Sons libres : rien n'est retéléchargé s'ils sont déjà intacts ; ceux ajoutés par une mise à jour arrivent ici.
& (Join-Path $PSScriptRoot 'importer-sons.ps1')
& (Join-Path $PSScriptRoot 'compiler.ps1') -Cible debug
# Modèles du désert : régénérés si le générateur ou son manifeste est plus récent que le plus ancien modèle.
$sourcesProps = @((Join-Path $Racine 'Scripts/Blender/generer_props_desert.py'), (Join-Path $Racine 'Scripts/Blender/atlas_vegetation.py'), (Join-Path $Racine 'Game/data/assets/desert_props.json'))
$modeles = @(Get-ChildItem -Path (Join-Path $Jeu 'assets/desert') -Filter '*.glb' -ErrorAction SilentlyContinue)
$attendus = @('buisson_a.glb', 'herbe_seche_a.glb', 'palmier_a_lod1.glb', 'acacia_a_lod0.glb', 'acacia_imposteur.glb', 'tamaris_a_lod0.glb', 'tamaris_imposteur.glb', 'jujubier_a.glb', 'laurier_rose_a.glb', 'retam_a.glb', 'foliage_atlas.dds')
$manquant = @($attendus | Where-Object { -not (Test-Path (Join-Path $Jeu "assets/desert/$_")) }).Count -gt 0
$plusRecent = ($sourcesProps | ForEach-Object { (Get-Item $_).LastWriteTimeUtc } | Measure-Object -Maximum).Maximum
$plusAncien = if ($modeles.Count -gt 0) { ($modeles | Measure-Object -Property LastWriteTimeUtc -Minimum).Minimum } else { [datetime]::MinValue }
if ($manquant -or $plusRecent -gt $plusAncien) { & (Join-Path $PSScriptRoot 'generer-props-desert.ps1') }
# Modèles de la faune : même règle (générateur ou manifeste plus récent que le plus ancien modèle).
$sourcesFaune = @((Join-Path $Racine 'Scripts/Blender/generer_faune.py'), (Join-Path $Racine 'Game/data/assets/fauna_models.json'))
$modelesFaune = @(Get-ChildItem -Path (Join-Path $Jeu 'assets/faune') -Filter '*.glb' -ErrorAction SilentlyContinue)
$manquantFaune = @(@('gazelle_dorcas.glb', 'tourterelle.glb', 'libellule.glb') | Where-Object { -not (Test-Path (Join-Path $Jeu "assets/faune/$_")) }).Count -gt 0
$plusRecentFaune = ($sourcesFaune | ForEach-Object { (Get-Item $_).LastWriteTimeUtc } | Measure-Object -Maximum).Maximum
$plusAncienFaune = if ($modelesFaune.Count -gt 0) { ($modelesFaune | Measure-Object -Property LastWriteTimeUtc -Minimum).Minimum } else { [datetime]::MinValue }
if ($manquantFaune -or $plusRecentFaune -gt $plusAncienFaune) { & (Join-Path $PSScriptRoot 'generer-faune.ps1') }
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
