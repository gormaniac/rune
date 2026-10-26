#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TEMPORARY=$(mktemp -d)
trap 'rm -rf "$TEMPORARY"' EXIT
REPO="$TEMPORARY/repo"
DEPLOY="$TEMPORARY/syn"
export TEST_DOCKER_LOG="$TEMPORARY/docker.log"
export TEST_SUDO_LOG="$TEMPORARY/sudo.log"
mkdir -p "$REPO" "$TEMPORARY/unrelated"

for file in env.sh bootstrap.sh rune.sh aha/run.sh core/run.sh svcs/run.sh svcs/register_svcs.sh svcs/install_storm.sh aha/compose.yml core/compose.yaml svcs/compose.yaml; do
    mkdir -p "$REPO/$(dirname "$file")"
    sed "s|/srv/syn|$DEPLOY|g" "$ROOT/$file" > "$REPO/$file"
    if [[ "$file" == *.sh ]]; then
        chmod +x "$REPO/$file"
        bash -n "$REPO/$file"
    fi
done
sed "s/^SVC_USER=.*/SVC_USER=$(id -un)/" "$ROOT/.env.example" > "$REPO/.env.example"

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

check_storage_path() {
    local compose="$1" group="$2" key="$3"
    grep -Fxq "      device: /srv/syn/$group/\${$key}/storage" "$ROOT/$compose" || fail "$compose has the wrong storage path for $key"
    [[ -d "$DEPLOY/$group/${!key}/storage" ]] || fail "launcher did not create storage for $key"
    grep -Fxq -- "-n chown -R 999 $DEPLOY/$group/${!key}/storage" "$TEST_SUDO_LOG" || fail "storage ownership was not assigned to the container UID for $key"
    grep -Fxq -- "-n chmod u+rwx $DEPLOY/$group/${!key}/storage" "$TEST_SUDO_LOG" || fail "storage owner was not granted access for $key"
}

expect_failure() {
    if "$@" > "$TEMPORARY/failure.log" 2>&1; then
        fail "expected command to fail: $*"
    fi
}

sudo() {
    printf '%s\n' "$*" >> "$TEST_SUDO_LOG"
    [[ "$1" == -n ]] || return 1
    shift
    if [[ "$1" == -u ]]; then
        shift 2
    fi
    case "$1" in
        chown) return 0 ;;
        install)
            shift
            while [[ "$1" == -o || "$1" == -g ]]; do shift 2; done
            command install "$@"
            ;;
        *) command "$@" ;;
    esac
}

docker() {
    printf '%s\n' "$*" >> "$TEST_DOCKER_LOG"
    if [[ "$*" == *" up -d --wait --wait-timeout "* ]]; then
        [[ "${TEST_AHA_WAIT_FAIL:-0}" == 0 ]] || return 1
    elif [[ "$*" == *synapse.tools.aha.provision.service* ]]; then
        printf 'one-time use URL: ssl://fixture/%s?token=$literal\n' "${!#}"
    elif [[ "$*" == *svcs/compose.yaml* && "$*" == *" up -d" ]]; then
        [[ "${IPAPI_AHA_REG_URL:-}" == 'ssl://fixture/00.ipapi?token=$literal' ]] || return 1
        [[ "${YARASTORM_AHA_REG_URL:-}" == 'ssl://fixture/00.yarastorm?token=$literal' ]] || return 1
    fi
}

sleep() { :; }
export -f sudo docker sleep

cd "$TEMPORARY/unrelated"
expect_failure bash "$REPO/core/run.sh"
grep -q 'Run bootstrap.sh first' "$TEMPORARY/failure.log" || fail "missing canonical file diagnostic"
RUNE_ALLOW_ROOT=1 bash "$REPO/bootstrap.sh" --dev-name=test0 --aha-domain=fixture.local
[[ -f "$REPO/.env.example" && ! -e "$REPO/.env" ]] || fail "bootstrap moved the template"
source "$REPO/env.sh"
rune_env_load
[[ "$NETWORK_DEVICE" == test0 && "$AHA_FQDN" == 00.aha.fixture.local ]] || fail "CLI overrides were not reloaded"
[[ -L "$DEPLOY/core/.env" && -L "$DEPLOY/svcs/.env" ]] || fail "bootstrap did not create symlinks"
[[ "$(readlink "$DEPLOY/core/.env")" == "$RUNE_ENV_FILE" ]] || fail "wrong symlink target"

