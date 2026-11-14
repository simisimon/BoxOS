from __future__ import annotations

from http import HTTPStatus
from typing import Any

from fastapi import HTTPException
from pydantic import BaseModel

from backend.core import db, validation


class GymIdRequest(BaseModel):
    gym_id: int


class EntityIdRequest(BaseModel):
    id: int


def get_gym_timezone(connection: Any, gym_id: int) -> str:
    gym_row = connection.execute("select timezone from gyms where id = ?", (gym_id,)).fetchone()
    if gym_row is None:
        raise HTTPException(status_code=HTTPStatus.NOT_FOUND.value, detail="Active gym not found.")
    return str(gym_row["timezone"])


def class_type_names(gym_id: int) -> list[str]:
    """Built-in class types plus the ones the gym's owner added."""
    connection = db.get_connection()
    try:
        rows = connection.execute(
            "select name from gym_class_types where gym_id = ? order by created_at, id",
            (gym_id,),
        ).fetchall()
    finally:
        connection.close()
    return [*validation.BUILTIN_CLASS_TYPES, *(row["name"] for row in rows)]
