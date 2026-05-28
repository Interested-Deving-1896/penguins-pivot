#!/usr/bin/env bash
# lib/manifest.sh — manifest read/write helpers
#
# A manifest is a TOML file. Since bash has no native TOML parser, we use
# a minimal key=value flat representation for shell consumption and delegate
# full TOML parsing to Python (available on all supported distros).
#
# Usage:
#   source lib/manifest.sh
#   manifest_write_field  manifest.toml  "system.hostname"  "myhost"
#   manifest_read_field   manifest.toml  "system.hostname"
#   manifest_to_env       manifest.toml   # exports MANIFEST_* vars

set -euo pipefail

MANIFEST_SCHEMA_VERSION=1

# ── write a single field ──────────────────────────────────────────────────────
manifest_write_field() {
  local file="$1" key="$2" value="$3"
  python3 - "$file" "$key" "$value" << 'PY'
import sys, pathlib, re

file, key, value = sys.argv[1], sys.argv[2], sys.argv[3]
path = pathlib.Path(file)
text = path.read_text() if path.exists() else ""

# Simple key = "value" replacement/insertion
section, _, field = key.rpartition('.')
pattern = re.compile(rf'^({re.escape(field)}\s*=\s*).*$', re.MULTILINE)

if pattern.search(text):
    text = pattern.sub(rf'\g<1>"{value}"', text)
else:
    text += f'\n{field} = "{value}"\n'

path.write_text(text)
PY
}

# ── read a single field ───────────────────────────────────────────────────────
manifest_read_field() {
  local file="$1" key="$2"
  python3 - "$file" "$key" << 'PY'
import sys, pathlib, re

file, key = sys.argv[1], sys.argv[2]
path = pathlib.Path(file)
if not path.exists():
    sys.exit(0)

_, _, field = key.rpartition('.')
text = path.read_text()
m = re.search(rf'^{re.escape(field)}\s*=\s*"?([^"\n]*)"?', text, re.MULTILINE)
if m:
    print(m.group(1))
PY
}

# ── append to a list field ────────────────────────────────────────────────────
manifest_append_list() {
  local file="$1" key="$2" value="$3"
  python3 - "$file" "$key" "$value" << 'PY'
import sys, pathlib, re

file, key, value = sys.argv[1], sys.argv[2], sys.argv[3]
_, _, field = key.rpartition('.')
path = pathlib.Path(file)
text = path.read_text() if path.exists() else ""

# Find existing list and append
pattern = re.compile(rf'^({re.escape(field)}\s*=\s*\[)([^\]]*?)(\])', re.MULTILINE | re.DOTALL)
m = pattern.search(text)
if m:
    existing = m.group(2).strip().rstrip(',')
    sep = ',\n  ' if existing else '\n  '
    new_list = f'{m.group(1)}{existing}{sep}"{value}"\n{m.group(3)}'
    text = pattern.sub(new_list, text, count=1)
else:
    text += f'\n{field} = ["{value}"]\n'

path.write_text(text)
PY
}

# ── export all scalar fields as MANIFEST_* env vars ──────────────────────────
manifest_to_env() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  while IFS='=' read -r key val; do
    key="${key//[^a-zA-Z0-9_]/_}"
    val="${val//\"/}"
    export "MANIFEST_${key^^}=${val}"
  done < <(python3 - "$file" << 'PY'
import sys, re, pathlib
text = pathlib.Path(sys.argv[1]).read_text()
for line in text.splitlines():
    line = line.strip()
    if not line or line.startswith('#') or line.startswith('['):
        continue
    m = re.match(r'^(\w+)\s*=\s*"?([^"\n#]*)"?', line)
    if m:
        print(f"{m.group(1)}={m.group(2).strip()}")
PY
)
}

# ── validate manifest has required fields ─────────────────────────────────────
manifest_validate() {
  local file="$1"
  local errors=0
  for field in "system.hostname" "system.arch" "system.distro"; do
    val=$(manifest_read_field "$file" "$field")
    if [[ -z "$val" ]]; then
      echo "[manifest] ERROR: required field '${field}' is empty" >&2
      errors=$((errors + 1))
    fi
  done
  return $errors
}
