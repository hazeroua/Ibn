[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$DossierSource,
    [Parameter(Mandatory)][string]$Rapport,
    [Parameter(Mandatory)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$Sha256Archive
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-PropertyValue {
    param($Object, [Parameter(Mandatory)][string]$Name, $Default = $null)

    if ($null -ne $Object -and $null -ne $Object.PSObject.Properties[$Name]) {
        return $Object.$Name
    }
    return $Default
}

function Test-SafeLeafUri {
    param([Parameter(Mandatory)][string]$Uri)

    return (
        $Uri -notmatch '[/\\:]' -and
        $Uri -notmatch '^\.' -and
        $Uri -notmatch '[\x00-\x1F<>"|?*]'
    )
}

function Get-Category {
    param([Parameter(Mandatory)][string]$Name)

    switch -Regex ($Name) {
        '^Rock_Medium_' { return 'rock' }
        '^RockPath_' { return 'rock_path' }
        '^Pebble_Round_' { return 'round_pebble' }
        '^Pebble_Square_' { return 'square_pebble' }
        '^Grass_' { return 'grass' }
        '^Bush_' { return 'bush' }
        '^(CommonTree|DeadTree|Pine|TwistedTree)_' { return 'tree' }
        '^(Clover|Fern|Flower|Mushroom|Petal|Plant)_' { return 'ground_plant' }
        default { return 'unclassified' }
    }
}

function Get-PngDimensions {
    param([Parameter(Mandatory)][string]$Path)

    $bytes = [IO.File]::ReadAllBytes($Path)
    if (
        $bytes.Length -lt 24 -or
        $bytes[0] -ne 0x89 -or $bytes[1] -ne 0x50 -or $bytes[2] -ne 0x4E -or $bytes[3] -ne 0x47 -or
        $bytes[12] -ne 0x49 -or $bytes[13] -ne 0x48 -or $bytes[14] -ne 0x44 -or $bytes[15] -ne 0x52
    ) {
        throw "PNG invalide ou sans en-tête IHDR : $([IO.Path]::GetFileName($Path))"
    }
    $width = ([uint32]$bytes[16] -shl 24) -bor ([uint32]$bytes[17] -shl 16) -bor ([uint32]$bytes[18] -shl 8) -bor $bytes[19]
    $height = ([uint32]$bytes[20] -shl 24) -bor ([uint32]$bytes[21] -shl 16) -bor ([uint32]$bytes[22] -shl 8) -bor $bytes[23]
    return [pscustomobject]@{ width = [long]$width; height = [long]$height }
}

function Write-JsonAtomic {
    param([Parameter(Mandatory)]$Value, [Parameter(Mandatory)][string]$Path)

    $fullPath = [IO.Path]::GetFullPath($Path)
    $directory = Split-Path -Parent $fullPath
    if (-not (Test-Path -LiteralPath $directory)) {
        $null = New-Item -ItemType Directory -Path $directory -Force
    }
    $temporary = Join-Path $directory ('.' + [IO.Path]::GetFileName($fullPath) + '.' + [guid]::NewGuid().ToString('N') + '.tmp')
    $encoding = New-Object Text.UTF8Encoding($false)
    try {
        [IO.File]::WriteAllText($temporary, ($Value | ConvertTo-Json -Depth 12), $encoding)
        Move-Item -LiteralPath $temporary -Destination $fullPath -Force
    }
    finally {
        if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force }
    }
}

$sourceRoot = [IO.Path]::GetFullPath($DossierSource)
if (-not (Test-Path -LiteralPath $sourceRoot -PathType Container)) {
    throw "Dossier glTF introuvable : $DossierSource"
}

$gltfFiles = @(Get-ChildItem -LiteralPath $sourceRoot -Filter '*.gltf' -File | Sort-Object Name)
if ($gltfFiles.Count -eq 0) { throw 'Aucun fichier glTF à analyser.' }

$models = [Collections.Generic.List[object]]::new()
$totalVertices = 0L
$totalTriangles = 0L
$totalPrimitives = 0L
$allReferencedFiles = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)

