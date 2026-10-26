# Rune

Synapse RunEverything - A [Synapse](https://github.com/vertexproject/synapse) "appliance" (docker compose script(s) to run Synapse/Storm Services on one machine). The goal is to provide an easy way to run all core Synapse Services in one go + optionally some supported community Storm Services. Minimal interaction will be required to register services with Aha. And of course, configuration tweaking will likely be needed to suit your environment (especially the network ranges).

The project is split into 3 docker compose files that build on eachother.
1. `aha/compose.yml` - run the Synapse Aha server to initialize an environment.
    - This has to run first so the remaining servers can register with it
    - Startup waits for Aha's local Synapse health check to pass before generating registration URLs for the core services.
        - Registration URLs are saved directly to `/srv/syn/.env`, replacing any previous values for those services.
    - You can always skip this, setup your own Aha server, and generate your own registration URLs for the next step.
2. `core/compose.yaml` - run only the core [Synapse Services](https://synapse.docs.vertex.link/en/latest/synapse/glossary.html#gloss-svc-synapse) published by The Vertex Project.
    - This is the "Synapse appliance".
    - Use this if you want to deploy or test a fully featured open-source Synapse instance instead of just a Cortex. Or if you plan to only integrate with your own list of additional Storm Services.
    - Cortex, JSONStor, Axon
3. `svcs/compose.yaml` - run a currated list of community [Storm Services](https://synapse.docs.vertex.link/en/latest/synapse/glossary.html#service-storm) + installs several community Storm Rapid Power-Ups directly onto your Cortex.
    - Requires some bootstrap scripts to run first to generate Aha registration URLs.
        - Registration URLs for these services are also saved directly to `/srv/syn/.env`.
    - Starts the following community Storm Services:
        - yarastorm
        - ip_api
        - The following are planned:
            - synapse-fileparser
            - unnatrib
            - shodan
            - crt.sh
    - Installs the following community Rapid Power-Ups on the Cortex:
        - [dnsstorm](https://github.com/gormaniac/stormlibpp/tree/main/src/pkgs/dnsstorm)
        - [lookup-storm](https://github.com/gormaniac/stormlibpp/tree/main/src/pkgs/lookup-storm)
        - [utils](https://github.com/gormaniac/stormlibpp/tree/main/src/pkgs/utils)
        - [stix](https://github.com/gormaniac/stormlibpp/tree/main/src/pkgs/stix)

# Architecture

This project creates an "appliance" for running services so, containers expect to all be run on the same host. However, it's possible to split each compose script and run them each on a separate host. Some networking changes will need to be made to accomodate.

Reference [Synapse's own docs](https://synapse.docs.vertex.link/en/latest/synapse/deploymentguide.html#introduction) for more info on their service's deployment architecture. In short, the Aha service allows everything to talk to eachother, the Cortex is the main querying and writing service, and the remainder is support. Everything needs to be able to talk to eachother (with some exception, change this at your own risk), but only the Aha service needs a domain name. The community Storm Services will also need to be able to talk to Aha and the core Synapse Services.

No mirrors or query pools are configured in these scripts, given the "appliance" nature if the host fails so would both the primary and mirror together. There's also limited resources on the same host. So while they might still have value for upgrades, container failures, etc., they're skipped in this project. The configuration does have a `PREFIX` variable to make it easy to setup a 2nd full appliance and register these services as mirrors.

## Networking

The compose files setup a custom network so that everything can talk to eachother - `rune-network`. IPs are assigned to each container so that clients can communicate with the services. These can be set within the `.env` configuration file.

Since docker cannot control domain names on a network, you're responsible for making sure that the Aha service has a DNS record somewhere your clients can reach. However, the benefit of using a shared docker network is that all containers can resolve IPs via the container name. So, the appliance setup works without assigning any DNS records.

In order to enable clients to talk to containers on the host, a docker network is created using `macvlan`. So the project requires you to pass the network device used for setup. This also means that each container get's it's own IP address. By default, the project uses `10.10.10.64/28` and assigns IPs sequentially in the order services are defined. These can be configured in `/srv/syn/.env` - when starting a 2nd mirror appliance these IPs need to be changed from whatever is used on the primary.

## Filesystem

Synapse/Storm Services require persistant storage. Each service uses a docker volume mapped to `/vertex/storage` on the container. On the host side, each service get's a directory under `/srv/syn`. Core Synapse Services (including Aha) live under `/srv/syn/core` and Storm Services live under `/srv/syn/svcs`.

Containers run as UID `999`, while `SVC_USER` manages host configuration and Compose files. Before startup, launchers recursively assign each service's storage tree to UID `999` and grant its owner access to the storage directory. This also repairs existing storage ownership without changing `/srv/syn/.env` or configuration ownership. This assumes normal rootful Docker UID mapping; rootless Docker or user-namespace remapping requires corresponding host ownership adjustments.

However, since we're only working on 3 docker compose files, you'll need to manage the Aha service from `/srv/syn/core/${AHA_SERVICE_NAME}/`, all of the other core Synapse Services from `/srv/syn/core`, and all of the Storm Services from `/srv/syn/svcs`. In other words...

To access the Aha container (assuming it has a service name of `00.aha`):
```bash
cd /srv/syn/core/00.aha/
docker compose exec aha_service /bin/bash
```

To access the Cortex container (assuming it has a service name of `00.cortex`):
```bash
cd /srv/syn/core/
docker compose exec cortex_service /bin/bash
```

To access the yarastorm container (assuming it has a service name of `00.yarastorm`):
```bash
cd /srv/syn/svcs/
docker compose exec yarastorm_service /bin/bash
```

### Shared Configuration

`/srv/syn/.env` is the only runtime configuration file. Bootstrap seeds it once from the repository's `.env`, if present, otherwise from `.env.example`. Existing canonical configuration is never replaced by the repository copy. After bootstrap, make all configuration changes in `/srv/syn/.env`; the repository's `.env` is no longer used.

Bootstrap creates `.env` symlinks in `/srv/syn/core` and `/srv/syn/svcs`. Aha startup also creates one in `/srv/syn/core/${AHA_SERVICE_NAME}`. Docker Compose reads these symlinks for interpolation, including when you run Compose directly in a deployed directory. Each Compose service explicitly maps the settings it needs into its container; the shared file is not injected wholesale into containers.

# Starting the appliance

If not already installed, setup [docker](https://docs.docker.com/engine/install/debian/) on the host.

The configured `SVC_USER` must already exist. Run the scripts as that user or an account in its group, with Docker access and noninteractive sudo permission for the setup commands and service-user operations. Newly created `/srv/syn/.env` files are owned by `SVC_USER` and its matching group with mode `0640`. Keep this file readable only by trusted operators: it contains one-time provisioning URLs.

To start everything in one go, do the following:
```bash
git clone https://github.com/gormaniac/rune.git
cd rune
cp .env.example .env
# edit .env for initial setup, including SVC_USER and networking
./rune.sh
```

On an existing installation, edit `/srv/syn/.env` instead. The `.env.example` template is never moved or modified by bootstrap.

## Deploying separately/on multiple hosts

If you'd like to start each compose file seperately (separate host deployments, self-managed Aha service, etc.) you can go into their own folder and use their `run.sh` script. However, you'll need to bootstrap the env first (mainly creates the macvlan network). If using a split setup, you'll need to run this on each host.

1. Clone the repo and bootstrap the environment:
    ```bash
    git clone https://github.com/gormaniac/rune.git
    cd rune/
    ```

2. Copy the example configuration and edit it for initial setup. For an existing installation, edit `/srv/syn/.env` instead.
    ```bash
    cp .env.example .env && code .env
    ```

3. Run the bootstrap script - do this once on every host.
    ```bash
    ./bootstrap.sh
    ```

4. Start the Aha service:
    ```bash
    cd aha/
    ./run.sh
    ```

5. Aha startup saves `AXON_AHA_REG_URL`, `JSONSTOR_AHA_REG_URL`, and `CORTEX_AHA_REG_URL` in `/srv/syn/.env`. If core services run on a different host, securely transfer those values into that host's `/srv/syn/.env`, retaining its host-specific networking settings.

6. Start the Core Synapse Services:
    ```bash
    cd ../core
    ./run.sh
    ```

    If you're running the Synapse Services from a different host than the Aha service, you will need to edit `core/compose.yaml` to point to Aha's FQDN instead of just the container name.

7. Start the optional Storm Services and optional Rapid Power-Ups:
    ```bash
    cd ../svcs
    ./run.sh
    ./install_storm.sh
    ```

    Step 7 assumes the optional Storm Services run on the same host as Aha. Otherwise, run `svcs/register_svcs.sh` from a checkout on the Aha host, then securely transfer `IPAPI_AHA_REG_URL` and `YARASTORM_AHA_REG_URL` into the services host's `/srv/syn/.env`. Start them with `./run.sh --skip-aha` to avoid attempting local registration.

    The same is true with the `./install_storm.sh`  script. If the Cortex is on a separate host, you'll need to copy this to that host and run it    there.

# Configuration

Everything is configured via `/srv/syn/.env`. The included `.env.example` provides initial defaults; bootstrap can use it directly or seed from a customized repository `.env`. Add service-specific variables to `/srv/syn/.env` and reference them explicitly in the relevant Compose service's `environment` section. Keep the file compatible with both Bash sourcing and Docker Compose interpolation. See each service's documentation for configuration options.

The project tries to use default service configurations wherever possible; however, there's some custom configuration options used (like always starting an HTTP API for each service).

There are 3 configuration variables you will likely ***always*** have to change and 1 series of variables:
- `AHA_DOMAIN`
    - The domain suffix to append to the Aha service's name. 
    - By default `rune.local`.
        - Making the default Aha domain `00.aha.rune.local`.
    - This can be changed by passing `--aha-domain=<suffix>` to the `rune.sh` or `bootstrap.sh` scripts.
- `NETWORK_DEVICE`
    - The name of the network device to attach the docker macvlan to.
    - By default `eth0`.
    - This can be changed by passing `--dev-name=<name>` to the `rune.sh` or `bootstrap.sh` scripts.
- `NETWORK_CIDR`
    - The CIDR range for the docker macvlan network that hosts get IP addresses assigned in.
    - By default `10.10.10.64/26`.
- `*_IP_ADDRESS`
    - If you change the above, you'll want to change the IP address for each service as well.
    - Where `*` is the service name minus the numeral prefix (ie `CORTEX` for the service `00.cortex`).
    - `GATEWAY_IP_ADDRESS` is not tied to a service but is the gateway IP assigned to the network.

## Configuration Updates

Use service-specific keys in `/srv/syn/.env` when a service needs a different setting. There are no separate override files. The `--aha-domain` and `--dev-name` bootstrap options update the canonical file directly, including on an existing installation.

For upgrades from the previous layout, manually merge any still-needed values from old registration or override files into `/srv/syn/.env`. These files are no longer read, and are not automatically merged or deleted. If a deployed Compose directory already has a regular `.env` file, move its settings into the canonical file and remove the local file before starting the scripts; they will not overwrite it with a symlink.

## Aha Registration

Aha startup uses Docker Compose's `up --wait --wait-timeout` support to wait up to 180 seconds for its health check to pass. Use a Compose version supporting those options. If startup fails or Aha remains unhealthy, the script prints container status and the last 100 log lines, then stops without generating registration URLs. A restart loop indicates a startup problem that must be resolved from those logs; waiting longer alone may not help.

Aha startup writes the core services' registration URLs into `/srv/syn/.env`. Optional-service startup registers its services and writes their URLs into the same file before loading the updated configuration. Repeated registration replaces each existing key instead of appending duplicates. Launchers fail before stopping containers if required registration values are empty.

Use `svcs/run.sh --skip-aha` when registration values are already configured and local registration should be skipped. Provisioning URLs are one-time credentials, not reusable tokens; a new service instance may need a newly generated URL. Provisioned services retain their certificates in persistent storage.

## Verification

Run `bash tests/env.sh` for isolated configuration and registration tests. The suite uses temporary deployment paths and mocks privileged/deployment commands; it never starts containers or modifies `/srv/syn`. If Docker Compose is installed, it also validates all three deployed configurations against the shared `.env` symlinks.

## Secrets

Rune does not support injecting any secrets to containers at any time by default. This is intentional, mostly because Aha supports cert based auth and users should be encouraged to rely on that. But also because it overly complicates the spirit of this project - starting a fully featured open-source Synapse instance with as little user input as possible. Secrets should be managed seperately from env vars, and some users may wish to remove secrets from a host post-install. For more involved deployments that wish to rely on this project and use secrets, manual editing of the `.env` file and the docker compose scripts is needed. I'd recommend starting by using `.env` to define paths on the host where secrets are stored/injected and then relying on Docker's `secrets` feature in the compose script which reference the paths in `.env`.
