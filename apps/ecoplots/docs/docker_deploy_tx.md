# Docker Deployment on tx.eco

Target directory:

```sh
/home/bbotson/applications/ecoquant/apps/ecoplots
```

## Build App Data

Build the app-ready RDS files before building or restarting the container:

```sh
cd /home/bbotson/applications/ecoquant/apps/ecoplots
Rscript r/build_ecoplots_rds.R
```

The Shiny app prefers `EcoPlots/*_1y.rds` when present and falls back to the
legacy file names.

The builder now also writes the SAS-derived EQI master database, lifecycle, and
EQMI RDS outputs used by the app's `EQI Master` tab.

## Build the Image

```sh
cd /home/bbotson/applications/ecoquant/apps/ecoplots
docker compose build
```

The image is based on `rocker/shiny` and installs the app's R package
dependencies from CRAN.

If the server has the legacy standalone Compose binary, use
`docker-compose build` instead.

## Run

```sh
docker compose up -d
```

With legacy Compose:

```sh
docker-compose up -d
```

The app is exposed on port `3838`:

```text
https://app.ecoquantinsight.com/
```

The Compose file attaches the app container to the existing external
`traefik-net` network and lets the already-running Traefik container route
`app.ecoquantinsight.com` to container port `3838`. Do not run a second Traefik
container for this app because the current proxy already owns host ports `80`
and `443`.

The included `deploy/shiny-server.conf` keeps Shiny sessions eligible for
reconnect and disables older fallback transports so WebSocket behavior is
clearer behind a proxy.

For Traefik, use a long-lived response timeout on the entrypoint or Servers
Transport that fronts this container. A dynamic config example:

```yaml
http:
  serversTransports:
    shiny-long-lived:
      forwardingTimeouts:
        dialTimeout: 30s
        responseHeaderTimeout: 0s
        idleConnTimeout: 1800s
```

The app uses Docker labels like these:

```yaml
labels:
  - traefik.enable=true
  - traefik.docker.network=traefik-net
  - traefik.http.routers.ecoplots.rule=Host(`app.ecoquantinsight.com`)
  - traefik.http.routers.ecoplots.entrypoints=websecure
  - traefik.http.routers.ecoplots.tls.certresolver=myresolver
  - traefik.http.services.ecoplots.loadbalancer.server.port=3838
```

Shiny can reconnect after ordinary idle WebSocket drops, but browser tab
suspension and laptop sleep can still terminate the browser-side session. The
app now shows a reload prompt on disconnect and sends a lightweight heartbeat
when focused or visible.

## Logs

```sh
docker compose logs -f ecoplots
```

With legacy Compose:

```sh
docker-compose logs -f ecoplots
```

Inside the container, Shiny Server logs are under:

```sh
/var/log/shiny-server
```

`compose.yaml` maps that directory to the host:

```sh
/home/bbotson/applications/ecoquant/apps/ecoplots/logs/shiny-server
```

Create the host log directories before starting the container:

```sh
cd /home/bbotson/applications/ecoquant/apps/ecoplots
mkdir -p logs/shiny-server
chmod 777 logs/shiny-server
```

Then view app logs directly on the host:

```sh
tail -f logs/shiny-server/*.log
```

## Updating Data Only

Because `compose.yaml` mounts `./EcoPlots` into the container read-only, data
updates do not require rebuilding the image:

```sh
cd /home/bbotson/applications/ecoquant/apps/ecoplots
scripts/update_ecoplots_data.sh
```

With legacy Compose:

```sh
COMPOSE_CMD=docker-compose scripts/update_ecoplots_data.sh
```

The update script runs incremental ingestion and restarts the container when it
is already running, which reloads the RDS files in a fresh R process.

For a scheduled weekday update:

```cron
15 19 * * 1-5 cd /home/bbotson/applications/ecoquant/apps/ecoplots && scripts/update_ecoplots_data.sh >> logs/ecoplots_update.log 2>&1
```

Create the log directory once:

```sh
mkdir -p /home/bbotson/applications/ecoquant/apps/ecoplots/logs /home/bbotson/applications/ecoquant/apps/ecoplots/logs/shiny-server
chmod 777 /home/bbotson/applications/ecoquant/apps/ecoplots/logs/shiny-server
```

## Updating Code or Packages

If `EcoPlots/app.R` changes only:

```sh
docker compose restart ecoplots
```

With legacy Compose:

```sh
docker-compose restart ecoplots
```

If the `Dockerfile`, Shiny Server config, or R package dependencies change:

```sh
docker compose build
docker compose up -d
```

With legacy Compose:

```sh
docker-compose build
docker-compose up -d
```

## Files Used by the Container

The runtime container needs:

- `Dockerfile`
- `compose.yaml`
- `deploy/shiny-server.conf`
- `EcoPlots/app.R`
- `EcoPlots/*_1y.rds`

The builder also needs:

- `r/build_ecoplots_rds.R`
- `../../results/results_stock_xtest_*.csv`
- `../../results/results_etf_xtest_*.csv`
