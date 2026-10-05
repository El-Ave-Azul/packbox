// Tests for the host surface exposed to the sandbox.
// Tests de la superficie del host expuesta al sandbox.
package sandbox

import "testing"

func TestHostExposure(t *testing.T) {
	sb := NewSandbox(t.TempDir(), "/app/bin/x", nil)
	sb.HostHome = t.TempDir()
	args, cleanup, err := sb.bwrapArgs()
	if err != nil {
		t.Fatal(err)
	}
	defer cleanup()

	// /var must not be exposed (its package DBs and logs leak system state).
	for i := 0; i+2 < len(args); i++ {
		if args[i] == "--ro-bind" && args[i+1] == "/var" && args[i+2] == "/var" {
			t.Fatal("/var should not be read-only bound")
		}
	}

	// /dev/shm must be a private tmpfs, not the host's shared one.
	tmpfs, devBind := false, false
	for i := 0; i+1 < len(args); i++ {
		if args[i] == "--tmpfs" && args[i+1] == "/dev/shm" {
			tmpfs = true
		}
		if args[i] == "--dev-bind" && args[i+1] == "/dev/shm" {
			devBind = true
		}
	}
	if !tmpfs || devBind {
		t.Fatalf("/dev/shm should be a private tmpfs (tmpfs=%v dev-bind=%v)", tmpfs, devBind)
	}
}
