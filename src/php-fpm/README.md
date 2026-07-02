# PHP-FPM — hardened FastCGI Process Manager images (Debian, PHP 5.6 → 8.5)

`eilandert/php-fpm` is a family of security-hardened **PHP-FPM** Docker images
spanning six PHP branches — `5.6`, `7.4`, `8.0`, `8.2`, `8.4`, `8.5` — on Debian
and Ubuntu bases. They are built from the PHP packages on
**[deb.myguard.nl](https://deb.myguard.nl)** and pair with the `nginx`, `angie`
and `apache-phpfpm` images in this project to serve any PHP application.

Where it matters, builds include **Snuffleupagus**, the runtime PHP security
module that virtually-patches whole vulnerability classes (RCE via
`unserialize`, dangerous `system()` calls, cookie/session hardening) without
touching application code.

## Why run PHP-FPM in Docker

- **Pin the exact PHP version** an app needs (a legacy `5.6` app and a modern
  `8.5` one can run side-by-side on the same host).
- **Decouple the runtime from the web server** — scale or restart FPM
  independently of nginx/Angie over the FastCGI socket.
- **Hardened by default** — non-root worker, dropped capabilities, read-only
  root filesystem. See
  [Docker Hardening for Self-Hosters](https://deb.myguard.nl/2026/05/docker-hardening-rootless-readonly-distroless/).

## Hardened `docker-compose.yml`

```yaml
services:
  php-fpm:
    image: eilandert/php-fpm:deb-8.4
    restart: unless-stopped
    read_only: true
    cap_drop: [ALL]
    security_opt:
      - no-new-privileges:true
    tmpfs:
      - /run
    volumes:
      - ./app:/var/www/html:ro          # your code, read-only into FPM
      - php-sessions:/var/lib/php/sessions
    expose:
      - "9000"                          # FastCGI — internal network only
    # no `ports:` — only nginx/angie should reach FPM

  web:
    image: eilandert/nginx:latest
    depends_on: [php-fpm]
    ports: ["443:443", "80:80", "443:443/udp"]
    volumes:
      - ./app:/var/www/html:ro

volumes:
  php-sessions:
```

> Never publish `9000` to the host. FastCGI has no auth — only the web container
> on the internal network should talk to it.

## Tags

Tags encode distro + version, e.g. `deb-8.4`, `deb-8.5`, `ubu-8.4`. Pin one.

## Links

- **PHP-FPM hardening with Snuffleupagus:** [Enhancing Web Security with PHP Snuffleupagus for PHP-FPM](https://deb.myguard.nl/2024/01/enhancing-web-security-with-php-snuffleupagus-for-php-fpm/)
- **All Docker images:** https://deb.myguard.nl/nginx-dockerized/
- **Package repo & articles:** https://deb.myguard.nl
- **Docker hardening guide:** https://deb.myguard.nl/2026/05/docker-hardening-rootless-readonly-distroless/
- **Source:** https://github.com/myguard-labs/dockerized
- **Discord:** https://discord.gg/UQNsFg2y
