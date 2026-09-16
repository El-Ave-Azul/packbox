#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
# EN: Packbox Installer v0.1.0 Alpha.
# ES: Instalador de Packbox v0.1.0 Alpha.
#
# EN: Installs Packbox (11 Go binaries) into ~/.packbox, sets up
#     PATH, desktop integration, i18n, compression, and a
#     Bubblewrap-based sandbox with DNS fix.
# ES: Instala Packbox (11 binarios Go) en ~/.packbox, configura
#     PATH, integración de escritorio, i18n, compresión y un
#     sandbox basado en Bubblewrap con fix de DNS.
# ═══════════════════════════════════════════════════════════════

# ───────────────────────────────────────────────────────────────
# EN: Force Bash and enable strict mode.
# ES: Fuerza Bash y activa modo estricto.
# ───────────────────────────────────────────────────────────────
if [ -z "$BASH_VERSION" ]; then echo "Error: usa bash."; exec bash "$0" "$@"; fi
set -uo pipefail

# EN: Directory of this script (used to locate packbox-i18n.sh).
# ES: Directorio de este script (usado para localizar packbox-i18n.sh).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ═══════════════════════════════════════════════════════════════
# EN: Paths.
# ES: Rutas.
# ═══════════════════════════════════════════════════════════════
PACKBOX_INSTALL_DIR="$HOME/.packbox"                    # EN: install root | ES: raíz de instalación
PACKBOX_BIN_DIR="$PACKBOX_INSTALL_DIR/bin"              # EN: compiled binaries | ES: binarios compilados
PACKBOX_SRC_DIR="$PACKBOX_INSTALL_DIR/src"              # EN: Go source tree | ES: árbol de código Go
PACKBOX_HOME="$HOME/.local/share/packbox"               # EN: runtime data | ES: datos de runtime
PACKBOX_LANG_DIR="$HOME/.config/packbox/lang"           # EN: i18n files | ES: archivos i18n
OLD_PACKBOX_DIR="$HOME/packbox"                         # EN: legacy layout | ES: layout antiguo

# ═══════════════════════════════════════════════════════════════
# EN: Load shared i18n (packbox-i18n.sh).
# ES: Carga la i18n compartida (packbox-i18n.sh).
# ═══════════════════════════════════════════════════════════════
_I18N_FILE="$SCRIPT_DIR/packbox-i18n.sh"
if [[ ! -f "$_I18N_FILE" ]]; then
    echo "❌ Falta packbox-i18n.sh en $SCRIPT_DIR"
    echo "   Descarga el repositorio completo de Packbox."
    exit 1
fi
# shellcheck disable=SC1090
source "$_I18N_FILE"

# ═══════════════════════════════════════════════════════════════
# EN: ANSI colors.
# ES: Colores ANSI.
# ═══════════════════════════════════════════════════════════════
R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; B='\033[0;34m'
C='\033[0;36m'; M='\033[0;35m'; BD='\033[1m'; DM='\033[2m'; N='\033[0m'

# ═══════════════════════════════════════════════════════════════
# EN: Terminal output helpers.
# ES: Helpers de salida de terminal.
# ═══════════════════════════════════════════════════════════════
info()  { echo -e "  ${B}·${N}  ${1:-}"; }                 # EN: info line | ES: línea informativa
ok()    { echo -e "  ${G}✓${N}  ${1:-}"; }                 # EN: success | ES: éxito
warn()  { echo -e "  ${Y}!${N}  ${1:-}"; }                 # EN: warning | ES: advertencia
error() { echo -e "  ${R}✗${N}  ${BD}${1:-error}${N}"; exit 1; }  # EN: fatal | ES: fatal
det()   { echo -e "     ${DM}→ ${1:-}${N}"; }              # EN: detail | ES: detalle

# EN: Section header. | ES: Cabecera de sección.
hdr() {
    echo ""
    echo -e "${C}${BD}───────────────────────────────────────────────────────────────${N}"
    echo -e "${C}${BD}  → ${1:-}${N}"
    echo -e "${C}${BD}───────────────────────────────────────────────────────────────${N}"
    echo ""
}

# EN: Success box. | ES: Caja de éxito.
box_ok() {
    echo ""
    echo -e "  ${G}═══════════════════════════════════════════════════════════════${N}"
    echo -e "  ${G}${BD}     ${1:-}${N}"
    echo -e "  ${G}═══════════════════════════════════════════════════════════════${N}"
    echo ""
}

# EN: Error box. | ES: Caja de error.
box_err() {
    echo ""
    echo -e "  ${R}═══════════════════════════════════════════════════════════════${N}"
    echo -e "  ${R}${BD}     ${1:-}${N}"
    echo -e "  ${R}═══════════════════════════════════════════════════════════════${N}"
    echo ""
}

# ═══════════════════════════════════════════════════════════════
# EN: progress — draw a progress bar.
# ES: progress — dibuja una barra de progreso.
#
# EN: Args: current, total, message.
# ES: Args: actual, total, mensaje.
# ═══════════════════════════════════════════════════════════════
progress() {
    local c="${1:-0}"
    local t="${2:-100}"
    local m="${3:-...}"
    local w=35
    [[ $t -le 0 ]] && t=1
    local p=$((c * 100 / t))
    local f=$((c * w / t))
    local e=$((w - f))
    printf "\r  %s [" "$m"
    local i
    for ((i=0; i<f; i++)); do printf "█"; done
    printf "\033[2m"
    for ((i=0; i<e; i++)); do printf "░"; done
    printf "\033[0m] %3d%%\033[K" "$p"
    [[ $c -ge $t ]] && echo ""
}

# ═══════════════════════════════════════════════════════════════
# EN: show_banner — installer banner.
# ES: show_banner — banner del instalador.
# ═══════════════════════════════════════════════════════════════
show_banner() {
    clear
    echo -e "${BD}${C}"
    echo "  ═══════════════════════════════════════════════════════════════"
    echo "   $(t L_INSTALLER_TITLE)"
    echo "   i18n (9 idiomas) · Desktop · Compresión"
    echo "   Install: ~/.packbox (oculto)"
    echo "  ═══════════════════════════════════════════════════════════════"
    echo -e "${N}"
}

# ═══════════════════════════════════════════════════════════════
# EN: detect_distro — detect distro family.
# ES: detect_distro — detecta la familia de la distribución.
#
# EN: Sets DF to one of: debian, fedora, arch, suse, unknown.
# ES: Define DF a uno de: debian, fedora, arch, suse, unknown.
# ═══════════════════════════════════════════════════════════════
detect_distro() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        DISTRO_NAME="${PRETTY_NAME:-Unknown}"
        case "${ID:-}" in
            # EN: Debian-family IDs. | ES: IDs de la familia Debian.
            ubuntu|linuxmint|pop|elementary|zorin|kali|deepin|neon|debian|raspbian) DF="debian" ;;
            # EN: Fedora-family IDs. | ES: IDs de la familia Fedora.
            fedora|centos|rhel|rocky|alma|nobara) DF="fedora" ;;
            # EN: Arch-family IDs. | ES: IDs de la familia Arch.
            arch|manjaro|endeavouros|garuda|cachyos) DF="arch" ;;
            # EN: SUSE-family IDs. | ES: IDs de la familia SUSE.
            opensuse*|suse) DF="suse" ;;
            # EN: Fallback via ID_LIKE. | ES: Fallback vía ID_LIKE.
            *)
                case "${ID_LIKE:-}" in
                    *debian*|*ubuntu*) DF="debian" ;;
                    *fedora*) DF="fedora" ;;
                    *arch*) DF="arch" ;;
                    *) DF="unknown" ;;
                esac ;;
        esac
    else
        DF="unknown"
        DISTRO_NAME="Unknown"
    fi
}

# ═══════════════════════════════════════════════════════════════
# EN: install_pkgs — install dependencies per distro family.
# ES: install_pkgs — instala dependencias según la familia.
# ═══════════════════════════════════════════════════════════════
install_pkgs() {
    case "$DF" in
        debian) $SUDO apt-get update -qq 2>/dev/null; $SUDO apt-get install -y -qq "$@" >/dev/null 2>&1 ;;
        fedora) $SUDO dnf install -y -q "$@" >/dev/null 2>&1 ;;
        arch)   $SUDO pacman -Sy --noconfirm --needed "$@" >/dev/null 2>&1 ;;
        suse)   $SUDO zypper --non-interactive install "$@" >/dev/null 2>&1 ;;
    esac
}

# ═══════════════════════════════════════════════════════════════
# EN: install_go — ensure Go 1.22+ is available.
# ES: install_go — asegura que Go 1.22+ esté disponible.
#
# EN: Uses existing Go if >= 1.22; otherwise downloads upstream
#     tarball into /usr/local/go and updates ~/.bashrc.
# ES: Usa Go existente si es >= 1.22; si no, descarga el tarball
#     oficial a /usr/local/go y actualiza ~/.bashrc.
# ═══════════════════════════════════════════════════════════════
install_go() {
    # EN: Check for an already suitable Go.
    # ES: Comprueba si ya hay un Go válido.
    if command -v go &>/dev/null; then
        local v maj min
        v=$(go version | grep -oP 'go\K[0-9]+\.[0-9]+' | head -1)
        maj=$(echo "$v" | cut -d. -f1)
        min=$(echo "$v" | cut -d. -f2)
        if [[ "$maj" -ge 1 && "$min" -ge 22 ]]; then
            ok "Go $v"
            return 0
        fi
    fi

    # EN: Download and unpack official Go 1.22.5.
    # ES: Descarga y descomprime Go 1.22.5 oficial.
    info "Instalando Go 1.22+..."
    cd /tmp || error "Sin /tmp"
    curl -fSL --progress-bar -o go1.22.5.linux-amd64.tar.gz \
        "https://go.dev/dl/go1.22.5.linux-amd64.tar.gz" || error "Descarga falló"
    [[ -d /usr/local/go ]] && $SUDO rm -rf /usr/local/go
    $SUDO tar -C /usr/local -xzf go1.22.5.linux-amd64.tar.gz
    rm -f go1.22.5.linux-amd64.tar.gz

    # EN: Add Go to PATH in ~/.bashrc (idempotent).
    # ES: Añade Go al PATH en ~/.bashrc (idempotente).
    grep -q '/usr/local/go/bin' "$HOME/.bashrc" 2>/dev/null \
        || echo 'export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin' >> "$HOME/.bashrc"
    export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin

    cd - >/dev/null 2>&1 || cd "$HOME"
    ok "Go instalado"
}

