#!/usr/bin/env bash
# =============================================================================
# lib/main-packager.sh — Menú del empaquetador.
# lib/main-packager.sh — Packager menu.
#
# Asume / Assumes: todo lo cargado por bootstrap.
# Provee / Provides: main_packager, show_banner_packager, change_language
# =============================================================================

main_packager() {
    case "${1:-}" in
        --lang|-l)
            select_language --force
            install_lang_files
            load_lang
            ok "$(_tt L_LANG_CHANGED "Idioma cambiado a"): $(t L_LANG_NAME)"
            return 0
            ;;
        --help|-h)
            cat <<'HELP'
Packbox Packager / Empaquetador Packbox

Uso / Usage:
  ./packbox-packager.sh [opciones]

Opciones / Options:
  -l, --lang        Cambiar idioma / Change language
  -h, --help        Esta ayuda / This help
HELP
            return 0
            ;;
    esac

    select_language
    install_lang_files
    load_lang

    if [[ ! -x "$PACKBOX_BIN_PACK" ]]; then
        show_banner_packager
        warn "Binaries not found in / Binarios no encontrados en: $PACKBOX_BIN_DIR"
        echo ""
        if ask_yn "$(_tt L_RUN_INSTALLER_NOW "¿Ejecutar el instalador ahora?")" "s"; then
            bash "$PACKBOX_ROOT/packbox-install.sh"
        else
            err "Packbox must be installed / Packbox debe estar instalado"
        fi
    fi

    while true; do
        show_banner_packager
        echo -e "  ${BD}$(t L_WHAT_DO)${N}"
        echo ""
        echo -e "  ${C}1${N}  $(t L_1_PACK)"
        echo -e "  ${C}2${N}  $(t L_2_LIST)"
        echo -e "  ${C}3${N}  $(t L_3_GC)"
        echo -e "  ${C}4${N}  ${BD}$(t L_4_EXPORT)${N}"
        echo -e "  ${C}5${N}  ${BD}$(t L_5_IMPORT)${N}"
        echo -e "  ${C}6${N}  ${R}${BD}$(t L_6_UNINSTALL)${N}"
        echo -e "  ${C}7${N}  $(_tt L_7_LANG "Cambiar idioma") ${DM}($(t L_LANG_NAME))${N}"
        echo -e "  ${C}0${N}  $(t L_0_EXIT)"
        echo ""
        echo -e "  ${DM}${HR_T}${N}"
        echo ""
        echo -en "  ${BD}> $(t L_OPTION) [0-7]: ${N}"
        local opt
        read -r opt
        case "$opt" in
            1) menu_pack ;;
            2) run_list ;;
            3) run_gc ;;
            4) export_app ;;
            5) import_app ;;
            6) uninstall_apps ;;
            7) change_language ;;
            0|q|Q)
                echo ""
                echo -e "  ${DM}Bye / Adiós${N}"
                echo ""
                exit 0
                ;;
            *) warn "$(t L_INVALID): $opt"; sleep 1 ;;
        esac
    done
}

# ─── Banner ─────────────────────────────────────────────────────────────────
show_banner_packager() {
    clear
    echo -e "${BD}${C}"
    echo "  ═══════════════════════════════════════════════════════════════"
    echo "   $(t L_PACKAGER_TITLE)"
    echo "   v${PACKBOX_VERSION} · i18n (9) · Bundles · Desktop · Network opt-in"
    echo "  ═══════════════════════════════════════════════════════════════"
    echo -e "${N}"
}

# ─── Cambiar idioma ─────────────────────────────────────────────────────────
change_language() {
    local prev="$_PB_LANG"
    select_language --force
    install_lang_files
    load_lang
    if [[ "$_PB_LANG" == "$prev" ]]; then
        ok "$(_tt L_LANG_UNCHANGED "Idioma sin cambios"): $(t L_LANG_NAME)"
    else
        ok "$(_tt L_LANG_CHANGED "Idioma cambiado a"): $(t L_LANG_NAME)"
    fi
    sleep 1
}

# ─── Opción 1: empaquetar ───────────────────────────────────────────────────
menu_pack() {
    detect_all
    echo ""
    info "$(t L_DETECTED): ${#APPS_SORTED[@]}"
    local gc=0 cc=0 bc=0 b
    for b in "${APPS_SORTED[@]}"; do
        local inf="${APPS_MAP[$b]}" g bd
        g=$(fld "$inf" 7)
        bd=$(fld "$inf" 9)
        [[ -n "$bd" ]] && bc=$((bc + 1))
        if [[ "$g" == "GUI" ]]; then
            gc=$((gc + 1))
        else
            cc=$((cc + 1))
        fi
    done
    echo -e "  ${DM}${ARROW} GUI: $gc | CLI: $cc | $(t L_BUNDLE): $bc${N}"
    echo ""
    while true; do
        if ! select_top 15 0; then
            break
        fi
        show_details
        if ! ask_yn "$(t L_PACKING)? $(t L_CONFIRM)" "s"; then
            if ask_yn "$(t L_ANOTHER)" "n"; then
                continue
            fi
            break
        fi
        configure_pack
        echo ""
        echo -e "  ${BD}$(t L_APP_ID): $CURRENT_APP_ID  |  $(t L_VERSION): $CURRENT_VERSION${N}"
        echo -e "  ${BD}$(_tt L_NETWORK "Red"): $CURRENT_NETWORK${N}"
        ask_yn "$(t L_CONFIRM)" "s" || continue
        package_real

        # Ofrecer export
        # Offer export
        if [[ -d "$PACKBOX_APPS_DIR/$CURRENT_APP_ID" ]]; then
            echo ""
            if ask_yn "$(t L_4_EXPORT)? [s/N] " "n"; then
                if "$PACKBOX_BIN_EXPORT" app "$CURRENT_APP_ID"; then
                    local exp="$PACKBOX_EXPORTS_DIR/$CURRENT_APP_ID.pbox"
                    ok "OK: $exp"
                    [[ -f "$exp" ]] && \
                        det "Size: $(du -h "$exp" 2>/dev/null | cut -f1)"
                fi
            fi
        fi
        echo ""
        ask_yn "$(t L_ANOTHER)" "n" || break
    done
}

