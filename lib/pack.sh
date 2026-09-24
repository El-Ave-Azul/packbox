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
    # Icono y categoría reales (del .desktop original), si se conocen.
    # The app's real icon and categories (from the original .desktop), if known.
    [[ -n "${CURRENT_ICON:-}" ]] && args+=(--icon "$CURRENT_ICON")
    [[ -n "${CURRENT_CATEGORIES:-}" ]] && args+=(--categories "$CURRENT_CATEGORIES")
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
    [[ -z "$CURRENT_APP_ID" ]] && { fail "App ID required"; return 1; }
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
        # "Sistema" = lib UNIVERSAL (vive en el host: glibc, libm, libz…).
        # Todo lo demás se empaqueta: en Debian/Ubuntu las libs de la app también
        # están en /usr/lib/x86_64-linux-gnu, y tratar /usr/lib como "sistema"
        # dejaba a la app sin sus dependencias reales ("cannot open shared object").
        # "System" = a UNIVERSAL lib (lives on the host: glibc, libm, libz…).
        # Anything else is packaged: on Debian/Ubuntu the app's own libs also live
        # under /usr/lib/x86_64-linux-gnu, and treating /usr/lib as "system" left
        # the app without its real deps ("cannot open shared object").
        if is_universal "$lib"; then
            lsys=$((lsys + 1))
        else
            plibs+=("$lp"); lpriv=$((lpriv + 1))
        fi
    done < <(get_libs "$p")
    warn_no_libs "$p" "$lpriv"
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
    invoke_pack "$wd" "$CURRENT_APP_ID" "$ep" || { fail "pack failed"; return 1; }
    jq empty "$wd/manifest.json" 2>/dev/null || { fail "invalid JSON"; return 1; }
    finish_pack "$wd" "$(t L_NORMAL)"
    rm -rf "$wd"
    unreg_cln "$wd"
}

# ─── Modo 2: Portable ───────────────────────────────────────────────────────
# ─── Mode 2: Portable ───────────────────────────────────────────────────────
pack_portable() {
    hdr "$(t L_PACKING) $(t L_PORTABLE)"
    local inf="$CURRENT_INFO" p
    p=$(fld "$inf" 2)
    [[ -z "$CURRENT_APP_ID" ]] && { fail "App ID required"; return 1; }
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
    warn_no_libs "$p" "$lb"
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
    invoke_pack "$wd" "$CURRENT_APP_ID" "$ep" || { fail "pack failed"; return 1; }
    # Marca el manifiesto ANTES de exportar (el .pbox debe llevarlo).
    # Flag the manifest BEFORE exporting (the .pbox must carry it).
    local tm
    tm=$(mktemp)
    jq '. + {"portable": true, "portable_libs_count": '"$lb"'}' "$wd/manifest.json" > "$tm"
    mv "$tm" "$wd/manifest.json"
    det "Libs: $lb ($tlh)"
    finish_pack "$wd" "$(t L_PORTABLE)"
    rm -rf "$wd"
    unreg_cln "$wd"
}