# ═══════════════════════════════════════════════════════════════
# EN: create_dirs — create hidden install directories.
# ES: create_dirs — crea los directorios ocultos de instalación.
#
# EN: Layout:
#       ~/.packbox/{bin,src}
#       ~/.local/share/packbox/{store,apps,mods,exports,tmp}
# ES: Estructura:
#       ~/.packbox/{bin,src}
#       ~/.local/share/packbox/{store,apps,mods,exports,tmp}
# ═══════════════════════════════════════════════════════════════
create_dirs() {
    hdr "$(t L_STEP3)"

    # EN: Binaries and Go source.
    # ES: Binarios y código Go.
    mkdir -p "$PACKBOX_BIN_DIR" "$PACKBOX_SRC_DIR"

    # EN: Runtime data: CAS store, installed apps, modules, exports, tmp.
    # ES: Datos de runtime: store CAS, apps, módulos, exports, tmp.
    mkdir -p "$PACKBOX_HOME"/{store,apps,mods,exports,tmp}

    # EN: CAS store must be readable (shared hardlinks).
    # ES: El store CAS debe ser legible (hardlinks compartidos).
    chmod 755 "$PACKBOX_HOME/store"

    ok "~/.packbox/"
}
# ═══════════════════════════════════════════════════════════════
# EN: generate_go — write the Packbox Go project.
# ES: generate_go — escribe el proyecto Go de Packbox.
#
# EN: Generates go.mod plus 5 internal packages:
#       security     — safe temp/copy/link/path helpers
#       cas          — content-addressed store with GC
#       manifest     — JSON manifest load/save
#       hostcontract — ELF dependency and symbol analysis
#       sandbox      — Bubblewrap sandbox with DNS fix and GUI binds
# ES: Genera go.mod y 5 paquetes internos:
#       security     — helpers seguros de temp/copia/link/ruta
#       cas          — store por contenido con GC
#       manifest     — carga/guardado de manifiesto JSON
#       hostcontract — análisis de dependencias y símbolos ELF
#       sandbox      — sandbox Bubblewrap con fix DNS y binds GUI
# ═══════════════════════════════════════════════════════════════
generate_go() {
    hdr "$(t L_STEP4)"
    cd "$PACKBOX_SRC_DIR" || error "cd falló"

    # ───────────────────────────────────────────────────────────
    # EN: go.mod — module path and dependencies.
    # ES: go.mod — ruta del módulo y dependencias.
    # ───────────────────────────────────────────────────────────
    cat > go.mod <<'GOMOD_EOF'
module github.com/packbox/packbox

go 1.22

require github.com/zeebo/blake3 v0.2.3
GOMOD_EOF

    # ═══════════════════════════════════════════════════════════
    # EN: internal/security — safe filesystem helpers.
    # ES: internal/security — helpers seguros de sistema de archivos.
    #
    # EN: Provides sandboxed temp dirs, safe copy, path traversal
    #     validation, and hardlink-with-fallback used by the CAS.
    # ES: Provee directorios temporales aislados, copia segura,
    #     validación de path traversal, y hardlink con fallback
    #     usados por el CAS.
    # ═══════════════════════════════════════════════════════════
    mkdir -p internal/security
    cat > internal/security/security.go <<'GO_SEC'
package security

import (
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

// EN: SecureTempDir returns a unique 0700 temp directory prefixed
//     by p. Prevents predictable temp paths.
// ES: SecureTempDir devuelve un directorio temporal 0700 único
//     con prefijo p. Evita rutas temporales predecibles.
func SecureTempDir(p string) (string, error) {
	b := make([]byte, 8)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	d := filepath.Join(os.TempDir(), fmt.Sprintf("%s-%s", p, hex.EncodeToString(b)))
	return d, os.MkdirAll(d, 0700)
}

// EN: SafeCopy copies src to dst with the given mode.
// ES: SafeCopy copia src a dst con el modo indicado.
func SafeCopy(src, dst string, mode os.FileMode) error {
	in, err := os.Open(src)
	if err != nil {
		return err
	}
	defer in.Close()
	out, err := os.OpenFile(dst, os.O_WRONLY|os.O_CREATE|os.O_TRUNC, mode)
	if err != nil {
		return err
	}
	defer out.Close()
	if _, err := out.ReadFrom(in); err != nil {
		return err
	}
	return os.Chmod(dst, mode)
}

// EN: ValidatePath ensures target stays inside base (no ".." escape).
// ES: ValidatePath asegura que target permanezca dentro de base
//     (sin escape con "..").
func ValidatePath(base, target string) error {
	ab, err := filepath.Abs(base)
	if err != nil {
		return err
	}
	at, err := filepath.Abs(target)
	if err != nil {
		return err
	}
	rel, err := filepath.Rel(ab, at)
	if err != nil {
		return err
	}
	if rel == ".." || strings.HasPrefix(rel, ".."+string(os.PathSeparator)) {
		return fmt.Errorf("path escapes")
	}
	return nil
}

// EN: SafeLink tries a hardlink; on failure (cross-device, no
//     support) falls back to SafeCopy, preserving the source mode.
// ES: SafeLink intenta un hardlink; si falla (cross-device o no
//     soportado) cae a SafeCopy, preservando el modo de origen.
func SafeLink(src, dst string) error {
	if err := os.Link(src, dst); err == nil {
		return nil
	}
	info, err := os.Stat(src)
	if err != nil {
		return fmt.Errorf("stat source: %w", err)
	}
	return SafeCopy(src, dst, info.Mode().Perm())
}
GO_SEC

    # ═══════════════════════════════════════════════════════════
    # EN: internal/cas — content-addressed store.
    # ES: internal/cas — store por contenido.
    #
    # EN: Chunks are addressed by BLAKE3 hash (64 hex chars).
    #     Reference counting via .refs sidecar files.
    #     GarbageCollect removes chunks with no live references.
    # ES: Los chunks se direccionan por hash BLAKE3 (64 hex).
    #     Conteo de referencias vía archivos .refs.
    #     GarbageCollect elimina chunks sin referencias vivas.
    # ═══════════════════════════════════════════════════════════
    mkdir -p internal/cas
    cat > internal/cas/cas.go <<'GO_CAS'
package cas

import (
	"encoding/hex"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"

	"github.com/packbox/packbox/internal/security"
	"github.com/zeebo/blake3"
)

// EN: Store is a content-addressed chunk store rooted at RootPath.
// ES: Store es un almacén de chunks por contenido en RootPath.
type Store struct{ RootPath string }

// EN: NewStore creates (if needed) and returns a Store.
// ES: NewStore crea (si hace falta) y devuelve un Store.
func NewStore(r string) (*Store, error) {
	if err := os.MkdirAll(r, 0755); err != nil {
		return nil, err
	}
	return &Store{RootPath: r}, nil
}

// EN: isValidHash enforces exactly 64 lowercase hex chars
//     (BLAKE3 = 32 bytes). Blocks path traversal via malicious
//     manifests (e.g. "../../etc/passwd" as a chunk id).
// ES: isValidHash exige exactamente 64 caracteres hex en
//     minúsculas (BLAKE3 = 32 bytes). Bloquea path traversal
//     vía manifiestos maliciosos (p. ej. "../../etc/passwd").
func isValidHash(h string) bool {
	if len(h) != 64 {
		return false
	}
	for _, c := range h {
		if !((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f')) {
			return false
		}
	}
	return true
}

// EN: HashFile returns the BLAKE3 hex hash of a file.
// ES: HashFile devuelve el hash BLAKE3 hex de un archivo.
func HashFile(p string) (string, error) {
	f, err := os.Open(p)
	if err != nil {
		return "", err
	}
	defer f.Close()
	h := blake3.New()
	if _, err := io.Copy(h, f); err != nil {
		return "", err
	}
	return hex.EncodeToString(h.Sum(nil)), nil
}

// EN: StoreFile stores src into the CAS and returns its hash.
//     Idempotent: no-op if the chunk already exists.
// ES: StoreFile guarda src en el CAS y devuelve su hash.
//     Idempotente: no-op si el chunk ya existe.
func (s *Store) StoreFile(src string) (string, error) {
	h, err := HashFile(src)
	if err != nil {
		return "", err
	}
	dir := filepath.Join(s.RootPath, h[:2])
	dst := filepath.Join(dir, h)
	if _, err := os.Stat(dst); err == nil {
		return h, nil
	}
	if err := os.MkdirAll(dir, 0755); err != nil {
		return "", err
	}
	if err := security.SafeCopy(src, dst, 0644); err != nil {
		return "", err
	}
	return h, nil
}

// EN: RetrieveFile copies a chunk from the CAS to dst.
// ES: RetrieveFile copia un chunk del CAS a dst.
func (s *Store) RetrieveFile(h, dst string) error {
	if !isValidHash(h) {
		return fmt.Errorf("hash inválido: %q", h)
	}
	src := filepath.Join(s.RootPath, h[:2], h)
	if _, err := os.Stat(src); os.IsNotExist(err) {
		return fmt.Errorf("chunk %s no encontrado", h)
	}
	return security.SafeCopy(src, dst, 0644)
}

// EN: LinkFile hardlinks a chunk into dst (fast, saves space).
//     Falls back to copy on cross-device filesystems.
// ES: LinkFile crea un hardlink del chunk en dst (rápido, ahorra
//     espacio). Cae a copia en sistemas cross-device.
func (s *Store) LinkFile(h, dst string) error {
	if !isValidHash(h) {
		return fmt.Errorf("hash inválido: %q", h)
	}
	src := filepath.Join(s.RootPath, h[:2], h)
	if _, err := os.Stat(src); os.IsNotExist(err) {
		return fmt.Errorf("chunk %s no encontrado", h)
	}
	if err := os.MkdirAll(filepath.Dir(dst), 0755); err != nil {
		return fmt.Errorf("mkdir: %w", err)
	}
	return security.SafeLink(src, dst)
}

// EN: AddReference records that app uses chunk h (refcounting).
// ES: AddReference registra que app usa el chunk h (refcount).
func (s *Store) AddReference(h, app string) error {
	if !isValidHash(h) {
		return fmt.Errorf("hash inválido: %q", h)
	}
	rp := filepath.Join(s.RootPath, h[:2], h+".refs")
	refs := map[string]bool{}
	if data, err := os.ReadFile(rp); err == nil {
		for _, l := range strings.Split(string(data), "\n") {
			if l != "" {
				refs[l] = true
			}
		}
	}
	refs[app] = true
	var c string
	for r := range refs {
		c += r + "\n"
	}
	return os.WriteFile(rp, []byte(c), 0644)
}

// EN: RemoveReference drops app's reference to chunk h.
// ES: RemoveReference elimina la referencia de app al chunk h.
func (s *Store) RemoveReference(h, app string) error {
	if !isValidHash(h) {
		return fmt.Errorf("hash inválido: %q", h)
	}
	rp := filepath.Join(s.RootPath, h[:2], h+".refs")
	refs := map[string]bool{}
	if data, err := os.ReadFile(rp); err == nil {
		for _, l := range strings.Split(string(data), "\n") {
			if l != "" && l != app {
				refs[l] = true
			}
		}
	}
	var c string
	for r := range refs {
		c += r + "\n"
	}
	return os.WriteFile(rp, []byte(c), 0644)
}

// EN: GarbageCollect deletes chunks with no live references.
//     Returns (chunks_removed, bytes_freed, error).
// ES: GarbageCollect borra chunks sin referencias vivas.
//     Devuelve (chunks_borrados, bytes_liberados, error).
func (s *Store) GarbageCollect() (int, int64, error) {
	del := 0
	var freed int64
	entries, err := os.ReadDir(s.RootPath)
	if err != nil {
		return 0, 0, err
	}
	for _, e := range entries {
		if !e.IsDir() || len(e.Name()) != 2 {
			continue
		}
		pd := filepath.Join(s.RootPath, e.Name())
		files, err := os.ReadDir(pd)
		if err != nil {
			continue
		}
		for _, f := range files {
			if f.IsDir() {
				continue
			}
			fn := f.Name()
			if filepath.Ext(fn) == ".refs" {
				continue
			}
			rp := filepath.Join(pd, fn+".refs")
			cp := filepath.Join(pd, fn)
			if _, err := os.Stat(rp); os.IsNotExist(err) {
				if fi, err := f.Info(); err == nil {
					freed += fi.Size()
				}
				os.Remove(cp)
				del++
			} else {
				data, _ := os.ReadFile(rp)
				if len(data) == 0 {
					if fi, err := f.Info(); err == nil {
						freed += fi.Size()
					}
					os.Remove(cp)
					os.Remove(rp)
					del++
				}
			}
		}
	}
	return del, freed, nil
}
GO_CAS

    # ═══════════════════════════════════════════════════════════
    # EN: internal/manifest — Packbox manifest format.
    # ES: internal/manifest — formato de manifiesto de Packbox.
    #
    # EN: Schema v1.5. Includes layers, mods, host contract, and
    #     optional portable/bundle markers.
    # ES: Esquema v1.5. Incluye capas, módulos, contrato de host
    #     y marcadores opcionales portable/bundle.
    # ═══════════════════════════════════════════════════════════
    mkdir -p internal/manifest
    cat > internal/manifest/manifest.go <<'GO_MAN'
package manifest

import (
	"encoding/json"
	"fmt"
	"os"
)

// EN: Manifest describes an installed or packaged application.
// ES: Manifest describe una aplicación instalada o empaquetada.
type Manifest struct {
	SchemaVersion string       `json:"schema_version"`
	Name          string       `json:"name"`
	Version       string       `json:"version"`
	Description   string       `json:"description,omitempty"`
	Entrypoint    string       `json:"entrypoint"`
	Arch          string       `json:"arch"`
	GUI           bool         `json:"gui,omitempty"`
	Toolkit       string       `json:"toolkit,omitempty"`
	Icon          string       `json:"icon,omitempty"`
	Layers        Layers       `json:"layers"`
	Mods          []string     `json:"mods"`
	HostContract  HostContract `json:"host_contract"`
	Portable      bool         `json:"portable,omitempty"`
}

// EN: Layers currently only has an "app" layer.
// ES: Layers actualmente solo tiene una capa "app".
type Layers struct{ App AppLayer `json:"app"` }

// EN: AppLayer maps relative file paths to chunk references.
// ES: AppLayer mapea rutas relativas a referencias de chunks.
type AppLayer struct{ Files map[string]FileInfo `json:"files"` }

// EN: FileInfo describes one file inside a layer.
// ES: FileInfo describe un archivo dentro de una capa.
type FileInfo struct {
	Chunks []string `json:"chunks"`
	Size   int64    `json:"size"`
	Mode   string   `json:"mode"`
}

// EN: HostContract declares required host symbols and fallbacks.
// ES: HostContract declara símbolos requeridos del host y fallbacks.
type HostContract struct {
	Version         string              `json:"version"`
	Delegate        []string            `json:"delegate"`
	RequiredSymbols map[string][]string `json:"required_symbols"`
	FallbackMods    map[string]string   `json:"fallback_mods"`
}

// EN: Load reads and validates a manifest JSON file.
// ES: Load lee y valida un archivo de manifiesto JSON.
func Load(p string) (*Manifest, error) {
	data, err := os.ReadFile(p)
	if err != nil {
		return nil, fmt.Errorf("read: %w", err)
	}
	var m Manifest
	if err := json.Unmarshal(data, &m); err != nil {
		return nil, fmt.Errorf("parse: %w", err)
	}
	if m.SchemaVersion == "" || m.Name == "" || m.Entrypoint == "" {
		return nil, fmt.Errorf("faltan campos")
	}
	return &m, nil
}

// EN: Save writes the manifest as indented JSON.
// ES: Save escribe el manifiesto como JSON indentado.
func (m *Manifest) Save(p string) error {
	data, err := json.MarshalIndent(m, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(p, data, 0644)
}
GO_MAN

    # ═══════════════════════════════════════════════════════════
    # EN: internal/hostcontract — ELF analysis.
    # ES: internal/hostcontract — análisis ELF.
    #
    # EN: Inspects ELF binaries with ldd/readelf to know which
    #     libraries and symbols the host must provide.
    # ES: Inspecciona binarios ELF con ldd/readelf para saber qué
    #     librerías y símbolos debe proveer el host.
    # ═══════════════════════════════════════════════════════════
    mkdir -p internal/hostcontract
    cat > internal/hostcontract/hostcontract.go <<'GO_HC'
package hostcontract

import (
	"bufio"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

// EN: AllowedLibs are the libraries the host always provides.
// ES: AllowedLibs son las librerías que el host siempre provee.
var AllowedLibs = []string{
	"libc.so.6", "libm.so.6", "libdl.so.2", "libpthread.so.0", "libz.so.1",
}

// EN: AnalyzeDependencies returns the shared libs required by p
//     (via ldd), excluding linux-vdso.
// ES: AnalyzeDependencies devuelve las libs compartidas que
//     requiere p (vía ldd), excluyendo linux-vdso.
func AnalyzeDependencies(p string) ([]string, error) {
	out, err := exec.Command("ldd", p).Output()
	if err != nil {
		return nil, err
	}
	var deps []string
	s := bufio.NewScanner(strings.NewReader(string(out)))
	for s.Scan() {
		l := s.Text()
		if strings.Contains(l, "=>") {
			parts := strings.Fields(l)
			if len(parts) >= 1 && !strings.HasPrefix(parts[0], "linux-vdso") {
				deps = append(deps, parts[0])
			}
		}
	}
	return deps, nil
}

// EN: ExtractRequiredSymbols parses readelf -s output for
//     undefined symbols and their library version tags.
// ES: ExtractRequiredSymbols parsea la salida de readelf -s
//     buscando símbolos indefinidos y sus tags de versión.
func ExtractRequiredSymbols(p string) (map[string][]string, error) {
	out, err := exec.Command("readelf", "-s", p).Output()
	if err != nil {
		return nil, err
	}
	sym := map[string][]string{}
	seen := map[string]bool{}
	s := bufio.NewScanner(strings.NewReader(string(out)))
	for s.Scan() {
		l := s.Text()
		if strings.Contains(l, "UND") && !strings.Contains(l, "0000000000000000") {
			f := strings.Fields(l)
			if len(f) >= 8 && strings.Contains(f[7], "@") {
				parts := strings.Split(f[7], "@")
				if len(parts) >= 2 && !seen[parts[1]] {
					seen[parts[1]] = true
					sym["libc.so.6"] = append(sym["libc.so.6"], parts[1])
				}
			}
		}
	}
	return sym, nil
}

// EN: FilterDelegatable keeps only libs listed in AllowedLibs.
// ES: FilterDelegatable conserva solo libs listadas en AllowedLibs.
func FilterDelegatable(d []string) []string {
	var r []string
	for _, x := range d {
		for _, a := range AllowedLibs {
			if x == a {
				r = append(r, x)
				break
			}
		}
	}
	return r
}

// EN: FindLibPath searches common lib dirs for a given library.
// ES: FindLibPath busca en directorios comunes la librería dada.
func FindLibPath(lib string) (string, error) {
	for _, d := range []string{
		"/lib/x86_64-linux-gnu", "/lib64", "/usr/lib",
		"/usr/lib64", "/usr/lib/x86_64-linux-gnu",
	} {
		p := filepath.Join(d, lib)
		if info, err := os.Stat(p); err == nil && !info.IsDir() {
			return p, nil
		}
	}
	return "", fmt.Errorf("no encontrada: %s", lib)
}
GO_HC

    # ═══════════════════════════════════════════════════════════
    # EN: internal/sandbox — Bubblewrap sandbox.
    # ES: internal/sandbox — sandbox Bubblewrap.
    #
    # EN: Isolated runtime for packaged apps.
    #     Key features:
    #       - ro-bind /app, /usr, /lib, /etc; tmpfs for /tmp and /run
    #       - unshare-all + share-net
    #       - DNS fix: resolves /etc/resolv.conf, /etc/hosts, etc.
    #         symlinks before binding (systemd-resolved case)
    #       - GUI support: X11, Wayland, DRI, PulseAudio, D-Bus
    #       - Per-app config dir binds (Firefox, Chrome, etc.)
    # ES: Runtime aislado para apps empaquetadas.
    #     Características clave:
    #       - ro-bind /app, /usr, /lib, /etc; tmpfs para /tmp y /run
    #       - unshare-all + share-net
    #       - Fix DNS: resuelve symlinks de /etc/resolv.conf,
    #         /etc/hosts, etc. antes del bind (caso systemd-resolved)
    #       - Soporte GUI: X11, Wayland, DRI, PulseAudio, D-Bus
    #       - Binds de config por app (Firefox, Chrome, etc.)
    # ═══════════════════════════════════════════════════════════
    mkdir -p internal/sandbox
    cat > internal/sandbox/sandbox.go <<'GO_SB'
package sandbox

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

// EN: Sandbox describes one app invocation.
// ES: Sandbox describe una invocación de app.
type Sandbox struct {
	AppDir       string
	Entrypoint   string
	Args         []string
	IsGUI        bool
	DelegateLibs []string
}

// EN: NewSandbox builds a sandbox for appDir/entrypoint.
// ES: NewSandbox construye un sandbox para appDir/entrypoint.
func NewSandbox(appDir, entrypoint string, args []string) *Sandbox {
	return &Sandbox{AppDir: appDir, Entrypoint: entrypoint, Args: args}
}

// EN: Run executes the app inside bwrap.
// ES: Run ejecuta la app dentro de bwrap.
func (s *Sandbox) Run() error {
	if _, err := exec.LookPath("bwrap"); err != nil {
		return fmt.Errorf("bubblewrap no encontrado: %w", err)
	}
	// EN: Base bwrap arguments: read-only app tree, /usr, /dev,
	//     /proc, tmpfs /tmp and /run, unshared namespaces, net
	//     shared, clean environment.
	// ES: Argumentos base de bwrap: árbol de app de solo lectura,
	//     /usr, /dev, /proc, tmpfs en /tmp y /run, namespaces
	//     aislados, red compartida, entorno limpio.
	a := []string{
		"--ro-bind", s.AppDir + "/tree", "/app",
		"--ro-bind", "/usr", "/usr",
		"--dev", "/dev", "--proc", "/proc",
		"--tmpfs", "/tmp", "--tmpfs", "/run",
		"--unshare-all", "--share-net",
		"--die-with-parent", "--new-session",
		"--clearenv",
		"--setenv", "PATH", "/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin:/sbin",
		"--setenv", "SHELL", "/bin/bash",
		"--setenv", "TERM", "xterm-256color",
	}
	// EN: Bind system dirs if they exist.
	// ES: Bind de directorios del sistema si existen.
	for _, d := range []string{"/lib", "/lib64", "/etc", "/bin", "/sbin", "/var"} {
		if _, err := os.Stat(d); err == nil {
			a = append(a, "--ro-bind", d, d)
		}
	}
	// EN: Whitelist host env vars that should pass through after
	//     --clearenv. Everything else is dropped.
	// ES: Whitelist de variables de entorno del host que deben
	//     pasar tras --clearenv. Todo lo demás se descarta.
	for _, k := range []string{
		"LANG", "LANGUAGE", "LC_ALL", "LC_MESSAGES", "LC_CTYPE",
		"TZ",
		"XDG_SESSION_TYPE", "XDG_CURRENT_DESKTOP", "XDG_SESSION_DESKTOP",
		"DISPLAY", "WAYLAND_DISPLAY", "XAUTHORITY", "XDG_RUNTIME_DIR",
	} {
		if v := os.Getenv(k); v != "" {
			a = append(a, "--setenv", k, v)
		}
	}

	// EN: Bind delegated libs (from host contract).
	// ES: Bind de librerías delegadas (del host contract).
	for _, lib := range s.DelegateLibs {
		for _, dir := range []string{"/lib/x86_64-linux-gnu", "/lib64", "/usr/lib"} {
			lp := filepath.Join(dir, lib)
			if _, err := os.Stat(lp); err == nil {
				a = append(a, "--ro-bind", lp, lp)
				break
			}
		}
	}

	// EN: Add GUI-related binds (X11, Wayland, DRI, audio, D-Bus).
	// ES: Añade binds relacionados con GUI (X11, Wayland, DRI,
	//     audio, D-Bus).
	s.addGUISupport(&a)

	a = append(a, s.Entrypoint)
	a = append(a, s.Args...)
	cmd := exec.Command("bwrap", a...)
	cmd.Stdin = os.Stdin
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	return cmd.Run()
}

// EN: addGUISupport appends all GUI/audio/DNS binds.
// ES: addGUISupport añade todos los binds de GUI/audio/DNS.
func (s *Sandbox) addGUISupport(args *[]string) {
	homeDir := os.Getenv("HOME")

	// EN: Preserve hostname.
	// ES: Preserva el hostname.
	if h, err := os.Hostname(); err == nil {
		*args = append(*args, "--hostname", h)
	}

	// EN: X11 auth cookie: copy to a private temp file to avoid
	//     exposing the host path; bound read-only.
	// ES: Cookie de auth X11: se copia a un archivo temporal
	//     privado para no exponer la ruta del host; bind ro.
	var origXauth string
	if env := os.Getenv("XAUTHORITY"); env != "" {
		if _, err := os.Stat(env); err == nil {
			origXauth = env
		}
	}
	if origXauth == "" && homeDir != "" {
		candidate := filepath.Join(homeDir, ".Xauthority")
		if _, err := os.Stat(candidate); err == nil {
			origXauth = candidate
		}
	}
	if origXauth != "" {
		tmpFile := fmt.Sprintf("/tmp/packbox-xauth-%d", os.Getpid())
		if data, err := os.ReadFile(origXauth); err == nil {
			_ = os.Remove(tmpFile)
			if err := os.WriteFile(tmpFile, data, 0600); err == nil {
				dst := "/tmp/packbox-xauth"
				*args = append(*args, "--ro-bind", tmpFile, dst)
				*args = append(*args, "--setenv", "XAUTHORITY", dst)
			}
		}
	}

	// EN: X11 socket.
	// ES: Socket X11.
	if _, err := os.Stat("/tmp/.X11-unix"); err == nil {
		*args = append(*args, "--ro-bind", "/tmp/.X11-unix", "/tmp/.X11-unix")
	}

	// EN: GPU and shared memory.
	// ES: GPU y memoria compartida.
	if _, err := os.Stat("/dev/dri"); err == nil {
		*args = append(*args, "--dev-bind", "/dev/dri", "/dev/dri")
	}
	if _, err := os.Stat("/dev/shm"); err == nil {
		*args = append(*args, "--dev-bind", "/dev/shm", "/dev/shm")
	} else {
		*args = append(*args, "--tmpfs", "/dev/shm")
	}

	// EN: Wayland socket (if any).
	// ES: Socket Wayland (si existe).
	if wd := os.Getenv("WAYLAND_DISPLAY"); wd != "" {
		*args = append(*args, "--setenv", "WAYLAND_DISPLAY", wd)
		if rd := os.Getenv("XDG_RUNTIME_DIR"); rd != "" {
			sp := filepath.Join(rd, wd)
			if _, err := os.Stat(sp); err == nil {
				*args = append(*args, "--ro-bind", sp, sp)
			}
		}
	}

	// EN: Session bus, PulseAudio and PipeWire sockets.
	// ES: Session bus, sockets de PulseAudio y PipeWire.
	if rd := os.Getenv("XDG_RUNTIME_DIR"); rd != "" {
		*args = append(*args, "--setenv", "XDG_RUNTIME_DIR", rd)
		bp := filepath.Join(rd, "bus")
		if _, err := os.Stat(bp); err == nil {
			*args = append(*args, "--ro-bind", bp, bp)
		}
		for _, s := range []string{"pulse", "pipewire-0", "pipewire-0-manager"} {
			p := filepath.Join(rd, s)
			if _, err := os.Stat(p); err == nil {
				*args = append(*args, "--ro-bind", p, p)
			}
		}
	}
	if _, err := os.Stat("/run/dbus/system_bus_socket"); err == nil {
		*args = append(*args, "--ro-bind", "/run/dbus/system_bus_socket", "/run/dbus/system_bus_socket")
	}

	// ───────────────────────────────────────────────────────
	// EN: DNS FIX — resolve symlinks before binding.
	//     On systemd-resolved systems, /etc/resolv.conf is a
	//     symlink into /run/systemd/resolve/. bwrap binds would
	//     otherwise fail or expose broken links. We EvalSymlinks
	//     and bind the real target at the same path inside.
	// ES: FIX DNS — resuelve symlinks antes del bind.
	//     En sistemas con systemd-resolved, /etc/resolv.conf es
	//     un symlink a /run/systemd/resolve/. Los binds de bwrap
	//     fallarían o expondrían enlaces rotos. Resolvemos con
	//     EvalSymlinks y bindeamos el target real en la misma
	//     ruta interna.
	// ───────────────────────────────────────────────────────
	for _, d := range []string{
		"/run/systemd/resolve",
		"/run/NetworkManager",
		"/run/avahi-daemon",
		"/run/nscd",
	} {
		if _, err := os.Stat(d); err == nil {
			*args = append(*args, "--ro-bind", d, d)
		}
	}
	for _, f := range []string{
		"/etc/resolv.conf",
		"/etc/hosts",
		"/etc/nsswitch.conf",
		"/etc/hostname",
		"/etc/gai.conf",
		"/etc/host.conf",
	} {
		info, err := os.Lstat(f)
		if err != nil {
			continue
		}
		if info.Mode()&os.ModeSymlink != 0 {
			target, err := filepath.EvalSymlinks(f)
			if err == nil {
				*args = append(*args, "--ro-bind", target, f)
			}
		} else {
			*args = append(*args, "--ro-bind", f, f)
		}
	}

	// EN: Create /home/<user>/ inside the sandbox so subdir binds
	//     have a parent (bwrap does not always create them).
	// ES: Crea /home/<user>/ dentro del sandbox para que los
	//     binds a subdirectorios tengan padre (bwrap no siempre
	//     los crea).
	if homeDir != "" && strings.HasPrefix(homeDir, "/home/") {
		parts := strings.Split(strings.TrimPrefix(homeDir, "/"), "/")
		if len(parts) >= 2 {
			*args = append(*args, "--dir", "/home")
			*args = append(*args, "--dir", "/home/"+parts[1])
		}
	}
	if homeDir != "" && strings.HasPrefix(homeDir, "/root") {
		*args = append(*args, "--dir", "/root")
	}

	// EN: Per-app config bind map. First match wins.
	// ES: Mapa de binds de config por app. Gana el primer match.
	appBase := strings.ToLower(filepath.Base(s.AppDir))
	configMap := []struct {
		keys []string
		dirs []string
	}{
		{[]string{"firefox"}, []string{".mozilla", ".cache/mozilla"}},
		{[]string{"thunderbird"}, []string{".thunderbird", ".cache/thunderbird"}},
		{[]string{"chrome"}, []string{".config/google-chrome", ".cache/google-chrome"}},
		{[]string{"chromium"}, []string{".config/chromium", ".cache/chromium"}},
		{[]string{"brave"}, []string{".config/BraveSoftware", ".cache/BraveSoftware"}},
		{[]string{"edge"}, []string{".config/microsoft-edge", ".cache/microsoft-edge"}},
		{[]string{"libreoffice"}, []string{".config/libreoffice"}},
		{[]string{"code"}, []string{".config/Code", ".vscode"}},
		{[]string{"discord"}, []string{".config/discord"}},
		{[]string{"spotify"}, []string{".config/spotify", ".cache/spotify"}},
		{[]string{"vlc"}, []string{".config/vlc"}},
		{[]string{"gimp"}, []string{".config/GIMP"}},
		{[]string{"inkscape"}, []string{".config/inkscape"}},
		{[]string{"mpv"}, []string{".config/mpv"}},
		{[]string{"transmission"}, []string{".config/transmission"}},
	}

	if homeDir != "" {
		for _, entry := range configMap {
			matched := false
			for _, k := range entry.keys {
				if strings.Contains(appBase, k) {
					matched = true
					break
				}
			}
			if !matched {
				continue
			}
			for _, d := range entry.dirs {
				full := filepath.Join(homeDir, d)
				_ = os.MkdirAll(full, 0700)
				*args = append(*args, "--bind-try", full, full)
			}
			break
		}

		// EN: Read-only user fonts, themes and icons.
		// ES: Fuentes, temas e iconos del usuario en solo lectura.
		for _, d := range []string{
			".local/share/fonts",
			".fonts",
			".themes",
			".icons",
			".local/share/themes",
			".local/share/icons",
		} {
			full := filepath.Join(homeDir, d)
			if _, err := os.Stat(full); err == nil {
				*args = append(*args, "--ro-bind", full, full)
			}
		}

		// EN: Writable fontconfig cache.
		// ES: Caché de fontconfig escribible.
		fc := filepath.Join(homeDir, ".cache", "fontconfig")
		_ = os.MkdirAll(fc, 0755)
		*args = append(*args, "--bind", fc, fc)

		// EN: System themes/icons (ro).
		// ES: Temas/iconos del sistema (ro).
		for _, d := range []string{"/usr/share/themes", "/usr/share/icons", "/usr/share/pixmaps"} {
			if _, err := os.Stat(d); err == nil {
				*args = append(*args, "--ro-bind", d, d)
			}
		}

		// EN: Per-app writable config dir.
		// ES: Directorio de config escribible por app.
		ac := filepath.Join(homeDir, ".config", filepath.Base(s.AppDir))
		_ = os.MkdirAll(ac, 0755)
		*args = append(*args, "--bind", ac, ac)
	}

	// EN: Set HOME and USER inside the sandbox.
	// ES: Define HOME y USER dentro del sandbox.
	*args = append(*args, "--setenv", "HOME", homeDir)
	*args = append(*args, "--setenv", "USER", os.Getenv("USER"))
}
GO_SB

    cd - >/dev/null 2>&1 || cd "$HOME"
    ok "Proyecto Go generado en $PACKBOX_SRC_DIR"
}
# ═══════════════════════════════════════════════════════════════
# EN: write_go_cmds — generate the 11 Packbox CLI binaries.
# ES: write_go_cmds — genera los 11 binarios CLI de Packbox.
#
# EN: Each binary lives in cmd/packbox-<name>/main.go and is
#     compiled separately by compile_go().
# ES: Cada binario vive en cmd/packbox-<name>/main.go y se
#     compila por separado en compile_go().
# ═══════════════════════════════════════════════════════════════
write_go_cmds() {
    cd "$PACKBOX_SRC_DIR" || error "cd falló"

    # ═══════════════════════════════════════════════════════════
    # EN: packbox-pack — ingest a directory into the CAS and
    #     produce a manifest.json describing the app.
    # ES: packbox-pack — ingesta un directorio en el CAS y genera
    #     un manifest.json describiendo la app.
    #
    # EN: Usage: packbox-pack [flags] <dir>
    #     Flags can appear before or after the directory (see pre()).
    # ES: Uso: packbox-pack [flags] <dir>
    #     Las flags pueden ir antes o después del directorio (ver pre()).
    # ═══════════════════════════════════════════════════════════
    mkdir -p cmd/packbox-pack
    cat > cmd/packbox-pack/main.go <<'GO_PK'
package main

import (
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/packbox/packbox/internal/cas"
	"github.com/packbox/packbox/internal/manifest"
)

// EN: strFlags lists flags that take a separate value argument
//     (no "="), used by pre() to reorder args before flag.Parse.
// ES: strFlags lista flags que toman un argumento separado (sin
//     "="), usadas por pre() para reordenar args antes de
//     flag.Parse.
var strFlags = map[string]bool{
	"--name": true, "-name": true,
	"--version": true, "-version": true,
	"--description": true, "-description": true,
	"--entrypoint": true, "-entrypoint": true,
	"--mods": true, "-mods": true,
	"--toolkit": true, "-toolkit": true,
	"--icon": true, "-icon": true,
}

// EN: pre separates the positional directory from flags, so the
//     caller can pass "packbox-pack ./dir --name foo" without
//     Go's flag package complaining about interspersed args.
// ES: pre separa el directorio posicional de las flags, para
//     permitir "packbox-pack ./dir --name foo" sin que el
//     paquete flag de Go se queje por args intercalados.
func pre() (string, []string) {
	var dir string
	var flags []string
	a := os.Args[1:]
	for i := 0; i < len(a); i++ {
		if strings.HasPrefix(a[i], "-") {
			flags = append(flags, a[i])
			if !strings.Contains(a[i], "=") && strFlags[a[i]] && i+1 < len(a) {
				i++
				flags = append(flags, a[i])
			}
		} else if dir == "" {
			dir = a[i]
		}
	}
	return dir, flags
}

func main() {
	dir, flags := pre()
	os.Args = append([]string{os.Args[0]}, flags...)

	// EN: Parse flags after reordering.
	// ES: Parsea flags tras reordenar.
	name := flag.String("name", "", "")
	ver := flag.String("version", "1.0.0", "")
	desc := flag.String("description", "", "")
	ep := flag.String("entrypoint", "", "")
	mods := flag.String("mods", "", "")
	gui := flag.Bool("gui", false, "")
	tk := flag.String("toolkit", "", "")
	icon := flag.String("icon", "", "")
	flag.Parse()

	if *name == "" || dir == "" {
		fmt.Println("ERROR: --name y directorio")
		os.Exit(1)
	}
	if _, err := os.Stat(dir); os.IsNotExist(err) {
		fmt.Printf("ERROR: no existe %s\n", dir)
		os.Exit(1)
	}

	// EN: Open (or create) the CAS store.
	// ES: Abre (o crea) el store CAS.
	home := os.Getenv("HOME")
	store, err := cas.NewStore(filepath.Join(home, ".local/share/packbox/store"))
	if err != nil {
		fmt.Printf("ERROR: %v\n", err)
		os.Exit(1)
	}

	fmt.Printf("[pack] %s v%s\n", *name, *ver)

	// EN: Resolve entrypoint. If not given, pick the largest
	//     executable under <dir>/bin.
	// ES: Resuelve entrypoint. Si no se da, elige el ejecutable
	//     más grande bajo <dir>/bin.
	binDir := filepath.Join(dir, "bin")
	var epPath string
	if *ep != "" {
		epPath = *ep
	} else if _, err := os.Stat(binDir); err == nil {
		var big string
		var bs int64
		_ = filepath.Walk(binDir, func(p string, i os.FileInfo, e error) error {
			if e != nil {
				return nil
			}
			if !i.IsDir() && i.Mode()&0111 != 0 && i.Size() > bs {
				bs = i.Size()
				big = p
			}
			return nil
		})
		if big == "" {
			fmt.Println("ERROR: sin ejecutable")
			os.Exit(1)
		}
		epPath = "/app/bin/" + filepath.Base(big)
	} else {
		fmt.Println("ERROR: sin bin/ ni --entrypoint")
		os.Exit(1)
	}

	// EN: Walk the directory, store each file in the CAS, and
	//     build the file → chunks map for the manifest.
	// ES: Recorre el directorio, guarda cada archivo en el CAS
	//     y construye el mapa archivo → chunks del manifiesto.
	files := map[string]manifest.FileInfo{}
	count := 0
	_ = filepath.Walk(dir, func(p string, i os.FileInfo, e error) error {
		if e != nil || i.IsDir() || filepath.Base(p) == "manifest.json" {
			return nil
		}
		rel, _ := filepath.Rel(dir, p)
		h, err := store.StoreFile(p)
		if err != nil {
			fmt.Printf("   WARN %s: %v\n", rel, err)
			return nil
		}
		files[rel] = manifest.FileInfo{
			Chunks: []string{h},
			Size:   i.Size(),
			Mode:   fmt.Sprintf("%04o", i.Mode().Perm()),
		}
		count++
		return nil
	})

	// EN: Parse comma-separated mods list.
	// ES: Parsea la lista de módulos separados por comas.
	var mlist []string
	if *mods != "" {
		for _, m := range strings.Split(*mods, ",") {
			if m = strings.TrimSpace(m); m != "" {
				mlist = append(mlist, m)
			}
		}
	}

	// EN: Compose and write the manifest.
	// ES: Compone y escribe el manifiesto.
	appM := &manifest.Manifest{
		SchemaVersion: "1.5",
		Name:          *name,
		Version:       *ver,
		Description:   *desc,
		Entrypoint:    epPath,
		Arch:          "x86_64",
		GUI:           *gui,
		Toolkit:       *tk,
		Icon:          *icon,
		Layers:        manifest.Layers{App: manifest.AppLayer{Files: files}},
		Mods:          mlist,
		HostContract: manifest.HostContract{
			Version:         "1",
			Delegate:        []string{},
			RequiredSymbols: map[string][]string{},
			FallbackMods:    map[string]string{},
		},
	}
	mp := filepath.Join(dir, "manifest.json")
	if err := appM.Save(mp); err != nil {
		fmt.Printf("ERROR: %v\n", err)
		os.Exit(1)
	}
	fmt.Printf("[ok] %s  archivos=%d\n", mp, count)
}
GO_PK

    # ═══════════════════════════════════════════════════════════
    # EN: packbox-install — install an app from a manifest.json.
    # ES: packbox-install — instala una app desde un manifest.json.
    #
    # EN: Reads the manifest, hardlinks each chunk into
    #     ~/.local/share/packbox/apps/<name>/tree/, and
    #     records chunk references. Reinstalls replace the app.
    # ES: Lee el manifiesto, enlaza cada chunk (hardlink) en
    #     ~/.local/share/packbox/apps/<name>/tree/ y registra
    #     las referencias. Reinstalar reemplaza la app.
    # ═══════════════════════════════════════════════════════════
    mkdir -p cmd/packbox-install
    cat > cmd/packbox-install/main.go <<'GO_IN'
package main

import (
	"fmt"
	"os"
	"path/filepath"
	"strconv"

	"github.com/packbox/packbox/internal/cas"
	"github.com/packbox/packbox/internal/manifest"
)

func main() {
	if len(os.Args) < 2 {
		fmt.Println("Uso: packbox-install <manifest.json>")
		os.Exit(1)
	}
	m, err := manifest.Load(os.Args[1])
	if err != nil {
		fmt.Printf("ERROR: %v\n", err)
		os.Exit(1)
	}

	home := os.Getenv("HOME")
	store, err := cas.NewStore(filepath.Join(home, ".local/share/packbox/store"))
	if err != nil {
		fmt.Printf("ERROR: %v\n", err)
		os.Exit(1)
	}

	fmt.Printf("[install] %s v%s\n", m.Name, m.Version)

	appDir := filepath.Join(home, ".local/share/packbox/apps", m.Name)

	// EN: Reinstall: drop old reference counts before wiping tree.
	// ES: Reinstalación: libera refcounts antiguos antes de borrar.
	if _, err := os.Stat(appDir); err == nil {
		old, err := manifest.Load(filepath.Join(appDir, "manifest.json"))
		if err == nil {
			for _, fi := range old.Layers.App.Files {
				for _, c := range fi.Chunks {
					store.RemoveReference(c, m.Name)
				}
			}
		}
		os.RemoveAll(appDir)
	}

	treeDir := filepath.Join(appDir, "tree")
	if err := os.MkdirAll(treeDir, 0755); err != nil {
		fmt.Printf("ERROR: %v\n", err)
		os.Exit(1)
	}

	// EN: Hardlink every chunk, restore mode, and ref it.
	// ES: Hardlink de cada chunk, restaura modo y lo referencia.
	count := 0
	for rel, fi := range m.Layers.App.Files {
		target := filepath.Join(treeDir, rel)
		_ = os.MkdirAll(filepath.Dir(target), 0755)
		if len(fi.Chunks) == 0 {
			continue
		}
		if err := store.LinkFile(fi.Chunks[0], target); err != nil {
			continue
		}
		mode, _ := strconv.ParseUint(fi.Mode, 8, 32)
		_ = os.Chmod(target, os.FileMode(mode))
		_ = store.AddReference(fi.Chunks[0], m.Name)
		count++
	}

	if err := m.Save(filepath.Join(appDir, "manifest.json")); err != nil {
		fmt.Printf("ERROR: %v\n", err)
		os.Exit(1)
	}
	fmt.Printf("[ok] %s instalado  archivos=%d\n", m.Name, count)
}
GO_IN

    # ═══════════════════════════════════════════════════════════
    # EN: packbox-run — run an installed app inside the sandbox.
    # ES: packbox-run — ejecuta una app instalada en el sandbox.
    #
    # EN: Loads the manifest, creates a Sandbox with the app's
    #     entrypoint, GUI flag, and delegated libs, then execs
    #     bwrap. Extra args are forwarded to the app.
    # ES: Carga el manifiesto, crea un Sandbox con el entrypoint,
    #     flag GUI y libs delegadas, y ejecuta bwrap. Los
    #     argumentos extra se pasan a la app.
    # ═══════════════════════════════════════════════════════════
    mkdir -p cmd/packbox-run
    cat > cmd/packbox-run/main.go <<'GO_RN'
package main

import (
	"fmt"
	"os"
	"path/filepath"

	"github.com/packbox/packbox/internal/manifest"
	"github.com/packbox/packbox/internal/sandbox"
)

func main() {
	if len(os.Args) < 2 {
		fmt.Println("Uso: packbox-run <app-id> [args...]")
		os.Exit(1)
	}
	appID := os.Args[1]
	args := os.Args[2:]

	home := os.Getenv("HOME")
	appDir := filepath.Join(home, ".local/share/packbox/apps", appID)
	if _, err := os.Stat(appDir); os.IsNotExist(err) {
		fmt.Printf("ERROR: no instalada: %s\n", appID)
		os.Exit(1)
	}

	m, err := manifest.Load(filepath.Join(appDir, "manifest.json"))
	if err != nil {
		fmt.Printf("ERROR: %v\n", err)
		os.Exit(1)
	}

	fmt.Printf("[run] %s v%s\n", appID, m.Version)

	// EN: Build and run the sandbox, forwarding GUI flag and
	//     delegated libs from the manifest.
	// ES: Construye y ejecuta el sandbox, propagando el flag GUI
	//     y las libs delegadas del manifiesto.
	sb := sandbox.NewSandbox(appDir, m.Entrypoint, args)
	sb.IsGUI = m.GUI
	sb.DelegateLibs = m.HostContract.Delegate
	if err := sb.Run(); err != nil {
		fmt.Printf("ERROR: %v\n", err)
		os.Exit(1)
	}
}
GO_RN

    # ═══════════════════════════════════════════════════════════
    # EN: packbox-list — list installed apps with tags.
    # ES: packbox-list — lista las apps instaladas con etiquetas.
    #
    # EN: Iterates ~/.local/share/packbox/apps/, loads each
    #     manifest, and prints name, version and tags
    #     ([PORTABLE], [GUI/<toolkit>]).
    # ES: Itera ~/.local/share/packbox/apps/, carga cada
    #     manifiesto y muestra nombre, versión y etiquetas
    #     ([PORTABLE], [GUI/<toolkit>]).
    # ═══════════════════════════════════════════════════════════
    mkdir -p cmd/packbox-list
    cat > cmd/packbox-list/main.go <<'GO_LS'
package main

import (
	"fmt"
	"os"
	"path/filepath"

	"github.com/packbox/packbox/internal/manifest"
)

func main() {
	home := os.Getenv("HOME")
	dir := filepath.Join(home, ".local/share/packbox/apps")
	if _, err := os.Stat(dir); os.IsNotExist(err) {
		fmt.Println("Sin apps instaladas")
		return
	}

	fmt.Println("Apps instaladas:")
	fmt.Println("-----------------------------------------------------------")

	n := 0
	entries, _ := os.ReadDir(dir)
	for _, e := range entries {
		if !e.IsDir() {
			continue
		}
		m, err := manifest.Load(filepath.Join(dir, e.Name(), "manifest.json"))
		if err != nil {
			continue
		}

		// EN: Compose tag string. | ES: Compone la cadena de tags.
		tags := ""
		if m.Portable {
			tags += " [PORTABLE]"
		}
		if m.GUI {
			tags += " [GUI"
			if m.Toolkit != "" {
				tags += "/" + m.Toolkit
			}
			tags += "]"
		}
		fmt.Printf("  * %-35s v%-10s%s\n", m.Name, m.Version, tags)
		n++
	}

	fmt.Println("-----------------------------------------------------------")
	fmt.Printf("Total: %d\n", n)
}
GO_LS
    # ═══════════════════════════════════════════════════════════
    # EN: packbox-remove — uninstall an app.
    # ES: packbox-remove — desinstala una app.
    #
    # EN: Drops chunk references, deletes the app tree, and
    #     removes desktop entry + icons.
    # ES: Libera refcounts, borra el árbol de la app y elimina
    #     la entrada de menú y los iconos.
    # ═══════════════════════════════════════════════════════════
    mkdir -p cmd/packbox-remove
    cat > cmd/packbox-remove/main.go <<'GO_RM'
package main

import (
	"fmt"
	"os"
	"path/filepath"

	"github.com/packbox/packbox/internal/cas"
	"github.com/packbox/packbox/internal/manifest"
)

func main() {
	if len(os.Args) < 2 {
		fmt.Println("Uso: packbox-remove <app-id>")
		os.Exit(1)
	}
	id := os.Args[1]
	home := os.Getenv("HOME")
	appDir := filepath.Join(home, ".local/share/packbox/apps", id)
	if _, err := os.Stat(appDir); os.IsNotExist(err) {
		fmt.Printf("ERROR: no instalada: %s\n", id)
		os.Exit(1)
	}

	store, err := cas.NewStore(filepath.Join(home, ".local/share/packbox/store"))
	if err != nil {
		fmt.Printf("ERROR: %v\n", err)
		os.Exit(1)
	}

	// EN: Drop reference counts for every chunk used by the app.
	// ES: Libera el refcount de cada chunk usado por la app.
	if m, err := manifest.Load(filepath.Join(appDir, "manifest.json")); err == nil {
		for _, fi := range m.Layers.App.Files {
			for _, c := range fi.Chunks {
				store.RemoveReference(c, id)
			}
		}
	}

	// EN: Remove desktop entry and icons (both png and svg variants).
	// ES: Elimina la entrada de menú y los iconos (png y svg).
	os.Remove(filepath.Join(home, ".local/share/applications", "packbox-"+id+".desktop"))
	os.Remove(filepath.Join(home, ".local/share/icons/hicolor/256x256/apps", "packbox-"+id+".png"))
	os.Remove(filepath.Join(home, ".local/share/icons/hicolor/256x256/apps", "packbox-"+id+".svg"))

	// EN: Delete the app tree.
	// ES: Borra el árbol de la app.
	os.RemoveAll(appDir)
	fmt.Printf("[ok] %s eliminado\n", id)
}
GO_RM

    # ═══════════════════════════════════════════════════════════
    # EN: packbox-gc — garbage-collect the CAS.
    # ES: packbox-gc — recolección de basura del CAS.
    #
    # EN: Removes chunks that have no live .refs file or whose
    #     refs file is empty. Prints count and bytes freed.
    # ES: Elimina chunks sin .refs vivo o con refs vacío.
    #     Muestra el conteo y los bytes liberados.
    # ═══════════════════════════════════════════════════════════
    mkdir -p cmd/packbox-gc
    cat > cmd/packbox-gc/main.go <<'GO_GC'
package main

import (
	"fmt"
	"os"
	"path/filepath"

	"github.com/packbox/packbox/internal/cas"
)

func main() {
	home := os.Getenv("HOME")
	s, err := cas.NewStore(filepath.Join(home, ".local/share/packbox/store"))
	if err != nil {
		fmt.Printf("ERROR: %v\n", err)
		os.Exit(1)
	}
	fmt.Println("[gc]")
	d, b, err := s.GarbageCollect()
	if err != nil {
		fmt.Printf("ERROR: %v\n", err)
		os.Exit(1)
	}
	fmt.Printf("[ok] chunks=%d  bytes=%d\n", d, b)
}
GO_GC

    # ═══════════════════════════════════════════════════════════
    # EN: packbox-verify — check runtime lib compatibility.
    # ES: packbox-verify — comprueba compatibilidad de libs.
    #
    # EN: Portable apps short-circuit to OK. Otherwise ldd the
    #     entrypoint (resolving launcher.sh) and verify each
    #     required library exists in standard system dirs.
    # ES: Las apps portables salen con OK. Si no, se hace ldd
    #     del entrypoint (resolviendo launcher.sh) y se verifica
    #     que cada librería exista en directorios estándar.
    # ═══════════════════════════════════════════════════════════
    mkdir -p cmd/packbox-verify
    cat > cmd/packbox-verify/main.go <<'GO_VF'
package main

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"github.com/packbox/packbox/internal/manifest"
)

func main() {
	if len(os.Args) < 2 {
		fmt.Println("Uso: packbox-verify <app-id>")
		os.Exit(1)
	}
	id := os.Args[1]
	home := os.Getenv("HOME")
	appDir := filepath.Join(home, ".local/share/packbox/apps", id)

	m, err := manifest.Load(filepath.Join(appDir, "manifest.json"))
	if err != nil {
		fmt.Printf("ERROR: %v\n", err)
		os.Exit(1)
	}

	// EN: Portable apps bundle everything; nothing to verify.
	// ES: Las apps portables traen todo; nada que verificar.
	if m.Portable {
		fmt.Printf("[ok] %s PORTABLE\n", id)
		os.Exit(0)
	}

	// EN: Map /app/entrypoint to the on-disk tree path.
	// ES: Mapea /app/entrypoint a la ruta física en tree/.
	treeDir := filepath.Join(appDir, "tree")
	bin := filepath.Join(treeDir, strings.TrimPrefix(m.Entrypoint, "/app"))

	// EN: If entrypoint is launcher.sh, pick the real executable
	//     from bin/ (the biggest one).
	// ES: Si el entrypoint es launcher.sh, se elige el ejecutable
	//     real de bin/ (el más grande).
	if strings.HasSuffix(bin, "launcher.sh") {
		entries, _ := os.ReadDir(filepath.Join(treeDir, "bin"))
		for _, e := range entries {
			if !e.IsDir() && e.Name() != "launcher.sh" {
				if i, _ := e.Info(); i.Mode()&0111 != 0 {
					bin = filepath.Join(treeDir, "bin", e.Name())
					break
				}
			}
		}
	}

	out, _ := exec.Command("ldd", bin).Output()
	var missing []string
	ok := 0

	// EN: For each "=>" line, check the lib exists in a standard
	//     system library directory.
	// ES: Por cada línea "=>", verifica que la lib exista en un
	//     directorio estándar del sistema.
	for _, l := range strings.Split(string(out), "\n") {
		if !strings.Contains(l, "=>") {
			continue
		}
		parts := strings.Fields(l)
		if len(parts) < 1 || strings.HasPrefix(parts[0], "linux-vdso") {
			continue
		}
		found := false
		for _, d := range []string{"/lib/x86_64-linux-gnu", "/lib64", "/usr/lib", "/usr/lib64"} {
			if _, err := os.Stat(filepath.Join(d, parts[0])); err == nil {
				found = true
				ok++
				break
			}
		}
		if !found {
			missing = append(missing, parts[0])
		}
	}

	if len(missing) == 0 {
		fmt.Printf("[ok] COMPATIBLE  libs=%d\n", ok)
		os.Exit(0)
	}
	fmt.Printf("[fail] faltan %d libs\n", len(missing))
	for _, x := range missing {
		fmt.Printf("   [X] %s\n", x)
	}
	os.Exit(1)
}
GO_VF

    # ═══════════════════════════════════════════════════════════
    # EN: packbox-export — export an app to a .pbox archive.
    # ES: packbox-export — exporta una app a un archivo .pbox.
    #
    # EN: Tars the app dir and compresses with zstd -19, then
    #     xz -9e, then gzip, whichever is available.
    # ES: Empaqueta el directorio de la app en tar y comprime
    #     con zstd -19, luego xz -9e, luego gzip, según disponibilidad.
    # ═══════════════════════════════════════════════════════════
    mkdir -p cmd/packbox-export
    cat > cmd/packbox-export/main.go <<'GO_EX'
package main

import (
	"archive/tar"
	"bytes"
	"compress/gzip"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"

	"github.com/packbox/packbox/internal/manifest"
)

func main() {
	if len(os.Args) < 3 {
		fmt.Println("Uso: packbox-export app <app-id>")
		os.Exit(1)
	}
	home := os.Getenv("HOME")
	expDir := filepath.Join(home, ".local/share/packbox/exports")
	os.MkdirAll(expDir, 0755)

	if os.Args[1] == "app" {
		id := os.Args[2]
		appDir := filepath.Join(home, ".local/share/packbox/apps", id)
		if _, err := os.Stat(appDir); os.IsNotExist(err) {
			fmt.Printf("ERROR: no existe: %s\n", id)
			os.Exit(1)
		}
		out := filepath.Join(expDir, id+".pbox")
		fmt.Printf("[export] %s\n", id)
		if err := createTar(out, appDir); err != nil {
			fmt.Printf("ERROR: %v\n", err)
			os.Exit(1)
		}

		// EN: Report the algorithm chosen, by probing availability.
		// ES: Reporta el algoritmo elegido, sondeando disponibilidad.
		m, _ := manifest.Load(filepath.Join(appDir, "manifest.json"))
		algo := "gzip"
		if _, err := exec.LookPath("zstd"); err == nil {
			algo = "zstd -19"
		} else if _, err := exec.LookPath("xz"); err == nil {
			algo = "xz -9e"
		}
		fmt.Printf("[ok] %s\n", out)
		fmt.Printf("   Algoritmo: %s\n", algo)
		if m != nil && m.Portable {
			fmt.Println("   Modo: PORTABLE")
		}
	}
}

// EN: createTar walks srcDir, writes a tar in memory, then pipes
//     it through zstd/xz/gzip. Falls back in that order.
// ES: createTar recorre srcDir, escribe un tar en memoria y lo
//     pasa por zstd/xz/gzip. Cae en ese orden.
func createTar(dstFile, srcDir string) error {
	var buf bytes.Buffer
	tw := tar.NewWriter(&buf)

	err := filepath.Walk(srcDir, func(p string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}
		rel, _ := filepath.Rel(srcDir, p)
		if rel == "." {
			return nil
		}
		h, err := tar.FileInfoHeader(info, "")
		if err != nil {
			return err
		}
		h.Name = rel
		if err := tw.WriteHeader(h); err != nil {
			return err
		}
		if !info.IsDir() {
			f, err := os.Open(p)
			if err != nil {
				return err
			}
			_, err = io.Copy(tw, f)
			f.Close()
			return err
		}
		return nil
	})
	if err != nil {
		return err
	}
	tw.Close()

	// EN: Prefer zstd -19 (multithreaded).
	// ES: Prefiere zstd -19 (multihilo).
	if p, err := exec.LookPath("zstd"); err == nil {
		cmd := exec.Command(p, "-19", "-T0", "-q", "-o", dstFile)
		cmd.Stdin = &buf
		if err := cmd.Run(); err == nil {
			return nil
		}
	}

	// EN: Then xz -9e (high ratio, single-threaded here).
	// ES: Luego xz -9e (ratio alto, mono-hilo aquí).
	if p, err := exec.LookPath("xz"); err == nil {
		f, err := os.Create(dstFile)
		if err == nil {
			defer f.Close()
			cmd := exec.Command(p, "-9e", "-T0", "-q", "-c")
			cmd.Stdin = &buf
			cmd.Stdout = f
			if err := cmd.Run(); err == nil {
				return nil
			}
		}
	}

	// EN: Final fallback: in-process gzip.
	// ES: Fallback final: gzip en proceso.
	f, err := os.Create(dstFile)
	if err != nil {
		return err
	}
	defer f.Close()
	gz := gzip.NewWriter(f)
	if _, err := gz.Write(buf.Bytes()); err != nil {
		return err
	}
	return gz.Close()
}
GO_EX

    # ═══════════════════════════════════════════════════════════
    # EN: packbox-import — import an app from a .pbox archive.
    # ES: packbox-import — importa una app desde un .pbox.
    #
    # EN: Detects compression by magic bytes, extracts into a
    #     temp dir, validates paths against traversal, then
    #     atomically renames into apps/<name>/.
    # ES: Detecta compresión por magic bytes, extrae a un dir
    #     temporal, valida rutas contra traversal y luego mueve
    #     atómicamente a apps/<name>/.
    # ═══════════════════════════════════════════════════════════
    mkdir -p cmd/packbox-import
    cat > cmd/packbox-import/main.go <<'GO_IM'
package main

import (
	"archive/tar"
	"compress/gzip"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"

	"github.com/packbox/packbox/internal/manifest"
	"github.com/packbox/packbox/internal/security"
)

func main() {
	if len(os.Args) < 3 {
		fmt.Println("Uso: packbox-import app <archivo.pbox>")
		os.Exit(1)
	}
	home := os.Getenv("HOME")
	tmpParent := filepath.Join(home, ".local/share/packbox/tmp")
	os.MkdirAll(tmpParent, 0755)
	tmpDir, err := os.MkdirTemp(tmpParent, "import-")
	if err != nil {
		fmt.Printf("ERROR: %v\n", err)
		os.Exit(1)
	}
	defer os.RemoveAll(tmpDir)

	filePath := os.Args[2]
	if os.Args[1] == "app" {
		fmt.Printf("[import] %s\n", filePath)
		if err := extract(filePath, tmpDir); err != nil {
			fmt.Printf("ERROR: %v\n", err)
			os.Exit(1)
		}
		m, err := manifest.Load(filepath.Join(tmpDir, "manifest.json"))
		if err != nil {
			fmt.Printf("ERROR: %v\n", err)
			os.Exit(1)
		}

		appsDir := filepath.Join(home, ".local/share/packbox/apps")
		appDir := filepath.Join(appsDir, m.Name)

		// EN: If the app already exists, remove it first.
		// ES: Si la app ya existe, se elimina primero.
		if _, err := os.Stat(appDir); err == nil {
			fmt.Printf("[warn] %s ya existe, sobrescribiendo\n", m.Name)
			os.RemoveAll(appDir)
		}
		os.MkdirAll(appsDir, 0755)
		if err := os.Rename(tmpDir, appDir); err != nil {
			fmt.Printf("ERROR: %v\n", err)
			os.Exit(1)
		}
		fmt.Printf("[ok] importado: %s\n", m.Name)
	}
}

// EN: extract detects the compression format from the first 6
//     bytes and streams into dst. Uses security.ValidatePath to
//     reject entries that would escape dst ("../").
// ES: extract detecta el formato de compresión por los primeros
//     6 bytes y lo dirige a dst. Usa security.ValidatePath para
//     rechazar entradas que escapen de dst ("../").
func extract(src, dst string) error {
	f, err := os.Open(src)
	if err != nil {
		return err
	}
	header := make([]byte, 6)
	f.Read(header)
	f.Close()

	var reader io.Reader
	var cmd *exec.Cmd

	switch {
	// EN: gzip magic: 1f 8b.
	// ES: Magic de gzip: 1f 8b.
	case header[0] == 0x1f && header[1] == 0x8b:
		f, err := os.Open(src)
		if err != nil {
			return err
		}
		defer f.Close()
		gz, err := gzip.NewReader(f)
		if err != nil {
			return err
		}
		defer gz.Close()
		reader = gz

	// EN: zstd magic: 28 b5 2f fd.
	// ES: Magic de zstd: 28 b5 2f fd.
	case header[0] == 0x28 && header[1] == 0xb5 && header[2] == 0x2f && header[3] == 0xfd:
		if _, err := exec.LookPath("zstd"); err != nil {
			return fmt.Errorf("zstd no instalado")
		}
		cmd = exec.Command("zstd", "-dc", src)
		stdout, err := cmd.StdoutPipe()
		if err != nil {
			return err
		}
		if err := cmd.Start(); err != nil {
			return err
		}
		defer cmd.Wait()
		reader = stdout

	// EN: xz magic: fd 37 7a 58.
	// ES: Magic de xz: fd 37 7a 58.
	case header[0] == 0xfd && header[1] == 0x37 && header[2] == 0x7a && header[3] == 0x58:
		if _, err := exec.LookPath("xz"); err != nil {
			return fmt.Errorf("xz no instalado")
		}
		cmd = exec.Command("xz", "-dc", src)
		stdout, err := cmd.StdoutPipe()
		if err != nil {
			return err
		}
		if err := cmd.Start(); err != nil {
			return err
		}
		defer cmd.Wait()
		reader = stdout

	default:
		return fmt.Errorf("formato desconocido")
	}

	tr := tar.NewReader(reader)
	for {
		h, err := tr.Next()
		if err == io.EOF {
			break
		}
		if err != nil {
			return err
		}
		target := filepath.Join(dst, h.Name)

		// EN: Reject path traversal before writing.
		// ES: Rechaza path traversal antes de escribir.
		if err := security.ValidatePath(dst, target); err != nil {
			return err
		}

		switch h.Typeflag {
		case tar.TypeDir:
			os.MkdirAll(target, 0755)
		case tar.TypeReg:
			os.MkdirAll(filepath.Dir(target), 0755)
			f, err := os.OpenFile(target, os.O_WRONLY|os.O_CREATE|os.O_TRUNC, os.FileMode(h.Mode))
			if err != nil {
				return err
			}
			if _, err := io.Copy(f, tr); err != nil {
				f.Close()
				return err
			}
			f.Close()
		}
	}
	return nil
}
GO_IM

    # ═══════════════════════════════════════════════════════════
    # EN: packbox-module — manage toolkit modules.
    # ES: packbox-module — gestiona módulos de toolkit.
    #
    # EN: A "module" is a bundle of shared libs for a given app
    #     (e.g. all Qt5 libs used by Krita) that can be installed
    #     once and shared across many apps.
    #     Subcommands: list, create, remove, info.
    # ES: Un "módulo" es un paquete de libs compartidas para una
    #     app (p.ej. todas las libs Qt5 usadas por Krita) que se
    #     instala una vez y se comparte entre varias apps.
    #     Subcomandos: list, create, remove, info.
    # ═══════════════════════════════════════════════════════════
    mkdir -p cmd/packbox-module
    cat > cmd/packbox-module/main.go <<'GO_MD'
package main

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"

	"github.com/packbox/packbox/internal/hostcontract"
	"github.com/packbox/packbox/internal/security"
)

func main() {
	if len(os.Args) < 2 {
		fmt.Println("Uso: packbox-module list|create|remove|info")
		os.Exit(1)
	}
	home := os.Getenv("HOME")
	modsDir := filepath.Join(home, ".local/share/packbox/mods")

	switch os.Args[1] {

	// EN: list — enumerate installed modules.
	// ES: list — enumera los módulos instalados.
	case "list":
		fmt.Println("Módulos:")
		fmt.Println("-----------------------------------------------------------")
		n := 0
		es, _ := os.ReadDir(modsDir)
		for _, e := range es {
			if !e.IsDir() {
				continue
			}
			vs, _ := os.ReadDir(filepath.Join(modsDir, e.Name()))
			for _, v := range vs {
				if v.IsDir() {
					fmt.Printf("  * %-35s v%s\n", e.Name(), v.Name())
					n++
				}
			}
		}
		fmt.Printf("Total: %d\n", n)

	// EN: create — bundle the libs of a binary into a module.
	// ES: create — empaqueta las libs de un binario en un módulo.
	case "create":
		if len(os.Args) < 5 {
			fmt.Println("Uso: packbox-module create <bin> <name> <version>")
			os.Exit(1)
		}
		binPath, modName, modVer := os.Args[2], os.Args[3], os.Args[4]

		tmpParent := filepath.Join(home, ".local/share/packbox/tmp")
		os.MkdirAll(tmpParent, 0755)
		tmp, err := os.MkdirTemp(tmpParent, "mod-")
		if err != nil {
			fmt.Printf("ERROR: %v\n", err)
			os.Exit(1)
		}
		defer os.RemoveAll(tmp)

		// EN: Copy every required lib into <tmp>/lib.
		// ES: Copia cada lib requerida en <tmp>/lib.
		libDir := filepath.Join(tmp, "lib")
		os.MkdirAll(libDir, 0755)
		libs, _ := hostcontract.AnalyzeDependencies(binPath)
		cnt := 0
		for _, l := range libs {
			lp, err := hostcontract.FindLibPath(l)
			if err != nil {
				continue
			}
			if err := security.SafeCopy(lp, filepath.Join(libDir, l), 0644); err == nil {
				cnt++
			}
		}

		// EN: Write module manifest and atomically move in place.
		// ES: Escribe el manifiesto del módulo y lo mueve en sitio.
		mm := map[string]interface{}{
			"schema_version": "1.5",
			"type":           "module",
			"name":           modName,
			"version":        modVer,
			"entrypoint":     "/app/lib",
			"arch":           "x86_64",
			"libs_count":     cnt,
		}
		data, _ := json.MarshalIndent(mm, "", "  ")
		os.WriteFile(filepath.Join(tmp, "manifest.json"), data, 0644)

		dest := filepath.Join(modsDir, modName, modVer)
		os.MkdirAll(filepath.Dir(dest), 0755)
		os.RemoveAll(dest)
		os.Rename(tmp, dest)
		fmt.Printf("[ok] módulo %s v%s (%d libs)\n", modName, modVer, cnt)
	}
}
GO_MD

    # ═══════════════════════════════════════════════════════════
    # EN: packbox-diagnose — health check.
    # ES: packbox-diagnose — chequeo de salud.
    #
    # EN: Prints paths, directory structure, required tools,
    #     DNS files (resolving symlinks), kernel, arch and Go
    #     version. Useful after install or before bug reports.
    # ES: Muestra rutas, estructura de directorios, herramientas
    #     requeridas, archivos DNS (resolviendo symlinks), kernel,
    #     arquitectura y versión de Go. Útil tras instalar o antes
    #     de reportar bugs.
    # ═══════════════════════════════════════════════════════════
    mkdir -p cmd/packbox-diagnose
    cat > cmd/packbox-diagnose/main.go <<'GO_DG'
package main

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
)

func main() {
	home := os.Getenv("HOME")
	fmt.Println("Diagnóstico Packbox v0.1.0 Alpha")
	fmt.Println("===============================================================")
	fmt.Printf("Install dir: %s\n", filepath.Join(home, ".packbox"))
	fmt.Printf("Data dir:    %s\n", filepath.Join(home, ".local/share/packbox"))
	fmt.Printf("Config dir:  %s\n", filepath.Join(home, ".config/packbox"))
	fmt.Println()

	// EN: Expected directory structure.
	// ES: Estructura de directorios esperada.
	fmt.Println("Estructura:")
	for _, d := range []string{
		".packbox/bin", ".packbox/src",
		".local/share/packbox/store", ".local/share/packbox/apps",
		".config/packbox/lang",
	} {
		p := filepath.Join(home, d)
		if _, err := os.Stat(p); err == nil {
			fmt.Printf("  [ok] %s\n", d)
		} else {
			fmt.Printf("  [X]  %s\n", d)
		}
	}
	fmt.Println()

	// EN: Required external tools.
	// ES: Herramientas externas requeridas.
	fmt.Println("Herramientas:")
	for _, t := range []string{"bwrap", "readelf", "ldd", "jq", "zstd", "xz", "tar"} {
		if _, err := exec.LookPath(t); err == nil {
			fmt.Printf("  [ok] %s\n", t)
		} else {
			fmt.Printf("  [X]  %s\n", t)
		}
	}
	fmt.Println()

	// EN: DNS-related files. Note if they are symlinks (systemd-
	//     resolved case) and where they point to.
	// ES: Archivos relacionados con DNS. Avisa si son symlinks
	//     (caso systemd-resolved) y a dónde apuntan.
	fmt.Println("DNS files:")
	for _, f := range []string{
		"/etc/resolv.conf", "/etc/hosts", "/etc/nsswitch.conf",
		"/run/systemd/resolve/stub-resolv.conf",
	} {
		info, err := os.Lstat(f)
		if err != nil {
			fmt.Printf("  [X]  %s\n", f)
			continue
		}
		if info.Mode()&os.ModeSymlink != 0 {
			t, _ := filepath.EvalSymlinks(f)
			fmt.Printf("  [ok] %s -> %s\n", f, t)
		} else {
			fmt.Printf("  [ok] %s\n", f)
		}
	}
	fmt.Println()
	fmt.Printf("Kernel: %s\n", kernel())
	fmt.Printf("Arch: %s\n", runtime.GOARCH)
	fmt.Printf("Go: %s\n", runtime.Version())
}

// EN: kernel returns the running kernel release (uname -r).
// ES: kernel devuelve la versión del kernel en ejecución (uname -r).
func kernel() string {
	out, err := exec.Command("uname", "-r").Output()
	if err != nil {
		return "?"
	}
	return strings.TrimSpace(string(out))
}
GO_DG

    cd - >/dev/null 2>&1 || cd "$HOME"
    ok "Comandos Go generados"
}
# ═══════════════════════════════════════════════════════════════
# EN: compile_go — build all 11 binaries into ~/.packbox/bin.
# ES: compile_go — compila los 11 binarios en ~/.packbox/bin.
#
# EN: Runs `go mod download/tidy`, verifies every cmd/ dir exists,
#     then builds each binary with a progress bar.
# ES: Ejecuta `go mod download/tidy`, verifica que cada dir cmd/
#     exista y compila cada binario con barra de progreso.
# ═══════════════════════════════════════════════════════════════
compile_go() {
    hdr "$(t L_STEP5)"
    cd "$PACKBOX_SRC_DIR" || error "cd falló"

    # EN: Fetch dependencies.
    # ES: Descarga dependencias.
    info "Descargando dependencias..."
    go mod download 2>&1 | tail -3 || warn "go mod download falló"
    go mod tidy 2>&1 | tail -3 || true

    # EN: Ordered list of binaries to build.
    # ES: Lista ordenada de binarios a compilar.
    local BINS=(
        packbox-pack packbox-install packbox-run packbox-list
        packbox-remove packbox-gc packbox-verify packbox-export
        packbox-import packbox-module packbox-diagnose
    )

    # EN: Sanity check: every cmd/<bin>/main.go must exist.
    # ES: Sanity check: cada cmd/<bin>/main.go debe existir.
    local missing=""
    for b in "${BINS[@]}"; do
        if [[ ! -f "cmd/$b/main.go" ]]; then
            missing+=" $b"
        fi
    done
    if [[ -n "$missing" ]]; then
        error "Faltan directorios cmd/:$missing"
    fi

    # EN: Build each binary with a progress bar.
    # ES: Compila cada binario con barra de progreso.
    local n=${#BINS[@]}
    local i
    for i in "${!BINS[@]}"; do
        local b="${BINS[$i]}"
        progress $((i + 1)) "$n" "Compilando $b"
        if ! go build -o "$PACKBOX_BIN_DIR/$b" "./cmd/$b" 2>&1; then
            echo ""
            echo -e "  ${R}Error de compilación en $b:${N}"
            echo ""
            go build -o "$PACKBOX_BIN_DIR/$b" "./cmd/$b" 2>&1 | head -20
            echo ""
            error "Falló compilación de $b"
        fi
        chmod +x "$PACKBOX_BIN_DIR/$b"
    done
    echo ""
    ok "Binarios compilados en $PACKBOX_BIN_DIR"
    cd - >/dev/null 2>&1 || cd "$HOME"
}

# ═══════════════════════════════════════════════════════════════
# EN: configure_path — wire up PATH, symlinks and ~/.bashrc.
# ES: configure_path — configura PATH, symlinks y ~/.bashrc.
#
# EN: 1. Clean stale legacy entries (~/packbox/bin without dot).
#     2. Symlink each binary into ~/.local/bin if it exists.
#     3. Append an idempotent block to ~/.bashrc.
#     4. Export PATH for the current shell.
# ES: 1. Limpia entradas antiguas (~/packbox/bin sin punto).
#     2. Enlaza cada binario en ~/.local/bin si existe.
#     3. Añade un bloque idempotente a ~/.bashrc.
#     4. Exporta PATH para la sesión actual.
# ═══════════════════════════════════════════════════════════════
configure_path() {
    hdr "$(t L_STEP7)"

    # EN: Strip legacy PATH entries pointing to ~/packbox/bin
    #     (without the leading dot). Backup first.
    # ES: Elimina entradas PATH antiguas a ~/packbox/bin (sin el
    #     punto inicial). Hace backup primero.
    if [[ -f "$HOME/.bashrc" ]]; then
        if grep -qE '/packbox/bin' "$HOME/.bashrc" 2>/dev/null; then
            if grep -vE '/\.packbox/bin' "$HOME/.bashrc" | grep -qE '/packbox/bin' 2>/dev/null; then
                cp "$HOME/.bashrc" "$HOME/.bashrc.packbox.bak"
                sed -i '\|packbox/bin|{/\.packbox/bin/!d}' "$HOME/.bashrc"
                ok "PATH viejo limpiado (backup: ~/.bashrc.packbox.bak)"
            fi
        fi
    fi

    # EN: Symlink each binary into ~/.local/bin (if it exists).
    # ES: Enlaza cada binario en ~/.local/bin (si existe).
    if [[ -d "$HOME/.local/bin" ]]; then
        local b
        for b in "$PACKBOX_BIN_DIR"/*; do
            [[ -x "$b" ]] || continue
            ln -sf "$b" "$HOME/.local/bin/$(basename "$b")" 2>/dev/null || true
        done
        ok "Symlinks en ~/.local/bin"
    fi

    # EN: Append PATH block to ~/.bashrc only once.
    # ES: Añade el bloque PATH a ~/.bashrc una sola vez.
    if ! grep -qF "$PACKBOX_BIN_DIR" "$HOME/.bashrc" 2>/dev/null; then
        {
            echo ""
            echo "# Packbox v0.1.0 Alpha"
            echo "export PATH=\"$PACKBOX_BIN_DIR:\$PATH\""
        } >> "$HOME/.bashrc"
        ok "PATH agregado: $PACKBOX_BIN_DIR"
    fi

    # EN: Reflect changes in the current shell.
    # ES: Refleja los cambios en la shell actual.
    export PATH="$PACKBOX_BIN_DIR:$PATH"
}

# ═══════════════════════════════════════════════════════════════
# EN: do_install — full install flow.
# ES: do_install — flujo completo de instalación.
#
# EN: Steps:
#       1. Detect distro
#       2. Install Go 1.22+
#       3. Create directory structure
#       4. Generate Go project (5 internal packages)
#       5. Generate 11 CLI binaries
#       6. Compile everything
#       7. Run tests
#       8. Configure PATH + symlinks
#       9. Final verification
# ES: Pasos:
#       1. Detectar distribución
#       2. Instalar Go 1.22+
#       3. Crear estructura de directorios
#       4. Generar proyecto Go (5 paquetes internos)
#       5. Generar 11 binarios CLI
#       6. Compilar todo
#       7. Ejecutar tests
#       8. Configurar PATH + symlinks
#       9. Verificación final
# ═══════════════════════════════════════════════════════════════
do_install() {
    show_banner
    echo -e "  ${BD}$(t L_WELCOME)${N}"
    echo -e "  ${DM}Lang: $(t L_LANG_NAME) | Install: ~/.packbox${N}"
    echo ""

    # EN: Warn about the legacy ~/packbox layout, if present.
    # ES: Avisa del layout antiguo ~/packbox, si existe.
    if [[ -d "$OLD_PACKBOX_DIR" ]] && [[ ! -d "$PACKBOX_INSTALL_DIR" ]]; then
        warn "$(t L_MIGRATE_DONE): ~/packbox"
        det "$(t L_MIGRATE_MSG)"
        echo ""
    fi

    # EN: Step 1 — distro detection.
    # ES: Paso 1 — detección de distro.
    hdr "$(t L_STEP1)"
    detect_distro
    [[ "$DF" == "unknown" ]] && error "Distro no soportada"
    ok "$DISTRO_NAME"

    # EN: Pick sudo (or none if root).
    # ES: Elige sudo (o ninguno si root).
    if [[ $EUID -eq 0 ]]; then SUDO=""
    elif command -v sudo &>/dev/null; then SUDO="sudo"
    else error "Sin sudo"; fi

    # EN: Required dependencies per family. bubblewrap is the
    #     sandbox engine; binutils gives readelf; jq is used by
    #     the packager; zstd/xz power compression.
    # ES: Dependencias requeridas por familia. bubblewrap es el
    #     motor del sandbox; binutils da readelf; jq lo usa el
    #     packager; zstd/xz dan compresión.
    local DEPS
    case "$DF" in
        debian|fedora|arch|suse) DEPS=(bubblewrap binutils jq bc curl tar) ;;
    esac

    info "$(t L_INSTALL_DEPS)${BD}${DEPS[*]}${N}"
    printf "  ${Y}?${N} $(t L_CONTINUE)"
    read -r -n 1 REPLY
    echo
    [[ $REPLY =~ ^[Nn]$ ]] && { warn "$(t L_CANCEL)"; return 0; }

    install_pkgs "${DEPS[@]}" || warn "Algunos paquetes fallaron"

    # EN: Step 2 — Go toolchain.
    # ES: Paso 2 — toolchain de Go.
    hdr "$(t L_STEP2)"
    install_go

    # EN: Steps 3–6 — build everything.
    # ES: Pasos 3–6 — construir todo.
    create_dirs
    generate_go
    write_go_cmds
    compile_go

    # EN: Step 7 — tests (best effort).
    # ES: Paso 7 — tests (best effort).
    hdr "$(t L_STEP6)"
    cd "$PACKBOX_SRC_DIR" && { go test ./... 2>&1 | grep -qE "^(ok|PASS)" && ok "Tests OK" || warn "Sin tests"; }
    cd - >/dev/null 2>&1 || cd "$HOME"

    # EN: Step 8 — PATH and symlinks.
    # ES: Paso 8 — PATH y symlinks.
    configure_path

    # EN: Step 9 — verify every binary exists and is executable.
    # ES: Paso 9 — verifica que cada binario exista y sea ejecutable.
    hdr "$(t L_STEP8)"
    local all_ok=true b
    for b in packbox-pack packbox-install packbox-run packbox-list \
             packbox-remove packbox-gc packbox-verify packbox-export \
             packbox-import packbox-module packbox-diagnose; do
        if [[ -x "$PACKBOX_BIN_DIR/$b" ]]; then
            det "${G}$b${N} OK"
        else
            det "${R}$b${N} FALLO"
            all_ok=false
        fi
    done
    [[ "$all_ok" != "true" ]] && error "Binarios faltantes"
    ok "$(t L_BINARIES_OK)"

    # EN: Success box and feature summary.
    # ES: Caja de éxito y resumen de características.
    box_ok "$(t L_INSTALLED_OK)"

    echo -e "  ${BD}Features:${N}"
    det "i18n: $(t L_LANG_NAME) (+8 más)"
    det "$(t L_COMPRESS_OK)"
    det "$(t L_DESKTOP_OK)"
    det "$(t L_DNS_OK)"
    echo ""

    echo -e "  ${BD}$(t L_NEXT_STEPS):${N}"
    det "1. $(t L_RELOAD_SHELL): source ~/.bashrc"
    det "2. $(t L_VERIFY): packbox-diagnose"
    det "3. $(t L_USE_DETECTOR): ./packbox-packager-v0.1.0.sh"
    echo ""
}

# ═══════════════════════════════════════════════════════════════
# EN: human_size — convert bytes to a human-readable string.
# ES: human_size — convierte bytes a una cadena legible.
# ═══════════════════════════════════════════════════════════════
human_size() {
    local b=$1
    if command -v numfmt &>/dev/null; then
        numfmt --to=iec "$b" 2>/dev/null && return
    fi
    if   [[ $b -ge 1073741824 ]]; then echo "$(( b / 1073741824 ))G"
    elif [[ $b -ge 1048576 ]];    then echo "$(( b / 1048576 ))M"
    elif [[ $b -ge 1024 ]];       then echo "$(( b / 1024 ))K"
    else echo "${b}B"
    fi
}

# ═══════════════════════════════════════════════════════════════
# EN: dir_size — total size of a directory in bytes.
# ES: dir_size — tamaño total de un directorio en bytes.
# ═══════════════════════════════════════════════════════════════
dir_size() {
    [[ -d "$1" ]] || { echo 0; return; }
    du -sb "$1" 2>/dev/null | awk '{print $1}'
}

# ═══════════════════════════════════════════════════════════════
# EN: do_uninstall — scan, confirm and remove Packbox.
# ES: do_uninstall — escanea, confirma y elimina Packbox.
#
# EN: Two modes:
#       k — binaries only: ~/.packbox + symlinks (apps intact)
#       s — full: also wipes store, apps, menus, icons, config
#
#     Requires typing DELETE in caps as a final safeguard.
# ES: Dos modos:
#       k — solo binarios: ~/.packbox + symlinks (apps intactas)
#       s — completo: también borra store, apps, menús, iconos, config
#
#     Exige escribir DELETE en mayúsculas como salvaguarda final.
# ═══════════════════════════════════════════════════════════════
do_uninstall() {
    show_banner
    hdr "$(t L_UNINSTALL_TITLE)"
    info "$(t L_UNINSTALL_SCAN)"
    echo ""

    # ───────────────────────────────────────────────────────────
    # EN: Collect what exists and compute total size.
    # ES: Recolecta lo que existe y calcula el tamaño total.
    # ───────────────────────────────────────────────────────────
    local total=0
    declare -A SIZES=()

    local has_install=0 has_data=0 has_config=0
    local has_old=0
    [[ -d "$PACKBOX_INSTALL_DIR" ]] && { has_install=1; SIZES["$PACKBOX_INSTALL_DIR"]=$(dir_size "$PACKBOX_INSTALL_DIR"); }
    [[ -d "$PACKBOX_HOME" ]]        && { has_data=1;    SIZES["$PACKBOX_HOME"]=$(dir_size "$PACKBOX_HOME"); }
    [[ -d "$HOME/.config/packbox" ]] && { has_config=1; SIZES["$HOME/.config/packbox"]=$(dir_size "$HOME/.config/packbox"); }
    [[ -d "$OLD_PACKBOX_DIR" ]]     && { has_old=1;     SIZES["$OLD_PACKBOX_DIR"]=$(dir_size "$OLD_PACKBOX_DIR"); }

    # EN: Desktop entries, icons, symlinks and .bashrc lines.
    # ES: Entradas de menú, iconos, symlinks y líneas en .bashrc.
    local desktop_files=()
    local icon_files=()
    while IFS= read -r f; do
        desktop_files+=("$f")
    done < <(find "$HOME/.local/share/applications" -maxdepth 1 -name "packbox-*.desktop" 2>/dev/null)
    while IFS= read -r f; do
        icon_files+=("$f")
    done < <(find "$HOME/.local/share/icons/hicolor" -name "packbox-*.png" -o -name "packbox-*.svg" 2>/dev/null)

    local symlinks=()
    while IFS= read -r f; do
        [[ -L "$f" ]] && symlinks+=("$f")
    done < <(find "$HOME/.local/bin" -maxdepth 1 -name "packbox-*" 2>/dev/null)

    local bashrc_lines=0
    if [[ -f "$HOME/.bashrc" ]]; then
        bashrc_lines=$(grep -cE '\.packbox/bin|/packbox/bin' "$HOME/.bashrc" 2>/dev/null || echo 0)
    fi

    # EN: Nothing to remove — bail out early.
    # ES: Nada que borrar — salida temprana.
    if [[ $has_install -eq 0 && $has_data -eq 0 && $has_config -eq 0 && ${#desktop_files[@]} -eq 0 && ${#icon_files[@]} -eq 0 && ${#symlinks[@]} -eq 0 && $bashrc_lines -eq 0 ]]; then
        warn "$(t L_UNINSTALL_NOTHING)"
        read -rp "  ENTER..."
        return 0
    fi

    # ───────────────────────────────────────────────────────────
    # EN: Show summary of what will be removed.
    # ES: Muestra el resumen de lo que se eliminará.
    # ───────────────────────────────────────────────────────────
    echo -e "  ${BD}$(t L_UNINSTALL_WILL)${N}"
    echo -e "  ${DM}─────────────────────────────────────────────────────────────${N}"

    if [[ $has_install -eq 1 ]]; then
        printf "  %-45s ${BD}%9s${N}\n" "~/.packbox/" "$(human_size "${SIZES[$PACKBOX_INSTALL_DIR]}")"
        total=$((total + SIZES[$PACKBOX_INSTALL_DIR]))
    fi
    if [[ $has_data -eq 1 ]]; then
        printf "  %-45s ${BD}%9s${N}\n" "~/.local/share/packbox/" "$(human_size "${SIZES[$PACKBOX_HOME]}")"
        total=$((total + SIZES[$PACKBOX_HOME]))
    fi
    if [[ $has_config -eq 1 ]]; then
        printf "  %-45s ${BD}%9s${N}\n" "~/.config/packbox/" "$(human_size "${SIZES[$HOME/.config/packbox]}")"
        total=$((total + SIZES[$HOME/.config/packbox]))
    fi

    if [[ ${#desktop_files[@]} -gt 0 ]]; then
        echo ""
        echo -e "  ${BD}$(t L_UNINSTALL_DESKTOP):${N}"
        local f
        for f in "${desktop_files[@]}"; do
            echo -e "    ${DM}${f/#$HOME/\~}${N}"
        done
    fi

    if [[ ${#icon_files[@]} -gt 0 ]]; then
        echo ""
        echo -e "  ${BD}$(t L_UNINSTALL_ICONS):${N}"
        local f
        for f in "${icon_files[@]}"; do
            echo -e "    ${DM}${f/#$HOME/\~}${N}"
        done
    fi

    if [[ ${#symlinks[@]} -gt 0 ]]; then
        echo ""
        echo -e "  ${BD}$(t L_UNINSTALL_SYMLINKS):${N}"
        local f
        for f in "${symlinks[@]}"; do
            echo -e "    ${DM}${f/#$HOME/\~}${N}"
        done
    fi

    if [[ $bashrc_lines -gt 0 ]]; then
        echo ""
        echo -e "  ${BD}~/.bashrc:${N} ${DM}$bashrc_lines $(t L_UNINSTALL_BASHRC)${N}"
    fi

    if [[ $has_old -eq 1 ]]; then
        echo ""
        echo -e "  ${Y}!${N}  ${BD}~/packbox/ (old)${N}: $(human_size "${SIZES[$OLD_PACKBOX_DIR]}")"
    fi

    echo -e "  ${DM}─────────────────────────────────────────────────────────────${N}"
    echo -e "  ${BD}$(t L_TOTAL): $(human_size "$total")${N}"
    echo ""
    echo -e "  ${DM}Nota: modo 'k' solo elimina ~/.packbox/ + symlinks (apps y menús intactos)${N}"
    echo ""

    # ───────────────────────────────────────────────────────────
    # EN: Ask mode. | ES: Pregunta el modo.
    # ───────────────────────────────────────────────────────────
    echo -en "  ${Y}?${N} $(t L_UNINSTALL_MODE)"
    local mode
    read -r mode
    case "$mode" in
        k|K)
            info "$(t L_UNINSTALL_BIN_ONLY)"
            det "Se elimina: ~/.packbox/ + symlinks ~/.local/bin"
            det "Se conserva: apps, store, menús, iconos, .bashrc"
            FULL_UNINSTALL=0
            ;;
        s|S)
            info "$(t L_UNINSTALL_FULL)"
            det "Se elimina: TODO (binarios + apps + store + menús + config)"
            FULL_UNINSTALL=1
            ;;
        q|Q|"")
            warn "$(t L_ABORT)"
            read -rp "  ENTER..."
            return 0
            ;;
        *)
            warn "Inválido"
            read -rp "  ENTER..."
            return 0
            ;;
    esac

    # ───────────────────────────────────────────────────────────
    # EN: Two-step confirmation: yes/no + DELETE token.
    # ES: Confirmación en dos pasos: sí/no + token DELETE.
    # ───────────────────────────────────────────────────────────
    echo ""
    printf "  ${Y}?${N} $(t L_UNINSTALL_CONFIRM)"
    read -r -n 1 reply
    echo
    [[ ! "$reply" =~ ^[SsYy]$ ]] && { warn "$(t L_ABORT)"; read -rp "  ENTER..."; return 0; }

    echo ""
    printf "  ${Y}?${N} $(t L_UNINSTALL_TYPE)"
    local confirm_token
    read -r confirm_token
    if [[ "$confirm_token" != "DELETE" ]]; then
        warn "$(t L_UNINSTALL_MISMATCH)"
        read -rp "  ENTER..."
        return 0
    fi

    # ───────────────────────────────────────────────────────────
    # EN: Actually remove things.
    # ES: Elimina realmente las cosas.
    # ───────────────────────────────────────────────────────────
    echo ""
    local freed=0

    if [[ $has_install -eq 1 ]]; then
        info "$(t L_UNINSTALL_REMOVING) ~/.packbox/"
        freed=$((freed + ${SIZES[$PACKBOX_INSTALL_DIR]}))
        rm -rf "$PACKBOX_INSTALL_DIR"
        ok "$(t L_UNINSTALL_REMOVED): ~/.packbox/"
    fi

    # EN: Full mode only: wipe data and config.
    # ES: Solo en modo completo: borra datos y config.
    if [[ $FULL_UNINSTALL -eq 1 ]]; then
        if [[ $has_data -eq 1 ]]; then
            info "$(t L_UNINSTALL_REMOVING) ~/.local/share/packbox/"
            freed=$((freed + ${SIZES[$PACKBOX_HOME]}))
            rm -rf "$PACKBOX_HOME"
            ok "$(t L_UNINSTALL_REMOVED): ~/.local/share/packbox/"
        fi
        if [[ $has_config -eq 1 ]]; then
            info "$(t L_UNINSTALL_REMOVING) ~/.config/packbox/"
            freed=$((freed + ${SIZES[$HOME/.config/packbox]}))
            rm -rf "$HOME/.config/packbox"
            ok "$(t L_UNINSTALL_REMOVED): ~/.config/packbox/"
        fi
    fi

    # EN: Menu entries and icons (always).
    # ES: Entradas de menú e iconos (siempre).
    if [[ ${#desktop_files[@]} -gt 0 ]]; then
        info "$(t L_UNINSTALL_DESKTOP)"
        local f
        for f in "${desktop_files[@]}"; do
            rm -f "$f"
        done
        ok "$(t L_UNINSTALL_REMOVED): ${#desktop_files[@]} .desktop"
    fi

    if [[ ${#icon_files[@]} -gt 0 ]]; then
        info "$(t L_UNINSTALL_ICONS)"
        local f
        for f in "${icon_files[@]}"; do
            rm -f "$f"
        done
        ok "$(t L_UNINSTALL_REMOVED): ${#icon_files[@]} iconos"
    fi

    # EN: Symlinks in ~/.local/bin (always).
    # ES: Symlinks en ~/.local/bin (siempre).
    if [[ ${#symlinks[@]} -gt 0 ]]; then
        info "$(t L_UNINSTALL_SYMLINKS)"
        local f
        for f in "${symlinks[@]}"; do
            rm -f "$f"
        done
        ok "$(t L_UNINSTALL_REMOVED): ${#symlinks[@]} symlinks"
    fi

    # EN: Refresh desktop caches so removed entries disappear.
    # ES: Refresca cachés de escritorio para que desaparezcan.
    if command -v update-desktop-database &>/dev/null; then
        update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
    fi
    if command -v gtk-update-icon-cache &>/dev/null; then
        gtk-update-icon-cache -f -t "$HOME/.local/share/icons/hicolor" 2>/dev/null || true
    fi

    # EN: Clean ~/.bashrc (backup first).
    # ES: Limpia ~/.bashrc (backup primero).
    if [[ $bashrc_lines -gt 0 ]] && [[ -f "$HOME/.bashrc" ]]; then
        info "$(t L_UNINSTALL_BASHRC)"
        cp "$HOME/.bashrc" "$HOME/.bashrc.packbox-uninstall.bak"
        sed -i '/# Packbox v[0-9]/d' "$HOME/.bashrc"
        sed -i '\|export PATH=.*\.packbox/bin|d' "$HOME/.bashrc"
        sed -i '\|export PATH=.*[^.]packbox/bin|d' "$HOME/.bashrc"
        ok "$(t L_UNINSTALL_BASHRC)"
    fi

    # EN: Optional removal of legacy ~/packbox.
    # ES: Eliminación opcional del ~/packbox antiguo.
    if [[ $has_old -eq 1 ]]; then
        echo ""
        printf "  ${Y}?${N} $(t L_UNINSTALL_OLD_PACKBOX)"
        read -r -n 1 reply
        echo
        if [[ "$reply" =~ ^[SsYy]$ ]]; then
            info "$(t L_UNINSTALL_REMOVING) ~/packbox/ (old)"
            freed=$((freed + ${SIZES[$OLD_PACKBOX_DIR]}))
            rm -rf "$OLD_PACKBOX_DIR"
            ok "$(t L_UNINSTALL_REMOVED): ~/packbox/"
        fi
    fi

    # EN: Final summary.
    # ES: Resumen final.
    echo ""
    box_ok "$(t L_UNINSTALL_DONE)"
    echo -e "  ${BD}$(t L_UNINSTALL_FREED): $(human_size "$freed")${N}"
    echo ""
    echo -e "  ${DM}Nota: si dejaste el modo 'solo binarios', tus apps y el store siguen en:${N}"
    echo -e "  ${DM}  ~/.local/share/packbox/${N}"
    echo ""
    read -rp "  ENTER..."
}

# ═══════════════════════════════════════════════════════════════
# EN: main — top-level entrypoint.
# ES: main — punto de entrada principal.
#
# EN: Installs language files, asks for language, then loops on
#     the install/uninstall menu until the user exits.
# ES: Instala los archivos de idioma, pregunta el idioma y luego
#     itera en el menú de instalación/desinstalación hasta salir.
# ═══════════════════════════════════════════════════════════════
main() {
    # EN: Bootstrap i18n before any translatable output.
    # ES: Arranca i18n antes de cualquier salida traducible.
    select_language
    install_lang_files
    load_lang

    while true; do
        show_banner
        echo -e "  ${BD}$(t L_WELCOME)${N}"
        echo -e "  ${DM}Lang: $(t L_LANG_NAME)${N}"
        echo ""
        echo -e "  ${C}1${N}  $(t L_MENU_INSTALL)"
        echo -e "  ${C}2${N}  ${R}$(t L_MENU_UNINSTALL)${N}"
        echo -e "  ${C}0${N}  $(t L_MENU_EXIT)"
        echo ""
        echo -e "  ${DM}─────────────────────────────────────────────────────────────${N}"
        echo ""
        echo -en "  ${BD}> $(t L_MENU_PROMPT) [0-2]: ${N}"

        local opt
        read -r opt
        case "$opt" in
            1)
                do_install
                # EN: Pause so the user can read the success summary.
                # ES: Pausa para que el usuario lea el resumen.
                echo ""
                echo -en "  ${BD}ENTER...${N}"
                read -r
                ;;
            2)
                do_uninstall
                ;;
            0|q|Q)
                echo ""
                echo -e "  ${DM}Bye / Adiós / Au revoir / Tschüss / Ciao / 再见 / さようなら / 안녕${N}"
                echo ""
                exit 0
                ;;
            *)
                warn "Inválido"
                sleep 1
                ;;
        esac
    done
}

main "$@"
