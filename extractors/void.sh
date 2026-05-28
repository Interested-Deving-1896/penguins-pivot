#!/usr/bin/env bash
# extractors/void.sh — extract manifest from Void Linux
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

extract_packages() {
  local manifest="$1" root="${2:-/}"
  local all; all=$(chroot "$root" xbps-query -l 2>/dev/null | awk '{print $2}' | sed 's/-[0-9].*//' | sort)
  local explicit; explicit=$(chroot "$root" xbps-query -m 2>/dev/null | sed 's/-[0-9].*//' | sort || echo "$all")
  manifest_write_field "$manifest" "packages.installed_raw" "$(echo "$all" | tr '\n' ' ')"
  manifest_write_field "$manifest" "packages.explicit_raw"  "$(echo "$explicit" | tr '\n' ' ')"
  manifest_write_field "$manifest" "system.init" "runit"
  # Detect musl vs glibc
  local libc="glibc"
  chroot "$root" xbps-query -l 2>/dev/null | grep -q 'musl' && libc="musl"
  manifest_write_field "$manifest" "system.libc" "$libc"
}

extract_services() {
  local manifest="$1" root="${2:-/}"
  local enabled; enabled=$(ls "${root}/var/service/" 2>/dev/null | tr '\n' ' ')
  manifest_write_field "$manifest" "services.enabled_raw" "$enabled"
}

main() {
  local manifest="${1:-system.manifest.toml}" root="${2:-/}"
  log_step "Extracting manifest from Void Linux"
  extract_common "$manifest" "$root"
  extract_packages "$manifest" "$root"
  extract_services "$manifest" "$root"
  manifest_validate "$manifest" && log_info "Manifest written: ${manifest}"
}
[[ "${BASH_SOURCE[0]}" == "$0" ]] && main "$@"
