#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
# EN: Packbox Packager v0.1.0 Alpha.
# ES: Empaquetador de Packbox v0.1.0 Alpha.
#
# EN: Detects installed applications (desktop entries, common
#     binaries, /opt bundles), lets the user pick one, and packs
#     it in one of four modes: Normal, Portable, Module, Bundle.
#     Also exports/imports .pbox archives and uninstalls apps.
# ES: Detecta aplicaciones instaladas (entradas de menú,
#     binarios comunes, bundles en /opt), permite elegir una y la
#     empaqueta en uno de cuatro modos: Normal, Portable, Módulo,
#     Bundle. También exporta/importa archivos .pbox y desinstala.
# ═══════════════════════════════════════════════════════════════

# ───────────────────────────────────────────────────────────────
# EN: Force Bash and enable strict mode.
# ES: Fuerza Bash y activa modo estricto.
# ───────────────────────────────────────────────────────────────
if [ -z "$BASH_VERSION" ]; then echo "Error: usa bash."; exec bash "$0" "$@"; fi
set -uo pipefail

# EN: Directory of this script (used to locate packbox-i18n.sh).
# ES: Directorio de este script (usado para localizar packbox-i18n.sh).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ═══════════════════════════════════════════════════════════════
# EN: Paths.
# ES: Rutas.
# ═══════════════════════════════════════════════════════════════
PACKBOX_HOME="$HOME/.local/share/packbox"                    # EN: runtime data | ES: datos de runtime
APPS_DIR="$PACKBOX_HOME/apps"                                # EN: installed apps | ES: apps instaladas
EXPORTS_DIR="$PACKBOX_HOME/exports"                          # EN: .pbox files | ES: archivos .pbox
ICONS_DIR="$HOME/.local/share/icons/hicolor/256x256/apps"    # EN: per-app icons | ES: iconos por app
DESKTOP_DIR="$HOME/.local/share/applications"                # EN: .desktop entries | ES: entradas .desktop
PACKBOX_LANG_DIR="$HOME/.config/packbox/lang"                # EN: i18n files | ES: archivos i18n

# ───────────────────────────────────────────────────────────────
# EN: Dual detection of the bin dir: new layout (~/.packbox) is
#     preferred; legacy layout (~/packbox) is a fallback.
# ES: Detección dual del bin dir: se prefiere el layout nuevo
#     (~/.packbox); el layout antiguo (~/packbox) es fallback.
# ───────────────────────────────────────────────────────────────
if [[ -d "$HOME/.packbox/bin" ]]; then
    PACKBOX_BIN_DIR="$HOME/.packbox/bin"
elif [[ -d "$HOME/packbox/bin" ]]; then
    PACKBOX_BIN_DIR="$HOME/packbox/bin"
else
    PACKBOX_BIN_DIR="$HOME/.packbox/bin"
fi

# ═══════════════════════════════════════════════════════════════
# EN: Load shared i18n (packbox-i18n.sh).
# ES: Carga la i18n compartida (packbox-i18n.sh).
# ═══════════════════════════════════════════════════════════════
_I18N_FILE="$SCRIPT_DIR/packbox-i18n.sh"
if [[ ! -f "$_I18N_FILE" ]]; then
    echo "❌ Falta packbox-i18n.sh en $SCRIPT_DIR"
    echo "   Descarga el repositorio completo de Packbox."
    exit 1
fi
# shellcheck disable=SC1090
source "$_I18N_FILE"

# ═══════════════════════════════════════════════════════════════
# EN: Absolute paths to the compiled Go binaries.
# ES: Rutas absolutas a los binarios Go compilados.
# ═══════════════════════════════════════════════════════════════
PACK_BIN="$PACKBOX_BIN_DIR/packbox-pack"
INSTALL_BIN="$PACKBOX_BIN_DIR/packbox-install"
RUN_BIN="$PACKBOX_BIN_DIR/packbox-run"
LIST_BIN="$PACKBOX_BIN_DIR/packbox-list"
REMOVE_BIN="$PACKBOX_BIN_DIR/packbox-remove"
GC_BIN="$PACKBOX_BIN_DIR/packbox-gc"
EXPORT_BIN="$PACKBOX_BIN_DIR/packbox-export"
IMPORT_BIN="$PACKBOX_BIN_DIR/packbox-import"
MODULE_BIN="$PACKBOX_BIN_DIR/packbox-module"

# ═══════════════════════════════════════════════════════════════
# EN: UI — detect UTF-8 to choose between fancy and ASCII symbols.
# ES: UI — detecta UTF-8 para elegir entre símbolos bonitos y ASCII.
# ═══════════════════════════════════════════════════════════════
_UTF8=0
case "${LC_ALL:-}${LC_CTYPE:-}${LANG:-}" in
    *UTF-8*|*utf-8*|*UTF8*|*utf8*) _UTF8=1 ;;
esac
if [[ $_UTF8 -eq 1 ]]; then
    HR="━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    HR_T="───────────────────────────────────────────────────────────────"
    ARROW="→"; BULLET="·"; PB_F="█"; PB_E="░"; CHK="✓"; XMK="✗"
else
    HR="==============================================================="
    HR_T="---------------------------------------------------------------"
    ARROW="->"; BULLET="*"; PB_F="#"; PB_E="-"; CHK="+"; XMK="x"
fi

# ═══════════════════════════════════════════════════════════════
# EN: ANSI colors — only when stdout is a TTY.
# ES: Colores ANSI — solo si stdout es una TTY.
# ═══════════════════════════════════════════════════════════════
if [[ -t 1 ]]; then
    R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; B='\033[0;34m'
    C='\033[0;36m'; M='\033[0;35m'; BD='\033[1m'; DM='\033[2m'; N='\033[0m'
else
    R=''; G=''; Y=''; B=''; C=''; M=''; BD=''; DM=''; N=''
fi

# ═══════════════════════════════════════════════════════════════
# EN: Terminal output helpers.
# ES: Helpers de salida de terminal.
# ═══════════════════════════════════════════════════════════════
info()   { echo -e "  ${B}${BULLET}${N}  ${1:-}"; }                 # EN: info | ES: info
ok()     { echo -e "  ${G}${CHK}${N}  ${1:-}"; }                    # EN: success | ES: éxito
warn()   { echo -e "  ${Y}!${N}  ${1:-}"; }                          # EN: warning | ES: aviso
err()    { echo -e "  ${R}${XMK}${N}  ${BD}${1:-}${N}"; exit 1; }    # EN: fatal | ES: fatal
det()    { echo -e "     ${DM}${ARROW} ${1:-}${N}"; }                # EN: detail | ES: detalle

# EN: Section header. | ES: Cabecera de sección.
hdr() {
    echo ""
    echo -e "${C}${BD}${HR_T}${N}"
    echo -e "${C}${BD}  ${ARROW} ${1:-}${N}"
    echo -e "${C}${BD}${HR_T}${N}"
    echo ""
}

# ═══════════════════════════════════════════════════════════════
# EN: ask_yn — yes/no prompt with a default.
# ES: ask_yn — pregunta sí/no con valor por defecto.
#
# EN: Accepts s/S/y/Y as yes. Empty → default.
# ES: Acepta s/S/y/Y como sí. Vacío → valor por defecto.
# ═══════════════════════════════════════════════════════════════
ask_yn() {
    local p="${1:-}" d="${2:-n}" r
    printf "  ${Y}?${N} %s" "$p"
    read -r -n 1 r
    echo
    [[ -z "$r" ]] && r="$d"
    [[ "$r" =~ ^[SsYy]$ ]]
}

# ═══════════════════════════════════════════════════════════════
# EN: ask_txt — free-text prompt, prints the reply.
# ES: ask_txt — prompt de texto libre, imprime la respuesta.
# ═══════════════════════════════════════════════════════════════
ask_txt() {
    printf "  ${Y}?${N} %s" "${1:-}"
    local r
    read -r r
    echo "$r"
}

# EN: Success box. | ES: Caja de éxito.
box_ok() {
    echo ""
    echo -e "  ${G}${HR}${N}"
    echo -e "  ${G}${BD}     ${1:-}${N}"
    echo -e "  ${G}${HR}${N}"
    echo ""
}

# ═══════════════════════════════════════════════════════════════
# EN: prog — draw a progress bar.
# ES: prog — dibuja una barra de progreso.
#
# EN: Args: current, total, message.
# ES: Args: actual, total, mensaje.
# ═══════════════════════════════════════════════════════════════
prog() {
    local c="${1:-0}"
    local t="${2:-100}"
    local m="${3:-...}"
    local w=35
    [[ $t -le 0 ]] && t=1
    local p=$((c * 100 / t))
    local f=$((c * w / t))
    local e=$((w - f))
    printf "\r  %s [" "$m"
    local i
    for ((i=0; i<f; i++)); do printf "%b" "$PB_F"; done
    printf "\033[2m"
    for ((i=0; i<e; i++)); do printf "%b" "$PB_E"; done
    printf "\033[0m] %3d%%\033[K" "$p"
    [[ $c -ge $t ]] && echo ""
}

# ═══════════════════════════════════════════════════════════════
# EN: hs — human-readable size (numfmt if available, else math).
# ES: hs — tamaño legible (numfmt si está, si no, cálculo).
# ═══════════════════════════════════════════════════════════════
hs() {
    local b="${1:-0}"
    if command -v numfmt &>/dev/null; then
        numfmt --to=iec "$b" 2>/dev/null && return
    fi
    if   [[ $b -ge 1073741824 ]]; then echo "$(( b / 1073741824 ))G"
    elif [[ $b -ge 1048576 ]];    then echo "$(( b / 1048576 ))M"
    elif [[ $b -ge 1024 ]];       then echo "$(( b / 1024 ))K"
    else echo "${b}B"
    fi
}

# EN: sz — file size in bytes (0 if missing). | ES: sz — tamaño en bytes (0 si no existe).
sz() { stat -c%s "$1" 2>/dev/null || echo 0; }

