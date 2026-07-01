#!/bin/bash
# =============================================================================
# post-install.sh — First boot setup (archlinux-bootc / KDE Plasma)
# Installed at /usr/bin/post-install.sh by the Containerfile.
# Runs as root via post-install.service (system service, not user).
# =============================================================================
set -euo pipefail

LOG=/var/log/post-install.log
exec > >(tee -a "$LOG") 2>&1
echo "[$(date '+%F %T')] Starting post-install..."

# ---------------------------------------------------------------------------
# 1. Wait for network
# ---------------------------------------------------------------------------
echo "[INFO] Waiting for NetworkManager..."
until nmcli -t -f STATE general status 2>/dev/null | grep -q "^connected"; do
    sleep 3
done
echo "[INFO] Network available."

# ---------------------------------------------------------------------------
# 2. DKMS — compile NVIDIA module against the real running kernel
#    Cannot be done inside the OCI build container (uname -r returns the
#    GitHub Actions runner kernel, not the Arch kernel installed in the image)
# ---------------------------------------------------------------------------
KVER="$(uname -r)"
echo "[INFO] Running kernel: $KVER"

if ! lsmod | grep -q '^nvidia '; then
    echo "[INFO] Running dkms autoinstall for $KVER..."
    dkms autoinstall -k "$KVER" && \
        modprobe nvidia nvidia_modeset nvidia_uvm nvidia_drm || \
        echo "[WARN] dkms autoinstall failed — check 'dkms status'."
else
    echo "[INFO] NVIDIA module already loaded."
fi

# ---------------------------------------------------------------------------
# 3. Flatpak — ensure Flathub and install base apps
# ---------------------------------------------------------------------------
echo "[INFO] Configuring Flatpak..."

if flatpak remotes 2>/dev/null | grep -q '^fedora'; then
    flatpak remote-delete --system fedora || true
fi

flatpak remote-add --system --if-not-exists flathub \
    https://flathub.org/repo/flathub.flatpakrepo

echo "[INFO] Installing Flatpaks..."
flatpak install --system -y --noninteractive flathub \
    org.gtk.Gtk3theme.Breeze \
    com.github.tchx84.Flatseal \
    org.telegram.desktop \
    org.mozilla.firefox \
    com.discordapp.Discord \
    com.spotify.Client \
    org.remmina.Remmina \
    org.kde.kalk \
    org.kde.isoimagewriter || \
    echo "[WARN] Some Flatpaks failed — install manually if needed."

# ---------------------------------------------------------------------------
# 4. Disable this service after successful first run
# ---------------------------------------------------------------------------
systemctl disable post-install.service 2>/dev/null || true
echo "[$(date '+%F %T')] Post-install complete. Log: $LOG"
