#!/usr/bin/env bash
# =============================================================================
# lib/import.sh — Importar apps desde .pbox.
# lib/import.sh — Import apps from .pbox.
#
# Asume / Assumes: ui.sh, paths.sh, common.sh, desktop.sh
# Provee / Provides: import_app
# =============================================================================

# ─── Importar app ───────────────────────────────────────────────────────────
# ─── Import app ─────────────────────────────────────────────────────────────
import_app() {
    hdr "$(t L_5_IMPORT)"

    if [[ ! -x "$PACKBOX_BIN_IMPORT" ]]; then
        warn "packbox-import not found / no encontrado"
        read -rp "  ENTER..."
        return 1
    fi

    echo -en "  ${BD}Path .pbox: ${N}"
    local pp
    read -r pp
    pp="${pp/#\~/$HOME}"

    if [[ -z "$pp" || ! -f "$pp" ]]; then
        warn "$(t L_DOES_NOT_EXIST)"
        read -rp "  ENTER..."
        return 1
    fi

    info "Importing / Importando..."
    local out
    out=$("$PACKBOX_BIN_IMPORT" app "$pp" 2>&1)
    echo "$out"

    # Extraer el nombre del output "imported: <name>" o "[ok] importado: <name>"
    # Extract name from "imported: <name>" or "[ok] importado: <name>"
    local an
    an=$(echo "$out" | grep -oE 'imported: \S+|importado: \S+' | head -1 | awk '{print $NF}')
    [[ -z "$an" ]] && an=$(basename "$pp" .pbox)

    box_ok "$an $(t L_INSTALLED)"

    # ─── Recrear entrada de menú si es GUI ──────────────────────────────────
    # ─── Recreate menu entry if GUI ─────────────────────────────────────────
    if [[ -d "$PACKBOX_APPS_DIR/$an" ]]; then
        local gui
        gui=$(jq -r '.gui // false' "$PACKBOX_APPS_DIR/$an/manifest.json" 2>/dev/null)
        if [[ "$gui" == "true" ]]; then
            echo ""
            if ask_yn "$(t L_CREATE_DESKTOP)" "s"; then
                create_desktop_entry "$an"
            fi
        fi
    fi

    ask_yn "$(t L_EXEC_NOW)" "n" && { echo ""; "$PACKBOX_BIN_RUN" "$an"; }
    read -rp "  ENTER..."
}