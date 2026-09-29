// Tests for the extra read-only binds (an app bundle under /opt).
// Tests para los binds extra de solo lectura (un bundle de la app en /opt).
package sandbox

import "testing"

func TestROBinds(t *testing.T) {
	dir := t.TempDir()
	sb := NewSandbox(t.TempDir(), "/app/bin/x", nil)
	sb.HostHome = t.TempDir()
	sb.ROBinds = []string{dir, "/nonexistent-packbox-xyz"}

	args, cleanup, err := sb.bwrapArgs()
	if err != nil {
		t.Fatal(err)
	}
	defer cleanup()

	if !hasTriple(args, "--ro-bind-try", dir, dir) {
		t.Fatalf("ROBinds dir not bound read-only: %v", args)
	}
	for _, a := range args {
		if a == "/nonexistent-packbox-xyz" {
			t.Fatal("a non-existent RO bind was added")
		}
	}
}
