// Tests for the Wayland/X11 session autodetection.
// Tests para la autodetección de sesión Wayland/X11.
package sandbox

import "testing"

func TestUseX11Autodetect(t *testing.T) {
	sb := NewSandbox(t.TempDir(), "/app/bin/x", nil)

	// Wayland session -> X11 off by default.
	t.Setenv("WAYLAND_DISPLAY", "wayland-0")
	t.Setenv("DISPLAY", ":0")
	if sb.useX11() {
		t.Fatal("a Wayland session must not expose X11 by default")
	}

	// X11-only session (no Wayland, DISPLAY set) -> X11 on.
	t.Setenv("WAYLAND_DISPLAY", "")
	t.Setenv("DISPLAY", ":0")
	if !sb.useX11() {
		t.Fatal("an X11-only session must expose X11")
	}

	// Headless (neither) -> X11 off.
	t.Setenv("WAYLAND_DISPLAY", "")
	t.Setenv("DISPLAY", "")
	if sb.useX11() {
		t.Fatal("a headless host must not expose X11")
	}

	// Explicit manifest opt-in wins even on Wayland.
	sb.X11 = true
	t.Setenv("WAYLAND_DISPLAY", "wayland-0")
	t.Setenv("DISPLAY", "")
	if !sb.useX11() {
		t.Fatal("an explicit X11 opt-in must win")
	}
}
