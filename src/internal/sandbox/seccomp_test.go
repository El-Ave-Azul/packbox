//go:build linux

// Tests for the seccomp filter.
// Tests para el filtro seccomp.
package sandbox

import "testing"

func TestBuildSeccompFilter(t *testing.T) {
	f := buildSeccompFilter([]uint32{1, 20})
	// LD + 2*(JEQ+RET) + RET ALLOW = 6
	if len(f) != 6 {
		t.Fatalf("len = %d, want 6", len(f))
	}
	if f[0].Code != bpfLdAbs || f[0].K != 0 {
		t.Fatalf("first instr must load seccomp_data.nr: %+v", f[0])
	}
	for i, want := range []uint32{1, 20} {
		j := 1 + i*2
		if f[j].Code != bpfJmpEqK || f[j].K != want || f[j].Jt != 0 || f[j].Jf != 1 {
			t.Fatalf("instr %d must be JEQ %d: %+v", j, want, f[j])
		}
		if f[j+1].Code != bpfRetK || f[j+1].K != seccompRetErrno|seccompErrEPERM {
			t.Fatalf("instr %d must be RET ERRNO(EPERM): %+v", j+1, f[j+1])
		}
	}
	last := f[len(f)-1]
	if last.Code != bpfRetK || last.K != seccompRetAllow {
		t.Fatalf("last instr must be RET ALLOW: %+v", last)
	}
}

func TestSeccompBytesLayout(t *testing.T) {
	f := buildSeccompFilter([]uint32{1})
	b := seccompBytes(f)
	if len(b) != len(f)*8 {
		t.Fatalf("bytes = %d, want %d", len(b), len(f)*8)
	}
	// instr 0: LD, code 0x20 (LE), k=0
	if b[0] != 0x20 || b[1] != 0x00 {
		t.Fatalf("first instr bytes wrong: % x", b[:8])
	}
	// instr 2: RET ERRNO|EPERM -> code 0x06, k = 0x00050001 (LE)
	off := 2 * 8
	if b[off] != 0x06 || b[off+4] != 0x01 || b[off+5] != 0x00 || b[off+6] != 0x05 || b[off+7] != 0x00 {
		t.Fatalf("RET ERRNO bytes wrong: % x", b[off:off+8])
	}
}

func TestDefaultBlockedSyscallsNonEmpty(t *testing.T) {
	if len(defaultBlockedSyscalls()) == 0 {
		t.Fatal("default deny-list must not be empty")
	}
}

func TestSandboxSeccompArg(t *testing.T) {
	sb := NewSandbox(t.TempDir(), "/app/bin/x", nil)
	sb.HostHome = t.TempDir()
	sb.seccompFD = 3

	args, cleanup, err := sb.bwrapArgs()
	if err != nil {
		t.Fatal(err)
	}
	defer cleanup()

	if !hasTriple(args, "--seccomp", "3", "/app/bin/x") {
		t.Fatalf("--seccomp 3 must be passed before the entrypoint: %v", args)
	}
}
