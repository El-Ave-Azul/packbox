#!/usr/bin/env bash
# =============================================================================
# lib/uninstall.sh — Desinstalación basada en journal.
# lib/uninstall.sh — Journal-based uninstallation.
#
# Asume / Assumes: ui.sh, paths.sh, common.sh, journal.sh
# Provee / Provides: do_uninstall
# =============================================================================

# _LAST_FREED — canal de retorno de _uninstall_dir.
# _LAST_FREED — return channel for _uninstall_dir.
_LAST_FREED=0

# _uninstall_dir <path> — borra un directorio y registra bytes liberados.
# _uninstall_dir <path> — deletes a directory and records freed bytes.
#
# Robusto contra archivos read-only (Go module cache, pip cache, etc.).
# Robust against read-only files (Go module cache, pip cache, etc.).
_uninstall_dir() {
    local d="$1"
    _LAST_FREED=0
    [[ -e "$d" ]] || return 0

    # Medir tamaño antes de borrar.
    # Measure size before deleting.
    local s=0
    if [[ -d "$d" ]]; then
        s=$(du -sb "$d" 2>/dev/null | awk '{print $1}')
    elif [[ -f "$d" ]]; then
        s=$(stat -c%s "$d" 2>/dev/null || echo 0)
    fi
    [[ -z "$s" ]] && s=0

    # ─── Intento 1: rm -rf directo (rápido) ────────────────────────────────
    # ─── Attempt 1: direct rm -rf (fast) ───────────────────────────────────
    rm -rf "$d" 2>/dev/null || true

    # ─── Intento 2: si algo quedó, hacer todo escribible y reintentar ──────
    # ─── Attempt 2: if something remains, make writable and retry ──────────
    if [[ -e "$d" ]]; then
        # Go module cache usa 0444 en archivos y 0555 en directorios.
        # Go module cache uses 0444 on files and 0555 on dirs.
        # chmod -R u+w los devuelve a escritura para el owner.
        # chmod -R u+w returns write permission to the owner.
        if [[ -d "$d" ]]; then
            chmod -R u+w "$d" 2>/dev/null || true
        else
            chmod u+w "$d" 2>/dev/null || true
        fi
        rm -rf "$d" 2>/dev/null || true
    fi

    # ─── Intento 3: último recurso con find ────────────────────────────────
    # ─── Attempt 3: last resort with find ──────────────────────────────────
    if [[ -d "$d" ]]; then
        find "$d" -type d -exec chmod u+w {} + 2>/dev/null || true
        find "$d" -type f -exec chmod u+w {} + 2>/dev/null || true
        rm -rf "$d" 2>/dev/null || true
    fi

    # Solo reportamos bytes liberados si de verdad desapareció.
    # Only report freed bytes if it actually disappeared.
    if [[ ! -e "$d" ]]; then
        _LAST_FREED="$s"
    else
        # Avisar si algo no se pudo borrar — para no mentir.
        # Warn if something couldn't be deleted — don't lie.
        warn "Could not fully remove: $d"
        warn "No se pudo eliminar del todo: $d"
        _LAST_FREED=0
    fi
}

