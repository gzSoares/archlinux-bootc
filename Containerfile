# =============================================================================
# Stage 1: Builder — compiles bootc from source
#
# bootc is not in the official Arch repos, so it must be compiled.
# NVIDIA/DKMS is NOT built here — dkms autoinstall needs the real running
# kernel, which is only available on first boot, not inside the OCI build.
# =============================================================================
FROM archlinux:latest AS builder

RUN pacman -Syu --noconfirm && \
    pacman -S --noconfirm --needed \
        base-devel git rust && \
    git clone --depth=1 https://github.com/containers/bootc /tmp/bootc && \
    cd /tmp/bootc && \
    cargo build --release && \
    install -Dm755 target/release/bootc /usr/local/bin/bootc && \
    rm -rf /tmp/bootc ~/.cargo

# =============================================================================
# Stage 2: Final image — Arch Linux + KDE Plasma 6 (minimal) + NVIDIA
# =============================================================================
FROM archlinux:latest AS final

LABEL ostree.bootable="true"
LABEL containers.bootc="1"
LABEL org.opencontainers.image.description="Arch Linux bootc — KDE Plasma 6 + NVIDIA"

COPY --from=builder /usr/local/bin/bootc /usr/local/bin/bootc

# Copy all config files from the repo root
COPY locale.conf vconsole.conf zram-generator.conf pacotes_necessarios \
     post-install.sh post-install.service \
     portals.conf xdg-desktop-portal.service ./

# -----------------------------------------------------------------------------
# Base system
# -----------------------------------------------------------------------------
RUN pacman -Syu --noconfirm && \
    pacman -S --noconfirm --needed \
        base base-devel \
        linux linux-headers linux-firmware \
        systemd systemd-sysvcompat \
        networkmanager \
        ostree \
        flatpak \
        zram-generator \
        sudo \
        bash fish \
        nano \
        curl wget git rsync \
        jq \
        man-db man-pages && \
    # bootc/ostree directory layout
    mkdir -vp /var/roothome /data /var/home && \
    rm -rf /opt && mkdir -vp /var/opt && ln -s /var/opt /opt && \
    # Safely move /usr/local to /var/usrlocal before any package writes to it
    mkdir -vp /var/usrlocal && \
    find /usr/local -mindepth 1 -maxdepth 1 -exec mv -v {} /var/usrlocal/ \; 2>/dev/null || true && \
    rm -rf /usr/local && ln -s /var/usrlocal /usr/local && \
    # Locale — English only
    mv locale.conf /etc/locale.conf && \
    echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen && \
    locale-gen && \
    # TTY keymap
    mv vconsole.conf /etc/vconsole.conf && \
    # Timezone
    ln -sf /usr/share/zoneinfo/UTC /etc/localtime && \
    # ZRAM swap
    mv zram-generator.conf /etc/systemd/ && \
    pacman -Scc --noconfirm

# -----------------------------------------------------------------------------
# NVIDIA drivers
#
# nvidia-open  → Turing (RTX 20xx) and newer  [open-source kernel module]
# nvidia-dkms  → Maxwell / Pascal / Volta      [proprietary, change if needed]
#
# dkms autoinstall runs on FIRST BOOT via post-install.service,
# not here — the build container does not have the real host kernel.
# -----------------------------------------------------------------------------
RUN pacman -S --noconfirm --needed \
        linux-headers \
        nvidia-open \
        nvidia-utils \
        lib32-nvidia-utils \
        nvidia-settings \
        opencl-nvidia \
        libvdpau \
        libxnvctrl && \
    printf 'nvidia\nnvidia_modeset\nnvidia_uvm\nnvidia_drm\n' \
        > /etc/modules-load.d/nvidia.conf && \
    echo "options nvidia-drm modeset=1 fbdev=1" > /etc/modprobe.d/nvidia.conf && \
    mkinitcpio -P && \
    pacman -Scc --noconfirm

# -----------------------------------------------------------------------------
# KDE Plasma 6 — minimal (no plasma-meta)
# -----------------------------------------------------------------------------
RUN pacman -S --noconfirm --needed \
        # Plasma core
        plasma-desktop \
        plasma-workspace \
        kwin \
        # Display manager — plasma-login-manager (Arch extra repo, Plasma 6.6+)
        plasma-login-manager \
        # Wayland
        qt6-wayland \
        xorg-xwayland \
        plasma-wayland-protocols \
        # XDG portals
        xdg-desktop-portal \
        xdg-desktop-portal-kde \
        xdg-utils \
        # Network
        plasma-nm \
        bluedevil \
        bluez \
        bluez-utils \
        # Audio
        plasma-pa \
        pipewire \
        pipewire-alsa \
        pipewire-pulse \
        wireplumber \
        playerctl \
        # Power / brightness
        powerdevil \
        kscreen \
        brightnessctl \
        # Polkit / wallet
        polkit-kde-agent \
        kwallet \
        kwallet-pam \
        # Essential apps
        dolphin \
        konsole \
        spectacle \
        ark \
        # System settings
        plasma-systemsettings \
        kde-gtk-config && \
    pacman -Scc --noconfirm

