#!/bin/bash
# =============================================================================
# post-install.sh — Primeiro boot do archlinux-bootc (Hyprland + II)
# Executado como root pelo post-install.service.
#
# O que faz:
#   1. Aguarda rede
#   2. Compila e instala os pacotes AUR do illogical-impulse via makepkg
#      (quickshell-git pinado, matugen, bibata-cursor, microtex)
#   3. Roda o setup do dots-hyprland como o usuário padrão
#   4. Configura Flatpak + Flathub
#   5. Compila o módulo NVIDIA via DKMS
# =============================================================================
set -euo pipefail

LOG=/var/log/post-install.log
exec > >(tee -a "$LOG") 2>&1
echo "[$(date '+%F %T')] Iniciando pós-instalação (Hyprland + Illogical Impulse)..."

# ---------------------------------------------------------------------------
# Detectar usuário padrão (primeiro usuário real, não root)
# ---------------------------------------------------------------------------
DEFAULT_USER=$(getent passwd | awk -F: '$3 >= 1000 && $3 < 65534 {print $1; exit}')
if [[ -z "$DEFAULT_USER" ]]; then
    echo "[WARN] Nenhum usuário comum encontrado. Pulando setup do II."
    DEFAULT_USER=""
fi
echo "[INFO] Usuário detectado: ${DEFAULT_USER:-nenhum}"

# ---------------------------------------------------------------------------
# 1. Aguardar rede
# ---------------------------------------------------------------------------
echo "[INFO] Aguardando NetworkManager..."
until nmcli -t -f STATE general status 2>/dev/null | grep -q "^connected"; do
    sleep 3
done
echo "[INFO] Rede disponível."

# ---------------------------------------------------------------------------
# 2. DKMS — compilar módulo NVIDIA com kernel real
# ---------------------------------------------------------------------------
KVER="$(uname -r)"
echo "[INFO] Kernel em execução: $KVER"
if ! lsmod | grep -q '^nvidia '; then
    echo "[INFO] Executando dkms autoinstall para kernel $KVER..."
    dkms autoinstall -k "$KVER" && \
        modprobe nvidia nvidia_modeset nvidia_uvm nvidia_drm || \
        echo "[WARN] dkms autoinstall falhou — verifique 'dkms status'."
else
    echo "[INFO] Módulo NVIDIA já carregado."
fi

# ---------------------------------------------------------------------------
# 3. Instalar pacotes AUR do illogical-impulse via makepkg
#    Feito como usuário comum (makepkg não roda como root)
# ---------------------------------------------------------------------------
if [[ -n "$DEFAULT_USER" ]]; then
    USER_HOME=$(getent passwd "$DEFAULT_USER" | cut -d: -f6)

    # Garantir que o usuário tenha sudo sem senha temporariamente para makepkg
    echo "$DEFAULT_USER ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/post-install-tmp

    run_as_user() {
        sudo -u "$DEFAULT_USER" env HOME="$USER_HOME" "$@"
    }

    # Instalar yay (AUR helper) para build dos pacotes II
    if ! command -v yay &>/dev/null; then
        echo "[INFO] Instalando yay..."
        run_as_user git clone --depth=1 https://aur.archlinux.org/yay-bin.git /tmp/yay-bin
        run_as_user bash -c "cd /tmp/yay-bin && makepkg -si --noconfirm"
        rm -rf /tmp/yay-bin
    fi

    echo "[INFO] Instalando pacotes AUR do illogical-impulse..."
    # Quickshell pinado (versão específica requerida pelo II)
    run_as_user yay -S --noconfirm --needed \
        illogical-impulse-quickshell-git \
        illogical-impulse-bibata-modern-classic-bin \
        illogical-impulse-microtex-git \
        matugen \
        adw-gtk-theme || \
        echo "[WARN] Alguns pacotes AUR falharam — verifique manualmente."

    # ---------------------------------------------------------------------------
    # 4. Clonar dots-hyprland e rodar setup --core como usuário
    # ---------------------------------------------------------------------------
    echo "[INFO] Clonando dots-hyprland..."
    DOTS_DIR="$USER_HOME/.cache/dots-hyprland"

    if [[ ! -d "$DOTS_DIR" ]]; then
        run_as_user git clone --recurse-submodules \
            https://github.com/end-4/dots-hyprland "$DOTS_DIR"
    else
        run_as_user bash -c "cd '$DOTS_DIR' && git pull && git submodule update --init --recursive"
    fi

    echo "[INFO] Executando setup --core do illogical-impulse..."
    # --core instala apenas Hyprland + Quickshell, sem extras como GNOME keyring
    run_as_user bash -c "cd '$DOTS_DIR' && ./setup install --core --noconfirm" || \
        echo "[WARN] setup install retornou erro — verifique $LOG"

    # Remover sudoers temporário
    rm -f /etc/sudoers.d/post-install-tmp
fi

# ---------------------------------------------------------------------------
# 5. Flatpak — Flathub + apps base
# ---------------------------------------------------------------------------
echo "[INFO] Configurando Flatpak..."
if flatpak remotes 2>/dev/null | grep -q '^fedora'; then
    flatpak remote-delete --system fedora || true
fi
flatpak remote-add --system --if-not-exists flathub \
    https://flathub.org/repo/flathub.flatpakrepo

flatpak install --system -y --noninteractive flathub \
    com.github.tchx84.Flatseal \
    org.telegram.desktop \
    org.mozilla.firefox \
    com.discordapp.Discord \
    com.spotify.Client || \
    echo "[WARN] Alguns Flatpaks falharam."

# ---------------------------------------------------------------------------
# Auto-desabilitar após execução
# ---------------------------------------------------------------------------
systemctl disable post-install.service 2>/dev/null || true
echo "[$(date '+%F %T')] Pós-instalação concluída. Log: $LOG"
