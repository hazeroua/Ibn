<#
.SYNOPSIS
  Installe et vérifie tous les outils du projet « Les Chemins d'Ibn Khaldoun » (Windows).

.DESCRIPTION
  À lancer depuis n'importe où :
      powershell -ExecutionPolicy Bypass -File <racine du projet>\Tools\installer.ps1

  Peut être relancé sans risque : n'installe que ce qui manque.

  1. Outils système (winget) : Git, Git LFS, Python, Visual Studio Build Tools (compilateur C++), Blender.
  2. Dépendances du projet aux versions figées de Tools\versions.json (Tools\dependances.ps1) :
     Godot portable et ses modèles d'export, godot-cpp, SCons, plugins Godot.
  3. Écrit Tools\outils.json (chemins et versions) et affiche un bilan.

  Seule intervention possible : la fenêtre Windows « Autoriser cette application à apporter des
  modifications » lors de l'installation de Visual Studio Build Tools ou de Blender.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
    throw 'installer.ps1 est réservé à Windows. Sous Linux, utilisez Tools/dependances.ps1.'
}

$Tools      = $PSScriptRoot
$OutilsJson = Join-Path $Tools 'outils.json'

function Write-Etape([string]$Message) { Write-Host "`n=== $Message" -ForegroundColor Cyan }
function Write-Ok([string]$Message)    { Write-Host "  [OK] $Message" -ForegroundColor Green }
function Write-Info([string]$Message)  { Write-Host "  ... $Message" }

function Test-Commande([string]$Nom) {
    return [bool](Get-Command $Nom -ErrorAction SilentlyContinue)
}

function Invoke-Sonde {
    # Lance un programme pour en tester la présence ou l'état, sans échouer s'il écrit sur la sortie
    # d'erreur (sous Windows PowerShell 5.1, toute redirection de cette sortie déclenche sinon une erreur).
    param([Parameter(Mandatory = $true)][string]$Programme, [string[]]$Arguments = @())
    $ancien = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $sortie = @(& $Programme @Arguments 2>&1 | ForEach-Object { "$_" })
        $code = $LASTEXITCODE
    } catch {
        $sortie = @("$_")
        $code = -1
    } finally {
        $ErrorActionPreference = $ancien
    }
    return [pscustomobject]@{ Code = $code; Sortie = ($sortie -join "`n") }
}

function Update-CheminSession {
    # Recharge le PATH après une installation winget, sans redémarrer la session.
    $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $utilisateur = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = "$machine;$utilisateur"
}

function Install-Winget([string]$Id, [string[]]$Arguments = @()) {
    $deja = Invoke-Sonde 'winget' @('list', '--id', $Id, '-e', '--accept-source-agreements', '--disable-interactivity')
    if ($deja.Code -eq 0 -and $deja.Sortie -match [regex]::Escape($Id)) {
        Write-Ok "$Id déjà installé"
        return
    }
    Write-Info "Installation de $Id"
    $parametres = @('install', '--id', $Id, '-e', '--accept-source-agreements', '--accept-package-agreements', '--disable-interactivity') + $Arguments
    & winget @parametres
    if ($LASTEXITCODE -ne 0) { throw "Échec de l'installation de $Id (code $LASTEXITCODE)." }
    Update-CheminSession
    Write-Ok "$Id installé"
}

if (-not (Test-Commande 'winget')) {
    throw "winget est introuvable. Installez « App Installer » depuis le Microsoft Store, puis relancez ce script."
}

# ---------------------------------------------------------------------------
# Git et Git LFS
# ---------------------------------------------------------------------------
Write-Etape 'Git et Git LFS'
if (-not (Test-Commande 'git')) { Install-Winget 'Git.Git' }
$versionGit = (git --version | Out-String).Trim()
if ((Invoke-Sonde 'git' @('lfs', 'version')).Code -ne 0) { Install-Winget 'GitHub.GitLFS' }
& git lfs install | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'git lfs install a échoué.' }
$versionLfs = (git lfs version | Out-String).Trim()
Write-Ok "$versionGit ; $versionLfs"

