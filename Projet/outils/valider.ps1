[CmdletBinding()]
param(
    # Scène du catalogue data/config/boot.json à mesurer ; vide = toutes les scènes.
    [string]$Scene = '',
    # Pilote de rendu de la mesure ; vide = celui du système (voir Docs/validation-multi-os.md).
    [ValidateSet('', 'vulkan', 'd3d12', 'metal', 'opengl3')]
    [string]$Renderer = '',
    [ValidateRange(5, 7200)]
    [int]$DurationSeconds = 30,
    [ValidateRange(0, 120)]
    [int]$WarmupSeconds = 5,
    # Dossier contenant Tools/outils.json (Godot, gdtoolkit). Par défaut : ce dépôt,
    # puis le dépôt principal si ce dossier est un worktree Git.
    [string]$ToolchainRoot = '',
    # Arrête après l'export, sans lancer la mesure sur le GPU.
    [switch]$SansMesure,
    # N'exporte pas le jeu (machines sans modèles d'export, CI) ; implique -SansMesure.
    [switch]$SansExport,
    # Rend les budgets bloquants hors de Windows (sous Windows, ils le sont toujours).
    [switch]$BudgetsBloquants,
    # Mesure sans sortie son (machines sans carte son, CI) : sinon Godot écrit une ligne ERROR:
    # en ne trouvant aucun périphérique, ce qui ferait échouer la validation.
    [switch]$SansSon
)

# Commande unique du projet, identique sous Windows, macOS et Linux : dépendances et
# ressources figées, analyse du GDScript, import, construction des scènes, tests GUT,
# export de la plateforme courante, mesure de chaque scène sur la machine, captures et
# comparaison aux budgets. Arrêt à la première erreur. Fonctionnement détaillé et
# différences entre systèmes : Docs/validation-multi-os.md.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$RepositoryRoot = Split-Path -Parent $ProjectRoot
$ReportsRoot = Join-Path $ProjectRoot 'rapports'
New-Item -ItemType Directory -Force -Path $ReportsRoot | Out-Null
$TranscriptPath = Join-Path $ReportsRoot 'derniere-validation.txt'
Start-Transcript -Path $TranscriptPath -Force | Out-Null
$Started = Get-Date
$Utf8 = New-Object System.Text.UTF8Encoding $false

