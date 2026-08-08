#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Get arguments from command line and pass them to the bootstrap script.
# If no arguments are provided, the bootstrap script will use the values from .env.
NETWORK_DEVICE=""
AHA_DOMAIN=""
NETWORK_DEVICE_ARG=""
AHA_DOMAIN_ARG=""

for arg in "$@"; do
  case "$arg" in
    --dev-name=*)  NETWORK_DEVICE="${arg#*=}" ;;
    --aha-domain=*) AHA_DOMAIN="${arg#*=}" ;;
  esac
done

# If arguments are passed to rune.sh,
# rebuild them so they can be passed to bootstrap.sh.
if [[ -n "$NETWORK_DEVICE" ]]; then
  NETWORK_DEVICE_ARG="--dev-name=$NETWORK_DEVICE"
fi

if [[ -n "$AHA_DOMAIN" ]]; then
  AHA_DOMAIN_ARG="--aha-domain=$AHA_DOMAIN"
fi

# Call the bootstrap script with the resolved arguments.
./bootstrap.sh $NETWORK_DEVICE_ARG $AHA_DOMAIN_ARG

cd "$SCRIPT_DIR/aha"
./run.sh

cd "$SCRIPT_DIR/core"
./run.sh

cd "$SCRIPT_DIR/svcs"
./run.sh
./install_storm.sh
