# MicroBin on Railway — wrapper around the pinned upstream image.
#
# Why a wrapper at all (house style: bake constants, keep the deploy
# form minimal, and survive Railway's root-owned volumes):
# - PORT: MicroBin reads its HTTP port from MICROBIN_PORT only
#   (default 8080) and ignores Railway's generic PORT (verified in
#   szabodanika/microbin master src/args.rs: `#[clap(short, long,
#   env = "MICROBIN_PORT", default_value_t = 8080)]`). entrypoint.sh
#   exports MICROBIN_PORT=$PORT on every boot. Fail loud if the
#   remap did not land — a server listening on the wrong port is a
#   silent dead deploy.
# - NO SHELL IN THE IMAGE: the upstream image is distroless
#   (gcr.io/distroless/cc-debian12) — no sh, no coreutils — so the
#   wrapper adds a static busybox binary (pinned by digest below)
#   solely to run entrypoint.sh. The busybox stage contributes one
#   file, /bin/busybox; nothing else from it is used.
# - USER root: the published image config carries no USER directive
#   (verified via the Docker Hub registry API 2026-11-10), so it
#   already runs as root, but the wrapper states USER root
#   explicitly so a future upstream non-root switch cannot silently
#   break writes to Railway's root-owned volume. (The repo
#   Dockerfile declares USER 65532:65532 — the published image does
#   not carry it — but the wrapper does not depend on either.)
# - DATA: one Railway volume at /data. MICROBIN_DATA_DIR (baked
#   below) puts everything on the volume: database.sqlite, the
#   attachments/ file store, and public/ (verified in
#   src/util/db_sqlite.rs and src/util/misc.rs — every path is
#   built from ARGS.data_dir), so pastas, files, and settings
#   survive restarts and redeploys.
# - ADMIN: upstream defaults are admin / m1cr0b1n (args.rs) and the
#   admin page warns loudly when they are left in place, so the
#   password is a generated deploy-form variable
#   (MICROBIN_ADMIN_PASSWORD=${{secret(16)}}) and the username is
#   baked as `admin`. There is no setup wizard and no email step:
#   open /auth_admin and log in with those credentials.
# - PUBLIC URL: derived at boot from the live RAILWAY_PUBLIC_DOMAIN
#   by entrypoint.sh — never a template-expression variable. A
#   https://${{RAILWAY_PUBLIC_DOMAIN}} default resolves to a bare
#   "https://" on first deploy (no domain exists yet); MicroBin
#   tolerates an unset value (it falls back to relative URLs and
#   warns in the admin page), but the boot-derived value is what
#   makes copy-URL and QR links correct behind the proxy. (Same
#   shape as the 2026-10-29 Spliit BASE_URL and 2026-11-08 LLDAP
#   HTTP_URL lessons.)
# - TELEMETRY / UPDATE CHECKS: disabled by default (baked below).
#   A self-hosted pastebin has no business phoning home; the
#   version is pinned here, so update checks add nothing.
# - No Docker HEALTHCHECK: rely on Railway's external
#   healthcheckPath. The upload page at / is unauthenticated and
#   returns 200 (create::index) — that is the platform probe.
#
# Upstream: MicroBin v2.1.0 (BSD-3-Clause), image pinned by manifest
# digest, verified 2026-11-10 via the Docker Hub API (tag 2.1 and
# tag 2.1.4 share this manifest digest; amd64 image digest
# sha256:e66131ff155fcf37d7daa64ec0a457d22d44f0057e5422efb6f085c0967700fc).
# NOTE: the FROM uses the digest WITHOUT a tag — Railpack 0.43.0
# fails to detect a Dockerfile whose FROM carries both a tag and a
# digest (redeploys die in the plan phase with "could not determine
# how to build the app"); the digest-only form builds under both
# the Dockerfile builder and Railpack (verified 2026-11-05 —
# TimeTagger's digest-only FROM is the precedent).

# busybox 1.37.0-musl (static binary, shell for entrypoint.sh only)
FROM busybox@sha256:f6a95d611e0a8780fabdb2aec43e31275b2720dfefa3e41b16835bfc42454478 AS busybox

# danielszabo99/microbin:2.1 (== 2.1.4)
FROM danielszabo99/microbin@sha256:6660e5ccad0d764fa3c0032464ffb8f4b4f28c92a2eb9e39202b94cdc5b68909

USER root

COPY --from=busybox /bin/busybox /bin/busybox
COPY entrypoint.sh /railway-entrypoint.sh
RUN chmod +x /railway-entrypoint.sh

# Baked constants (see header): data dir on the volume, admin
# username, telemetry and update checks off. The HTTP port is
# mapped from Railway's PORT by the entrypoint on every boot.
ENV MICROBIN_DATA_DIR=/data \
    MICROBIN_ADMIN_USERNAME=admin \
    MICROBIN_DISABLE_TELEMETRY=true \
    MICROBIN_DISABLE_UPDATE_CHECKING=true

# Documentation only: Railway routes to $PORT at runtime (see
# entrypoint.sh); 8080 is the upstream default the image would use
# without the wrapper's remap.
EXPOSE 8080

ENTRYPOINT ["/bin/busybox", "sh", "/railway-entrypoint.sh"]