# Système hôte. Compatible Windows PowerShell 5.1 (pas de $IsWindows) et PowerShell 7.
$OnWindows = [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT
$OnMacOS = (-not $OnWindows) -and
    [Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([Runtime.InteropServices.OSPlatform]::OSX)
$HostPlatform = if ($OnWindows) { 'windows' } elseif ($OnMacOS) { 'macos' } else { 'linux' }
# Architecture : x64 ou arm64. Sous Windows PowerShell 5.1, RuntimeInformation n'est pas
# toujours chargé : la variable d'environnement du processeur suffit.
$HostArchitecture = if ($OnWindows) {
    if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'arm64' } else { 'x64' }
}
else {
    ([string][Runtime.InteropServices.RuntimeInformation]::OSArchitecture).ToLowerInvariant()
}

# Ce qui change d'un système à l'autre, et seulement cela. Preset : nom du préréglage de
# export_presets.cfg ; Executable : fichier produit dans build/ (lancé pour la mesure) ;
# Required : fichiers qui doivent accompagner l'export ; Renderers : pilotes acceptés,
# le premier étant celui par défaut ; VenvBin : dossier des commandes de Tools/venv.
$PlatformSpecs = @{
    windows = @{
        Preset = 'Windows Desktop'; Executable = 'IbnKhaldoun.exe'
        Required = @('IbnKhaldoun.pck', 'libterrain.windows.release.x86_64.dll')
        Renderers = @('vulkan', 'd3d12', 'opengl3'); VenvBin = 'Scripts'; CommandSuffix = '.exe'
    }
    linux = @{
        Preset = 'Linux'; Executable = 'IbnKhaldoun.x86_64'
        Required = @('IbnKhaldoun.pck', 'libterrain.linux.release.x86_64.so')
        Renderers = @('vulkan', 'opengl3'); VenvBin = 'bin'; CommandSuffix = ''
    }
    macos = @{
        Preset = 'macOS'; Executable = 'IbnKhaldoun.app/Contents/MacOS/IbnKhaldoun'
        Required = @()
        Renderers = @('metal', 'vulkan', 'opengl3'); VenvBin = 'bin'; CommandSuffix = ''
    }
}
$Platform = $PlatformSpecs[$HostPlatform]
# Metal n'existe dans Godot 4.7 que sur Apple silicon : les Mac Intel passent par Vulkan (MoltenVK).
if ($OnMacOS -and $HostArchitecture -ne 'arm64') { $Platform.Renderers = @('vulkan', 'opengl3') }
if (-not $Renderer) { $Renderer = $Platform.Renderers[0] }
# Budgets : la cible du jeu est Windows sur Intel Arc ; ailleurs ils sont affichés sans bloquer.
$BudgetsBlock = $OnWindows -or $BudgetsBloquants

function Write-Step([string]$Text) {
    Write-Host ''
    Write-Host "==> $Text" -ForegroundColor Cyan
}

function Read-Json([string]$Path) {
    return [IO.File]::ReadAllText($Path, $Utf8) | ConvertFrom-Json
}

function Assert-CleanLog([string]$Path, [string]$Label) {
    if (-not (Test-Path -LiteralPath $Path)) { throw "$Label : journal absent ($Path)." }
    $Forbidden = Select-String -LiteralPath $Path -Pattern '(^|\s)(ERROR:|SCRIPT ERROR:|CRASH)' -CaseSensitive
    if ($Forbidden) { throw "$Label : erreur dans le journal : $($Forbidden[0].Line.Trim())" }
}

function Resolve-ToolchainRoot {
    if ($ToolchainRoot) { return $ToolchainRoot }
    if (Test-Path -LiteralPath (Join-Path $RepositoryRoot 'Tools/outils.json')) { return $RepositoryRoot }
    $CommonDir = (& git -C $RepositoryRoot rev-parse --path-format=absolute --git-common-dir 2>$null)
    if ($LASTEXITCODE -eq 0 -and $CommonDir) {
        $MainRoot = Split-Path -Parent $CommonDir.Trim()
        if (Test-Path -LiteralPath (Join-Path $MainRoot 'Tools/outils.json')) { return $MainRoot }
    }
    throw "Outils introuvables : lancez Tools/installer.ps1 dans le dépôt principal ou passez -ToolchainRoot."
}

function Install-Addon($Name, $Spec, [string]$Downloads) {
    $Target = Join-Path $ProjectRoot "addons/$Name"
    $Stamp = Join-Path $Target '.version-figee'
    if ((Test-Path -LiteralPath $Stamp) -and ((Get-Content -Raw -LiteralPath $Stamp).Trim() -eq $Spec.version)) {
        Write-Host "  $Name $($Spec.version) déjà installé"
        return
    }
    $Zip = Join-Path $Downloads "$($Spec.dossier)_$($Spec.version).zip"
    if (-not (Test-Path -LiteralPath $Zip)) {
        New-Item -ItemType Directory -Force -Path $Downloads | Out-Null
        Write-Host "  téléchargement de $($Spec.url)"
        Invoke-WebRequest -Uri $Spec.url -OutFile $Zip -UseBasicParsing
    }
    # Empreinte figée dans Tools/versions.json quand elle est connue.
    if ($Spec.PSObject.Properties['sha256']) {
        $Hash = (Get-FileHash -LiteralPath $Zip -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($Hash -ne $Spec.sha256) {
            Remove-Item -LiteralPath $Zip -Force
            throw "Empreinte inattendue pour $Zip (attendue $($Spec.sha256), obtenue $Hash) : archive supprimée."
        }
    }
    $Temporary = Join-Path ([IO.Path]::GetTempPath()) ("ibn-addon-" + [guid]::NewGuid().ToString('N'))
    try {
        Expand-Archive -LiteralPath $Zip -DestinationPath $Temporary
        $Source = Get-ChildItem -LiteralPath $Temporary -Directory -Recurse |
            Where-Object { $_.Name -eq $Name -and $_.Parent.Name -eq 'addons' } |
            Select-Object -First 1
        if (-not $Source) { throw "Archive $Zip sans dossier addons/$Name." }
        if (Test-Path -LiteralPath $Target) { Remove-Item -LiteralPath $Target -Recurse -Force }
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Target) | Out-Null
        Copy-Item -LiteralPath $Source.FullName -Destination $Target -Recurse
        Set-Content -LiteralPath $Stamp -Value $Spec.version -Encoding ASCII
        Write-Host "  $Name $($Spec.version) installé"
    }
    finally {
        if (Test-Path -LiteralPath $Temporary) { Remove-Item -LiteralPath $Temporary -Recurse -Force }
    }
}

# Télécharge les ressources de data/ressources.json et vérifie leurs empreintes SHA-256
# (data/ressources.lock.json). Une ressource nouvelle voit son empreinte enregistrée ;
# une empreinte différente d'une ressource connue arrête la validation.
function Sync-Resources {
    $Manifest = Read-Json (Join-Path $ProjectRoot 'data/ressources.json')
    $LockPath = Join-Path $ProjectRoot 'data/ressources.lock.json'
    $Lock = Read-Json $LockPath
    $Locked = @{}
    foreach ($Entry in $Lock.files.PSObject.Properties) { $Locked[$Entry.Name] = [string]$Entry.Value }
    $Recorded = 0
    $Count = 0
    $Wanted = @{}
    $DownloadRoot = Join-Path $ProjectRoot 'ressources/telechargees'
    # Liste (dossier, adresse) : quatre cartes par texture, une adresse par fichier isolé.
    $Entries = @()
    foreach ($Texture in $Manifest.textures.PSObject.Properties) {
        foreach ($File in $Texture.Value.files.PSObject.Properties) { $Entries += , @($Texture.Name, [string]$File.Value) }
    }
    if ($Manifest.PSObject.Properties['fichiers']) {
        foreach ($Single in $Manifest.fichiers.PSObject.Properties) {
            # « dossier » garde côte à côte les fichiers d'une même source (glTF et son .bin).
            $Folder = if ($Single.Value.PSObject.Properties['dossier']) { [string]$Single.Value.dossier } else { $Single.Name }
            $Entries += , @($Folder, [string]$Single.Value.url)
        }
    }
    foreach ($Entry in $Entries) {
        $Key = $Entry[0]
        $Url = $Entry[1]
            $Wanted[$Url] = $true
            $FileName = [IO.Path]::GetFileName(([Uri]$Url).AbsolutePath)
            $Target = Join-Path $ProjectRoot "ressources/telechargees/$Key/$FileName"
            if (-not (Test-Path -LiteralPath $Target)) {
                New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Target) | Out-Null
                Write-Host "  téléchargement de $Url"
                $Partial = "$Target.part"
                Invoke-WebRequest -Uri $Url -OutFile $Partial -UseBasicParsing
                Move-Item -LiteralPath $Partial -Destination $Target -Force
            }
            $Hash = (Get-FileHash -LiteralPath $Target -Algorithm SHA256).Hash.ToLowerInvariant()
            if ($Locked.ContainsKey($Url)) {
                if ($Locked[$Url] -ne $Hash) {
                    Remove-Item -LiteralPath $Target -Force
                    throw "Empreinte inattendue pour $Url (attendue $($Locked[$Url]), obtenue $Hash) : fichier supprimé."
                }
            }
            else {
                $Locked[$Url] = $Hash
                $Recorded += 1
                Write-Host "  empreinte enregistrée : $FileName"
            }
            $Count += 1
    }
    # Ressources retirées du manifeste : empreintes et fichiers supprimés.
    $Removed = 0
    foreach ($Url in @($Locked.Keys)) {
        if (-not $Wanted.ContainsKey($Url)) { $Locked.Remove($Url); $Removed += 1 }
    }
    if (Test-Path -LiteralPath $DownloadRoot) {
        foreach ($Folder in Get-ChildItem -LiteralPath $DownloadRoot -Directory) {
            $Expected = @($Entries | Where-Object { $_[0] -eq $Folder.Name } | ForEach-Object { [IO.Path]::GetFileName(([Uri]$_[1]).AbsolutePath) })
            if ($Expected.Count -eq 0) {
                Remove-Item -LiteralPath $Folder.FullName -Recurse -Force
                Write-Host "  ressource retirée : $($Folder.Name)"
                continue
            }
            foreach ($Old in Get-ChildItem -LiteralPath $Folder.FullName -File) {
                if ($Expected -notcontains $Old.Name) { Remove-Item -LiteralPath $Old.FullName -Force; Write-Host "  fichier retiré : $($Folder.Name)/$($Old.Name)" }
            }
        }
    }
    if ($Recorded -gt 0 -or $Removed -gt 0) {
        $Lines = @($Locked.Keys | Sort-Object | ForEach-Object { '    "{0}": "{1}"' -f $_, $Locked[$_] })
        $Text = "{`n  `"files`": {`n" + ($Lines -join ",`n") + "`n  }`n}`n"
        [IO.File]::WriteAllText($LockPath, $Text, $Utf8)
    }
    Write-Host "  $Count fichiers vérifiés, $Recorded empreintes nouvelles, $Removed retirées"
}

