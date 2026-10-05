param(
    [string]$Source,
    [string]$Repo = "Chazammm/atm10-cc-doom",
    [string]$Tag = "agartha-v2"
)

$ErrorActionPreference = "Stop"

function Find-Source {
    param([string]$Requested)

    if ($Requested) {
        return (Resolve-Path $Requested -ErrorAction Stop).Path
    }

    $candidates = @(
        (Get-Location).Path,
        (Join-Path $HOME "Downloads"),
        (Join-Path $HOME "Desktop")
    )

    foreach ($candidate in $candidates) {
        if (-not (Test-Path $candidate)) { continue }

        $zips = @(Get-ChildItem -Path $candidate -Filter "Agartha_V2_parts*.zip" -File -ErrorAction SilentlyContinue)
        $parts = @(Get-ChildItem -Path $candidate -Filter "agartha-v2-part*.32vid" -File -ErrorAction SilentlyContinue)

        if ($zips.Count -gt 0 -or $parts.Count -gt 0) {
            return $candidate
        }
    }

    throw "Could not find the V2 ZIPs/parts. Put them in Downloads, Desktop, the current folder, or pass -Source <folder>."
}

function Find-Gh {
    $cmd = Get-Command gh.exe -ErrorAction SilentlyContinue
    if (-not $cmd) { $cmd = Get-Command gh -ErrorAction SilentlyContinue }
    if ($cmd) { return $cmd.Source }

    $candidates = @(
        (Join-Path $env:ProgramFiles "GitHub CLI\gh.exe"),
        (Join-Path $env:LOCALAPPDATA "Programs\GitHub CLI\gh.exe"),
        (Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Links\gh.exe")
    )

    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path $candidate)) {
            return $candidate
        }
    }

    $wingetPackages = Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Packages"
    if (Test-Path $wingetPackages) {
        $found = Get-ChildItem -Path $wingetPackages -Filter "gh.exe" -File -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -match "GitHub\.cli" } |
            Select-Object -First 1
        if ($found) { return $found.FullName }
    }

    return $null
}

function Invoke-Gh-Probe {
    param(
        [string]$Gh,
        [string[]]$Arguments
    )

    $oldPreference = $ErrorActionPreference
    $ErrorActionPreference = "SilentlyContinue"
    try {
        & $Gh @Arguments *> $null
        return $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $oldPreference
    }
}

function Invoke-Gh-Interactive {
    param(
        [string]$Gh,
        [string[]]$Arguments
    )

    # gh writes normal status output to stderr. Windows PowerShell 5.1 may turn
    # this into NativeCommandError when ErrorActionPreference is Stop.
    $oldPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        & $Gh @Arguments
        return $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $oldPreference
    }
}

Write-Host ""
Write-Host "=== Agartha V2 automatic GitHub uploader ===" -ForegroundColor Cyan
Write-Host "Target: $Repo / release $Tag"
Write-Host ""

$gh = Find-Gh

if (-not $gh) {
    Write-Host "GitHub CLI (gh) was not found in PATH." -ForegroundColor Yellow

    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Write-Host "Installing/repairing GitHub CLI through winget..."

        $oldPreference = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        try {
            winget install --id GitHub.cli --exact --source winget --accept-source-agreements --accept-package-agreements
        }
        finally {
            $ErrorActionPreference = $oldPreference
        }

        $env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
                    [Environment]::GetEnvironmentVariable("Path", "User")

        $gh = Find-Gh
    } else {
        throw "GitHub CLI is not installed and winget is unavailable."
    }
}

if (-not $gh) {
    throw "GitHub CLI is installed but gh.exe could not be located. Close PowerShell, reopen it, and run this script again."
}

Write-Host "Using GitHub CLI: $gh" -ForegroundColor DarkGray

