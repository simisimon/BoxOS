# Deploying BoxOS on a VPS

One server runs everything: Postgres, the FastAPI backend and the Flutter web
build (`docker-compose.prod.yml`), behind the reverse proxy that already serves
the marketing site.

| URL | What | Local port |
|---|---|---|
| https://app.boxos-app.de | Web app (nginx in the `web` container) | 127.0.0.1:8090 |
| https://api.boxos-app.de | Backend | 127.0.0.1:8080 |
| https://boxos-app.de | Marketing site (unchanged) | – |

The production stack is invite-only (no sign-up, no demo accounts) and has
payments switched off: it passes no Stripe keys, and the backend refuses to
start with `BOXOS_ENV=production` if one is set. It also refuses dev passwords,
the template's `change-me` password, logged reset tokens and localhost CORS.

## 1. Server prerequisites

As root on a fresh Debian/Ubuntu VPS:

```bash
apt update && apt install -y ca-certificates curl git ufw unattended-upgrades
curl -fsSL https://get.docker.com | sh
dpkg-reconfigure -plow unattended-upgrades   # answer "Yes"
ufw allow 22/tcp && ufw allow 80/tcp && ufw allow 443/tcp && ufw enable
```

Docker's published ports bypass ufw, which is why the compose file binds the
backend and web ports to 127.0.0.1 only. Postgres publishes no port.

## 2. DNS

At the domain's DNS provider, point these at the VPS (A record, plus AAAA if
the server has IPv6):

- `app.boxos-app.de`
- `api.boxos-app.de`
- optional: `staging-app.boxos-app.de`, `staging-api.boxos-app.de`

Check with `dig +short app.boxos-app.de` before setting up TLS.

## 3. Code and secrets

```bash
mkdir -p /srv && git clone https://github.com/simisimon/BoxOS.git /srv/boxos
cd /srv/boxos
cp .env.prod.example .env.prod && chmod 600 .env.prod
sed -i "s|^POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=$(openssl rand -base64 32 | tr -d '/+=')|" .env.prod
```

Check `APP_URL` and `API_URL` in `.env.prod` (no trailing slash). The URLs are
built into the web app, so changing them needs a rebuild (`up -d --build`).

## 4. Start the stack

```bash
cd /srv/boxos
docker compose -f docker-compose.prod.yml --env-file .env.prod up -d --build
docker compose -f docker-compose.prod.yml ps
curl -fsS http://127.0.0.1:8080/health
```

The first build takes several minutes (Flutter). The database schema is created
on the backend's first start (`backend/db.py`).

If the backend restarts in a loop, read why:
`docker compose -f docker-compose.prod.yml logs backend | grep "Refusing to start"`.

## 5. Reverse proxy and TLS

We don't know yet which proxy serves the marketing site. Use the one that is
already there.

**Caddy:** add the blocks from `deploy/Caddyfile` to the server's Caddyfile,
keep the existing `boxos-app.de` block, then `systemctl reload caddy`. Caddy
gets and renews the certificates on its own.

**nginx:** one server block per host, then certificates with certbot:

```nginx
server {
  listen 80;
  server_name app.boxos-app.de;
  location / {
    proxy_pass http://127.0.0.1:8090;
    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
  }
}

server {
  listen 80;
  server_name api.boxos-app.de;
  client_max_body_size 10m;
  location / {
    proxy_pass http://127.0.0.1:8080;
    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
  }
}
```

```bash
apt install -y certbot python3-certbot-nginx
certbot --nginx -d app.boxos-app.de -d api.boxos-app.de
```

Then add `add_header Strict-Transport-Security "max-age=31536000" always;` to
the two HTTPS server blocks certbot wrote. The web container already sends
nosniff, frame and referrer headers.

## 6. First owner and test users

Accounts are created on the server; each command prints a generated password.

```bash
cd /srv/boxos
alias boxos-manage='docker compose -f docker-compose.prod.yml exec backend python -m backend.manage'
boxos-manage create-user --email owner@example.com --name "Box Owner" --role admin
```

The owner logs in at https://app.boxos-app.de, goes to Profile › "Create box"
(or Home › "Create Box") and sets up the box. Then add members and trainers:

```bash
boxos-manage list-gyms
boxos-manage create-user --email coach@example.com --name "Coach" --role trainer --gym "<slug>"
boxos-manage create-user --email member@example.com --name "Member" --role athlete --gym "<slug>"
```

Forgotten password: `boxos-manage reset-password --email ...` (password reset by
email is not available yet). Remove access: `boxos-manage deactivate-user --email ...`.

## 7. Backups

`deploy/backup.sh` writes a `pg_dump` and a tar of the uploads to
`/srv/boxos-backups` and keeps 14 days.

```bash
crontab -e
# 15 3 * * * /srv/boxos/deploy/backup.sh >> /var/log/boxos-backup.log 2>&1
```

Backups on the same server don't survive losing the server. Copy them off it
every night, for example with rclone to a storage box or S3 bucket:

```bash
# after `rclone config` set up a remote called "offsite"
# 45 3 * * * rclone copy /srv/boxos-backups offsite:boxos-backups --max-age 48h
```

## 8. Restore test

Do this once after the first backup, and whenever the backup setup changes. It
restores into a separate staging stack, so production is not touched:

```bash
cd /srv/boxos
cp .env.prod .env.staging   # then change APP_URL/API_URL to the staging hosts,
                            # BACKEND_PORT=8081, WEB_PORT=8091 and a new POSTGRES_PASSWORD
docker compose -p boxos-staging -f docker-compose.prod.yml --env-file .env.staging up -d --build
PROJECT=boxos-staging deploy/restore.sh /srv/boxos-backups/db-<stamp>.dump /srv/boxos-backups/uploads-<stamp>.tar.gz
```

Log in on the staging app and check that members, classes and images are
there. Stop it afterwards with
`docker compose -p boxos-staging -f docker-compose.prod.yml --env-file .env.staging down`
(add `-v` to delete its data too).

## 9. Updating

```bash
cd /srv/boxos
deploy/backup.sh
git pull
docker compose -f docker-compose.prod.yml --env-file .env.prod up -d --build
curl -fsS http://127.0.0.1:8080/health
```

There are no migrations yet: `backend/db.py` applies the schema on startup and
adds new tables and columns itself. Anything that changes or removes existing
data has to be done by hand, so read the commits before pulling and take a
backup first (as above).

## 10. Monitoring

Add an uptime check (e.g. UptimeRobot, Better Stack, or a cron `curl`) on:

- `https://api.boxos-app.de/health` – expects HTTP 200
- `https://app.boxos-app.de` – expects HTTP 200

Logs: `docker compose -f docker-compose.prod.yml logs -f backend` (rotated at
5 × 10 MB per container).