# ─── Modo 3: Bundle ─────────────────────────────────────────────────────────
# ─── Mode 3: Bundle ─────────────────────────────────────────────────────────
pack_bundle() {
    hdr "$(t L_PACKING) $(t L_BUNDLE)"
    local inf="$CURRENT_INFO" p s bd
    p=$(fld "$inf" 2); s=$(fld "$inf" 4); bd=$(fld "$inf" 9)
    [[ -z "$bd" || ! -d "$bd" ]] && { fail "no bundle_dir"; return 1; }
    [[ -z "$CURRENT_APP_ID" ]] && { fail "App ID required"; return 1; }
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
        { fail "Bundle copy failed ($bd → $wd/bundle)"; return 1; }
    fi

    local br=""
    local rs
    rs=$(readlink -f "$p" 2>/dev/null || echo "$p")
    if [[ "$rs" == "$bd"/* ]]; then
        local cand="${rs#$bd/}"
        [[ -e "$wd/bundle/$cand" ]] && br="$cand"
    fi
    [[ -z "$br" ]] && br=$(find_bin_in_bundle "$p" "$wd/bundle")
    [[ -z "$br" ]] && { fail "no binary in bundle"; return 1; }
    [[ ! -e "$wd/bundle/$br" ]] && { fail "missing: $br"; return 1; }
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

    invoke_pack "$wd" "$CURRENT_APP_ID" "/app/bin/launcher.sh" || { fail "pack failed"; return 1; }
    local tm
    tm=$(mktemp)
    jq '. + {"portable": true, "bundle": true, "bundle_dir": "'"$bd"'", "bundle_bin_rel": "'"$br"'"}' \
        "$wd/manifest.json" > "$tm"
    mv "$tm" "$wd/manifest.json"
    det "Bundle: $bd"
    det "Binary: bundle/$br"
    finish_pack "$wd" "$(t L_BUNDLE)"
    rm -rf "$wd"
    unreg_cln "$wd"
}

# ─── Modo 4: Módulo ─────────────────────────────────────────────────────────
# ─── Mode 4: Module ─────────────────────────────────────────────────────────
pack_module() {
    hdr "$(t L_MODULE)"
    local inf="$CURRENT_INFO" p tk
    p=$(fld "$inf" 2); tk=$(fld "$inf" 8)
    [[ ! -x "$PACKBOX_BIN_MODULE" ]] && { fail "packbox-module not found"; return 1; }
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

# ─── Cierre del empaquetado ─────────────────────────────────────────────────
# ─── Pack finish ────────────────────────────────────────────────────────────
# finish_pack <wd> [etiqueta] — exporta el .pbox desde el dir de trabajo y
# ofrece instalar la app en este equipo (por defecto NO).
# finish_pack <wd> [label] — exports the .pbox from the working dir and offers
# to install the app on this machine (default NO).
finish_pack() {
    local wd="$1" label="${2:-}" aid="$CURRENT_APP_ID"
    echo ""
    info "$(t L_4_EXPORT)..."
    if ! "$PACKBOX_BIN_EXPORT" app "$wd"; then
        fail "export failed"
        return 1
    fi
    local pb="$PACKBOX_EXPORTS_DIR/$aid.pbox"
    box_ok "$aid  $label"
    det "File: $pb"
    [[ -f "$pb" ]] && det "Size: $(du -h "$pb" 2>/dev/null | cut -f1)"

    echo ""
    if ask_yn "$(_tt L_INSTALL_HERE "¿Instalar también en este equipo?")" "n"; then
        "$PACKBOX_BIN_INSTALL" "$wd/manifest.json" || { fail "install failed"; return 1; }
        box_ok "$aid  $(t L_INSTALLED)"
        maybe_desktop
        ask_yn "$(t L_EXEC_NOW)" "n" && { echo ""; "$PACKBOX_BIN_RUN" "$aid"; }
    fi
}

# warn_no_libs <bin> <count> — si no se detectaron libs y el binario no es ELF
# (script/wrapper), avisa: sus dependencias no se pueden inferir.
# warn_no_libs <bin> <count> — if no libs were found and the binary is not ELF
# (a script/wrapper), warn: its dependencies cannot be inferred.
warn_no_libs() {
    local bin="${1:-}" n="${2:-0}"
    [[ -z "$bin" || "$n" -gt 0 ]] && return 0
    file -b "$bin" 2>/dev/null | grep -q ELF && return 0
    warn "$(_tt L_NOT_ELF "el binario no es un ELF (¿script/wrapper?): no se pueden deducir sus libs; la app puede no arrancar")"
}

# ─── Pregunta sobre entrada de menú ─────────────────────────────────────────
# ─── Desktop entry question ─────────────────────────────────────────────────
maybe_desktop() {
    # El binario Go `packbox-install` ya crea la entrada al instalar, para GUI
    # (sin terminal) y CLI (con terminal). Aquí solo la reportamos, y la
    # recreamos si el usuario la borró o si falló.
    # The Go binary `packbox-install` already creates the entry on install, for
    # GUI (no terminal) and CLI (with terminal). Here we only report it, and
    # recreate it if the user deleted it or if it failed.
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