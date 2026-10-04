#!/usr/bin/env bash
# shellcheck disable=SC2034  # usadas por los archivos que sourcean esta librería
# =============================================================================
# lib/ui.sh — Funciones de presentación (colores, iconos, cajas, barras).
# lib/ui.sh — Presentation functions (colors, icons, boxes, bars).
#
# Look: cajas con bordes redondeados (unicode) o ASCII como fallback.
# Look: rounded-box frames (unicode) with an ASCII fallback.
#
# Asume / Assumes: nada / nothing
# Provee / Provides: _num, info, ok, warn, det, err, fail, hdr, box_ok,
#                    progress, hs, pb_rule, panel_top, panel_bottom, menu_item,
#                    pb_banner, pb_status, kv
# =============================================================================

# ─── Colores ─────────────────────────────────────────────────────────────────
# ─── Colors ──────────────────────────────────────────────────────────────────
if [[ -t 1 ]]; then
    R=$'\033[0;31m'; G=$'\033[0;32m'; Y=$'\033[1;33m'; B=$'\033[0;34m'
    C=$'\033[0;36m'; M=$'\033[0;35m'; BD=$'\033[1m'; DM=$'\033[2m'; N=$'\033[0m'
else
    R=''; G=''; Y=''; B=''; C=''; M=''; BD=''; DM=''; N=''
fi

# ─── Iconos y bordes (UTF-8 si el locale lo soporta) ─────────────────────────
# ─── Icons and borders (UTF-8 if locale supports it) ─────────────────────────
_UTF8=0
case "${LC_ALL:-}${LC_CTYPE:-}${LANG:-}" in
    *UTF-8*|*utf-8*|*UTF8*|*utf8*) _UTF8=1 ;;
esac
if [[ $_UTF8 -eq 1 ]]; then
    HR="━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    HR_T="───────────────────────────────────────────────────────────────"
    ARROW="▸"; BULLET="·"; PB_F="█"; PB_E="░"; CHK="✓"; XMK="✗"
    PB_BOX_TL="╭"; PB_BOX_TR="╮"; PB_BOX_BL="╰"; PB_BOX_BR="╯"
    PB_BOX_H="─"; PB_BOX_V="│"
else
    HR="==============================================================="
    HR_T="---------------------------------------------------------------"
    ARROW=">"; BULLET="*"; PB_F="#"; PB_E="-"; CHK="+"; XMK="x"
    PB_BOX_TL="+"; PB_BOX_TR="+"; PB_BOX_BL="+"; PB_BOX_BR="+"
    PB_BOX_H="-"; PB_BOX_V="|"
fi

# Panel inner width in characters (content between the vertical borders).
# Ancho interior del panel en caracteres (contenido entre los bordes).
PB_W="${PB_W:-61}"

# ─── Utilidades internas ─────────────────────────────────────────────────────
# ─── Internal helpers ────────────────────────────────────────────────────────
# _num <value> — devuelve el valor si es un entero no negativo, o "0".
# _num <value> — returns the value if it's a non-negative integer, else "0".
_num() {
    local v="${1:-0}"
    if [[ "$v" =~ ^[0-9]+$ ]]; then
        printf '%s' "$v"
    else
        printf '0'
    fi
}

# _pb_repeat <n> <char> — repite <char> <n> veces.
# _pb_repeat <n> <char> — repeats <char> <n> times.
_pb_repeat() {
    local n="${1:-0}" c="${2:- }" s
    (( n < 0 )) && n=0
    printf -v s '%*s' "$n" ''
    printf '%s' "${s// /$c}"
}

