# psol-build — PageSpeed Optimization Library (PSOL) build environment

`eilandert/psol-build` is the compile environment used to build **PSOL**, the
PageSpeed Optimization Library that the nginx/Angie **ngx_pagespeed** module links
against. It is a build-time image in the **[deb.myguard.nl](https://deb.myguard.nl)**
toolchain — not a runtime service. You use it to produce the PSOL artifacts that
go into the hardened `nginx` and `angie` images, reproducibly and in isolation
from your host toolchain.

## Why a dedicated build image

- **Reproducible PSOL builds** — pinned compiler, deps and flags, isolated from
  whatever is on the host.
- **No toolchain pollution** — heavy build dependencies stay in the container.
- **Feeds the web images** — the PSOL output is consumed by `ngx_pagespeed` in the
  nginx/Angie builds.

The hardening posture of the resulting runtime images is described in
[Docker Hardening for Self-Hosters](https://deb.myguard.nl/2026/05/docker-hardening-rootless-readonly-distroless/).

## Usage

```bash
# Build PSOL artifacts into ./out using the pinned build env
docker run --rm -v "$PWD/out:/out" eilandert/psol-build:latest
```

The artifacts are then picked up by the `nginx`/`angie` Dockerfiles in this repo.

## Links

- **The web images it feeds:** https://deb.myguard.nl/nginx-dockerized/
- **Package repo & articles:** https://deb.myguard.nl
- **Docker hardening guide:** https://deb.myguard.nl/2026/05/docker-hardening-rootless-readonly-distroless/
- **Source:** https://github.com/myguard-labs/dockerized
- **Discord:** https://discord.gg/UQNsFg2y
