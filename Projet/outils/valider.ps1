[CmdletBinding()]
param(
    # Scène du catalogue data/config/boot.json à mesurer.
    [string]$Scene = 'terrain_test',
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

# Commande unique du socle : ressources figées, analyse du GDScript, import,
# tests GUT, export Windows, mesure de la scène sur la machine, capture et
# comparaison au budget. S'arrête à la première erreur avec un message clair.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$RepositoryRoot = Split-Path -Parent $ProjectRoot
$ReportsRoot = Join-Path $ProjectRoot 'rapports'
New-Item -ItemType Directory -Force -Path $ReportsRoot | Out-Null
$TranscriptPath = Join-Path $ReportsRoot 'derniere-validation.txt'
Start-Transcript -Path $TranscriptPath -Force | Out-Null
$Started = Get-Date

function Write-Step([string]$Text) {
    Write-Host ''
    Write-Host "==> $Text" -ForegroundColor Cyan
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

function Invoke-Godot([string[]]$Arguments, [string]$LogPath, [string]$Label) {
    & $script:Godot --path $ProjectRoot --log-file $LogPath @Arguments | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "$Label : Godot a quitté avec le code $LASTEXITCODE (journal : $LogPath)." }
    Assert-CleanLog $LogPath $Label
}

$ExitCode = 0
try {
    $Toolchain = Resolve-ToolchainRoot
    $Versions = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $RepositoryRoot 'Tools/versions.json') | ConvertFrom-Json
    $Tools = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $Toolchain 'Tools/outils.json') | ConvertFrom-Json
    $script:Godot = [string]$Tools.godot.console
    if (-not (Test-Path -LiteralPath $script:Godot)) { throw "Godot absent : $script:Godot" }
    if ($Tools.godot.tag -ne $Versions.godot.tag) {
        throw "Godot installé ($($Tools.godot.tag)) différent de la version figée ($($Versions.godot.tag)) : relancez Tools/installer.ps1."
    }
    $GdLint = Join-Path $Toolchain 'Tools/venv/Scripts/gdlint.exe'
    $GdFormat = Join-Path $Toolchain 'Tools/venv/Scripts/gdformat.exe'
    $Stamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
    $RunDir = Join-Path $ReportsRoot "$Scene/$Stamp-$Renderer"
    New-Item -ItemType Directory -Force -Path $RunDir | Out-Null
    Write-Host "Socle Ibn Khaldoun : scène $Scene, $Renderer, Godot $($Versions.godot.tag)"
    Write-Host "Rapports : $RunDir"

    Write-Step '1/6 Dépendances figées (Tools/versions.json)'
    $Downloads = Join-Path $Toolchain 'Tools/_telechargements'
    Install-Addon 'terrain_3d' $Versions.plugins.terrain_3d $Downloads
    Install-Addon 'gut' $Versions.plugins.gut $Downloads

    Write-Step '2/6 Analyse et mise en forme du GDScript'
    Push-Location $ProjectRoot
    try {
        & $GdLint core world tests
        if ($LASTEXITCODE -ne 0) { throw 'gdlint a trouvé des problèmes.' }
        & $GdFormat --check --line-length 140 core world tests
        if ($LASTEXITCODE -ne 0) { throw 'gdformat : des fichiers ne sont pas mis en forme.' }
    }
    finally { Pop-Location }

    Write-Step '3/6 Import du projet'
    Invoke-Godot @('--headless', '--editor', '--quit') (Join-Path $RunDir 'import.log') 'Import'

    Write-Step '4/6 Tests GUT'
    Invoke-Godot @('--headless', '-s', 'res://addons/gut/gut_cmdln.gd', '-gconfig=res://.gutconfig.json') (Join-Path $RunDir 'tests.log') 'Tests'

    Write-Step '5/6 Export Windows'
    $BuildDir = Join-Path $ProjectRoot 'build'
    if (Test-Path -LiteralPath $BuildDir) { Remove-Item -LiteralPath $BuildDir -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $BuildDir | Out-Null
    $Executable = Join-Path $BuildDir 'IbnKhaldoun.exe'
    Invoke-Godot @('--headless', '--export-release', 'Windows Desktop', $Executable) (Join-Path $RunDir 'export.log') 'Export'
    $TerrainLibrary = Join-Path $BuildDir 'libterrain.windows.release.x86_64.dll'
    foreach ($Required in @($Executable, (Join-Path $BuildDir 'IbnKhaldoun.pck'), $TerrainLibrary)) {
        if (-not (Test-Path -LiteralPath $Required)) { throw "Export incomplet : $Required absent." }
    }

    if ($SansMesure) {
        Write-Step '6/6 Mesure ignorée (-SansMesure)'
    }
    else {
        Write-Step "6/6 Mesure de « $Scene » : $WarmupSeconds s de préchauffage puis $DurationSeconds s"
        $GameLog = Join-Path $RunDir 'jeu.log'
        $Arguments = @(
            '--rendering-driver', $Renderer, '--log-file', "`"$GameLog`"", '--',
            '--measure', "--scene=$Scene", "--duration=$DurationSeconds", "--warmup=$WarmupSeconds", "--report-dir=`"$RunDir`""
        )
        $Process = Start-Process -FilePath $Executable -ArgumentList $Arguments -PassThru
        # Lire le handle tout de suite : sans lui, ExitCode peut rester vide après la sortie.
        $null = $Process.Handle
        $PeakWorkingSet = 0L
        $Deadline = (Get-Date).AddSeconds($DurationSeconds + $WarmupSeconds + 120)
        while (-not $Process.HasExited) {
            if ((Get-Date) -gt $Deadline) {
                Stop-Process -Id $Process.Id -Force
                throw "La mesure ne s'est pas terminée à temps (journal : $GameLog)."
            }
            $Process.Refresh()
            $PeakWorkingSet = [Math]::Max($PeakWorkingSet, [int64]$Process.WorkingSet64)
            Start-Sleep -Milliseconds 200
        }
        $Process.WaitForExit()
        Assert-CleanLog $GameLog 'Mesure'
        $ReportPath = Join-Path $RunDir 'rapport.json'
        if (-not (Test-Path -LiteralPath $ReportPath)) { throw "Rapport absent (code $($Process.ExitCode), journal : $GameLog)." }
        $Report = Get-Content -Raw -Encoding UTF8 -LiteralPath $ReportPath | ConvertFrom-Json
        $GamePeak = Get-Process -Name 'IbnKhaldoun' -ErrorAction SilentlyContinue
        if ($GamePeak) { throw 'Le jeu est encore ouvert après la mesure.' }
        $Report | Add-Member -NotePropertyName 'peak_process_working_set_mib' -NotePropertyValue ([Math]::Round($PeakWorkingSet / 1MB, 1)) -Force
        $Report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $ReportPath -Encoding UTF8
        if (-not (Test-Path -LiteralPath (Join-Path $RunDir 'capture.png'))) { throw 'Capture absente.' }

        Write-Host ''
        Write-Host ("  GPU                 : {0} ({1}, {2})" -f $Report.rendering_device, $Report.rendering_method, $Report.rendering_driver)
        Write-Host ("  Démarrage           : {0:N0} ms" -f $Report.startup_ms)
        Write-Host ("  Images mesurées     : {0} en {1:N1} s" -f $Report.frame_count, $Report.duration_seconds)
        Write-Host ("  Moyenne             : {0:N2} ms ({1:N0} i/s)" -f $Report.average_frame_ms, (1000 / [Math]::Max($Report.average_frame_ms, 0.001)))
        Write-Host ("  p99 / 1 % bas       : {0:N1} ms / {1:N0} i/s" -f $Report.p99_frame_ms, $Report.low_1_percent_fps)
        Write-Host ("  Pire image          : {0:N2} ms" -f $Report.max_frame_ms)
        Write-Host ("  Appels de dessin    : {0}" -f $Report.peak_draw_calls)
        Write-Host ("  Mémoire vidéo       : {0:N0} Mio" -f $Report.peak_video_memory_mib)
        Write-Host ("  Mémoire du processus: {0:N0} Mio" -f $Report.peak_process_working_set_mib)
        Write-Host ("  Collisions manquées : {0}/{1}" -f $Report.collision_failures, $Report.collision_checks)
        if ($Process.ExitCode -eq 2 -or -not $Report.budgets_passed) {
            foreach ($Failure in $Report.budget_failures) { Write-Host "  DÉPASSEMENT : $Failure" -ForegroundColor Red }
            throw 'Budget de performance dépassé.'
        }
        if ($Process.ExitCode -ne 0) { throw "Le jeu a quitté avec le code $($Process.ExitCode) (journal : $GameLog)." }
    }

    Write-Host ''
    Write-Host ("VALIDATION RÉUSSIE en {0:N0} s. Rapports : {1}" -f ((Get-Date) - $Started).TotalSeconds, $RunDir) -ForegroundColor Green
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