# ─── Opción 2: listar ───────────────────────────────────────────────────────
run_list() {
    if [[ -x "$PACKBOX_BIN_LIST" ]]; then
        "$PACKBOX_BIN_LIST"
    else
        warn "packbox-list not found / no encontrado"
    fi
    read -rp "  ENTER..."
}

# ─── Opción 3: GC ───────────────────────────────────────────────────────────
run_gc() {
    if [[ -x "$PACKBOX_BIN_GC" ]]; then
        "$PACKBOX_BIN_GC"
    else
        warn "packbox-gc not found / no encontrado"
    fi
    read -rp "  ENTER..."
}

# ─── Opción 6: desinstalar apps ─────────────────────────────────────────────
uninstall_apps() {
    hdr "$(t L_6_UNINSTALL)"
    [[ ! -x "$PACKBOX_BIN_REMOVE" ]] && err "packbox-remove not found"

    if [[ ! -d "$PACKBOX_APPS_DIR" || -z "$(ls -A "$PACKBOX_APPS_DIR" 2>/dev/null)" ]]; then
        warn "$(t L_NO_RESULTS)"
        read -rp "  ENTER..."
        return 1
    fi

    local apps=() sizes=() tot=0 totapar=0 i=1
    # Tamaños reales (hardlinks compartidos contados una vez) desde packbox-list.
    # Real sizes (hardlinks shared counted once) from packbox-list.
    while IFS=$'\t' read -r aid ver real apar tags; do
        [[ -z "$aid" ]] && continue
        [[ "$real" =~ ^[0-9]+$ ]] || real=0
        [[ "$apar" =~ ^[0-9]+$ ]] || apar=0
        local pct=0
        (( apar > 0 )) && pct=$(( (apar - real) * 100 / apar ))
        printf "  ${C}%3d${N}) %-26s ${DM}v%-8s${N} ${BD}real %9s${N} ${DM}suma %-9s -%s%%${N} %s\n" \
            "$i" "$aid" "$ver" "$(hs "$real")" "$(hs "$apar")" "$pct" "$tags"
        apps+=("$aid")
        sizes+=("$real")
        tot=$((tot + real))
        totapar=$((totapar + apar))
        i=$((i + 1))
    done < <("$PACKBOX_BIN_LIST" --tsv 2>/dev/null)

    echo ""
    local tpct=0
    (( totapar > 0 )) && tpct=$(( (totapar - tot) * 100 / totapar ))
    echo -e "  ${BD}$(t L_TOTAL): real $(hs "$tot") · suma $(hs "$totapar") · ahorro ${tpct}% — ${#apps[@]} apps${N}"
    echo -e "  ${DM}One '3' · many '1 3 5' · range '1-4' · all · q${N}"
    echo -en "  ${BD}> ${N}"
    local sel
    read -r sel
    [[ "$sel" == "q" || -z "$sel" ]] && return 1

    local idxs=()
    if [[ "$sel" == "all" || "$sel" == "a" ]]; then
        local k
        for k in "${!apps[@]}"; do idxs+=("$k"); done
    else
        local exp="" tok
        for tok in $sel; do
            if [[ "$tok" =~ ^([0-9]+)-([0-9]+)$ ]]; then
                local st="${BASH_REMATCH[1]}" en="${BASH_REMATCH[2]}"
                [[ "$st" -gt "$en" ]] && { local tmp=$st; st=$en; en=$tmp; }
                local n
                for ((n=st; n<=en; n++)); do exp+="$n "; done
            elif [[ "$tok" =~ ^[0-9]+$ ]]; then
                exp+="$tok "
            fi
        done
        for tok in $exp; do
            [[ "$tok" -ge 1 && "$tok" -le "${#apps[@]}" ]] && idxs+=("$((tok - 1))")
        done
    fi
    [[ ${#idxs[@]} -eq 0 ]] && { warn "$(t L_NO_SELECTION)"; return 1; }

    echo ""
    local stot=0 idx
    for idx in "${idxs[@]}"; do
        stot=$((stot + ${sizes[$idx]}))
        printf "  ${R}${XMK}${N}  %-35s ${DM}%9s${N}\n" \
            "${apps[$idx]}" "$(hs "${sizes[$idx]}")"
    done
    echo -e "  ${BD}$(t L_TOTAL): $(hs "$stot")${N}"
    echo ""
    ask_yn "$(t L_CONFIRM)" "n" || { warn "$(t L_CANCEL)"; return 1; }
    echo ""
    local rem=0 fail=0
    for idx in "${idxs[@]}"; do
        local aid="${apps[$idx]}"
        echo -e "  ${B}${BULLET}${N}  $aid..."
        if "$PACKBOX_BIN_REMOVE" "$aid" >/dev/null 2>&1; then
            ok "$aid $(t L_REMOVED)"
            rem=$((rem + 1))
        else
            warn "$aid $(t L_FAILED)"
            fail=$((fail + 1))
        fi
    done
    echo ""
    box_ok "OK: $rem | FAIL: $fail"
    if [[ $rem -gt 0 ]]; then
        echo ""
        if ask_yn "GC? [S/n] " "s"; then
            echo ""
            "$PACKBOX_BIN_GC"
        fi
    fi
    read -rp "  ENTER..."
}