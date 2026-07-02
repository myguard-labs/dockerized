#!/bin/bash
# =============================================================================
# Roundcube — s6 init-bootstrap oneshot.
#
# s6-overlay is PID1 (process supervisor); this oneshot runs FIRST and does all
# one-time setup, then the php-fpm and angie longruns start (and are supervised
# + restarted by s6). Everything here is CLI-only — it does NOT need php-fpm
# running (schema work uses the `php` CLI directly), so it completes before the
# pool comes up.
#
# Runs UNPRIVILEGED as the roundcube uid (10001): s6-overlay itself runs rootless
# (S6_READ_ONLY_ROOT=1), cap_drop ALL + no-new-privileges + AppArmor, read-only
# rootfs, angie on :8080. No runtime setuid/chown -> ZERO capabilities required.
#
# Because the container has NO root and CANNOT chown, every writable mount must
# already be owned by uid 10001. Named volumes inherit the image dir's owner; for
# host bind mounts / tmpfs set the owner yourself (host: chown -R 10001:10001;
# tmpfs: uid=10001,gid=10001).
#
# Writable locations: /run (s6 scratch, tmpfs), /tmp (sockets, RC temp, tmpfs),
# /var/roundcube/config (generated config + override). External DB mandatory.
# =============================================================================
set -euo pipefail

PHPVERSION="${PHPVERSION:-8.5}"
INSTALLDIR="${INSTALLDIR:-/var/www/html}"

# Roundcube config search path — exported so the CLI bin/*.sh scripts run below
# find the generated config (not just the empty install config/ dir).
export RCUBE_CONFIG_PATH="/var/roundcube/config/:config/"

log() { echo "[ROUNDCUBE] $*"; }
log "Image src: https://github.com/myguard-labs/dockerized/tree/master/src/roundcube"
log "Docker Hub: https://hub.docker.com/r/eilandert/roundcube"
log "Write-up  : https://deb.myguard.nl/2026/06/hardened-roundcube-docker-image/"
log "---------------------------------------------------------------------------"
log "Security profile: s6-overlay PID1, runs UNPRIVILEGED (no root), cap_drop ALL"
log "  + no-new-privileges + AppArmor, read-only rootfs, Angie on :8080."
log "Because the container has NO root and CANNOT chown, every WRITABLE mount"
log "  must already be owned by uid 10001 (roundcube) on the host:"
log "    named volume : nothing to do (inherits the image dir owner)"
log "    host bind dir : sudo chown -R 10001:10001 <your bind dir>"
log "    tmpfs        : --tmpfs <path>:uid=10001,gid=10001"
log "  A 'Permission denied' on boot = a writable mount not owned 10001:10001."
log "---------------------------------------------------------------------------"