# _pb_row <plain> <rendered> — una fila del panel. <rendered> debe tener el
# mismo ancho visible que <plain> (colores aparte).
# _pb_row <plain> <rendered> — one panel row. <rendered> must have the same
# visible width as <plain> (colors aside).
_pb_row() {
    local plain="$1" rendered="$2" pad sp
    pad=$(( PB_W - ${#plain} ))
    (( pad < 0 )) && pad=0
    printf -v sp '%*s' "$pad" ''
    printf '  %s %s%s %s\n' "${C}${PB_BOX_V}${N}" "$rendered" "$sp" "${C}${PB_BOX_V}${N}"
}

# ─── Mensajes ────────────────────────────────────────────────────────────────
# ─── Messages ────────────────────────────────────────────────────────────────
info()  { echo -e "  ${B}${BULLET}${N}  ${1:-}"; }
ok()    { echo -e "  ${G}${CHK}${N}  ${1:-}"; }
warn()  { echo -e "  ${Y}!${N}  ${1:-}"; }
det()   { echo -e "     ${DM}${ARROW} ${1:-}${N}"; }

# err — imprime error y termina. Único lugar con exit.
# err — prints error and exits. Only place with exit.
err() {
    echo -e "  ${R}${XMK}${N}  ${BD}${1:-error}${N}"
    exit 1
}

# fail — imprime error y devuelve 1, SIN salir. Para el flujo interactivo
# (un fallo al empaquetar/desinstalar debe volver al menú, no matar el packager).
# fail — prints an error and returns 1, WITHOUT exiting. For the interactive
# flow (a pack/uninstall failure must return to the menu, not kill the packager).
fail() {
    echo -e "  ${R}${XMK}${N}  ${BD}${1:-error}${N}"
    return 1
}

# ─── Reglas y encabezados ────────────────────────────────────────────────────
# ─── Rules and headers ───────────────────────────────────────────────────────
# pb_rule [color] — regla horizontal a lo ancho del panel.
# pb_rule [color] — horizontal rule across the panel width.
pb_rule() {
    printf '  %s%s%s\n' "${1:-$DM}" "$(_pb_repeat $((PB_W + 2)) "$PB_BOX_H")" "${N}"
}

# hdr <text> — encabezado de sección con marcador.
# hdr <text> — section header with a marker.
hdr() {
    echo ""
    echo -e "  ${C}${BD}${ARROW} ${1:-}${N}"
    echo -e "  ${C}${HR_T}${N}"
    echo ""
}

# kv <label> <value> — fila etiqueta/valor alineada (por caracteres, no bytes).
# kv <label> <value> — aligned label/value row (by characters, not bytes).
kv() {
    local label="${1:-}" value="${2:-}" pad sp
    pad=$(( 16 - ${#label} ))
    (( pad < 1 )) && pad=1
    printf -v sp '%*s' "$pad" ''
    printf '  %s%s%s%s %s\n' "${DM}" "$label" "$sp" "${N}" "$value"
}

# ─── Cajas / paneles ─────────────────────────────────────────────────────────
# ─── Boxes / panels ──────────────────────────────────────────────────────────
# panel_top [title] — borde superior; con título va incrustado en la línea.
# panel_top [title] — top border; with a title it is embedded in the line.
panel_top() {
    local title="${1:-}" inner=$((PB_W + 2))
    if [[ -z "$title" ]]; then
        printf '  %s%s%s%s%s\n' "${C}${BD}" "$PB_BOX_TL" \
            "$(_pb_repeat "$inner" "$PB_BOX_H")" "$PB_BOX_TR" "${N}"
        return
    fi
    local text="─ ${title} " fill
    fill=$(( inner - ${#text} ))
    (( fill < 0 )) && fill=0
    printf '  %s%s%s%s%s%s%s\n' "${C}${BD}" "$PB_BOX_TL" "$text" \
        "$(_pb_repeat "$fill" "$PB_BOX_H")" "$PB_BOX_TR" "${N}"
}

# panel_bottom — borde inferior.
# panel_bottom — bottom border.
panel_bottom() {
    printf '  %s%s%s%s%s\n' "${C}${BD}" "$PB_BOX_BL" \
        "$(_pb_repeat $((PB_W + 2)) "$PB_BOX_H")" "$PB_BOX_BR" "${N}"
}

# menu_item <key> <label> [desc] [color] [label-color] — una fila de menú.
# menu_item <key> <label> [desc] [color] [label-color] — one menu row.
menu_item() {
    local key="${1:-}" label="${2:-}" desc="${3:-}" col="${4:-$C}" lcol="${5:-}" k
    printf -v k '%-2s' "$key"
    local plain="  ${k}  ${label}"
    local rendered="  ${col}${BD}${k}${N}  ${lcol}${label}${N}"
    if [[ -n "$desc" ]]; then
        plain="${plain}   ${BULLET} ${desc}"
        rendered="${rendered}   ${DM}${BULLET} ${desc}${N}"
    fi
    _pb_row "$plain" "$rendered"
}

# pb_banner <title> <subtitle> [right] — banner enmarcado.
# pb_banner <title> <subtitle> [right] — framed banner.
pb_banner() {
    local title="${1:-}" sub="${2:-}" right="${3:-}" pad sp
    panel_top
    pad=$(( PB_W - 2 - ${#title} - ${#right} ))
    (( pad < 1 )) && pad=1
    printf -v sp '%*s' "$pad" ''
    _pb_row "  ${title}${sp}${right}" "  ${BD}${C}${title}${N}${sp}${DM}${right}${N}"
    if [[ -n "$sub" ]]; then
        _pb_row "  ${sub}" "  ${DM}${sub}${N}"
    fi
    panel_bottom
}

# pb_status <left> <right> — barra de estado de una línea.
# pb_status <left> <right> — one-line status bar.
pb_status() {
    local left="${1:-}" right="${2:-}" pad sp
    pad=$(( PB_W - ${#left} - ${#right} ))
    (( pad < 1 )) && pad=1
    printf -v sp '%*s' "$pad" ''
    printf '  %s%s%s%s%s\n' "${DM}" "$left" "$sp" "$right" "${N}"
}

# box_ok <text> — caja de éxito.
# box_ok <text> — success box.
box_ok() {
    echo ""
    panel_top
    _pb_row "  ${CHK} ${1:-}" "  ${G}${BD}${CHK} ${1:-}${N}"
    panel_bottom
    echo ""
}

# ─── Barra de progreso (blindada contra basura) ─────────────────────────────
# ─── Progress bar (hardened against garbage) ────────────────────────────────
progress() {
    local c t m
    c=$(_num "${1:-0}")
    t=$(_num "${2:-100}")
    m="${3:-...}"
    local w=35
    [[ $t -le 0 ]] && t=1
    local p=$((c * 100 / t))
    local f=$((c * w / t))
    local e=$((w - f))
    [[ $f -gt $w ]] && f=$w
    [[ $e -lt 0 ]] && e=0
    printf "\r  %s [" "$m"
    local i
    for ((i=0; i<f; i++)); do printf "%b" "$PB_F"; done
    printf "\033[2m"
    for ((i=0; i<e; i++)); do printf "%b" "$PB_E"; done
    printf "\033[0m] %3d%%\033[K" "$p"
    [[ $c -ge $t ]] && echo ""
}

# ─── Tamaño humano (blindado contra basura) ─────────────────────────────────
# ─── Human size (hardened against garbage) ──────────────────────────────────
hs() {
    local b
    b=$(_num "${1:-0}")
    if command -v numfmt &>/dev/null; then
        numfmt --to=iec "$b" 2>/dev/null && return
    fi
    if   [[ $b -ge 1073741824 ]]; then echo "$(( b / 1073741824 ))G"
    elif [[ $b -ge 1048576 ]];    then echo "$(( b / 1048576 ))M"
    elif [[ $b -ge 1024 ]];       then echo "$(( b / 1024 ))K"
    else echo "${b}B"
    fi
}
