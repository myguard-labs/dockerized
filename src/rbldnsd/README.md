# rbldnsd — hardened DNS blacklist (RBL/DNSBL) server, scratch image

`eilandert/rbldnsd` is a minimal, security-hardened Docker image of **rbldnsd**,
the small, fast DNS daemon purpose-built to serve **DNS blacklists** (RBL/DNSBL)
and whitelists. Built `FROM scratch` (just the static binary and its zone data),
it is the local-reputation backend of the **[deb.myguard.nl](https://deb.myguard.nl)**
mail stack, answering the RBL lookups that rspamd and Postfix fire on every
inbound message.

## Why run rbldnsd in Docker

- **Your own RBL zone**, served locally — instant, private IP/domain reputation
  lookups without leaking every sender to a third party.
- **Tiny, fast, `scratch`-based** — essentially just the daemon; nothing else to
  attack or patch.
- **Hardened by default** — no shell, no package manager, dropped capabilities,
  read-only by construction. Context:
  [Docker Hardening for Self-Hosters](https://deb.myguard.nl/2026/05/docker-hardening-rootless-readonly-distroless/).

## Hardened `docker-compose.yml`

```yaml
services:
  rbldnsd:
    image: eilandert/rbldnsd:latest
    restart: unless-stopped
    read_only: true
    cap_drop: [ALL]
    cap_add:
      - NET_BIND_SERVICE
    security_opt:
      - no-new-privileges:true
    volumes:
      - ./zones:/zones:ro              # your ip4set / dnset zone files
    ports:
      - "127.0.0.1:53:53/udp"
      - "127.0.0.1:53:53/tcp"
```

> Keep it internal — point rspamd's RBL/`rbl.example` modules at this resolver on
> the private network.

## Links

- **How RBLs fit into spam filtering:** [Rspamd Explained — Bayes, Neural Nets, RBLs and all the cool tricks](https://deb.myguard.nl/2026/05/rspamd-explained-modern-spam-filtering-bayes-neural-rbl/)
- **All Docker images:** https://deb.myguard.nl/nginx-dockerized/
- **Package repo & articles:** https://deb.myguard.nl
- **Docker hardening guide:** https://deb.myguard.nl/2026/05/docker-hardening-rootless-readonly-distroless/
- **Source:** https://github.com/myguard-labs/dockerized
- **Discord:** https://discord.gg/UQNsFg2y
