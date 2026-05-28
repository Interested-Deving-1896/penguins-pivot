#!/usr/bin/env bash
# pivot.sh — linux-pivot: distro-agnostic, arch-agnostic system converter
#
# Converts a running Linux system (or a rootfs directory) from one distro
# to another, preserving users, home directories, hostname, fstab, network
# config, and services. Optionally converts the kernel to the target distro's
# packaging format via lkf.
#
# Usage:
#   sudo ./pivot.sh --to debian                    # convert running system to Debian
#   sudo ./pivot.sh --to arch   --arch arm64       # convert to Arch on arm64
#   sudo ./pivot.sh --to gentoo --kernel-convert   # convert + rebuild kernel as ebuild
#   sudo ./pivot.sh --extract-only                 # just write system.manifest.toml
#   sudo ./pivot.sh --from system.manifest.toml --to fedora  # apply existing manifest
#
# Supported distros: debian ubuntu devuan arch fedora alpine void opensuse gentoo
# Supported arches:  amd64 arm64 armhf riscv64 ppc64el s390x loong64 i386

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "${SCRIPT_DIR}/lib/log.sh"
source "${SCRIPT_DIR}/lib/arch.sh"
source "${SCRIPT_DIR}/lib/manifest.sh"

# ── defaults ──────────────────────────────────────────────────────────────────
FROM_DISTRO=""          # auto-detected from running system
TO_DISTRO=""            # required (unless --extract-only)
TARGET_ARCH=""          # default: same as source
SOURCE_ROOT="/"         # source rootfs (default: running system)
TARGET_ROOT="/mnt/pivot-target"
MANIFEST_FILE="${MANIFEST_FILE:-system.manifest.toml}"
EXTRACT_ONLY=false
KERNEL_CONVERT=false
DRY_RUN=false
JOBS="${JOBS:-$(nproc)}"

SUPPORTED_DISTROS=(debian ubuntu devuan arch fedora alpine void opensuse gentoo)

# ── argument parsing ──────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --to)              TO_DISTRO="$2";      shift 2 ;;
    --from)            MANIFEST_FILE="$2";  shift 2 ;;
    --arch)            TARGET_ARCH="$2";    shift 2 ;;
    --source-root)     SOURCE_ROOT="$2";    shift 2 ;;
    --target)          TARGET_ROOT="$2";    shift 2 ;;
    --manifest)        MANIFEST_FILE="$2";  shift 2 ;;
    --extract-only)    EXTRACT_ONLY=true;   shift   ;;
    --kernel-convert)  KERNEL_CONVERT=true; shift   ;;
    --dry-run)         DRY_RUN=true;        shift   ;;
    --jobs)            JOBS="$2";           shift 2 ;;
    --verbose)         PIVOT_VERBOSE=1;     shift   ;;
    -h|--help)         _usage; exit 0 ;;
    *) die "Unknown option: $1 (run with --help)" ;;
  esac
done

_usage() {
  cat << 'USAGE'
Usage: sudo ./pivot.sh [OPTIONS]

Options:
  --to DISTRO          Target distro (required unless --extract-only)
  --from MANIFEST      Use existing manifest instead of extracting
  --arch ARCH          Target architecture (default: same as source)
  --source-root PATH   Source rootfs directory (default: /)
  --target PATH        Target rootfs directory (default: /mnt/pivot-target)
  --manifest FILE      Manifest file path (default: system.manifest.toml)
  --extract-only       Only extract manifest, do not install
  --kernel-convert     Also convert kernel to target distro format via lkf
  --dry-run            Show what would be done without doing it
  --jobs N             Parallel jobs (default: nproc)
  --verbose            Verbose output

Supported distros: debian ubuntu devuan arch fedora alpine void opensuse gentoo
Supported arches:  amd64 arm64 armhf riscv64 ppc64el s390x loong64 i386

Examples:
  sudo ./pivot.sh --to debian
  sudo ./pivot.sh --to arch --arch arm64
  sudo ./pivot.sh --to gentoo --kernel-convert
  sudo ./pivot.sh --extract-only --manifest /tmp/my-system.toml
  sudo ./pivot.sh --from /tmp/my-system.toml --to fedora
USAGE
}

# ── validation ────────────────────────────────────────────────────────────────
[[ $EUID -eq 0 ]] || die "Must run as root (sudo ./pivot.sh ...)"

_in_list() { local v="$1"; shift; for x in "$@"; do [[ "$x" == "$v" ]] && return 0; done; return 1; }

if [[ -n "$TO_DISTRO" ]]; then
  _in_list "$TO_DISTRO" "${SUPPORTED_DISTROS[@]}" || \
    die "Unsupported target distro: ${TO_DISTRO}. Supported: ${SUPPORTED_DISTROS[*]}"
fi

if [[ -n "$TARGET_ARCH" ]]; then
  _in_list "$TARGET_ARCH" amd64 arm64 armhf riscv64 ppc64el s390x loong64 i386 || \
    die "Unsupported arch: ${TARGET_ARCH}"
fi

