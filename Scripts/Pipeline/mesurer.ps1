<#
.SYNOPSIS
  Mesure les performances d'une carte sur un parcours de caméra scripté et vérifie ses budgets.

.DESCRIPTION
  Lance le jeu en fenêtre (1920x1080, synchronisation verticale désactivée), préchauffe, mesure chaque
  image pendant la durée demandée, puis écrit Mesures/<mvp>/<carte>/<date>/mesure/resume.json et images.csv.
  Échoue si un budget de Game/tests/perf/budgets/<carte>.json est dépassé.

  Les mesures n'ont de valeur que sur la machine de développement (puce Intel Arc intégrée) :
  ailleurs (CI), utiliser -SansBudgets.
.PARAMETER Carte
  Nom de la carte (par défaut : sandbox).
#>
[CmdletBinding()]
param(
    [string]$Carte = 'sandbox',
    [double]$Prechauffage = 3.0,
    [double]$Duree = 20.0,
    [switch]$SansBudgets
)
. "$PSScriptRoot/commun.ps1"

$chemins = Get-CheminCarte $Carte
$sortie = Join-Path $DossierMesures "$(Get-MvpEnCours)/$Carte/$(Get-Horodatage)/mesure"
Write-Etape "Mesure des performances : $Carte"
$arguments = @(
    '--path', $Jeu, '--resolution', '1920x1080', '--',
    '--mode=benchmark', "--scene=$($chemins.Scene)", "--viewpoints=$($chemins.PointsDeVue)",
    "--budgets=$($chemins.Budgets)", "--out=$sortie",
    "--warmup=$([string]::Format([Globalization.CultureInfo]::InvariantCulture, '{0}', $Prechauffage))",
    "--duration=$([string]::Format([Globalization.CultureInfo]::InvariantCulture, '{0}', $Duree))"
)
if ($SansBudgets) { $arguments += '--no-budgets' }
try {
    $null = Invoke-Godot -Arguments $arguments -Journal (Join-Path $sortie 'mesure.log')
} finally {
    $resume = Join-Path $sortie 'resume.json'
    if (Test-Path $resume) {
        $r = Get-Content -Raw -Encoding UTF8 $resume | ConvertFrom-Json
        Write-Host ('  Images : {0} | moyenne {1:N2} ms | 99e centile {2:N2} ms | 1 % bas {3:N1} i/s | GPU p99 {4:N2} ms | appels de dessin max {5} | primitives max {6} | mémoire vidéo max {7:N0} Mo' -f `
            $r.frames, $r.frame_avg_ms, $r.frame_p99_ms, $r.fps_1pct_low, $r.gpu_p99_ms, $r.draw_calls_max, $r.primitives_max, $r.video_mem_mb_max)
        Write-Host "  Matériel : $($r.adapter) ($($r.adapter_vendor)) — fenêtre $($r.window)"
    }
}
if ($SansBudgets) {
    Write-Ok "Mesure enregistrée sans vérification des budgets : $sortie"
} else {
    Write-Ok "Budgets respectés : $sortie"
}