# --- escaping helpers -------------------------------------------------------
# php_sq: make an arbitrary string safe inside a '...' single-quoted PHP literal
# in the generated config.inc.php — escape backslash first, then the quote. A DB
# password containing ' or \ would otherwise break the config (or inject into it).
php_sq() { local s=$1; s=${s//\\/\\\\}; s=${s//\'/\\\'}; printf '%s' "$s"; }
# urlenc: percent-encode a DSN credential (user/password) so reserved chars
# (@ : / ? # …) in a password don't corrupt the type://user:pass@host/db DSN.
urlenc() { php -d error_reporting=0 -r 'echo rawurlencode($argv[1]);' "$1"; }

# ---------------------------------------------------------------------------
# Writable runtime dirs (all under the /tmp tmpfs or the config/db volumes)
# ---------------------------------------------------------------------------
: "${ROUNDCUBEMAIL_TEMP_DIR:=/tmp/roundcube-temp}"

# We run UNPRIVILEGED and CANNOT chown. We only create subdirs here -- as their
# owner. The writable mounts (/var/roundcube/config, /tmp) MUST already be owned
# by the roundcube uid. Probe the writable ROOTS and emit a clear, actionable
# warning naming the path + the chown fix.
RC_UID="$(id -u)"
for _w in /var/roundcube/config /tmp "${ROUNDCUBEMAIL_TEMP_DIR}"; do
    [ -d "$_w" ] || continue
    _probe="${_w}/.rc-write-test.$$"
    if touch "$_probe" 2>/dev/null; then
        rm -f "$_probe"
    else
        log "WARNING: '${_w}' is NOT writable by uid ${RC_UID} (roundcube)."
        log "  Host bind dir : sudo chown -R 10001:10001 <that dir>"
        log "  tmpfs mount   : --tmpfs ${_w}:uid=10001,gid=10001,mode=1770"
        log "  Roundcube will fail to start until this mount is writable."
    fi
done

mkdir -p /tmp/run \
         /tmp/angie/client-body /tmp/angie/proxy /tmp/angie/fastcgi \
         "${ROUNDCUBEMAIL_TEMP_DIR}" /var/roundcube/config

# ---------------------------------------------------------------------------
# Database wiring (secrets > env). An external DB (mysql/mariadb or pgsql) is
# mandatory — there is no sqlite fallback. Fail fast if nothing is configured.
# ---------------------------------------------------------------------------
[ -f /run/secrets/roundcube_db_user ]     && ROUNDCUBEMAIL_DB_USER="$(cat /run/secrets/roundcube_db_user)"
[ -f /run/secrets/roundcube_db_password ] && ROUNDCUBEMAIL_DB_PASSWORD="$(cat /run/secrets/roundcube_db_password)"

: "${ROUNDCUBEMAIL_DB_TYPE:=mysql}"
case "${ROUNDCUBEMAIL_DB_TYPE}" in
    pgsql)
        : "${ROUNDCUBEMAIL_DB_HOST:=postgres}"
        : "${ROUNDCUBEMAIL_DB_PORT:=5432}"
        ;;
    mysql)
        : "${ROUNDCUBEMAIL_DB_HOST:=mysql}"
        : "${ROUNDCUBEMAIL_DB_PORT:=3306}"
        ;;
    *)
        log "FATAL: unsupported ROUNDCUBEMAIL_DB_TYPE='${ROUNDCUBEMAIL_DB_TYPE}' (use mysql or pgsql)"
        exit 1
        ;;
esac
: "${ROUNDCUBEMAIL_DB_NAME:=roundcubemail}"
if [ -z "${ROUNDCUBEMAIL_DB_USER:-}" ] || [ -z "${ROUNDCUBEMAIL_DB_PASSWORD:-}" ]; then
    log "FATAL: ROUNDCUBEMAIL_DB_USER / ROUNDCUBEMAIL_DB_PASSWORD must be set"
    exit 1
fi
# URL-encode user+password when assembling the default DSN so special chars in
# the password don't corrupt it. An operator-supplied ROUNDCUBEMAIL_DSNW is used
# verbatim (they own the encoding). The :=word is only evaluated when DSNW is unset.
: "${ROUNDCUBEMAIL_DSNW:=${ROUNDCUBEMAIL_DB_TYPE}://$(urlenc "${ROUNDCUBEMAIL_DB_USER}"):$(urlenc "${ROUNDCUBEMAIL_DB_PASSWORD}")@${ROUNDCUBEMAIL_DB_HOST}:${ROUNDCUBEMAIL_DB_PORT}/${ROUNDCUBEMAIL_DB_NAME}}"
wait-for-it.sh -q "${ROUNDCUBEMAIL_DB_HOST}:${ROUNDCUBEMAIL_DB_PORT}" -t 30

