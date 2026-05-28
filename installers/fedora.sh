#!/usr/bin/env bash
# installers/fedora.sh — install a Fedora system from manifest
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

bootstrap_distro() {
  local manifest="$1" target="$2"
  local arch; arch=$(manifest_read_field "$manifest" "system.arch")
  local release; release=$(manifest_read_field "$manifest" "system.release")
  local stage3="/tmp/pivot-stage3.tar.gz"
  fetch_stage3 "fedora" "$release" "$arch" "$stage3"
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
    local translated; translated=$(pkgmap_canonical_to_distro "$pkg" "fedora")
    [[ -n "$translated" ]] && pkgs+=("$translated")
  done
  [[ ${#pkgs[@]} -eq 0 ]] && return 0
  in_chroot "$target" dnf install -y "${pkgs[@]}" 2>/dev/null || true
}

configure_bootloader() {
  local manifest="$1" target="$2"
  in_chroot "$target" grub2-install 2>/dev/null || true
  in_chroot "$target" grub2-mkconfig -o /boot/grub2/grub.cfg 2>/dev/null || true
}

main() {
  local manifest="${1:-system.manifest.toml}" target="${2:-/mnt/pivot-target}" source="${3:-/}"
  log_step "Installing Fedora from manifest"
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
