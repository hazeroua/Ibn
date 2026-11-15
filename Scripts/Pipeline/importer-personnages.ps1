<#
.SYNOPSIS
  Télécharge les sources libres des personnages 3D et prépare chaque personnage avec Blender.

.DESCRIPTION
  Source de vérité : Game/data/assets/characters.json.
  1. Télécharge chaque fichier source (adresse figée, somme SHA-256 vérifiée) dans Tools/_telechargements/personnages/.
  2. Pour chaque personnage, lance Blender en ligne de commande (Scripts/Blender/preparer_personnage.py) qui produit
     Game/assets/characters/<id>/<id>.glb : échelle, orientation, une seule surface, animations du contrat.
  3. Écrit les réglages d'import Godot du GLB (script de fin d'import : bibliothèque « locomotion »).
  Rien n'est refait si le résultat est à jour (empreinte du script, du manifeste et de la version de Blender).
  Les fichiers produits ne sont pas versionnés. Appelé par importer-ressources.ps1 ; lancer ensuite importer.ps1.
.PARAMETER Force
  Reprépare les personnages même si le résultat est à jour.
#>
[CmdletBinding()]
param([switch]$Force)
. "$PSScriptRoot/commun.ps1"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$entetes = @{ 'User-Agent' = 'IbnKhaldoun-pipeline (https://github.com/hazeroua/Ibn)' }
$scriptBlender = Join-Path $Racine 'Scripts/Blender/preparer_personnage.py'
$manifestePath = Join-Path $Jeu 'data/assets/characters.json'
$cache = Join-Path $Racine 'Tools/_telechargements/personnages'

function Get-Sha256([string]$Chemin) {
    return (Get-FileHash -Algorithm SHA256 -Path $Chemin).Hash.ToLowerInvariant()
}

function Get-Sha256Texte([string]$Texte) {
    $algorithme = [Security.Cryptography.SHA256]::Create()
    try {
        $octets = $algorithme.ComputeHash([Text.Encoding]::UTF8.GetBytes($Texte))
    } finally {
        $algorithme.Dispose()
    }
    return ([BitConverter]::ToString($octets) -replace '-', '').ToLowerInvariant()
}

function Get-CheminBlender {
    # Windows : chemin écrit dans Tools/outils.json par Tools/installer.ps1 ; Linux (CI) : « blender » du système.
    $propriete = $Script:Outils.PSObject.Properties['blender']
    if ($propriete -and $propriete.Value -and $propriete.Value.chemin -and (Test-Path $propriete.Value.chemin)) {
        return $propriete.Value.chemin
    }
    $commande = Get-Command 'blender' -ErrorAction SilentlyContinue
    if ($commande) { return $commande.Source }
    throw 'Blender introuvable : relancez Tools/installer.ps1 (Windows) ou installez le paquet « blender » (Linux).'
}

