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

    # Lista los .pbox de exports/ para elegir por número (o pegar una ruta).
    # List the .pbox files in exports/ to pick by number (or paste a path).
    local pbs=() f
    while IFS= read -r f; do pbs+=("$f"); done \
        < <(find "$PACKBOX_EXPORTS_DIR" -maxdepth 1 -type f -name '*.pbox' 2>/dev/null | sort)

    local pp=""
    if (( ${#pbs[@]} > 0 )); then
        echo -e "  ${BD}$(_tt L_AVAILABLE_PBOX "Paquetes .pbox disponibles")${N}"
        local i=1 sz sign
        for f in "${pbs[@]}"; do
            sz=$(du -h "$f" 2>/dev/null | cut -f1)
            sign=""
            [[ -f "$f.sig" ]] && sign=" ${G}$(_tt L_SIGNED "firmado")${N}"
            printf "  ${C}%3d${N}) %-38s ${DM}%8s${N}%s\n" "$i" "$(basename "$f")" "$sz" "$sign"
            i=$((i + 1))
        done
        echo ""
        echo -en "  ${BD}> $(_tt L_NUMBER_OR_PATH "número o ruta") [1-${#pbs[@]}, q]: ${N}"
        local sel
        read -r sel
        [[ -z "$sel" || "$sel" == "q" ]] && return 1
        if [[ "$sel" =~ ^[0-9]+$ ]] && (( sel >= 1 && sel <= ${#pbs[@]} )); then
            pp="${pbs[$((sel - 1))]}"
        else
            pp="${sel/#\~/$HOME}"
        fi
    else
        echo -en "  ${BD}Path .pbox: ${N}"
        read -r pp
        pp="${pp/#\~/$HOME}"
    fi

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

    # ─── Recrear entrada de menú (GUI y CLI) ────────────────────────────────
    # ─── Recreate menu entry (both GUI and CLI) ─────────────────────────────
    if [[ -d "$PACKBOX_APPS_DIR/$an" ]]; then
        echo ""
        if ask_yn "$(t L_CREATE_DESKTOP)" "s"; then
            create_desktop_entry "$an"
        fi
    fi

    ask_yn "$(t L_EXEC_NOW)" "n" && { echo ""; "$PACKBOX_BIN_RUN" "$an"; }
    read -rp "  ENTER..."
}