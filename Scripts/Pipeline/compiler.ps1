<#
.SYNOPSIS
  Compile l'extension C++ (GDExtension) dans Game/bin/.
.PARAMETER Cible
  debug (bibliothèque de l'éditeur et des tests), release (version exportée) ou toutes (par défaut).
.PARAMETER Taches
  Nombre de compilations en parallèle (par défaut : nombre de cœurs).
#>
[CmdletBinding()]
param(
    [ValidateSet('debug', 'release', 'toutes')][string]$Cible = 'toutes',
    [int]$Taches = 0
)
. "$PSScriptRoot/commun.ps1"

$cibles = switch ($Cible) {
    'debug' { @('template_debug') }
    'release' { @('template_release') }
    default { @('template_debug', 'template_release') }
}
$paralleles = if ($Taches -gt 0) { $Taches } else { [Environment]::ProcessorCount }

Push-Location (Join-Path $Racine 'Extensions')
try {
    foreach ($cibleScons in $cibles) {
        Write-Etape "Compilation C++ : $cibleScons"
        Invoke-Outil $PythonOutils @('-m', 'SCons', "target=$cibleScons", "-j$paralleles")
        Write-Ok $cibleScons
    }
} finally {
    Pop-Location
}