# ---------------------------------------------------------------------------
# Generate config.inc.php into the writable config volume. RC finds it via
# env[RCUBE_CONFIG_PATH] = /var/roundcube/config/:config/ (set in the pool);
# defaults.inc.php + mimetypes.php come from the read-only install config/.
# ---------------------------------------------------------------------------
: "${ROUNDCUBEMAIL_DEFAULT_HOST:=localhost}"
: "${ROUNDCUBEMAIL_DEFAULT_PORT:=143}"
: "${ROUNDCUBEMAIL_SMTP_SERVER:=localhost}"
: "${ROUNDCUBEMAIL_SMTP_PORT:=587}"
: "${ROUNDCUBEMAIL_PLUGINS:=archive,zipdownload,managesieve,newmail_notifier,password,new_user_dialog}"
# Plugin names are identifiers — strip anything that isn't [A-Za-z0-9_,] so a
# stray value can't break out of the '...' PHP array literal generated below.
ROUNDCUBEMAIL_PLUGINS="$(printf '%s' "${ROUNDCUBEMAIL_PLUGINS}" | tr -cd 'A-Za-z0-9_,')"
: "${ROUNDCUBEMAIL_SKIN:=elastic}"
# IMAP/SMTP TLS handling. Verification is ON by default (secure transport).
#   1. (best) Point DEFAULT_HOST/SMTP at a name covered by the cert's SAN.
#   2. Pin the issuing CA: ROUNDCUBEMAIL_SSL_CA=/path/to/ca.pem (mount it).
#   3. (last resort, insecure) ROUNDCUBEMAIL_SSL_VERIFY=0 disables verification.
: "${ROUNDCUBEMAIL_SSL_VERIFY:=1}"
: "${ROUNDCUBEMAIL_SSL_CA:=}"

# des_key MUST stay stable across restarts: RC encrypts the IMAP password into
# the (DB-backed) session with it. A fresh key on every boot makes every
# pre-existing session undecryptable -> "Server Error: Empty password".
# Resolution: Docker secret > env > persisted <config>/.des_key > generate+persist.
DES_KEY_FILE=/var/roundcube/config/.des_key
if [ -f /run/secrets/roundcube_des_key ]; then
    ROUNDCUBEMAIL_DES_KEY="$(cat /run/secrets/roundcube_des_key)"
elif [ -n "${ROUNDCUBEMAIL_DES_KEY:-}" ]; then
    : # honour operator-supplied env var
elif [ -f "${DES_KEY_FILE}" ]; then
    ROUNDCUBEMAIL_DES_KEY="$(cat "${DES_KEY_FILE}")"
else
    ROUNDCUBEMAIL_DES_KEY="$(head -c 24 /dev/urandom | base64 | head -c 24)"
    ( umask 077; printf '%s' "${ROUNDCUBEMAIL_DES_KEY}" > "${DES_KEY_FILE}" )
fi

# Snuffleupagus secret_key — keys SP's cookie encryption. Like des_key it MUST be
# stable across restarts (a changed key invalidates SP-encrypted cookies, logging
# users out) and unique per deployment (the baked rulebook ships only a public
# placeholder). Same resolution order as des_key. The key is substituted into a
# per-deployment copy of the rulebook in the php-fpm override block below.
SP_SECRET_FILE=/var/roundcube/config/.sp_secret
if [ -f /run/secrets/roundcube_sp_secret ]; then
    SP_SECRET="$(cat /run/secrets/roundcube_sp_secret)"
elif [ -n "${ROUNDCUBEMAIL_SP_SECRET:-}" ]; then
    SP_SECRET="${ROUNDCUBEMAIL_SP_SECRET}"
elif [ -f "${SP_SECRET_FILE}" ]; then
    SP_SECRET="$(cat "${SP_SECRET_FILE}")"
else
    SP_SECRET="$(head -c 32 /dev/urandom | sha256sum | cut -d' ' -f1)"
    ( umask 077; printf '%s' "${SP_SECRET}" > "${SP_SECRET_FILE}" )
fi

if [ -n "${ROUNDCUBEMAIL_SSL_CA}" ]; then
    # CA pinning — verification stays ON, against the supplied CA bundle.
    _e_ca=$(php_sq "${ROUNDCUBEMAIL_SSL_CA}")
    SSL_OPTS_PHP="\$config['imap_conn_options'] = ['ssl' => ['verify_peer' => true, 'verify_peer_name' => true, 'cafile' => '${_e_ca}']];
