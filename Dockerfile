# Survos SSO — thin pin/extend over the official authentik image.
# The FROM tag IS our version pin (in git). Bump it, commit, redeploy.
# authentik migrates its own schema on boot (the `server` process), so an
# upgrade is: bump, push, watch the deploy log. Read the release notes first —
# authentik only supports upgrading one minor (YYYY.M) at a time.
FROM ghcr.io/goauthentik/server:2026.8.3

# ---------------------------------------------------------------------------
# NON-SECRET configuration lives here, in git. Dokku config carries only the
# secrets (see README). Same split as imgproxy/mattermost.
# ---------------------------------------------------------------------------

# Global Postgres (survos_pg on the fsn1 host), never a dokku postgres service.
# The app needs docker-options `--add-host=host.docker.internal:host-gateway`.
# Its own `authentik` login role, owner of the `authentik` database — not the
# `postgres` superuser — so the IdP's credentials unlock nothing else.
# AUTHENTIK_POSTGRESQL__PASSWORD is the only secret part and comes from config.
# Since 2025.10 authentik keeps sessions, cache and the task queue in Postgres
# too — there is no Redis to run.
ENV AUTHENTIK_POSTGRESQL__HOST=host.docker.internal \
    AUTHENTIK_POSTGRESQL__PORT=5432 \
    AUTHENTIK_POSTGRESQL__NAME=authentik \
    AUTHENTIK_POSTGRESQL__USER=authentik

# Outbound mail (password recovery, verification) through the same Brevo relay
# as mattermost. AUTHENTIK_EMAIL__PASSWORD is the secret (Brevo SMTP key).
ENV AUTHENTIK_EMAIL__HOST=smtp-relay.brevo.com \
    AUTHENTIK_EMAIL__PORT=465 \
    AUTHENTIK_EMAIL__USERNAME=tacman@gmail.com \
    AUTHENTIK_EMAIL__USE_SSL=true \
    AUTHENTIK_EMAIL__USE_TLS=false \
    AUTHENTIK_EMAIL__FROM="Survos Login <tacman@gmail.com>"

ENV AUTHENTIK_LOG_LEVEL=info \
    AUTHENTIK_ERROR_REPORTING__ENABLED=false \
    AUTHENTIK_DISABLE_UPDATE_CHECK=true

# Our blueprints: one file per relying party (the Symfony apps). authentik
# watches /blueprints and applies every file it finds, on boot and on change,
# so the OIDC clients are declared in git, not clicked together in the admin.
COPY --chown=1000:1000 blueprints/ /blueprints/survos/

# Museado logo and favicon for the login pages (blueprints/branding.yaml points at
# them). /web/dist is what authentik serves as /static/dist.
COPY branding/ /web/dist/assets/museado/

# Dokku runs the Procfile processes with this image's ENTRYPOINT
# (`dumb-init -- ak`), so `web: server` becomes `ak server`.
COPY Procfile /Procfile

# The server listens on 9000 (http) and 9443 (https, self-signed). Dokku
# terminates TLS and maps 80/443 -> 9000.
EXPOSE 9000