$authCode = Invoke-Gh-Probe -Gh $gh -Arguments @("auth", "status", "--hostname", "github.com")
if ($authCode -ne 0) {
    Write-Host ""
    Write-Host "One-time GitHub login required." -ForegroundColor Yellow
    Write-Host "A browser/device-login prompt will open." -ForegroundColor Yellow

    $loginCode = Invoke-Gh-Interactive -Gh $gh -Arguments @(
        "auth", "login",
        "--hostname", "github.com",
        "--git-protocol", "https",
        "--web"
    )

    if ($loginCode -ne 0) {
        throw "GitHub login failed (exit code $loginCode)."
    }

    $authCode = Invoke-Gh-Probe -Gh $gh -Arguments @("auth", "status", "--hostname", "github.com")
    if ($authCode -ne 0) {
        throw "GitHub login did not complete successfully."
    }
}

Write-Host "GitHub login OK." -ForegroundColor Green

$sourceDir = Find-Source $Source
Write-Host "Source folder: $sourceDir"

$temp = Join-Path ([IO.Path]::GetTempPath()) ("agartha-v2-upload-" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $temp -ErrorAction Stop | Out-Null

try {
    Get-ChildItem -Path $sourceDir -Filter "agartha-v2-part*.32vid" -File -ErrorAction SilentlyContinue |
        Copy-Item -Destination $temp -Force

    $zips = @(Get-ChildItem -Path $sourceDir -Filter "Agartha_V2_parts*.zip" -File -ErrorAction SilentlyContinue |
        Sort-Object Name)

    foreach ($zip in $zips) {
        Write-Host "Extracting $($zip.Name)..."
        Expand-Archive -Path $zip.FullName -DestinationPath $temp -Force
    }

    $files = @(Get-ChildItem -Path $temp -Filter "agartha-v2-part*.32vid" -File -Recurse | Sort-Object Name)

    if ($files.Count -ne 50) {
        throw "Expected 50 .32vid files but found $($files.Count). Make sure all 10 ZIP packs are present in $sourceDir."
    }

    for ($i = 1; $i -le 50; $i++) {
        $expected = "agartha-v2-part{0:D2}.32vid" -f $i
        if (-not ($files.Name -contains $expected)) {
            throw "Missing $expected"
        }
    }

    $totalMiB = [Math]::Round((($files | Measure-Object Length -Sum).Sum / 1MB), 1)
    Write-Host ""
    Write-Host "Found all 50 parts ($totalMiB MiB)." -ForegroundColor Green

    $releaseExists = (Invoke-Gh-Probe -Gh $gh -Arguments @("release", "view", $Tag, "--repo", $Repo)) -eq 0

    if (-not $releaseExists) {
        Write-Host "Creating GitHub Release '$Tag'..."

        $createCode = Invoke-Gh-Interactive -Gh $gh -Arguments @(
            "release", "create", $Tag,
            "--repo", $Repo,
            "--title", "Agartha V2 CC:Tweaked Media",
            "--notes", "10 FPS maximum-quality 32vid media for the 143x81 CC:Tweaked monitor player.",
            "--latest=false"
        )

        if ($createCode -ne 0) {
            throw "Could not create GitHub release (exit code $createCode)."
        }
    } else {
        Write-Host "Release '$Tag' already exists; matching assets will be replaced."
    }

    Write-Host ""
    Write-Host "Uploading all 50 files automatically. You can leave this window alone." -ForegroundColor Cyan

    for ($start = 0; $start -lt $files.Count; $start += 5) {
        $end = [Math]::Min($start + 4, $files.Count - 1)
        $batch = @($files[$start..$end])

        Write-Host ("Uploading parts {0:D2}-{1:D2}..." -f ($start + 1), ($end + 1))

        $arguments = @("release", "upload", $Tag)
        foreach ($file in $batch) { $arguments += $file.FullName }
        $arguments += @("--repo", $Repo, "--clobber")

        $uploadCode = Invoke-Gh-Interactive -Gh $gh -Arguments $arguments
        if ($uploadCode -ne 0) {
            throw "Upload failed for parts $($start + 1)-$($end + 1). Re-run this script; already-uploaded assets are safe because --clobber is enabled."
        }
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
