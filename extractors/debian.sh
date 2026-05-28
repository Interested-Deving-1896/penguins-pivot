#!/usr/bin/env bash
# extractors/debian.sh — extract manifest from Debian/Ubuntu/Devuan
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

extract_packages() {
  local manifest="$1" root="${2:-/}"
  local all; all=$(chroot "$root" dpkg-query -W -f='${Package}\n' 2>/dev/null | sort)
  local explicit; explicit=$(chroot "$root" apt-mark showmanual 2>/dev/null | sort)
  manifest_write_field "$manifest" "packages.installed_raw" "$(echo "$all" | tr '\n' ' ')"
  manifest_write_field "$manifest" "packages.explicit_raw"  "$(echo "$explicit" | tr '\n' ' ')"
  local init="systemd"
  chroot "$root" dpkg -l openrc 2>/dev/null | grep -q '^ii' && init="openrc"
  manifest_write_field "$manifest" "system.init" "$init"
  manifest_write_field "$manifest" "system.libc" "glibc"
}

extract_services() {
  local manifest="$1" root="${2:-/}"
  local enabled; enabled=$(chroot "$root" systemctl list-unit-files --state=enabled --no-legend 2>/dev/null | awk '{print $1}' | tr '\n' ' ' || true)
  manifest_write_field "$manifest" "services.enabled_raw" "$enabled"
}

main() {
  local manifest="${1:-system.manifest.toml}" root="${2:-/}"
  log_step "Extracting manifest from Debian/Ubuntu/Devuan"
  extract_common "$manifest" "$root"
  extract_packages "$manifest" "$root"
  extract_services "$manifest" "$root"
  manifest_validate "$manifest" && log_info "Manifest written: ${manifest}"
}
[[ "${BASH_SOURCE[0]}" == "$0" ]] && main "$@"
