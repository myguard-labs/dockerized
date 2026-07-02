# base — the common Debian/Ubuntu base layer for the deb.myguard.nl stack

`eilandert/debian-base` and `eilandert/ubuntu-base` are the shared foundation
images that every other image in the **[deb.myguard.nl](https://deb.myguard.nl)**
container stack is built `FROM`. They take a slim upstream `debian:trixie-slim` /
Ubuntu rolling image, wire in the **deb.myguard.nl APT repository**, apply the
common hardening and a small `bootstrap.sh` init, and stop there.

You normally don't run this image directly — you build on top of it. It exists so
that nginx, Angie, PHP-FPM, Postfix, Dovecot, rspamd, MariaDB and the rest all
share one patched, repo-pinned base instead of each re-deriving it.

## Why a shared base image

- **One place for the repo wiring + hardening** — fix it once, every downstream
  image inherits it.
- **Smaller, faster builds** — common layers are cached and shared across the
  whole stack.
- **Consistency** — every service container resolves packages from the same
  pinned [deb.myguard.nl](https://deb.myguard.nl) repository.

The hardening posture these images set up is described in
[Docker Hardening for Self-Hosters](https://deb.myguard.nl/2026/05/docker-hardening-rootless-readonly-distroless/).

## Using it as a base

```dockerfile
FROM eilandert/debian-base:stable
# the deb.myguard.nl repo is already configured:
RUN apt-get update && apt-get install -y --no-install-recommends nginx
CMD ["/bootstrap.sh"]
```

## Links

- **Package repo & articles:** https://deb.myguard.nl
- **All Docker images:** https://deb.myguard.nl/nginx-dockerized/
- **How to add the APT repo:** https://deb.myguard.nl/how-to-use/
- **Docker hardening guide:** https://deb.myguard.nl/2026/05/docker-hardening-rootless-readonly-distroless/
- **Source:** https://github.com/myguard-labs/dockerized
- **Discord:** https://discord.gg/UQNsFg2y
