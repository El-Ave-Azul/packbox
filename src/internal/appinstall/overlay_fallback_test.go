// Tests for the cell-materialization fallback when bwrap lacks --overlay.
// Tests del fallback de materialización de celdas cuando bwrap no tiene --overlay.
package appinstall

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/packbox/packbox/internal/cas"
	"github.com/packbox/packbox/internal/manifest"
	"github.com/packbox/packbox/internal/sandbox"
)

func TestApplyMaterializesCellsWithoutOverlay(t *testing.T) {
	orig := sandbox.OverlaySupported
	defer func() { sandbox.OverlaySupported = orig }()

	home := t.TempDir()
	store, err := cas.NewStore(filepath.Join(home, ".local/share/packbox/store"))
	if err != nil {
		t.Fatal(err)
	}
	h, err := store.StoreBytes([]byte("APPFILE"))
	if err != nil {
		t.Fatal(err)
	}
	cellLib := filepath.Join(home, ".local/share/packbox/mods", "org.test.cell", "1", "lib")
	if err := os.MkdirAll(cellLib, 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(cellLib, "libcell.so"), []byte("CELL"), 0644); err != nil {
		t.Fatal(err)
	}

	m := &manifest.Manifest{
		SchemaVersion: "1.6", Name: "app", Version: "1", Entrypoint: "/app/bin/app",
		Mods: []string{"org.test.cell@1"},
		Layers: manifest.Layers{App: manifest.AppLayer{Files: map[string]manifest.FileInfo{
			"bin/app": {Chunks: []string{h}, Size: 7, Mode: "0755"},
		}}},
	}
	treeLib := filepath.Join(home, ".local/share/packbox/apps/app/tree/lib/libcell.so")

	// With --overlay: the cell is a runtime layer, NOT materialized.
	sandbox.OverlaySupported = func() bool { return true }
	res, err := Apply(home, store, m)
	if err != nil {
		t.Fatal(err)
	}
	if res.Cells != 0 {
		t.Fatalf("cells materialized despite overlay support: %d", res.Cells)
	}
	if _, err := os.Stat(treeLib); err == nil {
		t.Fatal("cell library should not be in the tree when the overlay works")
	}

	// Without --overlay: the cell must be materialized so a plain bind works.
	os.RemoveAll(filepath.Join(home, ".local/share/packbox/apps"))
	sandbox.OverlaySupported = func() bool { return false }
	res, err = Apply(home, store, m)
	if err != nil {
		t.Fatal(err)
	}
	if res.Cells != 1 {
		t.Fatalf("cells not materialized without overlay: %d", res.Cells)
	}
	if _, err := os.Stat(treeLib); err != nil {
		t.Fatalf("cell library missing from the tree: %v", err)
	}
}
