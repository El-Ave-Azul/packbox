// Tests for the appinstall package.
// Tests para el paquete appinstall.
package appinstall

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/packbox/packbox/internal/cas"
	"github.com/packbox/packbox/internal/manifest"
)

func TestSplitModRef(t *testing.T) {
	cases := []struct{ in, name, ver string }{
		{"org.toolkit.gtk3@1.0.0", "org.toolkit.gtk3", "1.0.0"},
		{"org.toolkit.gtk3/2.1", "org.toolkit.gtk3", "2.1"},
		{"solo-nombre", "solo-nombre", ""},
		{"  spaced@1.0  ", "spaced", "1.0"},
	}
	for _, c := range cases {
		n, v := splitModRef(c.in)
		if n != c.name || v != c.ver {
			t.Fatalf("splitModRef(%q) = (%q,%q), want (%q,%q)", c.in, n, v, c.name, c.ver)
		}
	}
}

func TestLinkCellsHardlinks(t *testing.T) {
	home := t.TempDir()
	modLib := filepath.Join(home, ".local/share/packbox/mods", "org.demo.cell", "1.0.0", "lib")
	if err := os.MkdirAll(modLib, 0755); err != nil {
		t.Fatal(err)
	}
	src := filepath.Join(modLib, "libcell.so.1")
	if err := os.WriteFile(src, []byte("CELL"), 0644); err != nil {
		t.Fatal(err)
	}
	tree := filepath.Join(home, "apps", "demo", "tree")
	if err := os.MkdirAll(filepath.Join(tree, "lib"), 0755); err != nil {
		t.Fatal(err)
	}
	n, err := LinkCells(home, tree, []string{"org.demo.cell@1.0.0"})
	if err != nil || n != 1 {
		t.Fatalf("linkCells = %d, %v; want 1, nil", n, err)
	}
	si, _ := os.Stat(src)
	di, err := os.Stat(filepath.Join(tree, "lib", "libcell.so.1"))
	if err != nil {
		t.Fatalf("cell lib not materialized: %v", err)
	}
	if !os.SameFile(si, di) {
		t.Fatal("cell lib is not a hardlink")
	}
}

func TestLinkCellsKeepsAppLib(t *testing.T) {
	home := t.TempDir()
	modLib := filepath.Join(home, ".local/share/packbox/mods", "c", "1", "lib")
	os.MkdirAll(modLib, 0755)
	os.WriteFile(filepath.Join(modLib, "libx.so"), []byte("CELL"), 0644)
	tree := filepath.Join(home, "apps", "demo", "tree")
	treeLib := filepath.Join(tree, "lib")
	os.MkdirAll(treeLib, 0755)
	own := filepath.Join(treeLib, "libx.so")
	os.WriteFile(own, []byte("MINE"), 0644)
	if _, err := LinkCells(home, tree, []string{"c@1"}); err != nil {
		t.Fatal(err)
	}
	got, _ := os.ReadFile(own)
	if string(got) != "MINE" {
		t.Fatalf("app's own lib was overwritten: %q", got)
	}
}

func TestLinkCellsMissingCell(t *testing.T) {
	home := t.TempDir()
	tree := filepath.Join(home, "apps", "demo", "tree")
	os.MkdirAll(tree, 0755)
	if _, err := LinkCells(home, tree, []string{"nope@9"}); err == nil {
		t.Fatal("expected error for missing cell")
	}
}

