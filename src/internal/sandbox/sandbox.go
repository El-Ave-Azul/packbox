// Package sandbox runs apps under bubblewrap with a restrictive policy.
// El paquete sandbox ejecuta apps bajo bubblewrap con política restrictiva.
package sandbox

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"sync"

	"github.com/packbox/packbox/internal/libpath"
)

// OverlaySupported reports whether bubblewrap supports --overlay (checked once
// per process). Older bubblewrap (< 0.8) does not, and then /app is a plain
// read-only bind and the cells must be materialized into the tree at install.
// OverlaySupported indica si bubblewrap soporta --overlay (se comprueba una vez
// por proceso). El bubblewrap antiguo (< 0.8) no lo hace, y entonces /app es un
// bind de solo lectura y las celdas deben materializarse en el árbol al instalar.
var OverlaySupported = sync.OnceValue(func() bool {
	out, err := exec.Command("bwrap", "--help").Output()
	if err != nil {
		return false
	}
	return strings.Contains(string(out), "--overlay-src")
})

// Sandbox holds the parameters for a single run.
// Sandbox contiene los parámetros para una ejecución.
type Sandbox struct {
	AppDir       string
	Entrypoint   string
	Args         []string
	IsGUI        bool
	Network      bool
	DelegateLibs []string
	// Layers are directories layed UNDER the app tree at /app (overlay lower
	// layers, lowest first): the app tree (A) sits on top of them (C, e.g.
	// cells). The host (S) provides libs via /usr.
	// Layers son directorios por DEBAJO del árbol de la app en /app (capas
	// inferiores del overlay, la más baja primero): el árbol (A) queda encima de
	// ellas (C, p. ej. celdas). El host (S) aporta libs vía /usr.
	Layers []string

	// X11 opts the app into the X11 socket (and DISPLAY/xauth). Off by default:
	// GUI apps are expected to use Wayland and xdg-desktop-portal.
	// X11 habilita el socket X11 (y DISPLAY/xauth) para la app. Por defecto no:
	// se espera que las apps GUI usen Wayland y xdg-desktop-portal.
	X11 bool
	// Home is the app's private HOME: bound read-write and set as $HOME, so
	// each app gets its own data instead of touching the host user's.
	// Home es el HOME privado de la app: bindeado rw y usado como $HOME, así
	// cada app tiene sus propios datos en vez de tocar los del usuario.
	Home string
	// HostHome is the host user's home, used only as a source of read-only
	// font/theme assets (defaults to $HOME).
	// HostHome es el home del usuario del host, usado solo como origen de
	// assets de fuentes/temas de solo lectura (por defecto $HOME).
	HostHome string

	// D-Bus filtering (xdg-dbus-proxy). When available, the app talks to a
	// filtered proxy instead of the real bus. AllowSessionTalk/AllowSystemTalk
	// are the service names the app may talk to (nil = safe default);
	// NoDBusProxy disables filtering (binds the real sockets).
	// Filtrado de D-Bus (xdg-dbus-proxy). Si está disponible, la app habla con
	// un proxy filtrado en vez del bus real. AllowSessionTalk/AllowSystemTalk
	// son los nombres a los que puede hablar (nil = default seguro);
	// NoDBusProxy desactiva el filtrado (bindea los sockets reales).
	AllowSessionTalk []string
	AllowSystemTalk  []string
	NoDBusProxy      bool

	// sessionProxy/systemProxy are the sandbox-visible proxy socket paths, set
	// by Run before bwrapArgs.
	// sessionProxy/systemProxy son las rutas de socket del proxy visibles en el
	// sandbox, fijadas por Run antes de bwrapArgs.
	sessionProxy string
	systemProxy  string

	// Seccomp: a default filter blocks dangerous syscalls (EPERM). NoSeccomp
	// disables it. seccompFD is the fd bwrap reads the filter from, set by Run.
	// Seccomp: un filtro por defecto bloquea syscalls peligrosos (EPERM).
	// NoSeccomp lo desactiva. seccompFD es el fd del que bwrap lee el filtro.
	NoSeccomp bool
	seccompFD int
}

// NewSandbox creates a sandbox with default options.
// NewSandbox crea un sandbox con opciones por defecto.
func NewSandbox(appDir, entrypoint string, args []string) *Sandbox {
	return &Sandbox{
		AppDir:     appDir,
		Entrypoint: entrypoint,
		Args:       args,
		Home:       filepath.Join(appDir, "home"),
		HostHome:   os.Getenv("HOME"),
	}
}

