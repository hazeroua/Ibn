[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Archive,
    [Parameter(Mandatory)][string]$Rapport,
    [string]$DossierTemporaire = ([IO.Path]::GetTempPath())
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'AssetQuarantine/AssetQuarantine.psm1') -Force
$resultat = Test-AssetArchive -ArchivePath $Archive -ReportPath $Rapport -TemporaryRoot $DossierTemporaire

switch ($resultat.decision) {
    'accepted' {
        Write-Host "ACCEPTÉ : $($resultat.archive.name)" -ForegroundColor Green
        Write-Host "Rapport : $([IO.Path]::GetFullPath($Rapport))"
        exit 0
    }
    'quarantined' {
        Write-Host "QUARANTAINE : $($resultat.archive.name)" -ForegroundColor Yellow
        Write-Host "Rapport : $([IO.Path]::GetFullPath($Rapport))"
        exit 2
    }
    default {
        Write-Host "REFUSÉ : $($resultat.archive.name)" -ForegroundColor Red
        foreach ($finding in $resultat.findings | Where-Object severity -eq 'reject') {
            Write-Host "  [$($finding.code)] $($finding.entry) $($finding.message)" -ForegroundColor Red
        }
        Write-Host "Rapport : $([IO.Path]::GetFullPath($Rapport))"
        exit 3
    }
}
