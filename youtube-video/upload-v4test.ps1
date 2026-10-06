param(
  [string]$Source = (Get-Location).Path,
  [string]$Repo = "Chazammm/atm10-cc-doom",
  [string]$Tag = "agartha-v4-test"
)
$ErrorActionPreference="Stop"

$gh=(Get-Command gh.exe -ErrorAction SilentlyContinue).Source
if(-not $gh){$gh=(Get-Command gh -ErrorAction SilentlyContinue).Source}
if(-not $gh){$gh="$env:ProgramFiles\GitHub CLI\gh.exe"}
if(-not (Test-Path $gh)){throw "GitHub CLI is not installed."}

$old=$ErrorActionPreference;$ErrorActionPreference="SilentlyContinue"
& $gh auth status --hostname github.com *> $null
$auth=$LASTEXITCODE
$ErrorActionPreference=$old
if($auth -ne 0){& $gh auth login --hostname github.com --git-protocol https --web}

$temp=Join-Path ([IO.Path]::GetTempPath()) ("agartha-v4test-"+[guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory $temp | Out-Null
try{
  $zip=Get-ChildItem $Source -Filter "Agartha_V4_60s_Test.zip" -File | Select-Object -First 1
  if($zip){Expand-Archive $zip.FullName $temp -Force}
  Get-ChildItem $Source -Filter "agartha-v4-test-part*.32vid" -File -ErrorAction SilentlyContinue | Copy-Item -Destination $temp -Force
  $files=@(Get-ChildItem $temp -Filter "agartha-v4-test-part*.32vid" -File | Sort-Object Name)
  if($files.Count -ne 2){throw "Expected the two V4 test parts."}

  $old=$ErrorActionPreference;$ErrorActionPreference="SilentlyContinue"
  & $gh release view $Tag --repo $Repo *> $null
  $exists=$LASTEXITCODE -eq 0
  $ErrorActionPreference=$old
  if(-not $exists){
    & $gh release create $Tag --repo $Repo --title "Agartha V4 60s Quality Test" --notes "Experimental direct semigraphics cell optimiser." --latest=false
    if($LASTEXITCODE -ne 0){throw "Could not create release."}
  }
  & $gh release upload $Tag $files.FullName --repo $Repo --clobber
  if($LASTEXITCODE -ne 0){throw "Upload failed."}
  Write-Host "Upload complete. In Minecraft run: v4test" -ForegroundColor Green
} finally {
  if(Test-Path $temp){Remove-Item $temp -Recurse -Force}
}