# ═══════════════════════════════════════════════════════════════
# EN: tmpdir — create a private temp dir.
# ES: tmpdir — crea un directorio temporal privado.
#
# EN: Prefers $XDG_RUNTIME_DIR (tmpfs, auto-cleaned on logout);
#     falls back to $PACKBOX_HOME/tmp. Mode 0700 always.
# ES: Prefiere $XDG_RUNTIME_DIR (tmpfs, se limpia al cerrar
#     sesión); cae a $PACKBOX_HOME/tmp. Modo 0700 siempre.
# ═══════════════════════════════════════════════════════════════
tmpdir() {
    local p="${1:-packbox}" base
    if [[ -n "${XDG_RUNTIME_DIR:-}" && -d "$XDG_RUNTIME_DIR" && -w "$XDG_RUNTIME_DIR" ]]; then
        base="$XDG_RUNTIME_DIR/packbox"
    else
        base="$PACKBOX_HOME/tmp"
    fi
    mkdir -p "$base" 2>/dev/null
    chmod 700 "$base" 2>/dev/null
    local d
    d=$(mktemp -d "$base/${p}-XXXXXX")
    chmod 700 "$d"
    echo "$d"
}

# ═══════════════════════════════════════════════════════════════
# EN: Cleanup registry and EXIT trap.
# ES: Registro de limpieza y trap de EXIT.
#
# EN: Every tmpdir() created during the session is registered
#     here and removed on exit (success or failure).
# ES: Cada tmpdir() creado en la sesión se registra aquí y se
#     elimina al salir (éxito o fallo).
# ═══════════════════════════════════════════════════════════════
declare -a CLEANUP=()

# EN: Register a path for cleanup. | ES: Registra una ruta para limpieza.
reg_cln() { CLEANUP+=("$1"); }

# EN: Unregister a path (already removed manually).
# ES: Desregistra una ruta (ya eliminada manualmente).
unreg_cln() {
    local x="$1" n=() y
    for y in "${CLEANUP[@]}"; do [[ "$y" != "$x" ]] && n+=("$y"); done
    CLEANUP=("${n[@]}")
}

# EN: On exit, wipe every registered temp dir that still exists.
# ES: Al salir, borra cada directorio temporal registrado que exista.
trap 'for d in "${CLEANUP[@]}"; do [[ -n "$d" && -d "$d" ]] && rm -rf "$d"; done' EXIT

# ═══════════════════════════════════════════════════════════════
# EN: show_banner — packager banner.
# ES: show_banner — banner del empaquetador.
# ═══════════════════════════════════════════════════════════════
show_banner() {
    clear
    echo -e "${BD}${C}"
    echo -e "  ${HR}"
    echo -e "   $(t L_PACKAGER_TITLE)"
    echo -e "   i18n · Bundles · Desktop · Compression"
    echo -e "  ${HR}"
    echo -e "${N}"
}
# ═══════════════════════════════════════════════════════════════
# EN: gui_app — check if a binary links against GUI libraries.
# ES: gui_app — comprueba si un binario enlaza con librerías GUI.
#
# EN: Uses ldd to look for GTK, Qt, X11, Wayland or SDL.
# ES: Usa ldd para buscar GTK, Qt, X11, Wayland o SDL.
# ═══════════════════════════════════════════════════════════════
gui_app() {
    local o
    o=$(ldd "$1" 2>/dev/null || true)
    echo "$o" | grep -qE "libgtk|libgdk|libQt|libX11|libwayland|libSDL"
}

# ═══════════════════════════════════════════════════════════════
# EN: toolkit — detect which GUI toolkit a binary uses.
# ES: toolkit — detecta qué toolkit GUI usa un binario.
#
# EN: Returns GTK4, GTK3, Qt6, Qt5, SDL, or empty for CLI.
# ES: Devuelve GTK4, GTK3, Qt6, Qt5, SDL, o vacío para CLI.
# ═══════════════════════════════════════════════════════════════
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

# ═══════════════════════════════════════════════════════════════
# EN: resolve_bin — resolve a binary path to the real ELF.
# ES: resolve_bin — resuelve la ruta del binario al ELF real.
#
# EN: Follows symlinks, and if the result is a shell script,
#     extracts the "exec <target>" line and resolves that too.
# ES: Sigue symlinks, y si el resultado es un shell script,
#     extrae la línea "exec <target>" y resuelve también esa.
# ═══════════════════════════════════════════════════════════════
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

