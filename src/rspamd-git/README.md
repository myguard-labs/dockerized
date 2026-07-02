# rspamd — modern spam filter, hardened Docker image (Debian, git/HEAD)

`eilandert/rspamd-git` is a security-hardened Docker image of **rspamd**, the
fast, modern spam-filtering system — Bayesian classifier, neural networks,
greylisting, DNS blacklists (RBL/URIBL), Pyzor, Razor, OLEFY and DCC, all in one
event-driven daemon. It is built from the rspamd package on
**[deb.myguard.nl](https://deb.myguard.nl)** (git/HEAD and stable variants), so
the container matches what `apt install rspamd` gives you from the repo.

rspamd plugs into Postfix/Dovecot over the milter and HTTP protocols and scores
mail far faster than the SpamAssassin generation it replaces.

## Why run rspamd in Docker

- **Clean separation** of the mail-filtering brain from the MTA — restart,
  upgrade or roll back rspamd without touching Postfix.
- **Reproducible rule/model state** via a single mounted volume.
- **Hardened by default** — non-root, capability-dropped, read-only root
  filesystem. Background:
  [Docker Hardening for Self-Hosters](https://deb.myguard.nl/2026/05/docker-hardening-rootless-readonly-distroless/).

## Hardened `docker-compose.yml`

```yaml
services:
  rspamd:
    image: eilandert/rspamd-git:latest
    restart: unless-stopped
    read_only: true
    cap_drop: [ALL]
    security_opt:
      - no-new-privileges:true
    tmpfs:
      - /run
      - /tmp
    volumes:
      - rspamd-data:/var/lib/rspamd          # Bayes DB, neural models, fuzzy
      - ./rspamd/override.d:/etc/rspamd/override.d:ro
    ports:
      - "127.0.0.1:11332:11332"   # milter / proxy (Postfix talks here)
      - "127.0.0.1:11333:11333"   # normal worker
      - "127.0.0.1:11334:11334"   # controller / web UI + API
    healthcheck:
      test: ["CMD", "rspamadm", "control", "stat"]
      interval: 30s
      timeout: 5s
      retries: 3

volumes:
  rspamd-data:
```

> Put a password on the controller (`11334`) and keep it on loopback or behind a
> reverse proxy with auth — it exposes a web UI and a scan API.

## Links

- **How rspamd actually works:** [Rspamd Explained — Bayes, Neural Nets, RBLs and all the cool tricks](https://deb.myguard.nl/2026/05/rspamd-explained-modern-spam-filtering-bayes-neural-rbl/)
- **All Docker images:** https://deb.myguard.nl/nginx-dockerized/
- **Package repo & articles:** https://deb.myguard.nl
- **Docker hardening guide:** https://deb.myguard.nl/2026/05/docker-hardening-rootless-readonly-distroless/
- **Source:** https://github.com/myguard-labs/dockerized
- **Discord:** https://discord.gg/UQNsFg2y
