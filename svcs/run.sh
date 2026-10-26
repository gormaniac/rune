#!/usr/bin/env bash
set -euo pipefail

echo "📣 Starting the Optional Storm Services..."

SOURCE_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SRV_DIR="/srv/syn/svcs/"

source "$SOURCE_DIR/../env.sh"
rune_env_load

SKIP_AHA=false
for arg in "$@"; do
  [[ "$arg" == "--skip-aha" ]] && SKIP_AHA=true
done

if [[ "$SKIP_AHA" == false ]]; then
  "$SOURCE_DIR/register_svcs.sh"
  rune_env_load
fi

rune_env_require IPAPI_AHA_REG_URL YARASTORM_AHA_REG_URL
rune_env_link "$SRV_DIR"

# Prepare storage for the container UID, separate from service-user configuration.
for svc in "${IPAPI_SERVICE_NAME}" "${YARASTORM_SERVICE_NAME}"; do
  rune_storage_prepare "${SRV_DIR%/}/$svc/storage"
done

# Copy the compose.yaml file to the /srv/syn/svcs/ directory, ensuring it is owned by the SVC_USER.
sudo -n -u "$SVC_USER" cp "$SOURCE_DIR/compose.yaml" "$SRV_DIR/compose.yaml"

# Pull the latest images for the Optional Storm Services and their dependencies.
docker compose -f "$SRV_DIR/compose.yaml" pull

# Start the Optional Storm Services in detached mode, killing them first if they are already running.
docker compose -f "$SRV_DIR/compose.yaml" down
docker compose -f "$SRV_DIR/compose.yaml" up -d

echo "✅ Optional Storm Services started successfully."
