<#
.SYNOPSIS
  Construit les scènes générées à partir de leurs scripts (Game/tools/builders/build_<nom>.gd).
.PARAMETER Constructeur
  Nom du constructeur (ex. « sandbox »). Par défaut : tous les constructeurs.
#>
[CmdletBinding()]
param([string]$Constructeur = '')
. "$PSScriptRoot/commun.ps1"

$dossier = Join-Path $Jeu 'tools/builders'
if ($Constructeur) {
    if ($Constructeur -notmatch '^[a-z0-9_]+$') { throw "Nom de constructeur invalide : « $Constructeur »." }
    $scripts = @(Get-Item (Join-Path $dossier "build_$Constructeur.gd"))
} else {
    $scripts = @(Get-ChildItem -Path $dossier -Filter 'build_*.gd' | Sort-Object Name)
}
if ($scripts.Count -eq 0) { throw "Aucun constructeur trouvé dans $dossier." }

foreach ($script in $scripts) {
    Write-Etape "Construction : $($script.BaseName)"
    $null = Invoke-Godot -Arguments @('--headless', '--path', $Jeu, '--script', "res://tools/builders/$($script.Name)") `
        -Journal (Join-Path $DossierMesures "journaux/$($script.BaseName).log")
    Write-Ok $script.BaseName
}
