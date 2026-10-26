#!/usr/bin/env bash
set -euo pipefail

echo "📣 Starting the AHA service..."

SOURCE_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

source "$SOURCE_DIR/../env.sh"
rune_env_load

SRV_DIR="/srv/syn/core/${AHA_SERVICE_NAME}/"
rune_env_link "$SRV_DIR"

sudo -n -u "$SVC_USER" mkdir -p "$SRV_DIR/storage"
sudo -n -u "$SVC_USER" cp "$SOURCE_DIR/compose.yml" "$SRV_DIR/compose.yml"

# Pull the latest images for the AHA service and its dependencies.
docker compose -f "$SRV_DIR/compose.yml" pull

# Start the AHA service in detached mode, killing it first if it is already running.
docker compose -f "$SRV_DIR/compose.yml" down
docker compose -f "$SRV_DIR/compose.yml" up -d

echo "✅ AHA service started successfully."
echo "⏳ Waiting for 30 seconds to allow AHA to start and before generating registration URLs..."
sleep 30

url=$(docker compose -f "$SRV_DIR/compose.yml" exec -T aha_service python -m \
  synapse.tools.aha.provision.service "$AXON_SERVICE_NAME" \
  | sed 's/^one-time use URL: //'
)
rune_env_set AXON_AHA_REG_URL "$url"

url=$(docker compose -f "$SRV_DIR/compose.yml" exec -T aha_service python -m \
  synapse.tools.aha.provision.service "$JSONSTOR_SERVICE_NAME" \
  | sed 's/^one-time use URL: //'
)
rune_env_set JSONSTOR_AHA_REG_URL "$url"

url=$(docker compose -f "$SRV_DIR/compose.yml" exec -T aha_service python -m \
  synapse.tools.aha.provision.service "$CORTEX_SERVICE_NAME" \
  | sed 's/^one-time use URL: //'
)
rune_env_set CORTEX_AHA_REG_URL "$url"

echo "✅ Registration URLs generated and saved to $RUNE_ENV_FILE."
