param(
    [string]$Source,
    [string]$Repo = "Chazammm/atm10-cc-doom",
    [string]$Tag = "agartha-v3"
)

$ErrorActionPreference = "Stop"
$ExpectedParts = 86

function Find-Gh {
    $cmd = Get-Command gh.exe -ErrorAction SilentlyContinue
    if (-not $cmd) { $cmd = Get-Command gh -ErrorAction SilentlyContinue }
    if ($cmd) { return $cmd.Source }

    foreach ($candidate in @(
        (Join-Path $env:ProgramFiles "GitHub CLI\gh.exe"),
        (Join-Path $env:LOCALAPPDATA "Programs\GitHub CLI\gh.exe"),
        (Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Links\gh.exe")
    )) {
        if ($candidate -and (Test-Path $candidate)) { return $candidate }
    }
    return $null
}

function Run-Gh {
    param([string]$Gh, [string[]]$Arguments)
    $old = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        & $Gh @Arguments 2>&1 | ForEach-Object { Write-Host $_ }
        $code = $LASTEXITCODE
        return [int]$code
    } finally { $ErrorActionPreference = $old }
}

function Probe-Gh {
    param([string]$Gh, [string[]]$Arguments)
    $old = $ErrorActionPreference
    $ErrorActionPreference = "SilentlyContinue"
    try {
        & $Gh @Arguments *> $null
        return [int]$LASTEXITCODE
    } finally { $ErrorActionPreference = $old }
}

function Find-Source {
    param([string]$Requested)
    if ($Requested) { return (Resolve-Path $Requested).Path }

    foreach ($candidate in @((Get-Location).Path, (Join-Path $HOME "Downloads"), (Join-Path $HOME "Desktop"))) {
        if (-not (Test-Path $candidate)) { continue }
        $zips = @(Get-ChildItem $candidate -Filter "Agartha_V3_parts*.zip" -File -ErrorAction SilentlyContinue)
        $parts = @(Get-ChildItem $candidate -Filter "agartha-v3-part*.32vid" -File -ErrorAction SilentlyContinue)
        if ($zips.Count -gt 0 -or $parts.Count -gt 0) { return $candidate }
    }
    throw "Could not find Agartha V3 ZIPs/parts. Put them in Downloads/Desktop/current folder or pass -Source."
}

Write-Host ""
Write-Host "=== Agartha V3 automatic GitHub uploader ===" -ForegroundColor Cyan
Write-Host "Target: $Repo / release $Tag"

$gh = Find-Gh
if (-not $gh) {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) { throw "GitHub CLI is not installed." }
    Write-Host "Installing GitHub CLI..."
    $old = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        winget install --id GitHub.cli --exact --source winget --accept-source-agreements --accept-package-agreements
    } finally { $ErrorActionPreference = $old }
    $env:Path = [Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [Environment]::GetEnvironmentVariable("Path","User")
    $gh = Find-Gh
}
if (-not $gh) { throw "Could not locate gh.exe. Reopen PowerShell and retry." }

if ((Probe-Gh $gh @("auth","status","--hostname","github.com")) -ne 0) {
    Write-Host "One-time GitHub login required." -ForegroundColor Yellow
    if ((Run-Gh $gh @("auth","login","--hostname","github.com","--git-protocol","https","--web")) -ne 0) {
        throw "GitHub login failed."
    }
}

$sourceDir = Find-Source $Source
Write-Host "Source folder: $sourceDir"

