#!/usr/bin/env bash
# =============================================================================
# lib/bootstrap.sh — Sourcea todos los módulos en orden estricto.
# lib/bootstrap.sh — Sources all modules in strict order.
#
# No define lógica de negocio. Solo carga y verifica.
# No business logic. Only loads and verifies.
# =============================================================================

# Orden de sourceado. Cada módulo ASUME que los anteriores ya están cargados.
# Sourcing order. Each module ASSUMES the previous ones are already loaded.
_PB_MODULES=(
    # ─── Base: sin dependencias ──────────────────────────────────────────────
    # ─── Base: no dependencies ──────────────────────────────────────────────
    "lib/common.sh"          # trap, _cleanup, tmpdir, ask_yn, ask_txt, _tt
    "lib/ui.sh"              # info/ok/warn/err/det/hdr/box/progress/hs
    "lib/paths.sh"           # PACKBOX_* (única fuente de verdad / single source of truth)
    "lib/journal.sh"         # journal_init, journal_write, journal_list

    # ─── i18n: depende de paths (PACKBOX_LANG_DIR) ───────────────────────────
    # ─── i18n: depends on paths (PACKBOX_LANG_DIR) ──────────────────────────
    "i18n/common.sh"         # t, _tt, select_language, load_lang
    "i18n/es.sh"
    "i18n/en.sh"
    "i18n/fr.sh"
    "i18n/de.sh"
    "i18n/it.sh"
    "i18n/pt.sh"
    "i18n/zh.sh"
    "i18n/ja.sh"
    "i18n/ko.sh"

    # ─── Sistema: depende de ui + paths ──────────────────────────────────────
    # ─── System: depends on ui + paths ───────────────────────────────────────
    "lib/distro.sh"          # detect_distro, install_pkgs
    "lib/go.sh"              # install_go

    # ─── Build: depende de paths + ui ────────────────────────────────────────
    # ─── Build: depends on paths + ui ────────────────────────────────────────
    "lib/generate.sh"        # create_dirs, copy_src_tree
    "lib/compile.sh"         # compile_go, run_tests, configure_path

    # ─── Lógica de negocio ──────────────────────────────────────────────────
    # ─── Business logic ─────────────────────────────────────────────────────
    "lib/install.sh"         # do_install
    "lib/uninstall.sh"       # do_uninstall
    "lib/detect.sh"          # scan_bundles, scan_desktop, reg_app
    "lib/pack.sh"            # pack_normal/portable/bundle/module
    "lib/desktop.sh"         # create_desktop_entry
    "lib/export.sh"          # export_app
    "lib/import.sh"          # import_app

    # ─── Menús (últimos: usan todo lo anterior) ─────────────────────────────
    # ─── Menus (last: use everything above) ─────────────────────────────────
    "lib/main-installer.sh"  # main_installer
    "lib/main-packager.sh"   # main_packager
)

# =============================================================================
# _pb_bootstrap <root>
# Carga todos los módulos desde <root>.
# Loads all modules from <root>.
# =============================================================================
_pb_bootstrap() {
    local root="${1:-}"
    if [[ -z "$root" || ! -d "$root" ]]; then
        echo "ERROR: _pb_bootstrap requiere la raíz del proyecto" >&2
        echo "ERROR: _pb_bootstrap requires the project root" >&2
        return 1
    fi
    export PACKBOX_ROOT="$root"

    # Verificar que existen todos antes de sourcear ninguno.
    # Verify all exist before sourcing any.
    # Así si falta uno, no queda un estado a medias.
    # This way, if one is missing, no half-loaded state remains.
    local m f missing=()
    for m in "${_PB_MODULES[@]}"; do
        f="$root/$m"
        [[ -f "$f" ]] || missing+=("$m")
    done
    if (( ${#missing[@]} > 0 )); then
        echo "ERROR: faltan módulos / missing modules:" >&2
        printf '  - %s\n' "${missing[@]}" >&2
        return 1
    fi

    # Sourcear en orden.
    # Source in order.
    for m in "${_PB_MODULES[@]}"; do
        # shellcheck disable=SC1090
        source "$root/$m" || {
            echo "ERROR: fallo al sourcear $m" >&2
            echo "ERROR: failed to source $m" >&2
            return 1
        }
    done

    # Setup de trap tras sourcear common.sh (que define _cleanup).
    # Trap setup after sourcing common.sh (which defines _cleanup).
    trap '_cleanup' EXIT INT TERM

    return 0
}