# ---------------------------------------------------------------------------
# Python
# ---------------------------------------------------------------------------
Write-Etape 'Python'
$python = ''
foreach ($nom in @('python', 'py')) {
    $commande = Get-Command $nom -ErrorAction SilentlyContinue
    if ($commande) {
        if ((Invoke-Sonde $commande.Source @('--version')).Code -eq 0) { $python = $commande.Source; break }
    }
}
if (-not $python) {
    Install-Winget 'Python.Python.3.12'
    $python = (Get-Command 'python').Source
}
Write-Ok "$((& $python --version | Out-String).Trim()) ($python)"

# ---------------------------------------------------------------------------
# Compilateur C++ (MSVC)
# ---------------------------------------------------------------------------
Write-Etape 'Compilateur C++ (MSVC)'
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
function Find-Msvc {
    if (-not (Test-Path $vswhere)) { return '' }
    return (& $vswhere -latest -products '*' -requires 'Microsoft.VisualStudio.Component.VC.Tools.x86.x64' -property installationPath | Out-String).Trim()
}
$msvc = Find-Msvc
if (-not $msvc) {
    Write-Info "Installation des Build Tools : une fenêtre Windows d'autorisation va s'afficher."
    Install-Winget 'Microsoft.VisualStudio.2022.BuildTools' @('--override', '--wait --passive --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended')
    $msvc = Find-Msvc
}
if (-not $msvc) { throw 'Le compilateur MSVC est introuvable après installation.' }
Write-Ok $msvc

# ---------------------------------------------------------------------------
# Blender
# ---------------------------------------------------------------------------
Write-Etape 'Blender'
function Find-Blender {
    $racineBlender = Join-Path $env:ProgramFiles 'Blender Foundation'
    if (-not (Test-Path $racineBlender)) { return '' }
    $exe = Get-ChildItem -Path $racineBlender -Recurse -Filter 'blender.exe' -ErrorAction SilentlyContinue |
           Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($exe) { return $exe.FullName }
    return ''
}
$blender = Find-Blender
if (-not $blender) {
    Install-Winget 'BlenderFoundation.Blender'
    $blender = Find-Blender
}
if (-not $blender) { throw 'blender.exe introuvable après installation.' }
$versionBlender = ((& $blender --background --factory-startup --version | Select-String -Pattern '^Blender' | Select-Object -First 1).ToString()).Trim()
Write-Ok "$versionBlender ($blender)"

# ---------------------------------------------------------------------------
# Dépendances du projet (versions figées)
# ---------------------------------------------------------------------------
& (Join-Path $Tools 'dependances.ps1') -Python $python

# ---------------------------------------------------------------------------
# Compléments Windows dans outils.json
# ---------------------------------------------------------------------------
$outils = Get-Content -Raw -Encoding UTF8 $OutilsJson | ConvertFrom-Json
$complements = [ordered]@{
    git     = [ordered]@{ version = $versionGit; lfs = $versionLfs }
    msvc    = [ordered]@{ chemin = $msvc }
    blender = [ordered]@{ chemin = $blender; version = $versionBlender }
}
foreach ($cle in $complements.Keys) {
    $outils | Add-Member -NotePropertyName $cle -NotePropertyValue $complements[$cle] -Force
}
$outils | ConvertTo-Json -Depth 6 | Set-Content -Encoding UTF8 $OutilsJson

# ---------------------------------------------------------------------------
# Bilan
# ---------------------------------------------------------------------------
Write-Etape 'Bilan'
$bilan = @(
    [pscustomobject]@{ Outil = 'Git + LFS';  Detail = "$versionGit ; $versionLfs" }
    [pscustomobject]@{ Outil = 'MSVC';       Detail = $msvc }
    [pscustomobject]@{ Outil = 'Blender';    Detail = $versionBlender }
    [pscustomobject]@{ Outil = 'Godot';      Detail = $outils.godot.version }
    [pscustomobject]@{ Outil = 'godot-cpp';  Detail = "$($outils.godot_cpp.branche) ($($outils.godot_cpp.commit))" }
    [pscustomobject]@{ Outil = 'SCons';      Detail = $outils.scons.version }
)
$bilan | Format-Table -AutoSize | Out-String | Write-Host
Write-Host 'Tout est installé. Chemins et versions : Tools\outils.json' -ForegroundColor Green
