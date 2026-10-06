param(
    [Parameter(Mandatory=$true)]
    [string]$Zip,

    [string]$Repo = "Chazammm/atm10-cc-doom",
    [string]$Tag = "cc-music-library-v1",
    [string]$Branch = "cc-music-player",

    [switch]$Normalize,
    [switch]$KeepWork
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Need-Cmd([string]$Name) {
    $cmd = Get-Command $Name -ErrorAction SilentlyContinue
    if (-not $cmd) { throw "Missing '$Name' in PATH." }
    return $cmd.Source
}

function Run([string]$Exe, [string[]]$Args) {
    & $Exe @Args
    if ($LASTEXITCODE -ne 0) {
        throw ("Command failed ({0}): {1} {2}" -f $LASTEXITCODE, $Exe, ($Args -join " "))
    }
}

$Zip = (Resolve-Path $Zip).Path
if (-not (Test-Path $Zip -PathType Leaf)) { throw "ZIP not found: $Zip" }

$python = Need-Cmd "python"
$ffmpeg = Need-Cmd "ffmpeg"
$ffprobe = Need-Cmd "ffprobe"
$gh = Need-Cmd "gh"

Write-Host "Checking GitHub login..." -ForegroundColor Cyan
& $gh auth status *> $null
if ($LASTEXITCODE -ne 0) { throw "GitHub CLI is not logged in. Run: gh auth login" }

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$work = Join-Path $env:TEMP ("ccmusic-" + $stamp)
$src = Join-Path $work "source"
$out = Join-Path $work "sqsh2"
$converter = Join-Path $work "convert_to_sqsh48.py"
New-Item -ItemType Directory -Force -Path $src,$out | Out-Null

try {
    Write-Host ""
    Write-Host "=== CC-Music Library Builder ===" -ForegroundColor Cyan
    Write-Host ("Source ZIP : " + $Zip)
    Write-Host ("Work folder: " + $work)
    Write-Host ("Release    : " + $Repo + " / " + $Tag)
    Write-Host ""

    Write-Host "Extracting MP3/audio ZIP..." -ForegroundColor Cyan
    Expand-Archive -LiteralPath $Zip -DestinationPath $src -Force

    $audioExtensions = @(".mp3",".wav",".flac",".ogg",".opus",".m4a",".aac",".wma",".aiff",".aif")
    $sources = @(Get-ChildItem -Path $src -Recurse -File | Where-Object {
        $audioExtensions -contains $_.Extension.ToLowerInvariant()
    })
    if ($sources.Count -eq 0) { throw "No supported audio files were found in the ZIP." }

    Write-Host ("Found {0} source track(s)." -f $sources.Count) -ForegroundColor Green

    $raw = "https://raw.githubusercontent.com/$Repo/$Branch/cc-music/tools/convert_to_sqsh48.py?v=3.0.4"
    Write-Host "Downloading current Profile A+ converter..." -ForegroundColor Cyan
    Invoke-WebRequest -UseBasicParsing -Uri $raw -OutFile $converter

    $args = @($converter, $src, "--output", $out, "--overwrite")
    if ($Normalize) { $args += "--normalize" }

    Write-Host ""
    Write-Host "Converting locally to 48 kHz SQSH2 / Profile A+..." -ForegroundColor Cyan
    Run $python $args

    $files = @(Get-ChildItem -Path $out -Recurse -File -Filter "*.sqsh" | Sort-Object FullName)
    if ($files.Count -eq 0) { throw "Converter produced no .sqsh files." }

    # Flatten into release-safe unique names. Keep a deterministic collision suffix.
    $stage = Join-Path $work "release"
    New-Item -ItemType Directory -Force -Path $stage | Out-Null
    $used = @{}
    $tracks = @()
    $maxHttp = 16MB

    foreach ($file in $files) {
        $base = [IO.Path]::GetFileNameWithoutExtension($file.Name)
        $safe = ($base -replace '[^A-Za-z0-9 _().,&+''\-]', '_').Trim()
        if ([string]::IsNullOrWhiteSpace($safe)) { $safe = "track" }

        $name = $safe + ".sqsh"
        $n = 2
        while ($used.ContainsKey($name.ToLowerInvariant())) {
            $name = "{0} ({1}).sqsh" -f $safe,$n
            $n++
        }
        $used[$name.ToLowerInvariant()] = $true

        $dst = Join-Path $stage $name
        Copy-Item -LiteralPath $file.FullName -Destination $dst
        $size = (Get-Item $dst).Length

        if ($size -gt $maxHttp) {
            throw ("'{0}' is {1:N1} MiB, above the 16 MiB CC:Tweaked HTTP target. Remove/shorten that track or split it before upload." -f $name, ($size/1MB))
        }

        $display = [IO.Path]::GetFileNameWithoutExtension($name)
        $encodedName = [Uri]::EscapeDataString($name).Replace("%2F","/")
        $url = "https://github.com/$Repo/releases/download/$Tag/$encodedName"

        $tracks += [ordered]@{
            name = $name
            title = $display
            size = $size
            url = $url
        }
    }

    $manifest = [ordered]@{
        version = 1
        format = "CC-Music Library"
        created_utc = (Get-Date).ToUniversalTime().ToString("o")
        tag = $Tag
        profile = "A+"
        sample_rate = 48000
        preferred_format = "SQSH2 stereo"
        tracks = $tracks
    }

    $manifestPath = Join-Path $stage "library.json"
    $manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

    $total = ($tracks | Measure-Object -Property size -Sum).Sum
    Write-Host ""
    Write-Host ("Converted: {0} track(s), {1:N1} MiB total" -f $tracks.Count, ($total/1MB)) -ForegroundColor Green

    Write-Host ""
    Write-Host "Replacing GitHub music-library release..." -ForegroundColor Cyan

    & $gh release view $Tag --repo $Repo *> $null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Removing previous library release/tag so old low-quality tracks disappear..."
        & $gh release delete $Tag --repo $Repo --yes --cleanup-tag
        if ($LASTEXITCODE -ne 0) { throw "Could not remove old release '$Tag'." }
    }

    Run $gh @("release","create",$Tag,"--repo",$Repo,"--title","CC-Music Library","--notes","CC-Music 3.0 / Profile A+ / 48 kHz / SQSH2 stereo library.")

    $upload = @($manifestPath) + @(Get-ChildItem -Path $stage -File -Filter "*.sqsh" | Sort-Object Name | ForEach-Object { $_.FullName })

    # Small batches make retries much less painful.
    $batchSize = 12
    for ($i = 0; $i -lt $upload.Count; $i += $batchSize) {
        $end = [Math]::Min($i + $batchSize - 1, $upload.Count - 1)
        $batch = @($upload[$i..$end])
        Write-Host ("Uploading assets {0}-{1} / {2}..." -f ($i+1),($end+1),$upload.Count)
        Run $gh (@("release","upload",$Tag,"--repo",$Repo) + $batch)
    }

    Write-Host ""
    Write-Host "Upload complete." -ForegroundColor Green
    Write-Host ("Manifest: https://github.com/{0}/releases/download/{1}/library.json" -f $Repo,$Tag)
    Write-Host ""
    Write-Host "The original ZIP never left your PC; only the converted CC-Music files were uploaded." -ForegroundColor DarkGray
}
finally {
    if ($KeepWork) {
        Write-Host ("Keeping work folder: " + $work) -ForegroundColor Yellow
    } elseif (Test-Path $work) {
        Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    }
}
