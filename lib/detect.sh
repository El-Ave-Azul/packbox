#!/usr/bin/env bash
# shellcheck disable=SC2034  # usadas por los archivos que sourcean esta librería
# =============================================================================
# lib/detect.sh — Detección de apps instaladas en el sistema.
# lib/detect.sh — Detection of installed apps on the system.
#
# Asume / Assumes: ui.sh, paths.sh, common.sh
# Provee / Provides: gui_app, toolkit, resolve_bin, net_suggests,
#                    find_bin_in_bundle, find_bundle_dir, scan_bundles,
#                    scan_desktop, reg_app, calc_total, detect_all,
#                    fld, select_top, search_app, show_details, configure_pack
# =============================================================================

# ─── Estado global compartido con pack.sh ───────────────────────────────────
# ─── Global state shared with pack.sh ──────────────────────────────────────
# -g: los módulos se sourcean dentro de _pb_bootstrap (una función), así que
# sin -g estos arrays quedarían locales y se perderían.
# -g: modules are sourced inside _pb_bootstrap (a function), so without -g
# these arrays would be local and lost.
declare -gA APPS_MAP=()
declare -ga APPS_LIST=()
declare -ga APPS_SORTED=()

CURRENT_BIN=""
CURRENT_INFO=""
CURRENT_APP_ID=""
CURRENT_VERSION=""
CURRENT_DESC=""
CURRENT_IS_GUI=""
CURRENT_TOOLKIT=""
CURRENT_PACK_MODE=2
CURRENT_BUNDLE_DIR=""
CURRENT_NETWORK="false"
CURRENT_MODS=""
CURRENT_ICON=""
CURRENT_CATEGORIES=""
# Icono y categoría de cada app, tomados del .desktop original (clave = binario).
# Icon and category per app, taken from the original .desktop (key = binary).
declare -gA ICON_OF=()
declare -gA CAT_OF=()
# GUI/CLI por app, del .desktop original (Terminal=true → CLI). Clave = binario.
# GUI/CLI per app, from the original .desktop (Terminal=true → CLI). Key = binary.
declare -gA GUI_OF=()

