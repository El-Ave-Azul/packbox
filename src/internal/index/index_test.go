// Tests for the index package.
// Tests para el paquete index.
package index

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// writeRepo lays out a minimal published repository under dir.
// writeRepo crea un repositorio publicado mínimo bajo dir.
func writeRepo(t *testing.T, dir string) {
	t.Helper()
	hash := strings.Repeat("a", 64) // 64-char hex
	app := filepath.Join(dir, "demo")
	if err := os.MkdirAll(app, 0755); err != nil {
		t.Fatal(err)
	}
	man := `{
      "schema_version": "1.7",
      "name": "demo",
      "version": "1.2.3",
      "description": "Demo image tool",
      "arch": "amd64",
      "gui": true,
      "categories": "Graphics;Viewer;",
      "entrypoint": "/app/bin/demo",
      "layers": {"app": {"files": {"bin/demo": {"chunks": ["` + hash + `"], "size": 4, "mode": "0755"}}}},
      "mods": ["org.lib.foo.so@abc123"]
    }`
	if err := os.WriteFile(filepath.Join(app, "manifest.json"), []byte(man), 0644); err != nil {
		t.Fatal(err)
	}
	// One chunk in the remote store (8 bytes).
	cdir := filepath.Join(dir, "store", "aa")
	if err := os.MkdirAll(cdir, 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(cdir, hash), []byte("12345678"), 0644); err != nil {
		t.Fatal(err)
	}
	// One cell with a 4-byte file (plus files.json).
	mdir := filepath.Join(dir, "mods", "org.lib.foo.so", "abc123")
	if err := os.MkdirAll(mdir, 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(mdir, "libfoo.so"), []byte("lib!"), 0644); err != nil {
		t.Fatal(err)
	}
}

func TestBuild(t *testing.T) {
	dir := t.TempDir()
	writeRepo(t, dir)

	ix, err := Build(dir)
	if err != nil {
		t.Fatal(err)
	}
	if ix.SchemaVersion != SchemaVersion {
		t.Fatalf("schema = %q", ix.SchemaVersion)
	}
	if len(ix.Apps) != 1 {
		t.Fatalf("apps = %d, want 1", len(ix.Apps))
	}
	e := ix.Apps[0]
	if e.ID != "demo" || e.Name != "demo" || e.Version != "1.2.3" {
		t.Fatalf("entry = %+v", e)
	}
	if !e.GUI || e.Arch != "amd64" {
		t.Fatalf("gui/arch wrong: %+v", e)
	}
	if e.Chunks != 1 || e.Mods != 1 {
		t.Fatalf("chunks/mods = %d/%d, want 1/1", e.Chunks, e.Mods)
	}
	// size = 8 (chunk) + 4 (cell file); files.json is not written here.
	if e.Size != 12 {
		t.Fatalf("size = %d, want 12", e.Size)
	}
	// store/ and mods/ are not apps.
	if _, ok := ix.Find("store"); ok {
		t.Fatal("store/ leaked into the index")
	}
}

func TestRoundTripAndSearch(t *testing.T) {
	dir := t.TempDir()
	writeRepo(t, dir)
	ix, err := Build(dir)
	if err != nil {
		t.Fatal(err)
	}
	p := filepath.Join(dir, "index.json")
	if err := ix.Save(p); err != nil {
		t.Fatal(err)
	}
	data, err := os.ReadFile(p)
	if err != nil {
		t.Fatal(err)
	}
	got, err := Parse(data)
	if err != nil {
		t.Fatal(err)
	}
	if len(got.Apps) != 1 || got.Apps[0].ID != "demo" {
		t.Fatalf("round trip lost data: %+v", got)
	}
	if e, ok := got.Find("demo"); !ok || e.Version != "1.2.3" {
		t.Fatalf("Find(demo) = %+v ok=%v", e, ok)
	}
	if n := len(got.Search("image")); n != 1 { // matches the description
		t.Fatalf("Search(image) = %d, want 1", n)
	}
	if n := len(got.Search("graphics")); n != 1 { // matches categories
		t.Fatalf("Search(graphics) = %d, want 1", n)
	}
	if n := len(got.Search("nonesuch")); n != 0 {
		t.Fatalf("Search(nonesuch) = %d, want 0", n)
	}
	if n := len(got.Search("")); n != 1 { // empty = all
		t.Fatalf("Search(\"\") = %d, want 1", n)
	}
}

func TestParseRejectsNonIndex(t *testing.T) {
	if _, err := Parse([]byte(`{"apps":[]}`)); err == nil {
		t.Fatal("accepted JSON without schema_version")
	}
	if _, err := Parse([]byte(`not json`)); err == nil {
		t.Fatal("accepted invalid JSON")
	}
}
