<#
.SYNOPSIS
  Captures de contrôle de la médina générée (silhouette depuis le désert, porte, passage couvert,
  ruelle étroite, place, vue de dessus).

.DESCRIPTION
  Points de vue tirés du plan généré (Game/data/tunis/generation/medina_layout.json). Les images sont
  rangées dans Mesures/<mvp>/tunis/<date>/medina/.
#>
[CmdletBinding()]
param()
. "$PSScriptRoot/commun.ps1"

$sortie = Join-Path $DossierMesures "$(Get-MvpEnCours)/tunis/$(Get-Horodatage)/medina"
Write-Etape 'Captures de la médina'
$arguments = @('--path', $Jeu, '--resolution', '1920x1080', '--script', 'res://tools/medina/capture_medina.gd', '--', "--out=$sortie")
$null = Invoke-Godot -Arguments $arguments -Journal (Join-Path $sortie 'captures.log')
$images = @(Get-ChildItem -Path $sortie -Filter '*.png')
if ($images.Count -eq 0) { throw "Aucune capture produite dans $sortie." }
foreach ($image in $images) { Write-Ok $image.FullName }
