# Rune

Synapse RunEverything - A [Synapse](https://github.com/vertexproject/synapse) "appliance" (docker compose script(s) to run Synapse/Storm Services on one machine). The goal is to provide an easy way to run all core Synapse Services in one go + optionally some supported community Storm Services. Minimal interaction will be required to register services with Aha. And of course, configuration tweaking will likely be needed to suit your environment (especially the network ranges).

The project is split into 3 docker compose files that build on eachother.
1. `aha/compose.yaml` - run the Synapse Aha server to initialize an environment.
    - This has to run first so the remaining servers can register with it
    - Post-install the compose script sleeps for a time then runs multiple commands to generate the Aha registration URLs for the core services.
        - The command outputs are written to a .env.aha file that's copied out of the container and supersede's runes .env file
    - You can always skip this, setup your own Aha server, and generate your own registration URLs for the next step.
2. `core/compose.yaml` - run only the core [Synapse Services](https://synapse.docs.vertex.link/en/latest/synapse/glossary.html#gloss-svc-synapse) published by The Vertex Project.
    - This is the "Synapse appliance".
    - Use this if you want to deploy or test a fully featured open-source Synapse instance instead of just a Cortex. Or if you plan to only integrate with your own list of additional Storm Services.
    - Cortex, JSONStor, Axon
3. `svcs/compose.yaml` - run a currated list of community [Storm Services](https://synapse.docs.vertex.link/en/latest/synapse/glossary.html#service-storm) + installs several community Storm Rapid Power-Ups directly onto your Cortex.
    - Requires some bootstrap scripts to run first to generate Aha registration URLs.
        - Uses the same `.env.aha` naming scheme as the core script, just unique to the services in this script instead.
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

In order to enable clients to talk to containers on the host, a docker network is created using `macvlan`. So the project requires you to pass the network device used for setup. This also means that each container get's it's own IP address. By default, the project uses `10.10.10.64/28` and assigns IPs sequentially in the order services are defined. These can be configured in the project's `.env` file - when starting a 2nd mirror appliance these IPs need to be changed from whatever is used on the primary.

## Filesystem

Synapse/Storm Services require persistant storage. Each service uses a docker volume mapped to `/vertex/storage` on the container. On the host side, each service get's a directory under `/srv/syn`. Core Synapse Services (including Aha) live under `/srv/syn/core` and Storm Services live under `/srv/syn/svcs`.

However, since we're only working on 3 docker compose files, you'll need to manage the Aha service from `/srv/syn/core/${AHA_SERVICE_NAME}/`, all of the other core Synapse Services from `/srv/syn/core`, and all of the Storm Services from `/srv/syn/svcs`. In other words...

To access the Aha container (assuming it has a service name of `00.aha`):
```bash
cd /srv/syn/core/00.aha/
docker compose exec 00.aha /bin/bash
```

To access the Cortex container (assuming it has a service name of `00.cortex`):
```bash
cd /srv/syn/core/
docker compose exec 00.cortex /bin/bash
```

To access the yarastorm container (assuming it has a service name of `00.yarastorm`):
```bash
cd /srv/syn/svcs/
docker compose exec 00.yarastorm /bin/bash
```

### `.env` files

The `.env` file in the root of this project at runtime, is copied to `/srv/syn/.env`. All compose files reference it. See Configuration>Overrides below for more details.

# Starting the appliance

If not already installed, setup [docker](https://docs.docker.com/engine/install/debian/) on the host.

To start everything in one go, do the following:
```bash
git clone https://github.com/gormaniac/rune.git
cd rune
# edit the .env configuration file as needed
# mv .env.example .env && code .env
./rune.sh
```

## Deploying separately/on multiple hosts

If you'd like to start each compose file seperately (separate host deployments, self-managed Aha service, etc.) you can go into their own folder and use their `run.sh` script. However, you'll need to bootstrap the env first (mainly creates the macvlan network). If using a split setup, you'll need to run this on each host.

1. Clone the repo and bootstrap the environment:
    ```bash
    git clone https://github.com/gormaniac/rune.git
    cd rune/
    ```

2. Edit the `.env.example` configuration file as needed - rename it to `.env`.
    ```bash
    mv .env.example .env && code .env
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

5. Ensure the Aha service output an `.env.aha` file - move it to the `core` host if using a separate hosts:
    ```bash
    # Should see Aha registration URLs for the Cortex, Axon, and JSONStor.
    cat ../core/.env.aha
    ```

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

    The above command for step 7 assumes you're running the optional Storm Services on the same host as the Aha server. If you're not, you'll   need to copy the `bootstrap_aha.sh` script to     the host running the Aha container and run it.  Then copy the output `.env.aha` file to the  `svcs/` directory before running `svcs/run.sh`. 

    The same is true with the `./install_storm.sh`  script. If the Cortex is on a separate host, you'll need to copy this to that host and run it    there.

# Configuration

Everything is configured via a `.env` file at the root of the project. A `.env.example` file is included in the project. It's designed to be a completely featured default file that can be copied as is to `.env` and run. The example and the containers have commented out code to support root password generation. More service configuration can be done via adding variables to the `.env` file and call those values in the relevant `compose.yaml` file as environment variables. See each service's documentation for configuration options. 

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

## Overrides

Every compose script opens `/srv/syn/.env` as the master .env file for configuration. This is copied from the `.env` file present at the root of this project when `rune.sh`/`bootstrap.sh` are executed on a host. However, ocassionally, you may wish to override some shared value for a specific service only. In this case, drop a `.env.override` file in the same directory as the docker compose file with the specific values you wish to change. It is read as optional by every compose script.

It is prefered to make an edit to the master `.env` file that is unique to your service, the intention is for it to remain a one stop shop for environment variables.

## The `.env.aha` file

The Core and Services compose files will additionally read a `.env.aha` file from their own directory. It is listed as required since it sets an environment variable within each container that unfortunately needs to be there. However, it only needs to be there at first run. After initial install, you can go edit the compose files and remove this dependency if you wish.

## Secrets

Rune does not support injecting any secrets to containers at any time by default. This is intentional, mostly because Aha supports cert based auth and users should be encouraged to rely on that. But also because it overly complicates the spirit of this project - starting a fully featured open-source Synapse instance with as little user input as possible. Secrets should be managed seperately from env vars, and some users may wish to remove secrets from a host post-install. For more involved deployments that wish to rely on this project and use secrets, manual editing of the `.env` file and the docker compose scripts is needed. I'd recommend starting by using `.env` to define paths on the host where secrets are stored/injected and then relying on Docker's `secrets` feature in the compose script which reference the paths in `.env`.
