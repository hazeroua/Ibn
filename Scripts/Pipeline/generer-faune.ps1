<#
.SYNOPSIS
  Régénère les modèles de la faune d'ambiance du désert (oiseaux, gazelle, libellule) avec Blender en ligne de commande.
  Blender est cherché dans Tools/outils.json (écrit par Tools/installer.ps1), sinon dans le PATH.
  Appelé par importer-ressources.ps1 et lancer.ps1 ; les fichiers produits ne sont pas versionnés.
#>
param([string]$Blender = '')
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/commun.ps1"
$racine = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

if (-not $Blender) {
    $propriete = $Script:Outils.PSObject.Properties['blender']
    if ($propriete -and $propriete.Value -and $propriete.Value.chemin -and (Test-Path $propriete.Value.chemin)) {
        $Blender = $propriete.Value.chemin
    } else {
        $commande = Get-Command 'blender' -ErrorAction SilentlyContinue
        if (-not $commande) { throw 'Blender introuvable : relancez Tools/installer.ps1 (Windows) ou installez le paquet « blender » (Linux).' }
        $Blender = $commande.Source
    }
}

& $Blender --background --factory-startup --python (Join-Path $racine 'Scripts/Blender/generer_faune.py') -- --manifest (Join-Path $racine 'Game/data/assets/fauna_models.json') --output-dir (Join-Path $racine 'Game/assets/faune')
if ($LASTEXITCODE -ne 0) { throw 'La génération des modèles de la faune a échoué.' }