# ═══════════════════════════════════════════════════════════════
# EN: find_bin_in_bundle — locate the real executable inside a
#     bundle directory, resolving symlinks and scoring candidates.
# ES: find_bin_in_bundle — localiza el ejecutable real dentro de
#     un bundle, resolviendo symlinks y puntuando candidatos.
#
# EN: Strategy (in order):
#       1. If the resolved path is inside the bundle, use it.
#       2. Search for a file named like the original or "<name>.bin".
#       3. Fallback: pick the biggest ELF executable, filtering
#          out .so, .sh, helper, crashpad, sandbox and helper bins.
#       4. Last resort: follow a symlink that points inside.
# ES: Estrategia (en orden):
#       1. Si la ruta resuelta está dentro del bundle, usarla.
#       2. Buscar un archivo con el mismo nombre o "<nombre>.bin".
#       3. Fallback: elegir el ELF ejecutable más grande,
#          filtrando .so, .sh, helper, crashpad, sandbox.
#       4. Último recurso: seguir un symlink que apunte dentro.
# ═══════════════════════════════════════════════════════════════
find_bin_in_bundle() {
    local orig="$1"
    local bd="$2"
    local resolved
    resolved=$(readlink -f "$orig" 2>/dev/null || echo "$orig")

    # EN: Step 1 — resolved path is inside the bundle.
    # ES: Paso 1 — la ruta resuelta está dentro del bundle.
    if [[ "$resolved" == "$bd"/* && -e "$resolved" ]]; then
        echo "${resolved#$bd/}"
        return 0
    fi

    # EN: Step 2 — search by basename or "<basename>.bin".
    # ES: Paso 2 — busca por basename o "<basename>.bin".
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

    # EN: Step 3 — biggest ELF executable, filtered.
    # ES: Paso 3 — ELF ejecutable más grande, filtrado.
    local best="" bs=0
    while IFS= read -r f; do
        [[ -f "$f" && -x "$f" ]] || continue
        local fb
        fb=$(basename "$f")
        case "$fb" in
            # EN: Skip libs, scripts, helpers and non-binaries.
            # ES: Omite libs, scripts, helpers y no-binarios.
            *.so|*.so.*|lib*.so*|*.sh|*.py|*.pl) continue ;;
            *crashpad*|*-sandbox|*helper*|*Helper) continue ;;
            *.desktop|*.png|*.svg|*.json|*.xml) continue ;;
        esac
        file -b "$f" 2>/dev/null | grep -q ELF || continue
        local s
        s=$(sz "$f")
        if [[ $s -gt $bs ]]; then bs=$s; best="${f#$bd/}"; fi
    done < <(find "$bd" -maxdepth 4 -type f -executable 2>/dev/null)
    [[ -n "$best" ]] && { echo "$best"; return 0; }

    # EN: Step 4 — follow a symlink that resolves inside the bundle.
    # ES: Paso 4 — sigue un symlink que resuelva dentro del bundle.
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

# ═══════════════════════════════════════════════════════════════
# EN: scan_bundles — find apps that live in /opt or /usr/lib
#     and are exposed via /usr/bin symlinks.
# ES: scan_bundles — encuentra apps en /opt o /usr/lib expuestas
#     mediante symlinks en /usr/bin.
#
# EN: Rationale: a bundle is a self-contained directory (like
#     /opt/firefox) with a launcher symlink in /usr/bin. We map
#     each symlink to its top-level bundle dir, filter by size
#     (>= 5 MB), and dedup so we only keep parent bundles.
# ES: Razón: un bundle es un directorio autocontenido (como
#     /opt/firefox) con un symlink lanzador en /usr/bin. Se mapea
#     cada symlink a su bundle raíz, se filtra por tamaño
#     (>= 5 MB) y se deduplica dejando solo bundles padre.
# ═══════════════════════════════════════════════════════════════
scan_bundles() {
    info "$(t L_SEARCHING) /opt y /usr/lib..."

    # ───────────────────────────────────────────────────────────
    # EN: Pass 1 — map each /usr/bin symlink to its bundle dir.
    # ES: Pasada 1 — mapea cada symlink de /usr/bin a su bundle.
    # ───────────────────────────────────────────────────────────
    declare -A SYM_TO_BD=()
    local sym tgt
    for sym in /usr/bin/* /usr/local/bin/*; do
        [[ -L "$sym" ]] || continue
        tgt=$(readlink -f "$sym" 2>/dev/null)
        [[ -z "$tgt" ]] && continue
        local bd=""
        case "$tgt" in
            /opt/*)
                # EN: /opt/<top>/... → bundle = /opt/<top>.
                # ES: /opt/<top>/... → bundle = /opt/<top>.
                local rel="${tgt#/opt/}"
                local top="${rel%%/*}"
                [[ -d "/opt/$top" ]] && bd="/opt/$top"
                ;;
            /usr/lib/*|/usr/lib64/*)
                # EN: /usr/lib/<top>/... → bundle = /usr/lib/<top>,
                #     but skip well-known non-app top-level dirs.
                # ES: /usr/lib/<top>/... → bundle = /usr/lib/<top>,
                #     pero se omiten directorios de sistema conocidos.
                local pfx="/usr/lib"
                [[ "$tgt" == /usr/lib64/* ]] && pfx="/usr/lib64"
                local rel="${tgt#$pfx/}"
                local top="${rel%%/*}"
                case "$top" in
                    bin|sbin|share|lib|lib64|local|applications|pkgconfig|cmake|icons|fonts|themes|man|doc|info|licenses|systemd|dbus-1|mime|X11) continue ;;
                    python*|perl*|ruby*|node_modules|golang*) continue ;;
                    *-dev|*-doc|*-data|*-common|*-headers) continue ;;
                    x86_64-linux-gnu|i386-linux-gnu) continue ;;
                esac
                [[ -d "$pfx/$top" ]] && bd="$pfx/$top"
                ;;
        esac
        [[ -z "$bd" ]] && continue
        [[ "$tgt" != "$bd"/* ]] && continue

        # EN: Skip bundles smaller than 5 MB.
        # ES: Omite bundles menores de 5 MB.
        local ds
        ds=$(du -sb "$bd" 2>/dev/null | awk '{print $1}')
        [[ -z "$ds" || "$ds" -lt 5242880 ]] && continue
        SYM_TO_BD["$sym"]="$bd"
    done

    # ───────────────────────────────────────────────────────────
    # EN: Pass 2 — keep one symlink per bundle (the shortest).
    # ES: Pasada 2 — conserva un symlink por bundle (el más corto).
    # ───────────────────────────────────────────────────────────
    declare -A BD_TO_SYM=()
    for sym in "${!SYM_TO_BD[@]}"; do
        local bd="${SYM_TO_BD[$sym]}"
        if [[ -z "${BD_TO_SYM[$bd]+x}" ]]; then
            BD_TO_SYM["$bd"]="$sym"
        else
            [[ ${#sym} -lt ${#BD_TO_SYM[$bd]} ]] && BD_TO_SYM["$bd"]="$sym"
        fi
    done

    # ───────────────────────────────────────────────────────────
    # EN: Pass 3 — dedup so we only keep parent bundles.
    # ES: Pasada 3 — deduplica dejando solo bundles padre.
    # ───────────────────────────────────────────────────────────
    local bds=()
    for bd in "${!BD_TO_SYM[@]}"; do bds+=("$bd"); done
    IFS=$'\n' bds=($(for bd in "${bds[@]}"; do echo "${#bd}|$bd"; done | sort -n -t'|' -k1 | cut -d'|' -f2))
    local finals=()
    for bd in "${bds[@]}"; do
        local is_child=0 p
        for p in "${finals[@]}"; do
            if [[ "$bd" == "$p" || "$bd" == "$p"/* ]]; then is_child=1; break; fi
        done
        [[ $is_child -eq 0 ]] && finals+=("$bd")
    done

    # ───────────────────────────────────────────────────────────
    # EN: Pass 4 — register each bundle as an app.
    # ES: Pasada 4 — registra cada bundle como app.
    # ───────────────────────────────────────────────────────────
    local found=0
    for bd in "${finals[@]}"; do
        local s="${BD_TO_SYM[$bd]}"
        [[ -n "${APPS_MAP[$s]+x}" ]] && continue
        local ds
        ds=$(du -sb "$bd" 2>/dev/null | awk '{print $1}')
        [[ -z "$ds" || "$ds" -lt 5242880 ]] && continue

        # EN: Human-friendly name from the symlink basename.
        # ES: Nombre legible a partir del basename del symlink.
        local name
        name=$(basename "$s")
        name="$(tr '[:lower:]' '[:upper:]' <<< "${name:0:1}")${name:1}"

        # EN: Detect GUI and toolkit on the real ELF.
        # ES: Detecta GUI y toolkit sobre el ELF real.
        local real
        real=$(readlink -f "$s" 2>/dev/null || echo "$s")
        [[ -f "$real" ]] || real="$s"
        local g="CLI"
        gui_app "$real" && g="GUI"
        local tk
        tk=$(toolkit "$real")
        [[ "$g" == "CLI" ]] && tk=""

        # EN: Sanitize app ID. | ES: Sanea el app ID.
        local aid
        aid="org.bundle.$(basename "$bd")"
        aid=$(echo "$aid" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9-.' | sed 's/--*/-/g')

        local sh
        sh=$(hs "$ds")

        # EN: Register in the shared APPS_MAP/APPS_LIST.
        # ES: Registra en el APPS_MAP/APPS_LIST compartido.
        APPS_MAP["$s"]="$name|$s|Other|$sh|ELF|$aid|$g|$tk|$bd|$ds"
        APPS_LIST+=("$s")
        found=$((found + 1))
        det "$(t L_BUNDLE): $name  $sh  $bd"
    done

    # ───────────────────────────────────────────────────────────
    # EN: Extra pass — /opt/* dirs with no symlink at all.
    # ES: Pasada extra — dirs /opt/* sin symlink asociado.
    # ───────────────────────────────────────────────────────────
    if [[ -d /opt ]]; then
        local od
        for od in /opt/*/; do
            [[ -d "$od" ]] || continue
            od="${od%/}"

            # EN: Skip if already registered by the symlink pass.
            # ES: Omite si ya fue registrado por la pasada symlink.
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

            # EN: Pick the biggest ELF executable as the entry.
            # ES: Elige el ELF ejecutable más grande como entrada.
            local mb
            mb=$(find "$od" -maxdepth 4 -type f -executable 2>/dev/null | \
                while IFS= read -r f; do
                    local fb
                    fb=$(basename "$f")
                    case "$fb" in
                        *.so|*.so.*|lib*.so*|*crashpad*|*-sandbox|*helper*|*.sh|*.py) continue ;;
                    esac
                    file -b "$f" 2>/dev/null | grep -q ELF && echo "$(sz "$f")|$f"
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
            APPS_MAP["$mb"]="$name|$mb|Other|$sh|ELF|$aid|$g|$tk|$od|$ds"
            APPS_LIST+=("$mb")
            found=$((found + 1))
            det "$(t L_BUNDLE): $name  $sh  $od"
        done
    fi

    [[ $found -gt 0 ]] && ok "Bundles: $found"
}

# ═══════════════════════════════════════════════════════════════
# EN: App registry — global maps shared across the packager.
# ES: Registro de apps — mapas globales compartidos en el packager.
#
# EN: APPS_MAP key   = binary path.
#     APPS_MAP value = "name|path|category|human_size|format|app_id|gui|toolkit|bundle_dir|bytes"
#     APPS_LIST      = insertion-ordered keys.
#     APPS_SORTED    = keys sorted by size desc (filled by detect_all).
# ES: APPS_MAP clave = ruta del binario.
#     APPS_MAP valor = "name|path|category|human_size|format|app_id|gui|toolkit|bundle_dir|bytes"
#     APPS_LIST      = claves en orden de inserción.
#     APPS_SORTED    = claves ordenadas por tamaño desc (lo llena detect_all).
# ═══════════════════════════════════════════════════════════════
declare -A APPS_MAP
declare -a APPS_LIST=()
declare -a APPS_SORTED=()

# ═══════════════════════════════════════════════════════════════
# EN: find_bundle_dir — guess the bundle root for a binary.
# ES: find_bundle_dir — adivina la raíz del bundle de un binario.
#
# EN: Strategy:
#       1. If the binary is under /opt/<x>, /usr/lib/<x>, etc.,
#          and that top dir is > 10 MB, use it.
#       2. Otherwise try common name patterns (lowercase, kebab,
#          snake) under /opt, /usr/lib, /usr/lib64, /usr/share.
# ES: Estrategia:
#       1. Si el binario está bajo /opt/<x>, /usr/lib/<x>, etc.,
#          y ese directorio top es > 10 MB, usarlo.
#       2. Si no, probar patrones de nombre (minúsculas, kebab,
#          snake) bajo /opt, /usr/lib, /usr/lib64, /usr/share.
# ═══════════════════════════════════════════════════════════════
find_bundle_dir() {
    local b="$1" nm="$2" r
    r=$(resolve_bin "$b")

    # EN: Step 1 — derive from the binary's real path.
    # ES: Paso 1 — derivar de la ruta real del binario.
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

    # EN: Step 2 — try name-based candidates.
    # ES: Paso 2 — probar candidatos por nombre.
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

# ═══════════════════════════════════════════════════════════════
# EN: calc_total — total size, preferring bundle dir over file.
# ES: calc_total — tamaño total, prefiriendo bundle dir sobre archivo.
# ═══════════════════════════════════════════════════════════════
calc_total() {
    local b="$1" bd="$2"
    if [[ -n "$bd" && -d "$bd" ]]; then
        local s
        s=$(du -sb "$bd" 2>/dev/null | awk '{print $1}')
        [[ -n "$s" && "$s" -gt 0 ]] && { echo "$s"; return; }
    fi
    sz "$b"
}

# ═══════════════════════════════════════════════════════════════
# EN: reg_app — register an app in the global maps.
# ES: reg_app — registra una app en los mapas globales.
#
# EN: Skips duplicates. Auto-detects bundle dir if not given.
#     Returns 1 if already present, 0 otherwise.
# ES: Omite duplicados. Auto-detecta bundle dir si no se da.
#     Devuelve 1 si ya existe, 0 en caso contrario.
# ═══════════════════════════════════════════════════════════════
reg_app() {
    local nm="$1" b="$2" cat="$3" aid="$4" gui="$5" tk="$6"
    [[ -n "${APPS_MAP[$b]+x}" ]] && return 1
    local bd=""
    bd=$(find_bundle_dir "$b" "$nm" 2>/dev/null || echo "")
    local tot
    tot=$(calc_total "$b" "$bd")
    local sh
    sh=$(hs "$tot")
    APPS_MAP["$b"]="$nm|$b|$cat|$sh|ELF|$aid|$gui|$tk|$bd|$tot"
    APPS_LIST+=("$b")
    return 0
}

# ═══════════════════════════════════════════════════════════════
# EN: scan_desktop — parse .desktop files to find installed apps.
# ES: scan_desktop — parsea archivos .desktop para hallar apps.
#
# EN: Reads Name/Exec/Categories/NoDisplay, resolves the Exec
#     binary (handling env wrappers), maps Categories to our
#     internal categories, and registers the app.
# ES: Lee Name/Exec/Categories/NoDisplay, resuelve el binario
#     Exec (manejando wrappers env), mapea Categories a nuestras
#     categorías internas y registra la app.
# ═══════════════════════════════════════════════════════════════
scan_desktop() {
    info "$(t L_SEARCHING) .desktop..."
    local dirs=(
        "/usr/share/applications"
        "/usr/local/share/applications"
        "$HOME/.local/share/applications"
    )

    # EN: Progress bar total. | ES: Total para barra de progreso.
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
            prog "$n" "$tot" "desktop"

            # EN: Parse the .desktop file (first occurrence wins).
            # ES: Parsea el archivo .desktop (gana la primera).
            local name="" ec="" cat="" nd=""
            local ln
            while IFS= read -r ln; do
                case "$ln" in
                    Name=*) [[ -z "$name" ]] && name="${ln#Name=}" ;;
                    Exec=*) [[ -z "$ec" ]] && ec="${ln#Exec=}" ;;
                    Categories=*) cat="${ln#Categories=}" ;;
                    NoDisplay=true) nd="true" ;;
                esac
            done < "$df"
            [[ "$nd" == "true" || -z "$ec" || -z "$name" ]] && continue

            # EN: Strip field codes (%U, %f, etc.) and env wrappers.
            # ES: Quita códigos de campo (%U, %f, etc.) y wrappers env.
            ec=$(echo "$ec" | sed -E 's/%[UuFfikc]//g')
            [[ "$ec" == env\ * ]] && ec=$(echo "$ec" | sed -E 's/^env\s+//' | sed -E 's/\S+=\S+\s+//g')

            # EN: Extract the first token (the binary).
            # ES: Extrae el primer token (el binario).
            local b
            b=$(echo "$ec" | awk '{print $1}' | sed 's/^"//;s/"$//')
            [[ -z "$b" ]] && continue

            # EN: Resolve to an absolute path. | ES: Resuelve a ruta absoluta.
            local bp=""
            if [[ "$b" == /* ]]; then
                [[ -e "$b" ]] && bp="$b"
            else
                bp=$(command -v "$b" 2>/dev/null || true)
            fi
            [[ -z "$bp" || ! -f "$bp" || ! -x "$bp" ]] && continue

            # EN: Only ELF, shell scripts or symlinks are of interest.
            # ES: Solo interesan ELF, shell scripts o symlinks.
            local ft
            ft=$(file -b "$bp" 2>/dev/null || echo "")
            echo "$ft" | grep -qE "ELF|shell script|symbolic link" || continue

            # ───────────────────────────────────────────────────
            # EN: Map freedesktop Categories to our internal ones.
            # ES: Mapea Categories freedesktop a las internas.
            # ───────────────────────────────────────────────────
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

            local g="CLI"
            gui_app "$bp" && g="GUI"
            local tk
            tk=$(toolkit "$bp")

            # EN: Sanitize app ID from name; fallback to md5 of path.
            # ES: Sanea el app ID desde el nombre; fallback a md5.
            local aid
            aid="${name// /-}"
            aid=$(echo "$aid" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9-' | sed 's/--*/-/g;s/^-//;s/-$//')
            [[ -z "$aid" ]] && aid="app-$(echo "$bp" | md5sum | cut -c1-8)"

            reg_app "$name" "$bp" "$c" "$aid" "$g" "$tk"
        done < <(find "$d" -maxdepth 1 -name "*.desktop" 2>/dev/null)
    done
    echo ""
}

# ═══════════════════════════════════════════════════════════════
# EN: detect_all — full scan of installed applications.
# ES: detect_all — escaneo completo de aplicaciones instaladas.
#
# EN: Runs .desktop scan, checks a curated list of common CLI/GUI
#     binaries, runs the bundle scan, then sorts APPS_SORTED by
#     size descending.
# ES: Ejecuta el escaneo .desktop, revisa una lista curada de
#     binarios comunes CLI/GUI, ejecuta el escaneo de bundles y
#     ordena APPS_SORTED por tamaño descendente.
# ═══════════════════════════════════════════════════════════════
detect_all() {
    info "$(t L_SEARCHING)..."
    scan_desktop

    # ───────────────────────────────────────────────────────────
    # EN: Curated list of common binaries.
    # ES: Lista curada de binarios comunes.
    # ───────────────────────────────────────────────────────────
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
        reg_app "$a" "$bp" "Utilities" "org.$a.$a" "$g" "$tk" && fe=$((fe + 1))
    done
    [[ $fe -gt 0 ]] && det "Adicionales: $fe"

    # EN: Bundle scan (last, so it overrides weaker matches).
    # ES: Escaneo de bundles (último, sobreescribe matches débiles).
    scan_bundles

    # ───────────────────────────────────────────────────────────
    # EN: Sort by size descending for the "top apps" view.
    # ES: Ordena por tamaño descendente para la vista "top apps".
    # ───────────────────────────────────────────────────────────
    IFS=$'\n' APPS_SORTED=($(for b in "${APPS_LIST[@]}"; do
        local tt
        tt=$(echo "${APPS_MAP[$b]}" | awk -F'|' '{print $10}')
        [[ -z "$tt" ]] && tt=$(sz "$b")
        echo "$tt|$b"
    done | sort -rn | cut -d'|' -f2))

    ok "$(t L_DETECTED): ${#APPS_SORTED[@]}"
}

# ═══════════════════════════════════════════════════════════════
# EN: fld — extract field i (1-based) from a pipe-separated record.
# ES: fld — extrae el campo i (base 1) de un registro "|" separado.
# ═══════════════════════════════════════════════════════════════
fld() { echo "$1" | awk -F'|' -v i="$2" '{print $i}'; }
# ═══════════════════════════════════════════════════════════════
# EN: create_desktop_entry — generate a .desktop file and icon
#     for an installed app.
# ES: create_desktop_entry — genera un archivo .desktop e icono
#     para una app instalada.
#
# EN: Aggressive icon search inside the app tree, scored by:
#       - filename contains the app id (weight 1000)
#       - filename contains the first token of the app id (500)
#       - path contains 256x256 / 128x128 / scalable (200/150/120)
#       - is .svg (30) or .png (20)
#       - is "default*" or "icon*" (50)
#     Falls back to hardcoded well-known paths, then to a generic
#     theme icon if nothing is found.
# ES: Búsqueda agresiva de icono dentro del árbol de la app,
#     puntuada por:
#       - nombre contiene el app id (peso 1000)
#       - nombre contiene el primer token del app id (500)
#       - ruta contiene 256x256 / 128x128 / scalable (200/150/120)
#       - es .svg (30) o .png (20)
#       - es "default*" o "icon*" (50)
#     Cae a rutas conocidas hardcodeadas, luego a un icono de tema
#     genérico si no encuentra nada.
# ═══════════════════════════════════════════════════════════════
create_desktop_entry() {
    local app_id="$1"
    local manifest="$APPS_DIR/$app_id/manifest.json"
    [[ -f "$manifest" ]] || return 1

    # EN: Read manifest fields. | ES: Lee campos del manifiesto.
    local name ver desc gui tk
    name=$(jq -r '.name // ""' "$manifest" 2>/dev/null)
    ver=$(jq -r '.version // ""' "$manifest" 2>/dev/null)
    desc=$(jq -r '.description // ""' "$manifest" 2>/dev/null)
    gui=$(jq -r '.gui // false' "$manifest" 2>/dev/null)
    tk=$(jq -r '.toolkit // ""' "$manifest" 2>/dev/null)

    # ───────────────────────────────────────────────────────────
    # EN: Heuristic: force GUI if the app name suggests it, even
    #     if the manifest says false. Common for apps that do not
    #     link directly to libgtk/libQt but launch GUI children.
    # ES: Heurística: forzar GUI si el nombre lo sugiere, aunque
    #     el manifiesto diga false. Común en apps que no enlazan
    #     directamente con libgtk/libQt pero lanzan hijos GUI.
    # ───────────────────────────────────────────────────────────
    if [[ "$gui" != "true" ]]; then
        case "${app_id,,} ${name,,}" in
            *firefox*|*chrome*|*chromium*|*brave*|*thunderbird*|*libreoffice*|*gimp*|*inkscape*|*vlc*|*mpv*|*blender*|*code*|*discord*|*spotify*)
                gui="true"
                ;;
            *)
                det "App CLI — sin entrada de menú"
                return 1
                ;;
        esac
    fi

    mkdir -p "$DESKTOP_DIR"
    mkdir -p "$ICONS_DIR"

    # ───────────────────────────────────────────────────────────
    # EN: Icon search — score every image file in the tree.
    # ES: Búsqueda de icono — puntúa cada imagen del árbol.
    # ───────────────────────────────────────────────────────────
    local app_tree="$APPS_DIR/$app_id/tree"
    local found_icon=""

    if [[ -d "$app_tree" ]]; then
        found_icon=$(find "$app_tree" -type f \
                \( -name "*.png" -o -name "*.svg" -o -name "*.xpm" \) \
                2>/dev/null | while IFS= read -r f; do
                local fb
                fb=$(basename "$f" | tr '[:upper:]' '[:lower:]')
                local app_lc="${app_id,,}"
                local score=0
                [[ "$fb" == *"$app_lc"* ]] && score=$((score + 1000))
                [[ "$fb" == *"${app_lc%%-*}"* ]] && score=$((score + 500))
                [[ "$f" == *"256x256"* ]] && score=$((score + 200))
                [[ "$f" == *"128x128"* ]] && score=$((score + 150))
                [[ "$f" == *"scalable"* ]] && score=$((score + 120))
                [[ "$f" == *"64x64"* ]] && score=$((score + 80))
                [[ "$f" == *.svg ]] && score=$((score + 30))
                [[ "$f" == *.png ]] && score=$((score + 20))
                [[ "$fb" == "default"* || "$fb" == "icon"* ]] && score=$((score + 50))
                echo "$score|$f"
            done | sort -rn | head -1 | cut -d'|' -f2)
    fi

    # ───────────────────────────────────────────────────────────
    # EN: Fallback — well-known paths for popular apps.
    # ES: Fallback — rutas conocidas de apps populares.
    # ───────────────────────────────────────────────────────────
    if [[ -z "$found_icon" ]]; then
        local cands=(
            "$app_tree/bundle/browser/icons/mozicon128.png"
            "$app_tree/bundle/browser/chrome/icons/default/default128.png"
            "$app_tree/bundle/chrome/app/theme/chromium/product_logo_128.png"
            "$app_tree/bundle/share/icons/hicolor/256x256/apps/$app_id.png"
            "$app_tree/bundle/share/icons/hicolor/128x128/apps/$app_id.png"
            "$app_tree/bundle/share/icons/hicolor/scalable/apps/$app_id.svg"
            "$app_tree/bundle/share/pixmaps/$app_id.png"
            "$app_tree/bundle/$app_id.png"
        )
        local c
        for c in "${cands[@]}"; do
            [[ -f "$c" ]] && { found_icon="$c"; break; }
        done
    fi

    # ───────────────────────────────────────────────────────────
    # EN: Copy the icon into the hicolor theme. Fall back to a
    #     generic internet icon if nothing was found.
    # ES: Copia el icono al tema hicolor. Cae al icono genérico
    #     de internet si no se encontró nada.
    # ───────────────────────────────────────────────────────────
    local icon_ref="applications-internet"
    if [[ -n "$found_icon" && -f "$found_icon" ]]; then
        local ext="${found_icon##*.}"
        local tgt="$ICONS_DIR/packbox-$app_id.$ext"
        if cp "$found_icon" "$tgt" 2>/dev/null; then
            chmod 644 "$tgt"
            icon_ref="packbox-$app_id"
            det "Icono: $(basename "$found_icon") → packbox-$app_id.$ext"
        fi
    else
        det "Sin icono propio — usando '$icon_ref'"
    fi

    # ───────────────────────────────────────────────────────────
    # EN: Categories — sensible defaults per app-id keyword.
    # ES: Categorías — valores por defecto según palabra del id.
    # ───────────────────────────────────────────────────────────
    local cats="Utility;"
    case "${app_id,,}" in
        *firefox*|*chrome*|*chromium*|*brave*|*browser*|*opera*)  cats="Network;WebBrowser;" ;;
        *thunderbird*|*mail*)                                     cats="Network;Email;" ;;
        *vlc*|*mpv*|*celluloid*|*media*|*audio*)                  cats="AudioVideo;Player;" ;;
        *gimp*|*inkscape*|*photo*|*image*)                        cats="Graphics;" ;;
        *libreoffice*|*writer*|*calc*|*impress*)                  cats="Office;" ;;
        *code*|*editor*|*vim*|*emacs*)                            cats="Development;TextEditor;" ;;
        *terminal*|*console*)                                     cats="System;TerminalEmulator;" ;;
    esac

    # ───────────────────────────────────────────────────────────
    # EN: Write the .desktop file. X-Packbox-* fields are custom
    #     metadata read by the packager.
    # ES: Escribe el .desktop. Los campos X-Packbox-* son metadata
    #     personalizada que lee el packager.
    # ───────────────────────────────────────────────────────────
    local desktop_file="$DESKTOP_DIR/packbox-$app_id.desktop"
    cat > "$desktop_file" <<DESKTOP_EOF
