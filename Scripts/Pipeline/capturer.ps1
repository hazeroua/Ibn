<#
.SYNOPSIS
  Prend une capture d'écran PNG depuis chaque point de vue fixe d'une carte.

.DESCRIPTION
  Les points de vue sont dans Game/data/<carte>/viewpoints.json. Les captures sont rangées dans
  Mesures/<mvp>/<carte>/<date>/captures/ pour comparer l'évolution du jeu d'un MVP à l'autre.
#>
[CmdletBinding()]
param(
    [string]$Carte = 'sandbox',
    [int]$ImagesDeStabilisation = 30
)
. "$PSScriptRoot/commun.ps1"

$chemins = Get-CheminCarte $Carte
$sortie = Join-Path $DossierMesures "$(Get-MvpEnCours)/$Carte/$(Get-Horodatage)/captures"
Write-Etape "Captures d'écran : $Carte"
$arguments = @(
    '--path', $Jeu, '--resolution', '1920x1080', '--',
    '--mode=capture', "--scene=$($chemins.Scene)", "--viewpoints=$($chemins.PointsDeVue)",
    "--out=$sortie", "--settle-frames=$ImagesDeStabilisation"
)
$null = Invoke-Godot -Arguments $arguments -Journal (Join-Path $sortie 'captures.log')
$images = @(Get-ChildItem -Path $sortie -Filter '*.png')
if ($images.Count -eq 0) { throw "Aucune capture produite dans $sortie." }
foreach ($image in $images) { Write-Ok $image.FullName }
