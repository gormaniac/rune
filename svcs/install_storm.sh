#!/usr/bin/env bash
set -euo pipefail

SOURCE_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

set -o allexport
source "$SOURCE_DIR/../.env"
set +o allexport

cd /srv/syn/core

docker compose exec "$CORTEX_SERVICE_NAME" python -m synapse.tools.storm cell:///vertex/storage \
    pkg.load https://github.com/gormaniac/stormlibpp/releases/latest/download/utils.json

docker compose exec "$CORTEX_SERVICE_NAME" python -m synapse.tools.storm cell:///vertex/storage \
    pkg.load https://github.com/gormaniac/stormlibpp/releases/latest/download/lookup-storm.json

docker compose exec "$CORTEX_SERVICE_NAME" python -m synapse.tools.storm cell:///vertex/storage \
    pkg.load https://github.com/gormaniac/stormlibpp/releases/latest/download/dnsstorm.json

docker compose exec "$CORTEX_SERVICE_NAME" python -m synapse.tools.storm cell:///vertex/storage \
    pkg.load https://github.com/gormaniac/stormlibpp/releases/latest/download/stix.json