# ─── Icono del sistema ──────────────────────────────────────────────────────
# ─── System icon ────────────────────────────────────────────────────────────
# resolve_icon <nombre-o-ruta> — ruta absoluta a un icono real, o vacío.
# resolve_icon <name-or-path> — absolute path to a real icon file, or empty.
resolve_icon() {
    local n="$1" d e p
    [[ -z "$n" ]] && return 1
    if [[ "$n" == /* ]]; then
        [[ -f "$n" ]] && { echo "$n"; return 0; }
        return 1
    fi
    for d in /usr/share/pixmaps \
        /usr/share/icons/hicolor/256x256/apps /usr/share/icons/hicolor/128x128/apps \
        /usr/share/icons/hicolor/64x64/apps /usr/share/icons/hicolor/scalable/apps; do
        for e in png svg xpm; do
            p="$d/$n.$e"
            [[ -f "$p" ]] && { echo "$p"; return 0; }
        done
    done
    p=$(find /usr/share/icons -maxdepth 4 -type f \( -name "$n.png" -o -name "$n.svg" \) 2>/dev/null | head -1)
    [[ -n "$p" ]] && { echo "$p"; return 0; }
    return 1
}

# inherit_meta <bin> — hereda icono/categoría del .desktop del sistema que
# apunte al mismo binario (por basename), si aún no los tiene.
# inherit_meta <bin> — inherits icon/category from the system .desktop pointing
# at the same binary (by basename), if it doesn't have them yet.
inherit_meta() {
    local b="$1" sym
    [[ -z "$b" ]] && return 0
    sym=$(command -v "$(basename "$b")" 2>/dev/null || true)
    [[ -z "$sym" ]] && return 0
    [[ -z "${CAT_OF[$b]:-}" && -n "${CAT_OF[$sym]:-}" ]] && CAT_OF[$b]="${CAT_OF[$sym]}"
    [[ -z "${ICON_OF[$b]:-}" && -n "${ICON_OF[$sym]:-}" ]] && ICON_OF[$b]="${ICON_OF[$sym]}"
    [[ -z "${GUI_OF[$b]:-}" && -n "${GUI_OF[$sym]:-}" ]] && GUI_OF[$b]="${GUI_OF[$sym]}"
    return 0
}

# ─── Detección de GUI ────────────────────────────────────────────────────────
# ─── GUI detection ───────────────────────────────────────────────────────────
# gui_app <bin> — 0 si el binario enlaza contra libs de GUI.
# gui_app <bin> — 0 if the binary links against GUI libs.
gui_app() {
    local o
    o=$(ldd "$1" 2>/dev/null || true)
    echo "$o" | grep -qE "libgtk|libgdk|libQt|libX11|libwayland|libSDL"
}

# ─── Detección de toolkit ────────────────────────────────────────────────────
# ─── Toolkit detection ──────────────────────────────────────────────────────
# toolkit <bin> — devuelve GTK3/GTK4/Qt5/Qt6/SDL o vacío.
# toolkit <bin> — returns GTK3/GTK4/Qt5/Qt6/SDL or empty.
toolkit() {
    local o
    o=$(ldd "$1" 2>/dev/null || true)
    if echo "$o" | grep -q "libgtk-4"; then echo "GTK4"
    elif echo "$o" | grep -q "libgtk-3"; then echo "GTK3"
    elif echo "$o" | grep -q "libQt6"; then echo "Qt6"
    elif echo "$o" | grep -q "libQt5"; then echo "Qt5"
    elif echo "$o" | grep -q "libSDL"; then echo "SDL"
    else echo ""
    fi
}

# ─── Sugerencia de red ──────────────────────────────────────────────────────
# ─── Network suggestion ─────────────────────────────────────────────────────
# net_suggests <bin> — 0 si la app parece necesitar red.
# net_suggests <bin> — 0 if the app seems to need network.
net_suggests() {
    local bin="$1" o
    o=$(ldd "$bin" 2>/dev/null || true)
    if echo "$o" | grep -qE "libcurl|libssl|libcrypto|libgnutls|libsoup|libneon|libhttp|libmicrohttpd|libssh|libwebsockets"; then
        return 0
    fi
    case "$(basename "$bin")" in
        firefox*|chrome*|chromium*|brave*|thunderbird*|vivaldi*|opera*|\
        curl|wget|ssh|scp|sftp|rsync|ftp|nc|ncat|nmap|telnet|\
        git|hg|svn|npm|yarn|pnpm|pip|pip3|python*|node|deno|bun|\
        transmission*|deluge*|qbittorrent*|aria2c|yt-dlp|youtube-dl|\
        discord*|slack*|telegram*|signal*|element*|\
        spotify*|zoom|teams|skype|anydesk|remmina|syncthing|dropbox)
            return 0
            ;;
    esac
    if command -v strings &>/dev/null; then
        if strings -n 8 "$bin" 2>/dev/null | grep -qE "https?://[a-zA-Z]"; then
            return 0
        fi
        if strings -n 8 "$bin" 2>/dev/null | grep -qE "^SSL_(connect|read|write)$|^socket$|^connect$"; then
            return 0
        fi
    fi
    return 1
}

# ─── Resolución de binarios ─────────────────────────────────────────────────
# ─── Binary resolution ──────────────────────────────────────────────────────
# resolve_bin <path> — resuelve symlinks y wrappers shell.
# resolve_bin <path> — resolves symlinks and shell wrappers.
resolve_bin() {
    local b="$1" r
    r=$(readlink -f "$b" 2>/dev/null || echo "$b")
    local ft
    ft=$(file -b "$r" 2>/dev/null || echo "")
    if echo "$ft" | grep -qE "shell script|text"; then
        local t
        t=$(grep -oE '^[[:space:]]*exec[[:space:]]+[^[:space:]]+' "$r" 2>/dev/null | head -1 | awk '{print $2}')
        [[ -n "$t" && -x "$t" ]] && r=$(readlink -f "$t" 2>/dev/null || echo "$t")
    fi
    echo "$r"
}

# ─── Encontrar binario dentro de un bundle ──────────────────────────────────
# ─── Find binary inside a bundle ────────────────────────────────────────────
find_bin_in_bundle() {
    local orig="$1"
    local bd="$2"
    local resolved
    resolved=$(readlink -f "$orig" 2>/dev/null || echo "$orig")
    if [[ "$resolved" == "$bd"/* && -e "$resolved" ]]; then
        echo "${resolved#$bd/}"
        return 0
    fi
    local base
    base=$(basename "$orig")
    local hit
    hit=$(find "$bd" -maxdepth 4 \( -name "$base" -o -name "${base}.bin" \) \( -type f -o -type l \) 2>/dev/null | head -1)
    if [[ -n "$hit" ]]; then
        local t
        t=$(readlink -f "$hit" 2>/dev/null || echo "$hit")
        if [[ -n "$t" && "$t" == "$bd"/* ]] && file -b "$t" 2>/dev/null | grep -q ELF; then
            echo "${t#$bd/}"; return 0
        fi
    fi
    local best="" bs=0
    while IFS= read -r f; do
        [[ -f "$f" && -x "$f" ]] || continue
        local fb
        fb=$(basename "$f")
        case "$fb" in
            *.so|*.so.*|lib*.so*|*.sh|*.py|*.pl) continue ;;
            *crashpad*|*-sandbox|*helper*|*Helper) continue ;;
            *.desktop|*.png|*.svg|*.json|*.xml) continue ;;
        esac
        file -b "$f" 2>/dev/null | grep -q ELF || continue
        local s
        s=$(stat -c%s "$f" 2>/dev/null || echo 0)
        if [[ $s -gt $bs ]]; then bs=$s; best="${f#$bd/}"; fi
    done < <(find "$bd" -maxdepth 4 -type f -executable 2>/dev/null)
    [[ -n "$best" ]] && { echo "$best"; return 0; }
    while IFS= read -r l; do
        local t
        t=$(readlink -f "$l" 2>/dev/null)
        if [[ -n "$t" && "$t" == "$bd"/* ]] && file -b "$t" 2>/dev/null | grep -q ELF; then
            echo "${t#$bd/}"; return 0
        fi
    done < <(find "$bd" -maxdepth 2 -type l 2>/dev/null)
    echo ""
    return 1
}

# ─── Encontrar bundle dir ───────────────────────────────────────────────────
# ─── Find bundle dir ────────────────────────────────────────────────────────
find_bundle_dir() {
    local b="$1" nm="$2" r
    r=$(resolve_bin "$b")
    local pfx
    for pfx in /opt /usr/lib /usr/lib64 /usr/share; do
        if [[ "$r" == $pfx/* ]]; then
            local rel="${r#$pfx/}"
            local top="${rel%%/*}"
            local cand="$pfx/$top"
            case "$top" in
                bin|share|lib|lib64|local|applications) ;;
                *)
                    if [[ -d "$cand" ]]; then
                        local ds
                        ds=$(du -sb "$cand" 2>/dev/null | awk '{print $1}')
                        [[ -n "$ds" && "$ds" -gt 10485760 ]] && { echo "$cand"; return 0; }
                    fi
                    ;;
            esac
        fi
    done
    local nl="${nm,,}"
    nl="${nl// /-}"
    nl="${nl//./-}"
    local cs=(
        "/opt/$nl" "/opt/${nl//-/_}" "/opt/$nm"
        "/usr/lib/$nl" "/usr/lib64/$nl" "/usr/share/$nl"
    )
    local c
    for c in "${cs[@]}"; do
        if [[ -d "$c" ]]; then
            local ds
            ds=$(du -sb "$c" 2>/dev/null | awk '{print $1}')
            [[ -n "$ds" && "$ds" -gt 10485760 ]] && { echo "$c"; return 0; }
        fi
    done
    echo ""
    return 1
}

# ─── Cálculo de tamaño total ────────────────────────────────────────────────
# ─── Total size calculation ─────────────────────────────────────────────────
# calc_total <path> <bundle_dir>
# Siempre devuelve un entero no negativo por stdout.
# Always returns a non-negative integer on stdout.
calc_total() {
    local b="$1" bd="$2" n=""

    # Preferir tamaño del bundle dir si existe.
    # Prefer bundle dir size if it exists.
    if [[ -n "$bd" && -d "$bd" ]]; then
        n=$(du -sb "$bd" 2>/dev/null | awk '{print $1}')
        if [[ "$n" =~ ^[0-9]+$ && "$n" -gt 0 ]]; then
            printf '%s' "$n"
            return 0
        fi
    fi

    # Fallback: tamaño del binario.
    # Fallback: binary size.
    n=$(stat -c%s "$b" 2>/dev/null || true)
    if [[ "$n" =~ ^[0-9]+$ ]]; then
        printf '%s' "$n"
    else
        printf '0'
    fi
}

# ─── Registro de app ────────────────────────────────────────────────────────
# ─── App registration ───────────────────────────────────────────────────────
# Formato de APPS_MAP[b] / APPS_MAP[b] format:
#   name|path|category|size|ELF|app_id|GUI/CLI|toolkit|bundle_dir|total_bytes
reg_app() {
    local nm="$1" b="$2" cat="$3" aid="$4" gui="$5" tk="$6"

    # Evitar duplicados.
    # Avoid duplicates.
    [[ -n "${APPS_MAP[$b]+x}" ]] && return 1

    # Bundle dir (vacío si no aplica).
    # Bundle dir (empty if not applicable).
    local bd=""
    bd=$(find_bundle_dir "$b" "$nm" 2>/dev/null || echo "")

    # Tamaño: calc_total YA garantiza número.
    # Size: calc_total ALREADY guarantees a number.
    local tot
    tot=$(calc_total "$b" "$bd")

    # Guard defensivo: por si algo raro llegó hasta aquí.
    # Defensive guard: in case something weird got this far.
    [[ "$tot" =~ ^[0-9]+$ ]] || tot=0

    # Human size (también recibe número garantizado).
    # Human size (also receives guaranteed number).
    local sh
    sh=$(hs "$tot")

    APPS_MAP["$b"]="$nm|$b|$cat|$sh|ELF|$aid|$gui|$tk|$bd|$tot"
    APPS_LIST+=("$b")
    return 0
}

# ─── Escaneo de bundles ─────────────────────────────────────────────────────
# ─── Bundle scan ────────────────────────────────────────────────────────────
scan_bundles() {
    info "$(t L_SEARCHING) /opt y /usr/lib..."

    declare -A SYM_TO_BD=()
    local sym tgt
    for sym in /usr/bin/* /usr/local/bin/*; do
        [[ -L "$sym" ]] || continue
        tgt=$(readlink -f "$sym" 2>/dev/null)
        [[ -z "$tgt" ]] && continue
        local bd=""
        case "$tgt" in
            /opt/*)
                local rel="${tgt#/opt/}"
                local top="${rel%%/*}"
                [[ -d "/opt/$top" ]] && bd="/opt/$top"
                ;;
            /usr/lib/*|/usr/lib64/*)
                local pfx="/usr/lib"
                [[ "$tgt" == /usr/lib64/* ]] && pfx="/usr/lib64"
                local rel="${tgt#$pfx/}"
                local top="${rel%%/*}"
                case "$top" in
                    bin|sbin|share|lib|lib64|local|applications|pkgconfig|cmake|icons|fonts|themes|man|doc|info|licenses|systemd|dbus-1|mime|X11) continue ;;
                    python*|perl*|ruby*|node_modules|golang*) continue ;;
                    *-dev|*-doc|*-data|*-common|*-headers) continue ;;
                    x86_64-linux-gnu|i386-linux-gnu|aarch64-linux-gnu|arm-linux-gnueabihf) continue ;;
                esac
                [[ -d "$pfx/$top" ]] && bd="$pfx/$top"
                ;;
        esac
        [[ -z "$bd" ]] && continue
        [[ "$tgt" != "$bd"/* ]] && continue
        local ds
        ds=$(du -sb "$bd" 2>/dev/null | awk '{print $1}')
        [[ -z "$ds" || "$ds" -lt 5242880 ]] && continue
        SYM_TO_BD["$sym"]="$bd"
    done

    declare -A BD_TO_SYM=()
    for sym in "${!SYM_TO_BD[@]}"; do
        local bd="${SYM_TO_BD[$sym]}"
        if [[ -z "${BD_TO_SYM[$bd]+x}" ]]; then
            BD_TO_SYM["$bd"]="$sym"
        else
            [[ ${#sym} -lt ${#BD_TO_SYM[$bd]} ]] && BD_TO_SYM["$bd"]="$sym"
        fi
    done

    local bds=()
    for bd in "${!BD_TO_SYM[@]}"; do bds+=("$bd"); done
    local _bsorted
    _bsorted=$(for bd in "${bds[@]}"; do echo "${#bd}|$bd"; done | sort -n -t'|' -k1 | cut -d'|' -f2)
    bds=()
    [[ -n "$_bsorted" ]] && mapfile -t bds <<< "$_bsorted"
    local finals=()
    for bd in "${bds[@]}"; do
        local is_child=0 p
        for p in "${finals[@]}"; do
            if [[ "$bd" == "$p" || "$bd" == "$p"/* ]]; then is_child=1; break; fi
        done
        [[ $is_child -eq 0 ]] && finals+=("$bd")
    done

    local found=0
    for bd in "${finals[@]}"; do
        local s="${BD_TO_SYM[$bd]}"
        [[ -n "${APPS_MAP[$s]+x}" ]] && continue
        local ds
        ds=$(du -sb "$bd" 2>/dev/null | awk '{print $1}')
        [[ -z "$ds" || "$ds" -lt 5242880 ]] && continue
        local name
        name=$(basename "$s")
        name="$(tr '[:lower:]' '[:upper:]' <<< "${name:0:1}")${name:1}"
        local real
        real=$(readlink -f "$s" 2>/dev/null || echo "$s")
        [[ -f "$real" ]] || real="$s"
        local g="CLI"
        gui_app "$real" && g="GUI"
        [[ -n "${GUI_OF[$s]:-}" ]] && g="${GUI_OF[$s]}"
        local tk
        tk=$(toolkit "$real")
        [[ "$g" == "CLI" ]] && tk=""
        local aid
        aid="org.bundle.$(basename "$bd")"
        aid=$(echo "$aid" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9-.' | sed 's/--*/-/g')
        local sh
        sh=$(hs "$ds")
        APPS_MAP["$s"]="$name|$s|Other|$sh|ELF|$aid|$g|$tk|$bd|$ds"
        APPS_LIST+=("$s")
        found=$((found + 1))
        det "$(t L_BUNDLE): $name  $sh  $bd"
    done

    if [[ -d /opt ]]; then
        local od
        for od in /opt/*/; do
            [[ -d "$od" ]] || continue
            od="${od%/}"
            local already=0 k
            for k in "${APPS_LIST[@]}"; do
                local pbd
                pbd=$(echo "${APPS_MAP[$k]}" | awk -F'|' '{print $9}')
                [[ "$pbd" == "$od" ]] && { already=1; break; }
            done
            [[ $already -eq 1 ]] && continue
            local ds
            ds=$(du -sb "$od" 2>/dev/null | awk '{print $1}')
            [[ -z "$ds" || "$ds" -lt 5242880 ]] && continue
            local mb
            mb=$(find "$od" -maxdepth 4 -type f -executable 2>/dev/null | \
                while IFS= read -r f; do
                    local fb
                    fb=$(basename "$f")
                    case "$fb" in
                        *.so|*.so.*|lib*.so*|*crashpad*|*-sandbox|*helper*|*.sh|*.py) continue ;;
                    esac
                    file -b "$f" 2>/dev/null | grep -q ELF && echo "$(stat -c%s "$f" 2>/dev/null || echo 0)|$f"
                done | sort -rn | head -1 | cut -d'|' -f2)
            [[ -z "$mb" ]] && continue
            local name
            name=$(basename "$od")
            name="$(tr '[:lower:]' '[:upper:]' <<< "${name:0:1}")${name:1}"
            local g="CLI"
            gui_app "$mb" && g="GUI"
            local tk
            tk=$(toolkit "$mb")
            [[ "$g" == "CLI" ]] && tk=""
            local aid
            aid="org.bundle.$(basename "$od")"
            aid=$(echo "$aid" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9-.' | sed 's/--*/-/g')
            local sh
            sh=$(hs "$ds")
            inherit_meta "$mb"
            [[ -n "${GUI_OF[$mb]:-}" ]] && g="${GUI_OF[$mb]}"
            APPS_MAP["$mb"]="$name|$mb|Other|$sh|ELF|$aid|$g|$tk|$od|$ds"
            APPS_LIST+=("$mb")
            found=$((found + 1))
            det "$(t L_BUNDLE): $name  $sh  $od"
        done
    fi

    [[ $found -gt 0 ]] && ok "Bundles: $found"
}

# ─── Escaneo de .desktop ────────────────────────────────────────────────────
# ─── .desktop scan ──────────────────────────────────────────────────────────
scan_desktop() {
    info "$(t L_SEARCHING) .desktop..."
    local dirs=(
        "/usr/share/applications"
        "/usr/local/share/applications"
        "$HOME/.local/share/applications"
    )
    local tot=0 d
    for d in "${dirs[@]}"; do
        [[ -d "$d" ]] && tot=$((tot + $(find "$d" -maxdepth 1 -name "*.desktop" 2>/dev/null | wc -l)))
    done
    [[ $tot -eq 0 ]] && tot=1
    local n=0
    for d in "${dirs[@]}"; do
        [[ -d "$d" ]] || continue
        while IFS= read -r df; do
            n=$((n + 1))
            progress "$n" "$tot" "desktop"
            local name="" ec="" cat="" nd="" icon="" term=""
            local ln
            while IFS= read -r ln; do
                case "$ln" in
                    Name=*) [[ -z "$name" ]] && name="${ln#Name=}" ;;
                    Exec=*) [[ -z "$ec" ]] && ec="${ln#Exec=}" ;;
                    Categories=*) cat="${ln#Categories=}" ;;
                    Icon=*) icon="${ln#Icon=}" ;;
                    Terminal=*) term="${ln#Terminal=}" ;;
                    NoDisplay=true) nd="true" ;;
                esac
            done < "$df"
            [[ "$nd" == "true" || -z "$ec" || -z "$name" ]] && continue
            ec=$(echo "$ec" | sed -E 's/%[UuFfikc]//g')
            [[ "$ec" == env\ * ]] && ec=$(echo "$ec" | sed -E 's/^env\s+//' | sed -E 's/\S+=\S+\s+//g')
            local b
            b=$(echo "$ec" | awk '{print $1}' | sed 's/^"//;s/"$//')
            [[ -z "$b" ]] && continue
            local bp=""
            if [[ "$b" == /* ]]; then
                [[ -e "$b" ]] && bp="$b"
            else
                bp=$(command -v "$b" 2>/dev/null || true)
            fi
            [[ -z "$bp" || ! -f "$bp" || ! -x "$bp" ]] && continue
            local ft
            ft=$(file -b "$bp" 2>/dev/null || echo "")
            echo "$ft" | grep -qE "ELF|shell script|symbolic link" || continue
            local c="Other"
            if [[ "$cat" == *"Game"* ]]; then c="Games"
            elif [[ "$cat" == *"Audio"* || "$cat" == *"Video"* ]]; then c="Media"
            elif [[ "$cat" == *"Office"* || "$cat" == *"TextEditor"* ]]; then c="Office"
            elif [[ "$cat" == *"Development"* ]]; then c="DevTools"
            elif [[ "$cat" == *"Network"* || "$cat" == *"WebBrowser"* ]]; then c="Network"
            elif [[ "$cat" == *"Graphics"* ]]; then c="Graphics"
            elif [[ "$cat" == *"System"* || "$cat" == *"Settings"* ]]; then c="System"
            elif [[ "$cat" == *"Utility"* ]]; then c="Utilities"
            fi
            # El .desktop manda: Terminal=true → app de terminal; si no, GUI.
            # (gui_app/ldd falla con apps que cargan el toolkit con dlopen:
            #  Firefox no muestra libgtk en ldd y se marcaba CLI.)
            # The .desktop decides: Terminal=true → terminal app; else GUI.
            # (gui_app/ldd fails for apps that dlopen their toolkit: Firefox
            #  shows no libgtk in ldd and was tagged CLI.)
            local g="GUI"
            [[ "$term" == "true" ]] && g="CLI"
            GUI_OF[$bp]="$g"
            local tk
            tk=$(toolkit "$bp")
            local aid
            aid="${name// /-}"
            aid=$(echo "$aid" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9-' | sed 's/--*/-/g;s/^-//;s/-$//')
            [[ -z "$aid" ]] && aid="app-$(echo "$bp" | md5sum | cut -c1-8)"
            reg_app "$name" "$bp" "$c" "$aid" "$g" "$tk"
            # Icono y categoría reales de la app (.desktop), para la entrada de
            # menú generada.
            # The app's real icon and categories (.desktop), for the generated
            # menu entry.
            [[ -n "$cat" ]] && CAT_OF[$bp]="$cat"
            local iconp=""
            [[ -n "$icon" ]] && iconp=$(resolve_icon "$icon")
            [[ -n "$iconp" ]] && ICON_OF[$bp]="$iconp"
        done < <(find "$d" -maxdepth 1 -name "*.desktop" 2>/dev/null)
    done
    echo ""
}

# ─── Detección completa ─────────────────────────────────────────────────────
# ─── Full detection ─────────────────────────────────────────────────────────
detect_all() {
    APPS_MAP=()
    APPS_LIST=()
    APPS_SORTED=()

    info "$(t L_SEARCHING)..."
    scan_desktop
    info "Binarios comunes..."
    local apps=(htop btop vim nano nmap vlc mpv gimp inkscape firefox chromium
                blender libreoffice obs-studio steam discord transmission
                thunderbird brave-browser google-chrome code)
    local fe=0 a
    for a in "${apps[@]}"; do
        local bp
        bp=$(command -v "$a" 2>/dev/null || true)
        [[ -z "$bp" || ! -e "$bp" ]] && continue
        [[ -n "${APPS_MAP[$bp]+x}" ]] && continue
        local ft
        ft=$(file -b "$bp" 2>/dev/null || echo "")
        echo "$ft" | grep -qE "ELF|shell script|symbolic link" || continue
        local g="CLI"
        gui_app "$bp" && g="GUI"
        local tk
        tk=$(toolkit "$bp")
        inherit_meta "$bp"
        reg_app "$a" "$bp" "Utilities" "org.$a.$a" "$g" "$tk" && fe=$((fe + 1))
    done
    [[ $fe -gt 0 ]] && det "Adicionales: $fe"
    scan_bundles

    local _sorted
    _sorted=$(for b in "${APPS_LIST[@]}"; do
        local tt
        tt=$(echo "${APPS_MAP[$b]}" | awk -F'|' '{print $10}')
        [[ -z "$tt" ]] && tt=$(stat -c%s "$b" 2>/dev/null || echo 0)
        echo "$tt|$b"
    done | sort -rn | cut -d'|' -f2)
    APPS_SORTED=()
    [[ -n "$_sorted" ]] && mapfile -t APPS_SORTED <<< "$_sorted"

    ok "$(t L_DETECTED): ${#APPS_SORTED[@]}"
}

# ─── Campo de APPS_MAP ──────────────────────────────────────────────────────
# ─── APPS_MAP field ─────────────────────────────────────────────────────────
fld() { echo "$1" | awk -F'|' -v i="$2" '{print $i}'; }

# ─── Top de apps por tamaño ─────────────────────────────────────────────────
# ─── Top apps by size ───────────────────────────────────────────────────────
select_top() {
    local limit="${1:-15}" minb="${2:-0}"
    [[ ${#APPS_SORTED[@]} -eq 0 ]] && { fail "$(t L_NO_RESULTS)"; return 1; }
    hdr "$(t L_TOP)"

    local cand=() b
    for b in "${APPS_SORTED[@]}"; do
        local s
        s=$(fld "${APPS_MAP[$b]}" 10)
        [[ -z "$s" ]] && s=$(stat -c%s "$b" 2>/dev/null || echo 0)
        [[ "$s" -lt "$minb" ]] && continue
        cand+=("$b")
        [[ ${#cand[@]} -ge $limit ]] && break
    done
    [[ ${#cand[@]} -eq 0 ]] && { warn "$(t L_NO_RESULTS)"; return 1; }

    local fm=""
    [[ $minb -gt 0 ]] && fm=" (>= $(hs "$minb"))"
    echo -e "  ${BD}Top ${#cand[@]}${fm}:${N}"
    echo -e "  ${DM}${HR_T}${N}"
    local i
    for i in "${!cand[@]}"; do
        b="${cand[$i]}"
        local inf="${APPS_MAP[$b]}"
        local nm s g tk bd
        nm=$(fld "$inf" 1); s=$(fld "$inf" 4); g=$(fld "$inf" 7)
        tk=$(fld "$inf" 8); bd=$(fld "$inf" 9)
        local dn="$nm"
        [[ ${#dn} -gt 28 ]] && dn="${dn:0:25}..."
        local tag=""
        if [[ -n "$bd" ]]; then tag=" ${M}${BD}[$(t L_BUNDLE)]${N}"
        elif [[ "$g" == "GUI" ]]; then tag=" ${G}[GUI${tk:+/$tk}]${N}"
        else tag=" ${DM}[CLI]${N}"
        fi
        printf "  ${C}%3d${N}) %-28s ${BD}%9s${N}%b\n" $((i + 1)) "$dn" "$s" "$tag"
    done
    echo -e "  ${DM}${HR_T}${N}"
    echo ""
    echo -e "  ${BD}N${N} número · ${Y}f${N} filtrar MB · ${Y}b${N} buscar · ${Y}r${N} más · ${Y}q${N} cancelar"
    echo ""

    while true; do
        echo -en "  ${BD}> ${N}"
        local c
        read -r c
        case "$c" in
            q|Q) return 1 ;;
            f|F)
                local mb
                mb=$(ask_txt "$(t L_FILTER_MB)")
                [[ -z "$mb" ]] && continue
                [[ ! "$mb" =~ ^[0-9]+$ ]] && { warn "$(t L_INVALID)"; continue; }
                select_top "$limit" "$((mb * 1048576))"
                return $?
                ;;
            b|B) if search_app; then return 0; fi ;;
            r|R) select_top "$((limit * 2))" "$minb"; return $? ;;
            [0-9]*)
                if [[ "$c" -ge 1 && "$c" -le "${#cand[@]}" ]]; then
                    CURRENT_BIN="${cand[$((c - 1))]}"
                    CURRENT_INFO="${APPS_MAP[$CURRENT_BIN]}"
                    return 0
                else
                    warn "Rango 1-${#cand[@]}"
                fi
                ;;
            *) warn "$(t L_INVALID)" ;;
        esac
    done
}

# ─── Buscar app ─────────────────────────────────────────────────────────────
# ─── Search app ─────────────────────────────────────────────────────────────
search_app() {
    echo ""
    local q
    q=$(ask_txt "$(t L_SEARCH_PROMPT)")
    [[ -z "$q" ]] && return 1
    q=$(echo "$q" | tr '[:upper:]' '[:lower:]')
    local res=() b
    for b in "${APPS_SORTED[@]}"; do
        local inf="${APPS_MAP[$b]}"
        local nm p aid
        nm=$(fld "$inf" 1); p=$(fld "$inf" 2); aid=$(fld "$inf" 6)
        if echo "$nm $p $aid" | tr '[:upper:]' '[:lower:]' | grep -q "$q"; then
            res+=("$b")
        fi
    done
    [[ ${#res[@]} -eq 0 ]] && { warn "$(t L_NO_RESULTS)"; return 1; }
    echo ""
    echo -e "  ${BD}${#res[@]} results${N}"
    echo -e "  ${DM}${HR_T}${N}"
    local i
    for i in "${!res[@]}"; do
        b="${res[$i]}"
        local inf="${APPS_MAP[$b]}"
        local nm s bd
        nm=$(fld "$inf" 1); s=$(fld "$inf" 4); bd=$(fld "$inf" 9)
        local tag=""
        [[ -n "$bd" ]] && tag=" ${M}[$(t L_BUNDLE)]${N}"
        printf "  ${C}%3d${N}) %-35s ${BD}%9s${N}%b\n" $((i + 1)) "$nm" "$s" "$tag"
    done
    echo ""
    echo -en "  ${BD}> 1-${#res[@]}, q: ${N}"
    local c
    read -r c
    [[ "$c" == "q" ]] && return 1
    if [[ "$c" =~ ^[0-9]+$ && "$c" -ge 1 && "$c" -le "${#res[@]}" ]]; then
        CURRENT_BIN="${res[$((c - 1))]}"
        CURRENT_INFO="${APPS_MAP[$CURRENT_BIN]}"
        return 0
    fi
    return 1
}

# ─── Detalles de la app ─────────────────────────────────────────────────────
# ─── App details ────────────────────────────────────────────────────────────
show_details() {
    local inf="$CURRENT_INFO"
    local nm p c s t aid gui tk bd
    nm=$(fld "$inf" 1); p=$(fld "$inf" 2); c=$(fld "$inf" 3)
    s=$(fld "$inf" 4); t=$(fld "$inf" 5); aid=$(fld "$inf" 6)
    gui=$(fld "$inf" 7); tk=$(fld "$inf" 8); bd=$(fld "$inf" 9)

    local net_hint="no"
    net_suggests "$p" && net_hint="sí"

    hdr "$(t L_APP_ID)"
    echo -e "  ${BD}Name:${N}      $nm"
    echo -e "  ${BD}Path:${N}      $p"
    echo -e "  ${BD}Category:${N}  $c"
    echo -e "  ${BD}Size:${N}      ${BD}$s${N}"
    echo -e "  ${BD}Type:${N}      $gui ($tk)"
    echo -e "  ${BD}App ID:${N}    $aid"
    echo -e "  ${BD}Network:${N}   ${DM}hint: $net_hint${N}"
    if [[ -n "$bd" ]]; then
        echo -e "  ${BD}Bundle:${N}    ${M}$bd${N}"
    fi
    echo ""
}

# ─── Configuración interactiva ──────────────────────────────────────────────
# ─── Interactive configuration ──────────────────────────────────────────────
configure_pack() {
    local inf="$CURRENT_INFO"
    local nm p aid gui tk bd s
    nm=$(fld "$inf" 1); p=$(fld "$inf" 2); aid=$(fld "$inf" 6)
    gui=$(fld "$inf" 7); tk=$(fld "$inf" 8); bd=$(fld "$inf" 9); s=$(fld "$inf" 4)

    hdr "$(t L_APP_ID)"
    echo -en "  [${DM}$aid${N}]: "
    read -r new_id
    CURRENT_APP_ID="${new_id:-$aid}"
    CURRENT_APP_ID=$(echo "$CURRENT_APP_ID" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9.-' | sed 's/--*/-/g;s/^-//;s/-$//')
    [[ -z "$CURRENT_APP_ID" ]] && CURRENT_APP_ID="org.app.unknown"

    echo ""
    echo -e "  ${BD}$(t L_VERSION):${N}"
    local dv="1.0.0"
    if [[ -x "$p" ]]; then
        local v
        v=$("$p" --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1 || true)
        [[ -n "$v" ]] && dv="$v"
    fi
    echo -en "  [${DM}$dv${N}]: "
    read -r nv
    CURRENT_VERSION="${nv:-$dv}"

    echo ""
    echo -e "  ${BD}$(t L_DESCRIPTION):${N}"
    echo -en "  [${DM}$nm${N}]: "
    read -r nd
    CURRENT_DESC="${nd:-$nm}"

    CURRENT_IS_GUI="$gui"
    CURRENT_TOOLKIT="$tk"
    CURRENT_BUNDLE_DIR="$bd"
    # Icono/categoría reales de la app (vacíos si no hay .desktop).
    # The app's real icon/categories (empty if there is no .desktop).
    CURRENT_ICON="${ICON_OF[$p]:-}"
    CURRENT_CATEGORIES="${CAT_OF[$p]:-}"

    # ─── Pregunta de red ────────────────────────────────────────────────────
    # ─── Network question ───────────────────────────────────────────────────
    local net_default="n" net_hint="no"
    if net_suggests "$p"; then
        net_default="s"
        net_hint="sí"
    fi
    echo ""
    echo -e "  ${BD}$(_tt L_NETWORK "Acceso a red"):${N}"
    echo -e "     ${DM}Heuristic: this app $([ "$net_hint" = "sí" ] && echo "seems to NEED" || echo "seems NOT to need") network.${N}"
    if ask_yn "$(_tt L_NETWORK_PROMPT "¿Permitir red?")" "$net_default"; then
        CURRENT_NETWORK="true"
        det "$(_tt L_NETWORK_ON "Red: ACTIVADA")"
    else
        CURRENT_NETWORK="false"
        det "$(_tt L_NETWORK_OFF "Red: desactivada (aislada)")"
    fi

    # ─── Modo de empaquetado ────────────────────────────────────────────────
    # ─── Packaging mode ─────────────────────────────────────────────────────
    echo ""
    echo -e "  ${BD}$(t L_MODE):${N}"
    if [[ -n "$bd" ]]; then
        echo -e "     ${C}1${N}) $(t L_NORMAL)"
        echo -e "     ${C}2${N}) $(t L_PORTABLE)"
        echo -e "     ${C}3${N}) $(t L_MODULE)"
        echo -e "     ${C}4${N}) ${M}$(t L_BUNDLE)${N} ${G}<-- recomendado${N}"
        echo -e "     ${DM}$bd ($s)${N}"
        echo ""
        echo -en "  ${BD}[1/2/3/4] (default 4): ${N}"
        read -r pm
        CURRENT_PACK_MODE="${pm:-4}"
    else
        echo -e "     ${C}1${N}) $(t L_NORMAL)"
        echo -e "     ${C}2${N}) $(t L_PORTABLE) ${G}<-- recomendado${N}"
        echo -e "     ${C}3${N}) $(t L_MODULE)"
        echo ""
        echo -en "  ${BD}[1/2/3] (default 2): ${N}"
        read -r pm
        CURRENT_PACK_MODE="${pm:-2}"
    fi

    # ─── Celdas (módulos reutilizables) ─────────────────────────────────────
    # ─── Cells (reusable modules) ───────────────────────────────────────────
    echo ""
    # En Normal/Portable las libs de la app se convierten en celdas solas; este
    # campo es solo para AÑADIR celdas ya existentes (se listan las disponibles).
    # In Normal/Portable the app's libs become cells by themselves; this field is
    # only to ADD existing cells (the available ones are listed).
    local avail=() d
    if [[ -d "$PACKBOX_MODS_DIR" ]]; then
        for d in "$PACKBOX_MODS_DIR"/*/*/; do
            [[ -d "$d" ]] && avail+=("$(basename "$(dirname "$d")")@$(basename "$d")")
        done
    fi
    echo -e "  ${BD}$(_tt L_CELLS "Celdas (name@version, separadas por coma; vacío = ninguna")${N}"
    if (( ${#avail[@]} > 0 )); then
        echo -e "     ${DM}$(_tt L_CELLS_AVAIL "disponibles")${N}: ${avail[*]}"
    else
        echo -e "     ${DM}$(_tt L_CELLS_HINT "en Normal/Portable las libs se convierten en celdas automáticamente; aquí solo se añaden celdas existentes")${N}"
    fi
    echo -en "  ${DM}[$(_tt L_NONE "ninguna")]${N}: "
    read -r cm
    CURRENT_MODS="${cm// /}"

    echo ""
    ok "Config OK  (net: $CURRENT_NETWORK)"
}
