#!/usr/bin/env bash
set -euo pipefail

SOURCE_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

source "$SOURCE_DIR/../env.sh"
rune_env_load
SRV_DIR="/srv/syn/core/${AHA_SERVICE_NAME}"
rune_env_link "$SRV_DIR"

echo "📣 Registering the Optional Storm Services with Aha..."

url=$(docker compose -f "$SRV_DIR/compose.yml" exec -T aha_service python -m \
  synapse.tools.aha.provision.service "$IPAPI_SERVICE_NAME" \
  | sed 's/^one-time use URL: //'
)
rune_env_set IPAPI_AHA_REG_URL "$url"

url=$(docker compose -f "$SRV_DIR/compose.yml" exec -T aha_service python -m \
  synapse.tools.aha.provision.service "$YARASTORM_SERVICE_NAME" \
  | sed 's/^one-time use URL: //'
)
rune_env_set YARASTORM_AHA_REG_URL "$url"

echo "✅ Optional Storm Services registered successfully."
