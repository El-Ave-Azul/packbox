#!/usr/bin/env bash
# =============================================================================
# lib/desktop.sh — Entradas de menú .desktop (wrapper delgada).
# lib/desktop.sh — .desktop menu entries (thin wrapper).
#
# Asume / Assumes: ui.sh, paths.sh, common.sh
# Provee / Provides: create_desktop_entry, remove_desktop_entry
#
# La implementación vive en el paquete Go internal/desktop y se expone a
# través del binario `packbox-install` (--desktop / --remove-desktop). Este
# módulo solo la invoca, para que exista una sola fuente de verdad.
# The implementation lives in the Go package internal/desktop and is exposed
# through the `packbox-install` binary (--desktop / --remove-desktop). This
# module only invokes it, so there is a single source of truth.
# =============================================================================

# ─── Crear entrada de menú ──────────────────────────────────────────────────
# ─── Create menu entry ──────────────────────────────────────────────────────
create_desktop_entry() {
    local app_id="${1:-}"
    [[ -z "$app_id" ]] && return 1
    if [[ ! -x "$PACKBOX_BIN_INSTALL" ]]; then
        warn "packbox-install not found / no encontrado"
        return 1
    fi
    "$PACKBOX_BIN_INSTALL" --desktop "$app_id"
}

# ─── Eliminar entrada de menú ───────────────────────────────────────────────
# ─── Remove menu entry ──────────────────────────────────────────────────────
remove_desktop_entry() {
    local app_id="${1:-}"
    [[ -z "$app_id" ]] && return 1
    if [[ ! -x "$PACKBOX_BIN_INSTALL" ]]; then
        return 1
    fi
    "$PACKBOX_BIN_INSTALL" --remove-desktop "$app_id"
}
