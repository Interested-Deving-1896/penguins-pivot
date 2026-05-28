# penguins-pivot

A fork of [linux-pivot](https://github.com/Interested-Deving-1896/linux-pivot)
wired into the [penguins-eggs](https://github.com/pieroproietti/penguins-eggs)
all-features ecosystem. Enables live-ISO-based distro conversion: take a
penguins-eggs live ISO of any supported distro and remaster it as a different
distro, preserving users, services, and configuration.

## What this adds over linux-pivot

- `penguins-eggs/integration.sh` — integration layer called by penguins-eggs
  during the pivot phase of an ISO build or live-system remaster
- Manifest augmentation with eggs metadata (version, features, calamares flag)
- Automatic re-installation and re-configuration of penguins-eggs in the
  converted rootfs
- Feature flag passthrough (`calamares`, `wayland`, `firmware`, etc.)

## Usage

### Standalone (same as linux-pivot)

```bash
sudo ./pivot.sh --to debian
sudo ./pivot.sh --to arch --arch arm64 --kernel-convert
```

### Via penguins-eggs

```bash
export EGGS_ISO_DISTRO=ubuntu
export EGGS_TARGET_DISTRO=debian
export EGGS_FEATURES="calamares wayland firmware"
export EGGS_WORK_DIR=/tmp/penguins-eggs

sudo bash penguins-eggs/integration.sh

# Then produce the ISO
eggs produce --max
```

### Environment variables

| Variable | Default | Description |
|----------|---------|-------------|
| `EGGS_ISO_DISTRO` | *(required)* | Distro of the live ISO being built |
| `EGGS_TARGET_DISTRO` | same as ISO | Distro to convert to |
| `EGGS_TARGET_ARCH` | host arch | Target architecture |
| `EGGS_FEATURES` | *(empty)* | Space-separated penguins-eggs feature flags |
| `EGGS_WORK_DIR` | `/tmp/penguins-eggs` | Working directory |

## Supported distros and arches

Inherits full support from linux-pivot:

**Distros:** Debian, Ubuntu, Devuan, Arch, Fedora, Alpine, Void, openSUSE, Gentoo

**Arches:** `amd64` `arm64` `armhf` `riscv64` `ppc64el` `s390x` `loong64` `i386`

## Directory layout

```
pivot.sh                       # main entry point (from linux-pivot)
penguins-eggs/
  integration.sh               # penguins-eggs integration layer
lib/ extractors/ installers/   # inherited from linux-pivot
kernel/                        # lkf kernel conversion layer
config/                        # manifest schema + package map
.github/workflows/ci.yml       # CI: shellcheck + extract + dry-run matrix
```

## Relationship to linux-pivot

This repo tracks linux-pivot. Distro/arch support, extractors, installers,
and the kernel conversion layer are maintained upstream in linux-pivot and
merged here. penguins-eggs-specific changes live only in `penguins-eggs/`.

## License

MIT
