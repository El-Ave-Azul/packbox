#!/usr/bin/env bash
# =============================================================================
# lib/go.sh — Instalación de Go en ~/.packbox/go (sin sudo).
# lib/go.sh — Go installation in ~/.packbox/go (no sudo).
#
# Asume / Assumes: ui.sh, paths.sh, common.sh, journal.sh
# Provee / Provides: install_go, _go_arch, _fetch_go_sha,
#                    _local_sha, _verify_go_sha
# =============================================================================

# ─── Configuración ───────────────────────────────────────────────────────────
# ─── Configuration ───────────────────────────────────────────────────────────
GO_VERSION="${GO_VERSION:-1.27.1}"

# ─── Arquitectura ────────────────────────────────────────────────────────────
# ─── Architecture ────────────────────────────────────────────────────────────
# _go_arch — detecta la arquitectura Go correspondiente a uname -m.
# _go_arch — detects the Go architecture corresponding to uname -m.
_go_arch() {
    case "$(uname -m)" in
        x86_64|amd64)       echo "amd64" ;;
        aarch64|arm64)      echo "arm64" ;;
        armv7l|armv6l)      echo "armv6l" ;;
        *)                  echo "amd64" ;;
    esac
}

# ─── Hash local (offline fallback) ───────────────────────────────────────────
# ─── Local hash (offline fallback) ───────────────────────────────────────────
# _local_sha <arch> — devuelve el SHA256 embebido, o vacío si no existe.
# _local_sha <arch> — returns the embedded SHA256, or empty if none.
#
# NOTA: usar case en lugar de declare -A para evitar el bug de bash
# con set -u y arrays asociativos (${arr[$key]:-}).
# NOTE: use case instead of declare -A to avoid the bash bug
# with set -u and associative arrays (${arr[$key]:-}).
_local_sha() {
    case "$1" in
        amd64)
            echo "63d339f0da5ab53635a56f2490a7984dfe12dfcff22ad749f63edaf590168445" ;;
        arm64)
            echo "3450b45a3f9ee8568792736a5c5e70a1f2e9b36c35a8f74958c03e51d7d92bec" ;;
        *)
            echo "" ;;
    esac
}

# ─── SHA256 dinámico (online) ────────────────────────────────────────────────
# ─── Dynamic SHA256 (online) ─────────────────────────────────────────────────
# _fetch_go_sha <version> <arch> — consulta el hash en go.dev.
# _fetch_go_sha <version> <arch> — queries the hash from go.dev.
#
# Usa jq si está disponible (más robusto). Cae a awk como fallback.
# Uses jq if available (more robust). Falls back to awk.
_fetch_go_sha() {
    local ver="$1" arch="$2" json
    json=$(curl -fsSL "https://go.dev/dl/?mode=json" 2>/dev/null) || return 1
    [[ -z "$json" ]] && return 1

    local fname="go${ver}.linux-${arch}.tar.gz"

    if command -v jq &>/dev/null; then
        echo "$json" | jq -r --arg v "go${ver}" --arg f "$fname" '
            .[] | select(.version == $v)
                | .files[] | select(.filename == $f)
                | .sha256
        ' 2>/dev/null | head -1
    else
        echo "$json" | awk -v v="go${ver}" -v f="$fname" '
            $0 ~ "\"version\"" && index($0, "\"" v "\"") { in_ver=1 }
            in_ver && index($0, "\"filename\"") && index($0, "\"" f "\"") { want=1 }
            want && index($0, "\"sha256\"") {
                if (match($0, /[a-f0-9]{64}/)) {
                    print substr($0, RSTART, RLENGTH)
                    exit
                }
            }
        '
    fi
}

# _verify_go_sha <file> <expected> — verifica SHA256 de un archivo.
# _verify_go_sha <file> <expected> — verifies SHA256 of a file.
_verify_go_sha() {
    local file="$1" expected="$2" actual
    actual=$(sha256sum "$file" | awk '{print $1}')
    [[ "$actual" == "$expected" ]]
}

