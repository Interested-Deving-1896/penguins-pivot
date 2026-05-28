#!/usr/bin/env bash
# extractors/common.sh — distro-agnostic extraction helpers
#
# Each distro extractor sources this file, then implements:
#   extract_packages()   → populates manifest packages.installed + packages.explicit
#   extract_init()       → detects init system
#   extract_pkgmgr()     → detects package manager
#
# The common functions here handle kernel, bootloader, users, services,
# fstab, network, locale — all of which are readable from standard paths.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/manifest.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/log.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/arch.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/pkgmap.sh"

# ── kernel ────────────────────────────────────────────────────────────────────
extract_kernel() {
  local manifest="$1"
  local root="${2:-/}"

  # Running kernel version
  local kver; kver=$(uname -r 2>/dev/null || ls "${root}/lib/modules/" 2>/dev/null | sort -V | tail -1)
  manifest_write_field "$manifest" "kernel.version" "$kver"

  # Kernel config SHA
  local config_file="${root}/boot/config-${kver}"
  [[ -f "$config_file" ]] && \
    manifest_write_field "$manifest" "kernel.config_sha" "$(sha256sum "$config_file" | cut -d' ' -f1)"

  # Kernel cmdline
  local cmdline; cmdline=$(cat /proc/cmdline 2>/dev/null || true)
  manifest_write_field "$manifest" "kernel.cmdline" "$cmdline"

  # Loaded modules
  local modules; modules=$(lsmod 2>/dev/null | awk 'NR>1 {print $1}' | sort | tr '\n' ' ')
  manifest_write_field "$manifest" "kernel.modules_raw" "$modules"

  log_verbose "kernel: ${kver}"
}

# ── bootloader ────────────────────────────────────────────────────────────────
extract_bootloader() {
  local manifest="$1"
  local root="${2:-/}"

  local bl_type="" bl_config="" bl_efi="false"

  # EFI detection
  [[ -d /sys/firmware/efi ]] && bl_efi="true"

  # GRUB2
  if [[ -f "${root}/boot/grub/grub.cfg" || -f "${root}/boot/grub2/grub.cfg" ]]; then
    bl_type="grub2"
    bl_config="${root}/boot/grub/grub.cfg"
    [[ -f "${root}/boot/grub2/grub.cfg" ]] && bl_config="${root}/boot/grub2/grub.cfg"
  # systemd-boot
  elif [[ -f "${root}/boot/loader/loader.conf" || -d "${root}/boot/loader/entries" ]]; then
    bl_type="systemd-boot"
    bl_config="${root}/boot/loader/loader.conf"
  # U-Boot
  elif [[ -f "${root}/boot/boot.scr" || -f "${root}/boot/uEnv.txt" ]]; then
    bl_type="uboot"
    bl_config="${root}/boot/uEnv.txt"
  # syslinux/extlinux
  elif [[ -f "${root}/boot/syslinux/syslinux.cfg" || -f "${root}/boot/extlinux/extlinux.conf" ]]; then
    bl_type="syslinux"
    bl_config="${root}/boot/syslinux/syslinux.cfg"
  fi

  manifest_write_field "$manifest" "bootloader.type"        "$bl_type"
  manifest_write_field "$manifest" "bootloader.config_path" "$bl_config"
  manifest_write_field "$manifest" "bootloader.efi"         "$bl_efi"
  log_verbose "bootloader: ${bl_type} (efi=${bl_efi})"
}

# ── fstab ─────────────────────────────────────────────────────────────────────
extract_fstab() {
  local manifest="$1"
  local root="${2:-/}"
  local fstab="${root}/etc/fstab"
  [[ -f "$fstab" ]] || return 0

  # Write fstab as a raw string — installer will parse it
  local content; content=$(grep -v '^#' "$fstab" | grep -v '^$' | tr '\n' '|')
  manifest_write_field "$manifest" "fstab.raw" "$content"
  log_verbose "fstab: extracted"
}

