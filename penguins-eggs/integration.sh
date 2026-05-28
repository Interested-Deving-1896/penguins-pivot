#!/usr/bin/env bash
# penguins-eggs/integration.sh — penguins-pivot integration layer
#
# Bridges linux-pivot with penguins-eggs all-features, enabling live-ISO-based
# distro conversion. Called by penguins-eggs during the "pivot" phase of an
# ISO build or live-system remaster.
#
# penguins-eggs passes:
#   EGGS_WORK_DIR    — working directory (default: /tmp/penguins-eggs)
#   EGGS_ISO_DISTRO  — distro ID of the live ISO being built
#   EGGS_TARGET_DISTRO — distro to convert to (optional; defaults to ISO distro)
#   EGGS_TARGET_ARCH — target architecture (optional; defaults to host arch)
#   EGGS_FEATURES    — space-separated list of enabled penguins-eggs features
#
# Exit codes:
#   0  success
#   1  configuration error
#   2  pivot failed

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PIVOT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

source "${PIVOT_ROOT}/lib/log.sh"
source "${PIVOT_ROOT}/lib/manifest.sh"

# ── defaults ──────────────────────────────────────────────────────────────────
EGGS_WORK_DIR="${EGGS_WORK_DIR:-/tmp/penguins-eggs}"
EGGS_ISO_DISTRO="${EGGS_ISO_DISTRO:-}"
EGGS_TARGET_DISTRO="${EGGS_TARGET_DISTRO:-}"
EGGS_TARGET_ARCH="${EGGS_TARGET_ARCH:-}"
EGGS_FEATURES="${EGGS_FEATURES:-}"

PIVOT_MANIFEST="${EGGS_WORK_DIR}/system.manifest.toml"
PIVOT_TARGET="${EGGS_WORK_DIR}/pivot-rootfs"

# ── validate ──────────────────────────────────────────────────────────────────
[[ -n "$EGGS_ISO_DISTRO" ]] || die "EGGS_ISO_DISTRO must be set"

# ── feature flags ─────────────────────────────────────────────────────────────
# Parse EGGS_FEATURES into an associative array for O(1) lookup
declare -A FEATURE
for f in $EGGS_FEATURES; do
  FEATURE["$f"]=1
done

feature_enabled() { [[ "${FEATURE[$1]+set}" == "set" ]]; }

# ── eggs-specific manifest augmentation ───────────────────────────────────────
# Adds penguins-eggs metadata to the manifest so the installer can
# include eggs tooling in the converted system.
augment_manifest_for_eggs() {
  local manifest="$1"
  log_step "Augmenting manifest with penguins-eggs metadata"

  manifest_write_field "$manifest" "eggs.version"  "$(eggs --version 2>/dev/null | head -1 || echo unknown)"
  manifest_write_field "$manifest" "eggs.features" "$EGGS_FEATURES"
  manifest_write_field "$manifest" "eggs.iso_distro" "$EGGS_ISO_DISTRO"

  # Record which eggs features are active so the installer can
  # re-enable them in the converted system
  if feature_enabled "calamares"; then
    manifest_write_field "$manifest" "eggs.calamares" "true"
  fi
  if feature_enabled "wayland"; then
    manifest_write_field "$manifest" "eggs.wayland" "true"
  fi
  if feature_enabled "firmware"; then
    manifest_write_field "$manifest" "eggs.firmware" "true"
  fi
}

# ── post-install eggs wiring ──────────────────────────────────────────────────
# Re-installs penguins-eggs tooling in the converted rootfs and re-runs
# eggs configuration so the converted system can itself produce ISOs.
wire_eggs_into_target() {
  local target="$1" target_distro="$2"
  log_step "Wiring penguins-eggs into converted rootfs (${target_distro})"

  # Install eggs in the target chroot
  case "$target_distro" in
    debian|ubuntu|devuan)
      chroot "$target" bash -c "
        curl -fsSL https://penguins-eggs.net/install | bash -s -- --yes
      " || log_info "eggs install failed (non-fatal; install manually)"
      ;;
    arch)
      chroot "$target" bash -c "
        pacman -Sy --noconfirm penguins-eggs 2>/dev/null || \
        yay -S --noconfirm penguins-eggs 2>/dev/null || true
      "
      ;;
    fedora)
      chroot "$target" bash -c "
        dnf install -y penguins-eggs 2>/dev/null || true
      "
      ;;
    *)
      log_info "No eggs auto-install for ${target_distro}; install manually"
      ;;
  esac

  # Re-run eggs configuration in the target
  if chroot "$target" which eggs &>/dev/null; then
    chroot "$target" eggs dad --default || true
    log_info "penguins-eggs configured in target"
  fi

  # Restore feature flags
  if feature_enabled "calamares"; then
    chroot "$target" eggs calamares --install 2>/dev/null || true
  fi
}

# ── main ──────────────────────────────────────────────────────────────────────
main() {
  log_info "penguins-pivot integration layer"
  log_info "  iso distro:    ${EGGS_ISO_DISTRO}"
  log_info "  target distro: ${EGGS_TARGET_DISTRO:-same as iso}"
  log_info "  target arch:   ${EGGS_TARGET_ARCH:-same as host}"
  log_info "  features:      ${EGGS_FEATURES:-none}"
  log_info "  work dir:      ${EGGS_WORK_DIR}"

  mkdir -p "$EGGS_WORK_DIR" "$PIVOT_TARGET"

  # Phase 1: extract manifest from live system
  log_step "Extracting system manifest"
  bash "${PIVOT_ROOT}/extractors/${EGGS_ISO_DISTRO}.sh" "$PIVOT_MANIFEST" /

  # Phase 2: augment manifest with eggs metadata
  augment_manifest_for_eggs "$PIVOT_MANIFEST"

  # Phase 3: run pivot (install phase only if target differs from source)
  local target_distro="${EGGS_TARGET_DISTRO:-$EGGS_ISO_DISTRO}"
  local arch_flag=""
  [[ -n "$EGGS_TARGET_ARCH" ]] && arch_flag="--arch ${EGGS_TARGET_ARCH}"

  log_step "Running pivot: ${EGGS_ISO_DISTRO} → ${target_distro}"
  # shellcheck disable=SC2086
  bash "${PIVOT_ROOT}/pivot.sh" \
    --from   "$PIVOT_MANIFEST" \
    --to     "$target_distro" \
    --target "$PIVOT_TARGET" \
    $arch_flag

  # Phase 4: wire eggs back into the converted rootfs
  wire_eggs_into_target "$PIVOT_TARGET" "$target_distro"

  log_info "penguins-pivot complete → ${PIVOT_TARGET}"
  log_info "Pass EGGS_WORK_DIR=${EGGS_WORK_DIR} to eggs produce to build the ISO"
}

main "$@"
