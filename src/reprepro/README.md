# reprepro — hardened APT repository builder Docker image (Ubuntu)

`eilandert/reprepro` is a security-hardened Docker image of **reprepro**, the
lightweight tool for producing and maintaining a signed Debian/Ubuntu APT
repository from a local pool of `.deb` files. It complements the `aptly` image in
this stack: where aptly excels at snapshots and mirroring, reprepro is the simple,
deterministic choice for a single signed repository you feed by hand or from CI.

It powers part of the **[deb.myguard.nl](https://deb.myguard.nl)** publishing
workflow and ships with an SSH ingest endpoint and an HTTP server.

## Why run reprepro in Docker

- **Dead-simple signed repo** — drop `.deb`s in, get a `Packages`/`Release` tree
  with a detached signature out.
- **Reproducible + portable** — the whole repo lives in one `/repo` volume.
- **Hardened by default** — dropped capabilities, read-only root filesystem. See
  [Docker Hardening for Self-Hosters](https://deb.myguard.nl/2026/05/docker-hardening-rootless-readonly-distroless/).

## Hardened `docker-compose.yml`

```yaml
services:
  reprepro:
    image: eilandert/reprepro:latest
    restart: unless-stopped
    read_only: true
    cap_drop: [ALL]
    security_opt:
      - no-new-privileges:true
    tmpfs:
      - /run
    volumes:
      - ./repo:/repo                   # conf/, db/, pool/, dists/
      - ./gpg:/root/.gnupg             # signing key — keep secret + backed up
    ports:
      - "127.0.0.1:8080:80"            # serve dists/ + pool/ (front with TLS)
      - "127.0.0.1:2222:22"            # ingest over SSH
```

> Guard the signing key and ingest path exactly as you would with aptly — repo
> trust is package-supply-chain trust.

## Links

- **How to consume an APT repo like this:** https://deb.myguard.nl/how-to-use/
- **The repository it helps publish:** https://deb.myguard.nl
- **All Docker images:** https://deb.myguard.nl/nginx-dockerized/
- **Docker hardening guide:** https://deb.myguard.nl/2026/05/docker-hardening-rootless-readonly-distroless/
- **Source:** https://github.com/myguard-labs/dockerized
- **Discord:** https://discord.gg/UQNsFg2y
