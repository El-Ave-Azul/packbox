// Tests for the import tar-slip hardening.
// Tests para el endurecimiento del tar-slip en import.
package main

import (
	"archive/tar"
	"bytes"
	"compress/gzip"
	"os"
	"path/filepath"
	"testing"
)

func TestSafeJoinRejectsTraversal(t *testing.T) {
	dst := t.TempDir()
	if _, err := safeJoin(dst, "../escape"); err == nil {
		t.Fatal("path traversal not rejected")
	}
	if _, err := safeJoin(dst, "a/../../escape"); err == nil {
		t.Fatal("nested traversal not rejected")
	}
}

func TestSafeJoinRejectsSymlinkParent(t *testing.T) {
	dst := t.TempDir()
	if err := os.Symlink("/tmp", filepath.Join(dst, "link")); err != nil {
		t.Fatal(err)
	}
	if _, err := safeJoin(dst, "link/pwned"); err == nil {
		t.Fatal("write through symlink not rejected")
	}
}

func TestSafeJoinAllowsNormalPaths(t *testing.T) {
	dst := t.TempDir()
	got, err := safeJoin(dst, "bin/app")
	if err != nil {
		t.Fatalf("normal path rejected: %v", err)
	}
	if got != filepath.Join(dst, "bin", "app") {
		t.Fatalf("unexpected target: %s", got)
	}
}

func TestValidateLinkTarget(t *testing.T) {
	dst := t.TempDir()
	lp := filepath.Join(dst, "a", "link")
	if err := validateLinkTarget(dst, lp, "/etc/passwd"); err == nil {
		t.Fatal("absolute symlink target accepted")
	}
	if err := validateLinkTarget(dst, lp, "../../etc/passwd"); err == nil {
		t.Fatal("escaping symlink target accepted")
	}
	if err := validateLinkTarget(dst, lp, ""); err == nil {
		t.Fatal("empty symlink target accepted")
	}
	if err := validateLinkTarget(dst, lp, "../sibling"); err != nil {
		t.Fatalf("in-tree relative symlink rejected: %v", err)
	}
}

// TestExtractBlocksTarSlip feeds extract a crafted archive: a symlink
// pointing outside dst followed by a file beneath it.
// TestExtractBlocksTarSlip alimenta extract con un archivo manipulado:
// un symlink apuntando fuera de dst seguido de un archivo debajo.
func TestExtractBlocksTarSlip(t *testing.T) {
	dst := t.TempDir()
	outside := filepath.Join(t.TempDir(), "pwned")

	var buf bytes.Buffer
	gz := gzip.NewWriter(&buf)
	tw := tar.NewWriter(gz)
	if err := tw.WriteHeader(&tar.Header{
		Name: "evil", Typeflag: tar.TypeSymlink, Linkname: filepath.Dir(outside),
	}); err != nil {
		t.Fatal(err)
	}
	body := []byte("owned")
	if err := tw.WriteHeader(&tar.Header{
		Name: "evil/pwned", Typeflag: tar.TypeReg, Mode: 0644, Size: int64(len(body)),
	}); err != nil {
		t.Fatal(err)
	}
	if _, err := tw.Write(body); err != nil {
		t.Fatal(err)
	}
	if err := tw.Close(); err != nil {
		t.Fatal(err)
	}
	if err := gz.Close(); err != nil {
		t.Fatal(err)
	}

	p := filepath.Join(t.TempDir(), "evil.pbox")
	if err := os.WriteFile(p, buf.Bytes(), 0644); err != nil {
		t.Fatal(err)
	}
	if err := extract(p, dst); err == nil {
		t.Fatal("extract accepted a tar-slip payload")
	}
	if _, err := os.Stat(outside); err == nil {
		t.Fatal("file was written outside dst")
	}
}
