#!/usr/bin/env bash
# scripts/ci/fetch-cloud-image.sh — download a minimal cloud image for VM tests
#
# Usage: fetch-cloud-image.sh IMAGE_NAME OUTPUT_PATH
#   IMAGE_NAME: ubuntu-24.04-minimal | debian-12-minimal |
#               arch-latest-minimal  | alpine-3.20-minimal
#   OUTPUT_PATH: where to write the .img file

set -euo pipefail

IMAGE_NAME="${1:?IMAGE_NAME required}"
OUTPUT="${2:?OUTPUT_PATH required}"

declare -A URLS=(
  [ubuntu-24.04-minimal]="https://cloud-images.ubuntu.com/minimal/releases/noble/release/ubuntu-24.04-minimal-cloudimg-amd64.img"
  [debian-12-minimal]="https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-amd64.qcow2"
  [arch-latest-minimal]="https://geo.mirror.pkgbuild.com/images/latest/Arch-Linux-x86_64-cloudimg.qcow2"
  [alpine-3.20-minimal]="https://dl-cdn.alpinelinux.org/alpine/v3.20/releases/cloud/nocloud_alpine-3.20.0-x86_64-bios-cloudinit-r0.qcow2"
)

url="${URLS[$IMAGE_NAME]:-}"
[[ -n "$url" ]] || { echo "Unknown image: $IMAGE_NAME"; exit 1; }

# Use cached copy if present (CI cache key should include image name + date)
cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/linux-pivot-ci"
cache_file="${cache_dir}/${IMAGE_NAME}.img"
mkdir -p "$cache_dir"

if [[ -f "$cache_file" ]]; then
  echo "Using cached image: $cache_file"
  cp "$cache_file" "$OUTPUT"
  exit 0
fi

echo "Downloading: $url"
curl -fL --progress-bar "$url" -o "$OUTPUT"

# Convert qcow2 → raw if needed (virt-copy-in works on both but raw is faster)
if file "$OUTPUT" | grep -q QCOW; then
  echo "Converting qcow2 → raw..."
  qemu-img convert -f qcow2 -O raw "$OUTPUT" "${OUTPUT}.raw"
  mv "${OUTPUT}.raw" "$OUTPUT"
fi

# Cache for future runs
cp "$OUTPUT" "$cache_file"
echo "Image ready: $OUTPUT ($(du -sh "$OUTPUT" | cut -f1))"
