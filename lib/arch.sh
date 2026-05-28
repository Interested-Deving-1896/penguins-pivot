#!/usr/bin/env bash
# lib/arch.sh — architecture detection and normalisation
#
# Canonical arch names used throughout linux-pivot:
#   amd64 arm64 armhf riscv64 ppc64el s390x loong64 i386

# Detect the current host arch and normalise to canonical name
detect_arch() {
  local uname; uname=$(uname -m)
  case "$uname" in
    x86_64)                echo "amd64"   ;;
    aarch64)               echo "arm64"   ;;
    armv7l|armv7h|armhf)   echo "armhf"   ;;
    riscv64)               echo "riscv64" ;;
    ppc64le|ppc64el)       echo "ppc64el" ;;
    s390x)                 echo "s390x"   ;;
    loongarch64|loong64)   echo "loong64" ;;
    i686|i386)             echo "i386"    ;;
    *) echo "$uname" ;;
  esac
}

# Convert canonical arch → GNU triplet prefix for cross-compilation
arch_to_cross_prefix() {
  case "$1" in
    amd64)   echo "" ;;
    arm64)   echo "aarch64-linux-gnu-" ;;
    armhf)   echo "arm-linux-gnueabihf-" ;;
    riscv64) echo "riscv64-linux-gnu-" ;;
    ppc64el) echo "powerpc64le-linux-gnu-" ;;
    s390x)   echo "s390x-linux-gnu-" ;;
    loong64) echo "loongarch64-linux-gnu-" ;;
    i386)    echo "i686-linux-gnu-" ;;
    *)       echo "" ;;
  esac
}

# Convert canonical arch → QEMU user-static binary suffix
arch_to_qemu() {
  case "$1" in
    amd64)   echo "" ;;
    arm64)   echo "aarch64" ;;
    armhf)   echo "arm" ;;
    riscv64) echo "riscv64" ;;
    ppc64el) echo "ppc64le" ;;
    s390x)   echo "s390x" ;;
    loong64) echo "loongarch64" ;;
    i386)    echo "i386" ;;
    *)       echo "" ;;
  esac
}

# Convert canonical arch → Debian arch name
arch_to_debian() {
  echo "$1"  # canonical names match Debian names
}

# Convert canonical arch → RPM arch name
arch_to_rpm() {
  case "$1" in
    amd64)   echo "x86_64" ;;
    arm64)   echo "aarch64" ;;
    armhf)   echo "armhfp" ;;
    riscv64) echo "riscv64" ;;
    ppc64el) echo "ppc64le" ;;
    s390x)   echo "s390x" ;;
    i386)    echo "i686" ;;
    *)       echo "$1" ;;
  esac
}

# Convert canonical arch → Alpine arch name
arch_to_alpine() {
  case "$1" in
    amd64)   echo "x86_64" ;;
    arm64)   echo "aarch64" ;;
    armhf)   echo "armhf" ;;
    riscv64) echo "riscv64" ;;
    ppc64el) echo "ppc64le" ;;
    s390x)   echo "s390x" ;;
    loong64) echo "loongarch64" ;;
    i386)    echo "x86" ;;
    *)       echo "$1" ;;
  esac
}

# Convert canonical arch → Gentoo ARCH
arch_to_gentoo() {
  case "$1" in
    amd64)   echo "amd64" ;;
    arm64)   echo "arm64" ;;
    armhf)   echo "arm" ;;
    riscv64) echo "riscv" ;;
    ppc64el) echo "ppc64" ;;
    s390x)   echo "s390" ;;
    loong64) echo "loong" ;;
    i386)    echo "x86" ;;
    *)       echo "$1" ;;
  esac
}

# Setup QEMU binfmt_misc for cross-arch chroot
setup_qemu_for_arch() {
  local target_arch="$1"
  local host_arch; host_arch=$(detect_arch)
  [[ "$target_arch" == "$host_arch" ]] && return 0
  [[ "$host_arch" == "amd64" && "$target_arch" == "i386" ]] && return 0

  local qemu_suffix; qemu_suffix=$(arch_to_qemu "$target_arch")
  [[ -z "$qemu_suffix" ]] && return 0

  local qemu_bin="/usr/bin/qemu-${qemu_suffix}-static"
  if [[ ! -f "$qemu_bin" ]]; then
    if command -v apt-get &>/dev/null; then
      apt-get install -y --no-install-recommends qemu-user-static binfmt-support
    elif command -v dnf &>/dev/null; then
      dnf install -y qemu-user-static
    elif command -v pacman &>/dev/null; then
      pacman -S --noconfirm qemu-user-static
    else
      die "Cannot install qemu-user-static — install it manually"
    fi
  fi

  command -v update-binfmts &>/dev/null && update-binfmts --enable || true
  log_info "QEMU binfmt registered for ${target_arch} (${qemu_bin})"
}

# Inject QEMU binary into a chroot
inject_qemu() {
  local chroot_dir="$1" target_arch="$2"
  local host_arch; host_arch=$(detect_arch)
  [[ "$target_arch" == "$host_arch" ]] && return 0
  [[ "$host_arch" == "amd64" && "$target_arch" == "i386" ]] && return 0

  local qemu_suffix; qemu_suffix=$(arch_to_qemu "$target_arch")
  [[ -z "$qemu_suffix" ]] && return 0

  local qemu_bin="/usr/bin/qemu-${qemu_suffix}-static"
  [[ -f "$qemu_bin" ]] || return 0
  mkdir -p "${chroot_dir}/usr/bin"
  cp "$qemu_bin" "${chroot_dir}/usr/bin/"
  log_verbose "injected ${qemu_bin} into ${chroot_dir}"
}

remove_qemu() {
  local chroot_dir="$1"
  rm -f "${chroot_dir}/usr/bin/qemu-"*"-static"
}
