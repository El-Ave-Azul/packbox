#!/usr/bin/env bash
# =============================================================================
# lib/main-installer.sh — Menú del instalador.
# lib/main-installer.sh — Installer menu.
#
# Asume / Assumes: common, ui, paths, journal, i18n, install, uninstall
# Provee / Provides: main_installer, show_banner_installer, change_language_installer
# =============================================================================

main_installer() {
    # ─── Parseo de args ──────────────────────────────────────────────────────
    # ─── Arg parsing ─────────────────────────────────────────────────────────
    case "${1:-}" in
        --uninstall|-u)
            select_language
            install_lang_files
            load_lang
            do_uninstall
            return $?
            ;;
        --lang|-l)
            select_language --force
            install_lang_files
            load_lang
            ok "$(_tt L_LANG_CHANGED "Idioma cambiado a"): $(t L_LANG_NAME)"
            return 0
            ;;
        --help|-h)
            cat <<'HELP'
Packbox Installer / Instalador Packbox

Uso / Usage:
  ./packbox-install.sh [opciones]

Opciones / Options:
  -u, --uninstall   Desinstalar / Uninstall
  -l, --lang        Cambiar idioma / Change language
  -h, --help        Esta ayuda / This help
HELP
            return 0
            ;;
    esac

    # ─── i18n ────────────────────────────────────────────────────────────────
    # ─── i18n ───────────────────────────────────────────────────────────────
    select_language
    install_lang_files
    load_lang

    # ─── Menú principal ─────────────────────────────────────────────────────
    # ─── Main menu ──────────────────────────────────────────────────────────
    while true; do
        show_banner_installer
        echo -e "  ${BD}$(t L_WELCOME)${N}"
        echo -e "  ${DM}Lang: $(t L_LANG_NAME)${N}"
        echo ""
        echo -e "  ${C}1${N}  $(t L_MENU_INSTALL)"
        echo -e "  ${C}2${N}  ${R}$(t L_MENU_UNINSTALL)${N}"
        echo -e "  ${C}3${N}  $(_tt L_7_LANG "Cambiar idioma") ${DM}($(t L_LANG_NAME))${N}"
        echo -e "  ${C}0${N}  $(t L_MENU_EXIT)"
        echo ""
        echo -e "  ${DM}${HR_T}${N}"
        echo ""
        echo -en "  ${BD}> $(t L_MENU_PROMPT) [0-3]: ${N}"
        local opt
        read -r opt
        case "$opt" in
            1)
                do_install
                echo ""
                echo -en "  ${BD}ENTER...${N}"
                read -r
                ;;
            2)
                do_uninstall
                ;;
            3)
                change_language_installer
                ;;
            0|q|Q)
                echo ""
                echo -e "  ${DM}Bye / Adiós${N}"
                echo ""
                exit 0
                ;;
            *) warn "$(t L_INVALID)"; sleep 1 ;;
        esac
    done
}

# ─── Banner del instalador ───────────────────────────────────────────────────
# ─── Installer banner ────────────────────────────────────────────────────────
show_banner_installer() {
    clear
    echo -e "${BD}${C}"
    echo "  ═══════════════════════════════════════════════════════════════"
    echo "   $(t L_INSTALLER_TITLE)"
    echo "   v${PACKBOX_VERSION} · i18n (9) · Go ${GO_VERSION:-?} en ~/.packbox/go · Journal"
    echo "   Install: ~/.packbox (oculto / hidden)"
    echo "  ═══════════════════════════════════════════════════════════════"
    echo -e "${N}"
}

# ─── Cambiar idioma sin salir ────────────────────────────────────────────────
# ─── Change language without exiting ─────────────────────────────────────────
change_language_installer() {
    local prev="$_PB_LANG"
    select_language --force
    install_lang_files
    load_lang
    if [[ "$_PB_LANG" == "$prev" ]]; then
        ok "$(_tt L_LANG_UNCHANGED "Idioma sin cambios"): $(t L_LANG_NAME)"
    else
        ok "$(_tt L_LANG_CHANGED "Idioma cambiado a"): $(t L_LANG_NAME)"
    fi
    sleep 1
}