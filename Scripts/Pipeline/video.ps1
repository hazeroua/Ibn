<#
.SYNOPSIS
  Enregistre une vidéo du parcours des points de vue d'une carte (mode Movie Maker de Godot).

.DESCRIPTION
  Image par image à cadence fixe : la vidéo est fluide quelle que soit la puissance de la machine.
  Sortie : Mesures/<mvp>/<carte>/<date>/video/parcours.avi
#>
[CmdletBinding()]
param(
    [string]$Carte = 'sandbox',
    [int]$Duree = 12,
    [int]$ImagesParSeconde = 30
)
. "$PSScriptRoot/commun.ps1"

$chemins = Get-CheminCarte $Carte
$sortie = Join-Path $DossierMesures "$(Get-MvpEnCours)/$Carte/$(Get-Horodatage)/video"
New-Item -ItemType Directory -Force -Path $sortie | Out-Null
$fichier = Join-Path $sortie 'parcours.avi'
Write-Etape "Vidéo : $Carte"
$arguments = @(
    '--path', $Jeu, '--resolution', '1920x1080',
    '--write-movie', $fichier, '--fixed-fps', "$ImagesParSeconde", '--',
    '--mode=flythrough', "--scene=$($chemins.Scene)", "--viewpoints=$($chemins.PointsDeVue)", "--duration=$Duree"
)
$null = Invoke-Godot -Arguments $arguments -Journal (Join-Path $sortie 'video.log')
if (-not (Test-Path $fichier)) { throw "Vidéo absente : $fichier" }
Write-Ok $fichier