// Run executes the entrypoint inside bubblewrap.
// Run ejecuta el entrypoint dentro de bubblewrap.
func (s *Sandbox) Run() error {
	// Start filtered D-Bus proxies (if xdg-dbus-proxy is available).
	// Arranca los proxies D-Bus filtrados (si xdg-dbus-proxy está disponible).
	var proxies []*dbusProxy
	if !s.NoDBusProxy {
		if bus := sessionBusAddress(); bus != "" {
			if p, err := startDBusProxy(bus, s.sessionPolicy()); err == nil {
				proxies = append(proxies, p)
				s.sessionProxy = p.path
			}
		}
		if _, err := os.Stat("/run/dbus/system_bus_socket"); err == nil {
			if p, err := startDBusProxy("unix:path=/run/dbus/system_bus_socket", s.systemPolicy()); err == nil {
				proxies = append(proxies, p)
				s.systemProxy = p.path
			}
		}
	}
	defer func() {
		for _, p := range proxies {
			p.close()
		}
	}()

	// Seccomp: write the default filter to a temp file and hand its fd to bwrap.
	// Seccomp: escribe el filtro por defecto a un temporal y pasa su fd a bwrap.
	var secFile *os.File
	if !s.NoSeccomp {
		if data := seccompBytes(buildSeccompFilter(defaultBlockedSyscalls())); len(data) > 0 {
			if f, err := os.CreateTemp("", "packbox-seccomp-"); err == nil {
				if _, werr := f.Write(data); werr == nil {
					_, _ = f.Seek(0, 0)
					secFile = f
					s.seccompFD = 3 // ExtraFiles[0] -> fd 3
				} else {
					f.Close()
					os.Remove(f.Name())
				}
			}
		}
	}
	defer func() {
		if secFile != nil {
			name := secFile.Name()
			secFile.Close()
			os.Remove(name)
		}
	}()

	args, cleanup, err := s.bwrapArgs()
	if err != nil {
		return err
	}
	defer cleanup()
	bwrap, err := exec.LookPath("bwrap")
	if err != nil {
		return fmt.Errorf("bubblewrap not found: %w", err)
	}
	cmd := exec.Command(bwrap, args...)
	if secFile != nil {
		cmd.ExtraFiles = []*os.File{secFile}
	}
	cmd.Stdin = os.Stdin
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	return cmd.Run()
}

// bwrapArgs builds the bubblewrap argument list. The returned cleanup frees the
// temporary files (xauth).
// bwrapArgs construye la lista de argumentos de bubblewrap. El cleanup devuelto
// libera los temporales (xauth).
func (s *Sandbox) bwrapArgs() ([]string, func(), error) {
	a := []string{
		"--ro-bind", "/usr", "/usr",
		"--dev", "/dev", "--proc", "/proc",
		"--tmpfs", "/tmp", "--tmpfs", "/run",
		"--unshare-all",
		"--cap-drop", "ALL",
		"--die-with-parent", "--new-session",
		"--clearenv",
		"--setenv", "PATH", "/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin:/sbin",
		"--setenv", "SHELL", "/bin/bash",
		"--setenv", "TERM", "xterm-256color",
	}
	a = append(a, s.appMount()...)

	if s.Network {
		a = append(a, "--share-net")
	}
	for _, d := range []string{"/lib", "/lib64", "/bin", "/sbin", "/var"} {
		if _, err := os.Stat(d); err == nil {
			a = append(a, "--ro-bind", d, d)
		}
	}
	// Selective /etc bind (not the whole directory).
	// Bind selectivo de /etc (no el directorio completo).
	for _, f := range []string{
		"/etc/ld.so.cache", "/etc/ld.so.conf", "/etc/passwd", "/etc/group",
		"/etc/resolv.conf", "/etc/hosts", "/etc/nsswitch.conf",
		"/etc/hostname", "/etc/host.conf", "/etc/gai.conf",
		"/etc/localtime", "/etc/ssl", "/etc/ca-certificates",
		"/etc/pki", "/etc/fonts", "/etc/terminfo",
	} {
		info, err := os.Lstat(f)
		if err != nil {
			continue
		}
		if info.Mode()&os.ModeSymlink != 0 {
			target, err := filepath.EvalSymlinks(f)
			if err == nil && target != f {
				a = append(a, "--ro-bind-try", target, f)
			}
		} else {
			a = append(a, "--ro-bind-try", f, f)
		}
	}
	for _, k := range []string{
		"LANG", "LANGUAGE", "LC_ALL", "LC_MESSAGES", "LC_CTYPE",
		"TZ",
		"XDG_SESSION_TYPE", "XDG_CURRENT_DESKTOP", "XDG_SESSION_DESKTOP",
		"WAYLAND_DISPLAY", "XDG_RUNTIME_DIR",
	} {
		if v := os.Getenv(k); v != "" {
			a = append(a, "--setenv", k, v)
		}
	}

	for _, lib := range s.DelegateLibs {
		lp, err := libpath.Find(lib)
		if err != nil {
			continue
		}
		a = append(a, "--ro-bind", lp, lp)
	}

	// xauth: copy to a temp file, cleaned up by the caller.
	// xauth: copia a un temporal, liberado por el llamador.
	var xauthTmp string
	if s.useX11() {
		if p := s.setupXauth(&a); p != "" {
			xauthTmp = p
		}
	}
	cleanup := func() {
		if xauthTmp != "" {
			os.Remove(xauthTmp)
		}
	}

	s.addGUISupport(&a)
	if s.seccompFD != 0 {
		a = append(a, "--seccomp", strconv.Itoa(s.seccompFD))
	}
	a = append(a, s.Entrypoint)
	a = append(a, s.Args...)
	return a, cleanup, nil
}

