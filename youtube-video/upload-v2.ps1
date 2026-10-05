param(
    [string]$Source,
    [string]$Repo = "Chazammm/atm10-cc-doom",
    [string]$Tag = "agartha-v2"
)

$ErrorActionPreference = "Stop"

function Find-Source {
    param([string]$Requested)

    if ($Requested) {
        $p = (Resolve-Path $Requested).Path
        return $p
    }

    $candidates = @(
        (Get-Location).Path,
        (Join-Path $HOME "Downloads"),
        (Join-Path $HOME "Desktop")
    )

    foreach ($candidate in $candidates) {
        if (-not (Test-Path $candidate)) { continue }

        $zips = Get-ChildItem -Path $candidate -Filter "Agartha_V2_parts*.zip" -File -ErrorAction SilentlyContinue
        $parts = Get-ChildItem -Path $candidate -Filter "agartha-v2-part*.32vid" -File -ErrorAction SilentlyContinue

        if ($zips.Count -gt 0 -or $parts.Count -gt 0) {
            return $candidate
        }
    }

    throw "Could not find the V2 ZIPs/parts. Put them in Downloads, Desktop, the current folder, or pass -Source <folder>."
}

Write-Host ""
Write-Host "=== Agartha V2 automatic GitHub uploader ===" -ForegroundColor Cyan
Write-Host "Target: $Repo / release $Tag"
Write-Host ""

# Ensure GitHub CLI exists.
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    Write-Host "GitHub CLI (gh) is not installed." -ForegroundColor Yellow
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Write-Host "Installing GitHub CLI through winget..."
        winget install --id GitHub.cli --exact --source winget --accept-source-agreements --accept-package-agreements
        $env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
                    [Environment]::GetEnvironmentVariable("Path", "User")
    } else {
        throw "Install GitHub CLI from https://cli.github.com/ and run this script again."
    }
}

if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    throw "GitHub CLI was installed but is not visible yet. Close PowerShell, reopen it, and run this script again."
}

# Authenticate once. gh opens the browser/device flow when needed.
& gh auth status 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "One-time GitHub login required. Follow the browser/device prompt." -ForegroundColor Yellow
    & gh auth login --hostname github.com --git-protocol https --web
    if ($LASTEXITCODE -ne 0) { throw "GitHub login failed." }
}

$sourceDir = Find-Source $Source
Write-Host "Source folder: $sourceDir"

$temp = Join-Path ([IO.Path]::GetTempPath()) ("agartha-v2-upload-" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $temp | Out-Null

try {
    # Copy already-extracted parts.
    Get-ChildItem -Path $sourceDir -Filter "agartha-v2-part*.32vid" -File -ErrorAction SilentlyContinue |
        Copy-Item -Destination $temp -Force

    # Extract all ChatGPT ZIP packs automatically.
    $zips = Get-ChildItem -Path $sourceDir -Filter "Agartha_V2_parts*.zip" -File -ErrorAction SilentlyContinue |
        Sort-Object Name

    foreach ($zip in $zips) {
        Write-Host "Extracting $($zip.Name)..."
        Expand-Archive -Path $zip.FullName -DestinationPath $temp -Force
    }

    $files = @(Get-ChildItem -Path $temp -Filter "agartha-v2-part*.32vid" -File | Sort-Object Name)

    # Sometimes ZIPs contain a subfolder. Find recursively if required.
    if ($files.Count -ne 50) {
        $files = @(Get-ChildItem -Path $temp -Filter "agartha-v2-part*.32vid" -File -Recurse | Sort-Object Name)
    }

    if ($files.Count -ne 50) {
        throw "Expected 50 .32vid files but found $($files.Count). Make sure all 10 ZIP packs (01-05 through 46-50) are present."
    }

    # Verify names 01..50 before uploading.
    for ($i = 1; $i -le 50; $i++) {
        $expected = "agartha-v2-part{0:D2}.32vid" -f $i
        if (-not ($files.Name -contains $expected)) {
            throw "Missing $expected"
        }
    }

    $totalMiB = [Math]::Round((($files | Measure-Object Length -Sum).Sum / 1MB), 1)
    Write-Host ""
    Write-Host "Found all 50 parts ($totalMiB MiB)." -ForegroundColor Green

    # Create release if it does not already exist.
    & gh release view $Tag --repo $Repo *> $null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Creating GitHub Release '$Tag'..."
        & gh release create $Tag --repo $Repo --title "Agartha V2 CC:Tweaked Media" --notes "10 FPS maximum-quality 32vid media for the 143x81 CC:Tweaked monitor player." --latest=false
        if ($LASTEXITCODE -ne 0) { throw "Could not create GitHub release." }
    } else {
        Write-Host "Release '$Tag' already exists; existing matching assets will be replaced."
    }

    Write-Host ""
    Write-Host "Uploading all 50 files automatically. You can leave this window alone." -ForegroundColor Cyan

    # One gh invocation handles the whole list. --clobber makes reruns resumable.
    $arguments = @("release", "upload", $Tag)
    foreach ($file in $files) { $arguments += $file.FullName }
    $arguments += @("--repo", $Repo, "--clobber")

    & gh @arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Upload failed. Re-run the same script; --clobber will safely replace assets which already exist."
    }

    Write-Host ""
    Write-Host "Upload complete." -ForegroundColor Green
    Write-Host "Release URL: https://github.com/$Repo/releases/tag/$Tag"
    Write-Host ""
    Write-Host "In Minecraft, reinstall once:"
    Write-Host "wget run https://raw.githubusercontent.com/Chazammm/atm10-cc-doom/main/youtube-video/install.lua" -ForegroundColor White
    Write-Host "Then run: agartha-v2" -ForegroundColor White
}
finally {
    if (Test-Path $temp) {
        Remove-Item -Path $temp -Recurse -Force -ErrorAction SilentlyContinue
    }
}
