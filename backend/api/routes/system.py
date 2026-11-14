from __future__ import annotations

from http import HTTPStatus

from fastapi import APIRouter, HTTPException
from fastapi.responses import FileResponse

from backend.core import settings

router = APIRouter()


@router.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@router.get("/uploads/{file_path:path}")
def uploaded_file(file_path: str) -> FileResponse:
    candidate = (settings.UPLOADS_ROOT / file_path).resolve()
    uploads_root = settings.UPLOADS_ROOT.resolve()
    if not candidate.is_file() or uploads_root not in candidate.parents:
        raise HTTPException(status_code=HTTPStatus.NOT_FOUND.value, detail="Uploaded file not found.")
    return FileResponse(candidate)
