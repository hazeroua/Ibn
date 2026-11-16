<#
.SYNOPSIS
  Régénère les modèles du désert (rochers, falaises, végétation texturée et imposteurs) et l'atlas peint de la
  végétation (foliage_atlas.dds) avec Blender en ligne de commande.
  Blender est cherché dans Tools/outils.json (écrit par Tools/installer.ps1), sinon dans le PATH.
  Appelé par importer-ressources.ps1 ; les fichiers produits ne sont pas versionnés.
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

# --python-exit-code : une erreur du script (budget dépassé, exception) fait échouer Blender, donc ce script.
& $Blender --background --factory-startup --python-exit-code 1 --python (Join-Path $racine 'Scripts/Blender/generer_props_desert.py') -- --manifest (Join-Path $racine 'Game/data/assets/desert_props.json') --output-dir (Join-Path $racine 'Game/assets/desert')
if ($LASTEXITCODE -ne 0) { throw 'La génération des modèles du désert a échoué.' }
