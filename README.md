# authentik — Survos identity provider (Dockerfile-driven Dokku app)

Self-hosted [authentik](https://goauthentik.io), the OpenID Connect provider for
centralized login across the Survos sites. First relying party: **zm**
(recordia.org) through Symfony 8.2's `oidc_login` authenticator.

**Live:** https://auth.survos.com (Dokku app `authentik` on fsn1).

## Versions (pinned)

- **Server:** `ghcr.io/goauthentik/server:2026.8.3` (`Dockerfile`). The `FROM` tag
  is the version pin. authentik migrates its schema on boot and supports
  upgrading only one minor (`YYYY.M`) at a time — read the release notes, bump,
  push.
- **No Redis.** Since 2025.10 authentik keeps sessions, cache and its task queue
  in Postgres. At our traffic that is plenty.

## Layout

| file | what |
|---|---|
| `Dockerfile` | version pin + every NON-secret setting (DB host/name/user, SMTP, logging) |
| `Procfile` | `web: server`, `worker: worker` — the two authentik processes |
| `app.json` | Dokku healthcheck on `/-/health/live/` |
| `blueprints/*.yaml` | one file per relying party: its OAuth2/OIDC provider + application |
| `branding/` | Museado logo + favicon, baked into the image; `blueprints/branding.yaml` sets title "Museado Login" |
| `docker-compose.yml` | local, on-demand stack against the local global Postgres |

### Blueprints: clients live in git

authentik applies every blueprint under `/blueprints` on boot and on change. Each
Symfony app gets one file declaring its provider (client id, redirect URIs, scopes,
RS256 signing key) and application. Client **secrets** are `!Env` references, set
in Dokku config, never in git.

Adding a site = copy `blueprints/zm.yaml`, rename, add `<APP>_OIDC_CLIENT_SECRET`
to Dokku config, push.

Anything changed by hand in the admin UI on a blueprint-managed object is
overwritten the next time the blueprint is applied. Users, groups and
flows-you-click-together are not managed here.

Gotcha: an OIDC provider **must** have a `signing_key`. Without one authentik
signs ID tokens HS256 with the client secret, and Symfony refuses HMAC ID tokens.

## Secrets (Dokku config)

```
AUTHENTIK_SECRET_KEY              never change after first boot
AUTHENTIK_POSTGRESQL__PASSWORD    survos_pg `authentik` role (owns db `authentik`)
AUTHENTIK_EMAIL__PASSWORD         Brevo SMTP key (same as mattermost)
AUTHENTIK_BOOTSTRAP_EMAIL         first boot only — akadmin
AUTHENTIK_BOOTSTRAP_PASSWORD      first boot only — akadmin
ZM_OIDC_CLIENT_SECRET             = zm prod OIDC_CLIENT_SECRET
ZM_DEV_OIDC_CLIENT_SECRET         = zm local OIDC_CLIENT_SECRET (.env.local)
```

Read names with `ssh fsn1 config:keys authentik`; `config:show` prints the values.
A copy of what was generated at setup lives in `.env.prod.local` (gitignored).

## Local (podman compose)

On demand only — local apps should use the `*-dev` clients on auth.survos.com.

```bash
cp .env.example .env          # fill in
podman exec survos_postgres psql -U postgres -c 'create database authentik'
podman compose up -d --build
open http://localhost:9000/   # akadmin / AUTHENTIK_BOOTSTRAP_PASSWORD
```

`./blueprints` is mounted read-only, so blueprint edits apply without a rebuild.

## Dokku deploy (how auth.survos.com was set up)

```bash
H=dokku@fsn1.survos.com

# Database on the GLOBAL postgres (survos_pg on the host), not a dokku service
# Its own login role, so the IdP's DB password unlocks nothing else.
ssh -o BatchMode=yes fsn1-root "docker exec -i survos_pg psql -U postgres" <<< "create role authentik login password '...'"
ssh -o BatchMode=yes fsn1-root "docker exec survos_pg psql -U postgres -c 'create database authentik owner authentik'"

ssh $H apps:create authentik
ssh $H docker-options:add authentik build,deploy,run "--add-host=host.docker.internal:host-gateway"
ssh $H docker-options:add authentik deploy,run "--shm-size=512m"
ssh $H config:set --no-restart authentik \
  AUTHENTIK_SECRET_KEY=... AUTHENTIK_POSTGRESQL__PASSWORD=... AUTHENTIK_EMAIL__PASSWORD=... \
  AUTHENTIK_BOOTSTRAP_EMAIL=tac@survos.com AUTHENTIK_BOOTSTRAP_PASSWORD=... \
  ZM_OIDC_CLIENT_SECRET=... ZM_DEV_OIDC_CLIENT_SECRET=...
ssh $H domains:set authentik auth.survos.com
ssh $H ports:set   authentik http:80:9000
ssh $H storage:ensure-directory authentik
ssh $H storage:mount authentik /var/lib/dokku/data/storage/authentik:/data   # media, certs
ssh $H ps:scale    authentik web=1 worker=1

git remote add dokku dokku@fsn1.survos.com:authentik
git push dokku main

ssh $H letsencrypt:set    authentik email tac@museado.org
ssh $H letsencrypt:enable authentik
```

`auth.survos.com` rides the `*.survos.com` Cloudflare wildcard — no DNS record of
its own.

### Relying party settings (any app)

```
provider_uri   https://auth.survos.com/application/o/<app>/
client_id      <app>        (or <app>-dev locally)
check_path     /oidc/callback
```
