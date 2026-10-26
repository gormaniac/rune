#!/usr/bin/env bash

RUNE_ENV_FILE=/srv/syn/.env
RUNE_ENV_HELPER="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/env.sh"

rune_env_load() {
    if [[ ! -r "$RUNE_ENV_FILE" ]]; then
        echo "Error: cannot read $RUNE_ENV_FILE. Run bootstrap.sh first." >&2
        return 1
    fi
    set -o allexport
    source "$RUNE_ENV_FILE"
    set +o allexport
}

rune_env_set() {
    printf '%s\n' "$2" | sudo -n -u "$SVC_USER" bash "$RUNE_ENV_HELPER" "$1"
}

rune_env_require() {
    local key
    for key in "$@"; do
        if [[ -z "${!key:-}" ]]; then
            echo "Error: $key is missing from $RUNE_ENV_FILE. Register services first." >&2
            return 1
        fi
    done
}

rune_env_link() {
    local directory="$1"
    if [[ -e "$directory/.env" && ! -L "$directory/.env" ]]; then
        echo "Error: $directory/.env is not a symlink; move its settings into $RUNE_ENV_FILE first." >&2
        return 1
    fi
    sudo -n -u "$SVC_USER" mkdir -p "$directory"
    sudo -n -u "$SVC_USER" ln -sfn "$RUNE_ENV_FILE" "$directory/.env"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    set -euo pipefail
    key="${1:-}"
    if [[ ! "$key" =~ ^[A-Z][A-Z0-9_]*$ ]]; then
        echo "Error: invalid configuration key." >&2
        exit 1
    fi
    IFS= read -r value
    if [[ "$value" == *"'"* || "$value" == *$'\r'* ]] || IFS= read -r extra; then
        echo "Error: configuration values must be a single line without single quotes." >&2
        exit 1
    fi
    temporary=$(mktemp "${RUNE_ENV_FILE}.XXXXXX")
    trap 'rm -f "$temporary"' EXIT
    cp -p "$RUNE_ENV_FILE" "$temporary"
    found=false
    {
        while IFS= read -r line || [[ -n "$line" ]]; do
            if [[ "$line" =~ ^[[:space:]]*(export[[:space:]]+)?${key}= ]]; then
                if [[ "$found" == false ]]; then
                    printf "%s='%s'\n" "$key" "$value"
                    found=true
                fi
            else
                printf '%s\n' "$line"
            fi
        done < "$RUNE_ENV_FILE"
        if [[ "$found" == false ]]; then
            printf "%s='%s'\n" "$key" "$value"
        fi
    } > "$temporary"
    mv -f "$temporary" "$RUNE_ENV_FILE"
fi