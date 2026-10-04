// Tests for the sandbox environment (PATH).
// Tests del entorno del sandbox (PATH).
package sandbox

import (
	"strings"
	"testing"
)

func TestPathIncludesAppBin(t *testing.T) {
	sb := NewSandbox(t.TempDir(), "/app/bin/x", nil)
	sb.HostHome = t.TempDir()
	args, cleanup, err := sb.bwrapArgs()
	if err != nil {
		t.Fatal(err)
	}
	defer cleanup()

	path := ""
	for i := 0; i+2 < len(args); i++ {
		if args[i] == "--setenv" && args[i+1] == "PATH" {
			path = args[i+2]
			break
		}
	}
	// Flatpak puts /app/bin on PATH; an app's internal wrapper does
	// `exec <bin>` with no path and relied on that.
	// Flatpak pone /app/bin en el PATH; el wrapper interno de una app hace
	// `exec <bin>` sin ruta y contaba con eso.
	if !strings.Contains(path, "/app/bin") {
		t.Fatalf("sandbox PATH should include /app/bin: %q", path)
	}
}
