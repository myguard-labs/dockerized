#!/bin/bash
set -euo pipefail

image="${1:?usage: test-ssh-key-only.sh IMAGE}"
test_dir=$(mktemp -d)
container="aptly-ssh-test-$$"
trap 'docker rm -f "$container" >/dev/null 2>&1 || true; docker run --rm --entrypoint /bin/sh -v "$test_dir:/test" "$image" -c "rm -rf /test/ssh" >/dev/null 2>&1 || true; rmdir "$test_dir"' EXIT

mkdir -p "$test_dir/ssh"
cat > "$test_dir/ssh/sshd_config" <<'EOF'
PasswordAuthentication yes
Include /etc/ssh/sshd_config.d/*.conf
PubkeyAuthentication yes
UsePAM yes
EOF

# Prove the seed actually permits passwords before bootstrap changes it.
docker run --rm --entrypoint /bin/sh -v "$test_dir/ssh:/etc/ssh" "$image" \
    -c 'bash /ssh-createkeys.sh >/dev/null && /usr/sbin/sshd -T -C user=aptly,host=localhost,addr=127.0.0.1' \
    | grep -Eiq '^PasswordAuthentication yes$'

docker run --rm -d --name "$container" -v "$test_dir/ssh:/etc/ssh" \
    -e CLEANDBONSTART=NO -e STARTNGINX=NO -e STARTQUEUEWORKER=NO \
    "$image" >/dev/null

docker exec -u root "$container" /usr/sbin/sshd -t
docker exec -u root "$container" /usr/sbin/sshd -T \
    -C user=aptly,host=localhost,addr=127.0.0.1 \
    | grep -Eiq '^PasswordAuthentication no$'
docker exec -u root "$container" chage -l aptly \
    | grep -q 'Password expires.*never'
test "$(grep -c '^# aptly key-only policy$' "$test_dir/ssh/sshd_config")" -eq 1
echo 'aptly SSH key-only policy: passed'
