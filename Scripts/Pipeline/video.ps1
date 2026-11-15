<#
.SYNOPSIS
  Enregistre une vidéo du parcours des points de vue d'une carte (mode Movie Maker de Godot).

.DESCRIPTION
  Image par image à cadence fixe : la vidéo est fluide quelle que soit la puissance de la machine.
  Sortie : Mesures/<mvp>/<carte>/<date>/video/parcours.avi (points de vue) ou parcours_joueur.avi (joueur).
.PARAMETER Parcours
  points_de_vue (par défaut) : la caméra glisse d'un point de vue à l'autre pendant -Duree secondes.
  joueur : le joueur marche le long de Game/data/<carte>/route_joueur.json, piloté par les actions
  d'entrée, filmé par la caméra de la scène ; la vidéo dure tout le parcours, ou -Duree secondes au plus
  si -Duree est donné. Un chemin res://….json désigne un autre parcours du joueur.
#>
[CmdletBinding()]
param(
    [string]$Carte = 'sandbox',
    [int]$Duree = 12,
    [int]$ImagesParSeconde = 30,
    [string]$Parcours = 'points_de_vue'
)
. "$PSScriptRoot/commun.ps1"

$chemins = Get-CheminCarte $Carte
$parcoursChoisi = Get-Parcours $Carte $Parcours
$sortie = Join-Path $DossierMesures "$(Get-MvpEnCours)/$Carte/$(Get-Horodatage)/video"
New-Item -ItemType Directory -Force -Path $sortie | Out-Null
$fichier = Join-Path $sortie "parcours$($parcoursChoisi.Suffixe).avi"
Write-Etape "Vidéo : $Carte (parcours : $($parcoursChoisi.Fichier))"
$arguments = @(
    '--path', $Jeu, '--resolution', '1920x1080',
    '--write-movie', $fichier, '--fixed-fps', "$ImagesParSeconde", '--',
    '--mode=flythrough', "--scene=$($chemins.Scene)"
)
if ($parcoursChoisi.Joueur) {
    $arguments += "--route=$($parcoursChoisi.Fichier)"
    if ($PSBoundParameters.ContainsKey('Duree')) { $arguments += "--duration=$Duree" }
} else {
    $arguments += @("--viewpoints=$($chemins.PointsDeVue)", "--duration=$Duree")
}
$null = Invoke-Godot -Arguments $arguments -Journal (Join-Path $sortie 'video.log')
if (-not (Test-Path $fichier)) { throw "Vidéo absente : $fichier" }
Write-Ok $fichier
