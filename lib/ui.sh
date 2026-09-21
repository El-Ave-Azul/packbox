#!/usr/bin/env bash
# =============================================================================
# lib/ui.sh — Funciones de presentación (colores, iconos, barras).
# lib/ui.sh — Presentation functions (colors, icons, bars).
#
# Asume / Assumes: nada / nothing
# Provee / Provides: _num, info, ok, warn, err, det, hdr, box_ok, progress, hs
# =============================================================================

# ─── Colores ─────────────────────────────────────────────────────────────────
# ─── Colors ──────────────────────────────────────────────────────────────────
if [[ -t 1 ]]; then
    R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; B='\033[0;34m'
    C='\033[0;36m'; M='\033[0;35m'; BD='\033[1m'; DM='\033[2m'; N='\033[0m'
else
    R=''; G=''; Y=''; B=''; C=''; M=''; BD=''; DM=''; N=''
fi

# ─── Iconos (UTF-8 si el locale lo soporta) ─────────────────────────────────
# ─── Icons (UTF-8 if locale supports it) ────────────────────────────────────
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

# ─── Saneador numérico ───────────────────────────────────────────────────────
# ─── Numeric sanitizer ───────────────────────────────────────────────────────
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

# ─── Encabezados ─────────────────────────────────────────────────────────────
# ─── Headers ─────────────────────────────────────────────────────────────────
hdr() {
    echo ""
    echo -e "${C}${BD}${HR_T}${N}"
    echo -e "${C}${BD}  ${ARROW} ${1:-}${N}"
    echo -e "${C}${BD}${HR_T}${N}"
    echo ""
}

box_ok() {
    echo ""
    echo -e "  ${G}${HR}${N}"
    echo -e "  ${G}${BD}     ${1:-}${N}"
    echo -e "  ${G}${HR}${N}"
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