#!/usr/bin/env bash
# lib/pkgmap.sh — cross-distro package name translation
#
# Usage:
#   source lib/pkgmap.sh
#   pkgmap_canonical_to_distro vim arch        → vim
#   pkgmap_canonical_to_distro vim gentoo      → app-editors/vim
#   pkgmap_distro_to_canonical vim-enhanced fedora → vim
#   pkgmap_translate_list manifest.toml debian arch  → space-separated list

PKGMAP_FILE="${PKGMAP_FILE:-$(dirname "${BASH_SOURCE[0]}")/../config/package-map.toml}"

# Translate a canonical package name to a distro-specific name
pkgmap_canonical_to_distro() {
  local canonical="$1" distro="$2"
  python3 - "$PKGMAP_FILE" "$canonical" "$distro" << 'PY'
import sys, re, pathlib

pkgmap_file, canonical, distro = sys.argv[1], sys.argv[2], sys.argv[3]
text = pathlib.Path(pkgmap_file).read_text()

# Find [packages.{canonical}] section
section_re = re.compile(
    rf'^\[packages\.{re.escape(canonical)}\](.*?)(?=^\[|\Z)',
    re.MULTILINE | re.DOTALL
)
m = section_re.search(text)
if not m:
    print(canonical)  # fallback: assume same name
    sys.exit(0)

# Find distro = "value" within section
field_re = re.compile(rf'^{re.escape(distro)}\s*=\s*"([^"]*)"', re.MULTILINE)
fm = field_re.search(m.group(1))
if fm:
    val = fm.group(1)
    print(val if val else "")  # empty string = not available
else:
    print(canonical)  # fallback
PY
}

# Translate a distro-specific package name to canonical
pkgmap_distro_to_canonical() {
  local pkg="$1" distro="$2"
  python3 - "$PKGMAP_FILE" "$pkg" "$distro" << 'PY'
import sys, re, pathlib

pkgmap_file, pkg, distro = sys.argv[1], sys.argv[2], sys.argv[3]
text = pathlib.Path(pkgmap_file).read_text()

# Find any [packages.*] section where distro = "pkg"
section_re = re.compile(r'^\[packages\.(\w[\w-]*)\](.*?)(?=^\[|\Z)', re.MULTILINE | re.DOTALL)
for m in section_re.finditer(text):
    canonical = m.group(1)
    field_re = re.compile(rf'^{re.escape(distro)}\s*=\s*"{re.escape(pkg)}"', re.MULTILINE)
    if field_re.search(m.group(2)):
        print(canonical)
        sys.exit(0)

print(pkg)  # fallback: assume canonical == distro name
PY
}

# Translate a list of canonical names to distro-specific names
# Skips packages with empty distro mapping (not available)
pkgmap_translate_list() {
  local canonical_list=("$@")
  local distro="${canonical_list[-1]}"
  unset 'canonical_list[-1]'

  local result=()
  for pkg in "${canonical_list[@]}"; do
    local translated
    translated=$(pkgmap_canonical_to_distro "$pkg" "$distro")
    [[ -n "$translated" ]] && result+=("$translated")
  done
  echo "${result[@]}"
}

# Get all canonical names for a given distro package list
# Input: space-separated distro package names
# Output: space-separated canonical names
pkgmap_canonicalise_list() {
  local distro="$1"; shift
  local result=()
  for pkg in "$@"; do
    result+=("$(pkgmap_distro_to_canonical "$pkg" "$distro")")
  done
  echo "${result[@]}"
}
