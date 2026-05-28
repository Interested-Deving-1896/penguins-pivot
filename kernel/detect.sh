#!/usr/bin/env bash
# kernel/detect.sh — detect kernel packaging format and flavor from a running system
#
# Called by extractors to populate kernel.* fields in the manifest.
# Detects: version, flavor (generic/xanmod/liquorix/liqxanmod/rt/custom),
# packaging format, config SHA, modules, firmware.

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/../lib/manifest.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/log.sh"

# Detect kernel flavor from version string and installed packages
detect_kernel_flavor() {
  local root="${1:-/}"
  local kver; kver=$(uname -r 2>/dev/null || ls "${root}/lib/modules/" 2>/dev/null | sort -V | tail -1)

  case "$kver" in
    *xanmod*)    echo "xanmod" ;;
    *liquorix*|*lqx*) echo "liquorix" ;;
    *liqxanmod*) echo "liqxanmod" ;;
    *rt*)        echo "rt" ;;
    *lts*)       echo "lts" ;;
    *zen*)       echo "zen" ;;
    *)           echo "generic" ;;
  esac
}

# Detect kernel packaging format from the running distro
detect_kernel_format() {
  local root="${1:-/}"

  if   command -v dpkg   &>/dev/null; then echo "deb"
  elif command -v rpm    &>/dev/null; then echo "rpm"
  elif command -v pacman &>/dev/null; then echo "pkg"
  elif command -v apk    &>/dev/null; then echo "apk"
  elif command -v xbps-query &>/dev/null; then echo "xbps"
  elif [[ -d "${root}/var/db/pkg" ]]; then echo "ebuild"
  else echo "unknown"
  fi
}

# Extract full kernel metadata into manifest
extract_kernel_full() {
  local manifest="$1" root="${2:-/}"

  local kver; kver=$(uname -r 2>/dev/null || \
    ls "${root}/lib/modules/" 2>/dev/null | sort -V | tail -1)
  local flavor; flavor=$(detect_kernel_flavor "$root")
  local format; format=$(detect_kernel_format "$root")

  manifest_write_field "$manifest" "kernel.version" "$kver"
  manifest_write_field "$manifest" "kernel.flavor"  "$flavor"
  manifest_write_field "$manifest" "kernel.format"  "$format"

  # Config SHA
  local config="${root}/boot/config-${kver}"
  [[ -f "$config" ]] && \
    manifest_write_field "$manifest" "kernel.config_sha" \
      "$(sha256sum "$config" | cut -d' ' -f1)"

  # Cmdline
  manifest_write_field "$manifest" "kernel.cmdline" \
    "$(cat /proc/cmdline 2>/dev/null || true)"

  # Loaded modules (top 50 by name to keep manifest compact)
  local mods; mods=$(lsmod 2>/dev/null | awk 'NR>1{print $1}' | sort | head -50 | tr '\n' ' ')
  manifest_write_field "$manifest" "kernel.modules_raw" "$mods"

  # Firmware files (relative paths under /lib/firmware)
  local fw; fw=$(find "${root}/lib/firmware" -type f 2>/dev/null | \
    sed "s|${root}/lib/firmware/||" | sort | head -100 | tr '\n' ' ')
  manifest_write_field "$manifest" "kernel.firmware_raw" "$fw"

  # Installed kernel package name
  local pkg=""
  if command -v dpkg &>/dev/null; then
    pkg=$(dpkg -l 2>/dev/null | awk '/^ii.*linux-image/{print $2}' | grep "$kver" | head -1)
  elif command -v rpm &>/dev/null; then
    pkg=$(rpm -qa 2>/dev/null | grep -i "kernel.*${kver}" | head -1)
  elif command -v pacman &>/dev/null; then
    pkg=$(pacman -Qq 2>/dev/null | grep '^linux' | head -1)
  fi
  manifest_write_field "$manifest" "kernel.package" "$pkg"

  log_info "kernel: ${kver} (${flavor}, ${format})"
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && extract_kernel_full "$@"