printf 'PRESERVED=canonical\n' >> "$RUNE_ENV_FILE"
printf 'PRESERVED=repository\n' > "$REPO/.env"
RUNE_ALLOW_ROOT=1 bash "$REPO/bootstrap.sh"
grep -q '^PRESERVED=canonical$' "$RUNE_ENV_FILE" || fail "bootstrap overwrote canonical configuration"
expect_failure bash "$REPO/svcs/run.sh" --skip-aha
grep -q IPAPI_AHA_REG_URL "$TEMPORARY/failure.log" || fail "skip-aha accepted missing URLs"
if grep -q ' up -d' "$TEST_DOCKER_LOG"; then fail "services started without registration"; fi

rune_env_set IPAPI_AHA_REG_URL stale
printf 'export IPAPI_AHA_REG_URL=duplicate\n' >> "$RUNE_ENV_FILE"
cp "$RUNE_ENV_FILE" "$TEMPORARY/before-unhealthy"
export TEST_AHA_WAIT_FAIL=1
expect_failure bash "$REPO/aha/run.sh"
unset TEST_AHA_WAIT_FAIL
grep -q 'AHA did not become healthy' "$TEMPORARY/failure.log" || fail "unhealthy AHA did not report failure"
grep -Fq ' up -d --wait --wait-timeout ' "$TEST_DOCKER_LOG" || fail "startup did not wait for readiness"
grep -Fq ' ps -a' "$TEST_DOCKER_LOG" || fail "unhealthy AHA did not report container status"
grep -Fq ' logs --no-color --tail 100 aha_service' "$TEST_DOCKER_LOG" || fail "unhealthy AHA did not report logs"
if grep -q synapse.tools.aha.provision.service "$TEST_DOCKER_LOG"; then fail "unhealthy AHA attempted registration"; fi
cmp -s "$RUNE_ENV_FILE" "$TEMPORARY/before-unhealthy" || fail "unhealthy AHA changed registration values"
bash "$REPO/aha/run.sh"
bash "$REPO/core/run.sh"
bash "$REPO/svcs/run.sh"
rune_env_load
[[ "$IPAPI_AHA_REG_URL" == 'ssl://fixture/00.ipapi?token=$literal' ]] || fail "registration value did not round trip"
[[ "$(grep -c '^IPAPI_AHA_REG_URL=' "$RUNE_ENV_FILE")" == 1 ]] || fail "duplicate registration keys"
if grep -q '^export IPAPI_AHA_REG_URL=' "$RUNE_ENV_FILE"; then fail "old exported registration key remains"; fi
grep -Fq 'AHA_FQDN=${AHA_SERVICE_NAME}.${AHA_DOMAIN}' "$RUNE_ENV_FILE" || fail "lost template expressions"
[[ -L "$DEPLOY/core/$AHA_SERVICE_NAME/.env" ]] || fail "nested AHA symlink missing"
grep -Fq 'synapse.tools.healthcheck' "$DEPLOY/core/$AHA_SERVICE_NAME/compose.yml" || fail "AHA healthcheck missing"
grep -Fq "core/$AHA_SERVICE_NAME//compose.yml exec -T aha_service" "$TEST_DOCKER_LOG" || fail "core registration used wrong AHA stack"
grep -Fq "core/$AHA_SERVICE_NAME/compose.yml exec -T aha_service" "$TEST_DOCKER_LOG" || fail "optional registration used wrong AHA stack"

registrations=$(grep -c synapse.tools.aha.provision.service "$TEST_DOCKER_LOG")
bash "$REPO/svcs/run.sh" --skip-aha
[[ "$(grep -c synapse.tools.aha.provision.service "$TEST_DOCKER_LOG")" == "$registrations" ]] || fail "skip-aha registered services"
bash "$REPO/svcs/register_svcs.sh"
[[ "$(grep -c '^IPAPI_AHA_REG_URL=' "$RUNE_ENV_FILE")" == 1 ]] || fail "repeat registration appended keys"
bash "$REPO/svcs/install_storm.sh"
[[ "$(grep -c 'exec -T cortex_service' "$TEST_DOCKER_LOG")" == 4 ]] || fail "package installation used wrong core service"

printf '%s\n' "$RUNE_ENV_FILE" > "$TEMPORARY/expected-target"
cp "$RUNE_ENV_FILE" "$TEMPORARY/before"
expect_failure rune_env_set INVALID-KEY rejected
expect_failure rune_env_set IPAPI_AHA_REG_URL "bad'value"
expect_failure rune_env_set IPAPI_AHA_REG_URL $'bad\nsecond-line'
cmp -s "$RUNE_ENV_FILE" "$TEMPORARY/before" || fail "invalid update changed canonical file"
printf 'literal $value & backslash \\ end\n' > "$TEMPORARY/expected-value"
rune_env_set TEST_LITERAL 'literal $value & backslash \ end'
rune_env_load
printf '%s\n' "$TEST_LITERAL" > "$TEMPORARY/actual-value"
cmp -s "$TEMPORARY/expected-value" "$TEMPORARY/actual-value" || fail "literal value did not round trip"
[[ "$(ls -l "$RUNE_ENV_FILE" | cut -c 1-10)" == '-rw-r-----' ]] || fail "configuration permissions changed"