function Invoke-Blender {
    param([string]$Blender, [string[]]$Arguments, [string]$Journal)
    Write-Host "  > blender $($Arguments -join ' ')" -ForegroundColor DarkGray
    $ancien = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $sortie = @(& $Blender @Arguments 2>&1 | ForEach-Object { "$_" })
        $code = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $ancien
    }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Journal) | Out-Null
    $sortie | Set-Content -Encoding UTF8 $Journal
    foreach ($ligne in $sortie) { Write-Host $ligne }
    $erreurs = @($sortie | Where-Object { $_ -match '^(ERREUR preparer_personnage|Traceback|Error: )' })
    if ($erreurs.Count -gt 0) { throw "Blender a signalé une erreur :`n$($erreurs -join "`n")" }
    if ($code -ne 0) { throw "Blender s'est terminé avec le code $code." }
}

function Write-ReglagesImportPersonnage([string]$Glb) {
    # Réglages explicites et identiques sur toutes les machines. Godot complète ensuite le fichier
    # (identifiant, chemin importé) : on ne réécrit que si un réglage voulu manque ou diffère.
    $voulus = @(
        'importer="scene"', 'type="PackedScene"',
        'meshes/ensure_tangents=false', 'meshes/generate_lods=true', 'meshes/create_shadow_meshes=true', 'meshes/light_baking=0',
        'animation/import=true', 'animation/fps=30', 'animation/trimming=false', 'animation/remove_immutable_tracks=true',
        'animation/import_rest_as_RESET=false',
        'import_script/path="res://assets/characters/character_post_import.gd"'
    )
    $import = "$Glb.import"
    if (Test-Path $import) {
        $existantes = @(Get-Content -Encoding UTF8 $import | ForEach-Object { $_.Trim() })
        $manquants = @($voulus | Where-Object { $existantes -notcontains $_ })
        if ($manquants.Count -eq 0) { return }
    }
    $contenu = @('[remap]', '', 'importer="scene"', 'importer_version=1', 'type="PackedScene"', '', '[params]', '') +
        @($voulus | Where-Object { $_ -notmatch '^(importer|type)=' })
    $contenu | Set-Content -Encoding ASCII $import
}

Write-Etape 'Personnages 3D (sources libres, Blender)'
$manifeste = Get-Content -Raw -Encoding UTF8 $manifestePath | ConvertFrom-Json
$blender = Get-CheminBlender
$ancienEtat = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
try {
    $sortieVersion = @(& $blender --background --factory-startup --version 2>&1 | ForEach-Object { "$_" })
} finally {
    $ErrorActionPreference = $ancienEtat
}
$ligneVersion = @($sortieVersion | Where-Object { $_ -match '^Blender \d' } | Select-Object -First 1)
$versionBlender = if ($ligneVersion.Count -gt 0) { $ligneVersion[0].Trim() } else { '' }
if (-not $versionBlender) { throw "Version de Blender illisible : $($sortieVersion -join ' ')" }
Write-Ok "Blender : $versionBlender"

# 1. Sources : téléchargement et vérification SHA-256
$dossiersSources = @{}
foreach ($source in $manifeste.sources) {
    if ($source.id -notmatch '^[a-z0-9_]+$') { throw "Identifiant de source invalide : « $($source.id) »." }
    $dossier = Join-Path $cache $source.id
    foreach ($fichier in $source.files) {
        if ($fichier.path -notmatch '^[A-Za-z0-9_./-]+$' -or $fichier.path -match '\.\.') { throw "Chemin de source invalide : « $($fichier.path) »." }
        $destination = Join-Path $dossier $fichier.path
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination) | Out-Null
        $attendu = $fichier.sha256.ToLowerInvariant()
        if (-not ((Test-Path $destination) -and ((Get-Sha256 $destination) -eq $attendu))) {
            $partiel = "$destination.part"
            Invoke-WebRequest -Uri ($source.base_url + $fichier.path) -OutFile $partiel -UseBasicParsing -Headers $entetes
            if ((Get-Sha256 $partiel) -ne $attendu) {
                Remove-Item -Force $partiel
                throw "Source $($source.id) : somme SHA-256 incorrecte pour $($fichier.path)."
            }
            Move-Item -Force $partiel $destination
        }
        Write-Ok "$($source.id) / $($fichier.path) ($($source.license))"
    }
    $dossiersSources[$source.id] = $dossier
}

# 2. Préparation de chaque personnage
foreach ($personnage in $manifeste.characters) {
    if ($personnage.id -notmatch '^[a-z0-9_]+$') { throw "Identifiant de personnage invalide : « $($personnage.id) »." }
    if (-not $dossiersSources.ContainsKey($personnage.source)) { throw "Personnage $($personnage.id) : source « $($personnage.source) » inconnue." }
    $sortieDossier = Join-Path $Jeu "assets/characters/$($personnage.id)"
    New-Item -ItemType Directory -Force -Path $sortieDossier | Out-Null
    $glb = Join-Path $sortieDossier "$($personnage.id).glb"
    $empreinteFichier = "$glb.empreinte"
    $empreinte = Get-Sha256Texte ("$(Get-Sha256 $scriptBlender)|$(Get-Sha256 $manifestePath)|$versionBlender")
    $aJour = (-not $Force) -and (Test-Path $glb) -and (Test-Path $empreinteFichier) -and
        ((Get-Content -Raw -Encoding ASCII $empreinteFichier).Trim() -eq $empreinte)
    if ($aJour) {
        Write-Ok "$($personnage.id) : déjà à jour"
    } else {
        $rapport = Join-Path $DossierMesures "journaux/personnage-$($personnage.id).json"
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $rapport) | Out-Null
        Remove-Item -Force -ErrorAction SilentlyContinue $empreinteFichier
        $arguments = @(
            '--background', '--factory-startup', '--python', $scriptBlender, '--',
            '--manifest', $manifestePath, '--character', $personnage.id,
            '--source-dir', $dossiersSources[$personnage.source], '--output', $glb, '--report', $rapport
        )
        Invoke-Blender -Blender $blender -Arguments $arguments -Journal (Join-Path $DossierMesures "journaux/personnage-$($personnage.id).log")
        if (-not (Test-Path $glb)) { throw "Blender n'a pas produit $glb." }
        $empreinte | Set-Content -Encoding ASCII $empreinteFichier
        Write-Ok "$($personnage.id) : GLB produit ($glb)"
    }
    Write-ReglagesImportPersonnage $glb
}
