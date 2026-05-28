#!/usr/bin/env bash
# scripts/ci/run-in-vm.sh — run a command inside a cloud image via QEMU
#
# Usage: run-in-vm.sh IMAGE COMMAND LOG_FILE
#
# Boots IMAGE with QEMU, waits for SSH, runs COMMAND as root,
# streams output to LOG_FILE, exits with the command's exit code.
#
# Requires: qemu-system-x86_64, cloud-image-utils (cloud-localds), ssh, sshpass

set -euo pipefail

IMAGE="${1:?IMAGE required}"
COMMAND="${2:?COMMAND required}"
LOG_FILE="${3:-/tmp/vm-run.log}"

SSH_PORT="${SSH_PORT:-2222}"
SSH_KEY="${SSH_KEY:-/tmp/ci-vm-key}"
TIMEOUT="${TIMEOUT:-300}"   # seconds to wait for SSH

# Generate a throwaway SSH key if not present
if [[ ! -f "$SSH_KEY" ]]; then
  ssh-keygen -t ed25519 -N "" -f "$SSH_KEY" -q
fi

# Build cloud-init seed ISO to inject the SSH key
SEED_ISO="/tmp/ci-seed.iso"
META_DATA=$(mktemp)
USER_DATA=$(mktemp)
trap 'rm -f "$META_DATA" "$USER_DATA"' EXIT

cat > "$META_DATA" << 'META'
instance-id: ci-vm
local-hostname: ci-vm
META

cat > "$USER_DATA" << USERDATA
#cloud-config
ssh_authorized_keys:
  - $(cat "${SSH_KEY}.pub")
disable_root: false
runcmd:
  - echo "cloud-init done" > /tmp/cloud-init-done
USERDATA

cloud-localds "$SEED_ISO" "$USER_DATA" "$META_DATA"

# Boot the VM in the background
QEMU_PID_FILE="/tmp/ci-vm.pid"
qemu-system-x86_64 \
  -m 2048 \
  -smp 2 \
  -enable-kvm 2>/dev/null || true \
  -drive "file=${IMAGE},format=raw,if=virtio" \
  -drive "file=${SEED_ISO},format=raw,if=virtio" \
  -net nic,model=virtio \
  -net "user,hostfwd=tcp::${SSH_PORT}-:22" \
  -nographic \
  -serial "file:/tmp/ci-vm-serial.log" \
  -pidfile "$QEMU_PID_FILE" \
  -daemonize

VM_PID=$(cat "$QEMU_PID_FILE")
trap 'kill "$VM_PID" 2>/dev/null || true' EXIT

# Wait for SSH to become available
echo "Waiting for SSH on port ${SSH_PORT}..."
deadline=$(( $(date +%s) + TIMEOUT ))
while true; do
  if ssh -o StrictHostKeyChecking=no \
         -o ConnectTimeout=3 \
         -o BatchMode=yes \
         -i "$SSH_KEY" \
         -p "$SSH_PORT" \
         root@127.0.0.1 "true" 2>/dev/null; then
    echo "SSH ready"
    break
  fi
  [[ $(date +%s) -lt $deadline ]] || { echo "Timed out waiting for SSH"; exit 1; }
  sleep 5
done

# Run the command
echo "Running: $COMMAND"
ssh -o StrictHostKeyChecking=no \
    -o BatchMode=yes \
    -i "$SSH_KEY" \
    -p "$SSH_PORT" \
    root@127.0.0.1 \
    "$COMMAND" 2>&1 | tee "$LOG_FILE"

exit "${PIPESTATUS[0]}"
