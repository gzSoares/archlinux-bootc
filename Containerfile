# =============================================================================
# Estágio 1: Builder — compila bootc do source
# Nota: bootc não está nos repos oficiais do Arch, precisa ser compilado.
# NÃO instalamos nem compilamos NVIDIA aqui — dkms autoinstall precisa do
# kernel real do host e não funciona dentro de container OCI.
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
# Estágio 2: Imagem final — Arch Linux + KDE Plasma 6 enxuto + NVIDIA
# =============================================================================
FROM archlinux:latest AS final

LABEL ostree.bootable="true"
LABEL containers.bootc="1"
LABEL org.opencontainers.image.description="Arch Linux bootc com Hyprland + Illogical Impulse (Quickshell) + NVIDIA"

# Copiar bootc compilado do builder
COPY --from=builder /usr/local/bin/bootc /usr/local/bin/bootc

# Copiar arquivos de configuração do projeto
COPY locale.conf vconsole.conf post-install.sh post-install.service \
     zram-generator.conf pacotes_necessarios portals.conf \
     xdg-desktop-portal.service ./

# -----------------------------------------------------------------------------
# Base do sistema
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
    # Estrutura de diretórios requerida pelo bootc/ostree
    mkdir -vp /var/roothome /data /var/home && \
    rm -rf /opt && mkdir -vp /var/opt && ln -s /var/opt /opt && \
    # Mover /usr/local para /var/usrlocal antes de qualquer pacote escrever nele
    mkdir -vp /var/usrlocal && \
    find /usr/local -mindepth 1 -maxdepth 1 -exec mv -v {} /var/usrlocal/ \; 2>/dev/null || true && \
    rm -rf /usr/local && ln -s /var/usrlocal /usr/local && \
    # Locale
    mv locale.conf /etc/locale.conf && \
    echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen && \
    locale-gen && \
    # Teclado no TTY
    mv vconsole.conf /etc/vconsole.conf && \
    # Fuso horário
    ln -sf /usr/share/zoneinfo/UTC /etc/localtime && \
    # zram
    mv zram-generator.conf /etc/systemd/ && \
    pacman -Scc --noconfirm

# -----------------------------------------------------------------------------
# Drivers NVIDIA
#
# Escolha do driver:
#   nvidia-open  → GPUs Turing (RTX 20xx) ou mais novas  [driver open-source parcial]
#   nvidia-dkms  → GPUs Maxwell/Pascal/Volta/Turing/Ampere [driver proprietário fechado]
#
# Troque nvidia-open por nvidia-dkms se sua GPU for anterior à RTX 20xx.
#
# IMPORTANTE: dkms autoinstall NÃO roda aqui — precisa do kernel real do host.
# O post-install.service cuida disso no primeiro boot.
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
    # Módulos carregados automaticamente no boot
    printf 'nvidia\nnvidia_modeset\nnvidia_uvm\nnvidia_drm\n' \
        > /etc/modules-load.d/nvidia.conf && \
    # Habilitar DRM modesetting (necessário para Wayland)
    echo "options nvidia-drm modeset=1 fbdev=1" > /etc/modprobe.d/nvidia.conf && \
    # Garantir que nvidia_drm não entre no initramfs via autodetect
    # (o módulo é carregado pelo modules-load.d no espaço do usuário)
    # Regenerar initramfs com o kernel instalado nesta imagem
    mkinitcpio -P && \
    pacman -Scc --noconfirm

# -----------------------------------------------------------------------------
# Hyprland + dependências core
# Pacotes dos repos oficiais (illogical-impulse-hyprland meta-package equivalente)
# -----------------------------------------------------------------------------
RUN pacman -S --noconfirm --needed \
        # Compositor
        hyprland \
        hyprpaper \
        hypridle \
        hyprlock \
        hyprpicker \
        hyprsunset \
        # Display manager
        sddm \
        # Wayland essentials
        qt6-wayland \
        xorg-xwayland \
        xdg-desktop-portal \
        xdg-desktop-portal-hyprland \
        xdg-desktop-portal-kde \
        xdg-utils \
        # Rede
        networkmanager \
        bluez \
        bluez-utils \
        # Clipboard e launchers
        wl-clipboard \
        cliphist \
        fuzzel \
        # Polkit
        polkit-kde-agent && \
    pacman -Scc --noconfirm

# -----------------------------------------------------------------------------
# Áudio (illogical-impulse-audio)
# -----------------------------------------------------------------------------
RUN pacman -S --noconfirm --needed \
        pipewire \
        pipewire-alsa \
        pipewire-pulse \
        pipewire-jack \
        wireplumber \
        playerctl \
        cava && \
    pacman -Scc --noconfirm

# -----------------------------------------------------------------------------
# Quickshell — dependências Qt6 requeridas pelo II
# O binário do quickshell é compilado pelo post-install.sh via makepkg/AUR
# (illogical-impulse-quickshell-git pina um commit específico incompatível
#  com o quickshell-git do AUR genérico — precisa de makepkg em runtime)
# -----------------------------------------------------------------------------
RUN pacman -S --noconfirm --needed \
        qt6-base \
        qt6-declarative \
        qt6-wayland \
        qt6-5compat \
        qt6-multimedia \
        qt6-quicktimeline \
        qt6-virtualkeyboard \
        qt6-svg \
        qt6-positioning \
        cmake \
        ninja && \
    pacman -Scc --noconfirm