# ── detect source distro ──────────────────────────────────────────────────────
detect_source_distro() {
  local root="${1:-/}"
  if [[ -f "${root}/etc/os-release" ]]; then
    grep '^ID=' "${root}/etc/os-release" | cut -d= -f2 | tr -d '"'
  else
    echo "unknown"
  fi
}

# ── extract phase ─────────────────────────────────────────────────────────────
run_extract() {
  local src_distro="$1"
  log_step "Phase 1: Extract — ${src_distro} → ${MANIFEST_FILE}"

  local extractor="${SCRIPT_DIR}/extractors/${src_distro}.sh"
  [[ -f "$extractor" ]] || die "No extractor for distro: ${src_distro}"

  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "[dry-run] would run: bash ${extractor} ${MANIFEST_FILE} ${SOURCE_ROOT}"
    return 0
  fi

  bash "$extractor" "$MANIFEST_FILE" "$SOURCE_ROOT"
  log_info "Manifest written: ${MANIFEST_FILE}"
}

# ── install phase ─────────────────────────────────────────────────────────────
run_install() {
  local target_distro="$1"
  log_step "Phase 2: Install — ${target_distro} → ${TARGET_ROOT}"

  local installer="${SCRIPT_DIR}/installers/${target_distro}.sh"
  [[ -f "$installer" ]] || die "No installer for distro: ${target_distro}"

  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "[dry-run] would run: bash ${installer} ${MANIFEST_FILE} ${TARGET_ROOT} ${SOURCE_ROOT}"
    return 0
  fi

  bash "$installer" "$MANIFEST_FILE" "$TARGET_ROOT" "$SOURCE_ROOT"
}

# ── kernel conversion phase ───────────────────────────────────────────────────
run_kernel_convert() {
  local target_distro="$1" target_arch="$2"
  log_step "Phase 3: Kernel conversion → ${target_distro}/${target_arch}"

  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "[dry-run] would run: kernel/convert.sh --manifest ${MANIFEST_FILE} --target-distro ${target_distro} --target-arch ${target_arch}"
    return 0
  fi

  JOBS="$JOBS" bash "${SCRIPT_DIR}/kernel/convert.sh" \
    --manifest       "$MANIFEST_FILE" \
    --target-distro  "$target_distro" \
    --target-arch    "$target_arch" \
    --output         "${TARGET_ROOT}/tmp/pivot-kernel"
}

# ── summary ───────────────────────────────────────────────────────────────────
print_summary() {
  local src="$1" dst="$2" arch="$3"
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  linux-pivot complete"
  echo "  ${src} → ${dst} (${arch})"
  echo "  manifest:  ${MANIFEST_FILE}"
  echo "  target:    ${TARGET_ROOT}"
  [[ "$KERNEL_CONVERT" == "true" ]] && \
    echo "  kernel:    ${TARGET_ROOT}/tmp/pivot-kernel"
  echo ""
  echo "  Next steps:"
  echo "    1. Review ${TARGET_ROOT} and verify the conversion"
  echo "    2. Update /etc/fstab in ${TARGET_ROOT} if needed"
  echo "    3. Chroot and install bootloader:"
  echo "       mount --bind /dev ${TARGET_ROOT}/dev"
  echo "       chroot ${TARGET_ROOT} grub-install /dev/sdX"
  echo "    4. Reboot into the new system"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# ── main ──────────────────────────────────────────────────────────────────────
main() {
  log_info "linux-pivot v1.0 — distro-agnostic system converter"
  log_info "  source root:  ${SOURCE_ROOT}"
  log_info "  target root:  ${TARGET_ROOT}"
  log_info "  manifest:     ${MANIFEST_FILE}"
  log_info "  jobs:         ${JOBS}"

  # Determine source distro
  local src_distro
  if [[ -f "$MANIFEST_FILE" ]]; then
    src_distro=$(manifest_read_field "$MANIFEST_FILE" "system.distro")
    log_info "Using existing manifest (source: ${src_distro})"
  else
    src_distro=$(detect_source_distro "$SOURCE_ROOT")
    log_info "Detected source distro: ${src_distro}"
    run_extract "$src_distro"
  fi

  [[ "$EXTRACT_ONLY" == "true" ]] && { log_info "Extract-only mode — done."; exit 0; }

  [[ -n "$TO_DISTRO" ]] || die "--to DISTRO is required (or use --extract-only)"

  # Determine target arch
  local target_arch="${TARGET_ARCH:-$(manifest_read_field "$MANIFEST_FILE" "system.arch")}"
  [[ -z "$target_arch" ]] && target_arch=$(detect_arch)

  log_info "Converting: ${src_distro} → ${TO_DISTRO} (${target_arch})"

  # Write target distro + arch into manifest so installer can read them
  manifest_write_field "$MANIFEST_FILE" "system.target_distro" "$TO_DISTRO"
  manifest_write_field "$MANIFEST_FILE" "system.target_arch"   "$target_arch"

  # Setup QEMU if cross-arch
  setup_qemu_for_arch "$target_arch"

  run_install "$TO_DISTRO"

  [[ "$KERNEL_CONVERT" == "true" ]] && run_kernel_convert "$TO_DISTRO" "$target_arch"

  print_summary "$src_distro" "$TO_DISTRO" "$target_arch"
}

main
