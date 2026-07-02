# docker-cms — hardened all-in-one CMS image (Angie + PHP 8.5, Debian)

`eilandert/docker-cms` is a hardened, batteries-included **CMS bundle**: the
deb.myguard.nl **Angie** web server and **PHP 8.5** in a single image, ready to run
WordPress and other PHP CMSes. Built on top of the `angie` image from this stack,
it inherits HTTP/3 + QUIC, ModSecurity3 + OWASP CRS, the dedicated `openssl-nginx`
build and the audited dynamic-module set — so a CMS comes up production-hardened
out of the box rather than as bare upstream defaults.

## Why run your CMS in this image

- **One hardened image** instead of hand-assembling web server + PHP + WAF + TLS.
- **WAF included** — ModSecurity3 with the same OWASP CRS exclusions used on
  [deb.myguard.nl](https://deb.myguard.nl).
- **Modern transport** — HTTP/3, QUIC and post-quantum-ready TLS from the
  underlying Angie build.
- **Hardened by default** — read-only root, dropped capabilities, non-root PHP.
  See [Docker Hardening for Self-Hosters](https://deb.myguard.nl/2026/05/docker-hardening-rootless-readonly-distroless/).

## Hardened `docker-compose.yml`

```yaml
services:
  cms:
    image: eilandert/docker-cms:latest
    restart: unless-stopped
    read_only: true
    cap_drop: [ALL]
    cap_add:
      - NET_BIND_SERVICE
    security_opt:
      - no-new-privileges:true
    tmpfs:
      - /run
    volumes:
      - ./site:/var/www/html            # your CMS code + uploads
      - certs:/etc/letsencrypt:ro
    ports:
      - "443:443"
      - "80:80"
      - "443:443/udp"                   # HTTP/3
    depends_on: [db]

  db:
    image: eilandert/mariadb:latest
    read_only: true
    cap_drop: [ALL]
    security_opt: [no-new-privileges:true]
    volumes:
      - db:/var/lib/mysql
    environment:
      - MARIADB_RANDOM_ROOT_PASSWORD=1

volumes:
  certs:
  db:
```

## Links

- **All Docker images:** https://deb.myguard.nl/nginx-dockerized/
- **The Angie build underneath:** [Post-Quantum Cryptography with NGINX and Angie](https://deb.myguard.nl/2026/05/post-quantum-cryptography-with-nginx-and-angie-ml-kem-hybrid-tls-and-how-to-configure-it/)
- **Package repo & articles:** https://deb.myguard.nl
- **Docker hardening guide:** https://deb.myguard.nl/2026/05/docker-hardening-rootless-readonly-distroless/
- **Source:** https://github.com/myguard-labs/dockerized
- **Discord:** https://discord.gg/UQNsFg2y
