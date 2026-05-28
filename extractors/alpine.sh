#!/usr/bin/env bash
# extractors/alpine.sh — extract manifest from Alpine Linux
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

extract_packages() {
  local manifest="$1" root="${2:-/}"
  local all; all=$(chroot "$root" apk info 2>/dev/null | sort)
  local explicit; explicit=$(chroot "$root" apk info --installed -e $(chroot "$root" apk info 2>/dev/null) 2>/dev/null | sort || echo "$all")
  manifest_write_field "$manifest" "packages.installed_raw" "$(echo "$all" | tr '\n' ' ')"
  manifest_write_field "$manifest" "packages.explicit_raw"  "$(echo "$explicit" | tr '\n' ' ')"
  # Alpine uses OpenRC by default; musl libc
  local init="openrc"
  manifest_write_field "$manifest" "system.init" "$init"
  manifest_write_field "$manifest" "system.libc" "musl"
}

extract_services() {
  local manifest="$1" root="${2:-/}"
  local enabled; enabled=$(chroot "$root" rc-update show 2>/dev/null | awk '{print $1}' | tr '\n' ' ' || true)
  manifest_write_field "$manifest" "services.enabled_raw" "$enabled"
}

main() {
  local manifest="${1:-system.manifest.toml}" root="${2:-/}"
  log_step "Extracting manifest from Alpine Linux"
  extract_common "$manifest" "$root"
  extract_packages "$manifest" "$root"
  extract_services "$manifest" "$root"
  manifest_validate "$manifest" && log_info "Manifest written: ${manifest}"
}
[[ "${BASH_SOURCE[0]}" == "$0" ]] && main "$@"
