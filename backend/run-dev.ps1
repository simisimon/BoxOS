$ErrorActionPreference = "Stop"

Write-Host "Starting BoxOS FastAPI backend on http://127.0.0.1:8080 ..."
python -m uvicorn backend.fastapi_app:app --reload --host 127.0.0.1 --port 8080
