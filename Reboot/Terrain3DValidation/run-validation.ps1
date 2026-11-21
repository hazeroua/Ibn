[CmdletBinding()]
param(
    [ValidateSet('vulkan', 'd3d12')]
    [string]$Renderer = 'vulkan',
    [ValidateRange(5, 7200)]
    [int]$DurationSeconds = 1800,
    [string]$ToolchainRoot = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ProjectRoot = $PSScriptRoot
$RepositoryRoot = Split-Path -Parent (Split-Path -Parent $ProjectRoot)
if (-not $ToolchainRoot) { $ToolchainRoot = $RepositoryRoot }
$ToolsFile = Join-Path $ToolchainRoot 'Tools/outils.json'
$PluginSource = Join-Path $ToolchainRoot 'Game/addons/terrain_3d'
$PluginTarget = Join-Path $ProjectRoot 'addons/terrain_3d'

if (-not (Test-Path -LiteralPath $ToolsFile)) {
    throw "Outils absents : $ToolsFile. Lancez Tools/installer.ps1 dans le dépôt principal."
}
if (-not (Test-Path -LiteralPath $PluginSource)) {
    throw "Terrain3D absent : $PluginSource. Lancez Tools/dependances.ps1 dans le dépôt principal."
}

$Tools = Get-Content -Raw -Encoding UTF8 $ToolsFile | ConvertFrom-Json
$Godot = [string]$Tools.godot.console
if (-not (Test-Path -LiteralPath $Godot)) { throw "Godot absent : $Godot" }

if (Test-Path -LiteralPath $PluginTarget) {
    Remove-Item -LiteralPath $PluginTarget -Recurse -Force
}
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $PluginTarget) | Out-Null
Copy-Item -LiteralPath $PluginSource -Destination $PluginTarget -Recurse

$Driver = if ($Renderer -eq 'd3d12') { 'd3d12' } else { 'vulkan' }
& $Godot --path $ProjectRoot --editor --headless --quit --rendering-driver $Driver
if ($LASTEXITCODE -ne 0) { throw "Import Godot échoué avec le code $LASTEXITCODE." }

New-Item -ItemType Directory -Force -Path (Join-Path $ProjectRoot 'build') | Out-Null
& $Godot --path $ProjectRoot --headless --export-release 'Windows Desktop'
if ($LASTEXITCODE -ne 0) { throw "Export Windows échoué avec le code $LASTEXITCODE." }

$Executable = Join-Path $ProjectRoot 'build/Terrain3DValidation.console.exe'
if (-not (Test-Path -LiteralPath $Executable)) {
    $Executable = Join-Path $ProjectRoot 'build/Terrain3DValidation.exe'
}
if (-not (Test-Path -LiteralPath $Executable)) { throw "Export Windows introuvable : $Executable" }

$ReportPath = Join-Path $ProjectRoot "reports/terrain3d-validation-$Renderer.json"
$LogPath = Join-Path $ProjectRoot "reports/terrain3d-validation-$Renderer.log"
if (Test-Path -LiteralPath $ReportPath) { Remove-Item -LiteralPath $ReportPath -Force }
if (Test-Path -LiteralPath $LogPath) { Remove-Item -LiteralPath $LogPath -Force }
$Arguments = @('--rendering-driver', $Driver, '--log-file', $LogPath, '--', "--duration=$DurationSeconds", "--report=$ReportPath")
$Process = Start-Process -FilePath $Executable -ArgumentList $Arguments -PassThru -WindowStyle Hidden
$PeakWorkingSetBytes = 0L
while (-not $Process.HasExited) {
    $Process.Refresh()
    $PeakWorkingSetBytes = [Math]::Max($PeakWorkingSetBytes, [int64]$Process.WorkingSet64)
    Start-Sleep -Milliseconds 100
}
$Process.Refresh()
$PeakWorkingSetBytes = [Math]::Max($PeakWorkingSetBytes, [int64]$Process.PeakWorkingSet64)
$ExitCode = $Process.ExitCode
if ($ExitCode -ne 0) { throw "Validation Terrain3D échouée avec le code $ExitCode." }
if (-not (Test-Path -LiteralPath $ReportPath)) { throw "Rapport absent : $ReportPath" }
if (-not (Test-Path -LiteralPath $LogPath)) { throw "Journal absent : $LogPath" }
$Report = Get-Content -Raw -Encoding UTF8 $ReportPath | ConvertFrom-Json
$Report | Add-Member -NotePropertyName 'peak_process_working_set_bytes' -NotePropertyValue $PeakWorkingSetBytes -Force
$Report | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 $ReportPath
$ForbiddenLogLines = Select-String -Path $LogPath -Pattern '(^|\s)(ERROR:|SCRIPT ERROR:|CRASH)' -CaseSensitive
if ($ForbiddenLogLines) {
    throw "Le journal contient une erreur : $($ForbiddenLogLines[0].Line)"
}
