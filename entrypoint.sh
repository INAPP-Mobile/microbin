#!/bin/sh
# MicroBin Railway wrapper entrypoint (busybox sh — the upstream
# image is distroless and ships no shell, so the wrapper adds a
# static busybox binary solely to run this script).
#
# What it does, in order:
# - PORT: Railway injects PORT at runtime. MicroBin reads its HTTP
#   port from MICROBIN_PORT only (default 8080; verified in
#   szabodanika/microbin master src/args.rs — env
#   "MICROBIN_PORT"). Export MICROBIN_PORT=$PORT on every boot.
#   Fail loud if the remap did not land — a server listening on
#   the wrong port is a silent dead deploy.
# - PUBLIC URL: derive at boot from the live RAILWAY_PUBLIC_DOMAIN.
#   A template-expression default
#   (https://${{RAILWAY_PUBLIC_DOMAIN}}) resolves to a bare
#   "https://" on first deploy (no domain exists yet); MicroBin
#   tolerates an unset value (relative URLs + an admin-page
#   warning), but the boot-derived value is what makes copy-URL
#   and QR links correct behind the proxy. Only set it when a
#   real domain is present.
# - HANDOFF: exec the upstream binary exactly as the image does
#   (entrypoint `microbin`, resolved via PATH to
#   /usr/bin/microbin).

set -eu

PORT_VALUE="${PORT:-8080}"
export MICROBIN_PORT="$PORT_VALUE"

if [ "$MICROBIN_PORT" != "$PORT_VALUE" ]; then
  echo "MicroBin: ERROR HTTP port remap failed; refusing to start."
  exit 1
fi

# PUBLIC_URL: derive at boot from the live RAILWAY_PUBLIC_DOMAIN.
# Only set it when a real domain is present; otherwise leave it
# unset and MicroBin falls back to relative URLs.
if [ -n "${RAILWAY_PUBLIC_DOMAIN:-}" ]; then
  export MICROBIN_PUBLIC_PATH="https://${RAILWAY_PUBLIC_DOMAIN}"
fi

echo "MicroBin: HTTP on :${PORT_VALUE}, data in /data"
exec microbin
