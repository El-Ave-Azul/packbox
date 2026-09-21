// Tests for the layered /app overlay.
// Tests para el overlay por capas de /app.
package sandbox

import "testing"

func indexOf(a []string, x, y string) int {
	for i := 0; i+1 < len(a); i++ {
		if a[i] == x && a[i+1] == y {
			return i
		}
	}
	return -1
}

func TestAppMountLayered(t *testing.T) {
	sb := NewSandbox("/apps/demo", "/app/bin/x", nil)
	sb.HostHome = t.TempDir()
	sb.Layers = []string{"/mods/a/1", "/mods/b/2"}

	args, cleanup, err := sb.bwrapArgs()
	if err != nil {
		t.Fatal(err)
	}
	defer cleanup()

	iA := indexOf(args, "--overlay-src", "/mods/a/1")
	iB := indexOf(args, "--overlay-src", "/mods/b/2")
	iTree := indexOf(args, "--overlay-src", "/apps/demo/tree")
	iOv := indexOf(args, "--ro-overlay", "/app")
	if iA < 0 || iB < 0 || iTree < 0 || iOv < 0 {
		t.Fatalf("overlay args missing: %v", args)
	}
	// order: lower layers first, app tree last (on top), then the overlay mount
	if !(iA < iB && iB < iTree && iTree < iOv) {
		t.Fatalf("overlay order wrong: a=%d b=%d tree=%d ov=%d", iA, iB, iTree, iOv)
	}
	// the tree must NOT be bound directly to /app when layering
	if hasTriple(args, "--ro-bind", "/apps/demo/tree", "/app") {
		t.Fatalf("tree bound directly despite layers: %v", args)
	}
}

func TestAppMountPlain(t *testing.T) {
	sb := NewSandbox("/apps/demo", "/app/bin/x", nil)
	sb.HostHome = t.TempDir()

	args, cleanup, err := sb.bwrapArgs()
	if err != nil {
		t.Fatal(err)
	}
	defer cleanup()

	if !hasTriple(args, "--ro-bind", "/apps/demo/tree", "/app") {
		t.Fatalf("expected a plain ro-bind of the tree")
	}
	if indexOf(args, "--ro-overlay", "/app") >= 0 {
		t.Fatalf("unexpected overlay without layers")
	}
}