# -----------------------------------------------------------------------------
# Fontes e temas (illogical-impulse-fonts-themes)
# matugen — Material You color generator (AUR, compilado no post-install)
# -----------------------------------------------------------------------------
RUN pacman -S --noconfirm --needed \
        ttf-jetbrains-mono-nerd \
        ttf-readex-pro \
        ttf-material-symbols-variable-git 2>/dev/null || \
    pacman -S --noconfirm --needed ttf-material-symbols && \
    pacman -S --noconfirm --needed \
        noto-fonts \
        noto-fonts-emoji \
        ttf-liberation && \
    pacman -Scc --noconfirm

# -----------------------------------------------------------------------------
# Widgets e ferramentas de captura (illogical-impulse-widgets + screencapture)
# -----------------------------------------------------------------------------
RUN pacman -S --noconfirm --needed \
        # Captura de tela
        hyprshot \
        slurp \
        grim \
        swappy \
        wf-recorder \
        # OCR
        tesseract \
        tesseract-data-eng \
        # Misc UI
        libqalculate \
        upower && \
    pacman -Scc --noconfirm

# -----------------------------------------------------------------------------
# Python + GObject (illogical-impulse-python)
# kde-material-you-colors usa Python + KDE libs
# -----------------------------------------------------------------------------
RUN pacman -S --noconfirm --needed \
        python \
        uv \
        gtk4 \
        libadwaita \
        gobject-introspection \
        python-gobject && \
    pacman -Scc --noconfirm

# -----------------------------------------------------------------------------
# KDE apps integrados ao II (illogical-impulse-kde)
# Dolphin, KDE Connect, configurações de Bluetooth/rede via plasma-nm
# -----------------------------------------------------------------------------
RUN pacman -S --noconfirm --needed \
        dolphin \
        plasma-nm \
        bluedevil \
        systemsettings \
        kde-gtk-config && \
    pacman -Scc --noconfirm

# -----------------------------------------------------------------------------
# Utilitários essenciais
# -----------------------------------------------------------------------------
RUN pacman -S --noconfirm --needed \
        kitty \
        starship \
        eza \
        ripgrep \
        bc \
        jq \
        go-yq \
        rsync \
        mpv \
        ffmpeg \
        imagemagick \
        p7zip \
        unzip \
        zip \
        ntfs-3g \
        brightnessctl \
        ddcutil \
        lm_sensors \
        wtype \
        ydotool && \
    pacman -Scc --noconfirm

# -----------------------------------------------------------------------------
# Configuração do SDDM (DM usado com Hyprland no Arch)
# -----------------------------------------------------------------------------
RUN mkdir -p /etc/sddm.conf.d && \
    cat > /etc/sddm.conf.d/hyprland.conf << 'EOF'
[General]
HaltCommand=/usr/bin/systemctl poweroff
RebootCommand=/usr/bin/systemctl reboot

[Wayland]
EnableHiDPI=true
EOF

# -----------------------------------------------------------------------------
# Portal XDG para Hyprland
# Remove dependência de graphical-session.target (não ativado pelo Hyprland sem UWSM)
# -----------------------------------------------------------------------------
RUN mkdir -p /usr/lib/systemd/user && \
    cp xdg-desktop-portal.service /usr/lib/systemd/user/xdg-desktop-portal.service && \
    mkdir -p /etc/skel/.config/xdg-desktop-portal && \
    cp portals.conf /etc/skel/.config/xdg-desktop-portal/portals.conf && \
    rm xdg-desktop-portal.service portals.conf

# -----------------------------------------------------------------------------
# Skel — configuração base para novos usuários
# -----------------------------------------------------------------------------
# Shell
RUN mkdir -p /etc/skel/.config/fish && \
    echo 'starship init fish | source' >> /etc/skel/.config/fish/config.fish && \
    echo 'eval "$(starship init bash)"' >> /etc/skel/.bash_profile

# Variável de ambiente requerida pelo II Quickshell
# (definida aqui como fallback; o setup.sh do II a injeta no hyprland/env.lua)
RUN mkdir -p /etc/skel/.config/hypr && \
    cat > /etc/skel/.config/hypr/env-bootc.conf << 'EOF'
# Gerado pelo Containerfile — sobrescrito pelo setup do illogical-impulse
env = ILLOGICAL_IMPULSE_VIRTUAL_ENV,$HOME/.local/state/quickshell/.venv
env = XCURSOR_THEME,Bibata-Modern-Classic
env = XCURSOR_SIZE,24
env = QT_QPA_PLATFORMTHEME,kde
EOF

# -----------------------------------------------------------------------------
# Pacotes extras listados em pacotes_necessarios
# -----------------------------------------------------------------------------
RUN grep -v '^#' /pacotes_necessarios | grep -v '^$' | \
    xargs -r pacman -S --noconfirm --needed 2>/dev/null || true && \
    pacman -Scc --noconfirm

# -----------------------------------------------------------------------------
# Post-install service
# -----------------------------------------------------------------------------
RUN install -Dm755 post-install.sh /usr/bin/post-install.sh && \
    install -Dm644 post-install.service /usr/lib/systemd/system/post-install.service && \
    rm post-install.sh post-install.service

# -----------------------------------------------------------------------------
# Habilitar serviços
# -----------------------------------------------------------------------------
RUN systemctl enable NetworkManager && \
    systemctl enable sddm && \
    systemctl enable bluetooth && \
    systemctl enable post-install.service && \
    systemctl mask systemd-remount-fs.service && \
    rm -rf /var/roothome/.*

# -----------------------------------------------------------------------------
# Limpeza final
# -----------------------------------------------------------------------------
RUN rm -rf /var/cache/pacman/pkg/* \
           /var/log/* \
           /tmp/*

# Verificação final do bootc
RUN bootc container lint

# =============================================================================
# Estágio 3: Otimização com Chunkah (divide em layers OCI)
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
