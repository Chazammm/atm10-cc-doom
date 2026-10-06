param(
  [string]$Source=(Get-Location).Path
)
$ErrorActionPreference="Stop"
$base="https://raw.githubusercontent.com/Chazammm/atm10-cc-doom/main/youtube-video/"
$temp=Join-Path ([IO.Path]::GetTempPath()) ("agartha-upload-all-"+[guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory $temp | Out-Null
try {
  $jobs=@(
    @{Name="V3";Pattern="Agartha_V3_parts*.zip";Script="upload-v3.ps1"},
    @{Name="V4 full";Pattern="Agartha_V4_parts*.zip";Script="upload-v4.ps1"},
    @{Name="V4 quality test";Pattern="Agartha_V4_60s_Test.zip";Script="upload-v4test.ps1"},
    @{Name="Audio A-B-C test";Pattern="Agartha_Audio_ABC_Test.zip";Script="upload-audiotest.ps1"}
  )
  foreach($job in $jobs){
    if(Get-ChildItem $Source -Filter $job.Pattern -File -ErrorAction SilentlyContinue){
      Write-Host ("=== Uploading "+$job.Name+" ===") -ForegroundColor Cyan
      $local=Join-Path $temp $job.Script
      Invoke-WebRequest ($base+$job.Script) -OutFile $local
      & powershell -ExecutionPolicy Bypass -File $local -Source $Source
      if($LASTEXITCODE -ne 0){throw ($job.Name+" uploader failed.")}
    } else {
      Write-Host ("Skipping "+$job.Name+" (files not found).") -ForegroundColor DarkGray
    }
  }
  Write-Host ""
  Write-Host "All available media/test packages are uploaded." -ForegroundColor Green
} finally {
  if(Test-Path $temp){Remove-Item $temp -Recurse -Force}
}
