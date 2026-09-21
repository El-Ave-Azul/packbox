#!/usr/bin/env bash
# =============================================================================
# lib/journal.sh — Registro de todo lo que el instalador modifica.
# lib/journal.sh — Log of everything the installer modifies.
#
# El desinstalador solo borra lo que este diario lista.
# The uninstaller only deletes what this journal lists.
#
# Formato / Format: legible por humanos, parseable con awk/grep.
# Human-readable, parseable with awk/grep.
# Ubicación / Location: ~/.packbox/.installed-journal
# =============================================================================

# ─── Escritura ───────────────────────────────────────────────────────────────
# ─── Writing ─────────────────────────────────────────────────────────────────

# journal_init — crea el diario con la cabecera.
# journal_init — creates the journal with header.
journal_init() {
    mkdir -p "$(dirname "$PACKBOX_JOURNAL")" 2>/dev/null
    cat > "$PACKBOX_JOURNAL" <<'JOURNAL_HEADER'
# ═══════════════════════════════════════════════════════════════
# Packbox Installation Journal
# Diario de instalación de Packbox
# ═══════════════════════════════════════════════════════════════
# Este archivo registra TODO lo que el instalador crea o modifica.
# This file logs EVERYTHING the installer creates or modifies.
# El desinstalador solo borra lo que aquí aparece.
# The uninstaller only deletes what appears here.
# No editar a mano. / Do not edit by hand.
# ═══════════════════════════════════════════════════════════════

JOURNAL_HEADER
    journal_write "meta" "installer_version" "${PACKBOX_VERSION:-unknown}"
    journal_write "meta" "install_date" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}

# journal_write <section> <key> <value>
# Escribe una línea clave = "valor" en el diario.
# Writes a key = "value" line to the journal.
journal_write() {
    local section="$1" key="$2" value="$3"
    [[ -f "$PACKBOX_JOURNAL" ]] || journal_init
    printf '%s.%s = "%s"\n' "$section" "$key" "$value" >> "$PACKBOX_JOURNAL"
}

# journal_write_raw <section> <line>
# Escribe una línea cruda en el diario.
# Writes a raw line to the journal.
journal_write_raw() {
    local section="$1" line="$2"
    [[ -f "$PACKBOX_JOURNAL" ]] || journal_init
    printf '%s: %s\n' "$section" "$line" >> "$PACKBOX_JOURNAL"
}

# journal_register_dir <path> — registra un directorio creado.
# journal_register_dir <path> — registers a created directory.
journal_register_dir() {
    journal_write_raw "dir_created" "$1"
}

# journal_register_file <path> — registra un archivo creado.
# journal_register_file <path> — registers a created file.
journal_register_file() {
    journal_write_raw "file_created" "$1"
}

# journal_register_symlink <path> <target>
# Registra un symlink creado.
# Registers a created symlink.
journal_register_symlink() {
    journal_write_raw "symlink_created" "$1|$2"
}

# journal_register_bashrc <marker_start> <marker_end>
# Registra el bloque añadido a .bashrc.
# Registers the block added to .bashrc.
journal_register_bashrc() {
    journal_write "bashrc_block" "marker_start" "$1"
    journal_write "bashrc_block" "marker_end" "$2"
}

# ─── Lectura ─────────────────────────────────────────────────────────────────
# ─── Reading ─────────────────────────────────────────────────────────────────

# journal_exists — devuelve 0 si existe el diario.
# journal_exists — returns 0 if the journal exists.
journal_exists() {
    [[ -f "$PACKBOX_JOURNAL" ]]
}

# journal_list <section> — imprime las entradas de una sección.
# journal_list <section> — prints entries of a section.
journal_list() {
    local section="$1"
    [[ -f "$PACKBOX_JOURNAL" ]] || return 1
    grep "^${section}: " "$PACKBOX_JOURNAL" 2>/dev/null | sed "s/^${section}: //"
}

# journal_count <section> — cuenta entradas de una sección.
# journal_count <section> — counts entries of a section.
journal_count() {
    local section="$1"
    [[ -f "$PACKBOX_JOURNAL" ]] || { echo 0; return; }
    grep -c "^${section}: " "$PACKBOX_JOURNAL" 2>/dev/null || echo 0
}

# journal_get <section> <key> — lee un valor puntual.
# journal_get <section> <key> — reads a single value.
journal_get() {
    local section="$1" key="$2"
    [[ -f "$PACKBOX_JOURNAL" ]] || return 1
    grep "^${section}\.${key} = " "$PACKBOX_JOURNAL" 2>/dev/null | \
        head -1 | sed -E 's/.*= "([^"]*)".*/\1/'
}