# Dovecot — hardened IMAP/POP3/LMTP/ManageSieve (Docker)

A dockerized [Dovecot](https://www.dovecot.org/) mail-access server with
Sieve, built on Debian and the [deb.myguard.nl](https://deb.myguard.nl)
package repo. Dovecot is the daemon your mail client (Thunderbird, Outlook,
the Roundcube webmail, a phone) actually talks to when it **reads** mail —
IMAP and POP3 — plus LMTP (local delivery from your MTA), ManageSieve
(server-side filtering rules), and a submission proxy.

## See also

- **Image source / this repo:** <https://github.com/myguard-labs/dockerized/tree/master/src/dovecot-ubuntu>
- **Docker Hub:** <https://hub.docker.com/r/eilandert/dovecot>
- **Packages:** <https://deb.myguard.nl>
- **Write-up / guided tour:** _TODO — link the deb.myguard.nl article once published._

Companion images in the same fleet: **[Roundcube](../roundcube/)** (webmail
front-end), **[Postfix](../postfix/)** (the MTA that hands mail to Dovecot
over LMTP), **[rspamd](../rspamd-git/)** (spam filtering — see the
[rspamd write-up](https://deb.myguard.nl/2026/05/rspamd-explained-modern-spam-filtering-bayes-neural-rbl/)), and
**[ViMbAdmin](../vimbadmin/)** (the web UI that manages the mailbox database
these scripts read — see the
[ViMbAdmin write-up](https://deb.myguard.nl/2026/06/vimbadmin-postfix-dovecot-mailbox-admin-panel/)).

## Quick start

Save the [compose file](#docker-composeyml) below as `docker-compose.yml`,
**change every password in it**, then:

```bash
docker compose up -d
```

First boot with an empty `./config/dovecot` seeds the packaged defaults **plus
a high-port listener override and a TLS-hardening drop-in** (and a self-signed
bootstrap cert so it comes up TLS-ready); edit `./config/dovecot/*.conf` and
`docker compose restart dovecot`.

Mount `/etc/dovecot` with your own config to override. **If `dovecot.conf`
does not exist, the packaged default configs are copied in on startup** — so
you can start empty, let it seed, then customise. Existing configs are never
clobbered.

The container's root master process handles its own ownership of the config
mount and runtime dirs, so there is **no host pre-chown step**. Persist mail
on the `vmail` named volume; point the TLS config at your real certificate
(see [TLS](#tls)).

### docker-compose.yml

```yaml
# =============================================================================
#  Dovecot — hardened IMAP/POP3/LMTP/ManageSieve server
# =============================================================================
#  Packages built on https://deb.myguard.nl
#  Image src     : https://github.com/myguard-labs/dockerized/tree/master/src/dovecot-ubuntu
#  Docker Hub    : https://hub.docker.com/r/eilandert/dovecot
#
#  Security model — Dovecot's NATIVE privilege separation, caged:
#    * The root master starts, loads the TLS key, then drops the internet-facing
#      pre-auth login processes to the unprivileged `dovenull` and the mail
#      processes to `vmail` (uid 5000). Root never parses hostile input. This is
#      Dovecot's strongest mitigation — keep it; do NOT collapse to one uid.
#    * Around that root the container is locked down: cap_drop ALL + only the
#      handful of caps the master needs to bind/drop/own its runtime sockets,
#      no-new-privileges, every setuid bit stripped in the image, AppArmor.
#    * read_only rootfs: the only writable paths are the /run + /tmp tmpfs and
#      the /etc/dovecot + /var/vmail mounts. A compromise cannot persist on disk.
#    * Listeners are on >1024 ports (mapped down host-side), so NET_BIND_SERVICE
#      is not even needed.
#
#  Change EVERY password before deploying. Persist /var/vmail (mail + indexes).
# =============================================================================

services:
  dovecot:
    container_name: dovecot
    image: docker.io/eilandert/dovecot:latest
    restart: unless-stopped
    hostname: mail

    ports:
      #  host : container       service
      - "24:10024/tcp"     #    LMTP
      - "110:10110/tcp"    #    POP3 (STARTTLS)
      - "143:10143/tcp"    #    IMAP (STARTTLS)
      - "993:10993/tcp"    #    IMAPS
      - "995:10995/tcp"    #    POP3S
      - "4190:14190/tcp"   #    ManageSieve

    volumes:
      - ./config/dovecot:/etc/dovecot          # your config (seeded on first run if empty)
      - vmail:/var/vmail                        # maildir + index storage (persist!)
      - /etc/letsencrypt:/etc/letsencrypt:ro    # TLS certs (read-only)
      # Timezone for wall-clock log timestamps (TZ env sets the zone; this gives
      # the matching zoneinfo file on the read-only rootfs). Optional.
      - /etc/localtime:/etc/localtime:ro

    environment:
      TZ: Europe/Amsterdam      # also bind-mount /etc/localtime (see volumes)
      MALLOC: mimalloc          # mimalloc | jemalloc | none
      # ---- optional ----
      # SYSLOG_HOST: 10.0.0.118 # forward logs to a remote syslog over UDP
      # SLEEP: "10"             # startup grace (seconds) to dodge race conditions
      # WAIT_FOR_1: db:3306     # block boot until deps are up (bounded, 25 tries)
      # WAIT_FOR_2: redis:6379

    # ---- hardening ----------------------------------------------------------
    security_opt:
      - no-new-privileges:true
      - apparmor=docker-default
    # The root master needs exactly these to bind (high ports, so no
    # NET_BIND_SERVICE), drop privilege to dovenull/vmail, and own its runtime
    # sockets. Everything else is dropped.
    cap_drop: [ALL]
    cap_add:
      - SETUID         # master -> dovenull (login) / vmail (mail)
      - SETGID
      - SYS_CHROOT     # login processes chroot into /run/dovecot/login (priv-sep)
      - CHOWN          # own per-service sockets under /run/dovecot
      - DAC_OVERRIDE
      - FOWNER
      - KILL           # master signals its worker children

    # Immutable rootfs. The only writable paths are the two tmpfs and the
    # /etc/dovecot + /var/vmail mounts below; nothing else on the rootfs.
    read_only: true
    tmpfs:
      # Runtime sockets + pid (base_dir = /run/dovecot): root-owned, the master
      # chowns the per-service sockets to dovenull/vmail itself. nosuid/nodev
      # (NOT noexec — leave the master free to map executable pages here).
      - /run:mode=0755,nosuid,nodev
      # Scratch / sieve temp / patched vimbadmin scripts. noexec,nosuid,nodev.
      - /tmp:mode=1777,noexec,nosuid,nodev
      # Dovecot runtime state (instance registry, generated ssl params). Small,
      # non-persistent — a tmpfs is fine; mail + indexes live on /var/vmail.
      - /var/lib/dovecot:mode=0755,nosuid,nodev

    ulimits:
      nofile:
        soft: 16384
        hard: 16384
    deploy:
      resources:
        limits:
          memory: 512M
          pids: 512
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "3"

volumes:
  vmail:
```

## Ports

Clients connect to the standard **public** ports. Internally Dovecot binds a
high (>1024) port so the container needs no `CAP_NET_BIND_SERVICE`; the
compose `ports:` mapping forwards the public port down to it.

| Public (host) | Container | Service |
|------|------|---------|
| 24   | 10024 | LMTP (delivery from your MTA) |
| 110  | 10110 | POP3 (STARTTLS) |
| 143  | 10143 | IMAP (STARTTLS) |
| 993  | 10993 | IMAPS |
| 995  | 10995 | POP3S |
| 4190 | 14190 | ManageSieve |

The container ports are set by `conf.d/99-unprivileged-ports.conf` (seeded on
first run). Mount your own `/etc/dovecot` to change them — just keep the
compose `host:container` mapping in sync.

## TLS

The same seeded `conf.d/99-unprivileged-ports.conf` also pins the TLS policy
(dovecot 2.4 directive names):

- **No cleartext credentials.** `auth_allow_cleartext = no` — the 143/110
  listeners stay, but Dovecot refuses AUTH until the client upgrades with
  **STARTTLS**, so passwords never cross the wire in the clear. 993/995 are
  implicit TLS.
- **TLS 1.2 floor** (`ssl_min_protocol = TLSv1.2`; 1.0/1.1 disabled — verified
  rejected).
- **Forward-secret AEAD ciphers only**, server picks the order
  (`ssl_server_prefer_ciphers = server`), plus an explicit TLS 1.3 suite list.
  (The override also fixes an invalid `= yes` the packaged config shipped on
  that key.)

The image ships a **self-signed bootstrap cert** (`/etc/dovecot/private/
dovecot.{pem,key}`, owned `root:root` and loaded by the root master before it
drops privilege), so it comes up TLS-ready out of the box. **Replace it with
your real certificate** for production — set the 2.4 paths in your
`./config/dovecot/conf.d/99-unprivileged-ports.conf` (note: plain paths, no
`<` prefix):

```
ssl_server_cert_file = /etc/letsencrypt/live/mail.example.org/fullchain.pem
ssl_server_key_file  = /etc/letsencrypt/live/mail.example.org/privkey.pem
```

## Environment variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `TZ` | _unset_ | Container timezone, e.g. `Europe/Amsterdam`. For wall-clock log timestamps also bind-mount `/etc/localtime:/etc/localtime:ro` (the read-only rootfs is not rewritten). |
| `MALLOC` | `mimalloc` | Allocator preload: `mimalloc`, `jemalloc`, or `none`. Resolved per-architecture (amd64/arm64). |
| `SYSLOG_HOST` | _unset_ | Forward logs to a remote syslog over UDP. Works under the read-only rootfs: `/etc/syslog-ng` is a symlink into the `/tmp` tmpfs (seeded on first run) and the daemon's persist/control/pid are redirected there too. |
| `SLEEP` | _unset_ | Seconds to sleep at startup to dodge race conditions. |
| `WAIT_FOR_N` | _unset_ | `host:port` to block boot on until reachable (`WAIT_FOR_1`, `WAIT_FOR_2`, …). Bounded — gives up after 25 retries instead of hanging forever. |

## What's in the image

- **Dovecot** + all modules: imapd, pop3d, lmtpd, managesieved, submissiond,
  sieve, and the MySQL/MariaDB + PostgreSQL auth/userdb drivers.
- **Spam-reporting clients** so Sieve learn/report pipelines work:
  `rspamc` (rspamd), `spamc` (SpamAssassin), `pyzor`, `razor`.

There is **no local MTA**. Dovecot is mail *access*, not transport — Sieve
outbound (redirect/vacation/notify) is sent by SMTP to the
**[Postfix](../postfix/)** container via `submission_host` (see
[Sieve forwarding](#sieve-forwarding--outbound-mail)).

## Security model

The image keeps **Dovecot's native privilege separation** and cages the root
master that makes it possible:

- **Privilege separation (the key mitigation).** The master starts as root,
  loads the TLS key, then drops the *internet-facing* pre-auth login processes
  to the unprivileged **`dovenull`** user and the mail processes to **`vmail`**
  (uid 5000). The code that parses hostile network input never runs as root or
  as the mailbox owner. (Verified live: `default_login_user = dovenull`,
  `default_internal_user = dovecot`.) This is Dovecot's strongest defence —
  the image deliberately does **not** collapse everything to one uid.
- **No privileged ports.** Every listener is on a >1024 port
  (`conf.d/99-unprivileged-ports.conf`), mapped to the standard public ports
  host-side, so **`CAP_NET_BIND_SERVICE` is not needed**.
- **Minimal capabilities.** `cap_drop: [ALL]`, then only the handful the master
  genuinely needs: `SETUID`/`SETGID` (drop to dovenull/vmail), `SYS_CHROOT`
  (login processes chroot into `/run/dovecot/login`), `CHOWN`/`DAC_OVERRIDE`/
  `FOWNER` (own the per-service runtime sockets), `KILL` (signal children).
  No general-purpose root.
- `no-new-privileges:true` + `apparmor=docker-default` block escalation.
- **`read_only: true`** — the entire root filesystem is immutable. The only
  writable paths are three tmpfs (`/run` for sockets/pid, `/tmp` for
  sieve/scratch + the patched vimbadmin scripts, `/var/lib/dovecot` for the
  instance registry) and your two mounts (`/etc/dovecot`, `/var/vmail`).
  `/tmp` is **`noexec,nosuid,nodev`**; a compromise cannot drop and execute a
  binary or persist on disk.
- **No setuid/setgid binaries.** The build strips every setuid/setgid bit
  (`chmod -s`) — `su`, `mount`, `passwd`, … Dovecot drops privilege from the
  root master directly, not via setuid helpers, so nothing here needs them;
  with `no-new-privileges` there is no setuid path left to escalate through.
- **TLS-only auth** — cleartext credentials refused until STARTTLS, TLS 1.2+
  with forward-secret ciphers, TLS 1.0/1.1 rejected (see [TLS](#tls)).
- Memory / PID limits and a bounded file-descriptor `ulimit`.
- JSON log rotation.

## Sieve forwarding / outbound mail

This image ships **no local MTA**. Dovecot's job is mail *access*; mail
*transport* belongs to the **[Postfix](../postfix/)** container. Sieve rules
that send mail — `redirect` (forward), `vacation` (auto-reply), `notify` —
hand the message to an MTA over SMTP via Dovecot's `submission_host`, **not** a
local `sendmail`.

Point it at your Postfix submission service in
`./config/dovecot/conf.d/99-unprivileged-ports.conf` (shipped commented):

```
submission_host = postfix:587
```

Without this set, Sieve `redirect`/`vacation`/`notify` have nowhere to send.
Plain mailbox delivery (LMTP in, IMAP/POP3 read) needs nothing here.

## Tags

- `eilandert/dovecot:debian` / `eilandert/dovecot:latest` — Debian (this build)
