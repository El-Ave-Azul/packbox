#!/usr/bin/env bash
# =============================================================================
# tests/integration.sh — flujo end-to-end automatizado.
# tests/integration.sh — automated end-to-end flow.
#
#   pack → install → export (auto y --compress store) → import → run → firma
#   pack → install → export (auto & --compress store) → import → run → sign
#
# Corre en un HOME aislado bajo el propio repo (mismo FS que el proyecto, NO
# /tmp), para reproducir bugs cross-device: el staging del export va a /tmp
# (tmpfs) mientras las celdas viven en el HOME (p.ej. btrfs).
# Runs in an isolated HOME under the repo (same FS as the project, NOT /tmp), so
# cross-device bugs surface: export staging goes to /tmp (tmpfs) while cells
# live in $HOME (e.g. btrfs).
#
# Uso / Usage:  bash tests/integration.sh
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$ROOT/.itest"
HOME_DIR="$WORK/home"
BIN="$HOME_DIR/.packbox/bin"
APPS="$HOME_DIR/.local/share/packbox/apps"
MODS="$HOME_DIR/.local/share/packbox/mods"
EXPORTS="$HOME_DIR/.local/share/packbox/exports"
export HOME="$HOME_DIR"
# Keep the Go caches OUTSIDE the isolated HOME (which is wiped at the end): a
# read-only module cache inside it would make rm -rf fail.
export GOPATH="${PACKBOX_ITEST_GOPATH:-/tmp/packbox-itest/gopath}"
export GOCACHE="${PACKBOX_ITEST_GOCACHE:-/tmp/packbox-itest/gocache}"

pass() { printf '  \033[32mok\033[0m   %s\n' "$1"; }
fail() { printf '  \033[31mFAIL\033[0m %s\n' "$1" >&2; exit 1; }
step() { printf '\n== %s ==\n' "$1"; }

command -v bwrap >/dev/null || fail "bubblewrap (bwrap) is required"
command -v go    >/dev/null || fail "go is required to build the binaries"
rm -rf "$WORK"
mkdir -p "$BIN" "$APPS" "$MODS" "$EXPORTS" \
         "$HOME_DIR/.local/share/packbox/store" "$HOME_DIR/.config/packbox/lang"
echo en > "$HOME_DIR/.config/packbox/lang/current"

# Do we actually exercise the cross-device path? The export stages under /tmp.
if [ "$(stat -f -c %T "$WORK" 2>/dev/null)" = "$(stat -f -c %T /tmp 2>/dev/null)" ]; then
    printf '  \033[33mnote\033[0m %s\n' "$WORK and /tmp share a filesystem: cross-device not exercised"
fi

step "build the binaries"
( cd "$ROOT/src" && GOFLAGS=-mod=mod go build ./... )
for d in "$ROOT"/src/cmd/*/; do
    b="$(basename "$d")"
    ( cd "$ROOT/src" && GOFLAGS=-mod=mod go build -o "$BIN/$b" "./cmd/$b" )
done
[ -x "$BIN/packbox-export" ] && [ -x "$BIN/packbox-run" ] || fail "binaries missing"
pass "binaries built into $BIN"

step "synthetic app + a cell (layer C)"
mkdir -p "$MODS/org.test.cell/1/lib"
head -c 4096 /dev/urandom > "$MODS/org.test.cell/1/lib/libcell.so"
printf '{"type":"cell","name":"org.test.cell","version":"1"}' \
    > "$MODS/org.test.cell/1/manifest.json"
aw="$WORK/appwork"; mkdir -p "$aw/bin"
cat > "$aw/bin/app" <<'SH'
#!/bin/sh
if [ -f /app/lib/libcell.so ]; then echo LIBS_OK; else echo LIBS_MISSING; fi
SH
chmod +x "$aw/bin/app"
"$BIN/packbox-pack" --name demo --version 1.0 --entrypoint /app/bin/app \
    --mods org.test.cell@1 "$aw" >/dev/null
pass "packed"

"$BIN/packbox-install" "$aw/manifest.json" >/dev/null
pass "installed"

step "install keeps cells as a runtime layer (not materialized)"
[ ! -e "$APPS/demo/tree/lib" ] || fail "tree/lib should not exist after install"
pass "tree has no lib/"

step "export AUTO then import + run"
"$BIN/packbox-export" app demo > "$WORK/export.log"
grep -q "Algorithm:" "$WORK/export.log" || fail "export did not report an algorithm"
pbox="$EXPORTS/demo.pbox"
[ -s "$pbox" ] || fail "empty .pbox"
rm -rf "$APPS/demo"
"$BIN/packbox-import" app "$pbox" >/dev/null
[ -f "$APPS/demo/tree/lib/libcell.so" ] \
    || fail "imported tree lacks the cell library (staging cross-device?)"
out="$("$BIN/packbox-run" demo 2>&1 || true)"
echo "$out" | grep -q LIBS_OK || fail "run (auto) did not see the lib: $out"
pass "auto: export → import → run OK"

step "export --compress store (plain tar) then import + run"
"$BIN/packbox-export" --compress store app demo > "$WORK/store.log"
grep -q "store" "$WORK/store.log" || fail "store mode not reported"
rm -rf "$APPS/demo"
"$BIN/packbox-import" app "$pbox" >/dev/null
[ -f "$APPS/demo/tree/lib/libcell.so" ] || fail "plain-tar import lacks the cell library"
out="$("$BIN/packbox-run" demo 2>&1 || true)"
echo "$out" | grep -q LIBS_OK || fail "run (store) did not see the lib: $out"
pass "store: export → import (plain tar) → run OK"

step "signature trust chain (keygen → export --sign → verify → import)"
"$BIN/packbox-sign" keygen >/dev/null
"$BIN/packbox-export" --sign app demo > "$WORK/sign.log"
[ -f "$pbox.sig" ] || fail "--sign did not write a .sig"
"$BIN/packbox-sign" verify "$pbox" | grep -q "signed by" \
    || fail "verify rejected a valid signature"

# Tampering must be detected by verify and refused by import.
cp "$pbox" "$WORK/evil.pbox"; cp "$pbox.sig" "$WORK/evil.pbox.sig"
printf X | dd of="$WORK/evil.pbox" bs=1 seek=64 conv=notrunc 2>/dev/null
if "$BIN/packbox-sign" verify "$WORK/evil.pbox" >/dev/null 2>&1; then
    fail "verify accepted a tampered package"
fi
if "$BIN/packbox-import" app "$WORK/evil.pbox" >/dev/null 2>&1; then
    fail "import accepted a tampered package"
fi

# A valid signed package imports and runs.
rm -rf "$APPS/demo"
"$BIN/packbox-import" app "$pbox" >/dev/null 2>&1 \
    || fail "import of a valid signed package failed"
[ -f "$APPS/demo/tree/lib/libcell.so" ] || fail "signed import missing the cell"
out="$("$BIN/packbox-run" demo 2>&1 || true)"
echo "$out" | grep -q LIBS_OK || fail "run (signed) did not see the lib: $out"
pass "signature chain OK (verify + tamper refused + import + run)"

step "packager frontend loads"
printf '0\n' | TERM=xterm timeout 60 "$ROOT/packbox-packager.sh" >/dev/null 2>&1 \
    || fail "packager did not exit cleanly"
pass "packager OK"

rm -rf "$WORK"
echo
printf '\033[32m== integration: ALL GREEN ==\033[0m\n'
