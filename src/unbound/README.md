# Unbound — hardened recursive, validating DNS resolver (Alpine)

`eilandert/unbound` is a tiny, security-hardened Docker image of **Unbound**, the
validating, recursive, caching DNS resolver. It is part of the
**[deb.myguard.nl](https://deb.myguard.nl)** container stack, where it provides
fast local DNS with DNSSEC validation for the mail and web services (and removes
the dependency on — and leakage to — third-party resolvers).

## Why run Unbound in Docker

- **Private, validating resolver** on your own network: DNSSEC checking,
  aggressive caching, no query logging to an upstream provider.
- **A natural fit for mail hosts** — rspamd, Postfix and RBL lookups hammer DNS;
  a local recursive resolver makes them faster and more reliable.
- **Hardened, minimal Alpine base** — non-root, dropped capabilities,
  read-only root filesystem. See
  [Docker Hardening for Self-Hosters](https://deb.myguard.nl/2026/05/docker-hardening-rootless-readonly-distroless/).

## Hardened `docker-compose.yml`

```yaml
services:
  unbound:
    image: eilandert/unbound:latest
    restart: unless-stopped
    read_only: true
    cap_drop: [ALL]
    cap_add:
      - NET_BIND_SERVICE   # bind port 53
    security_opt:
      - no-new-privileges:true
    volumes:
      - ./unbound.conf.d:/etc/unbound/unbound.conf.d:ro
    ports:
      - "127.0.0.1:53:53/udp"
      - "127.0.0.1:53:53/tcp"
```

> Keep it on an internal network or loopback unless you intentionally run an open
> resolver (you almost never should — open resolvers get abused for DNS
> amplification).

## Links

- **Package repo & articles:** https://deb.myguard.nl
- **All Docker images:** https://deb.myguard.nl/nginx-dockerized/
- **Docker hardening guide:** https://deb.myguard.nl/2026/05/docker-hardening-rootless-readonly-distroless/
- **Source:** https://github.com/myguard-labs/dockerized
- **Discord:** https://discord.gg/UQNsFg2y
