#!/usr/bin/env bash
set -euo pipefail

echo "📣 Starting the Core Synapse Services..."

SOURCE_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SRV_DIR="/srv/syn/core/"

set -o allexport
source "$SOURCE_DIR/../.env"
set +o allexport

if [[ ! -f "$SOURCE_DIR/.env.aha" ]]; then
  echo "⚠️ Error: .env.aha not found in $SOURCE_DIR" >&2
  exit 1
fi

sudo -u "$SVC_USER" cp -r "$SOURCE_DIR/.env.aha" "$SRV_DIR/.env.aha"

# Make the storage directories for each service, ensuring they are owned by the SVC_USER.
for svc in "${AXON_SERVICE_NAME}" "${JSONSTOR_SERVICE_NAME}" "${CORTEX_SERVICE_NAME}"; do
  sudo -u "$SVC_USER" mkdir -p "$SRV_DIR/$svc/storage"
done

# Copy the compose.yml file to the /srv/syn/core/ directory, ensuring it is owned by the SVC_USER.
sudo -u "$SVC_USER" cp -r "$SOURCE_DIR/compose.yml" "$SRV_DIR/compose.yml"

# Pull the latest images for the Core Synapse Services and their dependencies.
docker compose -f "$SRV_DIR/compose.yml" pull

# Start the Core Synapse Services in detached mode, killing them first if they are already running.
docker compose -f "$SRV_DIR/compose.yml" down
docker compose -f "$SRV_DIR/compose.yml" up -d

echo "✅ Core Synapse Services started successfully."