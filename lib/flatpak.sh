#!/usr/bin/env bash
# =============================================================================
# lib/flatpak.sh — Importar una app instalada con Flatpak como .pbox.
# lib/flatpak.sh — Import an app installed with Flatpak as a .pbox.
#
# La app se lleva tal cual (su árbol files/) y el RUNTIME se trocea en **celdas
# compartidas**: un runtime de Flatpak son ~1 GB por familia y aquí sus libs se
# comparten entre apps y familias (deduplicadas por contenido).
# The app is taken as-is (its files/ tree) and the RUNTIME is split into
# **shared cells**: a Flatpak runtime is ~1 GB per family and here its libs are
# shared across apps and families (content-deduplicated).
#
# Asume / Assumes: ui.sh, paths.sh, common.sh, detect.sh, pack.sh
# Provee / Provides: flatpak_applications, flatpak_import
# =============================================================================

FLATPAK_ROOT="${FLATPAK_ROOT:-/var/lib/flatpak}"

# _fp_pause — pausa solo con terminal: en un script (sin stdin) no debe colgarse.
# _fp_pause — pauses only with a terminal: in a script (no stdin) it must not hang.
_fp_pause() {
    [[ -t 0 ]] && _fp_pause
    return 0
}


# flatpak_applications — ids de las apps instaladas con Flatpak.
# flatpak_applications — ids of the apps installed with Flatpak.
flatpak_applications() {
    local d
    for d in "$FLATPAK_ROOT"/app/*/; do
        [[ -d "$d" ]] || continue
        basename "$d"
    done | sort
}

# flatpak_deploy <app-id> — directorio del deployment activo (o el único).
# flatpak_deploy <app-id> — directory of the active deployment (or the only one).
flatpak_deploy() {
    local base="$FLATPAK_ROOT/app/$1" a d
    [[ -d "$base" ]] || return 1
    for a in "$base"/*/; do
        [[ -d "$a" ]] || continue
        for d in "$a"/*/; do
            [[ -d "$d/files" ]] || continue
            if [[ -e "$d/active" ]]; then
                readlink -f "$d/active"
            else
                echo "${d%/}"
            fi
            return 0
        done
    done
    return 1
}

# flatpak_runtime_dir <ref "org.gnome.Platform/x86_64/46"> — su deployment.
# flatpak_runtime_dir <ref> — its deployment.
flatpak_runtime_dir() {
    local ref="$1" id arch br base d
    IFS=/ read -r id arch br <<< "$ref"
    [[ -n "$id" && -n "$arch" && -n "$br" ]] || return 1
    base="$FLATPAK_ROOT/runtime/$id/$arch/$br"
    [[ -d "$base" ]] || return 1
    for d in "$base"/*/; do
        [[ -d "$d/files" ]] || continue
        if [[ -e "$d/active" ]]; then
            readlink -f "$d/active"
        else
            echo "${d%/}"
        fi
        return 0
    done
    return 1
}

# flatpak_meta <deploy> <clave> — campo del fichero metadata (INI).
# flatpak_meta <deploy> <key> — field of the metadata file (INI).
flatpak_meta() {
    grep -m1 "^$2=" "$1/metadata" 2>/dev/null | cut -d= -f2-
}

