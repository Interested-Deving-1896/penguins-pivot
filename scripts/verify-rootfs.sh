#!/usr/bin/env bash
# scripts/ci/verify-rootfs.sh — smoke-test a converted rootfs
#
# Usage: verify-rootfs.sh ROOTFS_PATH TARGET_DISTRO
#
# Checks that the rootfs looks like a valid installation of TARGET_DISTRO:
#   - Required directories exist
#   - /etc/os-release identifies the correct distro
#   - /etc/hostname is non-empty
#   - Package database is present
#   - At least one user exists in /etc/passwd

set -euo pipefail

ROOTFS="${1:?ROOTFS_PATH required}"
DISTRO="${2:?TARGET_DISTRO required}"

fail=0
check() {
  local desc="$1" result="$2"
  if [[ "$result" == "ok" ]]; then
    echo "  ✓ $desc"
  else
    echo "  ✗ $desc — $result"
    fail=1
  fi
}

echo "Verifying rootfs: $ROOTFS (target: $DISTRO)"

# Required directories
for d in etc usr var tmp home proc sys dev; do
  [[ -d "${ROOTFS}/${d}" ]] \
    && check "dir /${d}" "ok" \
    || check "dir /${d}" "missing"
done

# /etc/hostname
if [[ -s "${ROOTFS}/etc/hostname" ]]; then
  check "hostname" "ok"
else
  check "hostname" "missing or empty"
fi

# /etc/os-release distro ID
if [[ -f "${ROOTFS}/etc/os-release" ]]; then
  id_val=$(grep '^ID=' "${ROOTFS}/etc/os-release" | cut -d= -f2 | tr -d '"' | tr '[:upper:]' '[:lower:]')
  # Map distro names to expected ID values
  declare -A EXPECTED_IDS=(
    [debian]=debian [ubuntu]=ubuntu [devuan]=devuan
    [arch]=arch [fedora]=fedora [alpine]=alpine
    [void]=void [opensuse]=opensuse [gentoo]=gentoo
  )
  expected="${EXPECTED_IDS[$DISTRO]:-$DISTRO}"
  if [[ "$id_val" == "$expected"* ]]; then
    check "os-release ID=${id_val}" "ok"
  else
    check "os-release ID" "got '${id_val}', want '${expected}'"
  fi
else
  check "os-release" "missing"
fi

# Package database
declare -A PKG_DB=(
  [debian]="/var/lib/dpkg/status"
  [ubuntu]="/var/lib/dpkg/status"
  [devuan]="/var/lib/dpkg/status"
  [arch]="/var/lib/pacman/local"
  [fedora]="/var/lib/rpm"
  [alpine]="/lib/apk/db/installed"
  [void]="/var/db/xbps"
  [opensuse]="/var/lib/rpm"
  [gentoo]="/var/db/pkg"
)
db="${PKG_DB[$DISTRO]:-}"
if [[ -n "$db" ]]; then
  [[ -e "${ROOTFS}${db}" ]] \
    && check "package db (${db})" "ok" \
    || check "package db (${db})" "missing"
fi

# At least one non-system user or root in passwd
if grep -q '^root:' "${ROOTFS}/etc/passwd" 2>/dev/null; then
  check "passwd has root" "ok"
else
  check "passwd has root" "missing"
fi

echo ""
if [[ $fail -eq 0 ]]; then
  echo "Rootfs verification passed"
else
  echo "Rootfs verification FAILED"
  exit 1
fi
