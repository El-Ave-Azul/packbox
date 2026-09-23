#!/usr/bin/env bash
# =============================================================================
# lib/install.sh — Orquestación de la instalación.
# lib/install.sh — Installation orchestration.
#
# Asume / Assumes: todo lo anterior del bootstrap.
#                 everything above from bootstrap.
# Provee / Provides: do_install
# =============================================================================

# do_install — instalación completa con journal.
# do_install — full installation with journal.
do_install() {
    show_banner_installer
    echo -e "  ${BD}$(t L_WELCOME)${N}"
    echo -e "  ${DM}Lang: $(t L_LANG_NAME) | Install: ~/.packbox${N}"
    echo ""

    # ─── Migración desde ~/packbox ──────────────────────────────────────────
    # ─── Migration from ~/packbox ───────────────────────────────────────────
    if [[ -d "$PACKBOX_OLD_DIR" ]] && [[ ! -d "$PACKBOX_INSTALL_DIR" ]]; then
        warn "$(t L_MIGRATE_DONE): ~/packbox"
        det "$(t L_MIGRATE_MSG)"
        echo ""
    fi

    # ─── Paso 1: distro ─────────────────────────────────────────────────────
    # ─── Step 1: distro ─────────────────────────────────────────────────────
    hdr "$(t L_STEP1)"
    detect_distro
    [[ "$DF" == "unknown" ]] && err "Unsupported distro / Distro no soportada"
    ok "$DISTRO_NAME (family: $DF)"

    # Sudo
    if [[ $EUID -eq 0 ]]; then
        SUDO=""
    elif command -v sudo &>/dev/null; then
        SUDO="sudo"
    else
        SUDO=""
        warn "No sudo — system packages will be skipped"
    fi

    # Paquetes necesarios
    local DEPS
    read -r -a DEPS <<< "$(default_deps)"

    info "$(t L_INSTALL_DEPS)${BD}${DEPS[*]}${N}"
    printf "  ${Y}?${N} $(t L_CONTINUE)"
    read -r -n 1 REPLY
    echo
    if [[ "$REPLY" =~ ^[Nn]$ ]]; then
        warn "$(t L_CANCEL)"
        return 0
    fi

    if [[ -n "$SUDO" ]] || [[ $EUID -eq 0 ]]; then
        install_pkgs "${DEPS[@]}" || warn "Some packages failed / Algunos paquetes fallaron"
    fi

    # ─── Preparar journal ───────────────────────────────────────────────────
    # ─── Prepare journal ────────────────────────────────────────────────────
    if [[ -f "$PACKBOX_JOURNAL" ]]; then
        local bak
        bak="$PACKBOX_JOURNAL.prev.$(date +%Y%m%d-%H%M%S)"
        mv "$PACKBOX_JOURNAL" "$bak" 2>/dev/null || true
        info "Old journal saved / Diario antiguo guardado: $(basename "$bak")"
    fi
    journal_init

    # ─── Paso 2: Go ─────────────────────────────────────────────────────────
    # ─── Step 2: Go ─────────────────────────────────────────────────────────
    hdr "$(t L_STEP2)"
    install_go

    # ─── Paso 3: directorios ────────────────────────────────────────────────
    # ─── Step 3: directories ────────────────────────────────────────────────
    create_dirs

    # ─── Paso 4: copiar src/ ────────────────────────────────────────────────
    # ─── Step 4: copy src/ ──────────────────────────────────────────────────
    copy_src_tree

    # ─── Paso 5: compilar ───────────────────────────────────────────────────
    # ─── Step 5: compile ────────────────────────────────────────────────────
    compile_go

    # ─── Paso 6: tests ──────────────────────────────────────────────────────
    # ─── Step 6: tests ──────────────────────────────────────────────────────
    run_tests

    # ─── Paso 7: PATH ───────────────────────────────────────────────────────
    # ─── Step 7: PATH ───────────────────────────────────────────────────────
    configure_path

    # ─── Paso 8: verificar ──────────────────────────────────────────────────
    # ─── Step 8: verify ─────────────────────────────────────────────────────
    hdr "$(t L_STEP8)"
    local all_ok=true b
    for b in "${_PB_BINS[@]}"; do
        if [[ -x "$PACKBOX_BIN_DIR/$b" ]]; then
            det "${G}$b${N} OK"
        else
            det "${R}$b${N} FAIL"
            all_ok=false
        fi
    done
    [[ "$all_ok" != "true" ]] && err "Missing binaries / Binarios faltantes"
    ok "$(t L_BINARIES_OK)"

    # ─── Éxito ──────────────────────────────────────────────────────────────
    # ─── Success ────────────────────────────────────────────────────────────
    box_ok "$(t L_INSTALLED_OK)"
    echo -e "  ${BD}Features:${N}"
    det "i18n: $(t L_LANG_NAME) (+8 more / más)"
    det "$(t L_COMPRESS_OK)"
    det "$(t L_DESKTOP_OK)"
    det "$(t L_DNS_OK)"
    det "Sandbox: cap-drop ALL · red opt-in / network opt-in"
    det "Journal: ~/.packbox/.installed-journal"
    echo ""
    echo -e "  ${BD}$(t L_NEXT_STEPS):${N}"
    det "1. $(t L_RELOAD_SHELL): source ~/.bashrc"
    det "2. $(t L_VERIFY): packbox-diagnose"
    det "3. $(t L_USE_DETECTOR): ./packbox-packager.sh"
    echo ""
}