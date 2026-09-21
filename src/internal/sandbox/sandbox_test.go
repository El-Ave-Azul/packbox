// Tests for the sandbox home isolation.
// Tests para el aislamiento del HOME del sandbox.
package sandbox

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// hasTriple reports whether a contains the consecutive triple x,y,z.
// hasTriple indica si a contiene la terna consecutiva x,y,z.
func hasTriple(a []string, x, y, z string) bool {
	for i := 0; i+2 < len(a); i++ {
		if a[i] == x && a[i+1] == y && a[i+2] == z {
			return true
		}
	}
	return false
}

func TestPerAppHomeIsolation(t *testing.T) {
	hostHome := t.TempDir()
	// Host config that must NOT be bound (rw) into the sandbox.
	os.MkdirAll(filepath.Join(hostHome, ".mozilla"), 0755)
	os.MkdirAll(filepath.Join(hostHome, ".config", "google-chrome"), 0755)
	// Host asset that SHOULD be exposed read-only.
	os.MkdirAll(filepath.Join(hostHome, ".local", "share", "fonts"), 0755)

	appDir := t.TempDir()
	sb := NewSandbox(appDir, "/app/bin/x", nil)
	sb.HostHome = hostHome
	home := sb.Home // <appDir>/home

	args, cleanup, err := sb.bwrapArgs()
	if err != nil {
		t.Fatal(err)
	}
	defer cleanup()

	// $HOME is the app's private home, bound read-write.
	if !hasTriple(args, "--setenv", "HOME", home) {
		t.Fatalf("HOME not set to the app home %q", home)
	}
	if !hasTriple(args, "--bind", home, home) {
		t.Fatalf("app home not bound rw")
	}
	if hasTriple(args, "--setenv", "HOME", hostHome) {
		t.Fatalf("HOME still points at the host home")
	}
	if _, err := os.Stat(home); err != nil {
		t.Fatalf("app home not created: %v", err)
	}

	// Read-only asset is exposed inside the app home.
	if !hasTriple(args, "--ro-bind",
		filepath.Join(hostHome, ".local", "share", "fonts"),
		filepath.Join(home, ".local", "share", "fonts")) {
		t.Fatalf("font asset not exposed into the app home")
	}

	// No host path is bound read-write (only the app's own home).
	for i := 0; i+2 < len(args); i++ {
		switch args[i] {
		case "--bind", "--bind-try", "--dev-bind":
			src := args[i+1]
			if src == home {
				continue
			}
			if src == hostHome || strings.HasPrefix(src, hostHome+string(os.PathSeparator)) {
				t.Fatalf("host path bound rw: %s %s %s", args[i], src, args[i+2])
			}
		}
	}

	// The old hard-coded profile map is gone.
	for _, a := range args {
		if strings.Contains(a, ".mozilla") || strings.Contains(a, "google-chrome") {
			t.Fatalf("host profile referenced in sandbox args: %s", a)
		}
	}
}