func TestComputeDelta(t *testing.T) {
	store, err := cas.NewStore(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	h1, _ := store.StoreBytes([]byte("aaaaaa"))                              // 6
	h2, _ := store.StoreBytes([]byte("bbbbbbbb"))                            // 8
	h3, _ := store.StoreBytes([]byte("cccccccccccc"))                        // 12
	h4 := "0000000000000000000000000000000000000000000000000000000000000000" // not stored

	oldM := &manifest.Manifest{
		Name: "app",
		Layers: manifest.Layers{App: manifest.AppLayer{Files: map[string]manifest.FileInfo{
			"a": {Chunks: []string{h1}, Size: 6, Mode: "0644"},
			"b": {Chunks: []string{h2}, Size: 8, Mode: "0644"},
		}}},
	}
	newM := &manifest.Manifest{
		Name: "app",
		Layers: manifest.Layers{App: manifest.AppLayer{Files: map[string]manifest.FileInfo{
			"a": {Chunks: []string{h1}, Size: 6, Mode: "0644"},  // kept
			"b": {Chunks: []string{h3}, Size: 12, Mode: "0644"}, // changed
			"c": {Chunks: []string{h4}, Size: 5, Mode: "0644"},  // added, missing in store
		}}},
	}

	d := ComputeDelta(store, oldM, newM)
	if d.KeptFiles != 1 || d.ChangedFiles != 1 || d.AddedFiles != 1 || d.RemovedFiles != 0 {
		t.Fatalf("files delta wrong: %+v", d)
	}
	if d.TotalChunks != 3 || d.ReusedChunks != 2 || d.NewChunks != 2 {
		t.Fatalf("chunks delta wrong: %+v", d)
	}
	if d.TotalBytes != 6+12+5 {
		t.Fatalf("TotalBytes = %d, want 23", d.TotalBytes)
	}
	if d.ReusedBytes != 6+12 {
		t.Fatalf("ReusedBytes = %d, want 18", d.ReusedBytes)
	}
	if d.NewBytes != 12+5 { // h3 (12) + h4 (5) are new vs old
		t.Fatalf("NewBytes = %d, want 17", d.NewBytes)
	}
	if d.MissingBytes != 5 { // h4 not present
		t.Fatalf("MissingBytes = %d, want 5", d.MissingBytes)
	}
}

func writeApp(t *testing.T, appsDir, name string, mods []string) {
	t.Helper()
	d := filepath.Join(appsDir, name)
	if err := os.MkdirAll(d, 0755); err != nil {
		t.Fatal(err)
	}
	m := &manifest.Manifest{
		SchemaVersion: "1.6", Name: name, Version: "1", Entrypoint: "/app/x",
		Layers: manifest.Layers{App: manifest.AppLayer{Files: map[string]manifest.FileInfo{}}},
		Mods:   mods,
	}
	if err := m.Save(filepath.Join(d, "manifest.json")); err != nil {
		t.Fatal(err)
	}
}

func mkCell(t *testing.T, modsDir, name, ver string, size int) {
	t.Helper()
	libDir := filepath.Join(modsDir, name, ver, "lib")
	if err := os.MkdirAll(libDir, 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(libDir, "libx.so"), make([]byte, size), 0644); err != nil {
		t.Fatal(err)
	}
}

func TestReferencedCellsAndGC(t *testing.T) {
	base := t.TempDir()
	appsDir := filepath.Join(base, "apps")
	modsDir := filepath.Join(base, "mods")

	writeApp(t, appsDir, "appA", []string{"cell.a@1"})
	writeApp(t, appsDir, "appB", []string{"cell.a@1", "cell.b@2"})

	mkCell(t, modsDir, "cell.a", "1", 100) // referenced
	mkCell(t, modsDir, "cell.b", "2", 200) // referenced
	mkCell(t, modsDir, "cell.c", "3", 300) // orphan
	mkCell(t, modsDir, "cell.a", "9", 999) // orphan version

	refs := ReferencedCells(appsDir)
	if !refs["cell.a@1"] || !refs["cell.b@2"] || len(refs) != 2 {
		t.Fatalf("refs = %v, want {cell.a@1, cell.b@2}", refs)
	}

	removed, freed, err := GCCells(modsDir, refs)
	if err != nil {
		t.Fatal(err)
	}
	if removed != 2 {
		t.Fatalf("removed = %d, want 2", removed)
	}
	if freed != 1299 {
		t.Fatalf("freed = %d, want 1299", freed)
	}
	for _, keep := range []string{
		filepath.Join(modsDir, "cell.a", "1"),
		filepath.Join(modsDir, "cell.b", "2"),
	} {
		if _, err := os.Stat(keep); err != nil {
			t.Fatalf("referenced cell removed: %s", keep)
		}
	}
	if _, err := os.Stat(filepath.Join(modsDir, "cell.c")); err == nil {
		t.Fatal("orphan cell dir not removed")
	}
	if _, err := os.Stat(filepath.Join(modsDir, "cell.a", "9")); err == nil {
		t.Fatal("orphan cell version not removed")
	}
}
