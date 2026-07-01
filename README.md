# archlinux-bootc

An immutable, bootc-based Arch Linux image with KDE Plasma 6 and NVIDIA drivers.

## What's included

| Component | Details |
|---|---|
| Base | Arch Linux (`archlinux:latest`) |
| Desktop | KDE Plasma 6 (minimal — no `plasma-meta`) |
| Display Manager | `plasma-login-manager` (native KDE DM, Arch extra) |
| Compositor | KWin (Wayland) |
| NVIDIA | `nvidia-open` + DKMS (compiled on first boot) |
| Audio | PipeWire + WirePlumber |
| File manager | Dolphin |
| Terminal | Kitty |
| Shell | fish + starship |
| Language | English (en_US.UTF-8) |

## File structure

| File | Purpose |
|---|---|
| `Containerfile` | Multi-stage image build (builder / final / chunkah) |
| `pacotes_necessarios` | Optional extra packages installed via pacman at build time |
| `post-install.sh` | First-boot script: DKMS + Flatpak setup |
| `post-install.service` | systemd unit (system scope) that runs `post-install.sh` once |
| `portals.conf` | XDG portal backends (kde) — copied to user skel |
| `xdg-desktop-portal.service` | Patched unit without `graphical-session.target` dependency |
| `locale.conf` | System locale (`en_US.UTF-8`) |
| `vconsole.conf` | TTY keymap (`us`) |
| `zram-generator.conf` | ZRAM swap (half of RAM, zstd) |
| `config.toml` | User/partition config for ISO via bootc-image-builder |
| `.github/workflows/build.yml` | CI: build OCI image + ISO, push to ghcr.io |
| `.github/workflows/build-image.yml` | Manual ISO build with configurable type/rootfs/tag |

## First boot

`post-install.service` runs automatically on first boot and:

1. Waits for network
2. Compiles the NVIDIA kernel module via DKMS
3. Adds Flathub and installs base Flatpaks

Monitor progress with:
```bash
journalctl -fu post-install.service
```

## Using the image

### Switch from any bootc system

```bash
sudo bootc switch ghcr.io/gzsoares/archlinux-bootc:latest
sudo reboot
```

### Generate an install ISO

```bash
mkdir -p output
sudo podman run \
    --rm -it \
    --privileged \
    --pull=newer \
    --security-opt label=type:unconfined_t \
    -v ./output:/output \
    -v ./config.toml:/config.toml:ro \
    -v /var/lib/containers/storage:/var/lib/containers/storage \
    quay.io/centos-bootc/bootc-image-builder:latest \
    --type anaconda-iso \
    --rootfs btrfs \
    ghcr.io/gzsoares/archlinux-bootc:latest
```

ISOs are also built automatically by GitHub Actions and available as workflow artifacts.

### Local build

```bash
sudo buildah build \
    --skip-unused-stages=false \
    --security-opt=label=disable \
    -t "archlinux-bootc" \
    -f Containerfile \
    .
```

## System updates

```bash
sudo bootc upgrade --check   # check
sudo bootc upgrade           # apply
sudo reboot

sudo bootc rollback          # roll back if needed
```

## NVIDIA

Uses `nvidia-open` (open-source module) — requires **Turing (RTX 20xx) or newer**.

For older GPUs (Maxwell, Pascal, Volta), replace `nvidia-open` with `nvidia-dkms` in the `Containerfile`.

DKMS compilation runs on the **first boot** because it requires the actual running kernel.

## Customizing packages

Edit `pacotes_necessarios` — one package per line, `#` for comments. Official Arch repos only; AUR packages must be installed at runtime.
