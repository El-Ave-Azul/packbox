#!/usr/bin/env bash
# =============================================================================
# packbox-install.sh — Entry point del instalador de Packbox.
# packbox-install.sh — Packbox installer entry point.
#
# Solo hace bootstrap + despacho. Sin lógica de negocio.
# Only bootstraps and dispatches. No business logic.
#
# Uso / Usage:
#   ./packbox-install.sh              # menú interactivo / interactive menu
#   ./packbox-install.sh --uninstall  # desinstalar / uninstall
#   ./packbox-install.sh --help       # ayuda / help
# =============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck disable=SC1090
source "$SCRIPT_DIR/lib/bootstrap.sh" || exit 1
_pb_bootstrap "$SCRIPT_DIR" || exit 1

main_installer "$@"