$temp = Join-Path ([IO.Path]::GetTempPath()) ("agartha-v3-upload-" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $temp | Out-Null

try {
    Get-ChildItem $sourceDir -Filter "agartha-v3-part*.32vid" -File -ErrorAction SilentlyContinue |
        Copy-Item -Destination $temp -Force

    $zips = @(Get-ChildItem $sourceDir -Filter "Agartha_V3_parts*.zip" -File -ErrorAction SilentlyContinue | Sort-Object Name)
    foreach ($zip in $zips) {
        Write-Host "Extracting $($zip.Name)..."
        Expand-Archive $zip.FullName -DestinationPath $temp -Force
    }

    $all = @(Get-ChildItem $temp -Filter "agartha-v3-part*.32vid" -File -Recurse)
    if ($all.Count -eq 0) { throw "No V3 .32vid parts found." }

    $numbered = @{}
    $maxPart = 0
    foreach ($file in $all) {
        if ($file.Name -match '^agartha-v3-part(\d+)\.32vid$') {
            $n = [int]$Matches[1]
            $numbered[$n] = $file
            if ($n -gt $maxPart) { $maxPart = $n }
        }
    }
    if ($maxPart -ne $ExpectedParts -or $numbered.Count -ne $ExpectedParts) {
        throw ("Expected {0} V3 parts but found {1} (highest part {2}). Download all V3 packs first." -f $ExpectedParts,$numbered.Count,$maxPart)
    }
    for ($i=1; $i -le $ExpectedParts; $i++) {
        if (-not $numbered.ContainsKey($i)) { throw ("Missing agartha-v3-part{0:D2}.32vid" -f $i) }
    }
    $files = @(1..$ExpectedParts | ForEach-Object { $numbered[$_] })

    $totalMiB = [Math]::Round((($files | Measure-Object Length -Sum).Sum / 1MB),1)
    Write-Host ("Found {0} parts ({1} MiB)." -f $files.Count,$totalMiB) -ForegroundColor Green

    if ((Probe-Gh $gh @("release","view",$Tag,"--repo",$Repo)) -ne 0) {
        if ((Run-Gh $gh @(
            "release","create",$Tag,
            "--repo",$Repo,
            "--title","Agartha V3 - 20 FPS Stereo CC:Tweaked",
            "--notes","20 FPS, 164x67 monitor, 48 kHz DFPWM mono fallback + true two-speaker stereo.",
            "--latest=false"
        )) -ne 0) { throw "Could not create GitHub release." }
    }

    # Read existing release assets. Exact name+size matches are already done,
    # so a rerun after closing PowerShell does not upload hundreds of MB again.
    $existing = @{}
    $oldPreference = $ErrorActionPreference
    $ErrorActionPreference = "SilentlyContinue"
    try {
        $releaseId = & $gh api "repos/$Repo/releases/tags/$Tag" --jq '.id' 2>$null
        if ($LASTEXITCODE -eq 0 -and $releaseId) {
            $assetLines = @(& $gh api "repos/$Repo/releases/$releaseId/assets?per_page=100" --jq '.[] | [.name, (.size|tostring)] | @tsv' 2>$null)
            if ($LASTEXITCODE -eq 0) {
                foreach ($line in $assetLines) {
                    $cols = "$line".Split([char]9)
                    if ($cols.Count -eq 2) { $existing[$cols[0]] = [int64]$cols[1] }
                }
            }
        }
    } finally { $ErrorActionPreference = $oldPreference }

    $pending = @()
    foreach ($file in $files) {
        if ($existing.ContainsKey($file.Name) -and $existing[$file.Name] -eq $file.Length) {
            Write-Host ("Already complete: " + $file.Name) -ForegroundColor DarkGray
        } else {
            $pending += $file
        }
    }

    Write-Host ""
    Write-Host ("Uploading {0} remaining part(s) in batches of five." -f $pending.Count) -ForegroundColor Cyan

    for ($start=0; $start -lt $pending.Count; $start+=5) {
        $end=[Math]::Min($start+4,$pending.Count-1)
        $batch=@($pending[$start..$end])
        Write-Host ("Uploading batch {0}-{1} of {2}..." -f ($start+1),($end+1),$pending.Count)
        $arguments=@("release","upload",$Tag)
        foreach ($file in $batch) { $arguments += $file.FullName }
        $arguments += @("--repo",$Repo,"--clobber")
        if ((Run-Gh $gh $arguments) -ne 0) {
            throw "Upload failed. Run this script again; already-complete assets will be skipped."
        }
    }

    Write-Host ""
    Write-Host "Upload complete." -ForegroundColor Green
    Write-Host "In Minecraft:"
    Write-Host "wget run https://raw.githubusercontent.com/Chazammm/atm10-cc-doom/main/youtube-video/install.lua"
    Write-Host "agartha-v3"
}
finally {
    if (Test-Path $temp) { Remove-Item $temp -Recurse -Force -ErrorAction SilentlyContinue }
}