# do_uninstall — desinstalación interactiva.
# do_uninstall — interactive uninstallation.
do_uninstall() {
    show_banner_installer
    hdr "$(t L_UNINSTALL_TITLE)"

    # ─── Sin journal: fallback ──────────────────────────────────────────────
    # ─── No journal: fallback ───────────────────────────────────────────────
    if ! journal_exists; then
        warn "$(_tt L_NO_JOURNAL "No installation journal found")"
        det "Journal: $PACKBOX_JOURNAL"
        det "$(_tt L_NO_JOURNAL_MSG "Cannot safely uninstall without the journal.")"
        echo ""
        if [[ -d "$PACKBOX_INSTALL_DIR" ]]; then
            if ask_yn "$(_tt L_LEGACY_CLEANUP "Run legacy heuristic cleanup?")" "n"; then
                _uninstall_legacy
            fi
        else
            info "$(t L_UNINSTALL_NOTHING)"
        fi
        read -rp "  ENTER..."
        return 0
    fi

    # ─── Leer journal ──────────────────────────────────────────────────────
    # ─── Read journal ──────────────────────────────────────────────────────
    info "$(t L_UNINSTALL_SCAN)"
    echo ""

    local n_dirs n_files n_symlinks total=0
    n_dirs=$(journal_count dir_created)
    n_files=$(journal_count file_created)
    n_symlinks=$(journal_count symlink_created)

    # Sumar tamaños sin duplicar padres/hijos.
    # Sum sizes without double-counting parents/children.
    local _d
    while IFS= read -r _d; do
        [[ -d "$_d" ]] || continue
        local _s
        _s=$(du -sb "$_d" 2>/dev/null | awk '{print $1}')
        [[ -n "$_s" ]] && total=$((total + _s))
    done < <(journal_list dir_created)

    # ─── Resumen ───────────────────────────────────────────────────────────
    # ─── Summary ───────────────────────────────────────────────────────────
    echo -e "  ${BD}$(t L_UNINSTALL_WILL)${N}"
    echo -e "  ${DM}${HR_T}${N}"
    printf "  %-45s ${BD}%9d${N}\n" "$(_tt L_DIRS "Directories")" "$n_dirs"
    printf "  %-45s ${BD}%9d${N}\n" "$(_tt L_FILES "Files")"       "$n_files"
    printf "  %-45s ${BD}%9d${N}\n" "$(_tt L_SYMLINKS "Symlinks")" "$n_symlinks"
    echo -e "  ${DM}${HR_T}${N}"
    echo -e "  ${BD}$(t L_TOTAL): $(hs "$total")${N}"
    echo ""
    echo -e "  ${DM}$(_tt L_UNINSTALL_HINT "k = binaries only · s = full · q = cancel")${N}"
    echo ""

    # ─── Modo ──────────────────────────────────────────────────────────────
    # ─── Mode ──────────────────────────────────────────────────────────────
    echo -en "  ${Y}?${N} $(t L_UNINSTALL_MODE)"
    local mode
    read -r mode
    local FULL_UNINSTALL
    case "$mode" in
        k|K)
            info "$(t L_UNINSTALL_BIN_ONLY)"
            det "$(_tt L_KEEPS "Keeps apps, store, menus, .bashrc")"
            FULL_UNINSTALL=0
            ;;
        s|S)
            info "$(t L_UNINSTALL_FULL)"
            det "$(_tt L_REMOVES_ALL "Removes binaries + apps + store + menus + config")"
            FULL_UNINSTALL=1
            ;;
        q|Q|"")
            warn "$(t L_ABORT)"
            read -rp "  ENTER..."
            return 0
            ;;
        *)
            warn "$(t L_INVALID)"
            read -rp "  ENTER..."
            return 0
            ;;
    esac

    # ─── Confirmación simple ───────────────────────────────────────────────
    # ─── Simple confirmation ───────────────────────────────────────────────
    echo ""
    printf "  ${Y}?${N} $(t L_UNINSTALL_CONFIRM)"
    local reply
    read -r -n 1 reply
    echo
    [[ ! "$reply" =~ ^[SsYy]$ ]] && { warn "$(t L_ABORT)"; read -rp "  ENTER..."; return 0; }

    # ─── Confirmación fuerte ───────────────────────────────────────────────
    # ─── Strong confirmation ───────────────────────────────────────────────
    echo ""
    printf "  ${Y}?${N} $(t L_UNINSTALL_TYPE)"
    local token
    read -r token
    if [[ "$token" != "DELETE" ]]; then
        warn "$(t L_UNINSTALL_MISMATCH)"
        read -rp "  ENTER..."
        return 0
    fi

    echo ""
    local freed=0

    # ─── 1. Bloque de .bashrc (solo modo completo) ─────────────────────────
    # ─── 1. .bashrc block (full mode only) ─────────────────────────────────
    if [[ $FULL_UNINSTALL -eq 1 ]]; then
        local ms me
        ms=$(journal_get bashrc_block marker_start)
        me=$(journal_get bashrc_block marker_end)
        if [[ -n "$ms" && -n "$me" ]]; then
            info "$(t L_UNINSTALL_BASHRC)"
            _uninstall_bashrc "$ms" "$me"
        fi
    fi

    # ─── 2. Symlinks ───────────────────────────────────────────────────────
    # ─── 2. Symlinks ───────────────────────────────────────────────────────
    if [[ $FULL_UNINSTALL -eq 1 ]]; then
        local sl
        while IFS= read -r sl; do
            [[ -z "$sl" ]] && continue
            local path="${sl%%|*}"
            [[ -L "$path" ]] || continue
            rm -f "$path" 2>/dev/null || true
        done < <(journal_list symlink_created)
        ok "$(t L_UNINSTALL_SYMLINKS)"
    fi

    # ─── 3. Entradas .desktop + iconos (solo modo completo) ────────────────
    # ─── 3. .desktop entries + icons (full mode only) ──────────────────────
    if [[ $FULL_UNINSTALL -eq 1 ]]; then
        local df _count=0
        while IFS= read -r df; do
            [[ -z "$df" ]] && continue
            rm -f "$df" 2>/dev/null || true
            _count=$((_count + 1))
        done < <(find "$PACKBOX_DESKTOP_DIR" -maxdepth 1 -name 'packbox-*.desktop' 2>/dev/null)
        [[ $_count -gt 0 ]] && ok "$(t L_UNINSTALL_DESKTOP): $_count"

        local ico _icount=0
        while IFS= read -r ico; do
            [[ -z "$ico" ]] && continue
            rm -f "$ico" 2>/dev/null || true
            _icount=$((_icount + 1))
        done < <(find "$PACKBOX_ICONS_DIR" \( -name 'packbox-*.png' -o -name 'packbox-*.svg' \) 2>/dev/null)
        [[ $_icount -gt 0 ]] && ok "$(t L_UNINSTALL_ICONS): $_icount"

        # Refrescar cachés
        # Refresh caches
        command -v update-desktop-database &>/dev/null && \
            update-desktop-database "$PACKBOX_DESKTOP_DIR" 2>/dev/null || true
        command -v gtk-update-icon-cache &>/dev/null && \
            gtk-update-icon-cache -f -t "$PACKBOX_ICONS_DIR" 2>/dev/null || true
    fi

    # ─── 4. Config y datos (solo modo completo) ────────────────────────────
    # ─── 4. Config and data (full mode only) ───────────────────────────────
    if [[ $FULL_UNINSTALL -eq 1 ]]; then
        if [[ -d "$PACKBOX_CONFIG_DIR" ]]; then
            info "$(t L_UNINSTALL_REMOVING) ~/.config/packbox/"
            _uninstall_dir "$PACKBOX_CONFIG_DIR"
            freed=$((freed + _LAST_FREED))
        fi
        if [[ -d "$PACKBOX_HOME" ]]; then
            info "$(t L_UNINSTALL_REMOVING) ~/.local/share/packbox/"
            _uninstall_dir "$PACKBOX_HOME"
            freed=$((freed + _LAST_FREED))
        fi
    fi

    # ─── 5. Directorio de instalación (siempre) ────────────────────────────
    # ─── 5. Installation directory (always) ────────────────────────────────
    # Se hace al final porque contiene el journal.
    # Done last because it contains the journal.
    if [[ -d "$PACKBOX_INSTALL_DIR" ]]; then
        info "$(t L_UNINSTALL_REMOVING) ~/.packbox/"
        _uninstall_dir "$PACKBOX_INSTALL_DIR"
        freed=$((freed + _LAST_FREED))
    fi

    # ─── 6. ~/packbox antiguo (opcional) ───────────────────────────────────
    # ─── 6. Old ~/packbox (optional) ───────────────────────────────────────
    if [[ -d "$PACKBOX_OLD_DIR" ]]; then
        echo ""
        printf "  ${Y}?${N} $(t L_UNINSTALL_OLD_PACKBOX)"
        read -r -n 1 reply
        echo
        if [[ "$reply" =~ ^[SsYy]$ ]]; then
            info "$(t L_UNINSTALL_REMOVING) ~/packbox/"
            _uninstall_dir "$PACKBOX_OLD_DIR"
            freed=$((freed + _LAST_FREED))
        fi
    fi

    # ─── Éxito ──────────────────────────────────────────────────────────────
    # ─── Success ────────────────────────────────────────────────────────────
    echo ""
    box_ok "$(t L_UNINSTALL_DONE)"
    echo -e "  ${BD}$(t L_UNINSTALL_FREED): $(hs "$freed")${N}"
    echo ""
    if [[ $FULL_UNINSTALL -eq 0 ]]; then
        echo -e "  ${DM}$(_tt L_KEPT_MSG "Apps and store kept at ~/.local/share/packbox/")${N}"
        echo ""
    fi
    read -rp "  ENTER..."
}

