#!/usr/bin/env bash
# Nightly backup of the BoxOS production database and uploads.
#
# Writes a compressed pg_dump and a tar of the uploads volume to BACKUP_DIR and
# deletes local copies older than KEEP_DAYS. Copy BACKUP_DIR off the server
# (restic, rclone or the provider's storage box) so a lost VPS doesn't take the
# backups with it; see docs/deploy.md.
#
# Cron (as the deploy user), every night at 03:15:
#   15 3 * * * /docker/boxos/deploy/backup.sh >> /var/log/boxos-backup.log 2>&1
set -euo pipefail

REPO_DIR="${REPO_DIR:-/docker/boxos}"
BACKUP_DIR="${BACKUP_DIR:-/srv/boxos-backups}"
KEEP_DAYS="${KEEP_DAYS:-14}"
PROJECT="${PROJECT:-boxos-prod}"
# The env file is needed even for exec: the compose file requires its variables.
ENV_FILE="${ENV_FILE:-$REPO_DIR/.env.prod}"
COMPOSE=(docker compose -p "$PROJECT" -f "$REPO_DIR/docker-compose.prod.yml" --env-file "$ENV_FILE")

stamp="$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$BACKUP_DIR"
umask 077

"${COMPOSE[@]}" exec -T db pg_dump -U boxos -d boxos --format=custom \
  > "$BACKUP_DIR/db-$stamp.dump"

# The uploads volume holds avatars, gym logos and announcement images.
"${COMPOSE[@]}" exec -T backend tar -C /app -czf - uploads \
  > "$BACKUP_DIR/uploads-$stamp.tar.gz"

find "$BACKUP_DIR" -type f \( -name 'db-*.dump' -o -name 'uploads-*.tar.gz' \) \
  -mtime +"$KEEP_DAYS" -delete

echo "$(date -u +%FT%TZ) backup ok: db-$stamp.dump uploads-$stamp.tar.gz"
