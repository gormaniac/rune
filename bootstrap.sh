#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID:-$(id -u)}" -eq 0 ]] && [[ "${RUNE_ALLOW_ROOT:-0}" != "1" ]]; then
    echo "Error: run this script as a non-root user with Docker access." >&2
    echo "If you intentionally want root, rerun with RUNE_ALLOW_ROOT=1." >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/env.sh"

if [[ -f "$RUNE_ENV_FILE" ]]; then
  rune_env_load
else
  SEED_FILE="$SCRIPT_DIR/.env"
  if [[ ! -f "$SEED_FILE" ]]; then
    SEED_FILE="$SCRIPT_DIR/.env.example"
  fi
  set -o allexport
  source "$SEED_FILE"
  set +o allexport
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

if [[ ! -f "$RUNE_ENV_FILE" ]]; then
  sudo -n mkdir -p /srv/syn
  sudo -n chown "$SVC_USER":"$SVC_USER" /srv/syn
  sudo -n install -o "$SVC_USER" -g "$SVC_USER" -m 640 "$SEED_FILE" "$RUNE_ENV_FILE"
fi

for arg in "$@"; do
  case "$arg" in
    --dev-name=*) rune_env_set NETWORK_DEVICE "${arg#*=}" ;;
    --aha-domain=*) rune_env_set AHA_DOMAIN "${arg#*=}" ;;
  esac
done
rune_env_load
rune_env_link /srv/syn/core
rune_env_link /srv/syn/svcs

# Create the docker macvlan network
docker network create -d macvlan --subnet="$NETWORK_CIDR" --gateway="$GATEWAY_IP_ADDRESS" \
  -o parent="$NETWORK_DEVICE" "$NETWORK_NAME"
