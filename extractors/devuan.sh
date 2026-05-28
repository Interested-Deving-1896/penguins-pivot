#!/usr/bin/env bash
# extractors/devuan.sh — Devuan (delegates to debian extractor, overrides init)
source "$(dirname "${BASH_SOURCE[0]}")/debian.sh"

extract_packages() {
  local manifest="$1" root="${2:-/}"
  local all; all=$(chroot "$root" dpkg-query -W -f='${Package}\n' 2>/dev/null | sort)
  local explicit; explicit=$(chroot "$root" apt-mark showmanual 2>/dev/null | sort)
  manifest_write_field "$manifest" "packages.installed_raw" "$(echo "$all" | tr '\n' ' ')"
  manifest_write_field "$manifest" "packages.explicit_raw"  "$(echo "$explicit" | tr '\n' ' ')"
  # Devuan uses sysvinit/openrc — not systemd
  local init="sysvinit"
  chroot "$root" dpkg -l openrc 2>/dev/null | grep -q '^ii' && init="openrc"
  chroot "$root" dpkg -l runit  2>/dev/null | grep -q '^ii' && init="runit"
  manifest_write_field "$manifest" "system.init" "$init"
  manifest_write_field "$manifest" "system.libc" "glibc"
}
