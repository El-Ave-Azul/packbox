// Tests for D-Bus filtering (xdg-dbus-proxy).
// Tests para el filtrado de D-Bus (xdg-dbus-proxy).
package sandbox

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestDBusProxyArgs(t *testing.T) {
	got := dbusProxyArgs("unix:path=/run/user/1000/bus", "/tmp/x/bus",
		busPolicy{Talk: []string{"org.freedesktop.portal.*", "ca.desrt.dconf"}})

	// Proxy options come after the address and socket path.
	if len(got) < 4 || got[0] != "unix:path=/run/user/1000/bus" || got[1] != "/tmp/x/bus" {
		t.Fatalf("argv must start with address and socket: %v", got)
	}
	joined := strings.Join(got, " ")
	for _, want := range []string{
		"--filter",
		"--talk=org.freedesktop.portal.*",
		"--talk=ca.desrt.dconf",
	} {
		if !strings.Contains(joined, want) {
			t.Fatalf("argv missing %q: %v", want, got)
		}
	}
}

func TestDefaultBusPolicies(t *testing.T) {
	s := &Sandbox{}
	sp := s.sessionPolicy()
	hasPortal := false
	for _, n := range sp.Talk {
		if strings.Contains(n, "portal") {
			hasPortal = true
		}
	}
	if !hasPortal {
		t.Fatalf("default session policy should allow portals: %v", sp.Talk)
	}
	if len(s.systemPolicy().Talk) != 0 {
		t.Fatalf("default system policy should allow nothing: %v", s.systemPolicy().Talk)
	}

	// An explicit empty-but-non-nil policy means "nothing", not the default.
	// Una política vacía pero no-nil significa "nada", no el default.
	s.AllowSessionTalk = []string{}
	if len(s.sessionPolicy().Talk) != 0 {
		t.Fatalf("explicit empty session policy ignored: %v", s.sessionPolicy().Talk)
	}
}

func TestSandboxFilteredBus(t *testing.T) {
	appDir := t.TempDir()
	sb := NewSandbox(appDir, "/app/bin/x", nil)
	sb.HostHome = t.TempDir()
	sb.sessionProxy = "/run/user/1000/packbox-dbus-abc/bus"
	sb.systemProxy = "/run/packbox-dbus-def/system"

	args, cleanup, err := sb.bwrapArgs()
	if err != nil {
		t.Fatal(err)
	}
	defer cleanup()

	if !hasTriple(args, "--ro-bind", sb.sessionProxy, sb.sessionProxy) {
		t.Fatalf("session proxy socket not bound")
	}
	if !hasTriple(args, "--setenv", "DBUS_SESSION_BUS_ADDRESS", "unix:path="+sb.sessionProxy) {
		t.Fatalf("DBUS_SESSION_BUS_ADDRESS not pointed at the proxy")
	}
	if !hasTriple(args, "--setenv", "DBUS_SYSTEM_BUS_ADDRESS", "unix:path="+sb.systemProxy) {
		t.Fatalf("DBUS_SYSTEM_BUS_ADDRESS not pointed at the proxy")
	}

	// The real session bus must not be bound when the proxy is used.
	if rd := os.Getenv("XDG_RUNTIME_DIR"); rd != "" {
		real := filepath.Join(rd, "bus")
		for _, a := range args {
			if a == real {
				t.Fatalf("real session bus bound despite the proxy: %s", a)
			}
		}
	}
}
