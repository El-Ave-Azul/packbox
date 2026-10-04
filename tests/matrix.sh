#!/usr/bin/env bash
# =============================================================================
# tests/matrix.sh — Matriz de tests específica para nuevas funcionalidades.
# Valida el esquema v1.7 y la política de red del sandbox.
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$ROOT/.matrix_test"
HOME_DIR="$WORK/home"
BIN="$HOME_DIR/.packbox/bin"
APPS="$HOME_DIR/.local/share/packbox/apps"
export HOME="$HOME_DIR"
export GOPATH="/tmp/packbox-matrix/gopath"
export GOCACHE="/tmp/packbox-matrix/gocache"

pass() { printf '  \033[32mok\033[0m   %s\n' "$1"; }
fail() { printf '  \033[31mFAIL\033[0m %s\n' "$1" >&2; exit 1; }
step() { printf '\n== %s ==\n' "$1"; }

# 1. Setup environment
rm -rf "$WORK"
mkdir -p "$BIN" "$APPS" "$HOME_DIR/.config/packbox/lang"
echo en > "$HOME_DIR/.config/packbox/lang/current"

# 2. Build binaries
step "Building binaries"
( cd "$ROOT/src" && GOFLAGS=-mod=mod go build ./... )
for d in "$ROOT"/src/cmd/*/; do
    b="$(basename "$d")"
    ( cd "$ROOT/src" && GOFLAGS=-mod=mod go build -o "$BIN/$b" "./cmd/$b" )
done
pass "Binaries ready"

# 3. Test Manifest v1.7 Loading via real Pack
step "Test: Manifest v1.7 Loading"
app_work="$WORK/app_v17"
mkdir -p "$app_work/bin"
echo "#!/bin/sh\necho 'Hello'" > "$app_work/bin/app"
chmod +x "$app_work/bin/app"

# Use packbox-pack with = syntax to avoid pre() parser issues
"$BIN/packbox-pack" --name=matrix.test.v17 --version=1.0.0 --description="Test v1.7" \
    --entrypoint="/app/bin/app" --network=full "$app_work" >/dev/null

if "$BIN/packbox-install" "$app_work/manifest.json" >/dev/null 2>&1; then
    pass "Manifest v1.7 created by 'pack' and installed successfully"
else
    fail "Failed to install manifest v1.7"
fi

# 4. Test Network Isolation: "none"
step "Test: Network Isolation (NONE)"
net_none_work="$WORK/net_none"
mkdir -p "$net_none_work/bin"
cat > "$net_none_work/bin/net_test" <<'SH'
#!/bin/sh
if curl -s --connect-timeout 2 google.com > /dev/null; then
    echo "NETWORK_OK"
else
    echo "NETWORK_BLOCKED"
fi
SH
chmod +x "$net_none_work/bin/net_test"

"$BIN/packbox-pack" --name=matrix.net.none --version=1.0 --entrypoint="/app/bin/net_test" \
    --network=none "$net_none_work" >/dev/null

"$BIN/packbox-install" "$net_none_work/manifest.json" >/dev/null 2>&1
out=$("$BIN/packbox-run" matrix.net.none 2>&1 || true)
if echo "$out" | grep -q "NETWORK_BLOCKED"; then
    pass "Network is correctly BLOCKED when set to 'none'"
else
    fail "Network was NOT blocked for 'none' policy: $out"
fi

# 5. Test Network Isolation: "full"
step "Test: Network Isolation (FULL)"
net_full_work="$WORK/net_full"
mkdir -p "$net_full_work/bin"
cp "$net_none_work/bin/net_test" "$net_full_work/bin/net_test"

"$BIN/packbox-pack" --name=matrix.net.full --version=1.0 --entrypoint="/app/bin/net_test" \
    --network=full "$net_full_work" >/dev/null

"$BIN/packbox-install" "$net_full_work/manifest.json" >/dev/null 2>&1
out=$("$BIN/packbox-run" matrix.net.full 2>&1 || true)
if echo "$out" | grep -q "NETWORK_OK"; then
    pass "Network is correctly ENABLED when set to 'full'"
else
    fail "Network was NOT enabled for 'full' policy: $out"
fi

# 6. Test Network Isolation: "limited" (proxy filters private, allows public).
step "Test: Network Isolation (LIMITED)"
net_lim_work="$WORK/net_limited"
mkdir -p "$net_lim_work/bin"
cat > "$net_lim_work/bin/net_lim" <<'SH'
#!/bin/sh
# The limited proxy must answer 403 (blocked) for a private host, and let a
# public host through (any real HTTP code, not 000 = no connection).
c=$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 5 https://example.com)
[ "$c" != "000" ] && [ -n "$c" ] && echo "PUBLIC_OK"
p=$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 5 http://192.168.1.1)
[ "$p" = "403" ] && echo "PRIVATE_BLOCKED_BY_PROXY"
SH
chmod +x "$net_lim_work/bin/net_lim"

"$BIN/packbox-pack" --name=matrix.net.limited --version=1.0 --entrypoint="/app/bin/net_lim" \
    --network=limited "$net_lim_work" >/dev/null

"$BIN/packbox-install" "$net_lim_work/manifest.json" >/dev/null 2>&1
out=$("$BIN/packbox-run" matrix.net.limited 2>&1 || true)
if echo "$out" | grep -q "PUBLIC_OK" && echo "$out" | grep -q "PRIVATE_BLOCKED_BY_PROXY"; then
    pass "Network limited: public allowed, private blocked by the proxy"
else
    fail "Network limited behaved wrong: $out"
fi

rm -rf "$WORK"
printf '\n\033[32m== MATRIX TESTS: ALL GREEN ==\033[0m\n'
