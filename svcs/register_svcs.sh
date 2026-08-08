#!/usr/bin/env bash
set -euo pipefail

SOURCE_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SRV_DIR="/srv/syn/svcs/"

set -o allexport
source "$SOURCE_DIR/../.env"
set +o allexport

echo "📣 Registering the Optional Storm Services with Aha..."

url=$(docker compose -f "$SRV_DIR/compose.yml" exec "$AHA_SERVICE_NAME" python -m \
  synapse.tools.aha.provision.service "$IPAPI_SERVICE_NAME" \
  | sed 's/^one-time use URL: //'
)
echo "IPAPI_AHA_REG_URL=$url" >> "$SOURCE_DIR/.env.aha"

url=$(docker compose -f "$SRV_DIR/compose.yml" exec "$AHA_SERVICE_NAME" python -m \
  synapse.tools.aha.provision.service "$YARASTORM_SERVICE_NAME" \
  | sed 's/^one-time use URL: //'
)
echo "YARASTORM_AHA_REG_URL=$url" >> "$SOURCE_DIR/.env.aha"

echo "✅ Optional Storm Services registered successfully."
