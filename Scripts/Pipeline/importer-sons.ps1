<#
.SYNOPSIS
  Télécharge les sons libres déclarés dans Game/data/assets/sounds.json et vérifie leur intégrité.

.DESCRIPTION
  Pour chaque son du manifeste : adresse = base_url de sa source + nom du fichier (commit figé),
  téléchargement dans un fichier temporaire, contrôle de la taille exacte et de la somme SHA-256,
  puis rangement dans res://assets/sounds/<id>.ogg avec des réglages d'import explicites (boucle
  seulement pour les sons d'ambiance marqués « loop »). Rien n'est retéléchargé si le fichier est déjà présent et intact. Seules les licences
  CC0 sont acceptées. Appelé à la fin de importer-ressources.ps1 ; lancer ensuite importer.ps1.
#>
[CmdletBinding()]
param()
. "$PSScriptRoot/commun.ps1"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$LicencesAcceptees = @('CC0-1.0')
$TentativesMax = 4

function Get-Sha256([string]$Chemin) {
    return (Get-FileHash -Algorithm SHA256 -Path $Chemin).Hash.ToLowerInvariant()
}

function Test-SonIntact([string]$Chemin, [long]$Octets, [string]$Sha256) {
    if (-not (Test-Path $Chemin)) { return $false }
    if ((Get-Item $Chemin).Length -ne $Octets) { return $false }
    return (Get-Sha256 $Chemin) -eq $Sha256
}

function Write-ReglagesImportSon([string]$Chemin, [bool]$Boucle) {
    # Réglages explicites : un pas ne boucle jamais ; une ambiance (« loop » du manifeste) boucle toujours.
    $contenu = @(
        '[remap]', '', 'importer="oggvorbisstr"', 'type="AudioStreamOggVorbis"', '',
        '[params]', '',
        "loop=$($Boucle.ToString().ToLowerInvariant())",
        'loop_offset=0',
        'bpm=0',
        'beat_count=0',
        'bar_beats=4'
    )
    $import = "$Chemin.import"
    # Réécrit si le réglage de boucle a changé (le reste du fichier est géré par Godot).
    if ((-not (Test-Path $import)) -or -not (Select-String -Quiet -SimpleMatch -Pattern $contenu[7] -Path $import)) {
        $contenu | Set-Content -Encoding ASCII $import
    }
}

function Get-SonDistant([string]$Adresse, [string]$Destination, [long]$Octets, [string]$Sha256, [string]$Id) {
    $entetes = @{ 'User-Agent' = 'IbnKhaldoun-pipeline (https://github.com/hazeroua/Ibn)' }
    $partiel = "$Destination.part"
    for ($tentative = 1; $tentative -le $TentativesMax; $tentative++) {
        try {
            Invoke-WebRequest -Uri $Adresse -OutFile $partiel -UseBasicParsing -Headers $entetes
        } catch {
            if ($tentative -eq $TentativesMax) { throw "Son « $Id » : téléchargement impossible depuis $Adresse ($($_.Exception.Message))." }
            Start-Sleep -Seconds (2 * $tentative)
            continue
        }
        if (Test-SonIntact $partiel $Octets $Sha256) {
            Move-Item -Force $partiel $Destination
            return
        }
        $recu = (Get-Item $partiel).Length
        Remove-Item -Force $partiel
        if ($tentative -eq $TentativesMax) {
            throw "Son « $Id » : fichier reçu non conforme ($recu octets au lieu de $Octets, ou somme SHA-256 différente) depuis $Adresse."
        }
        Start-Sleep -Seconds (2 * $tentative)
    }
}

Write-Etape 'Sons libres (CC0)'
$manifeste = Get-Content -Raw -Encoding UTF8 (Join-Path $Jeu 'data/assets/sounds.json') | ConvertFrom-Json
if ($manifeste.destination -ne 'res://assets/sounds/') { throw "Manifeste des sons : destination inattendue « $($manifeste.destination) »." }
$dossier = Join-Path $Jeu 'assets/sounds'
New-Item -ItemType Directory -Force -Path $dossier | Out-Null

$ids = @{}
$telecharges = 0
foreach ($son in $manifeste.sounds) {
    if ($son.id -notmatch '^[a-z0-9_]+$') { throw "Identifiant de son invalide : « $($son.id) »." }
    if ($ids.ContainsKey($son.id)) { throw "Identifiant de son en double : « $($son.id) »." }
    $ids[$son.id] = $true
    if ($son.file -notmatch '^[A-Za-z0-9_-]+\.ogg$') { throw "Son « $($son.id) » : nom de fichier distant invalide « $($son.file) »." }
    if ($son.sha256 -notmatch '^[0-9a-f]{64}$') { throw "Son « $($son.id) » : somme SHA-256 invalide." }
    $octets = [long]$son.bytes
    if ($octets -le 0) { throw "Son « $($son.id) » : taille invalide." }
    $propriete = $manifeste.sources.PSObject.Properties[[string]$son.source]
    if ($null -eq $propriete) { throw "Son « $($son.id) » : source « $($son.source) » absente du manifeste." }
    $source = $propriete.Value
    if ($LicencesAcceptees -notcontains $source.license) { throw "Son « $($son.id) » : licence « $($source.license) » refusée (CC0 uniquement)." }
    if ($source.base_url -notmatch '^https://[^\s]+/$') { throw "Source « $($son.source) » : base_url invalide." }

    $destination = Join-Path $dossier "$($son.id).ogg"
    if (-not (Test-SonIntact $destination $octets $son.sha256)) {
        Get-SonDistant ($source.base_url + $son.file) $destination $octets $son.sha256 $son.id
        $telecharges++
    }
    Write-ReglagesImportSon $destination ([bool]($son.PSObject.Properties['loop'] -and $son.loop))
}
Write-Ok "$($ids.Count) sons vérifiés (taille et SHA-256), dont $telecharges téléchargés"
