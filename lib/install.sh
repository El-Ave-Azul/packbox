#!/usr/bin/env bash
# =============================================================================
# lib/install.sh — Orquestación de la instalación.
# lib/install.sh — Installation orchestration.
#
# Asume / Assumes: todo lo anterior del bootstrap.
#                 everything above from bootstrap.
# Provee / Provides: do_install, install_prebuilt
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

    # ─── Pasos 2-6: binarios (precompilados o compilados) ───────────────────
    # ─── Steps 2-6: binaries (prebuilt or compiled) ─────────────────────────
    if [[ "${PACKBOX_PREBUILT:-0}" == "1" ]]; then
        hdr "$(_tt L_PREBUILT "Binarios precompilados")"
        create_dirs
        install_prebuilt || err "$(_tt L_PREBUILT_FAIL "falló lo precompilado; reintenta sin --prebuilt para compilar")"
    else
        # ─── Paso 2: Go ─────────────────────────────────────────────────────
        # ─── Step 2: Go ─────────────────────────────────────────────────────
        hdr "$(t L_STEP2)"
        install_go

        # ─── Paso 3: directorios ────────────────────────────────────────────
        # ─── Step 3: directories ────────────────────────────────────────────
        create_dirs

        # ─── Paso 4: copiar src/ ────────────────────────────────────────────
        # ─── Step 4: copy src/ ──────────────────────────────────────────────
        copy_src_tree

        # ─── Paso 5: compilar ───────────────────────────────────────────────
        # ─── Step 5: compile ────────────────────────────────────────────────
        compile_go

        # ─── Paso 6: tests ──────────────────────────────────────────────────
        # ─── Step 6: tests ──────────────────────────────────────────────────
        run_tests
    fi

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

# install_prebuilt — descarga los binarios precompilados del release (arch del
# host), verifica el sha256 contra SHA256SUMS y los instala en ~/.packbox/bin/.
# install_prebuilt — downloads the prebuilt binaries from the release (host arch),
# verifies the sha256 against SHA256SUMS and installs them into ~/.packbox/bin/.
install_prebuilt() {
    local arch asset base tmp
    case "$(uname -m)" in
        x86_64|amd64)  arch=amd64 ;;
        aarch64|arm64) arch=arm64 ;;
        *) warn "$(_tt L_PREBUILT_ARCH "arquitectura no soportada") : $(uname -m)"; return 1 ;;
    esac
    asset="packbox-${PACKBOX_VERSION}-linux-${arch}.tar.gz"
    base="${PACKBOX_RELEASE_BASE:-https://github.com/${PACKBOX_REPO}/releases/download/v${PACKBOX_VERSION}}"
    tmp=$(mktemp -d) || return 1
    reg_cln "$tmp"

    info "$(_tt L_PREBUILT_DL "Descargando") $asset ..."
    if ! curl -fSL --progress-bar -o "$tmp/$asset" "$base/$asset"; then
        warn "$(_tt L_PREBUILT_NODL "no se pudo descargar el release") : $base"
        rm -rf "$tmp"; unreg_cln "$tmp"
        return 1
    fi

    # Integridad: sha256 contra el SHA256SUMS del release.
    # Integrity: sha256 against the release's SHA256SUMS.
    if curl -fsSL -o "$tmp/SHA256SUMS" "$base/SHA256SUMS"; then
        if ( cd "$tmp" && grep " $asset\$" SHA256SUMS | sha256sum -c - >/dev/null 2>&1 ); then
            ok "$(_tt L_PREBUILT_SUM "checksum OK")"
        else
            warn "$(_tt L_PREBUILT_BAD "checksum NO coincide")"
            rm -rf "$tmp"; unreg_cln "$tmp"
            return 1
        fi
    else
        warn "$(_tt L_PREBUILT_NOSUM "sin SHA256SUMS; se omite el checksum")"
    fi

    if ! tar -xzf "$tmp/$asset" -C "$PACKBOX_BIN_DIR"; then
        warn "$(_tt L_PREBUILT_EXTR "falló la extracción")"
        rm -rf "$tmp"; unreg_cln "$tmp"
        return 1
    fi
    chmod +x "$PACKBOX_BIN_DIR"/packbox-* 2>/dev/null || true
    rm -rf "$tmp"; unreg_cln "$tmp"

    local b missing=()
    for b in "${_PB_BINS[@]}"; do
        [[ -x "$PACKBOX_BIN_DIR/$b" ]] || missing+=("$b")
    done
    if (( ${#missing[@]} > 0 )); then
        warn "$(_tt L_PREBUILT_MISS "faltan binarios") : ${missing[*]}"
        return 1
    fi
    for b in "${_PB_BINS[@]}"; do
        journal_register_file "$PACKBOX_BIN_DIR/$b"
    done
    ok "${#_PB_BINS[@]} $(_tt L_PREBUILT_BINS "binarios instalados") ($arch)"
    return 0
}