# Prépare le personnage joueur avec Blender (outils/blender/preparer_personnage.py) à partir
# de sa source téléchargée : generated/personnages/<id>/<id>.glb et ses réglages d'import.
# Rien n'est refait si le résultat est à jour (empreinte du script, du manifeste, de la
# source et de la version de Blender).
function Get-TextHash([string]$Text) {
    $Algorithm = [Security.Cryptography.SHA256]::Create()
    try { $Bytes = $Algorithm.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text)) }
    finally { $Algorithm.Dispose() }
    return ([BitConverter]::ToString($Bytes) -replace '-', '').ToLowerInvariant()
}

function Get-FileSha([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

# Blender : chemin noté par l'installateur dans Tools/outils.json, sinon emplacement habituel
# du système, sinon commande « blender » du PATH.
function Resolve-Blender($Tools) {
    $Property = $Tools.PSObject.Properties['blender']
    if ($Property -and $Property.Value -and $Property.Value.chemin -and (Test-Path -LiteralPath $Property.Value.chemin)) {
        return [string]$Property.Value.chemin
    }
    $Candidates = @()
    if ($OnMacOS) {
        $Candidates += (Join-Path $Toolchain 'Tools/blender/Blender.app/Contents/MacOS/Blender')
        $Candidates += '/Applications/Blender.app/Contents/MacOS/Blender'
    }
    elseif (-not $OnWindows) {
        $Candidates += (Join-Path $Toolchain 'Tools/blender/blender')
    }
    foreach ($Candidate in $Candidates) { if (Test-Path -LiteralPath $Candidate) { return $Candidate } }
    $Command = Get-Command 'blender' -ErrorAction SilentlyContinue
    if ($Command) { return $Command.Source }
    $Installer = if ($OnWindows) { 'Tools/installer.ps1' } elseif ($OnMacOS) { 'Tools/installer-macos.command' } else { 'votre gestionnaire de paquets' }
    throw "Blender introuvable : installez-le avec $Installer (son chemin est noté dans Tools/outils.json)."
}

function Invoke-Blender([string]$Blender, [string[]]$Arguments, [string]$LogPath) {
    $Previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $Output = @(& $Blender @Arguments 2>&1 | ForEach-Object { "$_" })
        $Code = $LASTEXITCODE
    }
    finally { $ErrorActionPreference = $Previous }
    [IO.File]::WriteAllLines($LogPath, [string[]]$Output, $Utf8)
    $Failures = @($Output | Where-Object { $_ -match '^(ERREUR preparer_personnage|Traceback|Error: )' })
    if ($Failures.Count -gt 0) { throw "Blender a signalé une erreur (journal : $LogPath) :`n$($Failures -join "`n")" }
    if ($Code -ne 0) { throw "Blender s'est terminé avec le code $Code (journal : $LogPath)." }
}

function Write-CharacterImportSettings([string]$Glb) {
    $Wanted = @(
        'meshes/ensure_tangents=false', 'meshes/generate_lods=true', 'meshes/create_shadow_meshes=true', 'meshes/light_baking=0',
        'animation/import=true', 'animation/fps=30', 'animation/trimming=false', 'animation/remove_immutable_tracks=true',
        'animation/import_rest_as_RESET=false',
        'import_script/path="res://player/character_post_import.gd"'
    )
    $ImportPath = "$Glb.import"
    if (Test-Path -LiteralPath $ImportPath) {
        $Existing = @([IO.File]::ReadAllLines($ImportPath, $Utf8) | ForEach-Object { $_.Trim() })
        if (@($Wanted | Where-Object { $Existing -notcontains $_ }).Count -eq 0) { return }
    }
    $Lines = @('[remap]', '', 'importer="scene"', 'importer_version=1', 'type="PackedScene"', '', '[params]', '') + $Wanted
    [IO.File]::WriteAllLines($ImportPath, [string[]]$Lines, $Utf8)
}

function Build-Characters($Tools, [string]$RunRoot) {
    $ManifestPath = Join-Path $ProjectRoot 'data/player/personnage.json'
    $ScriptPath = Join-Path $ProjectRoot 'outils/blender/preparer_personnage.py'
    $Resources = Read-Json (Join-Path $ProjectRoot 'data/ressources.json')
    $Manifest = Read-Json $ManifestPath
    $Blender = Resolve-Blender $Tools
    $Previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { $VersionOutput = @(& $Blender --background --factory-startup --version 2>&1 | ForEach-Object { "$_" }) }
    finally { $ErrorActionPreference = $Previous }
    $VersionLine = @($VersionOutput | Where-Object { $_ -match '^Blender \d' } | Select-Object -First 1)
    if ($VersionLine.Count -eq 0) { throw "Version de Blender illisible : $($VersionOutput -join ' ')" }
    $BlenderVersion = $VersionLine[0].Trim()
    Write-Host "  $BlenderVersion"
    foreach ($Character in $Manifest.characters) {
        if ($Character.id -notmatch '^[a-z0-9_]+$') { throw "Identifiant de personnage invalide : « $($Character.id) »." }
        $SourceDir = Join-Path $ProjectRoot "ressources/telechargees/$($Character.source_ressource)"
        $SourceFile = Join-Path $SourceDir $Character.source_file
        if (-not (Test-Path -LiteralPath $SourceFile)) { throw "Personnage $($Character.id) : source absente ($SourceFile)." }
        $SourceHashes = @(Get-ChildItem -LiteralPath $SourceDir -File | Sort-Object Name | ForEach-Object { Get-FileSha $_.FullName })
        $OutputDir = Join-Path $ProjectRoot "generated/personnages/$($Character.id)"
        New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
        $Glb = Join-Path $OutputDir "$($Character.id).glb"
        $StampPath = "$Glb.empreinte"
        $Stamp = Get-TextHash ("$(Get-FileSha $ScriptPath)|$(Get-FileSha $ManifestPath)|$($SourceHashes -join ',')|$BlenderVersion")
        $UpToDate = (Test-Path -LiteralPath $Glb) -and (Test-Path -LiteralPath $StampPath) -and
            ([IO.File]::ReadAllText($StampPath).Trim() -eq $Stamp)
        if ($UpToDate) {
            Write-Host "  $($Character.id) : à jour"
        }
        else {
            if (Test-Path -LiteralPath $StampPath) { Remove-Item -LiteralPath $StampPath -Force }
            $Report = Join-Path $RunRoot "personnage-$($Character.id).json"
            $Arguments = @(
                '--background', '--factory-startup', '--python-exit-code', '1', '--python', $ScriptPath, '--',
                '--manifest', $ManifestPath, '--character', $Character.id,
                '--source-dir', $SourceDir, '--output', $Glb, '--report', $Report
            )
            Invoke-Blender $Blender $Arguments (Join-Path $RunRoot "personnage-$($Character.id).log")
            if (-not (Test-Path -LiteralPath $Glb)) { throw "Blender n'a pas produit $Glb." }
            [IO.File]::WriteAllText($StampPath, $Stamp, $Utf8)
            Write-Host "  $($Character.id) : préparé par Blender"
        }
        Write-CharacterImportSettings $Glb
    }
}

# Prépare le cheval (ticket #106) avec Blender : forme, textures cuites, puis squelette et animations du cheval
# de Quaternius (sources/cheval/). Résultat : generated/chevaux/cheval_sahara/cheval_sahara.glb. Rien n'est refait
# si le résultat est à jour (empreinte des trois scripts, de la source d'animations et de la version de Blender).
function Build-Horse($Tools, [string]$RunRoot) {
    $ScriptDir = Join-Path $ProjectRoot 'outils/blender/cheval'
    $Scripts = @('forme.py', 'textures.py', 'squelette.py') | ForEach-Object { Join-Path $ScriptDir $_ }
    $Animations = Join-Path $ProjectRoot 'sources/cheval/animations_quaternius.glb'
    foreach ($Required in $Scripts + @($Animations)) {
        if (-not (Test-Path -LiteralPath $Required)) { throw "Cheval : fichier absent ($Required)." }
    }
    $Blender = Resolve-Blender $Tools
    $Previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { $VersionOutput = @(& $Blender --background --factory-startup --version 2>&1 | ForEach-Object { "$_" }) }
    finally { $ErrorActionPreference = $Previous }
    $BlenderVersion = (@($VersionOutput | Where-Object { $_ -match '^Blender \d' } | Select-Object -First 1) -join '').Trim()
    $OutputDir = Join-Path $ProjectRoot 'generated/chevaux/cheval_sahara'
    $WorkDir = Join-Path $ProjectRoot 'generated/chevaux/travail'
    New-Item -ItemType Directory -Force -Path $OutputDir, $WorkDir | Out-Null
    # Fichiers de travail (.blend) : Godot ne doit pas les importer (il chercherait Blender).
    [IO.File]::WriteAllText((Join-Path $WorkDir '.gdignore'), '', $Utf8)
    $Glb = Join-Path $OutputDir 'cheval_sahara.glb'
    $StampPath = "$Glb.empreinte"
    $Hashes = (@($Scripts + @($Animations)) | ForEach-Object { Get-FileSha $_ }) -join '|'
    $Stamp = Get-TextHash "$Hashes|$BlenderVersion"
    if ((Test-Path -LiteralPath $Glb) -and (Test-Path -LiteralPath $StampPath) -and ([IO.File]::ReadAllText($StampPath).Trim() -eq $Stamp)) {
        Write-Host '  cheval_sahara : à jour'
        return
    }
    if (Test-Path -LiteralPath $StampPath) { Remove-Item -LiteralPath $StampPath -Force }
    $Common = @('--background', '--factory-startup', '--python-exit-code', '1', '--python')
    $Forme = Join-Path $WorkDir 'forme.blend'
    $Textures = Join-Path $WorkDir 'textures.blend'
    Invoke-Blender $Blender ($Common + @($Scripts[0], '--', '--sortie', $WorkDir)) (Join-Path $RunRoot 'cheval-forme.log')
    Invoke-Blender $Blender ($Common + @($Scripts[1], '--', '--entree', $Forme, '--sortie', $WorkDir)) (Join-Path $RunRoot 'cheval-textures.log')
    Invoke-Blender $Blender ($Common + @(
            $Scripts[2], '--', '--entree', $Textures, '--animations', $Animations, '--sortie', $Glb,
            '--rapport', (Join-Path $RunRoot 'cheval.json'))) (Join-Path $RunRoot 'cheval-squelette.log')
    if (-not (Test-Path -LiteralPath $Glb)) { throw "Blender n'a pas produit $Glb." }
    [IO.File]::WriteAllText($StampPath, $Stamp, $Utf8)
    Write-Host '  cheval_sahara : préparé par Blender (forme, textures, squelette)'
}

function Invoke-Godot([string[]]$Arguments, [string]$LogPath, [string]$Label) {
    & $script:Godot --path $ProjectRoot --log-file $LogPath @Arguments | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "$Label : Godot a quitté avec le code $LASTEXITCODE (journal : $LogPath)." }
    Assert-CleanLog $LogPath $Label
}

# Lance le jeu sans passer par un interpréteur de commandes. Les arguments sont transmis un à
# un (ArgumentList, PowerShell 7) ; sous Windows PowerShell 5.1, qui ne l'a pas, ils sont
# entourés de guillemets quand ils contiennent un espace.
function Start-Game([string]$Executable, [string[]]$Arguments) {
    $Info = New-Object System.Diagnostics.ProcessStartInfo
    $Info.FileName = $Executable
    $Info.UseShellExecute = $false
    $Info.WorkingDirectory = Split-Path -Parent $Executable
    if ($Info.PSObject.Properties['ArgumentList']) {
        foreach ($Argument in $Arguments) { $Info.ArgumentList.Add($Argument) }
    }
    else {
        $Info.Arguments = ($Arguments | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join ' '
    }
    $Process = [Diagnostics.Process]::Start($Info)
    # Lire le handle tout de suite : sans lui, ExitCode peut rester vide après la sortie (Windows).
    $null = $Process.Handle
    return $Process
}

# Préréglage d'export présent dans export_presets.cfg ?
function Test-ExportPreset([string]$Name) {
    $Config = [IO.File]::ReadAllText((Join-Path $ProjectRoot 'export_presets.cfg'), $Utf8)
    return $Config -match ('(?m)^name="' + [regex]::Escape($Name) + '"\s*$')
}

function Measure-Scene([string]$SceneId, [string]$Executable, [string]$RunRoot) {
    $RunDir = Join-Path $RunRoot $SceneId
    New-Item -ItemType Directory -Force -Path $RunDir | Out-Null
    $GameLog = Join-Path $RunDir 'jeu.log'
    # Sans export (préréglage absent pour ce système), Godot lance le projet lui-même.
    $Arguments = @()
    if ($Executable -eq $script:Godot) { $Arguments += @('--path', $ProjectRoot) }
    if ($SansSon) { $Arguments += @('--audio-driver', 'Dummy') }
    $Arguments += @(
        '--rendering-driver', $Renderer, '--log-file', $GameLog, '--',
        '--measure', "--scene=$SceneId", "--duration=$DurationSeconds", "--warmup=$WarmupSeconds", "--report-dir=$RunDir"
    )
    $Process = Start-Game $Executable $Arguments
    $PeakWorkingSet = 0L
    $Deadline = (Get-Date).AddSeconds($DurationSeconds + $WarmupSeconds + 180)
    while (-not $Process.HasExited) {
        if ((Get-Date) -gt $Deadline) {
            Stop-Process -Id $Process.Id -Force
            throw "$SceneId : la mesure ne s'est pas terminée à temps (journal : $GameLog)."
        }
        $Process.Refresh()
        $PeakWorkingSet = [Math]::Max($PeakWorkingSet, [int64]$Process.WorkingSet64)
        Start-Sleep -Milliseconds 200
    }
    $Process.WaitForExit()
    Assert-CleanLog $GameLog "Mesure de $SceneId"
    $ReportPath = Join-Path $RunDir 'rapport.json'
    if (-not (Test-Path -LiteralPath $ReportPath)) { throw "$SceneId : rapport absent (code $($Process.ExitCode), journal : $GameLog)." }
    $Report = Read-Json $ReportPath
    $Report | Add-Member -NotePropertyName 'peak_process_working_set_mib' -NotePropertyValue ([Math]::Round($PeakWorkingSet / 1MB, 1)) -Force
    $Report | Add-Member -NotePropertyName 'validation_platform' -NotePropertyValue "$HostPlatform-$HostArchitecture" -Force
    $Report | Add-Member -NotePropertyName 'budgets_blocking' -NotePropertyValue $BudgetsBlock -Force
    [IO.File]::WriteAllText($ReportPath, ($Report | ConvertTo-Json -Depth 8), $Utf8)
    if (-not (Test-Path -LiteralPath (Join-Path $RunDir 'capture.png'))) { throw "$SceneId : capture absente." }

    Write-Host ''
    Write-Host "  [$SceneId]"
    Write-Host ("  Système             : {0} {1} ({2})" -f $Report.os_name, $Report.os_version, $Report.cpu_architecture)
    Write-Host ("  GPU                 : {0} ({1}, {2})" -f $Report.rendering_device, $Report.rendering_method, $Report.rendering_driver)
    Write-Host ("  Démarrage           : {0:N0} ms" -f $Report.startup_ms)
    Write-Host ("  Images mesurées     : {0} en {1:N1} s" -f $Report.frame_count, $Report.duration_seconds)
    Write-Host ("  Moyenne             : {0:N2} ms ({1:N0} i/s)" -f $Report.average_frame_ms, (1000 / [Math]::Max($Report.average_frame_ms, 0.001)))
    Write-Host ("  p99 / 1 % bas       : {0:N1} ms / {1:N0} i/s" -f $Report.p99_frame_ms, $Report.low_1_percent_fps)
    Write-Host ("  Pire image          : {0:N2} ms" -f $Report.max_frame_ms)
    Write-Host ("  Appels de dessin    : {0}" -f $Report.peak_draw_calls)
    Write-Host ("  Mémoire vidéo       : {0:N0} Mio" -f $Report.peak_video_memory_mib)
    Write-Host ("  Mémoire du processus: {0:N0} Mio" -f $Report.peak_process_working_set_mib)
    Write-Host ("  Collisions manquées : {0:N0}/{1:N0}" -f $Report.collision_failures, $Report.collision_checks)
    if ($Process.ExitCode -eq 2 -or -not $Report.budgets_passed) {
        foreach ($Failure in $Report.budget_failures) { Write-Host "  DÉPASSEMENT : $Failure" -ForegroundColor Red }
        if ($BudgetsBlock) { throw "$SceneId : budget de performance dépassé." }
        Write-Host "  Budgets non bloquants sous $HostPlatform (cible : Windows sur Intel Arc ; -BudgetsBloquants pour bloquer)." -ForegroundColor Yellow
    }
    elseif ($Process.ExitCode -ne 0) { throw "$SceneId : le jeu a quitté avec le code $($Process.ExitCode) (journal : $GameLog)." }
}

$ExitCode = 0
try {
    $Toolchain = Resolve-ToolchainRoot
    $Versions = Read-Json (Join-Path $RepositoryRoot 'Tools/versions.json')
    $Tools = Read-Json (Join-Path $Toolchain 'Tools/outils.json')
    if ($Platform.Renderers -notcontains $Renderer) {
        throw "Pilote de rendu « $Renderer » indisponible sous $HostPlatform-$HostArchitecture (acceptés : $($Platform.Renderers -join ', '))."
    }
    $ToolsPlatform = if ($Tools.PSObject.Properties['plateforme']) { [string]$Tools.plateforme } else { 'windows' }
    if ($ToolsPlatform -ne $HostPlatform) {
        throw "Tools/outils.json a été écrit sous $ToolsPlatform, pas sous $HostPlatform : relancez l'installateur de ce système."
    }
    $script:Godot = [string]$Tools.godot.console
    if (-not (Test-Path -LiteralPath $script:Godot)) { throw "Godot absent : $script:Godot" }
    if ($Tools.godot.tag -ne $Versions.godot.tag) {
        throw "Godot installé ($($Tools.godot.tag)) différent de la version figée ($($Versions.godot.tag)) : relancez Tools/installer.ps1."
    }
    $GdLint = Join-Path $Toolchain "Tools/venv/$($Platform.VenvBin)/gdlint$($Platform.CommandSuffix)"
    $GdFormat = Join-Path $Toolchain "Tools/venv/$($Platform.VenvBin)/gdformat$($Platform.CommandSuffix)"
    foreach ($Command in @($GdLint, $GdFormat)) { if (-not (Test-Path -LiteralPath $Command)) { throw "gdtoolkit absent : $Command" } }
    $Catalog = Read-Json (Join-Path $ProjectRoot 'data/config/boot.json')
    $Scenes = @($Catalog.scenes.PSObject.Properties | ForEach-Object { $_.Name })
    if ($Scene) {
        if ($Scenes -notcontains $Scene) { throw "Scène inconnue : $Scene (catalogue : $($Scenes -join ', '))." }
        $Scenes = @($Scene)
    }
    $RunRoot = Join-Path $ReportsRoot ("{0}-{1}" -f (Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'), $Renderer)
    New-Item -ItemType Directory -Force -Path $RunRoot | Out-Null
    Write-Host "Ibn Khaldoun : scènes $($Scenes -join ', '), $Renderer, Godot $($Versions.godot.tag), $HostPlatform-$HostArchitecture"
    Write-Host "Rapports : $RunRoot"

    Write-Step '1/8 Dépendances figées (Tools/versions.json)'
    $Downloads = Join-Path $Toolchain 'Tools/_telechargements'
    Install-Addon 'terrain_3d' $Versions.plugins.terrain_3d $Downloads
    Install-Addon 'gut' $Versions.plugins.gut $Downloads
    Install-Addon 'sky_3d' $Versions.plugins.sky_3d $Downloads

    Write-Step '2/8 Ressources libres (data/ressources.json), personnage et cheval (Blender)'
    Sync-Resources
    Build-Characters $Tools $RunRoot
    Build-Horse $Tools $RunRoot

    Write-Step '3/8 Analyse et mise en forme du GDScript'
    Push-Location $ProjectRoot
    try {
        & $GdLint core world player horse audio tests outils
        if ($LASTEXITCODE -ne 0) { throw 'gdlint a trouvé des problèmes.' }
        & $GdFormat --check --line-length 140 core world player horse audio tests outils
        if ($LASTEXITCODE -ne 0) { throw 'gdformat : des fichiers ne sont pas mis en forme.' }
    }
    finally { Pop-Location }

    Write-Step '4/8 Import du projet'
    Invoke-Godot @('--headless', '--editor', '--quit') (Join-Path $RunRoot 'import.log') 'Import'

    Write-Step '5/8 Construction des scènes'
    Invoke-Godot @('--headless', '-s', 'res://outils/construire.gd') (Join-Path $RunRoot 'construction.log') 'Construction'
    Invoke-Godot @('--headless', '--editor', '--quit') (Join-Path $RunRoot 'import-construit.log') 'Import des ressources construites'

    Write-Step '6/8 Tests GUT'
    Invoke-Godot @('--headless', '-s', 'res://addons/gut/gut_cmdln.gd', '-gconfig=res://.gutconfig.json') (Join-Path $RunRoot 'tests.log') 'Tests'

    # Sans préréglage pour ce système (macOS : ticket #100, Linux : ticket #101), la mesure
    # lance le projet directement avec Godot : mêmes scènes, même sonde, mêmes rapports.
    $Executable = $script:Godot
    if ($SansExport) {
        Write-Step "7/8 Export $HostPlatform ignoré (-SansExport)"
    }
    elseif (-not (Test-ExportPreset $Platform.Preset)) {
        Write-Step "7/8 Export $HostPlatform : préréglage « $($Platform.Preset) » absent, la mesure lancera le projet avec Godot"
    }
    else {
        Write-Step "7/8 Export $HostPlatform ($($Platform.Preset))"
        $BuildDir = Join-Path $ProjectRoot 'build'
        if (Test-Path -LiteralPath $BuildDir) { Remove-Item -LiteralPath $BuildDir -Recurse -Force }
        New-Item -ItemType Directory -Force -Path $BuildDir | Out-Null
        $ExportTarget = if ($OnMacOS) { Join-Path $BuildDir 'IbnKhaldoun.app' } else { Join-Path $BuildDir $Platform.Executable }
        Invoke-Godot @('--headless', '--export-release', $Platform.Preset, $ExportTarget) (Join-Path $RunRoot 'export.log') 'Export'
        $Executable = Join-Path $BuildDir $Platform.Executable
        foreach ($Required in @($Platform.Executable) + $Platform.Required) {
            $RequiredPath = Join-Path $BuildDir $Required
            if (-not (Test-Path -LiteralPath $RequiredPath)) { throw "Export incomplet : $RequiredPath absent." }
        }
    }

    if ($SansMesure -or $SansExport) {
        Write-Step '8/8 Mesure ignorée (-SansMesure ou -SansExport)'
    }
    else {
        Write-Step "8/8 Mesure sur le GPU : $WarmupSeconds s de préchauffage puis $DurationSeconds s par scène"
        # Toutes les scènes sont mesurées, même si l'une échoue, pour un compte rendu complet.
        $Failures = @()
        foreach ($SceneId in $Scenes) {
            try { Measure-Scene $SceneId $Executable $RunRoot }
            catch { $Failures += $_.Exception.Message; Write-Host "  ÉCHEC : $($_.Exception.Message)" -ForegroundColor Red }
        }
        if ($Failures.Count -gt 0) { throw ($Failures -join ' | ') }
    }

    Write-Host ''
    Write-Host ("VALIDATION RÉUSSIE en {0:N0} s. Rapports : {1}" -f ((Get-Date) - $Started).TotalSeconds, $RunRoot) -ForegroundColor Green
}
catch {
    Write-Host ''
    Write-Host "VALIDATION ÉCHOUÉE : $($_.Exception.Message)" -ForegroundColor Red
    $ExitCode = 1
}
finally {
    Stop-Transcript | Out-Null
}
exit $ExitCode
