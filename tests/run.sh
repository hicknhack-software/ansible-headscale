#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

ssh_dir=$(mktemp -d)
trap 'rm -rf -- "$ssh_dir"' EXIT
ssh-keygen -q -t ed25519 -N '' -f "$ssh_dir/id_ed25519"
install -m 0644 "$ssh_dir/id_ed25519.pub" /test-ssh/authorized_keys

ansible-galaxy collection install -r requirements.yml
ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -i headscale-vm, -u root \
  --private-key "$ssh_dir/id_ed25519" tests/headscale.yml
