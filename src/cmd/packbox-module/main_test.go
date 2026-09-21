// Tests for the cell helpers.
// Tests para los helpers de celda.
package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestCellName(t *testing.T) {
	cases := map[string]string{
		"libgtk-4.so.1":  "org.lib.libgtk-4.so.1",
		"libstdc++.so.6": "org.lib.libstdc--.so.6",
		"weird name":     "org.lib.weird-name",
	}
	for in, want := range cases {
		if got := cellName(in); got != want {
			t.Fatalf("cellName(%q) = %q, want %q", in, got, want)
		}
	}
}

func TestMakeCellIdempotent(t *testing.T) {
	mods := t.TempDir()
	lib := filepath.Join(t.TempDir(), "libfoo.so.1")
	if err := os.WriteFile(lib, []byte("ELF-CONTENT"), 0644); err != nil {
		t.Fatal(err)
	}

	ref1, err := makeCell(mods, lib)
	if err != nil {
		t.Fatal(err)
	}
	ref2, err := makeCell(mods, lib)
	if err != nil {
		t.Fatal(err)
	}
	if ref1 != ref2 {
		t.Fatalf("refs differ: %s vs %s", ref1, ref2)
	}

	name := "org.lib.libfoo.so.1"
	if !strings.HasPrefix(ref1, name+"@") {
		t.Fatalf("unexpected ref: %s", ref1)
	}
	ver := strings.TrimPrefix(ref1, name+"@")
	target := filepath.Join(mods, name, ver, "lib", "libfoo.so.1")
	got, err := os.ReadFile(target)
	if err != nil {
		t.Fatalf("cell lib missing: %v", err)
	}
	if string(got) != "ELF-CONTENT" {
		t.Fatalf("content mismatch: %q", got)
	}

	es, _ := os.ReadDir(filepath.Join(mods, name))
	if len(es) != 1 {
		t.Fatalf("expected 1 version dir, got %d", len(es))
	}
}
