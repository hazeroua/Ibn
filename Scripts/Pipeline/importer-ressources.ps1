<#
.SYNOPSIS
  Télécharge les ressources libres déclarées dans les manifestes et range celles déposées dans Import/.

.DESCRIPTION
  1. Poly Haven (CC0) : pour chaque texture de Game/data/assets/polyhaven.json, télécharge chaque carte
     (couleur, normales, rugosité) via l'API Poly Haven, vérifie la somme MD5 et écrit les réglages
     d'import Godot (compression VRAM, mipmaps, carte de normales). Rien n'est retéléchargé si le
     fichier est déjà présent et intact.
  2. Import/ : les fichiers déposés à la main y sont déplacés vers Game/assets/import/<type>/.
  Lancer ensuite Scripts/Pipeline/importer.ps1 pour que Godot les importe.
#>
[CmdletBinding()]
param()
. "$PSScriptRoot/commun.ps1"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$entetes = @{ 'User-Agent' = 'IbnKhaldoun-pipeline (https://github.com/hazeroua/Ibn)' }

function Get-Md5([string]$Chemin) {
    return (Get-FileHash -Algorithm MD5 -Path $Chemin).Hash.ToLowerInvariant()
}

function Write-ReglagesImportTexture([string]$Chemin, [bool]$CarteDeNormales) {
    # Réglages explicites : l'import est identique sur toutes les machines, sans détection automatique.
    $normal = if ($CarteDeNormales) { 1 } else { 2 }
    $contenu = @(
        '[remap]', '', 'importer="texture"', 'type="CompressedTexture2D"', '',
        '[params]', '',
        'compress/mode=2',
        "compress/normal_map=$normal",
        'compress/high_quality=false',
        'mipmaps/generate=true',
        'detect_3d/compress_to=0'
    )
    $import = "$Chemin.import"
    if (-not (Test-Path $import)) {
        $contenu | Set-Content -Encoding ASCII $import
    }
}

# ---------------------------------------------------------------------------
# Poly Haven
# ---------------------------------------------------------------------------
Write-Etape 'Poly Haven (CC0)'
$manifeste = Get-Content -Raw -Encoding UTF8 (Join-Path $Jeu 'data/assets/polyhaven.json') | ConvertFrom-Json
foreach ($texture in $manifeste.textures) {
    if ($texture.id -notmatch '^[a-z0-9_]+$') { throw "Identifiant Poly Haven invalide : « $($texture.id) »." }
    $dossier = Join-Path $Jeu "assets/textures/polyhaven/$($texture.id)"
    New-Item -ItemType Directory -Force -Path $dossier | Out-Null
    $fichiers = $null
    foreach ($carte in $texture.maps.PSObject.Properties) {
        $nomLocal = $carte.Name
        $cleApi = $carte.Value
        $destination = Join-Path $dossier "$($texture.id)_$nomLocal.jpg"
        if ($null -eq $fichiers) {
            $fichiers = Invoke-RestMethod -Uri "https://api.polyhaven.com/files/$($texture.id)" -Headers $entetes
        }
        $entreeApi = $fichiers.$cleApi
        if ($null -eq $entreeApi) { throw "Poly Haven : carte « $cleApi » absente pour $($texture.id)." }
        $variante = $entreeApi.($texture.resolution)
        if ($null -eq $variante -or $null -eq $variante.jpg) {
            throw "Poly Haven : résolution $($texture.resolution) au format jpg absente pour $($texture.id) / $cleApi."
        }
        $md5Attendu = $variante.jpg.md5.ToLowerInvariant()
        if (-not ((Test-Path $destination) -and ((Get-Md5 $destination) -eq $md5Attendu))) {
            $partiel = "$destination.part"
            Invoke-WebRequest -Uri $variante.jpg.url -OutFile $partiel -UseBasicParsing -Headers $entetes
            if ((Get-Md5 $partiel) -ne $md5Attendu) {
                Remove-Item -Force $partiel
                throw "Poly Haven : somme MD5 incorrecte pour $($texture.id) / $cleApi."
            }
            Move-Item -Force $partiel $destination
        }
        Write-ReglagesImportTexture $destination ($nomLocal -eq 'nor_gl')
        Write-Ok "$($texture.id) / $nomLocal ($($texture.resolution))"
    }
}

# ---------------------------------------------------------------------------
# Ressources déposées à la main dans Import/
# ---------------------------------------------------------------------------
Write-Etape 'Dossier Import/'
$categories = @{
    '.png' = 'textures'; '.jpg' = 'textures'; '.jpeg' = 'textures'; '.exr' = 'textures'; '.hdr' = 'textures'; '.webp' = 'textures'
    '.glb' = 'modeles'; '.gltf' = 'modeles'; '.fbx' = 'modeles'; '.obj' = 'modeles'; '.blend' = 'modeles'
    '.wav' = 'sons'; '.ogg' = 'sons'; '.mp3' = 'sons'
    '.ttf' = 'polices'; '.otf' = 'polices'
}
$deposes = @(Get-ChildItem -Path (Join-Path $Racine 'Import') -File -Recurse | Where-Object { $_.Name -ne '.gitkeep' })
foreach ($fichier in $deposes) {
    $extension = $fichier.Extension.ToLowerInvariant()
    if (-not $categories.ContainsKey($extension)) {
        throw "Type de fichier non pris en charge dans Import/ : $($fichier.Name). Types acceptés : $(($categories.Keys | Sort-Object) -join ', ')."
    }
    $nom = ($fichier.BaseName.ToLowerInvariant() -replace '[^a-z0-9]+', '_').Trim('_') + $extension
    $cible = Join-Path $Jeu "assets/import/$($categories[$extension])"
    New-Item -ItemType Directory -Force -Path $cible | Out-Null
    $destination = Join-Path $cible $nom
    if (Test-Path $destination) { throw "Une ressource porte déjà ce nom : $destination" }
    Move-Item -Path $fichier.FullName -Destination $destination
    Write-Ok "$($fichier.Name) -> assets/import/$($categories[$extension])/$nom"
}
if ($deposes.Count -eq 0) { Write-Ok 'Aucune ressource en attente.' }

# ---------------------------------------------------------------------------
# Personnages 3D (sources libres préparées avec Blender)
# ---------------------------------------------------------------------------
& (Join-Path $PSScriptRoot 'importer-personnages.ps1')
& (Join-Path $PSScriptRoot 'generer-props-desert.ps1')
& (Join-Path $PSScriptRoot 'generer-faune.ps1')

# Sons libres (manifeste Game/data/assets/sounds.json)
& (Join-Path $PSScriptRoot 'importer-sons.ps1')
