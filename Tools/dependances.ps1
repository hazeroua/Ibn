<#
.SYNOPSIS
  Télécharge et installe les dépendances du projet aux versions figées de Tools/versions.json.

.DESCRIPTION
  Fonctionne sous Windows (PowerShell 5.1 ou 7), macOS Apple silicon et Linux (PowerShell 7, utilisé par la CI).
  Peut être relancé sans risque : ne télécharge que ce qui manque.

  Installe :
    - Godot (version portable) dans Tools/godot/<tag>/
    - les modèles d'export de Godot (sauf avec -SansModelesExport)
    - godot-cpp dans Extensions/godot-cpp (branche figée)
    - un environnement Python dédié (Tools/venv) avec SCons à la version figée
    - les plugins Godot dans Game/addons/

  Écrit Tools/outils.json (chemins et versions réellement installés).
  Sous Windows, ce script est appelé par Tools/installer.ps1, qui installe d'abord les outils système.

.PARAMETER SansModelesExport
  Ne pas installer les modèles d'export (environ 1 Go), inutiles quand on n'exporte pas.

.PARAMETER Python
  Chemin de l'interpréteur Python à utiliser pour créer Tools/venv. Par défaut : détection automatique.
#>
[CmdletBinding()]
param(
    [switch]$SansModelesExport,
    [string]$Python = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$EstWindows = [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT
$EstMacOS = [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(
    [System.Runtime.InteropServices.OSPlatform]::OSX
)

$Tools      = $PSScriptRoot
$Racine     = Split-Path -Parent $Tools
$Cache      = Join-Path $Tools '_telechargements'
$Jeu        = Join-Path $Racine 'Game'
$Addons     = Join-Path $Jeu 'addons'
$Extensions = Join-Path $Racine 'Extensions'
$OutilsJson = Join-Path $Tools 'outils.json'
$Versions   = Get-Content -Raw -Encoding UTF8 (Join-Path $Tools 'versions.json') | ConvertFrom-Json

New-Item -ItemType Directory -Force -Path $Cache, $Addons, $Extensions | Out-Null

function Write-Etape([string]$Message) { Write-Host "`n=== $Message" -ForegroundColor Cyan }
function Write-Ok([string]$Message)    { Write-Host "  [OK] $Message" -ForegroundColor Green }
function Write-Info([string]$Message)  { Write-Host "  ... $Message" }

function Invoke-Externe {
    # Lance un programme externe et échoue si son code de sortie n'est pas nul.
    param([Parameter(Mandatory = $true)][string]$Programme, [string[]]$Arguments = @())
    & $Programme @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Échec de « $Programme $($Arguments -join ' ') » (code $LASTEXITCODE)." }
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

function Get-Fichier([string]$Url, [string]$Destination) {
    if (Test-Path $Destination) { return }
    $partiel = "$Destination.part"
    if (Test-Path $partiel) { Remove-Item -Force $partiel }
    Write-Info "Téléchargement de $(Split-Path -Leaf $Destination)"
    $entetes = @{ 'User-Agent' = 'IbnKhaldoun-dependances' }
    Invoke-WebRequest -Uri $Url -OutFile $partiel -UseBasicParsing -Headers $entetes
    Move-Item -Force $partiel $Destination
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

function Assert-Sha256([string]$Fichier, [string]$Attendu) {
    $reel = (Get-FileHash -Algorithm SHA256 -LiteralPath $Fichier).Hash.ToLowerInvariant()
    if ($reel -ne $Attendu.ToLowerInvariant()) {
        throw "SHA-256 invalide pour $(Split-Path -Leaf $Fichier) : $reel au lieu de $Attendu."
    }
}

function Find-Python {
    if ($Python) { return $Python }
    $candidats = if ($EstWindows) { @('python', 'py') } else { @('python3', 'python') }
    foreach ($nom in $candidats) {
        $commande = Get-Command $nom -ErrorAction SilentlyContinue
        if ($commande) {
            if ((Invoke-Sonde $commande.Source @('--version')).Code -eq 0) { return $commande.Source }
        }
    }
    throw 'Python introuvable. Lancez Tools/installer.ps1 sous Windows ou Tools/installer-macos.command sous macOS ; sous Linux, installez python3 et python3-venv.'
}

# ---------------------------------------------------------------------------
# Godot
# ---------------------------------------------------------------------------
Write-Etape "Godot $($Versions.godot.tag)"
$dossierGodot = Join-Path $Tools "godot/$($Versions.godot.tag)"
$archiveGodot = if ($EstWindows) {
    $Versions.godot.archive_windows
} elseif ($EstMacOS) {
    $Versions.godot.archive_macos
} else {
    $Versions.godot.archive_linux
}
if ($EstWindows) {
    $nomEditeur = $archiveGodot -replace '\.zip$', ''
    $nomConsole = $nomEditeur -replace '\.exe$', '_console.exe'
    $godotEditeur = Join-Path $dossierGodot $nomEditeur
    $godotConsole = Join-Path $dossierGodot $nomConsole
} elseif ($EstMacOS) {
    $godotEditeur = Join-Path $dossierGodot 'Godot.app/Contents/MacOS/Godot'
    $godotConsole = $godotEditeur
} else {
    $nomEditeur = $archiveGodot -replace '\.zip$', ''
    $nomConsole = $nomEditeur
    $godotEditeur = Join-Path $dossierGodot $nomEditeur
    $godotConsole = Join-Path $dossierGodot $nomConsole
}
if (-not ((Test-Path $godotEditeur) -and (Test-Path $godotConsole))) {
    $archive = Join-Path $Cache $archiveGodot
    Get-Fichier "$($Versions.godot.url_base)/$archiveGodot" $archive
    if ($EstMacOS) {
        try {
            Assert-Sha256 $archive $Versions.godot.sha256_macos
        } catch {
            Write-Info 'Archive Godot macOS invalide dans le cache, nouveau téléchargement.'
            Remove-Item -Force $archive
            Get-Fichier "$($Versions.godot.url_base)/$archiveGodot" $archive
            Assert-Sha256 $archive $Versions.godot.sha256_macos
        }
    }
    Expand-Zip $archive $dossierGodot
    if (-not $EstWindows) { Invoke-Externe 'chmod' @('+x', $godotEditeur) }
}
if (-not ((Test-Path $godotEditeur) -and (Test-Path $godotConsole))) {
    throw "Exécutables Godot introuvables dans $dossierGodot."
}
$versionGodot = (& $godotConsole --version | Out-String).Trim()
if ($LASTEXITCODE -ne 0) { throw 'Godot ne démarre pas (godot --version a échoué).' }
Write-Ok "Godot $versionGodot"

# ---------------------------------------------------------------------------
# Modèles d'export
# ---------------------------------------------------------------------------
$dossierModeles = ''
if (-not $SansModelesExport) {
    Write-Etape "Modèles d'export $($Versions.godot.version_modeles_export)"
    if ($EstWindows) {
        $dossierModeles = Join-Path $env:APPDATA "Godot/export_templates/$($Versions.godot.version_modeles_export)"
    } elseif ($EstMacOS) {
        $profil = [Environment]::GetFolderPath('UserProfile')
        $dossierModeles = Join-Path $profil "Library/Application Support/Godot/export_templates/$($Versions.godot.version_modeles_export)"
    } else {
        $profil = [Environment]::GetFolderPath('UserProfile')
        $donnees = if ($env:XDG_DATA_HOME) { $env:XDG_DATA_HOME } else { Join-Path $profil '.local/share' }
        $dossierModeles = Join-Path $donnees "godot/export_templates/$($Versions.godot.version_modeles_export)"
    }
    if (-not (Test-Path (Join-Path $dossierModeles 'version.txt'))) {
        $archive = Join-Path $Cache $Versions.godot.modeles_export
        Get-Fichier "$($Versions.godot.url_base)/$($Versions.godot.modeles_export)" $archive
        $extraction = Join-Path $Cache 'export_templates'
        Expand-Zip $archive $extraction
        $versionTxt = Join-Path $extraction 'templates/version.txt'
        if (-not (Test-Path $versionTxt)) { throw "version.txt absent des modèles d'export." }
        $versionLue = (Get-Content -Raw $versionTxt).Trim()
        if ($versionLue -ne $Versions.godot.version_modeles_export) {
            throw "Modèles d'export inattendus : $versionLue au lieu de $($Versions.godot.version_modeles_export)."
        }
        New-Item -ItemType Directory -Force -Path $dossierModeles | Out-Null
        Copy-Item -Recurse -Force (Join-Path $extraction 'templates/*') $dossierModeles
        Remove-Item -Recurse -Force $extraction
    }
    Write-Ok $dossierModeles
}

# ---------------------------------------------------------------------------
# godot-cpp
# ---------------------------------------------------------------------------
Write-Etape "godot-cpp (branche $($Versions.godot_cpp.branche))"
$dossierCpp = Join-Path $Extensions 'godot-cpp'
$branche = $Versions.godot_cpp.branche
if (-not (Test-Path (Join-Path $dossierCpp '.git'))) {
    if (Test-Path $dossierCpp) { Remove-Item -Recurse -Force $dossierCpp }
    Invoke-Externe 'git' @('clone', '--branch', $branche, '--single-branch', '--depth', '1', '--recurse-submodules', '--shallow-submodules', $Versions.godot_cpp.depot, $dossierCpp)
} else {
    $brancheActuelle = (& git -C $dossierCpp rev-parse --abbrev-ref HEAD | Out-String).Trim()
    if ($brancheActuelle -ne $branche) {
        throw "Extensions/godot-cpp est sur la branche « $brancheActuelle » au lieu de « $branche ». Supprimez le dossier puis relancez."
    }
}
$commitCpp = (& git -C $dossierCpp rev-parse HEAD | Out-String).Trim()
Write-Ok "godot-cpp $branche ($commitCpp)"

# ---------------------------------------------------------------------------
# Python (environnement dédié) et SCons
# ---------------------------------------------------------------------------
Write-Etape "SCons $($Versions.scons.version)"
$venv = Join-Path $Tools 'venv'
$pythonVenv = if ($EstWindows) { Join-Path $venv 'Scripts/python.exe' } else { Join-Path $venv 'bin/python' }
if (-not (Test-Path $pythonVenv)) {
    $pythonSysteme = Find-Python
    Invoke-Externe $pythonSysteme @('-m', 'venv', $venv)
}
$versionScons = ''
$sondeScons = Invoke-Sonde $pythonVenv @('-m', 'SCons', '--version')
if ($sondeScons.Code -eq 0 -and $sondeScons.Sortie -match 'SCons: v(\S+)') {
    $versionScons = $Matches[1]
}
if (-not $versionScons.StartsWith($Versions.scons.version)) {
    Invoke-Externe $pythonVenv @('-m', 'pip', 'install', '--disable-pip-version-check', '--quiet', "scons==$($Versions.scons.version)")
    $versionScons = ((& $pythonVenv -m SCons --version | Select-String -Pattern 'SCons: v(\S+)' | Select-Object -First 1).Matches[0].Groups[1].Value)
}
$versionPython = (& $pythonVenv --version | Out-String).Trim()
Write-Ok "$versionPython ; SCons $versionScons"

Write-Etape "gdtoolkit $($Versions.gdtoolkit.version)"
$versionGdtoolkit = ''
$sondeGdtoolkit = Invoke-Sonde $pythonVenv @('-m', 'pip', 'show', 'gdtoolkit')
if ($sondeGdtoolkit.Code -eq 0 -and $sondeGdtoolkit.Sortie -match '(?m)^Version: (\S+)') {
    $versionGdtoolkit = $Matches[1]
}
if ($versionGdtoolkit -ne $Versions.gdtoolkit.version) {
    Invoke-Externe $pythonVenv @('-m', 'pip', 'install', '--disable-pip-version-check', '--quiet', "gdtoolkit==$($Versions.gdtoolkit.version)")
    $versionGdtoolkit = $Versions.gdtoolkit.version
}
Write-Ok "gdtoolkit $versionGdtoolkit"

# ---------------------------------------------------------------------------
# Plugins Godot
# ---------------------------------------------------------------------------
Write-Etape 'Plugins Godot'
$versionsPlugins = [ordered]@{}
foreach ($propriete in $Versions.plugins.PSObject.Properties) {
    $plugin = $propriete.Value
    $cible = Join-Path $Addons $plugin.dossier
    $marqueur = Join-Path $cible '.version-installee'
    $dejaInstalle = (Test-Path $marqueur) -and ((Get-Content -Raw $marqueur).Trim() -eq $plugin.version)
    if (-not $dejaInstalle) {
        $archive = Join-Path $Cache "$($propriete.Name)_$($plugin.version).zip"
        Get-Fichier $plugin.url $archive
        $extraction = Join-Path $Cache "extrait_$($propriete.Name)"
        Expand-Zip $archive $extraction
        $source = Get-ChildItem -Path $extraction -Recurse -Directory -Filter $plugin.dossier |
                  Where-Object { $_.Parent.Name -eq 'addons' } | Select-Object -First 1
        if (-not $source) { throw "$($propriete.Name) : dossier addons/$($plugin.dossier) introuvable dans l'archive." }
        if (Test-Path $cible) { Remove-Item -Recurse -Force $cible }
        Copy-Item -Recurse -Force $source.FullName $cible
        Set-Content -Encoding ASCII -Path $marqueur -Value $plugin.version
        Remove-Item -Recurse -Force $extraction
    }
    $versionsPlugins[$propriete.Name] = $plugin.version
    Write-Ok "$($propriete.Name) $($plugin.version)"
}

# ---------------------------------------------------------------------------
# outils.json (fusion avec les entrées écrites par installer.ps1)
# ---------------------------------------------------------------------------
Write-Etape 'Tools/outils.json'
$outils = [ordered]@{}
if (Test-Path $OutilsJson) {
    $existant = Get-Content -Raw -Encoding UTF8 $OutilsJson | ConvertFrom-Json
    foreach ($p in $existant.PSObject.Properties) { $outils[$p.Name] = $p.Value }
}
$outils['genere_le'] = (Get-Date).ToString('s')
$outils['plateforme'] = if ($EstWindows) { 'windows' } elseif ($EstMacOS) { 'macos' } else { 'linux' }
$outils['godot'] = [ordered]@{
    tag            = $Versions.godot.tag
    version        = $versionGodot
    editeur        = $godotEditeur
    console        = $godotConsole
    modeles_export = $dossierModeles
}
$outils['godot_cpp'] = [ordered]@{ chemin = $dossierCpp; branche = $branche; commit = $commitCpp }
$outils['scons'] = [ordered]@{ python = $pythonVenv; version = $versionScons; python_version = $versionPython }
$outils['gdtoolkit'] = [ordered]@{ version = $versionGdtoolkit }
$outils['plugins'] = $versionsPlugins
$outils | ConvertTo-Json -Depth 6 | Set-Content -Encoding UTF8 $OutilsJson
Write-Ok $OutilsJson
