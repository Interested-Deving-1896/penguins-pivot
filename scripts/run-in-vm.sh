#!/usr/bin/env bash
# scripts/ci/run-in-vm.sh — run a command inside a VM
#
# Uses Incus if available (preferred — KVM-accelerated, clean lifecycle),
# falls back to raw QEMU with cloud-init on standard GitHub-hosted runners.
#
# Usage: run-in-vm.sh IMAGE_ALIAS COMMAND LOG_FILE
#
#   IMAGE_ALIAS  — Incus image alias (e.g. ubuntu-24.04) or path to a raw .img
#   COMMAND      — shell command to run as root inside the VM
#   LOG_FILE     — where to stream output (default: /tmp/vm-run.log)
#
# Env:
#   VM_CPUS      — vCPUs (default: 2)
#   VM_MEMORY    — RAM (default: 2GiB)
#   VM_DISK      — root disk size for Incus VMs (default: 20GiB)
#   VM_TIMEOUT   — seconds to wait for SSH (default: 300)

set -euo pipefail

IMAGE="${1:?IMAGE required}"
COMMAND="${2:?COMMAND required}"
LOG_FILE="${3:-/tmp/vm-run.log}"

VM_CPUS="${VM_CPUS:-2}"
VM_MEMORY="${VM_MEMORY:-2GiB}"
VM_DISK="${VM_DISK:-20GiB}"
VM_TIMEOUT="${VM_TIMEOUT:-300}"
VM_NAME="pivot-ci-$$"

# ── helpers ───────────────────────────────────────────────────────────────────
cleanup() {
  if command -v incus &>/dev/null && incus info "$VM_NAME" &>/dev/null 2>&1; then
    incus delete --force "$VM_NAME" 2>/dev/null || true
  fi
  if [[ -n "${QEMU_PID:-}" ]]; then
    kill "$QEMU_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

# ── Incus path ────────────────────────────────────────────────────────────────
if command -v incus &>/dev/null; then
  echo "[run-in-vm] Using Incus (KVM-accelerated)"

  # Launch VM from pre-pulled image alias
  incus launch "$IMAGE" "$VM_NAME" \
    --vm \
    --config limits.cpu="$VM_CPUS" \
    --config limits.memory="$VM_MEMORY" \
    --device "root,size=${VM_DISK}"

  # Wait for the VM to be ready
  echo "[run-in-vm] Waiting for VM to boot..."
  deadline=$(( $(date +%s) + VM_TIMEOUT ))
  while true; do
    state=$(incus info "$VM_NAME" 2>/dev/null \
      | grep -i '^Status:' | awk '{print $2}' || echo "unknown")
    if [[ "$state" == "Running" ]]; then
      # Also wait for cloud-init
      if incus exec "$VM_NAME" -- test -f /run/cloud-init/result.json 2>/dev/null; then
        break
      fi
    fi
    [[ $(date +%s) -lt $deadline ]] || { echo "Timed out waiting for VM"; exit 1; }
    sleep 3
  done
  echo "[run-in-vm] VM ready"

  # Copy repo into VM
  incus file push -r . "${VM_NAME}/opt/linux-pivot/"

  # Run the command
  echo "[run-in-vm] Running: $COMMAND"
  incus exec "$VM_NAME" -- bash -c "$COMMAND" 2>&1 | tee "$LOG_FILE"
  exit "${PIPESTATUS[0]}"
fi

# ── Raw QEMU fallback (GitHub-hosted runners without Incus) ───────────────────
echo "[run-in-vm] Incus not available — falling back to raw QEMU"

SSH_PORT="${SSH_PORT:-2222}"
SSH_KEY="/tmp/ci-vm-key-$$"
SEED_ISO="/tmp/ci-seed-$$.iso"

ssh-keygen -t ed25519 -N "" -f "$SSH_KEY" -q

META_DATA=$(mktemp)
USER_DATA=$(mktemp)
trap 'rm -f "$META_DATA" "$USER_DATA" "$SSH_KEY" "${SSH_KEY}.pub" "$SEED_ISO"' EXIT

cat > "$META_DATA" << META
instance-id: ci-vm
local-hostname: ci-vm
META

cat > "$USER_DATA" << USERDATA
#cloud-config
ssh_authorized_keys:
  - $(cat "${SSH_KEY}.pub")
disable_root: false
USERDATA

cloud-localds "$SEED_ISO" "$USER_DATA" "$META_DATA"

# Boot VM
qemu-system-x86_64 \
  -m 2048 -smp "$VM_CPUS" \
  $([ -c /dev/kvm ] && echo "-enable-kvm" || true) \
  -drive "file=${IMAGE},format=raw,if=virtio" \
  -drive "file=${SEED_ISO},format=raw,if=virtio" \
  -net nic,model=virtio \
  -net "user,hostfwd=tcp::${SSH_PORT}-:22" \
  -nographic \
  -serial "file:/tmp/ci-vm-serial-$$.log" \
  -daemonize \
  -pidfile "/tmp/ci-vm-$$.pid"

QEMU_PID=$(cat "/tmp/ci-vm-$$.pid")

# Wait for SSH
echo "[run-in-vm] Waiting for SSH on port ${SSH_PORT}..."
deadline=$(( $(date +%s) + VM_TIMEOUT ))
while true; do
  if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=3 -o BatchMode=yes \
       -i "$SSH_KEY" -p "$SSH_PORT" root@127.0.0.1 "true" 2>/dev/null; then
    echo "[run-in-vm] SSH ready"
    break
  fi
  [[ $(date +%s) -lt $deadline ]] || { echo "Timed out waiting for SSH"; exit 1; }
  sleep 5
done

# Copy repo and run
scp -o StrictHostKeyChecking=no -o BatchMode=yes \
    -i "$SSH_KEY" -P "$SSH_PORT" \
    -r . root@127.0.0.1:/opt/linux-pivot/

echo "[run-in-vm] Running: $COMMAND"
ssh -o StrictHostKeyChecking=no -o BatchMode=yes \
    -i "$SSH_KEY" -p "$SSH_PORT" \
    root@127.0.0.1 "$COMMAND" 2>&1 | tee "$LOG_FILE"

exit "${PIPESTATUS[0]}"
