[CmdletBinding()]
param(
    # Scène du catalogue data/config/boot.json à mesurer ; vide = toutes les scènes.
    [string]$Scene = '',
    [ValidateSet('vulkan', 'd3d12')]
    [string]$Renderer = 'vulkan',
    [ValidateRange(5, 7200)]
    [int]$DurationSeconds = 30,
    [ValidateRange(0, 120)]
    [int]$WarmupSeconds = 5,
    # Dossier contenant Tools/outils.json (Godot, gdtoolkit). Par défaut : ce dépôt,
    # puis le dépôt principal si ce dossier est un worktree Git.
    [string]$ToolchainRoot = '',
    # Arrête après l'export, sans lancer la mesure sur le GPU.
    [switch]$SansMesure
)

# Commande unique du projet : dépendances et ressources figées, analyse du GDScript,
# import, construction des scènes, tests GUT, export Windows, mesure de chaque scène
# sur la machine, captures et comparaison aux budgets. Arrêt à la première erreur.

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
    # Liste (clé, adresse) : quatre cartes par texture, une adresse par fichier isolé.
    $Entries = @()
    foreach ($Texture in $Manifest.textures.PSObject.Properties) {
        foreach ($File in $Texture.Value.files.PSObject.Properties) { $Entries += , @($Texture.Name, [string]$File.Value) }
    }
    if ($Manifest.PSObject.Properties['fichiers']) {
        foreach ($Single in $Manifest.fichiers.PSObject.Properties) { $Entries += , @($Single.Name, [string]$Single.Value.url) }
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

function Invoke-Godot([string[]]$Arguments, [string]$LogPath, [string]$Label) {
    & $script:Godot --path $ProjectRoot --log-file $LogPath @Arguments | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "$Label : Godot a quitté avec le code $LASTEXITCODE (journal : $LogPath)." }
    Assert-CleanLog $LogPath $Label
}

function Measure-Scene([string]$SceneId, [string]$Executable, [string]$RunRoot) {
    $RunDir = Join-Path $RunRoot $SceneId
    New-Item -ItemType Directory -Force -Path $RunDir | Out-Null
    $GameLog = Join-Path $RunDir 'jeu.log'
    $Arguments = @(
        '--rendering-driver', $Renderer, '--log-file', "`"$GameLog`"", '--',
        '--measure', "--scene=$SceneId", "--duration=$DurationSeconds", "--warmup=$WarmupSeconds", "--report-dir=`"$RunDir`""
    )
    $Process = Start-Process -FilePath $Executable -ArgumentList $Arguments -PassThru
    # Lire le handle tout de suite : sans lui, ExitCode peut rester vide après la sortie.
    $null = $Process.Handle
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
    [IO.File]::WriteAllText($ReportPath, ($Report | ConvertTo-Json -Depth 8), $Utf8)
    if (-not (Test-Path -LiteralPath (Join-Path $RunDir 'capture.png'))) { throw "$SceneId : capture absente." }

    Write-Host ''
    Write-Host "  [$SceneId]"
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
        throw "$SceneId : budget de performance dépassé."
    }
    if ($Process.ExitCode -ne 0) { throw "$SceneId : le jeu a quitté avec le code $($Process.ExitCode) (journal : $GameLog)." }
}

$ExitCode = 0
try {
    $Toolchain = Resolve-ToolchainRoot
    $Versions = Read-Json (Join-Path $RepositoryRoot 'Tools/versions.json')
    $Tools = Read-Json (Join-Path $Toolchain 'Tools/outils.json')
    $script:Godot = [string]$Tools.godot.console
    if (-not (Test-Path -LiteralPath $script:Godot)) { throw "Godot absent : $script:Godot" }
    if ($Tools.godot.tag -ne $Versions.godot.tag) {
        throw "Godot installé ($($Tools.godot.tag)) différent de la version figée ($($Versions.godot.tag)) : relancez Tools/installer.ps1."
    }
    $GdLint = Join-Path $Toolchain 'Tools/venv/Scripts/gdlint.exe'
    $GdFormat = Join-Path $Toolchain 'Tools/venv/Scripts/gdformat.exe'
    $Catalog = Read-Json (Join-Path $ProjectRoot 'data/config/boot.json')
    $Scenes = @($Catalog.scenes.PSObject.Properties | ForEach-Object { $_.Name })
    if ($Scene) {
        if ($Scenes -notcontains $Scene) { throw "Scène inconnue : $Scene (catalogue : $($Scenes -join ', '))." }
        $Scenes = @($Scene)
    }
    $RunRoot = Join-Path $ReportsRoot ("{0}-{1}" -f (Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'), $Renderer)
    New-Item -ItemType Directory -Force -Path $RunRoot | Out-Null
    Write-Host "Ibn Khaldoun : scènes $($Scenes -join ', '), $Renderer, Godot $($Versions.godot.tag)"
    Write-Host "Rapports : $RunRoot"

    Write-Step '1/8 Dépendances figées (Tools/versions.json)'
    $Downloads = Join-Path $Toolchain 'Tools/_telechargements'
    Install-Addon 'terrain_3d' $Versions.plugins.terrain_3d $Downloads
    Install-Addon 'gut' $Versions.plugins.gut $Downloads
    Install-Addon 'sky_3d' $Versions.plugins.sky_3d $Downloads

    Write-Step '2/8 Ressources libres (data/ressources.json)'
    Sync-Resources

    Write-Step '3/8 Analyse et mise en forme du GDScript'
    Push-Location $ProjectRoot
    try {
        & $GdLint core world tests outils
        if ($LASTEXITCODE -ne 0) { throw 'gdlint a trouvé des problèmes.' }
        & $GdFormat --check --line-length 140 core world tests outils
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

    Write-Step '7/8 Export Windows'
    $BuildDir = Join-Path $ProjectRoot 'build'
    if (Test-Path -LiteralPath $BuildDir) { Remove-Item -LiteralPath $BuildDir -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $BuildDir | Out-Null
    $Executable = Join-Path $BuildDir 'IbnKhaldoun.exe'
    Invoke-Godot @('--headless', '--export-release', 'Windows Desktop', $Executable) (Join-Path $RunRoot 'export.log') 'Export'
    $TerrainLibrary = Join-Path $BuildDir 'libterrain.windows.release.x86_64.dll'
    foreach ($Required in @($Executable, (Join-Path $BuildDir 'IbnKhaldoun.pck'), $TerrainLibrary)) {
        if (-not (Test-Path -LiteralPath $Required)) { throw "Export incomplet : $Required absent." }
    }

    if ($SansMesure) {
        Write-Step '8/8 Mesure ignorée (-SansMesure)'
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
