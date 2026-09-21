#!/usr/bin/env bash
# =============================================================================
# lib/pack.sh — Empaquetado de apps.
# lib/pack.sh — App packaging.
#
# Asume / Assumes: ui.sh, paths.sh, common.sh, journal.sh, detect.sh, desktop.sh
# Provee / Provides: invoke_pack, launcher_simple, package_real,
#                    pack_normal, pack_portable, pack_bundle, pack_module,
#                    is_universal, get_libs, maybe_desktop
# =============================================================================

# ─── Librerías universales ──────────────────────────────────────────────────
# ─── Universal libraries ────────────────────────────────────────────────────
# -g: ver la nota en lib/detect.sh (sourceado dentro de _pb_bootstrap).
# -g: see the note in lib/detect.sh (sourced inside _pb_bootstrap).
declare -ga UNIVERSAL=(
    "libc.so.6" "libm.so.6" "libdl.so.2" "libpthread.so.0"
    "librt.so.1" "libresolv.so.2" "libutil.so.1" "libnsl.so.1"
    "libcrypt.so.1" "libz.so.1"
    "ld-linux-x86-64.so.2" "ld-linux.so.2"
    "ld-linux-aarch64.so.1" "ld-linux-armhf.so.3"
)

# ─── ¿Lib universal? ────────────────────────────────────────────────────────
# ─── Is universal lib? ──────────────────────────────────────────────────────
is_universal() {
    local l="$1" u
    for u in "${UNIVERSAL[@]}"; do [[ "$l" == "$u" ]] && return 0; done
    return 1
}

# ─── Extraer libs de un binario ─────────────────────────────────────────────
# ─── Extract libs from a binary ─────────────────────────────────────────────
# get_libs <bin> — imprime "lib|path" por cada dependencia.
# get_libs <bin> — prints "lib|path" per dependency.
get_libs() {
    local o
    o=$(ldd "$1" 2>/dev/null || true)
    while IFS= read -r line; do
        local lib p
        lib=$(echo "$line" | awk '{print $1}')
        p=$(echo "$line" | awk '{print $3}')
        [[ -z "$lib" || "$lib" == "linux-vdso"* ]] && continue
        [[ -z "$p" || ! -f "$p" ]] && continue
        echo "$lib|$p"
    done < <(echo "$o" | grep "=>")
}

# ─── Invocación de packbox-pack ─────────────────────────────────────────────
# ─── packbox-pack invocation ────────────────────────────────────────────────
invoke_pack() {
    local wd="$1" aid="$2" ep="$3"
    local gf="false"
    [[ "$CURRENT_IS_GUI" == "GUI" ]] && gf="true"
    local nf="false"
    [[ "$CURRENT_NETWORK" == "true" ]] && nf="true"
    local args=(--name "$aid" --version "$CURRENT_VERSION" \
        --description "$CURRENT_DESC" --entrypoint "$ep" \
        --gui="$gf" --network="$nf" --toolkit "$CURRENT_TOOLKIT")
    # Celdas (módulos) referenciadas, si las hay. / Referenced cells, if any.
    [[ -n "${CURRENT_MODS:-}" ]] && args+=(--mods "$CURRENT_MODS")
    "$PACKBOX_BIN_PACK" "${args[@]}" "$wd"
}

# ─── Generar launcher.sh simple ─────────────────────────────────────────────
# ─── Generate simple launcher.sh ────────────────────────────────────────────
launcher_simple() {
    local dest="$1" bn="$2"
    cat > "$dest" <<LAUNCHER_EOF
#!/usr/bin/env bash
SCRIPT_DIR="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="\$(dirname "\$SCRIPT_DIR")"
[[ -d "\$APP_DIR/lib" ]] && export LD_LIBRARY_PATH="\$APP_DIR/lib:\${LD_LIBRARY_PATH:-}"
[[ -d "\$APP_DIR/bundle" ]] && export LD_LIBRARY_PATH="\$APP_DIR/bundle:\$APP_DIR/bundle/lib:\${LD_LIBRARY_PATH:-}"
[[ -d "\$APP_DIR/share" ]] && export XDG_DATA_DIRS="\${XDG_DATA_DIRS:-/usr/local/share:/usr/share}:\$APP_DIR/share"
exec "\$SCRIPT_DIR/$bn" "\$@"
LAUNCHER_EOF
    chmod +x "$dest"
}

