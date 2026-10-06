param(
  [string]$Source=(Get-Location).Path,
  [string]$Repo="Chazammm/atm10-cc-doom",
  [string]$Tag="agartha-audio-test"
)
$ErrorActionPreference="Stop"
$gh=(Get-Command gh.exe -ErrorAction SilentlyContinue).Source
if(-not $gh){$gh=(Get-Command gh -ErrorAction SilentlyContinue).Source}
if(-not $gh){$gh="$env:ProgramFiles\GitHub CLI\gh.exe"}
if(-not (Test-Path $gh)){throw "GitHub CLI is not installed."}
$temp=Join-Path ([IO.Path]::GetTempPath()) ("agartha-audiotest-"+[guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory $temp|Out-Null
try{
  $zip=Get-ChildItem $Source -Filter "Agartha_Audio_ABC_Test.zip" -File|Select-Object -First 1
  if($zip){Expand-Archive $zip.FullName $temp -Force}
  Get-ChildItem $Source -Filter "*.dfpwm" -File -ErrorAction SilentlyContinue|Copy-Item -Destination $temp -Force
  $files=@(Get-ChildItem $temp -Filter "*.dfpwm" -File|Where-Object{$_.Name -match '^[abc]_(left|right|mono)\.dfpwm$'}|Sort-Object Name)
  if($files.Count -ne 9){throw "Expected 9 A/B/C audio files."}
  $old=$ErrorActionPreference;$ErrorActionPreference="SilentlyContinue"
  & $gh release view $Tag --repo $Repo *> $null;$exists=$LASTEXITCODE -eq 0
  $ErrorActionPreference=$old
  if(-not $exists){& $gh release create $Tag --repo $Repo --title "Agartha DFPWM A-B-C Audio Test" --notes "20-second preprocessing comparison." --latest=false}
  & $gh release upload $Tag $files.FullName --repo $Repo --clobber
  if($LASTEXITCODE -ne 0){throw "Upload failed."}
  Write-Host "Upload complete. In Minecraft: audiotest a" -ForegroundColor Green
}finally{if(Test-Path $temp){Remove-Item $temp -Recurse -Force}}
