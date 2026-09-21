// Tests for CellDirs.
// Tests para CellDirs.
package appinstall

import (
	"os"
	"path/filepath"
	"testing"
)

func TestCellDirs(t *testing.T) {
	home := t.TempDir()
	want := filepath.Join(home, ".local/share/packbox/mods", "c", "1")
	if err := os.MkdirAll(want, 0755); err != nil {
		t.Fatal(err)
	}
	dirs := CellDirs(home, []string{"c@1", "missing@2"})
	if len(dirs) != 1 || dirs[0] != want {
		t.Fatalf("CellDirs = %v, want [%s]", dirs, want)
	}
}