\$config['smtp_conn_options'] = ['ssl' => ['verify_peer' => true, 'verify_peer_name' => true, 'cafile' => '${_e_ca}']];"
elif [ "${ROUNDCUBEMAIL_SSL_VERIFY}" = "0" ] || [ "${ROUNDCUBEMAIL_SSL_VERIFY}" = "false" ]; then
    log "WARNING: ROUNDCUBEMAIL_SSL_VERIFY=0 — IMAP/SMTP TLS peer verification DISABLED (MITM possible). Prefer a matching cert or ROUNDCUBEMAIL_SSL_CA."
    SSL_OPTS_PHP="\$config['imap_conn_options'] = ['ssl' => ['verify_peer' => false, 'verify_peer_name' => false, 'allow_self_signed' => true]];
\$config['smtp_conn_options'] = ['ssl' => ['verify_peer' => false, 'verify_peer_name' => false, 'allow_self_signed' => true]];"
else
    SSL_OPTS_PHP="// TLS peer verification enabled (default). Use ROUNDCUBEMAIL_SSL_CA to pin a private CA, or ROUNDCUBEMAIL_SSL_VERIFY=0 to disable (insecure)."
fi

ROUNDCUBEMAIL_PLUGINS_PHP="$(echo "${ROUNDCUBEMAIL_PLUGINS}" | sed -E "s/[, ]+/', '/g")"

# Escape every scalar interpolated into the single-quoted PHP literals below so a
# special char (notably a ' in the DB password / DSN) can't corrupt or inject
# into config.inc.php. Plugin names are pre-sanitised to [A-Za-z0-9_,] above.
_e_dsnw=$(php_sq "${ROUNDCUBEMAIL_DSNW}")
_e_dh=$(php_sq "${ROUNDCUBEMAIL_DEFAULT_HOST}")
_e_dp=$(php_sq "${ROUNDCUBEMAIL_DEFAULT_PORT}")
_e_ss=$(php_sq "${ROUNDCUBEMAIL_SMTP_SERVER}")
_e_sp=$(php_sq "${ROUNDCUBEMAIL_SMTP_PORT}")
_e_dk=$(php_sq "${ROUNDCUBEMAIL_DES_KEY}")
_e_td=$(php_sq "${ROUNDCUBEMAIL_TEMP_DIR}")
_e_skin=$(php_sq "${ROUNDCUBEMAIL_SKIN}")

umask 077
cat > /var/roundcube/config/config.inc.php <<PHP
<?php
\$config = [];
\$config['db_dsnw']      = '${_e_dsnw}';
\$config['default_host'] = '${_e_dh}';
\$config['default_port'] = '${_e_dp}';
\$config['smtp_server']  = '${_e_ss}';
\$config['smtp_port']    = '${_e_sp}';
\$config['des_key']      = '${_e_dk}';
\$config['temp_dir']     = '${_e_td}';
\$config['plugins']      = getenv('RCUBE_NO_PLUGINS') === '1' ? [] : ['${ROUNDCUBEMAIL_PLUGINS_PHP}'];
\$config['skin']         = '${_e_skin}';
\$config['zipdownload_selection'] = true;
\$config['log_driver']   = 'stdout';
\$config['session_storage'] = 'db';
${SSL_OPTS_PHP}
PHP

if [ -f /var/roundcube/config/config.inc.php.user ]; then
    echo "// ---- operator overrides ----"            >> /var/roundcube/config/config.inc.php
    sed '1{/^<?php/d}' /var/roundcube/config/config.inc.php.user >> /var/roundcube/config/config.inc.php
fi

# ---------------------------------------------------------------------------
# Enabled-plugin presence check. An enabled plugin with no plugins/<p>/<p>.php
# makes Roundcube fatal at REQUEST time — a silent, confusing failure. Warn
# loudly at boot instead (core plugins live at plugins/<p>/<p>.php too).
# ---------------------------------------------------------------------------
IFS=',' read -ra _enabled <<< "${ROUNDCUBEMAIL_PLUGINS}"
for _p in "${_enabled[@]}"; do
    _p="$(echo "$_p" | tr -d '[:space:]')"
    [ -n "$_p" ] || continue
    [ -f "${INSTALLDIR}/plugins/${_p}/${_p}.php" ] && continue
    log "WARNING: plugin '${_p}' is enabled but NOT installed in this image"
    log "  (missing ${INSTALLDIR}/plugins/${_p}/${_p}.php) — Roundcube will 500 on"
    log "  every request. Remove it from ROUNDCUBEMAIL_PLUGINS, mount it into"
    log "  plugins/${_p}/, or use an image that bundles it."
