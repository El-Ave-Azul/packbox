#!/usr/bin/env bash
# =============================================================================
# lib/compile.sh — Compilación de binarios Go, tests y configuración de PATH.
# lib/compile.sh — Go binary compilation, tests, and PATH configuration.
#
# Asume / Assumes: ui.sh, paths.sh, common.sh, journal.sh, go.sh
# Provee / Provides: compile_go, run_tests, configure_path
# =============================================================================

# Lista canónica de los 15 binarios.
# Canonical list of the 15 binaries.
_PB_BINS=(
    packbox-pack
    packbox-install
    packbox-run
    packbox-list
    packbox-remove
    packbox-gc
    packbox-verify
    packbox-export
    packbox-import
    packbox-module
    packbox-diagnose
    packbox-update
    packbox-sign
    packbox-fetch
    packbox-debug
)

# ─── Variables de entorno de Go ─────────────────────────────────────────────
# ─── Go environment variables ───────────────────────────────────────────────
_go_env() {
    export GOROOT="$PACKBOX_GO_DIR"
    export GOPATH="$PACKBOX_GO_PATH"
    export PATH="$PACKBOX_GO_BIN:$GOPATH/bin:$PATH"
    export GOFLAGS="${GOFLAGS:-}"
    export CGO_ENABLED="${CGO_ENABLED:-0}"
}

# ─── Compilación ─────────────────────────────────────────────────────────────
# ─── Compilation ─────────────────────────────────────────────────────────────
# compile_go — compila los 15 binarios en ~/.packbox/bin/.
# compile_go — compiles the 15 binaries into ~/.packbox/bin/.
compile_go() {
    hdr "$(t L_STEP5)"
    _go_env

    if [[ ! -x "$PACKBOX_GO_BIN/go" ]]; then
        err "Go not found at $PACKBOX_GO_BIN/go"
    fi

    cd "$PACKBOX_SRC_DIR" || err "cd failed: $PACKBOX_SRC_DIR"

    # ─── Descarga de dependencias ───────────────────────────────────────────
    # ─── Dependency download ────────────────────────────────────────────────
    info "Downloading Go modules / Descargando módulos Go..."
    if ! go mod download 2>&1 | tail -3; then
        err "go mod download failed (network?)"
    fi
    go mod tidy 2>&1 | tail -3 || true

    # ─── Verificar que existen todos los cmd/ ───────────────────────────────
    # ─── Verify all cmd/ exist ──────────────────────────────────────────────
    local b missing=()
    for b in "${_PB_BINS[@]}"; do
        [[ -f "cmd/$b/main.go" ]] || missing+=("$b")
    done
    if (( ${#missing[@]} > 0 )); then
        err "missing cmd/ dirs: ${missing[*]}"
    fi

    # ─── Compilar uno a uno con barra de progreso ──────────────────────────
    # ─── Compile one by one with progress bar ──────────────────────────────
    local n=${#_PB_BINS[@]}
    local i=0
    for b in "${_PB_BINS[@]}"; do
        i=$((i + 1))
        progress "$i" "$n" "$b"
        if ! go build -o "$PACKBOX_BIN_DIR/$b" "./cmd/$b" 2>&1; then
            echo ""
            echo -e "  ${R}Compilation error in / Error de compilación en $b:${N}"
            echo ""
            go build -o "$PACKBOX_BIN_DIR/$b" "./cmd/$b" 2>&1 | head -20
            echo ""
            err "Build failed: $b"
        fi
        chmod +x "$PACKBOX_BIN_DIR/$b"
        journal_register_file "$PACKBOX_BIN_DIR/$b"
    done

    echo ""
    ok "15 binaries in ~/.packbox/bin/"
    cd "$HOME" || true
}

# ─── Tests ───────────────────────────────────────────────────────────────────
# ─── Tests ───────────────────────────────────────────────────────────────────
# run_tests — corre go test ./... en el árbol copiado.
# run_tests — runs go test ./... in the copied tree.
run_tests() {
    hdr "$(t L_STEP6)"
    _go_env

    cd "$PACKBOX_SRC_DIR" || err "cd failed: $PACKBOX_SRC_DIR"

    local out
    if out=$(go test ./... 2>&1); then
        local pkgs
        pkgs=$(echo "$out" | grep -c '^ok' || echo 0)
        ok "$(_tt L_TESTS_OK "Tests OK"): $pkgs packages"
    else
        echo "$out" | tail -20
        warn "$(_tt L_TESTS_FAIL "Some tests failed")"
    fi
    cd "$HOME" || true
}

# ─── PATH y symlinks ────────────────────────────────────────────────────────
# ─── PATH and symlinks ──────────────────────────────────────────────────────
# configure_path — añade PATH a .bashrc + crea symlinks.
# configure_path — adds PATH to .bashrc + creates symlinks.
configure_path() {
    hdr "$(t L_STEP7)"

    local marker_start="# >>> packbox initialize >>>"
    local marker_end="# <<< packbox initialize <<<"
    local bashrc="$HOME/.bashrc"

    # ─── Limpiar restos de versiones antiguas ───────────────────────────────
    # ─── Clean leftovers from old versions ─────────────────────────────────
    if [[ -f "$bashrc" ]]; then
        # v0.1.0: líneas suelas con /packbox/bin
        # v0.1.0: bare lines with /packbox/bin
        if grep -qE '/packbox/bin' "$bashrc" 2>/dev/null; then
            if grep -vE '/\.packbox/bin' "$bashrc" | grep -qE '/packbox/bin' 2>/dev/null; then
                cp "$bashrc" "$bashrc.packbox.bak"
                sed -i '\|packbox/bin|{/\.packbox/bin/!d}' "$bashrc"
                ok "Old PATH entries cleaned (backup: ~/.bashrc.packbox.bak)"
            fi
        fi

        # Bloque previo entre marcadores
        # Previous block between markers
        if grep -qF "$marker_start" "$bashrc" && grep -qF "$marker_end" "$bashrc"; then
            sed -i "\|$marker_start|,\|$marker_end|d" "$bashrc"
        fi
    fi

    # ─── Añadir bloque nuevo ────────────────────────────────────────────────
    # ─── Add new block ──────────────────────────────────────────────────────
    {
        echo ""
        echo "$marker_start"
        echo "# Packbox v${PACKBOX_VERSION} · Do not edit between these markers"
        echo "# Packbox v${PACKBOX_VERSION} · No editar entre estos marcadores"
        echo "export PATH=\"$PACKBOX_BIN_DIR:\$PATH\""
        echo "$marker_end"
    } >> "$bashrc"

    journal_register_bashrc "$marker_start" "$marker_end"
    ok "PATH added to ~/.bashrc"

    # ─── Symlinks en ~/.local/bin ───────────────────────────────────────────
    # ─── Symlinks in ~/.local/bin ───────────────────────────────────────────
    if [[ -d "$HOME/.local/bin" ]]; then
        local b target
        for b in "$PACKBOX_BIN_DIR"/*; do
            [[ -x "$b" ]] || continue
            target="$HOME/.local/bin/$(basename "$b")"
            ln -sf "$b" "$target" 2>/dev/null || true
            journal_register_symlink "$target" "$b"
        done
        ok "Symlinks in ~/.local/bin"
    fi

    export PATH="$PACKBOX_BIN_DIR:$PATH"
}