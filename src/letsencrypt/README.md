# Let's Encrypt — hardened ACME certificate client Docker image (Alpine)

`eilandert/letsencrypt` is a tiny, security-hardened **ACME client** image for
issuing and renewing free TLS certificates from Let's Encrypt (and any ACME CA).
It is the certificate-automation piece of the
**[deb.myguard.nl](https://deb.myguard.nl)** container stack, feeding fresh certs
to the `nginx`, `angie`, `postfix` and `dovecot` images.

## Why run an ACME client in Docker

- **Automated renewals** as a small, single-purpose sidecar — no cron-on-the-host,
  no certbot sprawl across machines.
- **Shared cert volume** — issue once, mount read-only into every service that
  needs TLS.
- **Hardened, minimal Alpine base** — non-root, dropped capabilities, read-only
  root filesystem. See
  [Docker Hardening for Self-Hosters](https://deb.myguard.nl/2026/05/docker-hardening-rootless-readonly-distroless/).

## Hardened `docker-compose.yml`

```yaml
services:
  acme:
    image: eilandert/letsencrypt:latest
    restart: unless-stopped
    read_only: true
    cap_drop: [ALL]
    security_opt:
      - no-new-privileges:true
    volumes:
      - certs:/etc/letsencrypt          # issued certs (shared, read-only elsewhere)
      - ./acme-webroot:/var/www/acme     # HTTP-01 challenge dir
    environment:
      - ACME_EMAIL=admin@example.com
      - ACME_DOMAINS=example.com,www.example.com

  web:
    image: eilandert/angie:latest
    depends_on: [acme]
    volumes:
      - certs:/etc/letsencrypt:ro        # consume certs read-only
    ports: ["443:443", "80:80", "443:443/udp"]

volumes:
  certs:
```

> Once you have certs, serve them with the post-quantum-ready TLS stack — see the
> article below.

## Links

- **What the certs feed (PQ-ready TLS):** [Post-Quantum Cryptography with NGINX and Angie](https://deb.myguard.nl/2026/05/post-quantum-cryptography-with-nginx-and-angie-ml-kem-hybrid-tls-and-how-to-configure-it/)
- **All Docker images:** https://deb.myguard.nl/nginx-dockerized/
- **Package repo & articles:** https://deb.myguard.nl
- **Docker hardening guide:** https://deb.myguard.nl/2026/05/docker-hardening-rootless-readonly-distroless/
- **Source:** https://github.com/myguard-labs/dockerized
- **Discord:** https://discord.gg/UQNsFg2y
