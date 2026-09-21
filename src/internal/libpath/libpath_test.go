// Tests for the libpath package.
// Tests para el paquete libpath.
package libpath

import (
	"os"
	"path/filepath"
	"testing"
)

func TestSearchPathsAreAbsoluteAndUnique(t *testing.T) {
	paths := SearchPaths()
	if len(paths) == 0 {
		t.Fatal("SearchPaths is empty")
	}
	seen := map[string]bool{}
	for _, p := range paths {
		if !filepath.IsAbs(p) {
			t.Fatalf("path is not absolute: %q", p)
		}
		if seen[p] {
			t.Fatalf("duplicate path: %q", p)
		}
		seen[p] = true
	}
}

func TestFindMissing(t *testing.T) {
	if _, err := Find("definitely-not-a-real-lib.so.999"); err == nil {
		t.Fatal("Find accepted a missing library")
	}
}

func TestFindExisting(t *testing.T) {
	// Find a real lib through the first existing search dir; skip if none.
	// Busca una lib real en el primer directorio existente; omite si no hay.
	for _, d := range SearchPaths() {
		entries, err := os.ReadDir(d)
		if err != nil {
			continue
		}
		for _, e := range entries {
			if e.IsDir() {
				continue
			}
			got, err := Find(e.Name())
			if err != nil {
				t.Fatalf("Find(%q) failed: %v", e.Name(), err)
			}
			if filepath.Dir(got) != d {
				// The same lib name may resolve from an earlier dir.
				if _, err := os.Stat(got); err != nil {
					t.Fatalf("Find(%q) returned a bad path: %s", e.Name(), got)
				}
			}
			return
		}
	}
	t.Skip("no host library directory available")
}
