// Tests for the remote package.
// Tests para el paquete remote.
package remote

import (
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"

	"github.com/packbox/packbox/internal/cas"
	"github.com/packbox/packbox/internal/manifest"
)

func buildSource(t *testing.T) (*cas.Store, *manifest.Manifest) {
	t.Helper()
	store, err := cas.NewStore(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	content := map[string][]byte{
		"bin/a": []byte("AAAA"),
		"bin/b": []byte("BBBBBBBB"),
		"bin/c": []byte("CC"),
	}
	files := map[string]manifest.FileInfo{}
	for name, data := range content {
		h, err := store.StoreBytes(data)
		if err != nil {
			t.Fatal(err)
		}
		files[name] = manifest.FileInfo{Chunks: []string{h}, Size: int64(len(data)), Mode: "0644"}
	}
	m := &manifest.Manifest{
		SchemaVersion: "1.6", Name: "demo", Version: "1.0", Entrypoint: "/app/bin/a",
		Layers: manifest.Layers{App: manifest.AppLayer{Files: files}},
	}
	return store, m
}

func TestPublishFetchRoundTrip(t *testing.T) {
	src, m := buildSource(t)
	dir := t.TempDir()
	n, b, err := Publish(src, m, "demo", dir)
	if err != nil {
		t.Fatal(err)
	}
	if n != 3 || b == 0 {
		t.Fatalf("publish: n=%d b=%d", n, b)
	}

	srv := httptest.NewServer(http.FileServer(http.Dir(dir)))
	defer srv.Close()

	dst, err := cas.NewStore(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	got, err := (&Source{Base: srv.URL}).Manifest("demo")
	if err != nil {
		t.Fatal(err)
	}
	if got.Name != "demo" {
		t.Fatalf("manifest name %q", got.Name)
	}

	r, err := Fetch(dst, &Source{Base: srv.URL}, got)
	if err != nil {
		t.Fatal(err)
	}
	if r.Total != 3 || r.Downloaded != 3 || r.Reused != 0 {
		t.Fatalf("first fetch: %+v", r)
	}
	for _, fi := range got.Layers.App.Files {
		for _, h := range fi.Chunks {
			if !dst.Has(h) {
				t.Fatalf("chunk %s not stored", h)
			}
		}
	}

	// A second fetch reuses everything (the delta).
	r2, err := Fetch(dst, &Source{Base: srv.URL}, got)
	if err != nil {
		t.Fatal(err)
	}
	if r2.Downloaded != 0 || r2.Reused != 3 {
		t.Fatalf("second fetch not all-reused: %+v", r2)
	}
}

func TestChunkHashMismatch(t *testing.T) {
	dir := t.TempDir()
	h := "0000000000000000000000000000000000000000000000000000000000000000"
	if err := os.MkdirAll(filepath.Join(dir, "store", h[:2]), 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "store", h[:2], h), []byte("WRONG"), 0644); err != nil {
		t.Fatal(err)
	}
	srv := httptest.NewServer(http.FileServer(http.Dir(dir)))
	defer srv.Close()
	if _, err := (&Source{Base: srv.URL}).Chunk(h); err == nil {
		t.Fatal("hash mismatch not detected")
	}
}
