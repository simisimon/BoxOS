#!/usr/bin/env sh
set -eu
cd "$(dirname "$0")/.."
exec python3 -m uvicorn backend.fastapi_app:app --reload --host 127.0.0.1 --port 8080