[Desktop Entry]
Type=Application
Version=1.0
Name=$name
Comment=$desc
Exec=$RUN_BIN $app_id
TryExec=$RUN_BIN
Icon=$icon_ref
Terminal=false
StartupNotify=true
StartupWMClass=$app_id
Categories=$cats
Keywords=packbox;$app_id;
X-Packbox-ID=$app_id
X-Packbox-Version=$ver
X-Packbox-Toolkit=$tk
DESKTOP_EOF
    chmod +x "$desktop_file"

    # ───────────────────────────────────────────────────────────
    # EN: Refresh desktop and icon caches so the entry appears
    #     immediately without a session restart.
    # ES: Refresca cachés de menú e iconos para que la entrada
    #     aparezca de inmediato sin reiniciar sesión.
    # ───────────────────────────────────────────────────────────
    if command -v update-desktop-database &>/dev/null; then
        update-desktop-database "$DESKTOP_DIR" 2>/dev/null || true
    fi
    if command -v gtk-update-icon-cache &>/dev/null; then
        gtk-update-icon-cache -f -t "$HOME/.local/share/icons/hicolor" 2>/dev/null || true
    fi
    command -v xdg-desktop-menu &>/dev/null && \
        xdg-desktop-menu forceupdate 2>/dev/null || true

    ok "Menú: $desktop_file  (icono: $icon_ref)"
    return 0
}

