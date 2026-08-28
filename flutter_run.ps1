# Run Flutter with PATH set (use if `flutter` is not recognized in your terminal)
$flutterBin = 'C:\flutter\bin'
if (-not (Test-Path "$flutterBin\flutter.bat")) {
  Write-Error "Flutter not found at $flutterBin. Install Flutter or update the path in this script."
  exit 1
}
$env:Path = "$flutterBin;$env:Path"
Set-Location $PSScriptRoot
& "$flutterBin\flutter.bat" @args
