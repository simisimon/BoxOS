# Workflow: from feature to release

How a change gets from the Mac to https://app.boxos-app.de. First-time server
setup is in [`deploy.md`](deploy.md).

## 1. Develop locally

1. Start the dev stack: `docker compose up -d --build` (app at
   http://localhost:3001 with quick login, API at http://localhost:8081).
   Demo data: `docker compose exec backend-dev python -m backend.seed_demo`.
   Accounts: `docker compose exec backend-dev python -m backend.manage ...`.
   Stripe test mode works here with the keys in `.env`. Production is never
   touched by anything you do here.
2. One branch per feature: `git checkout -b feature/<name>`.
3. After changing `app/`: `docker compose restart frontend-dev`, wait for
   "is being served", hard-reload the browser. The backend reloads on save.
4. Run the checks (known failures are listed in `CLAUDE.md`):
   ```bash
   python3 -m unittest discover -s backend -p "test_*.py"
   cd app && flutter pub get && flutter analyze lib test && flutter test
   ```
5. Merge into `main` and push. **`main` is what goes to the server**; anything
   not merged into `main` never reaches it.

## 2. Release on the VPS

```bash
ssh root@<vps>
cd /docker/boxos
deploy/backup.sh                 # safety copy first, ends with "backup ok"
git pull
boxos up -d --build
curl -I https://api.boxos-app.de/health
boxos ps                         # backend and db "healthy"
```

`boxos` is the alias
`docker compose -f docker-compose.prod.yml -f docker-compose.traefik.yml --env-file .env.prod`
(in `~/.bashrc` on the server):

```bash
echo "alias boxos='cd /docker/boxos && docker compose -f docker-compose.prod.yml -f docker-compose.traefik.yml --env-file .env.prod'" >> ~/.bashrc
```

- `up -d --build` rebuilds only what changed and restarts only containers with
  a new image: about a minute for a backend change, a few minutes when the
  Flutter app changed. Downtime is a few seconds.
- The database and uploads live in Docker volumes and survive every rebuild.
- Open browsers get the new app on their next reload (entry files are never
  cached).

## 3. Things to watch

- **Database changes.** New tables and columns are added by `backend/db.py`
  when the backend starts. Renaming or deleting columns, or changing existing
  data, needs a manual step on the server (there is no migration tool yet):
  write it down in the pull request and run it right after `git pull`, after
  the backup.
- **`.env.prod` changes.** `boxos up -d` applies them (`restart` does not
  reload the file). `APP_URL` / `API_URL` are built into the web app, so they
  need `boxos up -d --build`.
- **Payments** stay off in production until `BOXOS_STRIPE_*` is set up and the
  check in `settings.production_problems()` is removed.

## 4. Something broke: roll back

```bash
cd /docker/boxos
git log --oneline -5             # find the last good commit
git checkout <good commit>
boxos up -d --build
```

Fix it on the Mac, push, then on the server `git checkout main && git pull &&
boxos up -d --build`. If a release damaged data, restore the backup taken
before it: `deploy/restore.sh /srv/boxos-backups/db-<stamp>.dump` (asks for
confirmation, replaces the database).

## 5. Backups

`deploy/backup.sh` writes a `pg_dump` of the database (members, classes,
bookings, WODs, plans, messages) and a tar of the uploads (profile pictures,
logos, announcement images) to `/srv/boxos-backups`, readable by root only, and
deletes copies older than 14 days (`KEEP_DAYS`). The app keeps running while it
runs. Nightly via cron:

```
15 3 * * * /docker/boxos/deploy/backup.sh >> /var/log/boxos-backup.log 2>&1
```

Restore with `deploy/restore.sh <db dump> [uploads tar]`. The copies are on the
same server, so copy them off it too ([`deploy.md` §7](deploy.md#7-backups)).

## 6. Accounts and test data on the server

```bash
boxos exec backend python -m backend.manage list-gyms
boxos exec backend python -m backend.manage list-users --gym "<slug>"
boxos exec backend python -m backend.manage create-user --email x@y.de --name "Name" --role athlete|trainer|admin --gym "<slug>"
boxos exec backend python -m backend.manage reset-password --email x@y.de      # prints a new password
boxos exec backend python -m backend.manage deactivate-user --email x@y.de     # signs out, locks the account
boxos exec backend python -m backend.manage seed-test-data --gym "<slug>"           # test members, classes, WODs
boxos exec backend python -m backend.manage seed-test-data --gym "<slug>" --remove  # delete them again
```
