// Tests for the compress package.
// Tests para el paquete compress.
package compress

import (
	"os"
	"path/filepath"
	"testing"
)

func TestPrecompressed(t *testing.T) {
	cases := map[string]bool{
		"a.png": true, "b.JPG": true, "c.mp4": true, "d.zip": true,
		"e.bin": false, "f.wasm": false, "g.go": false, "h.wav": false,
	}
	for name, want := range cases {
		if got := Precompressed(name); got != want {
			t.Fatalf("Precompressed(%q) = %v, want %v", name, got, want)
		}
	}
}

func TestScan(t *testing.T) {
	dir := t.TempDir()
	write(t, filepath.Join(dir, "img.png"), 1000)
	write(t, filepath.Join(dir, "app.bin"), 3000)
	write(t, filepath.Join(dir, "sub", "v.mp4"), 500)
	total, pre := Scan(dir)
	if total != 4500 {
		t.Fatalf("total = %d, want 4500", total)
	}
	if pre != 1500 {
		t.Fatalf("pre = %d, want 1500", pre)
	}
}

func TestChoose(t *testing.T) {
	// auto, mostly compressed -> fast
	p := Choose("auto", 1000, 800, true, true)
	if p.Tool != "zstd" || p.Level != 3 {
		t.Fatalf("auto(mostly compressed) = %+v, want zstd -3", p)
	}
	// auto, compressible -> max
	p = Choose("auto", 1000, 100, true, true)
	if p.Tool != "zstd" || p.Level != 19 {
		t.Fatalf("auto(compressible) = %+v, want zstd -19", p)
	}
	// forced modes
	if p = Choose("store", 1000, 0, true, true); p.Tool != "store" {
		t.Fatalf("store = %+v", p)
	}
	if p = Choose("max", 1000, 900, true, true); p.Level != 19 {
		t.Fatalf("max = %+v", p)
	}
	if p = Choose("fast", 1000, 0, true, true); p.Level != 3 {
		t.Fatalf("fast = %+v", p)
	}
	// fallbacks when zstd is missing
	if p = Choose("max", 1000, 0, false, true); p.Tool != "xz" {
		t.Fatalf("max without zstd = %+v, want xz", p)
	}
	if p = Choose("max", 1000, 0, false, false); p.Tool != "gzip" {
		t.Fatalf("max without zstd/xz = %+v, want gzip", p)
	}
	if p = Choose("fast", 1000, 0, false, true); p.Tool != "gzip" {
		t.Fatalf("fast without zstd = %+v, want gzip", p)
	}
}

func write(t *testing.T, p string, size int) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(p), 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(p, make([]byte, size), 0644); err != nil {
		t.Fatal(err)
	}
}
