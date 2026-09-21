#!/usr/bin/env bash
# =============================================================================
# lib/common.sh — Utilidades base: trap, temporales, input.
# lib/common.sh — Base utilities: trap, temporaries, input.
#
# Asume / Assumes: ui.sh
# Provee / Provides: _cleanup, tmpdir, reg_cln, unreg_cln, ask_yn, ask_txt, _tt
# =============================================================================

# ─── Array de limpieza ───────────────────────────────────────────────────────
# ─── Cleanup array ───────────────────────────────────────────────────────────
# -g: ver la nota en lib/detect.sh (sourceado dentro de _pb_bootstrap).
# -g: see the note in lib/detect.sh (sourced inside _pb_bootstrap).
declare -ga CLEANUP=()

# reg_cln — registra un directorio temporal para borrar al salir.
# reg_cln — registers a temporary directory to delete on exit.
reg_cln() { CLEANUP+=("$1"); }

# unreg_cln — desregistra un directorio temporal.
# unreg_cln — unregisters a temporary directory.
unreg_cln() {
    local x="$1" n=() y
    for y in "${CLEANUP[@]:-}"; do [[ "$y" != "$x" ]] && n+=("$y"); done
    CLEANUP=("${n[@]:-}")
}

# _cleanup — borra todos los temporales registrados. Llamado por trap.
# _cleanup — deletes all registered temporaries. Called by trap.
_cleanup() {
    local d
    for d in "${CLEANUP[@]:-}"; do
        [[ -n "$d" && -e "$d" ]] && rm -rf "$d" 2>/dev/null
    done
}

# ─── Temporales ──────────────────────────────────────────────────────────────
# ─── Temporaries ─────────────────────────────────────────────────────────────
# tmpdir <prefix> — crea un directorio temporal seguro y lo devuelve.
# tmpdir <prefix> — creates a secure temp directory and returns it.
tmpdir() {
    local p="${1:-packbox}" base
    if [[ -n "${XDG_RUNTIME_DIR:-}" && -d "$XDG_RUNTIME_DIR" && -w "$XDG_RUNTIME_DIR" ]]; then
        base="$XDG_RUNTIME_DIR/packbox"
    else
        base="${PACKBOX_TMP_DIR:-/tmp}/packbox"
    fi
    mkdir -p "$base" 2>/dev/null
    chmod 700 "$base" 2>/dev/null
    local d
    d=$(mktemp -d "$base/${p}-XXXXXX")
    chmod 700 "$d"
    echo "$d"
}

# ─── Input ───────────────────────────────────────────────────────────────────
# ─── Input ───────────────────────────────────────────────────────────────────
# ask_yn <prompt> [default] — pregunta sí/no. Default: n.
# ask_yn <prompt> [default] — asks yes/no. Default: n.
# Muestra [S/n] o [s/N] según el default (la mayúscula es el default), salvo que
# el prompt ya traiga un hint [x/y].
# Shows [S/n] or [s/N] per the default (upper-case is the default), unless the
# prompt already carries an [x/y] hint.
ask_yn() {
    local p="${1:-}" d="${2:-n}" r hint
    if [[ "$d" == [Ss]* ]]; then hint="S/n"; else hint="s/N"; fi
    if [[ ! "$p" =~ \[[SsNnYy]/[SsNnYy]\] ]]; then
        p="${p% } [$hint] "
    fi
    printf "  ${Y}?${N} %s" "$p"
    read -r -n 1 r
    echo
    [[ -z "$r" ]] && r="$d"
    [[ "$r" =~ ^[SsYy]$ ]]
}

# ask_txt <prompt> — pregunta y devuelve texto.
# ask_txt <prompt> — asks and returns text.
# El prompt va a stderr: los llamadores usan $(ask_txt ...) y así capturan
# solo el valor, no el prompt.
# The prompt goes to stderr: callers use $(ask_txt ...) so they capture only
# the value, not the prompt.
ask_txt() {
    printf "  ${Y}?${N} %s" "${1:-}" >&2
    local r
    read -r r
    echo "$r"
}

# ─── i18n helper ─────────────────────────────────────────────────────────────
# ─── i18n helper ─────────────────────────────────────────────────────────────
# _tt <KEY> <DEFAULT> — traduce o devuelve default inline.
# _tt <KEY> <DEFAULT> — translates or returns inline default.
_tt() {
    local k="${1:-}" d="${2:-}" v
    v=$(t "$k" 2>/dev/null)
    if [[ -z "$v" || "$v" == "$k" ]]; then
        printf '%s' "$d"
    else
        printf '%s' "$v"
    fi
}