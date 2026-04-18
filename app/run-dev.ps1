$ErrorActionPreference = "Stop"

$envFile = "env/dev.json"

if (-not (Test-Path $envFile)) {
  Write-Host "Missing $envFile"
  Write-Host "Create env/dev.json with your local API settings."
  exit 1
}

Write-Host "Starting BoxOS with dart defines from $envFile ..."
flutter run -d chrome --dart-define-from-file=$envFile
