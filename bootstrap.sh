#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID:-$(id -u)}" -eq 0 ]] && [[ "${RUNE_ALLOW_ROOT:-0}" != "1" ]]; then
    echo "Error: run this script as a non-root user with Docker access." >&2
    echo "If you intentionally want root, rerun with RUNE_ALLOW_ROOT=1." >&2
    exit 1
fi

# If .env isn't present, copy .env.example to .env and use default values.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ ! -f "$SCRIPT_DIR/.env" ]]; then
  mv "$SCRIPT_DIR/.env.example" "$SCRIPT_DIR/.env"
fi

set -o allexport
source "$SCRIPT_DIR/.env"
set +o allexport

# Command-line args override values sourced from .env.
_AHA_DOMAIN_GIVEN=0
_NETWORK_DEVICE_GIVEN=0
for arg in "$@"; do
  case "$arg" in
    --dev-name=*)   NETWORK_DEVICE="${arg#*=}"; _NETWORK_DEVICE_GIVEN=1 ;;
    --aha-domain=*) AHA_DOMAIN="${arg#*=}"; _AHA_DOMAIN_GIVEN=1 ;;
  esac
done

if (( _AHA_DOMAIN_GIVEN )); then
  sed -i '' "s/^AHA_DOMAIN=.*/AHA_DOMAIN=$AHA_DOMAIN/" "$SCRIPT_DIR/.env"
fi

if (( _NETWORK_DEVICE_GIVEN )); then
  sed -i '' "s/^NETWORK_DEVICE=.*/NETWORK_DEVICE=$NETWORK_DEVICE/" "$SCRIPT_DIR/.env"
fi

# TODO - Do we want to control this actually? Have bootstrap create the user if needed?
if ! id "$SVC_USER" >/dev/null 2>&1; then
    echo "Error: The configured SVC_USER '$SVC_USER' does not exist on this host." >&2
    exit 1
fi

# Check if we can run docker commands.
if ! command -v docker >/dev/null 2>&1; then
    echo "Error: docker command not found. Install Docker first." >&2
    exit 1
fi

# Check if the current user can access the Docker daemon.
if ! docker info >/dev/null 2>&1; then
    echo "Error: current user cannot access Docker daemon." >&2
    echo "Run as a user with Docker socket access (for example docker group) or configure rootless Docker." >&2
    exit 1
fi

# Create the docker macvlan network
docker network create -d macvlan --subnet="$NETWORK_CIDR" --gateway="$GATEWAY_IP_ADDRESS" \
  -o parent="$NETWORK_DEVICE" $NETWORK_NAME

# Create the parent /srv/syn directory and set ownership to the service user.
sudo mkdir -p /srv/syn
sudo chown -R "$SVC_USER":"$SVC_USER" /srv/syn

# Copy the .env file into /srv/syn so all services can access it.
cp "$SCRIPT_DIR/.env" /srv/syn/.env
