// Tests for the portal / X11 opt-in.
// Tests para el opt-in de portales / X11.
package sandbox

import (
	"os"
	"path/filepath"
	"testing"
)

func TestX11OptIn(t *testing.T) {
	appDir := t.TempDir()
	// Force a Wayland session so autodetection is deterministic.
	t.Setenv("WAYLAND_DISPLAY", "wayland-0")
	t.Setenv("DISPLAY", ":0")

	// X11 off (default on Wayland): no X11 socket.
	sb := NewSandbox(appDir, "/app/bin/x", nil)
	sb.HostHome = t.TempDir()
	args, cleanup, err := sb.bwrapArgs()
	if err != nil {
		t.Fatal(err)
	}
	cleanup()
	for _, a := range args {
		if a == "/tmp/.X11-unix" {
			t.Fatalf("X11 socket bound without opt-in: %v", args)
		}
	}

	// X11 on: the socket is exposed when it exists on the host.
	sb2 := NewSandbox(appDir, "/app/bin/x", nil)
	sb2.HostHome = t.TempDir()
	sb2.X11 = true
	args2, cleanup2, err := sb2.bwrapArgs()
	if err != nil {
		t.Fatal(err)
	}
	defer cleanup2()
	if _, err := os.Stat("/tmp/.X11-unix"); err == nil {
		if !hasTriple(args2, "--ro-bind", "/tmp/.X11-unix", "/tmp/.X11-unix") {
			t.Fatalf("X11 socket not bound despite opt-in: %v", args2)
		}
	}
}

func TestPortalDocumentMount(t *testing.T) {
	rd := t.TempDir()
	doc := filepath.Join(rd, "doc")
	if err := os.MkdirAll(doc, 0755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("XDG_RUNTIME_DIR", rd)

	sb := NewSandbox(t.TempDir(), "/app/bin/x", nil)
	sb.HostHome = t.TempDir()
	args, cleanup, err := sb.bwrapArgs()
	if err != nil {
		t.Fatal(err)
	}
	defer cleanup()

	if !hasTriple(args, "--ro-bind", doc, doc) {
		t.Fatalf("portal document mount not bound: %v", args)
	}
}
