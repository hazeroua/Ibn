Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$script:IsWindowsPlatform = [Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(
    [Runtime.InteropServices.OSPlatform]::Windows
)

$script:AcceptedExtensions = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
@(
    '.bin', '.dds', '.exr', '.fbx', '.glb', '.gltf', '.hdr', '.jpeg', '.jpg',
    '.json', '.ktx', '.ktx2', '.license', '.md', '.mtl', '.obj', '.png',
    '.tga', '.txt', '.webp', '.xml', '.yaml', '.yml'
) | ForEach-Object { $null = $script:AcceptedExtensions.Add($_) }

$script:QuarantineExtensions = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
@('.7z', '.blend', '.gz', '.kra', '.pdf', '.psd', '.rar', '.tar', '.xcf', '.zip') |
    ForEach-Object { $null = $script:QuarantineExtensions.Add($_) }

$script:BlockedExtensions = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
@(
    '.app', '.bat', '.bash', '.class', '.cmd', '.com', '.command', '.cs', '.csproj',
    '.dll', '.dmg', '.dylib', '.exe', '.gd', '.gdextension', '.gdshader', '.godot',
    '.hta', '.jar', '.js', '.lnk', '.mjs', '.msi', '.pkg', '.plugin', '.ps1', '.py',
    '.pyc', '.rb', '.scr', '.sh', '.so', '.sln', '.ts', '.unitypackage', '.uplugin',
    '.uproject', '.url', '.vbe', '.vbs', '.wsf', '.zsh'
) | ForEach-Object { $null = $script:BlockedExtensions.Add($_) }

function New-Finding {
    param(
        [Parameter(Mandatory)][ValidateSet('info', 'quarantine', 'reject')][string]$Severity,
        [Parameter(Mandatory)][string]$Code,
        [Parameter(Mandatory)][string]$Message,
        [string]$Entry = ''
    )

    [pscustomobject][ordered]@{
        severity = $Severity
        code = $Code
        entry = $Entry
        message = $Message
    }
}

function Test-DocumentationName {
    param([Parameter(Mandatory)][string]$Name)

    $leaf = [IO.Path]::GetFileName($Name)
    return $leaf -match '^(?i:copying|licen[cs]e|notice|readme|start[ _-]?here)(\.[^./\\]+)?$'
}

function Get-EntryClassification {
    param([Parameter(Mandatory)][string]$NormalizedPath)

    $extension = [IO.Path]::GetExtension($NormalizedPath)
    if (-not $extension) {
        if (Test-DocumentationName $NormalizedPath) {
            return [pscustomobject]@{ category = 'documentation'; disposition = 'accepted' }
        }
        return [pscustomobject]@{ category = 'unknown'; disposition = 'rejected' }
    }

    if ($script:BlockedExtensions.Contains($extension)) {
        return [pscustomobject]@{ category = 'executable_or_script'; disposition = 'rejected' }
    }
    if ($script:QuarantineExtensions.Contains($extension)) {
        return [pscustomobject]@{ category = 'review_required'; disposition = 'quarantined' }
    }
    if ($script:AcceptedExtensions.Contains($extension)) {
        return [pscustomobject]@{ category = 'data'; disposition = 'accepted' }
    }
    return [pscustomobject]@{ category = 'unexpected_extension'; disposition = 'rejected' }
}

function Test-SymbolicLinkEntry {
    param([Parameter(Mandatory)][IO.Compression.ZipArchiveEntry]$Entry)

    $unixType = (($Entry.ExternalAttributes -shr 16) -band 0xF000)
    if ($unixType -eq 0xA000) { return $true }

    $windowsAttributes = $Entry.ExternalAttributes -band 0xFFFF
    return (($windowsAttributes -band [int][IO.FileAttributes]::ReparsePoint) -ne 0)
}

function Get-NormalizedEntryPath {
    param([Parameter(Mandatory)][string]$EntryName)

    if ([string]::IsNullOrWhiteSpace($EntryName)) { throw 'Nom de membre vide.' }
    if ($EntryName.IndexOf([char]0) -ge 0) { throw 'Nom contenant un octet nul.' }

    $normalized = $EntryName.Replace('\', '/')
    if ($normalized.StartsWith('/') -or $normalized.StartsWith('//') -or $normalized -match '^[A-Za-z]:') {
        throw 'Chemin absolu interdit.'
    }
    if ($normalized.Contains(':')) { throw 'Deux-points interdit dans un chemin de membre.' }

    $isDirectory = $normalized.EndsWith('/')
    $trimmed = $normalized.TrimEnd('/')
    if (-not $trimmed) { throw 'Chemin racine vide interdit.' }

    $segments = $trimmed.Split('/')
    if ($segments | Where-Object { $_ -eq '..' }) { throw 'Traversée de chemin interdite.' }
    if ($segments | Where-Object { $_ -eq '.' -or $_ -eq '' }) { throw 'Segment de chemin vide ou relatif interdit.' }
    foreach ($segment in $segments) {
        if ($segment -match '[<>"|?*\x00-\x1F]') { throw 'Caractère de nom de fichier interdit.' }
        if ($segment.TrimEnd(' ', '.') -ne $segment) { throw 'Espace ou point final interdit dans un segment.' }
        $stem = [IO.Path]::GetFileNameWithoutExtension($segment)
        if ($stem -match '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$') {
            throw 'Nom de périphérique Windows réservé.'
        }
    }

    [pscustomobject]@{
        path = ($segments -join '/')
        is_directory = $isDirectory
    }
}

function Get-SafeDestinationPath {
    param(
        [Parameter(Mandatory)][string]$ExtractionRoot,
        [Parameter(Mandatory)][string]$NormalizedPath
    )

    $root = [IO.Path]::GetFullPath($ExtractionRoot)
    $rootWithSeparator = $root.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) +
        [IO.Path]::DirectorySeparatorChar
    $relative = $NormalizedPath.Replace('/', [IO.Path]::DirectorySeparatorChar)
    $destination = [IO.Path]::GetFullPath((Join-Path $root $relative))
    $comparison = if ($script:IsWindowsPlatform) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
    if (-not $destination.StartsWith($rootWithSeparator, $comparison)) {
        throw 'Le chemin résolu sort du dossier temporaire.'
    }
    return $destination
}

function Write-JsonAtomic {
    param(
        [Parameter(Mandatory)]$Value,
        [Parameter(Mandatory)][string]$Path
    )

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

function Copy-StreamBounded {
    param(
        [Parameter(Mandatory)][IO.Stream]$InputStream,
        [Parameter(Mandatory)][IO.Stream]$OutputStream,
        [Parameter(Mandatory)][long]$ExpectedBytes,
        [Parameter(Mandatory)][long]$MaximumBytes
    )

    $buffer = New-Object byte[] (1MB)
    $written = 0L
    while (($read = $InputStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
        $written += $read
        if ($written -gt $ExpectedBytes -or $written -gt $MaximumBytes) {
            throw 'Le flux décompressé dépasse la taille déclarée ou autorisée.'
        }
        $OutputStream.Write($buffer, 0, $read)
    }
    if ($written -ne $ExpectedBytes) {
        throw 'Le flux décompressé ne correspond pas à la taille déclarée.'
    }
    return $written
}

function Test-AssetArchive {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ArchivePath,
        [Parameter(Mandatory)][string]$ReportPath,
        [string]$TemporaryRoot = ([IO.Path]::GetTempPath()),
        [ValidateRange(1, 200000)][int]$MaxEntries = 100000,
        [long]$MaxArchiveBytes = 8GB,
        [long]$MaxEntryBytes = 4GB,
        [long]$MaxTotalBytes = 20GB,
        [ValidateRange(1, 10000)][int]$MaxCompressionRatio = 200
    )

    $archiveFullPath = [IO.Path]::GetFullPath($ArchivePath)
    if ($MaxArchiveBytes -le 0 -or $MaxEntryBytes -le 0 -or $MaxTotalBytes -le 0) {
        throw 'Les limites de taille doivent être strictement positives.'
    }
    if (-not (Test-Path -LiteralPath $archiveFullPath -PathType Leaf)) {
        throw "Archive introuvable : $ArchivePath"
    }

    $archiveInfo = Get-Item -LiteralPath $archiveFullPath
    $archiveSizeBytes = $archiveInfo.Length
    $archiveSha256 = $null
    $findings = [Collections.Generic.List[object]]::new()
    $inventory = [Collections.Generic.List[object]]::new()
    $entryPlans = [Collections.Generic.List[object]]::new()
    $seenPaths = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $totalBytes = 0L
    $requiresQuarantine = $false
    $rejected = $false
    $extractionPerformed = $false
    $temporaryExtractionRemoved = $true
    $temporaryId = ''
    $archive = $null
    $archiveStream = $null
    $extractionRoot = ''
    $archiveTooLarge = $archiveInfo.Length -gt $MaxArchiveBytes

    if ($archiveTooLarge) {
        $findings.Add((New-Finding reject archive_too_large "Archive supérieure à $MaxArchiveBytes octets avant ouverture."))
        $rejected = $true
    }

    if ([IO.Path]::GetExtension($archiveFullPath) -ine '.zip') {
        $findings.Add((New-Finding reject unsupported_archive 'Seules les archives ZIP sont admises par cet outil.'))
        $rejected = $true
    }

    try {
        if (-not $archiveTooLarge) {
            $archiveStream = [IO.File]::Open(
                $archiveFullPath,
                [IO.FileMode]::Open,
                [IO.FileAccess]::Read,
                [IO.FileShare]::None
            )
            $archiveSizeBytes = $archiveStream.Length
            if ($archiveSizeBytes -gt $MaxArchiveBytes) {
                $findings.Add((New-Finding reject archive_too_large "Archive supérieure à $MaxArchiveBytes octets après verrouillage."))
                $archiveTooLarge = $true
                $rejected = $true
            }
            else {
                $sha256 = [Security.Cryptography.SHA256]::Create()
                try {
                    $archiveSha256 = ([BitConverter]::ToString($sha256.ComputeHash($archiveStream))).Replace('-', '').ToLowerInvariant()
                }
                finally {
                    $sha256.Dispose()
                }
                $archiveStream.Position = 0
            }
        }

        if (-not $rejected) {
            $archive = [IO.Compression.ZipArchive]::new($archiveStream, [IO.Compression.ZipArchiveMode]::Read, $true)
            if ($archive.Entries.Count -gt $MaxEntries) {
                $findings.Add((New-Finding reject too_many_entries "L'archive dépasse la limite de $MaxEntries membres."))
                $rejected = $true
            }

            foreach ($entry in $archive.Entries) {
                $normalized = $null
                try {
                    $normalized = Get-NormalizedEntryPath $entry.FullName
                }
                catch {
                    $findings.Add((New-Finding reject unsafe_path $_.Exception.Message $entry.FullName))
                    $rejected = $true
                    continue
                }

                if (-not $seenPaths.Add($normalized.path)) {
                    $findings.Add((New-Finding reject duplicate_path 'Chemin dupliqué ou collision de casse.' $normalized.path))
                    $rejected = $true
                    continue
                }

                if (Test-SymbolicLinkEntry $entry) {
                    $findings.Add((New-Finding reject symbolic_link 'Lien symbolique ou point de réanalyse interdit.' $normalized.path))
                    $rejected = $true
                    continue
                }

                if ($normalized.is_directory) {
                    $entryPlans.Add([pscustomobject]@{
                        entry = $entry
                        path = $normalized.path
                        is_directory = $true
                        category = 'directory'
                        disposition = 'accepted'
                    })
                    continue
                }

                if ($entry.Length -gt $MaxEntryBytes) {
                    $findings.Add((New-Finding reject entry_too_large "Membre supérieur à $MaxEntryBytes octets." $normalized.path))
                    $rejected = $true
                }
                $totalBytes += $entry.Length
                if ($totalBytes -gt $MaxTotalBytes) {
                    $findings.Add((New-Finding reject archive_too_large "Taille décompressée supérieure à $MaxTotalBytes octets." $normalized.path))
                    $rejected = $true
                }

                if ($entry.Length -gt 1MB) {
                    if ($entry.CompressedLength -eq 0) {
                        $findings.Add((New-Finding reject suspicious_compression 'Taux de compression infini pour un membre non vide.' $normalized.path))
                        $rejected = $true
                    }
                    elseif (($entry.Length / [double]$entry.CompressedLength) -gt $MaxCompressionRatio) {
                        $findings.Add((New-Finding reject suspicious_compression "Taux de compression supérieur à $MaxCompressionRatio." $normalized.path))
                        $rejected = $true
                    }
                }

                $classification = Get-EntryClassification $normalized.path
                switch ($classification.disposition) {
                    'rejected' {
                        $findings.Add((New-Finding reject blocked_file 'Extension exécutable, script, projet moteur ou extension inattendue.' $normalized.path))
                        $rejected = $true
                    }
                    'quarantined' {
                        $findings.Add((New-Finding quarantine manual_review 'Format complexe ou archive imbriquée à examiner séparément sans auto-exécution.' $normalized.path))
                        $requiresQuarantine = $true
                    }
                }

                $entryPlans.Add([pscustomobject]@{
                    entry = $entry
                    path = $normalized.path
                    is_directory = $false
                    category = $classification.category
                    disposition = $classification.disposition
                })
            }

            if ($archive.Entries.Count -eq 0) {
                $findings.Add((New-Finding reject empty_archive 'Archive vide.'))
                $rejected = $true
            }
        }

        if (-not $rejected) {
            if (-not (Test-Path -LiteralPath $TemporaryRoot -PathType Container)) {
                $null = New-Item -ItemType Directory -Path $TemporaryRoot -Force
            }
            $temporaryId = 'asset-quarantine-' + [guid]::NewGuid().ToString('N')
            $extractionRoot = Join-Path ([IO.Path]::GetFullPath($TemporaryRoot)) $temporaryId
            $null = New-Item -ItemType Directory -Path $extractionRoot
            $temporaryExtractionRemoved = $false

            foreach ($plan in $entryPlans) {
                $destination = Get-SafeDestinationPath $extractionRoot $plan.path
                if ($plan.is_directory) {
                    $null = New-Item -ItemType Directory -Path $destination -Force
                    continue
                }

                $parent = Split-Path -Parent $destination
                if (-not (Test-Path -LiteralPath $parent)) {
                    $null = New-Item -ItemType Directory -Path $parent -Force
                }

                $input = $null
                $output = $null
                try {
                    $input = $plan.entry.Open()
                    $output = [IO.File]::Open($destination, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
                    $null = Copy-StreamBounded -InputStream $input -OutputStream $output `
                        -ExpectedBytes $plan.entry.Length -MaximumBytes $MaxEntryBytes
                }
                finally {
                    if ($output) { $output.Dispose() }
                    if ($input) { $input.Dispose() }
                }

                $actualLength = (Get-Item -LiteralPath $destination).Length
                if ($actualLength -ne $plan.entry.Length) {
                    throw "Taille extraite incohérente pour $($plan.path)."
                }

                $inventory.Add([pscustomobject][ordered]@{
                    path = $plan.path
                    category = $plan.category
                    disposition = $plan.disposition
                    size_bytes = $actualLength
                    compressed_size_bytes = $plan.entry.CompressedLength
                    sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $destination).Hash.ToLowerInvariant()
                })
            }
            $extractionPerformed = $true
        }
    }
    catch {
        $findings.Add((New-Finding reject archive_read_error 'Lecture ou extraction ZIP impossible ; archive corrompue ou non conforme.'))
        $rejected = $true
    }
    finally {
        if ($archive) { $archive.Dispose() }
        if ($archiveStream) { $archiveStream.Dispose() }
        if ($extractionRoot -and (Test-Path -LiteralPath $extractionRoot)) {
            Remove-Item -LiteralPath $extractionRoot -Recurse -Force
        }
        $temporaryExtractionRemoved = -not ($extractionRoot -and (Test-Path -LiteralPath $extractionRoot))
    }

    $decision = if ($rejected) { 'rejected' } elseif ($requiresQuarantine) { 'quarantined' } else { 'accepted' }
    if ($decision -eq 'accepted') {
        $findings.Add((New-Finding info accepted 'Archive de données admise par les contrôles automatiques.'))
    }

    $report = [pscustomobject][ordered]@{
        schema_version = 1
        created_utc = [DateTime]::UtcNow.ToString('o')
        archive = [pscustomobject][ordered]@{
            name = $archiveInfo.Name
            size_bytes = $archiveSizeBytes
            sha256 = $archiveSha256
        }
        policy = [pscustomobject][ordered]@{
            max_archive_bytes = $MaxArchiveBytes
            max_entries = $MaxEntries
            max_entry_bytes = $MaxEntryBytes
            max_total_uncompressed_bytes = $MaxTotalBytes
            max_compression_ratio = $MaxCompressionRatio
        }
        decision = $decision
        extraction = [pscustomobject][ordered]@{
            performed = $extractionPerformed
            temporary_id = $temporaryId
            removed = $temporaryExtractionRemoved
        }
        totals = [pscustomobject][ordered]@{
            entries = $entryPlans.Count
            files = $inventory.Count
            uncompressed_bytes_declared = $totalBytes
        }
        findings = @($findings)
        inventory = @($inventory)
    }

    Write-JsonAtomic $report $ReportPath
    return $report
}

Export-ModuleMember -Function Test-AssetArchive
