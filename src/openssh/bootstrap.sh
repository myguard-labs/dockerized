#!/bin/sh

echo "[OPENSSH] This docker image can be found on https://hub.docker.com/u/eilandert and https://github.com/myguard-labs/dockerized"

host_keys_required() {
    echo /etc/ssh/ssh_host_rsa_key
    echo /etc/ssh/ssh_host_dsa_key
    echo /etc/ssh/ssh_host_ecdsa_key
    echo /etc/ssh/ssh_host_ed25519_key
}

create_key() {
    msg="$1"
    shift
    hostkeys="$1"
    shift
    file="$1"
    shift

    if echo "$hostkeys" | grep -x "$file" >/dev/null && \
        [ ! -f "$file" ] ; then
        printf %s "$msg"
        ssh-keygen -q -f "$file" -N '' "$@"
        echo
        if which restorecon >/dev/null 2>&1; then
            restorecon "$file" "$file.pub"
        fi
        ssh-keygen -l -f "$file.pub"
    fi
}

create_keys() {
    hostkeys="$(host_keys_required)"
    create_key "Creating SSH2 RSA key; this may take some time ..." \
        "$hostkeys" /etc/ssh/ssh_host_rsa_key -t rsa
    create_key "Creating SSH2 DSA key; this may take some time ..." \
        "$hostkeys" /etc/ssh/ssh_host_dsa_key -t dsa
    create_key "Creating SSH2 ECDSA key; this may take some time ..." \
        "$hostkeys" /etc/ssh/ssh_host_ecdsa_key -t ecdsa
    create_key "Creating SSH2 ED25519 key; this may take some time ..." \
        "$hostkeys" /etc/ssh/ssh_host_ed25519_key -t ed25519
}


if [ -n "${TZ}" ]; then
    rm -f /etc/timezone /etc/localtime
    echo "${TZ}" > /etc/timezone
    ln -s /usr/share/zoneinfo/${TZ} /etc/localtime
fi

FIRSTRUN="/etc/ssh/sshd_config"
if [ ! -f ${FIRSTRUN} ]; then
    echo "[OPENSSH] sshd_config not found, populating default configs to /etc/ssh"
    mkdir -p /etc/ssh
    cp -r /etc/ssh.orig/* /etc/ssh/
    rm -rf /etc/ssh/sshd_config.d/20*

    sed -i s/"#PermitRootLogin prohibit-password"/"PermitRootLogin yes"/ /etc/ssh/sshd_config
    echo "root:toor" | chpasswd

    echo "[OPENSSH] Creating new serverkeys"
    rm -f /etc/ssh/ssh_host_rsa_key*
    rm -f /etc/ssh/ssh_host_dsa_key*
    rm -f /etc/ssh/ssh_host_ecdsa_key*
    rm -f /etc/ssh/ssh_host_ed25519_key*
    create_keys
fi

if [ -n "${SYSLOG_HOST}" ]; then
    mkdir -p /etc/syslog-ng/conf.d
    echo "destination dst { syslog(\"${SYSLOG_HOST}\" transport(\"udp\")); };" > /etc/syslog-ng/conf.d/remote.conf
    echo "log { source(s_sys); destination(dst); };" >> /etc/syslog-ng/conf.d/remote.conf
    syslog-ng --no-caps
    echo "[OPENSSH] Output is set to remote syslog at ${SYSLOG_HOST}"
else
    rm -f /etc/syslog-ng/conf.d/remote.conf
fi

chmod 600 /etc/ssh/*key

VERSION=$(ssh -V 2>&1)
echo "[OPENSSH] Starting ${VERSION}"

exec /usr/sbin/sshd -D -o ListenAddress=0.0.0.0
