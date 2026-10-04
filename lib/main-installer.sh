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
        pb_status "$(t L_WELCOME)" "$(t L_LANG_NAME)"
        echo ""
        panel_top
        menu_item 1 "$(t L_MENU_INSTALL)"
        menu_item 2 "$(t L_MENU_UNINSTALL)" "" "$R"
        menu_item 3 "$(_tt L_7_LANG "Cambiar idioma")" "$(t L_LANG_NAME)"
        menu_item 0 "$(t L_MENU_EXIT)"
        panel_bottom
        echo ""
        echo -en "  ${BD}${ARROW} $(t L_MENU_PROMPT) [0-3]: ${N}"
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
    pb_banner "$(t L_INSTALLER_TITLE)" "Go ${GO_VERSION:-?} · ~/.packbox · journal" "v${PACKBOX_VERSION}"
    echo ""
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