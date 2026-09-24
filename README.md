[update-readmes]   Mode: rewrite — migrating to template structure...
# penguins-pivot

[![Built with Ona](https://ona.com/build-with-ona.svg)](https://app.ona.com/#https://github.com/Interested-Deving-1896/penguins-pivot) [![KDE Eco](https://img.shields.io/badge/KDE%20Eco-certified-brightgreen?logo=kde&logoColor=white&style=flat-square)](https://eco.kde.org/) [![Blue Angel](https://img.shields.io/badge/Blue%20Angel-DE--UZ%20215-0055a4?style=flat-square)](https://www.blauer-engel.de/en/certification/criteria)



<!-- AI:start:what-it-does -->
_Description pending._
<!-- AI:end:what-it-does -->

## Architecture

<!-- AI:start:architecture -->
_Architecture documentation pending._
<!-- AI:end:architecture -->

## Install

<!-- Add installation instructions here. This section is yours — the AI will not modify it. -->

```bash
git clone https://github.com/Interested-Deving-1896/penguins-pivot.git
cd penguins-pivot
```

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

## Configuration

<!-- Document configuration options here. This section is yours — the AI will not modify it. -->

## CI

<!-- AI:start:ci -->
_CI documentation pending._
<!-- AI:end:ci -->

## Mirror chain

<!-- AI:start:mirror-chain -->
This repo is maintained in [`Interested-Deving-1896/penguins-pivot`](https://github.com/Interested-Deving-1896/penguins-pivot) and mirrored through:

```
Interested-Deving-1896/penguins-pivot  ──►  OpenOS-Project-OSP/penguins-pivot  ──►  OpenOS-Project-Ecosystem-OOC/penguins-pivot
```

Changes flow downstream automatically via the hourly mirror chain in
[`fork-sync-all`](https://github.com/Interested-Deving-1896/fork-sync-all).
Direct commits to OSP or OOC are detected and opened as PRs back to `Interested-Deving-1896`.
<!-- AI:end:mirror-chain -->

## Contributors

<!-- AI:start:contributors -->
_Contributors pending._
<!-- AI:end:contributors -->

## Origins

<!-- AI:start:origins -->
_Original project — no upstream influences recorded._
<!-- AI:end:origins -->

## Resources

<!-- AI:start:resources -->
_No additional resource files found._
<!-- AI:end:resources -->

<!-- AI:start:accessibility -->
This repo uses automated accessibility auditing via `check-accessibility.yml`.

Checks include: CODEOWNERS ownership coverage, README screen-reader compatibility,
WCAG 2.1 AA HTML compliance, audio overview (espeak-ng), and Braille output (liblouis).




Run the [Check Accessibility](https://github.com/Interested-Deving-1896/penguins-pivot/actions/workflows/check-accessibility.yml)
workflow to generate the first report and accessibility artifacts.
See [DOCS/accessibility.md](https://github.com/Interested-Deving-1896/penguins-pivot/blob/main/DOCS/accessibility.md) for the full reference.
<!-- AI:end:accessibility -->

## License

<!-- AI:start:license -->
<!-- License not detected — add a LICENSE file to this repo. -->
<!-- AI:end:license -->
