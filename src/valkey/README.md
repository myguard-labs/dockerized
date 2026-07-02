# Valkey — hardened Redis-compatible in-memory data store (Debian)

`eilandert/valkey` is a small, security-hardened Docker image of **Valkey**, the
BSD-licensed, Linux-Foundation-backed fork of Redis. It is built from the same
Debian package published on **[deb.myguard.nl](https://deb.myguard.nl)**, so the
binary you run in a container is identical to what you'd get from
`apt install valkey` on a box pointed at the repo.

Valkey is a drop-in replacement for Redis 7.2: same `RESP` protocol, same client
libraries, same `redis-cli` muscle memory — used as an object cache, session
store, queue backend or rate-limiter.

## Why run Valkey in Docker

- **Isolation & reproducibility.** One pinned image, identical on every host —
  no "works on my server" drift between dev, staging and production.
- **A smaller, auditable base.** This image ships only what Valkey needs, not a
  full distro of background services.
- **Hardening by default.** Designed to run read-only, non-root,
  capability-dropped. The full reasoning is in
  [Docker Hardening for Self-Hosters](https://deb.myguard.nl/2026/05/docker-hardening-rootless-readonly-distroless/).

## Hardened `docker-compose.yml`

```yaml
services:
  valkey:
    image: eilandert/valkey:latest
    restart: unless-stopped
    command: ["valkey-server", "--save", "60", "1000", "--appendonly", "no"]
    read_only: true
    user: "999:999"                 # non-root valkey user
    cap_drop: [ALL]
    security_opt:
      - no-new-privileges:true
    tmpfs:
      - /run
    volumes:
      - valkey-data:/var/lib/valkey  # persistence (RDB/AOF)
    ports:
      - "127.0.0.1:6379:6379"        # bind to loopback, never 0.0.0.0
    healthcheck:
      test: ["CMD", "valkey-cli", "ping"]
      interval: 10s
      timeout: 3s
      retries: 3

volumes:
  valkey-data:
```

> Production note: keep `6379` on `127.0.0.1` or an internal Docker network and
> set `--requirepass`. Never expose an unauthenticated data store to the internet.

## Tags

`latest` tracks the current Debian stable build. Pull the exact one you tested
and pin it in production.

## Links

- **Why Valkey (and why this package):** [Valkey explained — the Redis fork that actually won](https://deb.myguard.nl/2026/05/valkey-explained-redis-fork-debian-ubuntu-package/)
- **All Docker images:** https://deb.myguard.nl/nginx-dockerized/
- **Package repo & articles:** https://deb.myguard.nl
- **Docker hardening guide:** https://deb.myguard.nl/2026/05/docker-hardening-rootless-readonly-distroless/
- **Source:** https://github.com/myguard-labs/dockerized
- **Discord:** https://discord.gg/UQNsFg2y
