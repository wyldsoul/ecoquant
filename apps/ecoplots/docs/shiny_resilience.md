# Shiny Resilience Notes

This app is more sensitive to inactive browser tabs than a static React or
request/response Flask app because the active Shiny session is tied to a
long-lived WebSocket. If a browser suspends the tab, a laptop sleeps, or a proxy
closes the idle socket, the R session can be lost.

Implemented repo changes:

- `deploy/shiny-server.conf` enables Shiny reconnects and removes old fallback
  transports.
- `EcoPlots/app.R` calls `session$allowReconnect(TRUE)` when supported.
- `EcoPlots/app.R` sends a small browser heartbeat every 25 seconds while the
  tab is running and whenever the tab becomes visible or focused.
- `EcoPlots/app.R` shows a fixed disconnect banner with a reload button.
- `compose.yaml` restarts the container automatically and exposes a healthcheck.

Remaining production limits:

- Browser sleep and aggressive background tab suspension can prevent any
  JavaScript heartbeat from running.
- Open-source Shiny Server cannot fully preserve every in-memory session after
  the R process exits.
- The app should continue moving toward stateless UI paths where all expensive
  calculations are prebuilt in RDS files and user selections can be recreated
  after reload.

Recommended proxy behavior:

- Keep WebSocket upgrade headers untouched.
- Avoid short idle timeouts for the Shiny route.
- Use a long-lived Traefik `serversTransport` for this service when it is placed
  behind HTTPS/WSS.