done

# ---------------------------------------------------------------------------
# Runtime php-fpm override driven by env (baked pool include targets this)
# ---------------------------------------------------------------------------
: > /var/roundcube/config/phpfpm.conf.override
if [ -n "${ROUNDCUBEMAIL_UPLOAD_MAX_FILESIZE:-}" ]; then
    {
        echo "php_admin_value[upload_max_filesize]=${ROUNDCUBEMAIL_UPLOAD_MAX_FILESIZE}"
        echo "php_admin_value[post_max_size]=${ROUNDCUBEMAIL_UPLOAD_MAX_FILESIZE}"
    } >> /var/roundcube/config/phpfpm.conf.override
fi

# Snuffleupagus: write a per-deployment copy of the rulebook onto the writable
# config volume with the real secret_key substituted, then point the FPM pool at
# it through this override include — which is parsed AFTER the baked
# sp.configuration_file in www.conf, so it wins. The baked rulebook lives on the
# read-only rootfs and only carries a placeholder, so it cannot be edited in place.
SP_RULES_SRC="/etc/php/${PHPVERSION}/php-snuffleupagus/roundcube.rules"
SP_RULES_DST="/var/roundcube/config/roundcube.rules"
if [ -f "${SP_RULES_SRC}" ]; then
    if ( umask 077; sed -E \
            "s|^sp\\.global\\.secret_key\\(.*|sp.global.secret_key(\"${SP_SECRET}\");|" \
            "${SP_RULES_SRC}" > "${SP_RULES_DST}" ); then
        echo "php_admin_value[sp.configuration_file]=${SP_RULES_DST}" \
            >> /var/roundcube/config/phpfpm.conf.override
    else
        log "WARNING: could not write ${SP_RULES_DST} — Snuffleupagus falls back to the baked rulebook (placeholder secret_key)"
    fi
fi

# ---------------------------------------------------------------------------
# Schema: initialise / migrate the DB. CLI-only (PHP CLI through Roundcube's own
# DB layer) — does NOT need php-fpm, so it runs here in the oneshot, before the
# pool comes up. See github.com/myguard-labs/dockerized#81 for why this is more than
# `initdb || updatedb` (that masked failures and could run the destructive init
# on a half-ready DB). We probe the ACTUAL schema, create-when-absent /
# migrate-when-present, and LOG the output.
# ---------------------------------------------------------------------------
as_rc() { "$@"; }

# Every CLI bootstrap step runs with plugins DISABLED: clisetup.php instantiates
# rcmail and init()s every enabled plugin, and request-time plugins are not
# CLI-safe (e.g. identity_switch's init() needs a logged-in user -> fatal
# TypeError). Plugin SQL applies via initdb/updatedb --dir, which does NOT load
# the plugin's PHP, so disabling plugins here is safe. config.inc.php reads this
# via getenv(); only THIS process tree sees it — the php-fpm longrun (a separate
# s6 service with clear_env=yes) keeps the full plugin set for web requests.
export RCUBE_NO_PLUGINS=1

case "${ROUNDCUBEMAIL_DB_TYPE}" in
    pgsql) db_driver_file="postgres" ;;
    *)     db_driver_file="mysql" ;;
esac

