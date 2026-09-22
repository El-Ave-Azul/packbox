#!/usr/bin/env bash
# =============================================================================
# lib/export.sh — Exportar apps a .pbox.
# lib/export.sh — Export apps to .pbox.
#
# Asume / Assumes: ui.sh, paths.sh, common.sh
# Provee / Provides: export_app
# =============================================================================

# ─── Exportar app ───────────────────────────────────────────────────────────
# ─── Export app ─────────────────────────────────────────────────────────────
export_app() {
    hdr "$(t L_4_EXPORT)"

    if [[ ! -x "$PACKBOX_BIN_EXPORT" ]]; then
        warn "packbox-export not found / no encontrado"
        read -rp "  ENTER..."
        return 1
    fi

    if [[ ! -d "$PACKBOX_APPS_DIR" || -z "$(ls -A "$PACKBOX_APPS_DIR" 2>/dev/null)" ]]; then
        warn "$(t L_NO_RESULTS)"
        read -rp "  ENTER..."
        return 1
    fi

    # ─── Listar apps ────────────────────────────────────────────────────────
    # ─── List apps ──────────────────────────────────────────────────────────
    local apps=() i=1
    while IFS= read -r ad; do
        [[ -d "$ad" ]] || continue
        local aid
        aid=$(basename "$ad")
        local ver="?" tags=""
        if [[ -f "$ad/manifest.json" ]]; then
            ver=$(jq -r '.version // "?"' "$ad/manifest.json" 2>/dev/null)
            local po bu
            po=$(jq -r '.portable // false' "$ad/manifest.json" 2>/dev/null)
            bu=$(jq -r '.bundle // false' "$ad/manifest.json" 2>/dev/null)
            [[ "$bu" == "true" ]] && tags+=" [$(t L_BUNDLE)]"
            [[ "$po" == "true" && "$bu" != "true" ]] && tags+=" [$(t L_PORTABLE)]"
        fi
        printf "  ${C}%3d${N}) %-30s ${DM}v%-8s${N}%s\n" "$i" "$aid" "$ver" "$tags"
        apps+=("$aid")
        i=$((i + 1))
    done < <(find "$PACKBOX_APPS_DIR" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | sort)

    echo ""
    echo -en "  ${BD}> 1-${#apps[@]}, q: ${N}"
    local c
    read -r c
    [[ "$c" == "q" || -z "$c" ]] && return 1

    if [[ ! "$c" =~ ^[0-9]+$ || "$c" -lt 1 || "$c" -gt "${#apps[@]}" ]]; then
        warn "$(t L_INVALID)"
        read -rp "  ENTER..."
        return 1
    fi

    local tgt="${apps[$((c - 1))]}"
    echo ""
    local signflag=""
    if [[ -f "$HOME/.config/packbox/signing.key" ]]; then
        ask_yn "$(_tt L_SIGN_Q "¿Firmar el paquete?")" "n" && signflag="--sign"
    else
        det "$(_tt L_NO_KEY "sin clave de firma (packbox-sign keygen)")"
    fi
    info "Exporting $tgt..."
    if "$PACKBOX_BIN_EXPORT" $signflag app "$tgt"; then
        local ef="$PACKBOX_EXPORTS_DIR/$tgt.pbox"
        if [[ -f "$ef" ]]; then
            box_ok "$tgt $(t L_4_EXPORT)"
            det "File: $ef"
            det "Size: $(du -h "$ef" 2>/dev/null | cut -f1)"
            det "Compression: zstd -19 / xz -9e / gzip"
            [[ -f "$ef.sig" ]] && det "Signature: $ef.sig"
        fi
    else
        { fail "Export failed / Export falló"; return 1; }
    fi
    read -rp "  ENTER..."
}