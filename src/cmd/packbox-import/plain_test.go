// Tests for extracting a plain (uncompressed) tar .pbox.
// Tests para extraer un .pbox tar plano (sin comprimir).
package main

import (
	"archive/tar"
	"os"
	"path/filepath"
	"testing"
)

func TestExtractPlainTar(t *testing.T) {
	src := filepath.Join(t.TempDir(), "app.pbox")
	f, err := os.Create(src)
	if err != nil {
		t.Fatal(err)
	}
	tw := tar.NewWriter(f)
	body := []byte("hello")
	if err := tw.WriteHeader(&tar.Header{
		Name: "bin/x", Typeflag: tar.TypeReg, Mode: 0755, Size: int64(len(body)),
	}); err != nil {
		t.Fatal(err)
	}
	if _, err := tw.Write(body); err != nil {
		t.Fatal(err)
	}
	tw.Close()
	f.Close()

	dst := t.TempDir()
	if err := extract(src, dst); err != nil {
		t.Fatalf("extract(plain tar) failed: %v", err)
	}
	got, err := os.ReadFile(filepath.Join(dst, "bin", "x"))
	if err != nil {
		t.Fatal(err)
	}
	if string(got) != "hello" {
		t.Fatalf("content = %q", got)
	}
}