# rc_obj_exists <table> [column]: 0 = DB up AND object exists, 1 = DB up but
# object absent, 2 = DB unreachable. Driver-agnostic.
rc_obj_exists() {
    ( cd "${INSTALLDIR}" && php -d error_reporting=0 -r '
        define("INSTALL_PATH", getcwd()."/");
        require_once INSTALL_PATH."program/include/clisetup.php";
        $db = rcube::get_instance()->get_dbh();
        $db->db_connect("w");
        if (!$db->is_connected()) { exit(2); }
        $col = (isset($argv[2]) && $argv[2] !== "") ? $db->quote_identifier($argv[2]) : "1";
        $db->query("SELECT $col FROM ".$db->table_name($argv[1])." LIMIT 1");
        exit($db->is_error() ? 1 : 0);
    ' "$1" "${2:-}" ) >/dev/null 2>&1
}

# rc_pkg_versioned <package>: 0 if a recorded schema version exists in `system`.
rc_pkg_versioned() {
    ( cd "${INSTALLDIR}" && php -d error_reporting=0 -r '
        define("INSTALL_PATH", getcwd()."/");
        require_once INSTALL_PATH."program/include/clisetup.php";
        $db = rcube::get_instance()->get_dbh();
        $db->db_connect("w");
        if (!$db->is_connected()) { exit(2); }
        $r = $db->query("SELECT value FROM ".$db->table_name("system")." WHERE name=?", $argv[1]."-version");
        if ($db->is_error()) { exit(1); }
        exit($db->fetch_assoc($r) ? 0 : 1);
    ' "$1" ) >/dev/null 2>&1
}

# rc_set_pkg_version <package> <version>: stamp `system` so a plugin whose
# initial.sql doesn't self-register a version is still recorded as installed.
rc_set_pkg_version() {
    ( cd "${INSTALLDIR}" && php -d error_reporting=0 -r '
        define("INSTALL_PATH", getcwd()."/");
        require_once INSTALL_PATH."program/include/clisetup.php";
        $db = rcube::get_instance()->get_dbh();
        $db->db_connect("w");
        if (!$db->is_connected()) { exit(1); }
        $t = $db->table_name("system");
        $db->query("DELETE FROM $t WHERE name=?", $argv[1]."-version");
        $db->query("INSERT INTO $t (name, value) VALUES (?, ?)", $argv[1]."-version", $argv[2]);
        exit($db->is_error() ? 1 : 0);
    ' "$1" "$2" ) >/dev/null 2>&1
}

# Wait until the database is genuinely reachable (not just the TCP port).
log "Waiting for database to become ready"
db_ready=0
for _ in $(seq 1 60); do
    st=0; rc_obj_exists session || st=$?
    if [ "$st" != 2 ]; then db_ready=1; break; fi
    sleep 1
done
[ "$db_ready" = 1 ] || log "WARN: database still unreachable after 60s — schema step may fail"

# --- Core schema: create when absent, migrate when present (output LOGGED) ---
st=0; rc_obj_exists session || st=$?
case "$st" in
    1)
        log "Core schema absent — initialising (bin/initdb.sh --dir=SQL)"
        if ! ( cd "${INSTALLDIR}" && as_rc bin/initdb.sh --dir=SQL ) 2>&1 \
                | sed 's/^/[ROUNDCUBE][initdb] /'; then
            log "ERROR: core schema init FAILED — Roundcube will not work until 'bin/initdb.sh --dir=SQL' succeeds"
        fi
        ;;
    0)
        log "Core schema present — applying migrations (bin/updatedb.sh)"
        ( cd "${INSTALLDIR}" && as_rc bin/updatedb.sh --dir=SQL --package=roundcube ) 2>&1 \
            | sed 's/^/[ROUNDCUBE][updatedb] /' || true
        ;;
    *)
        log "ERROR: database unreachable — SKIPPING schema step (no tables will be created)"
        ;;
esac

