# sitemap_warmup — cache + index warmup utility Docker image

`eilandert/sitemap_warmup` is a small utility image that reads a site's XML
sitemap and **warms it** — fetching every URL so the server-side cache (WP Fastest
Cache, nginx/Angie cache, PageSpeed) is primed and pages serve hot. It's a support
tool in the **[deb.myguard.nl](https://deb.myguard.nl)** stack, run on a schedule
after deploys or content updates.

## Why run it in Docker

- **A scheduled, single-purpose crawler** — drop it in a `cron`/timer or CI step;
  no Python/venv to maintain on the host.
- **Cache stays warm** — first-visitor latency disappears because the cache is
  already populated.
- **Pairs with indexing automation** — warm the cache, then ping search engines
  (see the Instant Indexing article below).
- **Hardened, minimal base.** See
  [Docker Hardening for Self-Hosters](https://deb.myguard.nl/2026/05/docker-hardening-rootless-readonly-distroless/).

## Hardened `docker-compose.yml`

```yaml
services:
  sitemap-warmup:
    image: eilandert/sitemap_warmup:latest
    read_only: true
    cap_drop: [ALL]
    security_opt:
      - no-new-privileges:true
    command: ["https://example.com/sitemap_index.xml"]
    restart: "no"        # run on demand / from a scheduler
```

Run it from cron after a deploy:

```bash
docker run --rm eilandert/sitemap_warmup:latest https://example.com/sitemap_index.xml
```

## Links

- **Pair it with search-engine pinging:** [Google Instant Indexing API for WordPress](https://deb.myguard.nl/2026/05/google-instant-indexing-api-wordpress)
- **All Docker images:** https://deb.myguard.nl/nginx-dockerized/
- **Package repo & articles:** https://deb.myguard.nl
- **Docker hardening guide:** https://deb.myguard.nl/2026/05/docker-hardening-rootless-readonly-distroless/
- **Source:** https://github.com/myguard-labs/dockerized
- **Discord:** https://discord.gg/UQNsFg2y
