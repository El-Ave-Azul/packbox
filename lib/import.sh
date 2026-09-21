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

    # Busca .pbox en exports/, Descargas/Downloads, tu HOME, el directorio
    # actual y medios extraíbles (USB) — así no hay que teclear rutas.
    # Look for .pbox in exports/, Downloads, your HOME, the current dir and
    # removable media (USB) — no path typing needed.
    local pbs=() f d u="${USER:-$(id -un)}"
    local dirs=("$PACKBOX_EXPORTS_DIR" "$HOME/Descargas" "$HOME/Downloads" "$HOME" "$PWD")
    for d in /run/media/"$u"/* /media/"$u"/* /mnt/*; do
        [[ -d "$d" ]] && dirs+=("$d")
    done
    for d in "${dirs[@]}"; do
        [[ -d "$d" ]] || continue
        while IFS= read -r f; do pbs+=("$f"); done \
            < <(find "$d" -maxdepth 1 -type f -name '*.pbox' 2>/dev/null)
    done
    # Deduplica preservando el orden. / Deduplicate preserving order.
    if (( ${#pbs[@]} > 0 )); then
        local uniq=() x seen
        for f in "${pbs[@]}"; do
            seen=0
            for x in "${uniq[@]}"; do [[ "$x" == "$f" ]] && { seen=1; break; }; done
            (( seen == 0 )) && uniq+=("$f")
        done
        pbs=("${uniq[@]}")
    fi

    # ¿Hay selector gráfico? / Is a GUI picker available?
    local picker=""
    command -v zenity  >/dev/null && picker="zenity"
    command -v kdialog >/dev/null && picker="kdialog"

    local pp=""
    echo -e "  ${BD}$(_tt L_AVAILABLE_PBOX "Paquetes .pbox disponibles")${N}"
    if (( ${#pbs[@]} > 0 )); then
        local i=1 sz sign loc
        for f in "${pbs[@]}"; do
            sz=$(du -h "$f" 2>/dev/null | cut -f1)
            sign=""
            [[ -f "$f.sig" ]] && sign=" ${G}$(_tt L_SIGNED "firmado")${N}"
            loc=$(dirname "$f"); loc="${loc/#$HOME/~}"
            printf "  ${C}%3d${N}) %-32s ${DM}%8s  %s${N}%s\n" \
                "$i" "$(basename "$f")" "$sz" "$loc" "$sign"
            i=$((i + 1))
        done
    else
        echo -e "  ${DM}$(_tt L_NONE "ninguno")${N}"
    fi
    echo ""
    local hint="$(_tt L_NUMBER_OR_PATH "número o ruta")"
    [[ -n "$picker" ]] && hint="$hint, b $(_tt L_BROWSE "buscar")"
    local rng="-"; (( ${#pbs[@]} > 0 )) && rng="1-${#pbs[@]}"
    echo -en "  ${BD}> $hint [$rng, q]: ${N}"
    local sel
    read -r sel
    [[ -z "$sel" || "$sel" == "q" ]] && return 1
    if [[ "$sel" == "b" && -n "$picker" ]]; then
        if [[ "$picker" == "zenity" ]]; then
            pp=$(zenity --file-selection --title="$(_tt L_BROWSE "Buscar .pbox")" \
                --file-filter='Packbox (*.pbox) | *.pbox' 2>/dev/null)
        else
            pp=$(kdialog --getopenfilename "$HOME" '*.pbox' 2>/dev/null)
        fi
    elif [[ "$sel" =~ ^[0-9]+$ ]] && (( sel >= 1 && sel <= ${#pbs[@]} )); then
        pp="${pbs[$((sel - 1))]}"
    else
        pp="${sel/#\~/$HOME}"
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