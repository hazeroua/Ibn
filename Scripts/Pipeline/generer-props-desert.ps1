<#
.SYNOPSIS
  Regenere les modeles du desert (rochers, palmiers, imposteur) avec Blender en ligne de commande.
#>
param([string]$Blender = "blender")
$ErrorActionPreference = "Stop"
$racine = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
& $Blender --background --factory-startup --python (Join-Path $racine "Scripts/Blender/generer_props_desert.py") -- --manifest (Join-Path $racine "Game/data/assets/desert_props.json") --output-dir (Join-Path $racine "Game/assets/desert")
if ($LASTEXITCODE -ne 0) { throw "La generation des modeles du desert a echoue." }
