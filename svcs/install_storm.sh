#!/usr/bin/env bash
set -euo pipefail

SOURCE_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

source "$SOURCE_DIR/../env.sh"
rune_env_load
rune_env_link /srv/syn/core

cd /srv/syn/core

docker compose exec -T cortex_service python -m synapse.tools.storm cell:///vertex/storage \
    'pkg.load --raw https://github.com/gormaniac/stormlibpp/releases/latest/download/utils.json'

docker compose exec -T cortex_service python -m synapse.tools.storm cell:///vertex/storage \
    'pkg.load --raw https://github.com/gormaniac/stormlibpp/releases/latest/download/lookup-storm.json'

docker compose exec -T cortex_service python -m synapse.tools.storm cell:///vertex/storage \
    'pkg.load --raw https://github.com/gormaniac/stormlibpp/releases/latest/download/dnsstorm.json'

docker compose exec -T cortex_service python -m synapse.tools.storm cell:///vertex/storage \
    'pkg.load --raw https://github.com/gormaniac/stormlibpp/releases/latest/download/stix.json'