// useX11 reports whether to expose X11: the manifest explicitly asked for it,
// or the host session is X11-only (no Wayland available but DISPLAY is set), so
// GUI apps would otherwise have no display. On a Wayland session X11 stays off
// (isolation) unless the manifest opted in.
// useX11 indica si exponer X11: el manifiesto lo pidió, o la sesión del host es
// solo X11 (no hay Wayland pero DISPLAY está definido), donde las apps GUI no
// tendrían display. En una sesión Wayland, X11 queda apagado (aislamiento) salvo
// que el manifiesto lo habilite.
func (s *Sandbox) useX11() bool {
	if s.X11 {
		return true
	}
	return os.Getenv("WAYLAND_DISPLAY") == "" && os.Getenv("DISPLAY") != ""
}

// appMount returns the /app mount: a layered overlay (A over C) when the app
// has lower layers, else a plain read-only bind. In bwrap later --overlay-src
// entries sit on top, so the app tree (A) is added last.
// appMount devuelve el montaje de /app: un overlay por capas (A sobre C) cuando
// la app tiene capas inferiores, si no un bind de solo lectura. En bwrap los
// --overlay-src posteriores quedan encima, así que el árbol (A) va al final.
func (s *Sandbox) appMount() []string {
	tree := filepath.Join(s.AppDir, "tree")
	// Without layers, or with a bubblewrap too old for --overlay, bind the tree
	// directly. In the latter case install materialized the cells into it.
	// Sin capas, o con un bubblewrap sin --overlay, bindea el árbol directamente.
	// En ese último caso el instalador materializó las celdas dentro.
	if len(s.Layers) == 0 || !OverlaySupported() {
		return []string{"--ro-bind", tree, "/app"}
	}
	var a []string
	for _, l := range s.Layers {
		a = append(a, "--overlay-src", l)
	}
	a = append(a, "--overlay-src", tree, "--ro-overlay", "/app")
	return a
}

// setupXauth copies Xauthority to a temp file inside bwrap.
// setupXauth copia Xauthority a un temporal dentro de bwrap.
func (s *Sandbox) setupXauth(args *[]string) string {
	homeDir := s.HostHome
	var origXauth string
	if env := os.Getenv("XAUTHORITY"); env != "" {
		if _, err := os.Stat(env); err == nil {
			origXauth = env
		}
	}
	if origXauth == "" && homeDir != "" {
		c := filepath.Join(homeDir, ".Xauthority")
		if _, err := os.Stat(c); err == nil {
			origXauth = c
		}
	}
	if origXauth == "" {
		return ""
	}
	data, err := os.ReadFile(origXauth)
	if err != nil {
		return ""
	}
	tmpFile, err := os.CreateTemp("", "packbox-xauth-*")
	if err != nil {
		return ""
	}
	name := tmpFile.Name()
	if _, err := tmpFile.Write(data); err != nil {
		tmpFile.Close()
		os.Remove(name)
		return ""
	}
	tmpFile.Close()
	os.Chmod(name, 0600)
	dst := "/tmp/packbox-xauth"
	*args = append(*args, "--ro-bind", name, dst)
	*args = append(*args, "--setenv", "XAUTHORITY", dst)
	return name
}

// homeLayer binds the app's private home as $HOME and exposes the host user's
// read-only font/theme assets inside it. It never binds host configuration
// read-write, so a sandboxed app cannot touch the user's real profile.
// homeLayer bindea el HOME privado de la app como $HOME y expone dentro los
// assets de fuentes/temas de solo lectura del usuario. Nunca bindea la
// configuración del host en rw, así la app no puede tocar el perfil real.
func (s *Sandbox) homeLayer() []string {
	var a []string
	home := s.Home
	if home == "" {
		return a
	}
	_ = os.MkdirAll(home, 0700)
	a = append(a, "--bind", home, home)
	a = append(a, "--setenv", "HOME", home)

	if s.HostHome == "" {
		return a
	}
	for _, d := range []string{
		".local/share/fonts", ".fonts", ".themes", ".icons",
		".local/share/themes", ".local/share/icons",
	} {
		src := filepath.Join(s.HostHome, d)
		if _, err := os.Stat(src); err != nil {
			continue
		}
		dst := filepath.Join(home, d)
		_ = os.MkdirAll(filepath.Dir(dst), 0755)
		a = append(a, "--ro-bind", src, dst)
	}
	return a
}

