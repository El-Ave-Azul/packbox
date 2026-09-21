// Tests for the appsize package.
// Tests para el paquete appsize.
package appsize

import (
	"os"
	"path/filepath"
	"testing"
)

func write(t *testing.T, p string, size int) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(p), 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(p, make([]byte, size), 0644); err != nil {
		t.Fatal(err)
	}
}

func TestComputeSharedHardlinks(t *testing.T) {
	dir := t.TempDir()
	a := filepath.Join(dir, "appA", "tree", "bin")
	b := filepath.Join(dir, "appB", "tree", "bin")

	// appA: own file (100) + shared (200)
	write(t, filepath.Join(a, "own"), 100)
	write(t, filepath.Join(a, "shared"), 200)
	// appB: own file (50) + hardlink to the same shared inode
	write(t, filepath.Join(b, "own"), 50)
	if err := os.Link(filepath.Join(a, "shared"), filepath.Join(b, "shared")); err != nil {
		t.Fatal(err)
	}

	st, err := Compute(dir, "", []string{"appA", "appB"})
	if err != nil {
		t.Fatal(err)
	}
	// shared 200B / 2 owners -> 100B each; plus each app's own file.
	if st["appA"].Apparent != 300 || st["appA"].Real != 200 {
		t.Fatalf("appA = %+v, want {Apparent:300 Real:200}", st["appA"])
	}
	if st["appB"].Apparent != 250 || st["appB"].Real != 150 {
		t.Fatalf("appB = %+v, want {Apparent:250 Real:150}", st["appB"])
	}
	// Sum of the apps' Real = total unique on-disk bytes (300 + 50 = 350).
	if tot := st["appA"].Real + st["appB"].Real; tot != 350 {
		t.Fatalf("sum of Real = %d, want 350 (total disk)", tot)
	}
	if st["appA"].SavingPct() != 33 || st["appB"].SavingPct() != 40 {
		t.Fatalf("saving: %d, %d; want 33, 40", st["appA"].SavingPct(), st["appB"].SavingPct())
	}
}

func TestComputeNoSharing(t *testing.T) {
	dir := t.TempDir()
	write(t, filepath.Join(dir, "solo", "tree", "f"), 123)
	st, err := Compute(dir, "", []string{"solo"})
	if err != nil {
		t.Fatal(err)
	}
	if st["solo"].Apparent != 123 || st["solo"].Real != 123 || st["solo"].SavingPct() != 0 {
		t.Fatalf("solo = %+v", st["solo"])
	}
}
