<#
.SYNOPSIS
  Installe et vérifie les outils du projet sous macOS Apple silicon.

.DESCRIPTION
  Utilise Homebrew pour les outils système manquants, puis le même fichier de versions et le même
  pipeline PowerShell que Windows. Peut être relancé sans réinstaller ce qui est déjà disponible.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$estMacOS = [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(
    [System.Runtime.InteropServices.OSPlatform]::OSX
)
if (-not $estMacOS) { throw 'installer-macos.ps1 est réservé à macOS.' }
if ([System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture -ne [System.Runtime.InteropServices.Architecture]::Arm64) {
    throw 'Cette adaptation cible macOS Apple silicon (arm64).'
}

$tools = $PSScriptRoot
$racine = Split-Path -Parent $tools
$outilsJson = Join-Path $tools 'outils.json'

function Write-Etape([string]$Message) { Write-Host "`n=== $Message" -ForegroundColor Cyan }
function Write-Ok([string]$Message) { Write-Host "  [OK] $Message" -ForegroundColor Green }

$brew = Get-Command 'brew' -ErrorAction SilentlyContinue
if (-not $brew) { throw 'Homebrew est requis. Installez-le depuis https://brew.sh puis relancez Tools/installer-macos.command.' }

function Install-Formule([string]$Nom, [string]$Commande) {
    if (Get-Command $Commande -ErrorAction SilentlyContinue) { return }
    & $brew.Source install $Nom
    if ($LASTEXITCODE -ne 0) { throw "Échec de l'installation Homebrew de $Nom." }
}

Write-Etape 'Outils système'
if (-not (Get-Command 'clang++' -ErrorAction SilentlyContinue)) {
    & xcode-select --install
    throw 'Installation des Command Line Tools demandée. Terminez-la puis relancez cet installateur.'
}
Install-Formule 'git-lfs' 'git-lfs'
Install-Formule 'python@3.12' 'python3.12'
& git lfs install
if ($LASTEXITCODE -ne 0) { throw 'git lfs install a échoué.' }
Write-Ok "$(git --version) ; $(git lfs version)"

$python = (Get-Command 'python3.12' -ErrorAction SilentlyContinue).Source
if (-not $python) {
    $prefixePython = (& $brew.Source --prefix 'python@3.12' | Out-String).Trim()
    $python = Join-Path $prefixePython 'bin/python3.12'
}
if (-not (Test-Path $python)) { throw 'Python 3.12 est introuvable après installation.' }
Write-Ok "$(& $python --version) ($python)"

Write-Etape 'Blender'
$candidatsBlender = @(
    (Join-Path $tools 'blender/Blender.app/Contents/MacOS/Blender'),
    '/Applications/Blender.app/Contents/MacOS/Blender'
)
$blender = @($candidatsBlender | Where-Object { Test-Path $_ } | Select-Object -First 1)
if ($blender.Count -eq 0) {
    & $brew.Source install --cask blender
    if ($LASTEXITCODE -ne 0) { throw "Échec de l'installation Homebrew de Blender." }
    $blender = @('/Applications/Blender.app/Contents/MacOS/Blender')
}
$cheminBlender = $blender[0]
$versionBlender = ((& $cheminBlender --background --factory-startup --disable-autoexec --version | Select-String '^Blender' | Select-Object -First 1).ToString()).Trim()
Write-Ok "$versionBlender ($cheminBlender)"

Write-Etape 'Dépendances du projet'
& (Join-Path $tools 'dependances.ps1') -Python $python

$outils = Get-Content -Raw -Encoding UTF8 $outilsJson | ConvertFrom-Json
$outils | Add-Member -NotePropertyName 'git' -NotePropertyValue ([ordered]@{
    version = (git --version | Out-String).Trim()
    lfs = (git lfs version | Out-String).Trim()
}) -Force
$outils | Add-Member -NotePropertyName 'blender' -NotePropertyValue ([ordered]@{
    chemin = $cheminBlender
    version = $versionBlender
}) -Force
$outils | ConvertTo-Json -Depth 6 | Set-Content -Encoding UTF8 $outilsJson

Write-Etape 'Bilan'
Write-Ok 'macOS Apple silicon prêt.'
Write-Host 'Lancez le jeu avec ./lancer.command' -ForegroundColor Green
