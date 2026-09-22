#!/usr/bin/env bash
# =============================================================================
# lib/paths.sh — Única fuente de verdad de todas las rutas de Packbox.
# lib/paths.sh — Single source of truth for all Packbox paths.
#
# Ningún otro módulo debe declarar rutas. Todas viven aquí.
# No other module should declare paths. All live here.
# =============================================================================

# ─── Versión del proyecto ────────────────────────────────────────────────────
# ─── Project version ─────────────────────────────────────────────────────────
# Fuente única: src/internal/version/VERSION (el mismo archivo que embebe el
# paquete Go `internal/version`). No hardcodear la versión en otros módulos.
# Single source: src/internal/version/VERSION (the same file the Go package
# `internal/version` embeds). Do not hardcode the version elsewhere.
PACKBOX_VERSION="$(cat "${PACKBOX_ROOT:-.}/src/internal/version/VERSION" 2>/dev/null | tr -d '[:space:]')"
[[ -n "$PACKBOX_VERSION" ]] || PACKBOX_VERSION="0.2.0"

# ─── Directorio de instalación (oculto) ──────────────────────────────────────
# ─── Installation directory (hidden) ─────────────────────────────────────────
PACKBOX_INSTALL_DIR="$HOME/.packbox"
PACKBOX_BIN_DIR="$PACKBOX_INSTALL_DIR/bin"
PACKBOX_SRC_DIR="$PACKBOX_INSTALL_DIR/src"
PACKBOX_GO_DIR="$PACKBOX_INSTALL_DIR/go"
PACKBOX_GO_BIN="$PACKBOX_GO_DIR/bin"
PACKBOX_GO_PATH="$PACKBOX_INSTALL_DIR/go-path"

# ─── Datos de usuario ────────────────────────────────────────────────────────
# ─── User data ───────────────────────────────────────────────────────────────
PACKBOX_HOME="$HOME/.local/share/packbox"
PACKBOX_APPS_DIR="$PACKBOX_HOME/apps"
PACKBOX_STORE_DIR="$PACKBOX_HOME/store"
PACKBOX_MODS_DIR="$PACKBOX_HOME/mods"
PACKBOX_EXPORTS_DIR="$PACKBOX_HOME/exports"
PACKBOX_TMP_DIR="$PACKBOX_HOME/tmp"

# ─── Configuración ───────────────────────────────────────────────────────────
# ─── Configuration ───────────────────────────────────────────────────────────
PACKBOX_CONFIG_DIR="$HOME/.config/packbox"
PACKBOX_LANG_DIR="$PACKBOX_CONFIG_DIR/lang"

# ─── Integración con el escritorio ───────────────────────────────────────────
# ─── Desktop integration ─────────────────────────────────────────────────────
PACKBOX_DESKTOP_DIR="$HOME/.local/share/applications"
PACKBOX_ICONS_DIR="$HOME/.local/share/icons/hicolor"

# ─── Diario de instalación ───────────────────────────────────────────────────
# ─── Installation journal ────────────────────────────────────────────────────
PACKBOX_JOURNAL="$PACKBOX_INSTALL_DIR/.installed-journal"

# ─── Rutas legacy (para migración) ───────────────────────────────────────────
# ─── Legacy paths (for migration) ────────────────────────────────────────────
PACKBOX_OLD_DIR="$HOME/packbox"

# ─── Binarios (los ejecutables Go) ───────────────────────────────────────────
# ─── Binaries (the Go executables) ───────────────────────────────────────────
PACKBOX_BIN_PACK="$PACKBOX_BIN_DIR/packbox-pack"
PACKBOX_BIN_INSTALL="$PACKBOX_BIN_DIR/packbox-install"
PACKBOX_BIN_RUN="$PACKBOX_BIN_DIR/packbox-run"
PACKBOX_BIN_LIST="$PACKBOX_BIN_DIR/packbox-list"
PACKBOX_BIN_REMOVE="$PACKBOX_BIN_DIR/packbox-remove"
PACKBOX_BIN_GC="$PACKBOX_BIN_DIR/packbox-gc"
PACKBOX_BIN_VERIFY="$PACKBOX_BIN_DIR/packbox-verify"
PACKBOX_BIN_EXPORT="$PACKBOX_BIN_DIR/packbox-export"
PACKBOX_BIN_IMPORT="$PACKBOX_BIN_DIR/packbox-import"
PACKBOX_BIN_MODULE="$PACKBOX_BIN_DIR/packbox-module"
PACKBOX_BIN_DIAGNOSE="$PACKBOX_BIN_DIR/packbox-diagnose"
PACKBOX_BIN_UPDATE="$PACKBOX_BIN_DIR/packbox-update"
PACKBOX_BIN_SIGN="$PACKBOX_BIN_DIR/packbox-sign"
PACKBOX_BIN_FETCH="$PACKBOX_BIN_DIR/packbox-fetch"
PACKBOX_BIN_DEBUG="$PACKBOX_BIN_DIR/packbox-debug"