#!/usr/bin/env bash
# =============================================================================
# packbox-packager.sh — Entry point del empaquetador de Packbox.
# packbox-packager.sh — Packbox packager entry point.
#
# Solo hace bootstrap + despacho. Sin lógica de negocio.
# Only bootstraps and dispatches. No business logic.
#
# Uso / Usage:
#   ./packbox-packager.sh             # menú interactivo / interactive menu
#   ./packbox-packager.sh --help      # ayuda / help
# =============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck disable=SC1090
source "$SCRIPT_DIR/lib/bootstrap.sh" || exit 1
_pb_bootstrap "$SCRIPT_DIR" || exit 1

main_packager "$@"