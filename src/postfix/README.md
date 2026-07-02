# Postfix — hardened SMTP mail transfer agent Docker image (Debian)

`eilandert/postfix` is a security-hardened Docker image of **Postfix**, the fast,
secure MTA that moves your mail. It is built from the Postfix package on
**[deb.myguard.nl](https://deb.myguard.nl)** and is designed to pair with the
`dovecot`, `rspamd`, `roundcube` and `vimbadmin` images in this stack to form a
complete, modern, self-hosted mail server.

The build targets the **modern MTA feature set**: post-quantum-ready TLS,
TLSRPT/MTA-STS, milter integration (rspamd, OpenDKIM) and SNI.

## Why run Postfix in Docker

- **A reproducible MTA** — the same configuration and binaries on every host,
  versioned alongside the rest of your mail stack.
- **Clean milter wiring** — Postfix, rspamd and Dovecot as separate containers on
  one internal network, each upgradable on its own.
- **Hardened by default** — dropped capabilities, read-only root filesystem,
  no-new-privileges. See
  [Docker Hardening for Self-Hosters](https://deb.myguard.nl/2026/05/docker-hardening-rootless-readonly-distroless/).

## Hardened `docker-compose.yml`

```yaml
services:
  postfix:
    image: eilandert/postfix:latest
    hostname: mail.example.com
    restart: unless-stopped
    read_only: true
    cap_drop: [ALL]
    cap_add:
      - CHOWN
      - SETUID
      - SETGID
      - NET_BIND_SERVICE     # bind 25/587
    security_opt:
      - no-new-privileges:true
    tmpfs:
      - /run
    volumes:
      - postfix-spool:/var/lib/postfix
      - ./postfix/main.cf:/etc/postfix/main.cf:ro
      - ./tls:/etc/ssl/mail:ro
    ports:
      - "25:25"              # inbound SMTP
      - "587:587"            # submission (STARTTLS, authenticated)

volumes:
  postfix-spool:
```

> Pair `587` with SASL auth over TLS only, publish valid SPF/DKIM/DMARC, and route
> mail through the `rspamd` milter for scoring.

## Links

- **The modern MTA stack:** [Postfix 3.11 — Post-Quantum TLS, TLSRPT, Milters and the Modern MTA Stack](https://deb.myguard.nl/2026/05/postfix-3-11-post-quantum-tls-tlsrpt-milters-and-the-modern-mta-stack)
- **All Docker images:** https://deb.myguard.nl/nginx-dockerized/
- **Package repo & articles:** https://deb.myguard.nl
- **Docker hardening guide:** https://deb.myguard.nl/2026/05/docker-hardening-rootless-readonly-distroless/
- **Source:** https://github.com/myguard-labs/dockerized
- **Discord:** https://discord.gg/UQNsFg2y
