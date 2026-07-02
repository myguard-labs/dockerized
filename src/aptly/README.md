# aptly — hardened APT repository management Docker image (Debian)

`eilandert/aptly` is a security-hardened Docker image of **aptly**, the tool that
builds, snapshots and publishes Debian/Ubuntu APT repositories. It is the same
tooling that publishes **[deb.myguard.nl](https://deb.myguard.nl)** itself, packaged
so you can host your own signed `.deb` repository — mirror upstreams, stage
snapshots, and publish reproducible package sets over HTTP.

The image bundles an SSH endpoint (for `aptly api` / remote publish workflows)
and an HTTP server to serve the published pool.

## Why run aptly in Docker

- **A self-contained package-publishing pipeline** — repo state in one volume,
  the binary pinned, no host pollution.
- **Reproducible snapshots** — publish an immutable snapshot, roll forward or back
  without rebuilding.
- **Hardened by default** — dropped capabilities, read-only root filesystem. See
  [Docker Hardening for Self-Hosters](https://deb.myguard.nl/2026/05/docker-hardening-rootless-readonly-distroless/).

## Hardened `docker-compose.yml`

```yaml
services:
  aptly:
    image: eilandert/aptly:latest
    restart: unless-stopped
    read_only: true
    cap_drop: [ALL]
    security_opt:
      - no-new-privileges:true
    tmpfs:
      - /run
    volumes:
      - aptly-data:/var/lib/aptly
      - ./ssh:/etc/ssh                 # persist host keys for the publish endpoint
      - ./gpg:/root/.gnupg             # signing key (keep this secret + backed up)
    ports:
      - "127.0.0.1:8080:80"            # serve the published repo (front with a TLS proxy)
      - "127.0.0.1:2222:22"            # publish/admin over SSH

volumes:
  aptly-data:
```

> Protect the GPG signing key and the SSH endpoint — anyone who can publish to the
> repo can ship packages to every machine that trusts it.

## Links

- **How to consume an APT repo like this:** https://deb.myguard.nl/how-to-use/
- **The repository it publishes:** https://deb.myguard.nl
- **All Docker images:** https://deb.myguard.nl/nginx-dockerized/
- **Docker hardening guide:** https://deb.myguard.nl/2026/05/docker-hardening-rootless-readonly-distroless/
- **Source:** https://github.com/myguard-labs/dockerized
- **Discord:** https://discord.gg/UQNsFg2y