# ─── Importar ───────────────────────────────────────────────────────────────
# ─── Import ─────────────────────────────────────────────────────────────────
flatpak_import() {
    local want="${1:-}" id dep rt cmd
    hdr "$(_tt L_FP_TITLE "Importar una app de Flatpak")"

    if [[ ! -d "$FLATPAK_ROOT/app" ]]; then
        warn "$(_tt L_FP_NONE "Flatpak no está instalado (o no hay apps instaladas)")"
        _fp_pause
        return 1
    fi

    # Elegir app (o usar la indicada).
    if [[ -z "$want" ]]; then
        local apps=() i=1 a
        while IFS= read -r a; do
            printf "  ${C}%3d${N}) %s\n" "$i" "$a"
            apps+=("$a")
            i=$((i + 1))
        done < <(flatpak_applications)
        if ((${#apps[@]} == 0)); then
            warn "$(_tt L_NONE "ninguna")"
            _fp_pause
            return 1
        fi
        echo ""
        echo -en "  ${BD}> 1-${#apps[@]}, q: ${N}"
        local c
        read -r c
        [[ "$c" =~ ^[0-9]+$ ]] && ((c >= 1 && c <= ${#apps[@]})) || return 1
        id="${apps[$((c - 1))]}"
    else
        id="$want"
    fi

    dep=$(flatpak_deploy "$id") || {
        warn "$(_tt L_FP_NOTFOUND "no encontrada") : $id"
        _fp_pause
        return 1
    }
    cmd=$(flatpak_meta "$dep" command)
    [[ -z "$cmd" ]] && cmd=$(ls "$dep/files/bin" 2>/dev/null | head -1)
    rt=$(flatpak_meta "$dep" runtime)

    echo ""
    det "app:     ${dep#"$FLATPAK_ROOT"/}"
    det "command: $cmd"
    det "runtime: ${rt:--}"
    if [[ -z "$cmd" || ! -x "$dep/files/bin/$cmd" ]]; then
        warn "$(_tt L_FP_NOCMD "no encuentro el binario de la app") : bin/${cmd:-?}"
        _fp_pause
        return 1
    fi
    echo ""
    ask_yn "$(_tt L_FP_CONFIRM "¿Convertir esta app a .pbox?")" "s" || return 1

    current_from_flatpak "$dep" "$id" "$cmd" "$rt" || return 1
    flatpak_pack "$dep" "$cmd" "$rt"
}

# current_from_flatpak — rellena los CURRENT_* desde el metadata y el export.
# current_from_flatpak — fills the CURRENT_* from the metadata and the export.
current_from_flatpak() {
    local dep="$1" id="$2" cmd="$3" rt="$4"
    local sockets shared rtdir df

    CURRENT_APP_ID="$id"
    CURRENT_VERSION="1.0"
    CURRENT_DESC="$id"
    CURRENT_IS_GUI="GUI"
    CURRENT_TOOLKIT=""
    CURRENT_BUNDLE_DIR=""
    CURRENT_MODS=""
    CURRENT_BUS=""
    CURRENT_SANDBOX=""
    CURRENT_X11=""
    CURRENT_CATEGORIES=""
    CURRENT_ICON=""

    # export/: el .desktop y los iconos que la app expone.
    df=$(find "$dep/export/share/applications" -maxdepth 1 -name '*.desktop' 2>/dev/null | head -1)
    if [[ -n "$df" ]]; then
        CURRENT_DESC=$(grep -m1 '^Name=' "$df" | cut -d= -f2-)
        CURRENT_CATEGORIES=$(grep -m1 '^Categories=' "$df" | cut -d= -f2-)
        CURRENT_IS_GUI="GUI"
        grep -qi '^Terminal=true' "$df" && CURRENT_IS_GUI="CLI"
        CURRENT_BUS=$(basename "$df" .desktop)
        grep -qi '^DBusActivatable=true' "$df" || CURRENT_BUS=""
        # En Flatpak el nombre de bus es el app-id (convención).
        # In Flatpak the bus name is the app id (convention).
        [[ -z "$CURRENT_BUS" ]] && CURRENT_BUS="$id"
        local ic
        ic=$(grep -m1 '^Icon=' "$df" | cut -d= -f2-)
        [[ -n "$ic" ]] && CURRENT_ICON=$(resolve_icon "$ic" || true)
    fi

    # Context: red, x11, y las libs del runtime para resolver dependencias.
    shared=$(flatpak_meta "$dep" shared)
    sockets=$(flatpak_meta "$dep" sockets)
    [[ "$shared" == *network* ]] && CURRENT_NETWORK="full" || CURRENT_NETWORK="none"
    [[ "$sockets" == *x11* ]] && CURRENT_X11="1"

    # LD_LIBRARY_PATH con el runtime: sin él, ldd no resuelve las libs de la app
    # (que no están en el host) y no se empaquetaría ninguna celda.
    # LD_LIBRARY_PATH with the runtime: without it ldd cannot resolve the app's
    # libs (absent from the host) and no cell would be packaged.
    rtdir=$(flatpak_runtime_dir "$rt" 2>/dev/null || true)
    CURRENT_LDLP=""
    if [[ -n "$rtdir" && -d "$rtdir/files" ]]; then
        local d
        for d in lib lib64 lib/x86_64-linux-gnu; do
            [[ -d "$rtdir/files/$d" ]] && CURRENT_LDLP="${CURRENT_LDLP:+$CURRENT_LDLP:}$rtdir/files/$d"
        done
    fi
    CURRENT_INFO="$CURRENT_DESC|${rtdir:-$dep}/files/bin/$cmd|Other|0|ELF|$id|$CURRENT_IS_GUI|||0"
    return 0
}

# flatpak_pack <deploy> <cmd> <runtime-ref> — empaqueta (app + celdas del runtime).
# flatpak_pack <deploy> <cmd> <runtime-ref> — packages (app + runtime cells).
flatpak_pack() {
    local dep="$1" cmd="$2" rt="$3" rtdir d lp libs=() cells wd
    rtdir=$(flatpak_runtime_dir "$rt" 2>/dev/null || true)

    wd=$(tmpdir "flatpak")
    reg_cln "$wd"
    mkdir -p "$wd"
    info "$(_tt L_FP_COPY "Copiando la app...")"
    cp -a "$dep/files/." "$wd/" 2>/dev/null || true

    # Celdas: libs no universales del runtime + las privadas de la app.
    # Cells: non-universal runtime libs + the app's own private libs.
    info "$(_tt L_FP_CELLS "Celdas desde el runtime...")"
    for d in "$rtdir/files/lib" "$rtdir/files/lib64" "$rtdir/files/lib/x86_64-linux-gnu" \
        "$wd/lib" "$wd/lib64" "$wd/lib/x86_64-linux-gnu"; do
        [[ -d "$d" ]] || continue
        while IFS= read -r lp; do
            [[ -f "$lp" ]] || continue
            is_universal "$(basename "$lp")" && continue
            libs+=("$lp")
        # -type f Y -type l: los sonames (libfoo.so.1 → libfoo.so.1.2.3) son
        # symlinks y sin ellos el loader no encuentra las libs.
        # -type f AND -type l: sonames (libfoo.so.1 → libfoo.so.1.2.3) are
        # symlinks and without them the loader cannot find the libs.
        done < <(find "$d" -maxdepth 1 \( -type f -o -type l \) -name '*.so*' 2>/dev/null)
    done
    if ((${#libs[@]} > 0)); then
        cells=$("$PACKBOX_BIN_MODULE" cell "${libs[@]}" 2>/dev/null | paste -sd, -)
        [[ -n "$cells" ]] && CURRENT_MODS="${CURRENT_MODS:+$CURRENT_MODS,}$cells"
        ok "$(_tt L_CELLS "Celdas"): ${#libs[@]}"
    fi

    # Launcher: el binario necesita /app/lib (donde caen las celdas).
    # Launcher: the binary needs /app/lib (where the cells land).
    mkdir -p "$wd/bin"
    launcher_simple "$wd/bin/launcher.sh" "$cmd"
    invoke_pack "$wd" "$CURRENT_APP_ID" "/app/bin/launcher.sh" || { fail "pack failed"; rm -rf "$wd"; unreg_cln "$wd"; return 1; }
    jq empty "$wd/manifest.json" 2>/dev/null || { fail "invalid JSON"; rm -rf "$wd"; unreg_cln "$wd"; return 1; }

    finish_pack "$wd" "Flatpak"
    rm -rf "$wd"
    unreg_cln "$wd"
}