# ─── Fallback sin journal ────────────────────────────────────────────────────
# ─── Fallback without journal ────────────────────────────────────────────────
_uninstall_legacy() {
    warn "$(_tt L_LEGACY_WARN "Heuristic cleanup — may leave leftovers")"
    echo ""
    local freed=0

    # .bashrc
    local bashrc="$HOME/.bashrc"
    if [[ -f "$bashrc" ]] && grep -qF "# >>> packbox initialize >>>" "$bashrc"; then
        _uninstall_bashrc "# >>> packbox initialize >>>" "# <<< packbox initialize <<<"
    fi

    # Symlinks
    local f
    for f in "$HOME/.local/bin"/packbox-*; do
        [[ -L "$f" ]] || continue
        rm -f "$f" 2>/dev/null || true
    done

    # Desktop + icons
    find "$PACKBOX_DESKTOP_DIR" -maxdepth 1 -name 'packbox-*.desktop' -delete 2>/dev/null || true
    find "$PACKBOX_ICONS_DIR" \( -name 'packbox-*.png' -o -name 'packbox-*.svg' \) -delete 2>/dev/null || true

    # Standard dirs
    local d
    for d in "$PACKBOX_CONFIG_DIR" "$PACKBOX_HOME" "$PACKBOX_INSTALL_DIR"; do
        [[ -d "$d" ]] || continue
        _uninstall_dir "$d"
        freed=$((freed + _LAST_FREED))
    done

    echo ""
    ok "$(t L_UNINSTALL_DONE): $(hs "$freed")"
    echo ""
}
