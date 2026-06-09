FROM python:3.13-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    BOXOS_HOST=0.0.0.0 \
    BOXOS_PORT=8080 \
    BOXOS_DATABASE_URL=postgresql://boxos:boxos@db:5432/boxos \
    BOXOS_UPLOADS_ROOT=/app/uploads

WORKDIR /app

COPY backend/requirements-fastapi.txt ./backend/requirements-fastapi.txt
RUN pip install --no-cache-dir -r backend/requirements-fastapi.txt

COPY backend ./backend

RUN mkdir -p /app/uploads

EXPOSE 8080

CMD ["python", "-m", "uvicorn", "backend.fastapi_app:app", "--host", "0.0.0.0", "--port", "8080"]