# ── network ───────────────────────────────────────────────────────────────────
extract_network() {
  local manifest="$1"
  local root="${2:-/}"

  local mgr=""
  if   [[ -d "${root}/etc/NetworkManager" ]];    then mgr="networkmanager"
  elif [[ -d "${root}/etc/systemd/network" ]];   then mgr="systemd-networkd"
  elif [[ -f "${root}/etc/network/interfaces" ]]; then mgr="ifupdown"
  elif [[ -d "${root}/etc/netifrc" ]];            then mgr="netifrc"
  elif [[ -d "${root}/etc/wicked" ]];             then mgr="wicked"
  fi

  manifest_write_field "$manifest" "network.manager" "$mgr"

  local ifaces; ifaces=$(ip -o link show 2>/dev/null | awk -F': ' '{print $2}' | grep -v '^lo$' | tr '\n' ' ')
  manifest_write_field "$manifest" "network.interfaces_raw" "$ifaces"
  log_verbose "network: manager=${mgr}"
}

# ── locale + timezone ─────────────────────────────────────────────────────────
extract_locale() {
  local manifest="$1"
  local root="${2:-/}"

  local locale=""
  if [[ -f "${root}/etc/locale.conf" ]]; then
    locale=$(grep '^LANG=' "${root}/etc/locale.conf" | cut -d= -f2 | tr -d '"')
  elif [[ -f "${root}/etc/default/locale" ]]; then
    locale=$(grep '^LANG=' "${root}/etc/default/locale" | cut -d= -f2 | tr -d '"')
  fi
  [[ -z "$locale" ]] && locale=$(locale 2>/dev/null | grep '^LANG=' | cut -d= -f2)

  local tz=""
  if [[ -f "${root}/etc/timezone" ]]; then
    tz=$(cat "${root}/etc/timezone")
  elif [[ -L "${root}/etc/localtime" ]]; then
    tz=$(readlink "${root}/etc/localtime" | sed 's|.*/zoneinfo/||')
  fi

  manifest_write_field "$manifest" "system.locale"   "${locale:-en_US.UTF-8}"
  manifest_write_field "$manifest" "system.timezone"  "${tz:-UTC}"
  log_verbose "locale: ${locale} tz: ${tz}"
}

# ── users ─────────────────────────────────────────────────────────────────────
extract_users() {
  local manifest="$1"
  local root="${2:-/}"

  # Extract non-system users (UID >= 1000)
  local users_raw=""
  while IFS=: read -r name _ uid gid _ home shell; do
    [[ "$uid" -ge 1000 ]] 2>/dev/null || continue
    [[ "$shell" == */nologin || "$shell" == */false ]] && continue
    users_raw="${users_raw}${name}:${uid}:${gid}:${home}:${shell}|"
  done < "${root}/etc/passwd"

  manifest_write_field "$manifest" "users.raw" "$users_raw"
  log_verbose "users: extracted"
}

# ── hostname ──────────────────────────────────────────────────────────────────
extract_hostname() {
  local manifest="$1"
  local root="${2:-/}"

  local hostname=""
  [[ -f "${root}/etc/hostname" ]] && hostname=$(cat "${root}/etc/hostname" | tr -d '\n')
  [[ -z "$hostname" ]] && hostname=$(hostname 2>/dev/null || echo "linux")

  manifest_write_field "$manifest" "system.hostname" "$hostname"
}

# ── system identity ───────────────────────────────────────────────────────────
extract_identity() {
  local manifest="$1"
  local root="${2:-/}"

  manifest_write_field "$manifest" "system.arch" "$(detect_arch)"

  # Read /etc/os-release
  if [[ -f "${root}/etc/os-release" ]]; then
    local id; id=$(grep '^ID=' "${root}/etc/os-release" | cut -d= -f2 | tr -d '"')
    local version_id; version_id=$(grep '^VERSION_CODENAME=' "${root}/etc/os-release" | cut -d= -f2 | tr -d '"')
    [[ -z "$version_id" ]] && version_id=$(grep '^VERSION_ID=' "${root}/etc/os-release" | cut -d= -f2 | tr -d '"')
    manifest_write_field "$manifest" "system.distro"  "$id"
    manifest_write_field "$manifest" "system.release" "$version_id"
  fi

  manifest_write_field "$manifest" "manifest.version" "1"
}

# ── run all common extractions ────────────────────────────────────────────────
extract_common() {
  local manifest="$1"
  local root="${2:-/}"

  extract_identity   "$manifest" "$root"
  extract_hostname   "$manifest" "$root"
  extract_kernel     "$manifest" "$root"
  extract_bootloader "$manifest" "$root"
  extract_fstab      "$manifest" "$root"
  extract_network    "$manifest" "$root"
  extract_locale     "$manifest" "$root"
  extract_users      "$manifest" "$root"
}