rm "$DEPLOY/svcs/.env"
printf 'LOCAL=keep\n' > "$DEPLOY/svcs/.env"
expect_failure rune_env_link "$DEPLOY/svcs"
grep -q '^LOCAL=keep$' "$DEPLOY/svcs/.env" || fail "symlink creation overwrote a local file"
rm "$DEPLOY/svcs/.env"
ln -s "$TEMPORARY/obsolete" "$DEPLOY/svcs/.env"
rune_env_link "$DEPLOY/svcs"
[[ "$(readlink "$DEPLOY/svcs/.env")" == "$RUNE_ENV_FILE" ]] || fail "obsolete symlink not refreshed"

rm -rf "$DEPLOY"
cp "$REPO/.env.example" "$REPO/.env"
printf 'SEEDED_FROM_REPO=yes\n' >> "$REPO/.env"
RUNE_ALLOW_ROOT=1 bash "$REPO/bootstrap.sh"
grep -q '^SEEDED_FROM_REPO=yes$' "$RUNE_ENV_FILE" || fail "bootstrap did not prefer repository .env"
bash "$REPO/aha/run.sh"
bash "$REPO/core/run.sh"
bash "$REPO/svcs/run.sh"
rune_env_load

check_storage_path aha/compose.yml core AHA_SERVICE_NAME
check_storage_path core/compose.yaml core AXON_SERVICE_NAME
check_storage_path core/compose.yaml core JSONSTOR_SERVICE_NAME
check_storage_path core/compose.yaml core CORTEX_SERVICE_NAME
check_storage_path svcs/compose.yaml svcs IPAPI_SERVICE_NAME
check_storage_path svcs/compose.yaml svcs YARASTORM_SERVICE_NAME
[[ "$(grep -Fc '    user: "999"' "$ROOT/aha/compose.yml")" == 1 ]] || fail "AHA UID differs from storage owner"
[[ "$(grep -Fc '    user: "999"' "$ROOT/core/compose.yaml")" == 3 ]] || fail "core UIDs differ from storage owner"
[[ "$(grep -Fc '    user: "999"' "$ROOT/svcs/compose.yaml")" == 2 ]] || fail "optional service UIDs differ from storage owner"
if grep '^-n chown -R ' "$TEST_SUDO_LOG" | grep -v '/storage$'; then fail "ownership changes extend beyond storage trees"; fi
echo 'PASS: all six volume paths and requested ownership match container storage requirements'

echo 'PASS: canonical initialization, CLI overrides, registration updates, reload, skip-aha, symlinks, and permissions'

if command docker compose version >/dev/null 2>&1; then
    for compose in "$DEPLOY/core/$AHA_SERVICE_NAME/compose.yml" "$DEPLOY/core/compose.yaml" "$DEPLOY/svcs/compose.yaml"; do
        (
            unset SVC_PREFIX AHA_SERVICE_NAME AHA_FQDN AHA_NETWORK AHA_IP_ADDRESS
            unset AXON_SERVICE_NAME JSONSTOR_SERVICE_NAME CORTEX_SERVICE_NAME IPAPI_SERVICE_NAME YARASTORM_SERVICE_NAME
            unset AXON_IP_ADDRESS JSONSTOR_IP_ADDRESS CORTEX_IP_ADDRESS IPAPI_IP_ADDRESS YARASTORM_IP_ADDRESS HTTPS_PORT NETWORK_NAME
            unset AXON_AHA_REG_URL JSONSTOR_AHA_REG_URL CORTEX_AHA_REG_URL IPAPI_AHA_REG_URL YARASTORM_AHA_REG_URL
            cd "$(dirname "$compose")"
            command docker compose config --quiet
            command docker compose config --environment > "$TEMPORARY/interpolation"
            grep -Fxq 'IPAPI_AHA_REG_URL=ssl://fixture/00.ipapi?token=$literal' "$TEMPORARY/interpolation" || fail "Compose changed literal registration URL"
            cd "$TEMPORARY/unrelated"
            command docker compose -f "$compose" config --quiet
        )
    done
    echo 'PASS: all Compose stacks resolve canonical symlinks without exported configuration'
else
    echo 'SKIP: Docker Compose is unavailable; configuration parsing was not checked'
fi