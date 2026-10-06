param(
    [string]$Zip,
    [string]$Source,

    [string]$Repo = "Chazammm/atm10-cc-doom",
    [string]$Tag = "cc-music-library-v1",
    [string]$Branch = "cc-music-player",

    [switch]$Normalize,
    [switch]$KeepWork
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Find-Cmd([string]$Name) {
    $cmd = Get-Command $Name -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    if ($Name -eq "ffmpeg" -or $Name -eq "ffprobe") {
        $candidates = @()

        if ($env:LOCALAPPDATA) {
            $link = Join-Path $env:LOCALAPPDATA ("Microsoft\WinGet\Links\" + $Name + ".exe")
            if (Test-Path $link -PathType Leaf) { $candidates += (Get-Item $link) }

            $packages = Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Packages"
            if (Test-Path $packages -PathType Container) {
                $candidates += @(Get-ChildItem -Path $packages -Filter ($Name + ".exe") -File -Recurse -ErrorAction SilentlyContinue)
            }
        }

        if ($env:ProgramFiles) {
            $candidates += @(Get-ChildItem -Path $env:ProgramFiles -Filter ($Name + ".exe") -File -Recurse -ErrorAction SilentlyContinue |
                Where-Object { $_.FullName -match "ffmpeg|Gyan" })
        }

        $found = $candidates | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($found) {
            Write-Host ("Found {0} outside PATH: {1}" -f $Name, $found.FullName) -ForegroundColor Yellow
            return $found.FullName
        }
    }

    return $null
}

function Need-Cmd([string]$Name) {
    $found = Find-Cmd $Name
    if (-not $found) { throw "Missing '$Name'." }
    return $found
}

function Ensure-FFmpeg {
    $ffmpeg = Find-Cmd "ffmpeg"
    $ffprobe = Find-Cmd "ffprobe"
    if ($ffmpeg -and $ffprobe) {
        return @($ffmpeg, $ffprobe)
    }

    # No system FFmpeg? Bootstrap a private portable build for CC-Music.
    # Nothing is installed globally and no admin rights are required.
    $toolRoot = Join-Path $env:LOCALAPPDATA "CCMusic\ffmpeg"
    $ffmpegExe = Get-ChildItem -Path $toolRoot -Filter "ffmpeg.exe" -File -Recurse -ErrorAction SilentlyContinue |
        Select-Object -First 1
    $ffprobeExe = Get-ChildItem -Path $toolRoot -Filter "ffprobe.exe" -File -Recurse -ErrorAction SilentlyContinue |
        Select-Object -First 1

    if ($ffmpegExe -and $ffprobeExe) {
        Write-Host ("Using portable FFmpeg: " + $ffmpegExe.FullName) -ForegroundColor Yellow
        return @($ffmpegExe.FullName, $ffprobeExe.FullName)
    }

    Write-Host "FFmpeg was not found. Downloading a private portable build..." -ForegroundColor Cyan
    New-Item -ItemType Directory -Force -Path $toolRoot | Out-Null
    $zipPath = Join-Path $env:TEMP "ccmusic-ffmpeg.zip"
    $downloadUrl = "https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip"

    try {
        Invoke-WebRequest -UseBasicParsing -Uri $downloadUrl -OutFile $zipPath
    } catch {
        throw "Could not download portable FFmpeg: $($_.Exception.Message)"
    }

    Write-Host "Extracting portable FFmpeg..." -ForegroundColor Cyan
    if (Test-Path $toolRoot) {
        Get-ChildItem -Path $toolRoot -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    }
    Expand-Archive -LiteralPath $zipPath -DestinationPath $toolRoot -Force
    Remove-Item -LiteralPath $zipPath -Force -ErrorAction SilentlyContinue

    $ffmpegExe = Get-ChildItem -Path $toolRoot -Filter "ffmpeg.exe" -File -Recurse -ErrorAction SilentlyContinue |
        Select-Object -First 1
    $ffprobeExe = Get-ChildItem -Path $toolRoot -Filter "ffprobe.exe" -File -Recurse -ErrorAction SilentlyContinue |
        Select-Object -First 1

    if (-not $ffmpegExe -or -not $ffprobeExe) {
        throw "Portable FFmpeg download completed, but ffmpeg.exe/ffprobe.exe were not found."
    }

    Write-Host ("Portable FFmpeg ready: " + $ffmpegExe.FullName) -ForegroundColor Green
    return @($ffmpegExe.FullName, $ffprobeExe.FullName)
}


function Test-Python([string]$Exe, [string[]]$Prefix = @()) {
    if (-not $Exe) { return $false }
    try {
        & $Exe @Prefix -c "import sys; assert sys.version_info >= (3,9); print(sys.executable)" *> $null
        return ($LASTEXITCODE -eq 0)
    } catch {
        return $false
    }
}

function Ensure-Python {
    # Ignore Microsoft's WindowsApps python.exe placeholder: Get-Command can
    # resolve it even though no real Python interpreter is installed.
    $pythonCmd = Get-Command python.exe -ErrorAction SilentlyContinue
    if ($pythonCmd -and $pythonCmd.Source -notmatch "\\Microsoft\\WindowsApps\\") {
        if (Test-Python $pythonCmd.Source) {
            return [pscustomobject]@{ Exe = $pythonCmd.Source; Prefix = @() }
        }
    }

    # The Python Launcher is common on Windows even when "python" is not on PATH.
    $pyCmd = Get-Command py.exe -ErrorAction SilentlyContinue
    if ($pyCmd) {
        if (Test-Python $pyCmd.Source @("-3")) {
            Write-Host ("Using Python launcher: " + $pyCmd.Source) -ForegroundColor Yellow
            return [pscustomobject]@{ Exe = $pyCmd.Source; Prefix = @("-3") }
        }
    }

    # Look in normal per-user Python installs.
    $pythonRoots = @()
    if ($env:LOCALAPPDATA) { $pythonRoots += (Join-Path $env:LOCALAPPDATA "Programs\Python") }
    if ($env:ProgramFiles) { $pythonRoots += (Join-Path $env:ProgramFiles "Python*") }

    $found = @()
    foreach ($root in $pythonRoots) {
        $found += @(Get-ChildItem -Path $root -Filter "python.exe" -File -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -notmatch "\\Microsoft\\WindowsApps\\" })
    }
    foreach ($item in ($found | Sort-Object LastWriteTime -Descending)) {
        if (Test-Python $item.FullName) {
            Write-Host ("Found Python outside PATH: " + $item.FullName) -ForegroundColor Yellow
            return [pscustomobject]@{ Exe = $item.FullName; Prefix = @() }
        }
    }

    # Last resort: install a real per-user Python from the WinGet community
    # source. --source winget deliberately avoids the Microsoft Store source.
    $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
    if ($winget) {
        Write-Host "Real Python was not found. Installing Python 3.13 for the current user..." -ForegroundColor Cyan
        & $winget.Source install --id Python.Python.3.13 -e --source winget --scope user --accept-package-agreements --accept-source-agreements
        if ($LASTEXITCODE -eq 0) {
            $base = Join-Path $env:LOCALAPPDATA "Programs\Python"
            $after = @(Get-ChildItem -Path $base -Filter "python.exe" -File -Recurse -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime -Descending)
            foreach ($item in $after) {
                if (Test-Python $item.FullName) {
                    Write-Host ("Python ready: " + $item.FullName) -ForegroundColor Green
                    return [pscustomobject]@{ Exe = $item.FullName; Prefix = @() }
                }
            }
        }
    }

    throw "A real Python 3.9+ interpreter could not be found or installed. The WindowsApps python.exe entry is only a Store placeholder."
}

function Run([string]$Exe, [string[]]$Args) {
    & $Exe @Args
    if ($LASTEXITCODE -ne 0) {
        throw ("Command failed ({0}): {1} {2}" -f $LASTEXITCODE, $Exe, ($Args -join " "))
    }
}

if (-not $Zip -and -not $Source) {
    throw "Provide either -Zip <file.zip> or -Source <folder>."
}
if ($Zip -and $Source) {
    throw "Use only one input: -Zip or -Source."
}

$inputPath = $Zip
$inputMode = "zip"
if ($Source) {
    $inputPath = $Source
    $inputMode = "folder"
}

$inputPath = (Resolve-Path $inputPath).Path
if ($inputMode -eq "zip" -and -not (Test-Path $inputPath -PathType Leaf)) {
    throw "ZIP not found: $inputPath"
}
if ($inputMode -eq "folder" -and -not (Test-Path $inputPath -PathType Container)) {
    throw "Source folder not found: $inputPath"
}

$pythonInfo = Ensure-Python
$python = $pythonInfo.Exe
$pythonPrefix = @($pythonInfo.Prefix)
$ff = Ensure-FFmpeg
$ffmpeg = $ff[0]
$ffprobe = $ff[1]
$gh = Need-Cmd "gh"

# Make the resolved/private FFmpeg tools visible to the Python converter.
$ffmpegDir = Split-Path $ffmpeg -Parent
$ffprobeDir = Split-Path $ffprobe -Parent
$extraPath = @($ffmpegDir, $ffprobeDir) | Select-Object -Unique
$env:PATH = (($extraPath -join [IO.Path]::PathSeparator) + [IO.Path]::PathSeparator + $env:PATH)

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
    Write-Host ("Source     : " + $inputPath)
    Write-Host ("Input mode : " + $inputMode)
    Write-Host ("Work folder: " + $work)
    Write-Host ("Release    : " + $Repo + " / " + $Tag)
    Write-Host ""

    if ($inputMode -eq "zip") {
        Write-Host "Extracting MP3/audio ZIP..." -ForegroundColor Cyan
        Expand-Archive -LiteralPath $inputPath -DestinationPath $src -Force
    } else {
        Write-Host "Copying source audio folder..." -ForegroundColor Cyan
        Copy-Item -Path (Join-Path $inputPath "*") -Destination $src -Recurse -Force
    }

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
    Run $python (@($pythonPrefix) + $args)

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
    $manifestJson = $manifest | ConvertTo-Json -Depth 8
    [IO.File]::WriteAllText($manifestPath, $manifestJson, (New-Object Text.UTF8Encoding($false)))

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
    Write-Host "The original audio never left your PC; only the converted CC-Music files were uploaded." -ForegroundColor DarkGray
}
finally {
    if ($KeepWork) {
        Write-Host ("Keeping work folder: " + $work) -ForegroundColor Yellow
    } elseif (Test-Path $work) {
        Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    }
}
