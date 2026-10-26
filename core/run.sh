#!/usr/bin/env bash
set -euo pipefail

echo "📣 Starting the Core Synapse Services..."

SOURCE_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SRV_DIR="/srv/syn/core/"

source "$SOURCE_DIR/../env.sh"
rune_env_load
rune_env_require AXON_AHA_REG_URL JSONSTOR_AHA_REG_URL CORTEX_AHA_REG_URL
rune_env_link "$SRV_DIR"

# Prepare storage for the container UID, separate from service-user configuration.
for svc in "${AXON_SERVICE_NAME}" "${JSONSTOR_SERVICE_NAME}" "${CORTEX_SERVICE_NAME}"; do
  rune_storage_prepare "${SRV_DIR%/}/$svc/storage"
done

# Copy the compose.yaml file to the /srv/syn/core/ directory, ensuring it is owned by the SVC_USER.
sudo -n -u "$SVC_USER" cp "$SOURCE_DIR/compose.yaml" "$SRV_DIR/compose.yaml"

# Pull the latest images for the Core Synapse Services and their dependencies.
docker compose -f "$SRV_DIR/compose.yaml" pull

# Start the Core Synapse Services in detached mode, killing them first if they are already running.
docker compose -f "$SRV_DIR/compose.yaml" down
docker compose -f "$SRV_DIR/compose.yaml" up -d

echo "✅ Core Synapse Services started successfully."