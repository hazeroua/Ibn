# Socle commun des scripts du pipeline. À charger en tête de chaque script :  . "$PSScriptRoot/commun.ps1"
#
# - Lit Tools/outils.json (créé par Tools/installer.ps1 ou Tools/dependances.ps1).
# - Fournit Invoke-Godot, qui lance Godot, journalise sa sortie et échoue si Godot renvoie un code
#   non nul ou affiche une erreur (« ERROR: », « SCRIPT ERROR: », « Parse Error: »…).
# - Fonctionne sous Windows PowerShell 5.1, PowerShell 7, macOS Apple silicon et Linux (CI).

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$Script:EstWindows = [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT
$Script:EstMacOS = [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(
    [System.Runtime.InteropServices.OSPlatform]::OSX
)
$Script:Racine = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$Script:Jeu = Join-Path $Script:Racine 'Game'
$Script:DossierMesures = Join-Path $Script:Racine 'Mesures'
$Script:CheminOutils = Join-Path $Script:Racine 'Tools/outils.json'

if (-not (Test-Path $Script:CheminOutils)) {
    throw 'Tools/outils.json introuvable : lancez Tools/installer.ps1 (Windows), Tools/installer-macos.command (macOS) ou Tools/dependances.ps1 (Linux).'
}
$Script:Outils = Get-Content -Raw -Encoding UTF8 $Script:CheminOutils | ConvertFrom-Json
$Script:GodotConsole = $Script:Outils.godot.console
$Script:GodotEditeur = $Script:Outils.godot.editeur
$Script:PythonOutils = $Script:Outils.scons.python
foreach ($chemin in @($Script:GodotConsole, $Script:GodotEditeur, $Script:PythonOutils)) {
    if (-not (Test-Path $chemin)) {
        $installateur = if ($Script:EstMacOS) { 'Tools/installer-macos.command' } else { 'Tools/installer.ps1' }
        throw "Outil introuvable : $chemin. Relancez $installateur."
    }
}

function Write-Etape([string]$Message) { Write-Host "`n=== $Message" -ForegroundColor Cyan }
function Write-Ok([string]$Message) { Write-Host "  [OK] $Message" -ForegroundColor Green }

function Get-Horodatage {
    return (Get-Date).ToString('yyyy-MM-dd_HH-mm-ss')
}

function Get-MvpEnCours {
    # Lu dans project.godot (réglage ibn/projet/mvp_en_cours) pour ranger mesures et captures par MVP.
    $ligne = Select-String -Path (Join-Path $Script:Jeu 'project.godot') -Pattern '^projet/mvp_en_cours="([^"]+)"' | Select-Object -First 1
    if (-not $ligne) { throw 'Réglage ibn/projet/mvp_en_cours absent de Game/project.godot.' }
    return $ligne.Matches[0].Groups[1].Value
}

function Get-CheminCarte([string]$Carte) {
    # Conventions : scène res://world/<carte>/<carte>.tscn, points de vue res://data/<carte>/viewpoints.json,
    # budgets res://tests/perf/budgets/<carte>.json.
    if ($Carte -notmatch '^[a-z0-9_]+$') { throw "Nom de carte invalide : « $Carte »." }
    return [pscustomobject]@{
        Scene       = "res://world/$Carte/$Carte.tscn"
        PointsDeVue = "res://data/$Carte/viewpoints.json"
        Budgets     = "res://tests/perf/budgets/$Carte.json"
    }
}

function Get-Parcours([string]$Carte, [string]$Parcours) {
    # Parcours suivi par les mesures et la vidéo d'une carte :
    # - 'points_de_vue' : la caméra glisse d'un point de vue à l'autre (res://data/<carte>/viewpoints.json) ;
    # - 'joueur' : le joueur marche, piloté par les actions d'entrée, le long de res://data/<carte>/route_joueur.json ;
    # - 'res://….json' : un autre parcours du joueur (même format que route_joueur.json).
    $chemins = Get-CheminCarte $Carte
    if ($Parcours -eq 'points_de_vue') {
        return [pscustomobject]@{ Joueur = $false; Fichier = $chemins.PointsDeVue; Suffixe = '' }
    }
    if ($Parcours -eq 'joueur') {
        $fichier = "res://data/$Carte/route_joueur.json"
    } elseif ($Parcours -match '^res://[A-Za-z0-9_/.-]+\.json$' -and $Parcours -notmatch '\.\.') {
        $fichier = $Parcours
    } else {
        throw "Parcours invalide : « $Parcours » (points_de_vue, joueur ou un chemin res://….json)."
    }
    $local = Join-Path $Script:Jeu $fichier.Substring('res://'.Length)
    if (-not (Test-Path $local)) { throw "Parcours du joueur introuvable : $fichier" }
    return [pscustomobject]@{ Joueur = $true; Fichier = $fichier; Suffixe = '_joueur' }
}

function Invoke-Godot {
    param(
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [string]$Journal = '',
        [switch]$Editeur,
        [switch]$IgnorerErreursAffichees,
        [string]$Executable = ''
    )
    $executable = if ($Executable) { $Executable } elseif ($Editeur) { $Script:GodotEditeur } else { $Script:GodotConsole }
    if ($env:CI -eq 'true' -and $Arguments -notcontains '--headless' -and $Arguments -notcontains '--audio-driver') {
        # Les machines d'intégration continue n'ont pas de carte son : pilote audio factice.
        # Sur la machine de développement, le son reste actif pendant les mesures (il fait partie du coût réel).
        $Arguments = @('--audio-driver', 'Dummy') + $Arguments
    }
    Write-Host "  > godot $($Arguments -join ' ')" -ForegroundColor DarkGray
    $ancien = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $sortie = @(& $executable @Arguments 2>&1 | ForEach-Object { "$_" })
        $code = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $ancien
    }
    foreach ($ligne in $sortie) { Write-Host $ligne }
    if ($Journal) {
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Journal) | Out-Null
        $sortie | Set-Content -Encoding UTF8 $Journal
    }
    if (-not $IgnorerErreursAffichees) {
        $erreurs = @($sortie | Where-Object { $_ -match '^\s*(ERROR|SCRIPT ERROR|USER ERROR|Parse Error)\b' })
        if ($erreurs.Count -gt 0) {
            throw "Godot a signalé $($erreurs.Count) erreur(s) :`n$($erreurs -join "`n")"
        }
    }
    if ($code -ne 0) {
        throw "Godot s'est terminé avec le code $code : godot $($Arguments -join ' ')"
    }
    return $sortie
}

function Invoke-Outil {
    # Lance un programme externe (hors Godot) et échoue si son code de sortie n'est pas nul.
    param([Parameter(Mandatory = $true)][string]$Programme, [string[]]$Arguments = @())
    & $Programme @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Échec de « $Programme $($Arguments -join ' ') » (code $LASTEXITCODE)." }
}
