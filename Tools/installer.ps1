<#
.SYNOPSIS
  Installe et vérifie tous les outils du projet « Les Chemins d'Ibn Khaldoun ».

.DESCRIPTION
  À lancer depuis n'importe où :
      powershell -ExecutionPolicy Bypass -File <racine du projet>\Tools\installer.ps1

  Le script peut être relancé sans risque : il ne télécharge et n'installe que ce qui manque.
  La version de Godot est figée dans Tools\outils.json dès la première installation ;
  les lancements suivants réutilisent cette version.

  Installe ou vérifie :
    - Git et Git LFS
    - Godot 4 (version portable, dans Tools\godot\) et ses modèles d'export
    - godot-cpp (Extensions\godot-cpp), sur la branche qui correspond à la version de Godot
    - Python et SCons (compilation de l'extension C++)
    - Visual Studio Build Tools (compilateur C++ MSVC)
    - Blender
    - Les plugins Godot : Terrain3D, Dialogue Manager, GUT

  Une seule intervention possible : la fenêtre Windows « Autoriser cette application à apporter
  des modifications » lors de l'installation de Visual Studio Build Tools et de Blender.

.PARAMETER GodotTag
  Étiquette d'une version précise de Godot (ex. « 4.5.1-stable »). Par défaut : la version figée
  dans outils.json, ou à défaut la dernière version stable.
#>
[CmdletBinding()]
param(
    [string]$GodotTag = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'   # Invoke-WebRequest est beaucoup plus rapide sans barre de progression
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ---------------------------------------------------------------------------
# Chemins
# ---------------------------------------------------------------------------
$Tools      = $PSScriptRoot
$Root       = Split-Path -Parent $Tools
$Cache      = Join-Path $Tools '_telechargements'
$GodotDir   = Join-Path $Tools 'godot'
$Game       = Join-Path $Root 'Game'
$Addons     = Join-Path $Game 'addons'
$Extensions = Join-Path $Root 'Extensions'
$OutilsJson = Join-Path $Tools 'outils.json'

New-Item -ItemType Directory -Force -Path $Cache, $GodotDir, $Addons, $Extensions, (Join-Path $Root 'Import') | Out-Null

# ---------------------------------------------------------------------------
# Affichage
# ---------------------------------------------------------------------------
$Resultats = New-Object System.Collections.Generic.List[object]

function Write-Etape([string]$Message) { Write-Host "`n=== $Message" -ForegroundColor Cyan }
function Write-Ok([string]$Message)    { Write-Host "  [OK] $Message" -ForegroundColor Green }
function Write-Info([string]$Message)  { Write-Host "  ... $Message" }
function Add-Resultat([string]$Outil, [string]$Etat, [string]$Detail) {
    $Resultats.Add([pscustomobject]@{ Outil = $Outil; Etat = $Etat; Detail = $Detail })
}

# ---------------------------------------------------------------------------
# Utilitaires
# ---------------------------------------------------------------------------
function Test-Commande([string]$Nom) {
    return [bool](Get-Command $Nom -ErrorAction SilentlyContinue)
}

function Update-CheminSession {
    # Recharge le PATH après une installation winget, sans redémarrer la session.
    $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user    = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = "$machine;$user"
}

function Install-Winget([string]$Id, [string[]]$Arguments = @()) {
    $deja = (winget list --id $Id -e --accept-source-agreements 2>$null | Out-String)
    if ($deja -match [regex]::Escape($Id)) {
        Write-Ok "$Id déjà installé"
        return
    }
    Write-Info "Installation de $Id"
    $params = @('install', '--id', $Id, '-e', '--accept-source-agreements', '--accept-package-agreements') + $Arguments
    & winget @params
    if ($LASTEXITCODE -ne 0) { throw "Échec de l'installation de $Id (code $LASTEXITCODE)." }
    Update-CheminSession
    Write-Ok "$Id installé"
}

function Get-Release([string]$Depot, [string]$Tag = '') {
    $entetes = @{ 'User-Agent' = 'IbnKhaldoun-installer'; 'Accept' = 'application/vnd.github+json' }
    if ($env:GITHUB_TOKEN) { $entetes['Authorization'] = "Bearer $($env:GITHUB_TOKEN)" }
    if ($Tag) { $url = "https://api.github.com/repos/$Depot/releases/tags/$Tag" }
    else      { $url = "https://api.github.com/repos/$Depot/releases/latest" }
    return Invoke-RestMethod -Uri $url -Headers $entetes
}

function Get-Fichier([string]$Url, [string]$Destination) {
    if (Test-Path $Destination) { return $Destination }
    $partiel = "$Destination.part"
    if (Test-Path $partiel) { Remove-Item -Force $partiel }
    Write-Info "Téléchargement de $(Split-Path -Leaf $Destination)"
    Invoke-WebRequest -Uri $Url -OutFile $partiel -UseBasicParsing -Headers @{ 'User-Agent' = 'IbnKhaldoun-installer' }
    Move-Item -Force $partiel $Destination
    return $Destination
}

function Expand-Zip([string]$Archive, [string]$Destination) {
    # Expand-Archive (PowerShell 5.1) n'accepte que l'extension .zip.
    $zip = $Archive
    if ([IO.Path]::GetExtension($Archive) -ne '.zip') {
        $zip = "$Archive.zip"
        if (-not (Test-Path $zip)) { Copy-Item -Force $Archive $zip }
    }
    if (Test-Path $Destination) { Remove-Item -Recurse -Force $Destination }
    Expand-Archive -Path $zip -DestinationPath $Destination -Force
}

function Read-Outils {
    if (Test-Path $OutilsJson) { return (Get-Content -Raw -Encoding UTF8 $OutilsJson | ConvertFrom-Json) }
    return $null
}

# ---------------------------------------------------------------------------
# 0. Pré-requis
# ---------------------------------------------------------------------------
Write-Etape 'Pré-requis'
if (-not (Test-Commande 'winget')) {
    throw "winget est introuvable. Installez « App Installer » depuis le Microsoft Store, puis relancez ce script."
}
Write-Ok 'winget disponible'
$outilsExistants = Read-Outils

# ---------------------------------------------------------------------------
# 1. Git et Git LFS
# ---------------------------------------------------------------------------
Write-Etape 'Git et Git LFS'
if (-not (Test-Commande 'git')) { Install-Winget 'Git.Git' }
$gitVersion = (git --version).Trim()
Write-Ok $gitVersion

& git lfs version *> $null
if ($LASTEXITCODE -ne 0) { Install-Winget 'GitHub.GitLFS' }
& git lfs install | Out-Null
$lfsVersion = (git lfs version).Trim()
Write-Ok $lfsVersion
Add-Resultat 'Git + Git LFS' 'OK' "$gitVersion ; $lfsVersion"

if (-not (Test-Path (Join-Path $Root '.git'))) {
    Push-Location $Root
    & git init -b main | Out-Null
    Pop-Location
    Write-Ok 'Dépôt Git initialisé'
}

# ---------------------------------------------------------------------------
# 2. Godot 4 (portable) et modèles d'export
# ---------------------------------------------------------------------------
Write-Etape 'Godot 4'
if (-not $GodotTag -and $outilsExistants -and $outilsExistants.godot.tag) {
    $GodotTag = $outilsExistants.godot.tag
    Write-Info "Version figée dans outils.json : $GodotTag"
}
$release = Get-Release 'godotengine/godot' $GodotTag
$GodotTag = $release.tag_name
if ($GodotTag -notmatch '^(\d+)\.(\d+)(\.(\d+))?-stable$') {
    throw "La version $GodotTag n'est pas une version stable de Godot."
}
$godotMajeure = [int]$Matches[1]
$godotMineure = [int]$Matches[2]
if ($godotMajeure -ne 4) { throw "Le projet exige Godot 4 (version trouvée : $GodotTag)." }

$assetEditeur = $release.assets | Where-Object { $_.name -match '^Godot_v.+-stable_win64\.exe\.zip$' } | Select-Object -First 1
$assetModeles = $release.assets | Where-Object { $_.name -match '^Godot_v.+-stable_export_templates\.tpz$' } | Select-Object -First 1
if (-not $assetEditeur) { throw "Archive Windows de Godot introuvable dans la version $GodotTag." }
if (-not $assetModeles) { throw "Modèles d'export introuvables dans la version $GodotTag." }

$dossierVersion = Join-Path $GodotDir $GodotTag
$godotExe = Get-ChildItem -Path $dossierVersion -Filter 'Godot_v*_win64.exe' -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -notmatch 'console' } | Select-Object -First 1
if (-not $godotExe) {
    $archive = Get-Fichier $assetEditeur.browser_download_url (Join-Path $Cache $assetEditeur.name)
    Expand-Zip $archive $dossierVersion
    $godotExe = Get-ChildItem -Path $dossierVersion -Recurse -Filter 'Godot_v*_win64.exe' |
                Where-Object { $_.Name -notmatch 'console' } | Select-Object -First 1
}
$godotConsole = Get-ChildItem -Path $dossierVersion -Recurse -Filter 'Godot_v*_win64_console.exe' | Select-Object -First 1
if (-not $godotExe -or -not $godotConsole) { throw "Exécutables Godot introuvables après extraction." }
$godotVersionTexte = (& $godotConsole.FullName --version | Out-String).Trim()
Write-Ok "Godot $godotVersionTexte"

# Modèles d'export : %APPDATA%\Godot\export_templates\<version>
$archiveModeles = Get-Fichier $assetModeles.browser_download_url (Join-Path $Cache $assetModeles.name)
$extraction = Join-Path $Cache 'export_templates'
Expand-Zip $archiveModeles $extraction
$versionTxt = Join-Path $extraction 'templates\version.txt'
if (-not (Test-Path $versionTxt)) { throw "version.txt absent des modèles d'export." }
$versionModeles = (Get-Content -Raw $versionTxt).Trim()
$cibleModeles = Join-Path $env:APPDATA "Godot\export_templates\$versionModeles"
if (-not (Test-Path (Join-Path $cibleModeles 'version.txt'))) {
    New-Item -ItemType Directory -Force -Path $cibleModeles | Out-Null
    Copy-Item -Recurse -Force (Join-Path $extraction 'templates\*') $cibleModeles
}
Remove-Item -Recurse -Force $extraction
Write-Ok "Modèles d'export $versionModeles installés"
Add-Resultat 'Godot' 'OK' "$godotVersionTexte (modèles d'export $versionModeles)"

# ---------------------------------------------------------------------------
# 3. godot-cpp
# ---------------------------------------------------------------------------
Write-Etape 'godot-cpp'
$brancheCpp = "$godotMajeure.$godotMineure"
$depotCpp = 'https://github.com/godotengine/godot-cpp.git'
$dossierCpp = Join-Path $Extensions 'godot-cpp'
$brancheExiste = (git ls-remote --heads $depotCpp $brancheCpp | Out-String).Trim()
if (-not $brancheExiste) {
    throw "Aucune branche godot-cpp « $brancheCpp » pour Godot $GodotTag. Choisissez une version de Godot prise en charge par godot-cpp (paramètre -GodotTag)."
}
if (-not (Test-Path (Join-Path $dossierCpp '.git'))) {
    & git clone --branch $brancheCpp --single-branch --recurse-submodules $depotCpp $dossierCpp
    if ($LASTEXITCODE -ne 0) { throw 'Échec du clonage de godot-cpp.' }
} else {
    Push-Location $dossierCpp
    & git fetch origin $brancheCpp
    & git checkout $brancheCpp
    & git pull --ff-only origin $brancheCpp
    Pop-Location
}
$commitCpp = (git -C $dossierCpp rev-parse --short HEAD).Trim()
Write-Ok "godot-cpp $brancheCpp ($commitCpp)"
Add-Resultat 'godot-cpp' 'OK' "branche $brancheCpp, commit $commitCpp"

# ---------------------------------------------------------------------------
# 4. Python et SCons
# ---------------------------------------------------------------------------
Write-Etape 'Python et SCons'
$python = $null
foreach ($candidat in @('python', 'py')) {
    if (Test-Commande $candidat) {
        & $candidat --version *> $null
        if ($LASTEXITCODE -eq 0) { $python = (Get-Command $candidat).Source; break }
    }
}
if (-not $python) {
    Install-Winget 'Python.Python.3.12'
    $python = (Get-Command 'python').Source
}
& $python -m pip install --upgrade --user scons
if ($LASTEXITCODE -ne 0) { throw "Échec de l'installation de SCons." }
$pythonVersion = (& $python --version | Out-String).Trim()
$sconsVersion = ((& $python -m SCons --version | Select-String 'SCons: v' | Select-Object -First 1).ToString()).Trim()
Write-Ok "$pythonVersion ; $sconsVersion"
Add-Resultat 'Python + SCons' 'OK' "$pythonVersion ; $sconsVersion"

# ---------------------------------------------------------------------------
# 5. Visual Studio Build Tools (MSVC)
# ---------------------------------------------------------------------------
Write-Etape 'Compilateur C++ (Visual Studio Build Tools)'
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
function Find-Msvc {
    if (-not (Test-Path $vswhere)) { return $null }
    $chemin = (& $vswhere -latest -products '*' -requires 'Microsoft.VisualStudio.Component.VC.Tools.x86.x64' -property installationPath | Out-String).Trim()
    if ($chemin) { return $chemin }
    return $null
}
$msvc = Find-Msvc
if (-not $msvc) {
    Write-Info "Installation des Build Tools : une fenêtre Windows d'autorisation va s'afficher."
    Install-Winget 'Microsoft.VisualStudio.2022.BuildTools' @('--override', '--wait --passive --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended')
    $msvc = Find-Msvc
}
if (-not $msvc) { throw "Le compilateur MSVC est introuvable après installation." }
Write-Ok "MSVC : $msvc"
Add-Resultat 'Visual Studio Build Tools' 'OK' $msvc

# ---------------------------------------------------------------------------
# 6. Blender
# ---------------------------------------------------------------------------
Write-Etape 'Blender'
function Find-Blender {
    $racine = Join-Path $env:ProgramFiles 'Blender Foundation'
    if (-not (Test-Path $racine)) { return $null }
    $exe = Get-ChildItem -Path $racine -Recurse -Filter 'blender.exe' -ErrorAction SilentlyContinue |
           Sort-Object LastWriteTime -Descending |
           Select-Object -First 1
    if ($exe) { return $exe.FullName }
    return $null
}
$blender = Find-Blender
if (-not $blender) {
    Install-Winget 'BlenderFoundation.Blender'
    $blender = Find-Blender
}
if (-not $blender) { throw 'blender.exe introuvable après installation.' }
$blenderVersion = ((& $blender --background --version | Select-String '^Blender' | Select-Object -First 1).ToString()).Trim()
Write-Ok $blenderVersion
Add-Resultat 'Blender' 'OK' "$blenderVersion ($blender)"

# ---------------------------------------------------------------------------
# 7. Plugins Godot
# ---------------------------------------------------------------------------
Write-Etape 'Plugins Godot'
function Install-Addon([string]$Depot, [string]$NomDossier, [bool]$ExigerBinaires) {
    $rel = Get-Release $Depot
    $asset = $rel.assets | Where-Object { $_.name -match '\.zip$' } | Select-Object -First 1
    if ($asset) {
        $url = $asset.browser_download_url
        $nomArchive = $asset.name
    } elseif ($ExigerBinaires) {
        throw "$Depot : aucune archive compilée dans la version $($rel.tag_name)."
    } else {
        $url = $rel.zipball_url
        $nomArchive = "$($Depot -replace '/', '_')_$($rel.tag_name).zip"
    }
    $archive = Get-Fichier $url (Join-Path $Cache $nomArchive)
    $extraction = Join-Path $Cache "extrait_$NomDossier"
    Expand-Zip $archive $extraction
    $source = Get-ChildItem -Path $extraction -Recurse -Directory -Filter $NomDossier |
              Where-Object { $_.Parent.Name -eq 'addons' } | Select-Object -First 1
    if (-not $source) { throw "$Depot : dossier addons\$NomDossier introuvable dans l'archive." }
    $cible = Join-Path $Addons $NomDossier
    if (Test-Path $cible) { Remove-Item -Recurse -Force $cible }
    Copy-Item -Recurse -Force $source.FullName $cible
    Remove-Item -Recurse -Force $extraction
    Write-Ok "$NomDossier $($rel.tag_name)"
    return $rel.tag_name
}
$versionTerrain = Install-Addon 'TokisanGames/Terrain3D' 'terrain_3d' $true
$versionDialogue = Install-Addon 'nathanhoad/godot_dialogue_manager' 'dialogue_manager' $false
$versionGut = Install-Addon 'bitwes/Gut' 'gut' $false
Add-Resultat 'Plugins' 'OK' "Terrain3D $versionTerrain ; Dialogue Manager $versionDialogue ; GUT $versionGut"

# ---------------------------------------------------------------------------
# 8. outils.json
# ---------------------------------------------------------------------------
Write-Etape 'Enregistrement de outils.json'
$outils = [ordered]@{
    genere_le     = (Get-Date).ToString('s')
    godot         = [ordered]@{
        tag               = $GodotTag
        version           = $godotVersionTexte
        editeur           = $godotExe.FullName
        console           = $godotConsole.FullName
        modeles_export    = $cibleModeles
    }
    godot_cpp     = [ordered]@{ chemin = $dossierCpp; branche = $brancheCpp; commit = $commitCpp }
    python        = [ordered]@{ chemin = $python; version = $pythonVersion }
    scons         = [ordered]@{ commande = "`"$python`" -m SCons"; version = $sconsVersion }
    msvc          = [ordered]@{ chemin = $msvc }
    blender       = [ordered]@{ chemin = $blender; version = $blenderVersion }
    git           = [ordered]@{ version = $gitVersion; lfs = $lfsVersion }
    plugins       = [ordered]@{ terrain_3d = $versionTerrain; dialogue_manager = $versionDialogue; gut = $versionGut }
}
$outils | ConvertTo-Json -Depth 5 | Set-Content -Encoding UTF8 $OutilsJson
Write-Ok $OutilsJson

# ---------------------------------------------------------------------------
# Bilan
# ---------------------------------------------------------------------------
Write-Etape 'Bilan'
$Resultats | Format-Table -AutoSize | Out-String | Write-Host
Write-Host "Tout est installé. Les chemins des outils sont dans Tools\outils.json." -ForegroundColor Green
Write-Host "Attention : vérifier que les plugins (Terrain3D, Dialogue Manager, GUT) sont compatibles avec $GodotTag au premier lancement du projet." -ForegroundColor Yellow