# ─── Instalación ─────────────────────────────────────────────────────────────
# ─── Installation ────────────────────────────────────────────────────────────
# install_go — instala Go 1.27.1 en ~/.packbox/go si no está ya.
# install_go — installs Go 1.27.1 in ~/.packbox/go if not already present.
install_go() {
    # ─── 1. Verificar si ya hay un Go válido ─────────────────────────────────
    # ─── 1. Check if a valid Go already exists ───────────────────────────────
    local go_bin="$PACKBOX_GO_BIN/go"
    if [[ -x "$go_bin" ]]; then
        local v maj min
        v=$("$go_bin" version 2>/dev/null | awk '{print $3}' | sed 's/go//')
        maj=$(echo "$v" | cut -d. -f1)
        min=$(echo "$v" | cut -d. -f2)
        if [[ -n "$maj" && "$maj" -ge 1 && "$min" -ge 22 ]]; then
            ok "Go $v (en ~/.packbox/go / in ~/.packbox/go)"
            export GOROOT="$PACKBOX_GO_DIR"
            export GOPATH="$PACKBOX_GO_PATH"
            export PATH="$PACKBOX_GO_BIN:$GOPATH/bin:$PATH"
            return 0
        fi
    fi

    # ─── 2. Detectar arquitectura ────────────────────────────────────────────
    # ─── 2. Detect architecture ─────────────────────────────────────────────
    local arch tgz url sha
    arch=$(_go_arch)
    tgz="go${GO_VERSION}.linux-${arch}.tar.gz"
    url="https://go.dev/dl/${tgz}"

    info "Instalando Go ${GO_VERSION} en ~/.packbox/go..."
    info "Installing Go ${GO_VERSION} in ~/.packbox/go..."

    # ─── 3. Descargar a un temporal ─────────────────────────────────────────
    # ─── 3. Download to a temporary ─────────────────────────────────────────
    # El tarball va a un tmpfs (rápido). La extracción va al destino final.
    # The tarball goes to a tmpfs (fast). Extraction goes to the final target.
    local tmp
    tmp=$(tmpdir "go")
    reg_cln "$tmp"
    local dl="$tmp/$tgz"

    if ! curl -fSL --progress-bar -o "$dl" "$url"; then
        unreg_cln "$tmp"
        rm -rf "$tmp"
        err "Descarga de Go falló / Go download failed"
    fi

    # ─── 4. Verificar SHA256 ────────────────────────────────────────────────
    # ─── 4. Verify SHA256 ──────────────────────────────────────────────────
    # Intento 1: hash dinámico desde go.dev (requiere red).
    # Intento 2: hash local embebido (offline).
    # Try 1: dynamic hash from go.dev (requires network).
    # Try 2: embedded local hash (offline).
    sha=$(_fetch_go_sha "$GO_VERSION" "$arch" 2>/dev/null || true)
    if [[ -z "$sha" ]]; then
        sha=$(_local_sha "$arch")
        [[ -n "$sha" ]] && det "Usando hash local embebido / Using embedded local hash"
    fi

    if [[ -n "$sha" ]]; then
        if _verify_go_sha "$dl" "$sha"; then
            ok "SHA256 verificado / verified"
        else
            rm -f "$dl"
            unreg_cln "$tmp"
            rm -rf "$tmp"
            err "SHA256 no coincide / SHA256 mismatch"
        fi
    else
        rm -f "$dl"
        unreg_cln "$tmp"
        rm -rf "$tmp"
        err "No SHA256 available (offline and unknown arch)"
    fi

    # ─── 5. Limpiar destino anterior si existe ──────────────────────────────
    # ─── 5. Clean previous target if it exists ──────────────────────────────
    if [[ -d "$PACKBOX_GO_DIR" ]]; then
        rm -rf "$PACKBOX_GO_DIR"
    fi
    mkdir -p "$PACKBOX_GO_DIR"

    # ─── 6. Extraer directamente en el destino ──────────────────────────────
    # ─── 6. Extract directly to destination ─────────────────────────────────
    # --strip-components=1 elimina el directorio "go/" de dentro del tarball.
    # --strip-components=1 removes the "go/" directory inside the tarball.
    # Al extraer directo al destino final, evitamos mv cross-device.
    # By extracting directly to the final target, we avoid cross-device mv.
    if ! tar -C "$PACKBOX_GO_DIR" --strip-components=1 -xzf "$dl"; then
        rm -rf "$PACKBOX_GO_DIR"
        unreg_cln "$tmp"
        rm -rf "$tmp"
        err "Extracción de Go falló / Go extraction failed"
    fi

    # Verificar que el binario quedó donde esperamos.
    # Verify the binary ended up where we expect.
    if [[ ! -x "$PACKBOX_GO_BIN/go" ]]; then
        rm -rf "$PACKBOX_GO_DIR"
        unreg_cln "$tmp"
        rm -rf "$tmp"
        err "Binario de Go no encontrado tras extraer / Go binary missing after extraction"
    fi

    # ─── 7. Registrar en el diario ──────────────────────────────────────────
    # ─── 7. Register in journal ─────────────────────────────────────────────
    journal_register_dir "$PACKBOX_GO_DIR"
    journal_register_dir "$PACKBOX_GO_BIN"
    journal_write "go_runtime" "version" "$GO_VERSION"
    journal_write "go_runtime" "path" "$PACKBOX_GO_DIR"
    journal_write "go_runtime" "sha256" "${sha:-unknown}"

    # ─── 8. Limpiar temporales ──────────────────────────────────────────────
    # ─── 8. Clean temporaries ───────────────────────────────────────────────
    rm -rf "$tmp"
    unreg_cln "$tmp"

    # ─── 9. Configurar entorno en la sesión actual ──────────────────────────
    # ─── 9. Configure environment in current session ────────────────────────
    export GOROOT="$PACKBOX_GO_DIR"
    export GOPATH="$PACKBOX_GO_PATH"
    export PATH="$PACKBOX_GO_BIN:$GOPATH/bin:$PATH"

    local installed_ver
    installed_ver=$("$go_bin" version 2>/dev/null | awk '{print $3}' | sed 's/go//')
    ok "Go $installed_ver instalado en ~/.packbox/go"
    ok "Go $installed_ver installed in ~/.packbox/go"
}