#!/usr/bin/env bash
# =============================================================================
# lib/generate.sh — Crea directorios y copia el árbol src/.
# lib/generate.sh — Creates directories and copies the src/ tree.
#
# Asume / Assumes: ui.sh, paths.sh, common.sh, journal.sh
# Provee / Provides: create_dirs, copy_src_tree
# =============================================================================

# ─── Creación de directorios ─────────────────────────────────────────────────
# ─── Directory creation ──────────────────────────────────────────────────────
# create_dirs — crea todos los directorios de Packbox y los registra.
# create_dirs — creates all Packbox directories and registers them.
create_dirs() {
    hdr "$(t L_STEP3)"

    local dirs=(
        "$PACKBOX_INSTALL_DIR"
        "$PACKBOX_BIN_DIR"
        "$PACKBOX_SRC_DIR"
        "$PACKBOX_GO_PATH"
        "$PACKBOX_HOME"
        "$PACKBOX_STORE_DIR"
        "$PACKBOX_APPS_DIR"
        "$PACKBOX_MODS_DIR"
        "$PACKBOX_EXPORTS_DIR"
        "$PACKBOX_TMP_DIR"
        "$PACKBOX_CONFIG_DIR"
        "$PACKBOX_LANG_DIR"
    )

    local d
    for d in "${dirs[@]}"; do
        if [[ ! -d "$d" ]]; then
            mkdir -p "$d" || {
                err "mkdir failed: $d"
            }
            journal_register_dir "$d"
        fi
    done

    # Store necesita permisos 755 explícitos.
    # Store needs explicit 755 perms.
    chmod 755 "$PACKBOX_STORE_DIR" 2>/dev/null || true

    ok "~/.packbox/ ($(t L_STEP3))"
}

# ─── Copia del árbol Go ─────────────────────────────────────────────────────
# ─── Go tree copy ───────────────────────────────────────────────────────────
# copy_src_tree — copia $PACKBOX_ROOT/src a $PACKBOX_SRC_DIR.
# copy_src_tree — copies $PACKBOX_ROOT/src to $PACKBOX_SRC_DIR.
copy_src_tree() {
    hdr "$(t L_STEP4)"

    local src_root="$PACKBOX_ROOT/src"
    if [[ ! -d "$src_root" ]]; then
        err "src/ not found at $src_root"
    fi
    if [[ ! -f "$src_root/go.mod" ]]; then
        err "go.mod not found in $src_root"
    fi

    # Limpiar copia anterior (si existe).
    # Clean previous copy (if any).
    if [[ -d "$PACKBOX_SRC_DIR" ]]; then
        rm -rf "$PACKBOX_SRC_DIR"
    fi
    mkdir -p "$PACKBOX_SRC_DIR"

    # Copiar recursivamente preservando permisos.
    # Copy recursively preserving permissions.
    if ! cp -r "$src_root/." "$PACKBOX_SRC_DIR/"; then
        err "copy failed: $src_root → $PACKBOX_SRC_DIR"
    fi

    journal_register_dir "$PACKBOX_SRC_DIR"

    local n
    n=$(find "$PACKBOX_SRC_DIR" -name '*.go' 2>/dev/null | wc -l)
    ok "$n .go files copied to ~/.packbox/src"
}