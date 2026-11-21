Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
Import-Module (Join-Path $PSScriptRoot '../AssetQuarantine/AssetQuarantine.psm1') -Force

function Assert-Equal {
    param($Actual, $Expected, [string]$Message)
    if ($Actual -ne $Expected) {
        throw "$Message — attendu : $Expected ; obtenu : $Actual"
    }
}
function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function New-SyntheticZip {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][object[]]$Entries
    )

    $zip = [IO.Compression.ZipFile]::Open($Path, [IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($definition in $Entries) {
            $entry = $zip.CreateEntry([string]$definition.path, [IO.Compression.CompressionLevel]::Optimal)
            if ($definition.symlink) {
                $bytes = [BitConverter]::GetBytes([uint32]2717843456)
                $entry.ExternalAttributes = [BitConverter]::ToInt32($bytes, 0)
            }
            $stream = $entry.Open()
            try {
                $content = [Text.Encoding]::UTF8.GetBytes([string]$definition.content)
                $stream.Write($content, 0, $content.Length)
            }
            finally {
                $stream.Dispose()
            }
        }
    }
    finally {
        $zip.Dispose()
    }
}

$root = Join-Path ([IO.Path]::GetTempPath()) ('ibn-asset-quarantine-tests-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $root
$passed = 0
$archives = @{}

try {
    $cases = @(
        [pscustomobject]@{
            name = 'archive saine'
            expected = 'accepted'
            entries = @(
                [pscustomobject]@{ path = 'Models/rock.glb'; content = 'synthetic-glb'; symlink = $false },
                [pscustomobject]@{ path = 'Textures/rock.png'; content = 'synthetic-png'; symlink = $false },
                [pscustomobject]@{ path = 'LICENSE.txt'; content = 'synthetic-license'; symlink = $false }
            )
            expectedCode = 'accepted'
        },
        [pscustomobject]@{
            name = 'traversée de chemin'
            expected = 'rejected'
            entries = @([pscustomobject]@{ path = '../escape.glb'; content = 'blocked'; symlink = $false })
            expectedCode = 'unsafe_path'
        },
        [pscustomobject]@{
            name = 'lien symbolique'
            expected = 'rejected'
            entries = @([pscustomobject]@{ path = 'Models/link.glb'; content = 'Models/target.glb'; symlink = $true })
            expectedCode = 'symbolic_link'
        },
        [pscustomobject]@{
            name = 'script inattendu'
            expected = 'rejected'
            entries = @([pscustomobject]@{ path = 'Tools/setup.py'; content = 'print("never executed")'; symlink = $false })
            expectedCode = 'blocked_file'
        },
        [pscustomobject]@{
            name = 'fichier Blend'
            expected = 'quarantined'
            entries = @([pscustomobject]@{ path = 'Source/model.blend'; content = 'synthetic-blend'; symlink = $false })
            expectedCode = 'manual_review'
        },
        [pscustomobject]@{
            name = 'document PDF'
            expected = 'quarantined'
            entries = @([pscustomobject]@{ path = 'Documentation/manual.pdf'; content = 'synthetic-pdf'; symlink = $false })
            expectedCode = 'manual_review'
        },
        [pscustomobject]@{
            name = 'collision de casse'
            expected = 'rejected'
            entries = @(
                [pscustomobject]@{ path = 'Models/Rock.glb'; content = 'one'; symlink = $false },
                [pscustomobject]@{ path = 'models/rock.glb'; content = 'two'; symlink = $false }
            )
            expectedCode = 'duplicate_path'
        },
        [pscustomobject]@{
            name = 'chemin absolu Windows'
            expected = 'rejected'
            entries = @([pscustomobject]@{ path = 'C:\escape.glb'; content = 'blocked'; symlink = $false })
            expectedCode = 'unsafe_path'
        },
        [pscustomobject]@{
            name = 'extension inconnue'
            expected = 'rejected'
            entries = @([pscustomobject]@{ path = 'Models/model.xyzpayload'; content = 'blocked'; symlink = $false })
            expectedCode = 'blocked_file'
        },
        [pscustomobject]@{
            name = 'nom Windows réservé'
            expected = 'rejected'
            entries = @([pscustomobject]@{ path = 'Models/CON.glb'; content = 'blocked'; symlink = $false })
            expectedCode = 'unsafe_path'
        }
    )

    foreach ($case in $cases) {
        $archive = Join-Path $root (($case.name -replace '[^A-Za-z0-9]+', '-') + '.zip')
        $report = Join-Path $root (($case.name -replace '[^A-Za-z0-9]+', '-') + '.json')
        New-SyntheticZip -Path $archive -Entries $case.entries
        $archives[$case.name] = $archive
        $result = Test-AssetArchive -ArchivePath $archive -ReportPath $report -TemporaryRoot $root

        Assert-Equal $result.decision $case.expected "$($case.name) : décision"
        Assert-True (Test-Path -LiteralPath $report) "$($case.name) : rapport absent"
        $saved = Get-Content -Raw -Encoding UTF8 -LiteralPath $report | ConvertFrom-Json
        Assert-Equal $saved.decision $case.expected "$($case.name) : décision du rapport"
        Assert-True (@($saved.findings.code) -contains $case.expectedCode) "$($case.name) : constat $($case.expectedCode) absent"
        Assert-True $saved.extraction.removed "$($case.name) : dossier temporaire non supprimé"
        Assert-True ($saved.archive.sha256 -match '^[0-9a-f]{64}$') "$($case.name) : SHA-256 archive absent"

        if ($case.expected -eq 'accepted') {
            Assert-Equal @($saved.inventory).Count 3 "$($case.name) : inventaire incomplet"
            Assert-True (@($saved.inventory | Where-Object { $_.sha256 -notmatch '^[0-9a-f]{64}$' }).Count -eq 0) "$($case.name) : empreinte fichier absente"
        }
        if ($case.expected -eq 'rejected') {
            Assert-True (-not $saved.extraction.performed) "$($case.name) : une archive refusée a été extraite"
        }

        Write-Host "[OK] $($case.name)"
        $passed++
    }

    $oversizedReport = Join-Path $root 'archive-trop-grande.json'
    $oversized = Test-AssetArchive -ArchivePath $archives['archive saine'] -ReportPath $oversizedReport `
        -TemporaryRoot $root -MaxArchiveBytes 1
    Assert-Equal $oversized.decision 'rejected' 'limite archive : décision'
    Assert-True (@($oversized.findings.code) -contains 'archive_too_large') 'limite archive : constat absent'
    Assert-True (-not $oversized.extraction.performed) 'limite archive : extraction inattendue'
    Assert-True ($null -eq $oversized.archive.sha256) 'limite archive : hash calculé malgré le refus avant lecture'
    Write-Host '[OK] limite de taille du ZIP avant ouverture'
    $passed++

    $pwsh = (Get-Process -Id $PID).Path
    $cli = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../inspecter-archive-3d.ps1'))
    $cliAcceptedReport = Join-Path $root 'cli-accepted.json'
    & $pwsh -NoProfile -File $cli -Archive $archives['archive saine'] -Rapport $cliAcceptedReport -DossierTemporaire $root
    Assert-Equal $LASTEXITCODE 0 'CLI : code archive saine'
    Assert-True (Test-Path -LiteralPath $cliAcceptedReport) 'CLI : rapport archive saine absent'

    $cliRejectedReport = Join-Path $root 'cli-rejected.json'
    & $pwsh -NoProfile -File $cli -Archive $archives['script inattendu'] -Rapport $cliRejectedReport -DossierTemporaire $root
    Assert-Equal $LASTEXITCODE 3 'CLI : code archive refusée'
    Assert-True (Test-Path -LiteralPath $cliRejectedReport) 'CLI : rapport archive refusée absent'

    Write-Host "$passed tests synthétiques et 2 tests CLI réussis." -ForegroundColor Green
}
finally {
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
}
