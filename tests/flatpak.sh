#!/usr/bin/env bash
# =============================================================================
# tests/flatpak.sh — descubrimiento de deployments de Flatpak.
# tests/flatpak.sh — Flatpak deployment discovery.
#
# No necesita flatpak instalado: monta un layout falso con la MISMA forma que
# /var/lib/flatpak (…/app/<id>/<arch>/<branch>/<commit>/files, active en <branch>).
# No flatpak needed: it builds a fake layout shaped like /var/lib/flatpak
# (…/app/<id>/<arch>/<branch>/<commit>/files, active at <branch>).
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "$ROOT/lib/flatpak.sh"

pass() { printf '  \033[32mok\033[0m   %s\n' "$1"; }
fail() { printf '  \033[31mFAIL\033[0m %s\n' "$1" >&2; exit 1; }
step() { printf '\n== %s ==\n' "$1"; }

W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT
R="$W/flatpak"

step "flatpak deployment discovery"
mkdir -p "$R/app/org.test.App/x86_64/stable/C1/files/bin" \
         "$R/runtime/org.test.Platform/x86_64/46/RC/files"
touch "$R/app/org.test.App/x86_64/stable/C1/files/bin/app"
ln -s C1 "$R/app/org.test.App/x86_64/stable/active"
ln -s RC "$R/runtime/org.test.Platform/x86_64/46/active"
printf 'command=app\nruntime=org.test.Platform/x86_64/46\n' \
    > "$R/app/org.test.App/x86_64/stable/C1/metadata"
export FLATPAK_ROOT="$R"

[ "$(flatpak_applications)" = "org.test.App" ] \
    || fail "flatpak_applications did not list the app"
pass "lists apps"

dep="$(flatpak_deploy org.test.App)"
[ "$dep" = "$R/app/org.test.App/x86_64/stable/C1" ] \
    || fail "flatpak_deploy = $dep (expected the active commit; off-by-one regression?)"
pass "flatpak_deploy resolves the active commit"

[ "$(flatpak_meta "$dep" command)" = "app" ] \
    || fail "flatpak_meta did not read command= from metadata"
pass "flatpak_meta reads metadata"

[ "$(flatpak_runtime_dir org.test.Platform/x86_64/46)" = "$R/runtime/org.test.Platform/x86_64/46/RC" ] \
    || fail "flatpak_runtime_dir did not resolve the runtime"
pass "flatpak_runtime_dir resolves the runtime"

# _fp_pause must not recurse (old bug) nor hang without a TTY.
_fp_pause </dev/null || fail "_fp_pause returned non-zero"
pass "_fp_pause does not recurse or hang"

printf '\n\033[32m== flatpak tests: ALL GREEN ==\033[0m\n'