# --- Enabled-plugin schemas (self-healing) -------------------------------------
# Roundcube core init does NOT migrate third-party plugin tables. For every
# enabled plugin shipping SQL/<driver>.initial.sql we reconcile the ACTUAL schema
# against the recorded version, so a partial/aborted previous run repairs itself.
# Set ROUNDCUBEMAIL_PLUGIN_DB_INIT=0 to opt out entirely.
if [ "$st" != 2 ] && [ "${ROUNDCUBEMAIL_PLUGIN_DB_INIT:-1}" != "0" ]; then
    IFS=',' read -ra _plugins <<< "${ROUNDCUBEMAIL_PLUGINS}"
    for _p in "${_plugins[@]}"; do
        _p="$(echo "$_p" | tr -d '[:space:]')"
        [ -n "$_p" ] || continue
        _sqldir="${INSTALLDIR}/plugins/${_p}/SQL"
        _initial="${_sqldir}/${db_driver_file}.initial.sql"
        [ -f "$_initial" ] || continue

        # newest delta version. The SQL/<driver>/ delta dir is OPTIONAL; guard the
        # ls so an absent dir doesn't trip set -o pipefail and kill the script.
        _ver=""
        [ -d "${_sqldir}/${db_driver_file}" ] && \
            _ver="$(ls "${_sqldir}/${db_driver_file}/" 2>/dev/null | sed -n 's/\.sql$//p' | sort -n | tail -1)"

        # schema marker: a created table, else an added column (table + column)
        _mtable="$(sed -n -E 's/.*CREATE TABLE([[:space:]]+IF NOT EXISTS)?[[:space:]]+`?([A-Za-z0-9_]+)`?.*/\2/Ip' "$_initial" | head -1)"
        _mcol=""
        if [ -z "$_mtable" ]; then
            _alter="$(sed -n -E 's/.*ALTER TABLE[[:space:]]+`?([A-Za-z0-9_]+)`?[[:space:]]+ADD[[:space:]]+(COLUMN[[:space:]]+)?`?([A-Za-z0-9_]+)`?.*/\1 \3/Ip' "$_initial" | head -1)"
            case "$_alter" in *" "*) _mtable="${_alter%% *}"; _mcol="${_alter#* }" ;; esac
        fi

        if rc_pkg_versioned "$_p"; then _has_ver=0; else _has_ver=1; fi
        if [ -n "$_mtable" ]; then
            if rc_obj_exists "$_mtable" "$_mcol"; then _has_obj=0; else _has_obj=1; fi
        else
            _has_obj=$_has_ver   # no detectable marker -> fall back to version row
        fi

        if [ "$_has_obj" = 0 ] && [ "$_has_ver" = 0 ]; then
            log "Plugin '${_p}': schema present — migrating"
            ( cd "${INSTALLDIR}" && as_rc bin/updatedb.sh --dir="plugins/${_p}/SQL" --package="${_p}" ) 2>&1 \
                | sed "s/^/[ROUNDCUBE][${_p}] /" || true
        elif [ "$_has_obj" = 0 ]; then
            log "Plugin '${_p}': schema present but unversioned — recording version (self-heal, no re-create)"
            rc_set_pkg_version "$_p" "${_ver:-0}" \
                || log "WARN: plugin '${_p}' version stamp failed"
        else
            if [ "$_has_ver" = 0 ]; then
                log "Plugin '${_p}': recorded but schema missing — re-initialising (self-heal)"
            else
                log "Plugin '${_p}': schema absent — initialising"
            fi
            if ( cd "${INSTALLDIR}" && as_rc bin/initdb.sh --dir="plugins/${_p}/SQL" ) 2>&1 \
                    | sed "s/^/[ROUNDCUBE][${_p}] /"; then
                rc_set_pkg_version "$_p" "${_ver:-0}" \
                    || log "WARN: plugin '${_p}' schema created but version stamp failed (reboot may re-init)"
            else
                log "ERROR: plugin '${_p}' schema init FAILED — see [${_p}] lines above"
            fi
        fi
    done
fi
( cd "${INSTALLDIR}" && as_rc bin/gc.sh >/dev/null 2>&1 ) || true

if [ -n "${CLEAN_INACTIVE_USERS_DAYS:-}" ]; then
    log "Purging users inactive > ${CLEAN_INACTIVE_USERS_DAYS} days"
    ( cd "${INSTALLDIR}" && as_rc bin/deluser.sh --age="${CLEAN_INACTIVE_USERS_DAYS}" 2>/dev/null ) || true
fi

log "init-bootstrap complete — handing off to s6 (php-fpm, angie)"
