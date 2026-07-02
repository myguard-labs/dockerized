# OpenSSH server — hardened SSH daemon Docker image (Debian)

`eilandert/openssh` is a minimal, security-hardened **OpenSSH server** image
built from the openssh package on **[deb.myguard.nl](https://deb.myguard.nl)**.
It gives you a self-contained `sshd` for jump-hosts, SFTP/SCP endpoints, git
transports, rsync targets and CI runners — without dragging a full OS image
along.

## Why run sshd in Docker

- **Single-purpose, smaller attack surface** than installing `openssh-server`
  on a host that also runs everything else.
- **Disposable and reproducible** — keys and home directories live in mounted
  volumes; the container itself is replaceable.
- **Hardened by default** — dropped capabilities, read-only root filesystem,
  no-new-privileges. See
  [Docker Hardening for Self-Hosters](https://deb.myguard.nl/2026/05/docker-hardening-rootless-readonly-distroless/).

## Hardened `docker-compose.yml`

```yaml
services:
  sshd:
    image: eilandert/openssh:latest
    restart: unless-stopped
    read_only: true
    cap_drop: [ALL]
    cap_add:
      - CHOWN            # sshd needs these to drop privs to the session user
      - SETUID
      - SETGID
    security_opt:
      - no-new-privileges:true
    tmpfs:
      - /run
    volumes:
      - ./ssh-host-keys:/etc/ssh        # persist host keys across restarts
      - ./home:/home                    # user home dirs / authorized_keys
    ports:
      - "2222:22"                       # map high to avoid clashing with host sshd
```

> Use key-based auth only (`PasswordAuthentication no`), publish on a non-22
> host port, and put it behind fail2ban / a firewall allowlist.

## Links

- **Hardened package repo & articles:** https://deb.myguard.nl
- **All Docker images:** https://deb.myguard.nl/nginx-dockerized/
- **Docker hardening guide:** https://deb.myguard.nl/2026/05/docker-hardening-rootless-readonly-distroless/
- **Source:** https://github.com/myguard-labs/dockerized
- **Discord:** https://discord.gg/UQNsFg2y
