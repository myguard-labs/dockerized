# Apache + PHP-FPM — hardened web + PHP image (Debian, PHP 5.6 → 8.5)

`eilandert/apache-phpfpm` bundles the **Apache HTTP Server** with **PHP-FPM** over
`mod_proxy_fcgi`, built from the packages on
**[deb.myguard.nl](https://deb.myguard.nl)**. It's the drop-in choice for PHP
applications that expect Apache semantics — `.htaccess`, `mod_rewrite`,
per-directory overrides — across six PHP branches (`5.6`, `7.4`, `8.0`, `8.2`,
`8.4`, `8.5`).

Where available, PHP is hardened at runtime with **Snuffleupagus**.

## Why run Apache + PHP-FPM in Docker

- **Legacy-friendly** — many off-the-shelf PHP apps assume Apache + `.htaccess`;
  this image serves them without rewriting config for nginx.
- **FPM process isolation** — PHP runs in its own pool, not in the web-server
  process, so a crash or leak is contained.
- **Pin the PHP version** per app and run several side-by-side.
- **Hardened by default.** See
  [Docker Hardening for Self-Hosters](https://deb.myguard.nl/2026/05/docker-hardening-rootless-readonly-distroless/).

## Hardened `docker-compose.yml`

```yaml
services:
  web:
    image: eilandert/apache-phpfpm:deb-8.4
    restart: unless-stopped
    read_only: true
    cap_drop: [ALL]
    cap_add:
      - NET_BIND_SERVICE
    security_opt:
      - no-new-privileges:true
    tmpfs:
      - /run
      - /tmp
    volumes:
      - ./app:/var/www/html:ro
      - apache-logs:/var/log/apache2
    ports:
      - "443:443"
      - "80:80"

volumes:
  apache-logs:
```

## Tags

Distro + PHP version, e.g. `deb-8.4`, `deb-5.6`, `ubu-8.5`. Pin one in production.

## Links

- **PHP hardening with Snuffleupagus:** [Enhancing Web Security with PHP Snuffleupagus for PHP-FPM](https://deb.myguard.nl/2024/01/enhancing-web-security-with-php-snuffleupagus-for-php-fpm/)
- **All Docker images:** https://deb.myguard.nl/nginx-dockerized/
- **Package repo & articles:** https://deb.myguard.nl
- **Docker hardening guide:** https://deb.myguard.nl/2026/05/docker-hardening-rootless-readonly-distroless/
- **Source:** https://github.com/myguard-labs/dockerized
- **Discord:** https://discord.gg/UQNsFg2y