# ═══════════════════════════════════════════════════════════════
# EN: Global selection state.
# ES: Estado global de selección.
#
# EN: Populated by select_top()/search_app(), read by show_details,
#     configure_pack and the pack_* functions.
# ES: Lo llenan select_top()/search_app(), lo leen show_details,
#     configure_pack y las funciones pack_*.
# ═══════════════════════════════════════════════════════════════
CURRENT_BIN=""           # EN: path of the chosen binary | ES: ruta del binario elegido
CURRENT_INFO=""          # EN: raw APPS_MAP record | ES: registro APPS_MAP crudo
CURRENT_APP_ID=""        # EN: sanitized app id | ES: app id saneado
CURRENT_VERSION=""       # EN: user-visible version | ES: versión visible
CURRENT_DESC=""          # EN: user-visible description | ES: descripción visible
CURRENT_IS_GUI=""        # EN: "GUI" or "CLI" | ES: "GUI" o "CLI"
CURRENT_TOOLKIT=""       # EN: GTK3/Qt5/etc. | ES: GTK3/Qt5/etc.
CURRENT_PACK_MODE=2      # EN: default mode = portable | ES: modo por defecto = portable
CURRENT_BUNDLE_DIR=""    # EN: bundle root, if any | ES: raíz del bundle, si hay

