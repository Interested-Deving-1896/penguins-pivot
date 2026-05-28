#!/usr/bin/env bash
# lib/chroot.sh — chroot mount/umount helpers (shared by extractors + installers)

mount_pseudo() {
  local root="$1"
  mkdir -p "${root}"/{proc,sys,dev,dev/pts,run}
  mount -t proc  none          "${root}/proc"
  mount --bind   /sys          "${root}/sys"  && mount --make-slave "${root}/sys"
  mount --bind   /dev          "${root}/dev"  && mount --make-slave "${root}/dev"
  mount --bind   /dev/pts      "${root}/dev/pts" && mount --make-slave "${root}/dev/pts"
  mount -t tmpfs -o mode=1777 none "${root}/dev/shm" 2>/dev/null || true
  mount -t tmpfs none          "${root}/run"
}

umount_pseudo() {
  local root="$1"
  for mp in run dev/shm dev/pts dev sys proc; do
    mountpoint -q "${root}/${mp}" 2>/dev/null && umount -l "${root}/${mp}" || true
  done
}

# Run a command inside a chroot, with pseudo-fs already mounted
in_chroot() {
  local root="$1"; shift
  env -i \
    HOME=/root \
    PATH=/usr/sbin:/usr/bin:/sbin:/bin \
    TERM="${TERM:-xterm}" \
    chroot "$root" "$@"
}

# Copy resolv.conf into chroot for network access
chroot_setup_dns() {
  local root="$1"
  cp /etc/resolv.conf "${root}/etc/resolv.conf" 2>/dev/null || \
    echo 'nameserver 1.1.1.1' > "${root}/etc/resolv.conf"
}

chroot_teardown_dns() {
  local root="$1"
  rm -f "${root}/etc/resolv.conf"
}
