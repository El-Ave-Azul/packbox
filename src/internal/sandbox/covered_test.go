// Tests that delegate libs already visible via a dir bind are not re-mounted.
// Tests de que las libs delegadas ya visibles por un bind de dir no se montan.
package sandbox

import (
	"strings"
	"testing"
)

func TestDelegateLibsSkipCovered(t *testing.T) {
	sb := NewSandbox(t.TempDir(), "/app/bin/x", nil)
	sb.HostHome = t.TempDir()
	sb.DelegateLibs = []string{"libz.so.1", "libc.so.6", "libm.so.6"}

	args, cleanup, err := sb.bwrapArgs()
	if err != nil {
		t.Fatal(err)
	}
	defer cleanup()

	for i := 0; i+2 < len(args); i++ {
		if args[i] != "--ro-bind" && args[i] != "--ro-bind-try" {
			continue
		}
		dst := args[i+2]
		if dst == "/usr" || dst == "/lib" || dst == "/lib64" {
			continue
		}
		for _, p := range []string{"/usr/", "/lib/", "/lib64/"} {
			if strings.HasPrefix(dst, p) {
				t.Fatalf("delegate lib re-mounted though already visible: %s", dst)
			}
		}
	}
}

func TestCoveredByDirBind(t *testing.T) {
	if !coveredByDirBind("/usr/lib/libz.so.1") {
		t.Fatal("/usr/lib should be covered")
	}
	if !coveredByDirBind("/lib64/libz.so.1") {
		t.Fatal("/lib64 should be covered")
	}
	if coveredByDirBind("/opt/app/lib/libx.so") {
		t.Fatal("/opt is not covered")
	}
}