# -----------------------------------------------------------------------------
# Fonts and themes
# -----------------------------------------------------------------------------
RUN pacman -S --noconfirm --needed \
        ttf-jetbrains-mono-nerd \
        noto-fonts \
        noto-fonts-emoji \
        ttf-liberation \
        breeze \
        breeze-gtk && \
    pacman -Scc --noconfirm

# -----------------------------------------------------------------------------
# Essential utilities
# (nano removed — already installed in base block above)
# -----------------------------------------------------------------------------
RUN pacman -S --noconfirm --needed \
        kitty \
        starship \
        eza \
        ripgrep \
        mpv \
        ffmpeg \
        ffmpegthumbs \
        p7zip \
        unzip \
        zip \
        ntfs-3g \
        upower \
        lm_sensors \
        ddcutil && \
    pacman -Scc --noconfirm

# -----------------------------------------------------------------------------
# plasma-login-manager config
# Drop-in under /etc/plasmalogin.conf.d/ (correct path for the Arch package).
# DefaultSession must include the .desktop extension.
# -----------------------------------------------------------------------------
RUN mkdir -p /etc/plasmalogin.conf.d && \
    cat > /etc/plasmalogin.conf.d/defaults.conf << 'EOF'
[General]
DefaultSession=plasmawayland.desktop
HaltCommand=/usr/bin/systemctl poweroff
RebootCommand=/usr/bin/systemctl reboot
EOF

# -----------------------------------------------------------------------------
# XDG portal — patched unit + portals.conf for KDE
# Removes the graphical-session.target dependency that causes failures
# when the compositor doesn't activate that target automatically.
# -----------------------------------------------------------------------------
RUN install -Dm644 xdg-desktop-portal.service \
        /usr/lib/systemd/user/xdg-desktop-portal.service && \
    mkdir -p /etc/skel/.config/xdg-desktop-portal && \
    install -Dm644 portals.conf \
        /etc/skel/.config/xdg-desktop-portal/portals.conf && \
    rm xdg-desktop-portal.service portals.conf

# -----------------------------------------------------------------------------
# Skel — default config for new users
# -----------------------------------------------------------------------------
RUN mkdir -p /etc/skel/.config && \
    cat > /etc/skel/.config/plasma-localerc << 'EOF'
[Formats]
LANG=en_US.UTF-8

[Translations]
LANGUAGE=en_US
EOF

RUN cat > /etc/skel/.config/kwinrc << 'EOF'
[Compositing]
Backend=OpenGL
OpenGLIsUnsafe=false
EOF

RUN mkdir -p /etc/skel/.config/fish && \
    echo 'starship init fish | source' >> /etc/skel/.config/fish/config.fish && \
    echo 'eval "$(starship init bash)"' >> /etc/skel/.bash_profile

# -----------------------------------------------------------------------------
# Extra packages from pacotes_necessarios
# -----------------------------------------------------------------------------
RUN grep -v '^#' /pacotes_necessarios | grep -v '^$' | \
    xargs -r pacman -S --noconfirm --needed 2>/dev/null || true && \
    pacman -Scc --noconfirm

# -----------------------------------------------------------------------------
# post-install service
# -----------------------------------------------------------------------------
RUN install -Dm755 post-install.sh /usr/bin/post-install.sh && \
    install -Dm644 post-install.service /usr/lib/systemd/system/post-install.service && \
    rm post-install.sh post-install.service

# -----------------------------------------------------------------------------
# Enable services
# (thermald removed — not in official Arch repos)
# -----------------------------------------------------------------------------
RUN systemctl enable NetworkManager && \
    systemctl enable plasmalogin && \
    systemctl enable bluetooth && \
    systemctl enable post-install.service && \
    systemctl mask systemd-remount-fs.service && \
    rm -rf /var/roothome/.*

# -----------------------------------------------------------------------------
# Final cleanup
# -----------------------------------------------------------------------------
RUN rm -rf /var/cache/pacman/pkg/* /var/log/* /tmp/*

RUN bootc container lint

# =============================================================================
# Stage 3: Chunkah — splits image into OCI layers
# =============================================================================
FROM quay.io/coreos/chunkah AS chunkah

ARG CHUNKAH_CONFIG_STR

RUN --mount=from=final,src=/,target=/chunkah,ro \
    --mount=type=bind,target=/run/src,rw \
    chunkah build --max-layers 128 \
        --label ostree.commit- \
        --label ostree.final-diffid- \
        > /run/src/out.ociarchive

FROM oci-archive:out.ociarchive

LABEL ostree.bootable="true"
LABEL containers.bootc="1"
