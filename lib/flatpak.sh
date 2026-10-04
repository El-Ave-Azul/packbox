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
# Provee / Provides: flatpak_roots, flatpak_applications, flatpak_import, fp_version
# =============================================================================

# Instalaciones de Flatpak: sistema y usuario. FLATPAK_ROOT lo fuerza (tests).
# Flatpak installs: system and user. FLATPAK_ROOT overrides (tests).
FLATPAK_ROOT="${FLATPAK_ROOT:-}"

# flatpak_roots — raíces de Flatpak existentes (sistema + usuario).
# flatpak_roots — existing Flatpak roots (system + user).
flatpak_roots() {
    if [[ -n "$FLATPAK_ROOT" ]]; then
        [[ -d "$FLATPAK_ROOT/app" ]] && printf '%s\n' "$FLATPAK_ROOT"
        return 0
    fi
    local r
    for r in /var/lib/flatpak "$HOME/.local/share/flatpak" "${XDG_DATA_HOME:-$HOME/.local/share}/flatpak"; do
        [[ -d "$r/app" ]] && printf '%s\n' "$r"
    done | sort -u
}

# _fp_pause — pausa solo con terminal: en un script (sin stdin) no debe colgarse.
# _fp_pause — pauses only with a terminal: in a script (no stdin) it must not hang.
_fp_pause() {
    [[ -t 0 ]] && read -rp "  ENTER..."
    return 0
}

# fp_version <app-id> — versión real si flatpak la reporta, si no "1.0".
# fp_version <app-id> — real version if flatpak reports it, else "1.0".
fp_version() {
    local id="$1" v=""
    if command -v flatpak >/dev/null 2>&1; then
        v=$(flatpak info "$id" 2>/dev/null | awk -F': *' '/^[[:space:]]*Version:/{print $2; exit}')
    fi
    printf '%s' "${v:-1.0}"
}


# flatpak_applications — ids de las apps instaladas con Flatpak (sistema + usuario).
# flatpak_applications — ids of the installed Flatpak apps (system + user).
flatpak_applications() {
    local root d
    while IFS= read -r root; do
        for d in "$root"/app/*/; do
            [[ -d "$d" ]] || continue
            basename "$d"
        done
    done < <(flatpak_roots) | sort -u
}

# flatpak_deploy <app-id> — directorio del deployment activo (o el único).
# flatpak_deploy <app-id> — directory of the active deployment (or the only one).
flatpak_deploy() {
    local id="$1" root base a br d
    while IFS= read -r root; do
        base="$root/app/$id"
        [[ -d "$base" ]] || continue
        for a in "$base"/*/; do          # <arch>/
            [[ -d "$a" ]] || continue
            for br in "$a"/*/; do        # <branch>/
                [[ -d "$br" ]] || continue
                # <branch>/active → commit activo (el deployment activo).
                # <branch>/active → active commit (the active deployment).
                if [[ -e "$br/active" ]]; then
                    readlink -f "$br/active"
                    return 0
                fi
                for d in "$br"/*/; do    # <commit>/
                    [[ -d "$d/files" ]] || continue
                    echo "${d%/}"
                    return 0
                done
            done
        done
    done < <(flatpak_roots)
    return 1
}

# flatpak_runtime_dir <ref "org.gnome.Platform/x86_64/46"> — su deployment.
# flatpak_runtime_dir <ref> — its deployment.
flatpak_runtime_dir() {
    local ref="$1" root id arch br base d
    IFS=/ read -r id arch br <<< "$ref"
    [[ -n "$id" && -n "$arch" && -n "$br" ]] || return 1
    while IFS= read -r root; do
        base="$root/runtime/$id/$arch/$br"
        [[ -d "$base" ]] || continue
        # Preferir el commit activo (<branch>/active); si no, el primero.
        # Prefer the active commit (<branch>/active); otherwise the first one.
        if [[ -e "$base/active" ]]; then
            readlink -f "$base/active"
            return 0
        fi
        for d in "$base"/*/; do
            [[ -d "$d/files" ]] || continue
            echo "${d%/}"
            return 0
        done
    done < <(flatpak_roots)
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

    if [[ -z "$(flatpak_roots | head -1)" ]]; then
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
    det "app:     ${dep#"${dep%%/app/*}"/}"
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
    CURRENT_VERSION="$(fp_version "$id")"
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