# ─── Despacho de modo ───────────────────────────────────────────────────────
# ─── Mode dispatch ──────────────────────────────────────────────────────────
package_real() {
    case "$CURRENT_PACK_MODE" in
        1) pack_normal ;;
        2) pack_portable ;;
        3) pack_module ;;
        4) pack_bundle ;;
        *) pack_portable ;;
    esac
}

# ─── Modo 1: Normal ─────────────────────────────────────────────────────────
# ─── Mode 1: Normal ─────────────────────────────────────────────────────────
pack_normal() {
    hdr "$(t L_PACKING) $(t L_NORMAL)"
    local inf="$CURRENT_INFO" p
    p=$(fld "$inf" 2)
    [[ -z "$CURRENT_APP_ID" ]] && err "App ID required"
    local wd
    wd=$(tmpdir "real")
    reg_cln "$wd"
    mkdir -p "$wd/bin"
    cp "$p" "$wd/bin/"
    chmod +x "$wd/bin/$(basename "$p")"
    local bn
    bn=$(basename "$p")
    info "Analyzing libs / Analizando libs..."
    local lsys=0 lpriv=0 plibs=()
    while IFS='|' read -r lib lp; do
        [[ -z "$lib" || -z "$lp" ]] && continue
        if [[ "$lp" == /usr/lib/* || "$lp" == /lib/* || "$lp" == /lib64/* ]]; then
            lsys=$((lsys + 1))
        else
            plibs+=("$lp"); lpriv=$((lpriv + 1))
        fi
    done < <(get_libs "$p")
    det "System: $lsys  Private: $lpriv"
    local ep
    if [[ $lpriv -gt 0 ]]; then
        # Libs privadas -> celdas (una por lib), referenciadas en el manifiesto.
        # Private libs -> cells (one per lib), referenced in the manifest.
        local cells
        cells=$("$PACKBOX_BIN_MODULE" cell "${plibs[@]}" 2>/dev/null | paste -sd, -)
        [[ -n "$cells" ]] && CURRENT_MODS="${CURRENT_MODS:+$CURRENT_MODS,}$cells"
        launcher_simple "$wd/bin/launcher.sh" "$bn"
        ep="/app/bin/launcher.sh"
    else
        ep="/app/bin/$bn"
    fi
    invoke_pack "$wd" "$CURRENT_APP_ID" "$ep" || err "pack failed"
    jq empty "$wd/manifest.json" 2>/dev/null || err "invalid JSON"
    "$PACKBOX_BIN_INSTALL" "$wd/manifest.json" || err "install failed"
    local ad="$PACKBOX_APPS_DIR/$CURRENT_APP_ID"
    [[ -d "$ad/tree" ]] || err "no tree/"
    box_ok "$CURRENT_APP_ID  $(t L_INSTALLED)"
    maybe_desktop
    ask_yn "$(t L_EXEC_NOW)" "n" && { echo ""; "$PACKBOX_BIN_RUN" "$CURRENT_APP_ID"; }
    rm -rf "$wd"
    unreg_cln "$wd"
}

# ─── Modo 2: Portable ───────────────────────────────────────────────────────
# ─── Mode 2: Portable ───────────────────────────────────────────────────────
pack_portable() {
    hdr "$(t L_PACKING) $(t L_PORTABLE)"
    local inf="$CURRENT_INFO" p
    p=$(fld "$inf" 2)
    [[ -z "$CURRENT_APP_ID" ]] && err "App ID required"
    local wd
    wd=$(tmpdir "portable")
    reg_cln "$wd"
    mkdir -p "$wd/bin"
    cp "$p" "$wd/bin/"
    chmod +x "$wd/bin/$(basename "$p")"
    local bn
    bn=$(basename "$p")
    info "Non-universal libs / Libs no universales..."
    local lb=0 tls=0 sku=0 seen="" libs=()
    while IFS='|' read -r lib lp; do
        [[ -z "$lib" || -z "$lp" || ! -f "$lp" ]] && continue
        if is_universal "$lib"; then
            sku=$((sku + 1)); continue
        fi
        echo "$seen" | grep -q "|$lib|" && continue
        seen+="|$lib|"
        libs+=("$lp")
        local ls
        ls=$(stat -c%s "$lp" 2>/dev/null || echo 0)
        tls=$((tls + ls))
        lb=$((lb + 1))
    done < <(get_libs "$p")
    local tlh
    tlh=$(hs "$tls")
    local ep
    if [[ $lb -gt 0 ]]; then
        # Una celda por lib no universal: la app las declara y el instalador
        # las resuelve/enlaza -> reuso entre apps y capa A mínima.
        # One cell per non-universal lib: the app declares them and install
        # resolves/links them -> cross-app reuse and a minimal A layer.
        local cells
        cells=$("$PACKBOX_BIN_MODULE" cell "${libs[@]}" 2>/dev/null | paste -sd, -)
        [[ -n "$cells" ]] && CURRENT_MODS="${CURRENT_MODS:+$CURRENT_MODS,}$cells"
        ok "Cells: $lb ($tlh)"
        launcher_simple "$wd/bin/launcher.sh" "$bn"
        ep="/app/bin/launcher.sh"
    else
        ep="/app/bin/$bn"
    fi
    invoke_pack "$wd" "$CURRENT_APP_ID" "$ep" || err "pack failed"
    "$PACKBOX_BIN_INSTALL" "$wd/manifest.json" || err "install failed"
    local ad="$PACKBOX_APPS_DIR/$CURRENT_APP_ID"
    [[ -d "$ad/tree" ]] || err "no tree/"
    local tm
    tm=$(mktemp)
    jq '. + {"portable": true, "portable_libs_count": '"$lb"'}' "$ad/manifest.json" > "$tm"
    mv "$tm" "$ad/manifest.json"
    box_ok "$CURRENT_APP_ID  $(t L_PORTABLE)"
    det "Libs: $lb ($tlh)"
    maybe_desktop
    ask_yn "$(t L_EXEC_NOW)" "n" && { echo ""; "$PACKBOX_BIN_RUN" "$CURRENT_APP_ID"; }
    rm -rf "$wd"
    unreg_cln "$wd"
}

# ─── Modo 3: Bundle ─────────────────────────────────────────────────────────
# ─── Mode 3: Bundle ─────────────────────────────────────────────────────────
pack_bundle() {
    hdr "$(t L_PACKING) $(t L_BUNDLE)"
    local inf="$CURRENT_INFO" p s bd
    p=$(fld "$inf" 2); s=$(fld "$inf" 4); bd=$(fld "$inf" 9)
    [[ -z "$bd" || ! -d "$bd" ]] && err "no bundle_dir"
    [[ -z "$CURRENT_APP_ID" ]] && err "App ID required"
    local wd
    wd=$(tmpdir "bundle")
    reg_cln "$wd"
    mkdir -p "$wd/bin" "$wd/bundle"

    info "Copying bundle $s..."
    # Intento 1: hardlinks (rápido, sin duplicar).
    # Intento 2: copia real.
    if cp -al "$bd/." "$wd/bundle/" 2>/dev/null; then
        det "Hardlinks OK (same FS)"
    elif cp -a --no-preserve=ownership "$bd/." "$wd/bundle/" 2>/dev/null; then
        det "Real copy (cross-FS)"
    else
        err "Bundle copy failed ($bd → $wd/bundle)"
    fi

    local br=""
    local rs
    rs=$(readlink -f "$p" 2>/dev/null || echo "$p")
    if [[ "$rs" == "$bd"/* ]]; then
        local cand="${rs#$bd/}"
        [[ -e "$wd/bundle/$cand" ]] && br="$cand"
    fi
    [[ -z "$br" ]] && br=$(find_bin_in_bundle "$p" "$wd/bundle")
    [[ -z "$br" ]] && err "no binary in bundle"
    [[ ! -e "$wd/bundle/$br" ]] && err "missing: $br"
    [[ -f "$wd/bundle/$br" && ! -x "$wd/bundle/$br" ]] && chmod +x "$wd/bundle/$br"
    ok "Binary: bundle/$br"

    cat > "$wd/bin/launcher.sh" <<LAUNCHER_EOF
#!/usr/bin/env bash
SCRIPT_DIR="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="\$(dirname "\$SCRIPT_DIR")"
BUNDLE_DIR="\$APP_DIR/bundle"
export LD_LIBRARY_PATH="\$BUNDLE_DIR:\$BUNDLE_DIR/lib:\$BUNDLE_DIR/lib64:\$BUNDLE_DIR/program:\${LD_LIBRARY_PATH:-}"
[[ -d "\$BUNDLE_DIR/share" ]] && export XDG_DATA_DIRS="\${XDG_DATA_DIRS:-/usr/local/share:/usr/share}:\$BUNDLE_DIR/share"
exec "\$BUNDLE_DIR/$br" "\$@"
LAUNCHER_EOF
    chmod +x "$wd/bin/launcher.sh"

    invoke_pack "$wd" "$CURRENT_APP_ID" "/app/bin/launcher.sh" || err "pack failed"
    "$PACKBOX_BIN_INSTALL" "$wd/manifest.json" || err "install failed"
    local ad="$PACKBOX_APPS_DIR/$CURRENT_APP_ID"
    [[ -d "$ad/tree" ]] || err "no tree/"
    local tm
    tm=$(mktemp)
    jq '. + {"portable": true, "bundle": true, "bundle_dir": "'"$bd"'", "bundle_bin_rel": "'"$br"'"}' \
        "$ad/manifest.json" > "$tm"
    mv "$tm" "$ad/manifest.json"
    box_ok "$CURRENT_APP_ID  $(t L_BUNDLE)"
    det "Bundle: $bd"
    det "Binary: bundle/$br"
    maybe_desktop
    ask_yn "$(t L_EXEC_NOW)" "n" && { echo ""; "$PACKBOX_BIN_RUN" "$CURRENT_APP_ID"; }
    rm -rf "$wd"
    unreg_cln "$wd"
}

# ─── Modo 4: Módulo ─────────────────────────────────────────────────────────
# ─── Mode 4: Module ─────────────────────────────────────────────────────────
pack_module() {
    hdr "$(t L_MODULE)"
    local inf="$CURRENT_INFO" p tk
    p=$(fld "$inf" 2); tk=$(fld "$inf" 8)
    [[ ! -x "$PACKBOX_BIN_MODULE" ]] && err "packbox-module not found"
    echo -en "  ${BD}Name: ${N}"
    local mn
    read -r mn
    [[ -z "$mn" ]] && mn="org.toolkit.$(echo "$tk" | tr '[:upper:]' '[:lower:]')"
    echo -en "  ${BD}Version [1.0.0]: ${N}"
    local mv
    read -r mv
    mv="${mv:-1.0.0}"
    "$PACKBOX_BIN_MODULE" create "$p" "$mn" "$mv"
    read -rp "  ENTER..."
}

# ─── Pregunta sobre entrada de menú ─────────────────────────────────────────
# ─── Desktop entry question ─────────────────────────────────────────────────
maybe_desktop() {
    # Si es CLI no preguntar.
    # If CLI, don't ask.
    if [[ "$CURRENT_IS_GUI" != "GUI" ]]; then
        return 0
    fi
    # El binario Go `packbox-install` ya crea la entrada al instalar.
    # The Go binary `packbox-install` already creates the entry on install.
    # Solo la creamos si el usuario la borró o si falló.
    # We only create it if the user deleted it or if it failed.
    local df="$PACKBOX_DESKTOP_DIR/packbox-$CURRENT_APP_ID.desktop"
    if [[ -f "$df" ]]; then
        det "Desktop entry: OK"
        return 0
    fi
    echo ""
    if ask_yn "$(t L_CREATE_DESKTOP)" "s"; then
        create_desktop_entry "$CURRENT_APP_ID"
    fi
}