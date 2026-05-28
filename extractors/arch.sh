#!/usr/bin/env bash
# extractors/arch.sh — extract manifest from Arch Linux
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

extract_packages() {
  local manifest="$1" root="${2:-/}"
  local all; all=$(chroot "$root" pacman -Qq 2>/dev/null | sort)
  local explicit; explicit=$(chroot "$root" pacman -Qqe 2>/dev/null | sort)
  manifest_write_field "$manifest" "packages.installed_raw" "$(echo "$all" | tr '\n' ' ')"
  manifest_write_field "$manifest" "packages.explicit_raw"  "$(echo "$explicit" | tr '\n' ' ')"
  manifest_write_field "$manifest" "system.init" "systemd"
  manifest_write_field "$manifest" "system.libc" "glibc"
}

extract_services() {
  local manifest="$1" root="${2:-/}"
  local enabled; enabled=$(chroot "$root" systemctl list-unit-files --state=enabled --no-legend 2>/dev/null | awk '{print $1}' | tr '\n' ' ' || true)
  manifest_write_field "$manifest" "services.enabled_raw" "$enabled"
}

main() {
  local manifest="${1:-system.manifest.toml}" root="${2:-/}"
  log_step "Extracting manifest from Arch Linux"
  extract_common "$manifest" "$root"
  extract_packages "$manifest" "$root"
  extract_services "$manifest" "$root"
  manifest_validate "$manifest" && log_info "Manifest written: ${manifest}"
}
[[ "${BASH_SOURCE[0]}" == "$0" ]] && main "$@"
