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
.PARAMETER Parcours
  points_de_vue (par défaut) : la caméra glisse d'un point de vue à l'autre pendant -Duree secondes.
  joueur : le joueur marche le long de Game/data/<carte>/route_joueur.json, piloté par les actions
  d'entrée comme un vrai joueur ; la mesure dure exactement le parcours (-Duree ne s'applique pas).
  Un chemin res://….json désigne un autre parcours du joueur.
  Résultats dans …/mesure/ (points de vue) ou …/mesure_joueur/ (joueur).
#>
[CmdletBinding()]
param(
    [string]$Carte = 'sandbox',
    [double]$Prechauffage = 3.0,
    [double]$Duree = 20.0,
    [switch]$SansBudgets,
    [string]$Parcours = 'points_de_vue'
)
. "$PSScriptRoot/commun.ps1"

$chemins = Get-CheminCarte $Carte
$parcoursChoisi = Get-Parcours $Carte $Parcours
if ($parcoursChoisi.Joueur -and $PSBoundParameters.ContainsKey('Duree')) {
    throw '-Duree ne s''applique pas au parcours du joueur : la mesure dure tout le parcours (max_duration_s le borne).'
}
$sortie = Join-Path $DossierMesures "$(Get-MvpEnCours)/$Carte/$(Get-Horodatage)/mesure$($parcoursChoisi.Suffixe)"
Write-Etape "Mesure des performances : $Carte (parcours : $($parcoursChoisi.Fichier))"
$prechauffageTexte = [string]::Format([Globalization.CultureInfo]::InvariantCulture, '{0}', $Prechauffage)
if ($parcoursChoisi.Joueur) {
    $arguments = @(
        '--path', $Jeu, '--resolution', '1920x1080', '--',
        '--mode=walk', "--scene=$($chemins.Scene)", "--route=$($parcoursChoisi.Fichier)",
        "--budgets=$($chemins.Budgets)", "--out=$sortie", "--warmup=$prechauffageTexte"
    )
} else {
    $arguments = @(
        '--path', $Jeu, '--resolution', '1920x1080', '--',
        '--mode=benchmark', "--scene=$($chemins.Scene)", "--viewpoints=$($chemins.PointsDeVue)",
        "--budgets=$($chemins.Budgets)", "--out=$sortie",
        "--warmup=$prechauffageTexte",
        "--duration=$([string]::Format([Globalization.CultureInfo]::InvariantCulture, '{0}', $Duree))"
    )
}
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
        if ($r.PSObject.Properties.Name -contains 'route_status') {
            Write-Host ('  Parcours du joueur : {0} | état {1} | points atteints {2}/{3} | {4:N1} m marchés en {5:N1} s' -f `
                $r.route, $r.route_status, $r.route_waypoints_reached, $r.route_waypoints, $r.route_walked_m, $r.route_time_s)
        }
    }
}
if ($SansBudgets) {
    Write-Ok "Mesure enregistrée sans vérification des budgets : $sortie"
} else {
    Write-Ok "Budgets respectés : $sortie"
}
