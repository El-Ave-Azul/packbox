// Tests for cell publish/fetch.
// Tests para publicar/descargar celdas.
package remote

import (
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"

	"github.com/packbox/packbox/internal/manifest"
)

func TestCellsRoundTrip(t *testing.T) {
	mods := t.TempDir()
	cd := filepath.Join(mods, "cell.x", "1", "lib")
	if err := os.MkdirAll(cd, 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(cd, "libfoo.so"), []byte("CELLDATA"), 0644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(mods, "cell.x", "1", "manifest.json"), []byte(`{"type":"cell"}`), 0644); err != nil {
		t.Fatal(err)
	}

	m := &manifest.Manifest{SchemaVersion: "1.6", Name: "demo", Entrypoint: "/app/bin/x", Mods: []string{"cell.x@1"}}

	dir := t.TempDir()
	n, b, err := PublishCells(mods, m, dir)
	if err != nil {
		t.Fatal(err)
	}
	if n != 2 || b == 0 {
		t.Fatalf("publish cells: n=%d b=%d", n, b)
	}

	srv := httptest.NewServer(http.FileServer(http.Dir(dir)))
	defer srv.Close()

	dstMods := t.TempDir()
	r, err := FetchCells(dstMods, &Source{Base: srv.URL}, m)
	if err != nil {
		t.Fatal(err)
	}
	if r.Total != 2 || r.Downloaded != 2 || r.Reused != 0 {
		t.Fatalf("first fetch: %+v", r)
	}
	got, err := os.ReadFile(filepath.Join(dstMods, "cell.x", "1", "lib", "libfoo.so"))
	if err != nil {
		t.Fatal(err)
	}
	if string(got) != "CELLDATA" {
		t.Fatalf("cell content = %q", got)
	}

	r2, err := FetchCells(dstMods, &Source{Base: srv.URL}, m)
	if err != nil {
		t.Fatal(err)
	}
	if r2.Downloaded != 0 || r2.Reused != 2 {
		t.Fatalf("second fetch not all-reused: %+v", r2)
	}
}
