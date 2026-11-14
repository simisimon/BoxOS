from __future__ import annotations

from contextlib import asynccontextmanager
from http import HTTPStatus

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from backend.api.deps import logger
from backend.api.routes import (
    admin,
    announcements,
    auth,
    community,
    follows,
    gyms,
    members,
    membership,
    movements,
    notifications,
    profile,
    programming,
    result_social,
    results,
    schedule,
    system,
)
from backend.core import db, settings, validation


@asynccontextmanager
async def lifespan(_: FastAPI):
    problems = settings.production_problems()
    if problems:
        raise RuntimeError("Refusing to start in production: " + " ".join(problems))
    db.init_db()
    yield


app = FastAPI(title="BoxOS Backend", version="0.1.0", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.CORS_ALLOW_ORIGINS,
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.exception_handler(validation.ApiError)
async def handle_api_error(_: Request, error: validation.ApiError) -> JSONResponse:
    return JSONResponse(status_code=error.status.value, content={"detail": error.message})


@app.exception_handler(Exception)
async def handle_unexpected_error(_: Request, error: Exception) -> JSONResponse:
    logger.exception("Unhandled error while processing request", exc_info=error)
    return JSONResponse(
        status_code=HTTPStatus.INTERNAL_SERVER_ERROR.value,
        content={"detail": "Internal server error."},
    )


# Order matters: a router registered earlier wins when two paths overlap
# (e.g. /results/me in results before /results/{result_id} in result_social).
app.include_router(auth.router)
app.include_router(gyms.router)
app.include_router(notifications.router)
app.include_router(profile.router)
app.include_router(schedule.router)
app.include_router(membership.router)
app.include_router(members.router)
app.include_router(announcements.router)
app.include_router(programming.router)
app.include_router(community.router)
app.include_router(system.router)
app.include_router(movements.router)
app.include_router(results.router)
app.include_router(follows.router)
app.include_router(result_social.router)
app.include_router(admin.router)
