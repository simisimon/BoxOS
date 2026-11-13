#!/usr/bin/env bash
# Restore a backup made by backup.sh into a running stack.
#   deploy/restore.sh /srv/boxos-backups/db-<stamp>.dump [/srv/boxos-backups/uploads-<stamp>.tar.gz]
# Test it on staging first:  PROJECT=boxos-staging deploy/restore.sh ...
# This replaces the target database. It asks before it starts.
set -euo pipefail

DUMP="${1:?usage: restore.sh <db dump> [uploads tar]}"
UPLOADS="${2:-}"
REPO_DIR="${REPO_DIR:-/srv/boxos}"
PROJECT="${PROJECT:-boxos-prod}"
COMPOSE=(docker compose -p "$PROJECT" -f "$REPO_DIR/docker-compose.prod.yml")

read -r -p "Replace the database of project '$PROJECT' with $DUMP? Type yes: " answer
[ "$answer" = "yes" ] || { echo "Aborted."; exit 1; }

"${COMPOSE[@]}" stop backend
"${COMPOSE[@]}" exec -T db pg_restore -U boxos -d boxos --clean --if-exists --no-owner < "$DUMP"
if [ -n "$UPLOADS" ]; then
  "${COMPOSE[@]}" run --rm -T --no-deps --entrypoint tar backend -C /app -xzf - < "$UPLOADS"
fi
"${COMPOSE[@]}" start backend
echo "Restored $DUMP into project $PROJECT."
