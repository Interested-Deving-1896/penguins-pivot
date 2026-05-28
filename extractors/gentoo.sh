#!/usr/bin/env bash
# extractors/gentoo.sh — extract manifest from Gentoo Linux
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

extract_packages() {
  local manifest="$1" root="${2:-/}"
  # All installed atoms
  local all; all=$(chroot "$root" qlist -IC 2>/dev/null | sort || \
                   find "${root}/var/db/pkg" -mindepth 2 -maxdepth 2 -type d 2>/dev/null | \
                   sed "s|${root}/var/db/pkg/||" | sort)
  # Explicitly installed (world set)
  local explicit; explicit=$(cat "${root}/var/lib/portage/world" 2>/dev/null | sort)
  manifest_write_field "$manifest" "packages.installed_raw" "$(echo "$all" | tr '\n' ' ')"
  manifest_write_field "$manifest" "packages.explicit_raw"  "$(echo "$explicit" | tr '\n' ' ')"
  # Init system
  local init="openrc"
  [[ -d "${root}/run/systemd" ]] && init="systemd"
  manifest_write_field "$manifest" "system.init" "$init"
  # libc
  local libc="glibc"
  [[ -f "${root}/etc/portage/make.conf" ]] && grep -q 'musl' "${root}/etc/portage/make.conf" && libc="musl"
  manifest_write_field "$manifest" "system.libc" "$libc"
  # Gentoo profile
  local profile; profile=$(readlink "${root}/etc/portage/make.profile" 2>/dev/null | sed 's|.*/profiles/||')
  manifest_write_field "$manifest" "system.gentoo_profile" "$profile"
}

extract_services() {
  local manifest="$1" root="${2:-/}"
  local enabled; enabled=$(chroot "$root" rc-update show 2>/dev/null | awk '{print $1}' | tr '\n' ' ' || true)
  manifest_write_field "$manifest" "services.enabled_raw" "$enabled"
}

main() {
  local manifest="${1:-system.manifest.toml}" root="${2:-/}"
  log_step "Extracting manifest from Gentoo Linux"
  extract_common "$manifest" "$root"
  extract_packages "$manifest" "$root"
  extract_services "$manifest" "$root"
  manifest_validate "$manifest" && log_info "Manifest written: ${manifest}"
}
[[ "${BASH_SOURCE[0]}" == "$0" ]] && main "$@"
