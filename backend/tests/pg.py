"""Shared PostgreSQL test backend.

Starts a single throwaway PostgreSQL container for the whole test process (via
testcontainers) and hands out its connection string. Each test resets the
``public`` schema so it starts from a clean database. If Docker or
testcontainers is unavailable the helpers degrade to ``None`` so suites can skip
instead of failing.
"""

from __future__ import annotations

import atexit
import importlib.util

_TESTCONTAINERS_AVAILABLE = importlib.util.find_spec("testcontainers") is not None

_container = None
_dsn: str | None = None
_unavailable = False


def get_dsn() -> str | None:
    """Return a psycopg connection string for the shared test database, starting the
    container on first use. Returns ``None`` if a database could not be provisioned."""
    global _container, _dsn, _unavailable
    if _dsn is not None:
        return _dsn
    if _unavailable or not _TESTCONTAINERS_AVAILABLE:
        _unavailable = True
        return None
    try:
        from testcontainers.postgres import PostgresContainer

        _container = PostgresContainer("postgres:16-alpine")
        _container.start()
        atexit.register(_stop_container)
        # testcontainers returns a SQLAlchemy-style URL (e.g. postgresql+psycopg2://...);
        # psycopg wants a plain postgresql:// DSN.
        url = _container.get_connection_url()
        _dsn = url.replace("+psycopg2", "").replace("+psycopg", "")
    except Exception:
        _unavailable = True
        _dsn = None
    return _dsn


def reset_database() -> None:
    """Drop and recreate the public schema so the next test starts clean."""
    import psycopg

    dsn = get_dsn()
    if dsn is None:
        return
    with psycopg.connect(dsn, autocommit=True) as connection:
        connection.execute("drop schema if exists public cascade")
        connection.execute("create schema public")


def _stop_container() -> None:
    global _container
    if _container is not None:
        try:
            _container.stop()
        except Exception:
            pass
        _container = None
