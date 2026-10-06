param(
  [string]$Source=(Get-Location).Path,
  [string]$Repo="Chazammm/atm10-cc-doom",
  [string]$Tag="agartha-audio-test"
)
$ErrorActionPreference="Stop"

function Find-Gh {
  $cmd=Get-Command gh.exe -ErrorAction SilentlyContinue
  if(-not $cmd){$cmd=Get-Command gh -ErrorAction SilentlyContinue}
  if($cmd){return $cmd.Source}
  $candidate="$env:ProgramFiles\GitHub CLI\gh.exe"
  if(Test-Path $candidate){return $candidate}
  return $null
}
function Probe-Gh([string]$Gh,[string[]]$Arguments){
  $old=$ErrorActionPreference;$ErrorActionPreference="SilentlyContinue"
  try{& $Gh @Arguments *> $null; return [int]$LASTEXITCODE}
  finally{$ErrorActionPreference=$old}
}
function Run-Gh([string]$Gh,[string[]]$Arguments){
  $old=$ErrorActionPreference;$ErrorActionPreference="Continue"
  try{& $Gh @Arguments 2>&1 | ForEach-Object{Write-Host $_}; $code=$LASTEXITCODE; return [int]$code}
  finally{$ErrorActionPreference=$old}
}

$gh=Find-Gh
if(-not $gh){throw "GitHub CLI is not installed."}
if((Probe-Gh $gh @("auth","status","--hostname","github.com")) -ne 0){
  if((Run-Gh $gh @("auth","login","--hostname","github.com","--git-protocol","https","--web")) -ne 0){throw "GitHub login failed."}
}

$temp=Join-Path ([IO.Path]::GetTempPath()) ("agartha-audiotest-"+[guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory $temp|Out-Null
try{
  $zip=Get-ChildItem $Source -Filter "Agartha_Audio_ABC_Test.zip" -File|Select-Object -First 1
  if($zip){Expand-Archive $zip.FullName $temp -Force}
  Get-ChildItem $Source -Filter "*.dfpwm" -File -ErrorAction SilentlyContinue|Copy-Item -Destination $temp -Force
  $files=@(Get-ChildItem $temp -Filter "*.dfpwm" -File|Where-Object{$_.Name -match '^[abc]_(left|right|mono)\.dfpwm$'}|Sort-Object Name)
  if($files.Count -ne 9){throw "Expected 9 A/B/C audio files."}

  if((Probe-Gh $gh @("release","view",$Tag,"--repo",$Repo)) -ne 0){
    if((Run-Gh $gh @("release","create",$Tag,"--repo",$Repo,"--title","Agartha DFPWM A-B-C Audio Test","--notes","20-second preprocessing comparison.","--latest=false")) -ne 0){throw "Could not create release."}
  }
  $args=@("release","upload",$Tag)
  foreach($file in $files){$args+=$file.FullName}
  $args+=@("--repo",$Repo,"--clobber")
  if((Run-Gh $gh $args) -ne 0){throw "Upload failed."}
  Write-Host "Upload complete. In Minecraft: audiotest a" -ForegroundColor Green
}finally{
  if(Test-Path $temp){Remove-Item $temp -Recurse -Force}
}
