#!/usr/bin/env bash
# =============================================================================
# i18n/common.sh — Núcleo de internacionalización.
# i18n/common.sh — Internationalization core.
#
# Asume / Assumes: ui.sh, paths.sh
# Provee / Provides: t, _tt, select_language, install_lang_files, load_lang
# =============================================================================

declare -gA _PB_T=()
_PB_LANG="en"
_PB_LANG_NAME="English"
_PB_LANG_SELECTED=""

_PB_LANGS=(es en fr de it pt zh ja ko)
_PB_LANG_LABELS=(
    "Español"
    "English"
    "Français"
    "Deutsch"
    "Italiano"
    "Português"
    "中文"
    "日本語"
    "한국어"
)

# ─── t <KEY> — traduce / translates ─────────────────────────────────────────
t() {
    local k="${1:-}"
    [[ -z "$k" ]] && return 0
    local v="${_PB_T[$k]:-}"
    if [[ -z "$v" ]]; then
        v="${_PB_T_EN[$k]:-$k}"
    fi
    printf '%s' "$v"
}

# ─── select_language [--force] ───────────────────────────────────────────────
# Sin --force: usa la guardada, luego $LANG, luego pregunta.
# Without --force: uses saved, then $LANG, then asks.
# Con --force: siempre pregunta (default = actual).
# With --force: always asks (default = current).
select_language() {
    local force=0
    [[ "${1:-}" == "--force" ]] && force=1

    # ─── 1. Guardada / Saved ────────────────────────────────────────────────
    if [[ $force -eq 0 && -f "$PACKBOX_LANG_DIR/current" ]]; then
        local saved
        saved=$(tr -d '[:space:]' < "$PACKBOX_LANG_DIR/current" 2>/dev/null || true)
        if [[ -n "$saved" ]]; then
            local c
            for c in "${_PB_LANGS[@]}"; do
                if [[ "$saved" == "$c" ]]; then
                    _PB_LANG_SELECTED="$saved"
                    return 0
                fi
            done
        fi
    fi

    # ─── 2. Default desde entorno / Default from environment ────────────────
    local auto="${LANG:-}${LC_ALL:-}${LC_MESSAGES:-}"
    auto="${auto%%.*}"
    auto="${auto%%_*}"
    auto="${auto%%-*}"
    local default_idx=2
    local i
    for i in "${!_PB_LANGS[@]}"; do
        if [[ "${_PB_LANGS[$i]}" == "$auto" ]]; then
            default_idx=$((i + 1))
            break
        fi
    done

    # Si --force y hay una guardada, usarla como default del menú.
    # If --force and there's a saved one, use it as menu default.
    if [[ $force -eq 1 && -f "$PACKBOX_LANG_DIR/current" ]]; then
        local cur
        cur=$(tr -d '[:space:]' < "$PACKBOX_LANG_DIR/current" 2>/dev/null || true)
        for i in "${!_PB_LANGS[@]}"; do
            if [[ "${_PB_LANGS[$i]}" == "$cur" ]]; then
                default_idx=$((i + 1))
                break
            fi
        done
    fi

    # ─── 3. Menú con colores / Colored menu ─────────────────────────────────
    clear
    echo ""
    echo -e "${BD}${C}  ${HR}${N}"
    echo -e "${BD}${C}   Packbox — Language / Idioma / Langue / Sprache / Lingua${N}"
    echo -e "${BD}${C}             语言 / 日本語 / 한국어${N}"
    echo -e "${BD}${C}  ${HR}${N}"
    echo ""
    local idx=1 lbl
    for lbl in "${_PB_LANG_LABELS[@]}"; do
        printf "   ${C}${BD}%d)${N}  %s\n" "$idx" "$lbl"
        idx=$((idx + 1))
    done
    echo ""
    echo -e "  ${DM}${HR_T}${N}"
    echo ""
    printf "  ${BD}> ${N}[1-9] (default %d): " "$default_idx"
    local r
    read -r r
    [[ -z "$r" ]] && r="$default_idx"
    if [[ "$r" =~ ^[0-9]+$ ]] && (( r >= 1 && r <= ${#_PB_LANGS[@]} )); then
        _PB_LANG_SELECTED="${_PB_LANGS[$((r - 1))]}"
    else
        _PB_LANG_SELECTED="${_PB_LANGS[$((default_idx - 1))]}"
    fi
}

# ─── install_lang_files — persiste la selección ─────────────────────────────
install_lang_files() {
    mkdir -p "$PACKBOX_LANG_DIR" 2>/dev/null || true
    printf '%s\n' "${_PB_LANG_SELECTED:-en}" > "$PACKBOX_LANG_DIR/current" 2>/dev/null || true
}

# ─── load_lang — carga el diccionario en _PB_T ──────────────────────────────
load_lang() {
    _load_lang_into "${_PB_LANG_SELECTED:-en}"
}

# ─── _load_lang_into <code> — carga un idioma ───────────────────────────────
_load_lang_into() {
    local code="$1" arr_name
    case "$code" in
        es) arr_name=_PB_T_ES ;;
        fr) arr_name=_PB_T_FR ;;
        de) arr_name=_PB_T_DE ;;
        it) arr_name=_PB_T_IT ;;
        pt) arr_name=_PB_T_PT ;;
        zh) arr_name=_PB_T_ZH ;;
        ja) arr_name=_PB_T_JA ;;
        ko) arr_name=_PB_T_KO ;;
        en|*) arr_name=_PB_T_EN; code=en ;;
    esac
    _PB_T=()
    local -n _src="$arr_name"
    local k
    for k in "${!_src[@]}"; do
        _PB_T[$k]="${_src[$k]}"
    done
    unset -n _src 2>/dev/null || true
    _PB_LANG="$code"
    _PB_LANG_NAME="${_PB_T[L_LANG_NAME]:-$code}"
}