// Tests for the debug package.
// Tests para el paquete debug.
package debug

import (
	"os"
	"path/filepath"
	"testing"
)

func TestCellName(t *testing.T) {
	if got := CellName("btop"); got != "org.debug.btop" {
		t.Fatalf("CellName = %q", got)
	}
}

func TestAttach(t *testing.T) {
	mods := t.TempDir()
	cd := filepath.Join(mods, "org.debug.app", "abc123")
	if err := os.MkdirAll(cd, 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(cd, "app.debug"), []byte("SYMBOLS"), 0644); err != nil {
		t.Fatal(err)
	}
	bin := filepath.Join(t.TempDir(), "app")
	if err := os.WriteFile(bin, []byte("ELF"), 0755); err != nil {
		t.Fatal(err)
	}

	got, err := Attach(mods, "org.debug.app@abc123", bin)
	if err != nil {
		t.Fatal(err)
	}
	if got != bin+".debug" {
		t.Fatalf("attached to %q", got)
	}
	b, err := os.ReadFile(got)
	if err != nil {
		t.Fatal(err)
	}
	if string(b) != "SYMBOLS" {
		t.Fatalf("content = %q", b)
	}
}

func TestAttachMissingCell(t *testing.T) {
	if _, err := Attach(t.TempDir(), "org.debug.nope@x", "/tmp/does-not-matter"); err == nil {
		t.Fatal("missing cell was accepted")
	}
}

func TestHasDebug(t *testing.T) {
	plain := filepath.Join(t.TempDir(), "x")
	if err := os.WriteFile(plain, []byte("not an elf"), 0644); err != nil {
		t.Fatal(err)
	}
	if HasDebug(plain) {
		t.Fatal("a plain file reported as having debug info")
	}

	// The Go test binary itself carries DWARF (unless built with -s -w).
	exe, err := os.Executable()
	if err != nil {
		t.Skip("no executable path")
	}
	if HasDebug(exe) == false {
		t.Log("test binary looks stripped; skipping the positive check")
	}
}
