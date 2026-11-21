Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-Equal {
    param($Actual, $Expected, [string]$Message)
    if ($Actual -ne $Expected) { throw "$Message — attendu : $Expected ; obtenu : $Actual" }
}

$root = Join-Path ([IO.Path]::GetTempPath()) ('ibn-gltf-analysis-tests-' + [guid]::NewGuid().ToString('N'))
$source = Join-Path $root 'glTF'
$report = Join-Path $root 'report.json'
$null = New-Item -ItemType Directory -Path $source -Force

try {
    $gltf = @{
        asset = @{ version = '2.0' }
        scenes = @(@{ nodes = @(0) })
        nodes = @(@{ mesh = 0; name = 'Rock_Medium_Test' })
        meshes = @(@{ primitives = @(@{ attributes = @{ POSITION = 0 }; indices = 1 }) })
        accessors = @(
            @{ count = 4; type = 'VEC3'; min = @(-1.0, 0.0, -1.0); max = @(1.0, 2.0, 1.0) },
            @{ count = 6; type = 'SCALAR' }
        )
        buffers = @(@{ byteLength = 12; uri = 'Rock_Medium_Test.bin' })
        images = @(@{ uri = 'Rock_Medium_Test.png' })
        materials = @(@{ name = 'Rock' })
    } | ConvertTo-Json -Depth 10
    [IO.File]::WriteAllText((Join-Path $source 'Rock_Medium_Test.gltf'), $gltf, [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllBytes((Join-Path $source 'Rock_Medium_Test.bin'), [byte[]](0..11))
    [IO.File]::WriteAllBytes(
        (Join-Path $source 'Rock_Medium_Test.png'),
        [Convert]::FromBase64String('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=')
    )

    $script = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../analyser-pack-gltf.ps1'))
    & $script -DossierSource $source -Rapport $report -Sha256Archive ('a' * 64)
    $result = Get-Content -Raw -Encoding UTF8 -LiteralPath $report | ConvertFrom-Json

    Assert-Equal $result.totals.models 1 'nombre de modèles'
    Assert-Equal $result.totals.vertices 4 'nombre de sommets'
    Assert-Equal $result.totals.triangles 2 'nombre de triangles'
    Assert-Equal $result.models[0].category 'rock' 'catégorie'
    Assert-Equal $result.models[0].grounded_with_2_percent_tolerance $true 'pivot au sol'
    Assert-Equal $result.models[0].dimensions_m[1] 2 'hauteur'
    Assert-Equal $result.textures[0].width 1 'largeur texture PNG'
    Assert-Equal $result.textures[0].height 1 'hauteur texture PNG'
    Write-Host '[OK] analyse glTF synthétique'

    $unsafe = $gltf | ConvertFrom-Json
    $unsafe.buffers[0].uri = '../escape.bin'
    [IO.File]::WriteAllText((Join-Path $source 'Unsafe.gltf'), ($unsafe | ConvertTo-Json -Depth 10), [Text.UTF8Encoding]::new($false))
    $failedSafely = $false
    try {
        & $script -DossierSource $source -Rapport $report -Sha256Archive ('a' * 64)
    }
    catch {
        $failedSafely = $_.Exception.Message -match 'URI externe ou chemin non sûr'
    }
    Assert-Equal $failedSafely $true 'URI traversante refusée'
    Write-Host '[OK] URI glTF traversante refusée'
}
finally {
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
}
