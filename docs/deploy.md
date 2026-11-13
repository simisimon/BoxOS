# Deploying BoxOS on a VPS

One server runs everything: Postgres, the FastAPI backend and the Flutter web
build (`docker-compose.prod.yml`), behind the reverse proxy that already serves
the marketing site.

| URL | What |
|---|---|
| https://app.boxos-app.de | Web app (nginx in the `web` container, 127.0.0.1:8090) |
| https://api.boxos-app.de | Backend (127.0.0.1:8080) |
| https://boxos-app.de | Marketing site (unchanged; its login button links to the app) |

The production stack is invite-only (no sign-up, no demo accounts) and has
payments switched off: it passes no Stripe keys, and the backend refuses to
start with `BOXOS_ENV=production` if one is set. It also refuses dev passwords,
the template's `change-me` password, logged reset tokens and localhost CORS.

Our VPS (Hostinger) already runs **Traefik** for the marketing site
(`/docker/boxos-website`): Docker provider, entrypoints `web`/`websecure`,
certificate resolver `letsencrypt`. `docker-compose.traefik.yml` adds the
matching labels, so no extra proxy is needed. Section 5 has Caddy and nginx
for other servers.

All commands below run as root on the server, from `/docker/boxos`. To keep
them short:

```bash
alias boxos='docker compose -f docker-compose.prod.yml -f docker-compose.traefik.yml --env-file .env.prod'
```

## 1. Server prerequisites

Docker and Traefik are already set up on our Hostinger VPS. On a fresh
Debian/Ubuntu server:

```bash
apt update && apt install -y ca-certificates curl git unattended-upgrades
curl -fsSL https://get.docker.com | sh
dpkg-reconfigure -plow unattended-upgrades   # answer "Yes"
```

Firewall: only 22, 80 and 443 open (Hostinger: hPanel › VPS › Firewall, or
`ufw`). The compose file binds the backend and web ports to 127.0.0.1, so they
are not reachable from outside even though Docker bypasses ufw.

**Memory:** the Flutter web build runs on the server and needs a few GB of RAM.
Check with `free -h`. With less than ~4 GB, add swap before the first build:

```bash
fallocate -l 4G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile
echo '/swapfile none swap sw 0 0' >> /etc/fstab
```

(Alternative: build the web image on a Mac and push it to ghcr.io, like the
marketing site's image.)

## 2. DNS

At the DNS provider (Hostinger: hPanel › Domains › DNS), add A records pointing
at the VPS IP:

- `app` → VPS IP
- `api` → VPS IP
- optional: `staging-app`, `staging-api`

Wait until `dig +short app.boxos-app.de` and `dig +short api.boxos-app.de` show
the IP. Traefik can only get certificates once they do.

## 3. Code and secrets

The repository is private: add a read-only deploy key first
(`ssh-keygen -t ed25519 -f ~/.ssh/boxos_deploy -N ""`, put the `.pub` under
GitHub › BoxOS › Settings › Deploy keys).

```bash
GIT_SSH_COMMAND='ssh -i ~/.ssh/boxos_deploy' git clone git@github.com:simisimon/BoxOS.git /docker/boxos
cd /docker/boxos
git config core.sshCommand 'ssh -i ~/.ssh/boxos_deploy'
cp .env.prod.example .env.prod && chmod 600 .env.prod
sed -i "s|^POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=$(openssl rand -base64 32 | tr -d '/+=')|" .env.prod
```

Check `APP_URL` and `API_URL` in `.env.prod` (no trailing slash). The URLs are
built into the web app, so changing them needs a rebuild (`up -d --build`).

## 4. Start the stack

```bash
cd /docker/boxos
boxos up -d --build
boxos ps
curl -fsS http://127.0.0.1:8080/health
curl -I https://api.boxos-app.de/health
curl -I https://app.boxos-app.de
```

The first build takes several minutes (Flutter). The database schema is created
on the backend's first start (`backend/db.py`). The first HTTPS request can take
a few seconds while Traefik gets the certificate.

If the backend restarts in a loop, read why:
`boxos logs backend | grep "Refusing to start"`.
If HTTPS fails, check Traefik: `docker logs traefik-traefik-1 --tail 50`.

## 5. Other servers: Caddy or nginx

Only for a server without Traefik. Start the stack without the Traefik file
(`docker compose -f docker-compose.prod.yml --env-file .env.prod up -d --build`)
and point the proxy at the local ports.

**Caddy:** add the blocks from `deploy/Caddyfile` to the server's Caddyfile,
keep the existing site block, then `systemctl reload caddy`.

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
the two HTTPS server blocks certbot wrote.

## 6. First owner and test users

Accounts are created on the server; each command prints a generated password.

```bash
cd /docker/boxos
boxos exec backend python -m backend.manage create-user --email owner@example.com --name "Box Owner" --role admin
```

The owner logs in at https://app.boxos-app.de, goes to Profile › "Create box"
(or Home › "Create Box") and sets up the box. Then add members and trainers:

```bash
boxos exec backend python -m backend.manage list-gyms
boxos exec backend python -m backend.manage create-user --email coach@example.com --name "Coach" --role trainer --gym "<slug>"
boxos exec backend python -m backend.manage create-user --email member@example.com --name "Member" --role athlete --gym "<slug>"
```

Forgotten password: `... manage reset-password --email ...` (password reset by
email is not available yet). Remove access: `... manage deactivate-user --email ...`.

## 7. Backups

`deploy/backup.sh` writes a `pg_dump` and a tar of the uploads to
`/srv/boxos-backups` and keeps 14 days. It finds the containers by the
project name `boxos-prod`, so it works whichever proxy file was used.

```bash
crontab -e
# 15 3 * * * /docker/boxos/deploy/backup.sh >> /var/log/boxos-backup.log 2>&1
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
cd /docker/boxos
cp .env.prod .env.staging
# in .env.staging: APP_URL=https://staging-app.boxos-app.de, API_URL=https://staging-api.boxos-app.de,
# BACKEND_PORT=8081, WEB_PORT=8091, a new POSTGRES_PASSWORD, and for Traefik:
# TRAEFIK_NAME=boxos-staging, APP_HOST=staging-app.boxos-app.de, API_HOST=staging-api.boxos-app.de
docker compose -p boxos-staging -f docker-compose.prod.yml -f docker-compose.traefik.yml --env-file .env.staging up -d --build
PROJECT=boxos-staging ENV_FILE=.env.staging deploy/restore.sh /srv/boxos-backups/db-<stamp>.dump /srv/boxos-backups/uploads-<stamp>.tar.gz
```

Log in on the staging app and check that members, classes and images are
there. Stop it afterwards with
`docker compose -p boxos-staging -f docker-compose.prod.yml -f docker-compose.traefik.yml --env-file .env.staging down`
(add `-v` to delete its data too).

## 9. Updating

```bash
cd /docker/boxos
deploy/backup.sh
git pull
boxos up -d --build
curl -I https://api.boxos-app.de/health
```

There are no migrations yet: `backend/db.py` applies the schema on startup and
adds new tables and columns itself. Anything that changes or removes existing
data has to be done by hand, so read the commits before pulling and take a
backup first (as above).

## 10. Monitoring

Add an uptime check (e.g. UptimeRobot, Better Stack, or a cron `curl`) on:

- `https://api.boxos-app.de/health` – expects HTTP 200
- `https://app.boxos-app.de` – expects HTTP 200

Logs: `boxos logs -f backend` (rotated at 5 × 10 MB per container).
