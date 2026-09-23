// Tests for the cas package.
// Tests para el paquete cas.
package cas

import (
	"os"
	"path/filepath"
	"testing"
)

func TestIsValidHash(t *testing.T) {
	valid := "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
	if !isValidHash(valid) {
		t.Fatal("valid hash rejected")
	}
	invalid := []string{
		"", "abc", "../../etc/passwd",
		"0123456789ABCDEF0123456789abcdef0123456789abcdef0123456789abcdef",
		"0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcde",
	}
	for _, h := range invalid {
		if isValidHash(h) {
			t.Fatalf("invalid hash accepted: %q", h)
		}
	}
}

func TestStoreRoundTrip(t *testing.T) {
	dir := t.TempDir()
	s, err := NewStore(dir)
	if err != nil {
		t.Fatal(err)
	}
	src := filepath.Join(dir, "src.txt")
	if err := os.WriteFile(src, []byte("hello world"), 0644); err != nil {
		t.Fatal(err)
	}
	h, err := s.StoreFile(src)
	if err != nil {
		t.Fatal(err)
	}
	if !isValidHash(h) {
		t.Fatal("invalid hash returned")
	}
	dst := filepath.Join(dir, "dst.txt")
	if err := s.RetrieveFile(h, dst); err != nil {
		t.Fatal(err)
	}
	got, _ := os.ReadFile(dst)
	if string(got) != "hello world" {
		t.Fatalf("content mismatch: %q", got)
	}
}

func TestRefsAndGC(t *testing.T) {
	dir := t.TempDir()
	s, _ := NewStore(dir)
	src := filepath.Join(dir, "x")
	os.WriteFile(src, []byte("data"), 0644)
	h, _ := s.StoreFile(src)
	if err := s.AddReference(h, "app1"); err != nil {
		t.Fatal(err)
	}
	if err := s.RemoveReference(h, "app1"); err != nil {
		t.Fatal(err)
	}
	del, _, err := s.GarbageCollect()
	if err != nil {
		t.Fatal(err)
	}
	if del == 0 {
		t.Fatal("GC did not remove unreferenced chunk")
	}
}
