param()
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/commun.ps1"
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$blender = $Script:Outils.blender.chemin
if (-not (Test-Path $blender)) { throw 'Blender introuvable : relancez Tools/installer.ps1.' }
$report = Join-Path $root 'Mesures/tunis/architecture.json'
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $report) | Out-Null
& $blender --background --factory-startup --python-exit-code 1 --python (Join-Path $root 'Scripts/Blender/generer_architecture_tunis.py') -- --manifest (Join-Path $root 'Game/data/assets/tunis_architecture.json') --output-dir (Join-Path $root 'Game/assets/tunis') --report $report
if ($LASTEXITCODE -ne 0) { throw 'La génération de l’architecture de Tunis a échoué.' }