// addGUISupport binds the minimum needed for GUI apps.
// addGUISupport enlaza lo mínimo para apps GUI.
func (s *Sandbox) addGUISupport(args *[]string) {
	if h, err := os.Hostname(); err == nil {
		*args = append(*args, "--hostname", h)
	}

	// X11 is opt-in (Wayland + portals by default); with it on, the socket and
	// DISPLAY/xauth are exposed (no isolation between X11 clients).
	// X11 es opt-in (Wayland + portales por defecto); con él, se exponen el
	// socket y DISPLAY/xauth (sin aislamiento entre clientes X11).
	if s.useX11() {
		if _, err := os.Stat("/tmp/.X11-unix"); err == nil {
			*args = append(*args, "--ro-bind", "/tmp/.X11-unix", "/tmp/.X11-unix")
		}
		if d := os.Getenv("DISPLAY"); d != "" {
			*args = append(*args, "--setenv", "DISPLAY", d)
		}
	}

	if _, err := os.Stat("/dev/dri"); err == nil {
		*args = append(*args, "--dev-bind", "/dev/dri", "/dev/dri")
	}
	if _, err := os.Stat("/dev/shm"); err == nil {
		*args = append(*args, "--dev-bind", "/dev/shm", "/dev/shm")
	} else {
		*args = append(*args, "--tmpfs", "/dev/shm")
	}

	if wd := os.Getenv("WAYLAND_DISPLAY"); wd != "" {
		*args = append(*args, "--setenv", "WAYLAND_DISPLAY", wd)
		if rd := os.Getenv("XDG_RUNTIME_DIR"); rd != "" {
			sp := filepath.Join(rd, wd)
			if _, err := os.Stat(sp); err == nil {
				*args = append(*args, "--ro-bind", sp, sp)
			}
		}
	}

	if rd := os.Getenv("XDG_RUNTIME_DIR"); rd != "" {
		*args = append(*args, "--setenv", "XDG_RUNTIME_DIR", rd)
		// "doc" is the xdg-desktop-portal document mount: files the user grants
		// through the portal become readable there.
		// "doc" es el montaje de documentos de xdg-desktop-portal: los archivos
		// que el usuario concede por el portal se leen ahí.
		for _, s := range []string{"pulse", "pipewire-0", "pipewire-0-manager", "doc"} {
			p := filepath.Join(rd, s)
			if _, err := os.Stat(p); err == nil {
				*args = append(*args, "--ro-bind", p, p)
			}
		}
	}
	// D-Bus: filtered proxy if available, else the real sockets.
	// D-Bus: proxy filtrado si está disponible, si no los sockets reales.
	if s.sessionProxy != "" {
		*args = append(*args, "--ro-bind", s.sessionProxy, s.sessionProxy)
		*args = append(*args, "--setenv", "DBUS_SESSION_BUS_ADDRESS", "unix:path="+s.sessionProxy)
	} else if rd := os.Getenv("XDG_RUNTIME_DIR"); rd != "" {
		bp := filepath.Join(rd, "bus")
		if _, err := os.Stat(bp); err == nil {
			*args = append(*args, "--ro-bind", bp, bp)
			*args = append(*args, "--setenv", "DBUS_SESSION_BUS_ADDRESS", "unix:path="+bp)
		}
	}
	if s.systemProxy != "" {
		*args = append(*args, "--ro-bind", s.systemProxy, s.systemProxy)
		*args = append(*args, "--setenv", "DBUS_SYSTEM_BUS_ADDRESS", "unix:path="+s.systemProxy)
	} else if _, err := os.Stat("/run/dbus/system_bus_socket"); err == nil {
		*args = append(*args, "--ro-bind", "/run/dbus/system_bus_socket", "/run/dbus/system_bus_socket")
	}

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

	// Per-app HOME (private data). Replaces binding the host's real configs.
	// HOME privado por app (datos propios). Sustituye el bind de configs reales.
	*args = append(*args, s.homeLayer()...)

	if hh := s.HostHome; hh != "" && strings.HasPrefix(hh, "/home/") {
		parts := strings.Split(strings.TrimPrefix(hh, "/"), "/")
		if len(parts) >= 2 {
			*args = append(*args, "--dir", "/home")
			*args = append(*args, "--dir", "/home/"+parts[1])
		}
	}
	if hh := s.HostHome; hh != "" && strings.HasPrefix(hh, "/root") {
		*args = append(*args, "--dir", "/root")
	}

	if u := os.Getenv("USER"); u != "" {
		*args = append(*args, "--setenv", "USER", u)
	}
}
