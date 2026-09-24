// D-Bus filtering via xdg-dbus-proxy.
// Filtrado de D-Bus mediante xdg-dbus-proxy.
package sandbox

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"time"
)

// busPolicy describes what an app may do on a bus.
// busPolicy describe qué puede hacer una app en un bus.
type busPolicy struct {
	Talk []string // service names the app may talk to (globs allowed)
	Own  []string // names the app may own
	See  []string // names the app may see (valid D-Bus names only)
}

// dbusProxyArgs builds the xdg-dbus-proxy argv for a policy. Note that proxy
// options go AFTER the address and socket path.
// dbusProxyArgs construye el argv de xdg-dbus-proxy para una política. Ojo:
// las opciones del proxy van DESPUÉS de la dirección y la ruta del socket.
func dbusProxyArgs(realAddress, socketPath string, p busPolicy) []string {
	a := []string{realAddress, socketPath, "--filter"}
	for _, n := range p.Talk {
		a = append(a, "--talk="+n)
	}
	for _, n := range p.Own {
		a = append(a, "--own="+n)
	}
	for _, n := range p.See {
		a = append(a, "--see="+n)
	}
	return a
}

// dbusProxy is a running xdg-dbus-proxy instance.
// dbusProxy es una instancia de xdg-dbus-proxy en ejecución.
type dbusProxy struct {
	cmd  *exec.Cmd
	dir  string // temp dir holding the proxy socket
	path string // the proxy's unix socket path
}

// startDBusProxy starts a filtered proxy for realAddress. It fails if the proxy
// does not come up (so the caller can fall back).
// startDBusProxy arranca un proxy filtrado para realAddress. Falla si el proxy
// no arranca (para que el llamador pueda caer al bus real).
func startDBusProxy(realAddress string, p busPolicy) (*dbusProxy, error) {
	bin, err := exec.LookPath("xdg-dbus-proxy")
	if err != nil {
		return nil, err
	}
	dir, err := os.MkdirTemp("", "packbox-dbus-")
	if err != nil {
		return nil, err
	}
	sock := filepath.Join(dir, "bus")
	cmd := exec.Command(bin, dbusProxyArgs(realAddress, sock, p)...)
	if err := cmd.Start(); err != nil {
		os.RemoveAll(dir)
		return nil, err
	}
	// Wait (briefly) for the proxy socket to appear.
	// Espera (brevemente) a que aparezca el socket del proxy.
	for i := 0; i < 200; i++ {
		if _, err := os.Stat(sock); err == nil {
			return &dbusProxy{cmd: cmd, dir: dir, path: sock}, nil
		}
		time.Sleep(5 * time.Millisecond)
	}
	_ = cmd.Process.Kill()
	_, _ = cmd.Process.Wait()
	os.RemoveAll(dir)
	return nil, fmt.Errorf("xdg-dbus-proxy did not create %s", sock)
}

// close stops the proxy and removes its socket.
// close detiene el proxy y elimina su socket.
func (p *dbusProxy) close() {
	if p == nil {
		return
	}
	if p.cmd != nil && p.cmd.Process != nil {
		_ = p.cmd.Process.Kill()
		_, _ = p.cmd.Process.Wait()
	}
	_ = os.RemoveAll(p.dir)
}

// sessionBusAddress returns the host session bus address, or "".
// sessionBusAddress devuelve la dirección del bus de sesión del host, o "".
func sessionBusAddress() string {
	if a := os.Getenv("DBUS_SESSION_BUS_ADDRESS"); a != "" {
		return a
	}
	if rd := os.Getenv("XDG_RUNTIME_DIR"); rd != "" {
		p := filepath.Join(rd, "bus")
		if _, err := os.Stat(p); err == nil {
			return "unix:path=" + p
		}
	}
	return ""
}

// sessionPolicy returns the session-bus policy (portals + dconf by default).
// sessionPolicy devuelve la política del bus de sesión (portales + dconf por
// defecto).
func (s *Sandbox) sessionPolicy() busPolicy {
	talk := s.AllowSessionTalk
	if talk == nil {
		talk = []string{
			"org.freedesktop.portal.*",
			"org.freedesktop.DBus",
			"ca.desrt.dconf",
		}
	}
	return busPolicy{Talk: talk}
}

// systemPolicy returns the system-bus policy. By default nothing is allowed; the
// opt-in "system-bus"/"libvirt" capabilities allow libvirt + the bus itself.
// systemPolicy devuelve la política del bus de sistema. Por defecto nada; las
// capacidades opt-in "system-bus"/"libvirt" permiten libvirt + el propio bus.
func (s *Sandbox) systemPolicy() busPolicy {
	talk := s.AllowSystemTalk
	if talk == nil {
		talk = []string{}
		if s.hasCap("system-bus") || s.hasCap("libvirt") {
			talk = append(talk, "org.libvirt", "org.freedesktop.DBus")
		}
	}
	return busPolicy{Talk: talk}
}
