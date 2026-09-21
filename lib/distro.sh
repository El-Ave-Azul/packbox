#!/usr/bin/env bash
# =============================================================================
# lib/distro.sh — Detección de distro e instalación de paquetes del sistema.
# lib/distro.sh — Distro detection and system package installation.
#
# Asume / Assumes: ui.sh, paths.sh
# Provee / Provides: detect_distro, install_pkgs
# =============================================================================

# ─── Detección de distro ─────────────────────────────────────────────────────
# ─── Distro detection ────────────────────────────────────────────────────────
# detect_distro — lee /etc/os-release y setea DF + DISTRO_NAME.
# detect_distro — reads /etc/os-release and sets DF + DISTRO_NAME.
#
# DF ∈ {debian, fedora, arch, suse, unknown}
detect_distro() {
    DF="unknown"
    DISTRO_NAME="Unknown"
    [[ -f /etc/os-release ]] || return 0

    local os_id os_like
    os_id=$(awk -F= '/^ID=/{gsub(/"/,"",$2); print $2}' /etc/os-release | head -1)
    os_like=$(awk -F= '/^ID_LIKE=/{gsub(/"/,"",$2); print $2}' /etc/os-release | head -1)
    DISTRO_NAME=$(awk -F= '/^PRETTY_NAME=/{gsub(/"/,"",$2); print $2}' /etc/os-release | head -1)
    DISTRO_NAME="${DISTRO_NAME:-Unknown}"

    case "$os_id" in
        ubuntu|linuxmint|pop|elementary|zorin|kali|deepin|neon|debian|raspbian)
            DF="debian" ;;
        fedora|centos|rhel|rocky|alma|nobara)
            DF="fedora" ;;
        arch|manjaro|endeavouros|garuda|cachyos)
            DF="arch" ;;
        opensuse*|suse)
            DF="suse" ;;
        *)
            case "$os_like" in
                *debian*|*ubuntu*) DF="debian" ;;
                *fedora*)          DF="fedora" ;;
                *arch*)            DF="arch" ;;
                *)                 DF="unknown" ;;
            esac ;;
    esac
}

# ─── Instalación de paquetes ─────────────────────────────────────────────────
# ─── Package installation ────────────────────────────────────────────────────
# install_pkgs <pkg...> — instala paquetes usando el gestor de la distro.
# install_pkgs <pkg...> — installs packages via the distro's package manager.
#
# Requiere que $SUDO esté definida ("" si root, "sudo" si no).
# Requires $SUDO to be set ("" if root, "sudo" if not).
install_pkgs() {
    [[ $# -eq 0 ]] && return 0

    case "$DF" in
        debian)
            $SUDO apt-get update -qq 2>/dev/null || true
            $SUDO apt-get install -y -qq "$@" >/dev/null 2>&1
            ;;
        fedora)
            $SUDO dnf install -y -q "$@" >/dev/null 2>&1
            ;;
        arch)
            $SUDO pacman -Sy --noconfirm --needed "$@" >/dev/null 2>&1
            ;;
        suse)
            $SUDO zypper --non-interactive install "$@" >/dev/null 2>&1
            ;;
        *)
            warn "Unknown distro — cannot install packages"
            warn "Distro desconocida — no se pueden instalar paquetes"
            return 1
            ;;
    esac
}

# ─── Paquetes por defecto según distro ──────────────────────────────────────
# ─── Default packages per distro ────────────────────────────────────────────
# default_deps — imprime la lista de paquetes que necesitamos.
# default_deps — prints the list of packages we need.
default_deps() {
    case "$DF" in
        debian|fedora|arch|suse)
            echo "bubblewrap binutils jq bc curl tar" ;;
        *)
            echo "bubblewrap curl tar" ;;
    esac
}