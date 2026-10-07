param(
    [string]$Zip,
    [string]$Source,

    [string]$Repo = "Chazammm/atm10-cc-doom",
    [string]$Tag = "cc-music-library-v1",
    [string]$Branch = "cc-music-player",

    [switch]$Normalize,
    [switch]$KeepWork,
    [string]$CacheDir = "$env:LOCALAPPDATA\CCMusic\library-cache"
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
        & $winget.Source install --id Python.Python.3.13 -e --source winget --scope user --accept-package-agreements --accept-source-agreements | Out-Host
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

function Run([string]$Exe, [string[]]$CommandArgs) {
    & $Exe @CommandArgs
    if ($LASTEXITCODE -ne 0) {
        throw ("Command failed ({0}): {1} {2}" -f $LASTEXITCODE, $Exe, ($CommandArgs -join " "))
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

$pythonInfo = @(Ensure-Python) | Where-Object { $_ -and $_.PSObject.Properties.Name -contains "Exe" } | Select-Object -Last 1
if (-not $pythonInfo) { throw "Python setup completed but no interpreter descriptor was returned." }
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
$out = Join-Path $CacheDir "sqsh2"
$converter = Join-Path $work "convert_to_sqsh48.py"
New-Item -ItemType Directory -Force -Path $src,$out,$CacheDir | Out-Null

# Correctness beats stale conversion-cache reuse. The old builder could leave
# removed or previously encoded songs in this folder, which then got uploaded
# into a freshly recreated release. Start every library build from a clean
# generated-output directory; source audio is still copied only to the temp
# work folder and never uploaded directly.
if (Test-Path $out -PathType Container) {
    Get-ChildItem -LiteralPath $out -Force -ErrorAction SilentlyContinue |
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
}


function Get-SqshMeta([string]$Path) {
    $bytes = [IO.File]::ReadAllBytes($Path)
    $sep = -1
    for ($i = 0; $i -lt ($bytes.Length - 1); $i++) {
        if ($bytes[$i] -eq 10 -and $bytes[$i + 1] -eq 10) {
            $sep = $i
            break
        }
    }
    if ($sep -lt 0) { throw "Invalid SQSH header: $Path" }

    $text = [Text.Encoding]::ASCII.GetString($bytes, 0, $sep)
    $lines = @($text -split [char]10)
    $magic = $lines[0].Trim()
    $values = @{}
    for ($j = 1; $j -lt $lines.Count; $j++) {
        $line = $lines[$j].Trim()
        if ($line -match '^([^=]+)=(\d+)$') {
            $values[$matches[1]] = [int64]$matches[2]
        }
    }

    if (-not $values.ContainsKey("rate") -or -not $values.ContainsKey("audio")) {
        throw "Incomplete SQSH header: $Path"
    }

    $channels = 1
    if ($magic -eq "SQSH2") { $channels = 2 }
    elseif ($magic -ne "SQSH1") { throw "Unsupported SQSH format '$magic': $Path" }

    return [pscustomobject]@{
        Format = $magic
        Rate = [int]$values["rate"]
        Channels = $channels
        AudioBytes = [int64]$values["audio"]
    }
}

try {
    Write-Host ""
    Write-Host "=== CC-Music Library Builder ===" -ForegroundColor Cyan
    Write-Host ("Source     : " + $inputPath)
    Write-Host ("Input mode : " + $inputMode)
    Write-Host ("Work folder: " + $work)
    Write-Host ("SQSH cache : " + $out)
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

    $raw = "https://raw.githubusercontent.com/$Repo/$Branch/cc-music/tools/convert_to_sqsh48.py?v=3.7.0"
    Write-Host "Downloading current Profile A+ converter..." -ForegroundColor Cyan
    Invoke-WebRequest -UseBasicParsing -Uri $raw -OutFile $converter

    $converterArgs = @($converter, $src, "--output", $out, "--max-file-bytes", "15728640")
    if ($Normalize) { $converterArgs += "--normalize" }

    Write-Host ""
    Write-Host "Converting locally to 48 kHz SQSH2 / Profile A+..." -ForegroundColor Cyan
    $pythonArgs = @($pythonPrefix) + @($converterArgs)
    Write-Host ("Python command: {0} {1}" -f $python, ($pythonArgs -join " ")) -ForegroundColor DarkGray
    Run $python $pythonArgs

    $files = @(Get-ChildItem -Path $out -Recurse -File -Filter "*.sqsh" | Sort-Object FullName)
    if ($files.Count -eq 0) { throw "Converter produced no .sqsh files." }

    # Group normal files and .partNNN files back into logical tracks.
    # Long albums remain one track in the UI even though GitHub/CC:Tweaked
    # streams them through several <=15 MiB assets.
    $stage = Join-Path $work "release"
    New-Item -ItemType Directory -Force -Path $stage | Out-Null
    $used = @{}
    $tracks = @()
    $groups = @{}

    foreach ($file in $files) {
        $stem = [IO.Path]::GetFileNameWithoutExtension($file.Name)
        $logicalStem = $stem
        $partNo = 1
        $isPart = $false
        if ($stem -match '^(.*)\.part(\d{3})$') {
            $logicalStem = $matches[1]
            $partNo = [int]$matches[2]
            $isPart = $true
        }

        $groupKey = $file.DirectoryName + "|" + $logicalStem
        if (-not $groups.ContainsKey($groupKey)) {
            $groups[$groupKey] = [ordered]@{
                Stem = $logicalStem
                Items = @()
            }
        }
        $groups[$groupKey].Items += [pscustomobject]@{
            File = $file
            PartNo = $partNo
            IsPart = $isPart
        }
    }

    foreach ($group in ($groups.Values | Sort-Object Stem)) {
        $safe = ($group.Stem -replace '[^A-Za-z0-9 _().,&+''\-]', '_').Trim()
        if ([string]::IsNullOrWhiteSpace($safe)) { $safe = "track" }

        $logicalName = $safe + ".sqsh"
        $n = 2
        while ($used.ContainsKey($logicalName.ToLowerInvariant())) {
            $logicalName = "{0} ({1}).sqsh" -f $safe,$n
            $n++
        }
        $used[$logicalName.ToLowerInvariant()] = $true
        $logicalBase = [IO.Path]::GetFileNameWithoutExtension($logicalName)

        $items = @($group.Items | Sort-Object PartNo)
        $manifestParts = @()
        $totalSize = [int64]0
        $totalAudioBytes = [int64]0
        $firstMeta = $null

        for ($p = 0; $p -lt $items.Count; $p++) {
            $item = $items[$p]
            $meta = Get-SqshMeta $item.File.FullName
            if (-not $firstMeta) { $firstMeta = $meta }

            if ($items.Count -eq 1) {
                $assetName = $logicalName
            } else {
                $assetName = "{0}.part{1:D3}.sqsh" -f $logicalBase,($p + 1)
            }

            $dst = Join-Path $stage $assetName
            Copy-Item -LiteralPath $item.File.FullName -Destination $dst
            $size = (Get-Item $dst).Length
            if ($size -gt 16MB) {
                throw ("Generated asset '{0}' is still above 16 MiB: {1:N1} MiB" -f $assetName, ($size/1MB))
            }

            $encoded = [Uri]::EscapeDataString($assetName).Replace("%2F","/")
            $url = "https://github.com/$Repo/releases/download/$Tag/$encoded"
            $totalSize += $size
            $totalAudioBytes += $meta.AudioBytes

            $manifestParts += [ordered]@{
                name = $assetName
                size = $size
                audio_bytes = $meta.AudioBytes
                url = $url
            }
        }

        $duration = [double]$totalAudioBytes * 8.0 / [double]$firstMeta.Rate

        # The converter writes a tiny sidecar next to each logical track with
        # ffprobe title/artist/album metadata. Preserve it in library.json so
        # the in-game UI and online synced-lyrics matcher do not have to guess
        # from YouTube-style filenames.
        $sourceMeta = $null
        $sidecar = Join-Path $items[0].File.DirectoryName ($group.Stem + ".ccmeta.json")
        if (Test-Path $sidecar -PathType Leaf) {
            try {
                $sourceMeta = Get-Content -LiteralPath $sidecar -Raw | ConvertFrom-Json
            } catch {
                Write-Warning ("Could not read metadata sidecar for {0}: {1}" -f $group.Stem,$_.Exception.Message)
            }
        }

        $displayTitle = $logicalBase
        $artist = ""
        $album = ""
        if ($sourceMeta) {
            if ($sourceMeta.title -and -not [string]::IsNullOrWhiteSpace([string]$sourceMeta.title)) {
                $displayTitle = [string]$sourceMeta.title
            }
            if ($sourceMeta.artist) { $artist = ([string]$sourceMeta.artist).Trim() }
            if ($sourceMeta.album) { $album = ([string]$sourceMeta.album).Trim() }
        }

        $track = [ordered]@{
            name = $logicalName
            title = $displayTitle
            size = $totalSize
            duration = [Math]::Round($duration, 6)
            format = $firstMeta.Format
            rate = $firstMeta.Rate
            channels = $firstMeta.Channels
        }
        if (-not [string]::IsNullOrWhiteSpace($artist)) { $track["artist"] = $artist }
        if (-not [string]::IsNullOrWhiteSpace($album)) { $track["album"] = $album }

        if ($manifestParts.Count -eq 1) {
            $track.url = $manifestParts[0].url
        } else {
            $track.segmented = $true
            $track.parts = $manifestParts
            Write-Host ("Segmented: {0} -> {1} HTTP-safe parts" -f $logicalBase,$manifestParts.Count) -ForegroundColor Yellow
        }

        $tracks += $track
    }

    $manifest = [ordered]@{
        version = 2
        format = "CC-Music Library"
        segmented_tracks = $true
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

    $total = [int64]0
    foreach ($trackEntry in $tracks) {
        if ($trackEntry.Contains("size")) {
            $total += [int64]$trackEntry["size"]
        }
    }
    Write-Host ""
    Write-Host ("Converted: {0} track(s), {1:N1} MiB total" -f $tracks.Count, ($total/1MB)) -ForegroundColor Green

    Write-Host ""
    Write-Host "Replacing GitHub music-library release..." -ForegroundColor Cyan

    # GitHub CLI writes "release not found" to stderr. With Windows
    # PowerShell 5.1 + ErrorActionPreference=Stop that stderr becomes a
    # terminating NativeCommandError even though "not found" is expected here.
    # Run the existence probe in a child process and use only its exit code.
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $gh
    $psi.Arguments = ('release view "{0}" --repo "{1}"' -f $Tag, $Repo)
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $probe = [System.Diagnostics.Process]::Start($psi)
    $probe.StandardOutput.ReadToEnd() | Out-Null
    $probe.StandardError.ReadToEnd() | Out-Null
    $probe.WaitForExit()
    $releaseExists = ($probe.ExitCode -eq 0)
    $probe.Dispose()

    if ($releaseExists) {
        Write-Host "Removing previous library release/tag so old low-quality tracks disappear..."
        Run $gh @("release","delete",$Tag,"--repo",$Repo,"--yes","--cleanup-tag")
    }

    Run $gh @("release","create",$Tag,"--repo",$Repo,"--title","CC-Music Library","--notes","CC-Music 3.7 / Profile A+ / 48 kHz / SQSH2 stereo library with track metadata.")

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
