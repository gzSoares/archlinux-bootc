# archlinux-bootc

An immutable, bootc-based Arch Linux image with Hyprland and the Illogical Impulse (Quickshell) dotfiles, plus NVIDIA drivers.

## What's included

| Component | Details |
|---|---|
| Base | Arch Linux (`archlinux:latest`) |
| Compositor | Hyprland (Wayland) |
| Shell UI | Illogical Impulse — Quickshell by end-4 |
| Lock screen | Hyprlock |
| Idle daemon | Hypridle |
| Display Manager | SDDM |
| NVIDIA | `nvidia-open` + DKMS (compiled on first boot) |
| Audio | PipeWire + WirePlumber |
| File manager | Dolphin |
| Terminal | Kitty |
| Shell | fish + starship |
| Language | English (en_US.UTF-8) |

## File structure

| File | Purpose |
|---|---|
| `Containerfile` | Multi-stage image build definition |
| `pacotes_necessarios` | Optional extra packages installed via pacman at build time |
| `post-install.sh` | First-boot script: DKMS + AUR packages (yay, quickshell, matugen) + dots-hyprland setup |
| `post-install.service` | systemd unit that runs `post-install.sh` once |
| `portals.conf` | XDG portal backends (hyprland + kde) — copied to skel |
| `xdg-desktop-portal.service` | Patched portal unit (no `graphical-session.target` dependency) |
| `locale.conf` | System locale (`en_US.UTF-8`) |
| `vconsole.conf` | TTY keymap (`us`) |
| `zram-generator.conf` | ZRAM swap (half of RAM, zstd) |
| `config.toml` | User config for ISO generation via bootc-image-builder |
| `.github/workflows/build.yml` | CI/CD: builds OCI image and ISO, pushes to ghcr.io |

## First boot

On the first boot, `post-install.service` runs automatically and:

1. Waits for network
2. Compiles the NVIDIA kernel module via DKMS
3. Installs AUR packages: `yay`, `illogical-impulse-quickshell-git`, `matugen`, `bibata-cursor`, `microtex`
4. Clones [dots-hyprland](https://github.com/end-4/dots-hyprland) and runs `./setup install --core`
5. Adds Flathub and installs base Flatpaks

This takes several minutes on first boot. Check progress with:

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

The ISO is also built automatically by GitHub Actions and available as a workflow artifact.

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
sudo bootc upgrade --check   # check for updates
sudo bootc upgrade           # apply
sudo reboot

sudo bootc rollback          # roll back if needed
```

## NVIDIA drivers

This image uses `nvidia-open` (open-source kernel module), which supports **Turing (RTX 20xx) and newer** GPUs.

For older GPUs (Maxwell, Pascal, Volta), replace `nvidia-open` with `nvidia-dkms` in the `Containerfile`.

DKMS compilation runs on the **first boot** via `post-install.service` because it requires the actual running kernel.

## Customizing packages

Add packages to `pacotes_necessarios` (one per line, `#` for comments). Only official Arch repo packages — AUR packages must be installed at runtime.

## Credits

- Illogical Impulse / dots-hyprland: [end-4](https://github.com/end-4/dots-hyprland)
- bootc: [containers/bootc](https://github.com/containers/bootc)
