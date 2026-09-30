// Tests that /sys is exposed read-only (system monitors need it).
// Tests de que /sys se expone en solo lectura (los monitores lo necesitan).
package sandbox

import "testing"

func TestSysBindRO(t *testing.T) {
	sb := NewSandbox(t.TempDir(), "/app/bin/x", nil)
	sb.HostHome = t.TempDir()
	args, cleanup, err := sb.bwrapArgs()
	if err != nil {
		t.Fatal(err)
	}
	defer cleanup()
	if !hasTriple(args, "--ro-bind-try", "/sys", "/sys") {
		t.Fatalf("/sys is not bound read-only: %v", args)
	}
}
