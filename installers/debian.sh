#!/usr/bin/env bash
# installers/debian.sh — install a Debian/Ubuntu/Devuan system from manifest
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

DEBIAN_MIRROR="${DEBIAN_MIRROR:-http://deb.debian.org/debian}"

bootstrap_distro() {
  local manifest="$1" target="$2"
  local distro; distro=$(manifest_read_field "$manifest" "system.distro")
  local release; release=$(manifest_read_field "$manifest" "system.release")
  local arch; arch=$(manifest_read_field "$manifest" "system.arch")
  local stage3="/tmp/pivot-stage3.tar.gz"
  fetch_stage3 "$distro" "$release" "$arch" "$stage3"
  mkdir -p "$target"
  tar xf "$stage3" -C "$target"
  rm -f "$stage3"
  inject_qemu "$target" "$arch"
  mount_pseudo "$target"
  chroot_setup_dns "$target"
}

install_packages() {
  local manifest="$1" target="$2"
  local explicit_raw; explicit_raw=$(manifest_read_field "$manifest" "packages.explicit_raw")
  local pkgs=()
  for pkg in $explicit_raw; do
    local translated; translated=$(pkgmap_canonical_to_distro "$pkg" "debian")
    [[ -n "$translated" ]] && pkgs+=("$translated")
  done
  [[ ${#pkgs[@]} -eq 0 ]] && return 0
  in_chroot "$target" apt-get install -y --no-install-recommends "${pkgs[@]}" 2>/dev/null || true
}

configure_bootloader() {
  local manifest="$1" target="$2"
  local bl; bl=$(manifest_read_field "$manifest" "bootloader.type")
  case "$bl" in
    grub2) in_chroot "$target" grub-install 2>/dev/null || true
           in_chroot "$target" update-grub  2>/dev/null || true ;;
    systemd-boot) in_chroot "$target" bootctl install 2>/dev/null || true ;;
  esac
}

main() {
  local manifest="${1:-system.manifest.toml}" target="${2:-/mnt/pivot-target}" source="${3:-/}"
  log_step "Installing Debian/Ubuntu/Devuan from manifest"
  bootstrap_distro "$manifest" "$target"
  install_common   "$manifest" "$target" "$source"
  install_packages "$manifest" "$target"
  configure_bootloader "$manifest" "$target"
  umount_pseudo "$target"
  chroot_teardown_dns "$target"
  remove_qemu "$target"
  log_info "Install complete: ${target}"
}
[[ "${BASH_SOURCE[0]}" == "$0" ]] && main "$@"
