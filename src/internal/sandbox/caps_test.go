// Tests for the opt-in sandbox capabilities (system-bus/libvirt/kvm).
// Tests para las capacidades opt-in del sandbox (system-bus/libvirt/kvm).
package sandbox

import (
	"os"
	"testing"
)

func TestSystemPolicyCaps(t *testing.T) {
	if p := (&Sandbox{}).systemPolicy(); len(p.Talk) != 0 {
		t.Fatalf("default system policy should be empty: %v", p.Talk)
	}
	for _, cap := range []string{"system-bus", "libvirt"} {
		p := (&Sandbox{Caps: []string{cap}}).systemPolicy()
		found := false
		for _, n := range p.Talk {
			if n == "org.libvirt" {
				found = true
			}
		}
		if !found {
			t.Fatalf("cap %q should allow org.libvirt: %v", cap, p.Talk)
		}
	}
}

func TestCapsBindKvmAndLibvirt(t *testing.T) {
	sb := NewSandbox(t.TempDir(), "/app/bin/x", nil)
	sb.HostHome = t.TempDir()
	sb.Caps = []string{"system-bus", "libvirt", "kvm"}
	args, cleanup, err := sb.bwrapArgs()
	if err != nil {
		t.Fatal(err)
	}
	defer cleanup()

	if _, err := os.Stat("/dev/kvm"); err == nil {
		if !hasTriple(args, "--dev-bind", "/dev/kvm", "/dev/kvm") {
			t.Fatalf("kvm cap did not bind /dev/kvm")
		}
	}
	if _, err := os.Stat("/run/libvirt"); err == nil {
		if !hasTriple(args, "--ro-bind-try", "/run/libvirt", "/run/libvirt") {
			t.Fatalf("libvirt cap did not expose /run/libvirt")
		}
	}

	// Without the caps neither is exposed.
	plain := NewSandbox(t.TempDir(), "/app/bin/x", nil)
	plain.HostHome = t.TempDir()
	a2, c2, err := plain.bwrapArgs()
	if err != nil {
		t.Fatal(err)
	}
	defer c2()
	if hasTriple(a2, "--dev-bind", "/dev/kvm", "/dev/kvm") {
		t.Fatal("kvm bound without the cap")
	}
	if hasTriple(a2, "--ro-bind-try", "/run/libvirt", "/run/libvirt") {
		t.Fatal("libvirt exposed without the cap")
	}
}