foreach ($file in $gltfFiles) {
    $document = Get-Content -Raw -Encoding UTF8 -LiteralPath $file.FullName | ConvertFrom-Json
    $asset = Get-PropertyValue $document 'asset'
    if ((Get-PropertyValue $asset 'version' '') -ne '2.0') {
        throw "$($file.Name) : version glTF autre que 2.0."
    }

    $accessors = @(Get-PropertyValue $document 'accessors' @())
    $meshes = @(Get-PropertyValue $document 'meshes' @())
    $materials = @(Get-PropertyValue $document 'materials' @())
    $animations = @(Get-PropertyValue $document 'animations' @())
    $nodes = @(Get-PropertyValue $document 'nodes' @())
    $images = @(Get-PropertyValue $document 'images' @())
    $buffers = @(Get-PropertyValue $document 'buffers' @())

    $modelVertices = 0L
    $modelTriangles = 0L
    $modelPrimitives = 0L
    $minimum = @([double]::PositiveInfinity, [double]::PositiveInfinity, [double]::PositiveInfinity)
    $maximum = @([double]::NegativeInfinity, [double]::NegativeInfinity, [double]::NegativeInfinity)

    foreach ($mesh in $meshes) {
        foreach ($primitive in @(Get-PropertyValue $mesh 'primitives' @())) {
            $mode = [int](Get-PropertyValue $primitive 'mode' 4)
            if ($mode -ne 4) { throw "$($file.Name) : primitive non triangulaire (mode $mode)." }

            $attributes = Get-PropertyValue $primitive 'attributes'
            $positionIndex = [int](Get-PropertyValue $attributes 'POSITION' -1)
            if ($positionIndex -lt 0 -or $positionIndex -ge $accessors.Count) {
                throw "$($file.Name) : accesseur POSITION invalide."
            }
            $positionAccessor = $accessors[$positionIndex]
            $vertexCount = [long](Get-PropertyValue $positionAccessor 'count' 0)
            $modelVertices += $vertexCount

            $indicesIndex = [int](Get-PropertyValue $primitive 'indices' -1)
            if ($indicesIndex -lt 0 -or $indicesIndex -ge $accessors.Count) {
                throw "$($file.Name) : primitive triangulaire sans indices valides."
            }
            $indexCount = [long](Get-PropertyValue $accessors[$indicesIndex] 'count' 0)
            if (($indexCount % 3) -ne 0) { throw "$($file.Name) : nombre d'indices non divisible par trois." }
            $modelTriangles += [long]($indexCount / 3)
            $modelPrimitives++

            $accessorMinimum = @(Get-PropertyValue $positionAccessor 'min' @())
            $accessorMaximum = @(Get-PropertyValue $positionAccessor 'max' @())
            if ($accessorMinimum.Count -ne 3 -or $accessorMaximum.Count -ne 3) {
                throw "$($file.Name) : limites POSITION absentes."
            }
            for ($axis = 0; $axis -lt 3; $axis++) {
                $minimum[$axis] = [Math]::Min($minimum[$axis], [double]$accessorMinimum[$axis])
                $maximum[$axis] = [Math]::Max($maximum[$axis], [double]$accessorMaximum[$axis])
            }
        }
    }

    $references = [Collections.Generic.List[string]]::new()
    foreach ($resource in @($buffers) + @($images)) {
        $uri = [string](Get-PropertyValue $resource 'uri' '')
        if (-not $uri -or -not (Test-SafeLeafUri $uri)) { throw "$($file.Name) : URI externe ou chemin non sûr." }
        $referencedPath = Join-Path $sourceRoot $uri
        if (-not (Test-Path -LiteralPath $referencedPath -PathType Leaf)) {
            throw "$($file.Name) : ressource absente : $uri"
        }
        $references.Add($uri)
        $null = $allReferencedFiles.Add($uri)
    }

    $hasNodeTransform = @($nodes | Where-Object {
        $null -ne $_.PSObject.Properties['matrix'] -or
        $null -ne $_.PSObject.Properties['translation'] -or
        $null -ne $_.PSObject.Properties['rotation'] -or
        $null -ne $_.PSObject.Properties['scale']
    }).Count -gt 0
    $height = $maximum[1] - $minimum[1]
    $groundTolerance = [Math]::Max(0.02, $height * 0.02)
    $grounded = [Math]::Abs($minimum[1]) -le $groundTolerance

    $totalVertices += $modelVertices
    $totalTriangles += $modelTriangles
    $totalPrimitives += $modelPrimitives
    $models.Add([pscustomobject][ordered]@{
        id = [IO.Path]::GetFileNameWithoutExtension($file.Name)
        category = Get-Category ([IO.Path]::GetFileNameWithoutExtension($file.Name))
        gltf_file = $file.Name
        vertices = $modelVertices
        triangles = $modelTriangles
        primitives = $modelPrimitives
        materials = $materials.Count
        material_names = @($materials | ForEach-Object { [string](Get-PropertyValue $_ 'name' '') })
        referenced_files = @($references | Sort-Object -Unique)
        animations = $animations.Count
        has_node_transform = $hasNodeTransform
        bounds_min = @($minimum)
        bounds_max = @($maximum)
        dimensions_m = @(
            ($maximum[0] - $minimum[0])
            $height
            ($maximum[2] - $minimum[2])
        )
        pivot_min_y_m = $minimum[1]
        grounded_with_2_percent_tolerance = $grounded
        required_ground_offset_m = -$minimum[1]
    })
}

$textureFiles = @($allReferencedFiles | Where-Object { [IO.Path]::GetExtension($_) -ieq '.png' } | Sort-Object)
$textures = @($textureFiles | ForEach-Object {
    $texturePath = Join-Path $sourceRoot $_
    $dimensions = Get-PngDimensions $texturePath
    [pscustomobject][ordered]@{
        file = $_
        bytes = (Get-Item -LiteralPath $texturePath).Length
        width = $dimensions.width
        height = $dimensions.height
    }
})

$report = [pscustomobject][ordered]@{
    schema_version = 1
    generated_utc = [DateTime]::UtcNow.ToString('o')
    archive_sha256 = $Sha256Archive.ToLowerInvariant()
    format = 'glTF 2.0'
    coordinate_assumption = 'right-handed, Y-up, metres according to glTF 2.0; dimensions verified from accessors'
    source_directory_name = [IO.Path]::GetFileName($sourceRoot.TrimEnd([IO.Path]::DirectorySeparatorChar))
    totals = [pscustomobject][ordered]@{
        models = $models.Count
        vertices = $totalVertices
        triangles = $totalTriangles
        primitives = $totalPrimitives
        unique_referenced_files = $allReferencedFiles.Count
    }
    textures = $textures
    models = @($models)
}

Write-JsonAtomic $report $Rapport
Write-Host "Analyse glTF : $($models.Count) modèles, $totalTriangles triangles, $totalVertices sommets."
Write-Host "Rapport : $([IO.Path]::GetFullPath($Rapport))"
