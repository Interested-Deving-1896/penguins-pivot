#!/usr/bin/env bash
# scripts/ci/incus-setup-runner.sh — provision an Incus-based CI runner host
#
# Run once on a bare-metal or VM host to set it up as a self-hosted GitHub
# Actions runner that uses Incus VMs for the nightly pivot tests.
#
# What this does:
#   1. Installs Incus (from zabbly stable channel)
#   2. Initialises Incus with a storage pool and default network
#   3. Pre-pulls the cloud images used by the nightly workflow
#   4. Installs the GitHub Actions runner and registers it with the repo
#      (labels: self-hosted, linux, kvm, incus)
#
# Required env:
#   GH_RUNNER_TOKEN   — runner registration token from
#                       github.com/<owner>/<repo>/settings/actions/runners/new
#   GH_REPO           — e.g. Interested-Deving-1896/linux-pivot
#
# Optional env:
#   INCUS_STORAGE_POOL — name for the storage pool (default: pivot-ci)
#   INCUS_POOL_SIZE    — size of the storage pool (default: 50GB)
#   RUNNER_DIR         — where to install the runner (default: /opt/actions-runner)
#   RUNNER_USER        — user to run the runner as (default: runner)

set -euo pipefail

: "${GH_RUNNER_TOKEN:?GH_RUNNER_TOKEN is required}"
: "${GH_REPO:?GH_REPO is required}"

INCUS_STORAGE_POOL="${INCUS_STORAGE_POOL:-pivot-ci}"
INCUS_POOL_SIZE="${INCUS_POOL_SIZE:-50GB}"
RUNNER_DIR="${RUNNER_DIR:-/opt/actions-runner}"
RUNNER_USER="${RUNNER_USER:-runner}"

info() { echo "[incus-setup] $*"; }
die()  { echo "[incus-setup][error] $*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "Must run as root"

# ── 1. Install Incus ──────────────────────────────────────────────────────────
info "Installing Incus..."
if ! command -v incus &>/dev/null; then
  # zabbly stable channel — works on Debian 12, Ubuntu 22.04+
  curl -fsSL https://pkgs.zabbly.com/get/incus-stable | bash
fi
incus version
info "Incus installed: $(incus version | head -1)"

# ── 2. Initialise Incus ───────────────────────────────────────────────────────
info "Initialising Incus..."
if ! incus storage show "$INCUS_STORAGE_POOL" &>/dev/null; then
  cat << PRESEED | incus admin init --preseed
config: {}
networks:
  - name: incusbr0
    type: bridge
    config:
      ipv4.address: 10.88.0.1/24
      ipv4.nat: "true"
      ipv6.address: none
storage_pools:
  - name: ${INCUS_STORAGE_POOL}
    driver: btrfs
    config:
      size: ${INCUS_POOL_SIZE}
profiles:
  - name: default
    devices:
      eth0:
        name: eth0
        network: incusbr0
        type: nic
      root:
        path: /
        pool: ${INCUS_STORAGE_POOL}
        type: disk
PRESEED
  info "Incus initialised"
else
  info "Incus already initialised (pool ${INCUS_STORAGE_POOL} exists)"
fi

# Enable KVM acceleration if available
if [[ -c /dev/kvm ]]; then
  info "KVM available — enabling in default profile"
  incus profile device add default kvm unix-char source=/dev/kvm path=/dev/kvm 2>/dev/null || true
fi

# ── 3. Pre-pull cloud images ──────────────────────────────────────────────────
info "Pre-pulling cloud images..."
declare -A IMAGES=(
  [ubuntu-24.04]="ubuntu:24.04"
  [debian-12]="images:debian/12/cloud"
  [arch-latest]="images:archlinux/cloud"
  [alpine-3.20]="images:alpine/3.20/cloud"
  [fedora-40]="images:fedora/40/cloud"
)
for alias in "${!IMAGES[@]}"; do
  remote="${IMAGES[$alias]}"
  if incus image show "$alias" &>/dev/null; then
    info "  already cached: $alias"
  else
    info "  pulling: $remote → $alias"
    incus image copy "$remote" local: --alias "$alias" --vm 2>/dev/null || \
    incus image copy "$remote" local: --alias "$alias"
  fi
done

# ── 4. Create runner user ─────────────────────────────────────────────────────
info "Setting up runner user: ${RUNNER_USER}"
if ! id "$RUNNER_USER" &>/dev/null; then
  useradd -m -s /bin/bash "$RUNNER_USER"
fi
# Allow runner user to manage Incus VMs without sudo
usermod -aG incus-admin "$RUNNER_USER" 2>/dev/null || \
  usermod -aG incus "$RUNNER_USER" 2>/dev/null || true

# ── 5. Install GitHub Actions runner ─────────────────────────────────────────
info "Installing GitHub Actions runner..."
RUNNER_VERSION=$(curl -fsSL https://api.github.com/repos/actions/runner/releases/latest \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['tag_name'].lstrip('v'))")

mkdir -p "$RUNNER_DIR"
cd "$RUNNER_DIR"

if [[ ! -f "./config.sh" ]]; then
  ARCH=$(uname -m)
  case "$ARCH" in
    x86_64)  RUNNER_ARCH=x64 ;;
    aarch64) RUNNER_ARCH=arm64 ;;
    *)       die "Unsupported arch: $ARCH" ;;
  esac
  curl -fsSL \
    "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-${RUNNER_ARCH}-${RUNNER_VERSION}.tar.gz" \
    | tar -xz
fi

chown -R "${RUNNER_USER}:" "$RUNNER_DIR"

# Register the runner
sudo -u "$RUNNER_USER" ./config.sh \
  --url "https://github.com/${GH_REPO}" \
  --token "$GH_RUNNER_TOKEN" \
  --name "incus-kvm-$(hostname)" \
  --labels "self-hosted,linux,kvm,incus" \
  --work "_work" \
  --unattended \
  --replace

# Install as a systemd service
./svc.sh install "$RUNNER_USER"
./svc.sh start

info "Runner registered and started"
info "Labels: self-hosted, linux, kvm, incus"
info ""
info "Set vars.KVM_RUNNER = 'self-hosted' in your repo/org settings to use this runner"
info "Or set it to '[self-hosted, kvm, incus]' for the label selector"
