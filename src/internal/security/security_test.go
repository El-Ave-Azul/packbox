// Tests for the security package.
// Tests para el paquete security.
package security

import (
	"os"
	"path/filepath"
	"testing"
)

func TestValidatePath(t *testing.T) {
	base := "/tmp/base"
	cases := map[string]bool{
		"/tmp/base/foo":    true,
		"/tmp/base/a/b":    true,
		"/tmp/base/../etc": false,
		"/etc/passwd":      false,
	}
	for p, wantOK := range cases {
		err := ValidatePath(base, p)
		if (err == nil) != wantOK {
			t.Fatalf("ValidatePath(%q,%q)=%v, wantOK=%v", base, p, err, wantOK)
		}
	}
}

func TestSafeCopy(t *testing.T) {
	dir := t.TempDir()
	src := filepath.Join(dir, "s")
	dst := filepath.Join(dir, "d")
	os.WriteFile(src, []byte("abc"), 0640)
	if err := SafeCopy(src, dst, 0644); err != nil {
		t.Fatal(err)
	}
	b, _ := os.ReadFile(dst)
	if string(b) != "abc" {
		t.Fatalf("content mismatch: %q", b)
	}
}

func TestSafeLink(t *testing.T) {
	dir := t.TempDir()
	src := filepath.Join(dir, "src")
	dst := filepath.Join(dir, "dst")
	os.WriteFile(src, []byte("hi"), 0644)
	if err := SafeLink(src, dst); err != nil {
		t.Fatal(err)
	}
	b, _ := os.ReadFile(dst)
	if string(b) != "hi" {
		t.Fatalf("link content mismatch: %q", b)
	}
}