# ═══════════════════════════════════════════════════════════════
# EN: select_top — show the top N largest apps and let the user
#     pick one. Also offers filter, search, expand and cancel.
# ES: select_top — muestra las N apps más grandes y permite
#     elegir una. Ofrece filtro, búsqueda, expandir y cancelar.
#
# EN: Args: limit (default 15), minb (min size in bytes, 0=all).
# ES: Args: limit (por defecto 15), minb (tamaño mín en bytes,
#     0=todas).
# ═══════════════════════════════════════════════════════════════
select_top() {
    local limit="${1:-15}" minb="${2:-0}"
    [[ ${#APPS_SORTED[@]} -eq 0 ]] && err "$(t L_NO_RESULTS)"
    hdr "$(t L_TOP)"

    # EN: Build the candidate list, applying the min-size filter.
    # ES: Construye la lista de candidatos aplicando el filtro.
    local cand=() b
    for b in "${APPS_SORTED[@]}"; do
        local s
        s=$(fld "${APPS_MAP[$b]}" 10)
        [[ -z "$s" ]] && s=$(sz "$b")
        [[ "$s" -lt "$minb" ]] && continue
        cand+=("$b")
        [[ ${#cand[@]} -ge $limit ]] && break
    done
    [[ ${#cand[@]} -eq 0 ]] && { warn "$(t L_NO_RESULTS)"; return 1; }

    # EN: Render the list. | ES: Renderiza la lista.
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

        # EN: Truncate long names to fit the column.
        # ES: Trunca nombres largos para ajustar la columna.
        local dn="$nm"
        [[ ${#dn} -gt 28 ]] && dn="${dn:0:25}..."

        # EN: Tag: BUNDLE > GUI/toolkit > CLI.
        # ES: Etiqueta: BUNDLE > GUI/toolkit > CLI.
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

    # EN: Input loop. | ES: Bucle de entrada.
    while true; do
        echo -en "  ${BD}> ${N}"
        local c
        read -r c
        case "$c" in
            q|Q) return 1 ;;
            f|F)
                # EN: Recurse with a byte filter derived from MB input.
                # ES: Recurse con filtro en bytes desde entrada en MB.
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
            *) warn "Opción inválida" ;;
        esac
    done
}

# ═══════════════════════════════════════════════════════════════
# EN: search_app — search by name, path or app id.
# ES: search_app — busca por nombre, ruta o app id.
#
# EN: Case-insensitive substring match. Shows a numbered list
#     and lets the user pick one.
# ES: Coincidencia de subcadena sin distinguir mayúsculas.
#     Muestra una lista numerada y permite elegir una.
# ═══════════════════════════════════════════════════════════════
search_app() {
    echo ""
    local q
    q=$(ask_txt "$(t L_SEARCH_PROMPT)")
    [[ -z "$q" ]] && return 1
    q=$(echo "$q" | tr '[:upper:]' '[:lower:]')

    # EN: Collect matches. | ES: Recolecta coincidencias.
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

    # EN: Render results. | ES: Renderiza resultados.
    echo ""
    echo -e "  ${BD}${#res[@]} resultados${N}"
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

# ═══════════════════════════════════════════════════════════════
# EN: show_details — print the selected app's details.
# ES: show_details — muestra los detalles de la app seleccionada.
# ═══════════════════════════════════════════════════════════════
show_details() {
    local inf="$CURRENT_INFO"
    local nm p c s t aid gui tk bd
    nm=$(fld "$inf" 1); p=$(fld "$inf" 2); c=$(fld "$inf" 3)
    s=$(fld "$inf" 4); t=$(fld "$inf" 5); aid=$(fld "$inf" 6)
    gui=$(fld "$inf" 7); tk=$(fld "$inf" 8); bd=$(fld "$inf" 9)

    hdr "Detalles"
    echo -e "  ${BD}Nombre:${N}      $nm"
    echo -e "  ${BD}Ruta:${N}        $p"
    echo -e "  ${BD}Categoría:${N}   $c"
    echo -e "  ${BD}Tamaño:${N}      ${BD}$s${N}"
    echo -e "  ${BD}Tipo:${N}        $gui ($tk)"
    echo -e "  ${BD}App ID:${N}      $aid"
    if [[ -n "$bd" ]]; then
        echo -e "  ${BD}Bundle:${N}      ${M}$bd${N}"
    fi
    echo ""
}

# ═══════════════════════════════════════════════════════════════
# EN: configure_pack — ask the user for app id, version,
#     description and packing mode.
# ES: configure_pack — pide al usuario app id, versión,
#     descripción y modo de empaquetado.
#
# EN: Offers 3 modes for regular apps (Normal / Portable / Module)
#     and 4 for bundles (adds Bundle, recommended).
#     Sensible defaults are shown in brackets.
# ES: Ofrece 3 modos para apps normales (Normal / Portable /
#     Módulo) y 4 para bundles (añade Bundle, recomendado).
#     Se muestran valores por defecto entre corchetes.
# ═══════════════════════════════════════════════════════════════
configure_pack() {
    local inf="$CURRENT_INFO"
    local nm p aid gui tk bd s
    nm=$(fld "$inf" 1); p=$(fld "$inf" 2); aid=$(fld "$inf" 6)
    gui=$(fld "$inf" 7); tk=$(fld "$inf" 8); bd=$(fld "$inf" 9); s=$(fld "$inf" 4)

    # ───────────────────────────────────────────────────────────
    # EN: App ID (sanitized to lowercase, dots and dashes).
    # ES: App ID (saneado a minúsculas, puntos y guiones).
    # ───────────────────────────────────────────────────────────
    hdr "$(t L_APP_ID)"
    echo -en "  [${DM}$aid${N}]: "
    read -r new_id
    CURRENT_APP_ID="${new_id:-$aid}"
    CURRENT_APP_ID=$(echo "$CURRENT_APP_ID" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9.-' | sed 's/--*/-/g;s/^-//;s/-$//')
    [[ -z "$CURRENT_APP_ID" ]] && CURRENT_APP_ID="org.app.unknown"

    # ───────────────────────────────────────────────────────────
    # EN: Version — try to autodetect with --version, fallback 1.0.0.
    # ES: Versión — intenta autodetectar con --version, fallback 1.0.0.
    # ───────────────────────────────────────────────────────────
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

    # ───────────────────────────────────────────────────────────
    # EN: Description — default is the app name.
    # ES: Descripción — por defecto el nombre de la app.
    # ───────────────────────────────────────────────────────────
    echo ""
    echo -e "  ${BD}$(t L_DESCRIPTION):${N}"
    echo -en "  [${DM}$nm${N}]: "
    read -r nd
    CURRENT_DESC="${nd:-$nm}"

    # EN: Propagate selected metadata for later use.
    # ES: Propaga metadata seleccionada para uso posterior.
    CURRENT_IS_GUI="$gui"
    CURRENT_TOOLKIT="$tk"
    CURRENT_BUNDLE_DIR="$bd"

    # ───────────────────────────────────────────────────────────
    # EN: Mode selection. Bundles get a 4th option (recommended).
    # ES: Selección de modo. Los bundles tienen una 4ª opción.
    # ───────────────────────────────────────────────────────────
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
    echo ""
    ok "Configuración OK"
}

# ═══════════════════════════════════════════════════════════════
# EN: invoke_pack — call packbox-pack with the current settings.
# ES: invoke_pack — llama a packbox-pack con los ajustes actuales.
#
# EN: Args: workdir, app_id, entrypoint.
# ES: Args: workdir, app_id, entrypoint.
# ═══════════════════════════════════════════════════════════════
invoke_pack() {
    local wd="$1" aid="$2" ep="$3"
    local gf="false"
    [[ "$CURRENT_IS_GUI" == "GUI" ]] && gf="true"
    "$PACK_BIN" --name "$aid" --version "$CURRENT_VERSION" \
        --description "$CURRENT_DESC" --entrypoint "$ep" \
        --gui="$gf" --toolkit "$CURRENT_TOOLKIT" "$wd"
}

# ═══════════════════════════════════════════════════════════════
# EN: launcher_simple — write a small launcher.sh for normal and
#     portable modes. Sets LD_LIBRARY_PATH and XDG_DATA_DIRS.
# ES: launcher_simple — escribe un launcher.sh para los modos
#     normal y portable. Define LD_LIBRARY_PATH y XDG_DATA_DIRS.
# ═══════════════════════════════════════════════════════════════
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

# ═══════════════════════════════════════════════════════════════
# EN: package_real — dispatch to the correct packer by mode.
# ES: package_real — despacha al empaquetador correcto según modo.
# ═══════════════════════════════════════════════════════════════
package_real() {
    case "$CURRENT_PACK_MODE" in
        1) pack_normal ;;
        2) pack_portable ;;
        3) pack_module ;;
        4) pack_bundle ;;
        *) pack_portable ;;
    esac
}

# ═══════════════════════════════════════════════════════════════
# EN: pack_normal — binary + private libs (if any) in ~/.packbox.
# ES: pack_normal — binario + libs privadas (si hay) en ~/.packbox.
#
# EN: System libs are left for the host to provide. Private libs
#     get bundled and a launcher.sh is created.
# ES: Las libs de sistema las provee el host. Las libs privadas
#     se empaquetan y se crea un launcher.sh.
# ═══════════════════════════════════════════════════════════════
pack_normal() {
    hdr "$(t L_PACKING) $(t L_NORMAL)"
    local inf="$CURRENT_INFO" p
    p=$(fld "$inf" 2)
    [[ -z "$CURRENT_APP_ID" ]] && err "App ID"

    local wd
    wd=$(tmpdir "real")
    reg_cln "$wd"
    mkdir -p "$wd/bin"
    cp "$p" "$wd/bin/"
    chmod +x "$wd/bin/$(basename "$p")"
    local bn
    bn=$(basename "$p")

    # EN: Classify libs: system vs private.
    # ES: Clasifica libs: sistema vs privadas.
    info "Analizando libs..."
    local lsys=0 lpriv=0
    while IFS='|' read -r lib lp; do
        [[ -z "$lib" || -z "$lp" ]] && continue
        if [[ "$lp" == /usr/lib/* || "$lp" == /lib/* || "$lp" == /lib64/* ]]; then
            lsys=$((lsys + 1))
        else
            mkdir -p "$wd/lib"
            cp -L "$lp" "$wd/lib/" 2>/dev/null && lpriv=$((lpriv + 1))
        fi
    done < <(get_libs "$p")
    det "Sistema: $lsys  Privadas: $lpriv"

    # EN: If any private lib was bundled, use the launcher.
    # ES: Si se empaquetó alguna lib privada, usar el launcher.
    local ep
    if [[ $lpriv -gt 0 ]]; then
        launcher_simple "$wd/bin/launcher.sh" "$bn"
        ep="/app/bin/launcher.sh"
    else
        ep="/app/bin/$bn"
    fi

    invoke_pack "$wd" "$CURRENT_APP_ID" "$ep" || err "pack falló"
    jq empty "$wd/manifest.json" 2>/dev/null || err "JSON inválido"
    "$INSTALL_BIN" "$wd/manifest.json" || err "install falló"

    local ad="$APPS_DIR/$CURRENT_APP_ID"
    [[ -d "$ad/tree" ]] || err "sin tree/"
    box_ok "$CURRENT_APP_ID  $(t L_INSTALLED)"
    maybe_desktop
    ask_yn "$(t L_EXEC_NOW)" "n" && { echo ""; "$RUN_BIN" "$CURRENT_APP_ID"; }

    rm -rf "$wd"
    unreg_cln "$wd"
}

# ═══════════════════════════════════════════════════════════════
# EN: pack_portable — bundle every non-universal lib.
# ES: pack_portable — empaqueta cada lib no universal.
#
# EN: Universal libs (libc, libm, etc.) are provided by any host
#     and are NOT bundled. Everything else is copied into lib/.
# ES: Las libs universales (libc, libm, etc.) las provee cualquier
#     host y NO se empaquetan. Todo lo demás va a lib/.
# ═══════════════════════════════════════════════════════════════
pack_portable() {
    hdr "$(t L_PACKING) $(t L_PORTABLE)"
    local inf="$CURRENT_INFO" p
    p=$(fld "$inf" 2)
    [[ -z "$CURRENT_APP_ID" ]] && err "App ID"

    local wd
    wd=$(tmpdir "portable")
    reg_cln "$wd"
    mkdir -p "$wd/bin" "$wd/lib"
    cp "$p" "$wd/bin/"
    chmod +x "$wd/bin/$(basename "$p")"
    local bn
    bn=$(basename "$p")

    # EN: Copy every non-universal lib (dedup by name).
    # ES: Copia cada lib no universal (dedup por nombre).
    info "Libs no universales..."
    local lb=0 tls=0 sku=0 seen=""
    while IFS='|' read -r lib lp; do
        [[ -z "$lib" || -z "$lp" || ! -f "$lp" ]] && continue
        if is_universal "$lib"; then
            sku=$((sku + 1)); continue
        fi
        echo "$seen" | grep -q "|$lib|" && continue
        seen+="|$lib|"
        cp -L "$lp" "$wd/lib/" 2>/dev/null || continue
        local ls
        ls=$(sz "$lp")
        tls=$((tls + ls))
        lb=$((lb + 1))
    done < <(get_libs "$p")

    local tlh
    tlh=$(hs "$tls")
    local ep
    if [[ $lb -gt 0 ]]; then
        ok "Bundle libs: $lb ($tlh)"
        launcher_simple "$wd/bin/launcher.sh" "$bn"
        ep="/app/bin/launcher.sh"
    else
        ep="/app/bin/$bn"
    fi

    invoke_pack "$wd" "$CURRENT_APP_ID" "$ep" || err "pack falló"
    "$INSTALL_BIN" "$wd/manifest.json" || err "install falló"

    # EN: Mark the manifest as portable and record lib count.
    # ES: Marca el manifiesto como portable y anota el nº de libs.
    local ad="$APPS_DIR/$CURRENT_APP_ID"
    [[ -d "$ad/tree" ]] || err "sin tree/"
    local tm
    tm=$(mktemp)
    jq '. + {"portable": true, "portable_libs_count": '"$lb"'}' "$ad/manifest.json" > "$tm"
    mv "$tm" "$ad/manifest.json"

    box_ok "$CURRENT_APP_ID  $(t L_PORTABLE)"
    det "Libs: $lb ($tlh)"
    maybe_desktop
    ask_yn "$(t L_EXEC_NOW)" "n" && { echo ""; "$RUN_BIN" "$CURRENT_APP_ID"; }

    rm -rf "$wd"
    unreg_cln "$wd"
}

# ═══════════════════════════════════════════════════════════════
# EN: pack_bundle — copy the whole /opt (or /usr/lib) dir.
# ES: pack_bundle — copia el directorio completo de /opt (o /usr/lib).
#
# EN: Most robust mode for apps like Firefox/Chrome that ship
#     their own tree. Resolves the real binary inside the bundle,
#     writes a launcher that sets LD_LIBRARY_PATH and XDG_DATA_DIRS.
# ES: Modo más robusto para apps como Firefox/Chrome que traen su
#     propio árbol. Resuelve el binario real dentro del bundle y
#     escribe un launcher que define LD_LIBRARY_PATH y XDG_DATA_DIRS.
# ═══════════════════════════════════════════════════════════════
pack_bundle() {
    hdr "$(t L_PACKING) $(t L_BUNDLE)"
    local inf="$CURRENT_INFO" p s bd
    p=$(fld "$inf" 2); s=$(fld "$inf" 4); bd=$(fld "$inf" 9)
    [[ -z "$bd" || ! -d "$bd" ]] && err "Sin bundle_dir"
    [[ -z "$CURRENT_APP_ID" ]] && err "App ID"

    local wd
    wd=$(tmpdir "bundle")
    reg_cln "$wd"
    mkdir -p "$wd/bin" "$wd/bundle"

    # EN: One-shot copy; abort on real failure.
    # ES: Copia de un solo intento; aborta si falla de verdad.
    info "Copiando bundle $s..."
    cp -a --no-preserve=ownership "$bd/." "$wd/bundle/" \
        || err "cp bundle falló: $bd"
    # ───────────────────────────────────────────────────────────
    # EN: Resolve the real binary inside the bundle:
    #       1. If the resolved path is inside bd, use the relative.
    #       2. Otherwise ask find_bin_in_bundle for the best match.
    # ES: Resuelve el binario real dentro del bundle:
    #       1. Si la ruta resuelta está dentro de bd, usar relativa.
    #       2. Si no, pedir a find_bin_in_bundle el mejor candidato.
    # ───────────────────────────────────────────────────────────
    local br=""
    local rs
    rs=$(readlink -f "$p" 2>/dev/null || echo "$p")
    if [[ "$rs" == "$bd"/* ]]; then
        local cand="${rs#$bd/}"
        [[ -e "$wd/bundle/$cand" ]] && br="$cand"
    fi
    [[ -z "$br" ]] && br=$(find_bin_in_bundle "$p" "$wd/bundle")
    [[ -z "$br" ]] && err "Sin binario en bundle
  p=$p
  bd=$bd"
    [[ ! -e "$wd/bundle/$br" ]] && err "No existe $br"
    [[ -f "$wd/bundle/$br" && ! -x "$wd/bundle/$br" ]] && chmod +x "$wd/bundle/$br"
    ok "Binario: bundle/$br"

    # ───────────────────────────────────────────────────────────
    # EN: Launcher exposes the bundle's own lib and share dirs.
    # ES: El launcher expone lib y share propios del bundle.
    # ───────────────────────────────────────────────────────────
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

    invoke_pack "$wd" "$CURRENT_APP_ID" "/app/bin/launcher.sh" || err "pack falló"
    "$INSTALL_BIN" "$wd/manifest.json" || err "install falló"

    # EN: Record bundle-specific metadata in the manifest.
    # ES: Registra metadata específica del bundle en el manifiesto.
    local ad="$APPS_DIR/$CURRENT_APP_ID"
    [[ -d "$ad/tree" ]] || err "sin tree/"
    local tm
    tm=$(mktemp)
    jq '. + {"portable": true, "bundle": true, "bundle_dir": "'"$bd"'", "bundle_bin_rel": "'"$br"'"}' \
        "$ad/manifest.json" > "$tm"
    mv "$tm" "$ad/manifest.json"

    box_ok "$CURRENT_APP_ID  $(t L_BUNDLE)"
    det "Bundle: $bd"
    det "Binario: bundle/$br"
    maybe_desktop
    ask_yn "$(t L_EXEC_NOW)" "n" && { echo ""; "$RUN_BIN" "$CURRENT_APP_ID"; }

    rm -rf "$wd"
    unreg_cln "$wd"
}

# ═══════════════════════════════════════════════════════════════
# EN: pack_module — create a shared library module for a toolkit.
# ES: pack_module — crea un módulo de librerías compartidas.
#
# EN: Useful for toolkits like Qt5 that many apps share. The user
#     names the module and version; packbox-module does the work.
# ES: Útil para toolkits como Qt5 compartidos entre varias apps.
#     El usuario nombra el módulo y versión; packbox-module hace
#     el trabajo.
# ═══════════════════════════════════════════════════════════════
pack_module() {
    hdr "$(t L_MODULE)"
    local inf="$CURRENT_INFO" p tk
    p=$(fld "$inf" 2); tk=$(fld "$inf" 8)
    [[ ! -x "$MODULE_BIN" ]] && err "packbox-module no encontrado"

    echo -en "  ${BD}Nombre: ${N}"
    local mn
    read -r mn
    [[ -z "$mn" ]] && mn="org.toolkit.$(echo "$tk" | tr '[:upper:]' '[:lower:]')"

    echo -en "  ${BD}Versión [1.0.0]: ${N}"
    local mv
    read -r mv
    mv="${mv:-1.0.0}"

    "$MODULE_BIN" create "$p" "$mn" "$mv"
    read -rp "  ENTER..."
}

# ═══════════════════════════════════════════════════════════════
# EN: maybe_desktop — ask whether to create a menu entry.
# ES: maybe_desktop — pregunta si crear entrada de menú.
#
# EN: Always asks. The decision to actually create it (or bail out
#     for CLI apps) is made by create_desktop_entry itself.
# ES: Siempre pregunta. La decisión real de crearla (o no, para
#     apps CLI) la toma create_desktop_entry.
# ═══════════════════════════════════════════════════════════════
maybe_desktop() {
    echo ""
    if ask_yn "$(t L_CREATE_DESKTOP)" "s"; then
        create_desktop_entry "$CURRENT_APP_ID"
    fi
}
# ═══════════════════════════════════════════════════════════════
# EN: Library helpers.
# ES: Helpers de librerías.
# ═══════════════════════════════════════════════════════════════

# EN: UNIVERSAL — libs every Linux host provides. These are NOT
#     bundled in portable mode.
# ES: UNIVERSAL — libs que cualquier Linux provee. NO se
#     empaquetan en modo portable.
UNIVERSAL=(
    "libc.so.6" "libm.so.6" "libdl.so.2" "libpthread.so.0"
    "librt.so.1" "libresolv.so.2" "libutil.so.1" "libnsl.so.1"
    "libcrypt.so.1" "libz.so.1"
    "ld-linux-x86-64.so.2" "ld-linux.so.2"
)

# ═══════════════════════════════════════════════════════════════
# EN: is_universal — check whether a lib is in the universal set.
# ES: is_universal — comprueba si una lib está en el set universal.
# ═══════════════════════════════════════════════════════════════
is_universal() {
    local l="$1" u
    for u in "${UNIVERSAL[@]}"; do [[ "$l" == "$u" ]] && return 0; done
    return 1
}

# ═══════════════════════════════════════════════════════════════
# EN: get_libs — parse `ldd` output into "lib|path" lines.
# ES: get_libs — parsea la salida de `ldd` en líneas "lib|path".
#
# EN: Only lines with "=>" (the "not found" case yields an empty
#     path and is skipped).
# ES: Solo líneas con "=>" (el caso "not found" da una ruta vacía
#     y se omite).
# ═══════════════════════════════════════════════════════════════
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

# ═══════════════════════════════════════════════════════════════
# EN: export_app — package an installed app into a .pbox archive.
# ES: export_app — empaqueta una app instalada en un .pbox.
#
# EN: Lists installed apps with their version and tags
#     ([BUNDLE], [PORTABLE]), lets the user pick one, and calls
#     packbox-export.
# ES: Lista las apps instaladas con versión y etiquetas
#     ([BUNDLE], [PORTABLE]), permite elegir una y llama a
#     packbox-export.
# ═══════════════════════════════════════════════════════════════
export_app() {
    hdr "$(t L_4_EXPORT)"
    [[ ! -x "$EXPORT_BIN" ]] && err "packbox-export"

    # EN: Bail out if no apps are installed.
    # ES: Sale si no hay apps instaladas.
    if [[ ! -d "$APPS_DIR" || -z "$(ls -A "$APPS_DIR" 2>/dev/null)" ]]; then
        warn "$(t L_NO_RESULTS)"
        read -rp "  ENTER..."
        return 1
    fi

    # EN: Enumerate installed apps. | ES: Enumera las apps instaladas.
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
    done < <(find "$APPS_DIR" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | sort)

    echo ""
    echo -en "  ${BD}> 1-${#apps[@]}, q: ${N}"
    local c
    read -r c
    [[ "$c" == "q" ]] && return 1
    if [[ ! "$c" =~ ^[0-9]+$ || "$c" -lt 1 || "$c" -gt "${#apps[@]}" ]]; then
        warn "$(t L_INVALID)"
        return 1
    fi

    # EN: Run the export and report the resulting file.
    # ES: Ejecuta la exportación y reporta el archivo resultante.
    local tgt="${apps[$((c - 1))]}"
    echo ""
    info "Exportando $tgt..."
    if "$EXPORT_BIN" app "$tgt"; then
        local ef="$EXPORTS_DIR/$tgt.pbox"
        if [[ -f "$ef" ]]; then
            box_ok "$tgt $(t L_INSTALLED)"
            det "Archivo: $ef"
            det "Tamaño: $(du -h "$ef" 2>/dev/null | cut -f1)"
            det "Compresión: zstd -19 / xz -9e / gzip"
        fi
    else
        err "Export falló"
    fi
    read -rp "  ENTER..."
}

# ═══════════════════════════════════════════════════════════════
# EN: import_app — import a .pbox archive.
# ES: import_app — importa un archivo .pbox.
#
# EN: Asks for a path (supports ~), calls packbox-import, then
#     optionally offers to create a desktop entry if the app is
#     GUI, and to run it.
# ES: Pide una ruta (acepta ~), llama a packbox-import, luego
#     ofrece crear entrada de menú si la app es GUI y ejecutarla.
# ═══════════════════════════════════════════════════════════════
import_app() {
    hdr "$(t L_5_IMPORT)"
    [[ ! -x "$IMPORT_BIN" ]] && err "packbox-import"

    echo -en "  ${BD}Path .pbox: ${N}"
    local pp
    read -r pp
    pp="${pp/#\~/$HOME}"
    if [[ -z "$pp" || ! -f "$pp" ]]; then
        warn "$(t L_DOES_NOT_EXIST)"
        read -rp "  ENTER..."
        return 1
    fi

    info "Importando..."
    local out
    out=$("$IMPORT_BIN" app "$pp" 2>&1)
    echo "$out"

    # EN: Parse the app name from the import output.
    # ES: Parsea el nombre de la app desde la salida del import.
    local an
    an=$(echo "$out" | grep -oP 'importado: \K[^\s]+' | head -1)
    [[ -z "$an" ]] && an=$(basename "$pp" .pbox)
    box_ok "$an $(t L_INSTALLED)"

    # EN: Offer a desktop entry if the imported app is GUI.
    # ES: Ofrece entrada de menú si la app importada es GUI.
    if [[ -d "$APPS_DIR/$an" ]] && \
       [[ "$(jq -r '.gui // false' "$APPS_DIR/$an/manifest.json" 2>/dev/null)" == "true" ]]; then
        echo ""
        if ask_yn "$(t L_CREATE_DESKTOP)" "s"; then
            CURRENT_APP_ID="$an"
            CURRENT_IS_GUI="GUI"
            create_desktop_entry "$an"
        fi
    fi

    ask_yn "$(t L_EXEC_NOW)" "n" && { echo ""; "$RUN_BIN" "$an"; }
    read -rp "  ENTER..."
}

# ═══════════════════════════════════════════════════════════════
# EN: uninstall_apps — multi-select and remove apps.
# ES: uninstall_apps — selección múltiple y borrado de apps.
#
# EN: Supports single ("3"), multiple ("1 3 5"), range ("1-4")
#     and "all". Shows a preview with sizes, asks confirmation,
#     then runs packbox-remove per app and offers GC.
# ES: Soporta individual ("3"), múltiple ("1 3 5"), rango ("1-4")
#     y "all". Muestra previsualización con tamaños, pide
#     confirmación, ejecuta packbox-remove por app y ofrece GC.
# ═══════════════════════════════════════════════════════════════
uninstall_apps() {
    hdr "$(t L_6_UNINSTALL)"
    [[ ! -x "$REMOVE_BIN" ]] && err "packbox-remove"

    if [[ ! -d "$APPS_DIR" || -z "$(ls -A "$APPS_DIR" 2>/dev/null)" ]]; then
        warn "$(t L_NO_RESULTS)"
        read -rp "  ENTER..."
        return 1
    fi

    # EN: Enumerate apps with sizes. | ES: Enumera apps con tamaños.
    local apps=() sizes=() tot=0 i=1
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
        local asz
        asz=$(du -sb "$ad" 2>/dev/null | awk '{print $1}')
        [[ -z "$asz" ]] && asz=0
        printf "  ${C}%3d${N}) %-30s ${DM}v%-8s${N} ${BD}%9s${N}%s\n" \
            "$i" "$aid" "$ver" "$(hs "$asz")" "$tags"
        apps+=("$aid")
        sizes+=("$asz")
        tot=$((tot + asz))
        i=$((i + 1))
    done < <(find "$APPS_DIR" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | sort)

    echo ""
    echo -e "  ${BD}$(t L_TOTAL): $(hs "$tot") — ${#apps[@]} apps${N}"
    echo -e "  ${DM}Uno '3' · varios '1 3 5' · rango '1-4' · all · q${N}"
    echo -en "  ${BD}> ${N}"
    local sel
    read -r sel
    [[ "$sel" == "q" || -z "$sel" ]] && return 1

    # ───────────────────────────────────────────────────────────
    # EN: Parse selection into a list of zero-based indices.
    # ES: Parsea la selección a una lista de índices base 0.
    # ───────────────────────────────────────────────────────────
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

    # ───────────────────────────────────────────────────────────
    # EN: Preview and confirm. | ES: Previsualiza y confirma.
    # ───────────────────────────────────────────────────────────
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

    # ───────────────────────────────────────────────────────────
    # EN: Remove each selected app, tracking success/failure.
    # ES: Elimina cada app seleccionada, registrando éxito/fallo.
    # ───────────────────────────────────────────────────────────
    local rem=0 fail=0
    for idx in "${idxs[@]}"; do
        local aid="${apps[$idx]}"
        echo -e "  ${B}${BULLET}${N}  $aid..."
        if "$REMOVE_BIN" "$aid" >/dev/null 2>&1; then
            ok "$aid $(t L_REMOVED)"
            rem=$((rem + 1))
        else
            warn "$aid $(t L_FAILED)"
            fail=$((fail + 1))
        fi
    done
    echo ""
    box_ok "OK: $rem | FAIL: $fail"

    # EN: Offer GC if at least one app was removed.
    # ES: Ofrece GC si al menos una app fue eliminada.
    if [[ $rem -gt 0 ]]; then
        echo ""
        if ask_yn "GC? [S/n] " "s"; then
            echo ""
            "$GC_BIN"
        fi
    fi
    read -rp "  ENTER..."
}

# ═══════════════════════════════════════════════════════════════
# EN: main — top-level entrypoint of the packager.
# ES: main — punto de entrada principal del empaquetador.
#
# EN: Bootstraps i18n, verifies the binary dir exists, offers to
#     run the installer if missing, then loops on the main menu.
# ES: Arranca i18n, verifica que exista el dir de binarios,
#     ofrece ejecutar el instalador si faltan, y luego itera en
#     el menú principal.
# ═══════════════════════════════════════════════════════════════
main() {
    # EN: Bootstrap i18n. Order matters: write files before
    #     selecting the language so the selection can persist.
    # ES: Arranca i18n. El orden importa: escribe archivos antes
    #     de seleccionar el idioma para que la elección persista.
    install_lang_files
    select_language
    load_lang

    # ───────────────────────────────────────────────────────────
    # EN: If packbox-pack is missing, Packbox is not installed.
    #     Offer to run the installer now.
    # ES: Si falta packbox-pack, Packbox no está instalado.
    #     Ofrece ejecutar el instalador ahora.
    # ───────────────────────────────────────────────────────────
    if [[ ! -x "$PACK_BIN" ]]; then
        show_banner
        warn "Binarios no encontrados en $PACKBOX_BIN_DIR"
        echo ""
        if ask_yn "$(t L_RUN_INSTALLER_NOW)" "s"; then
            local inst="$SCRIPT_DIR/packbox-installer-v0.1.0.sh"
            [[ -x "$inst" ]] || err "Instalador no encontrado en $SCRIPT_DIR"
            bash "$inst"
        else
            err "Packbox debe estar instalado"
        fi
    fi

    # ───────────────────────────────────────────────────────────
    # EN: Main menu loop.
    # ES: Bucle del menú principal.
    # ───────────────────────────────────────────────────────────
    while true; do
        show_banner
        echo -e "  ${BD}$(t L_WHAT_DO)${N}"
        echo ""
        echo -e "  ${C}1${N}  $(t L_1_PACK)"
        echo -e "  ${C}2${N}  $(t L_2_LIST)"
        echo -e "  ${C}3${N}  $(t L_3_GC)"
        echo -e "  ${C}4${N}  ${BD}$(t L_4_EXPORT)${N}"
        echo -e "  ${C}5${N}  ${BD}$(t L_5_IMPORT)${N}"
        echo -e "  ${C}6${N}  ${R}${BD}$(t L_6_UNINSTALL)${N}"
        echo -e "  ${C}0${N}  $(t L_0_EXIT)"
        echo ""
        echo -e "  ${DM}${HR_T}${N}"
        echo ""
        echo -en "  ${BD}> $(t L_OPTION) [0-6]: ${N}"
        local opt
        read -r opt

        case "$opt" in
            1)
                # ───────────────────────────────────────────────
                # EN: Pack flow: scan, pick, configure, package,
                #     optionally export, repeat until user quits.
                # ES: Flujo pack: escanear, elegir, configurar,
                #     empaquetar, exportar opcionalmente, repetir.
                # ───────────────────────────────────────────────
                detect_all
                echo ""
                info "$(t L_DETECTED): ${#APPS_SORTED[@]}"

                # EN: Quick summary of what was found.
                # ES: Resumen rápido de lo encontrado.
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
                    ask_yn "$(t L_CONFIRM)" "s" || continue
                    package_real

                    # EN: Offer export after a successful package.
                    # ES: Ofrece exportar tras empaquetar con éxito.
                    if [[ -d "$APPS_DIR/$CURRENT_APP_ID" ]]; then
                        echo ""
                        if ask_yn "$(t L_4_EXPORT)? [s/N] " "n"; then
                            if "$EXPORT_BIN" app "$CURRENT_APP_ID"; then
                                local exp="$EXPORTS_DIR/$CURRENT_APP_ID.pbox"
                                ok "OK: $exp"
                                [[ -f "$exp" ]] && \
                                    det "Size: $(du -h "$exp" 2>/dev/null | cut -f1)"
                            fi
                        fi
                    fi
                    echo ""
                    ask_yn "$(t L_ANOTHER)" "n" || break
                done
                ;;
            2)
                # EN: List installed apps. | ES: Lista apps instaladas.
                if [[ -x "$LIST_BIN" ]]; then
                    "$LIST_BIN"
                else
                    warn "packbox-list no encontrado"
                fi
                read -rp "  ENTER..."
                ;;
            3)
                # EN: Garbage collect the CAS.
                # ES: Recolección de basura del CAS.
                if [[ -x "$GC_BIN" ]]; then
                    "$GC_BIN"
                else
                    warn "packbox-gc no encontrado"
                fi
                read -rp "  ENTER..."
                ;;
            4) export_app ;;
            5) import_app ;;
            6) uninstall_apps ;;
            0|q|Q)
                echo ""
                echo -e "  ${DM}${HR}${N}"
                echo -e "  ${DM}  Bye / Adiós / Au revoir / Auf Wiedersehen / Ciao / 再见 / さようなら / 안녕${N}"
                echo -e "  ${DM}${HR}${N}"
                echo ""
                exit 0
                ;;
            *)
                warn "Opción inválida: $opt"
                sleep 1
                ;;
        esac
    done
}

main "$@"
