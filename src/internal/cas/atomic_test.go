// Tests for the atomic StoreFile write.
// Tests para la escritura atómica de StoreFile.
package cas

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// TestStoreFileLeavesNoTemp verifies the temp file is renamed away.
// TestStoreFileLeavesNoTemp verifica que el temporal se renombre.
func TestStoreFileLeavesNoTemp(t *testing.T) {
	dir := t.TempDir()
	s, err := NewStore(dir)
	if err != nil {
		t.Fatal(err)
	}
	src := filepath.Join(dir, "f")
	if err := os.WriteFile(src, []byte("hello"), 0644); err != nil {
		t.Fatal(err)
	}
	h, err := s.StoreFile(src)
	if err != nil {
		t.Fatal(err)
	}
	entries, err := os.ReadDir(filepath.Join(dir, h[:2]))
	if err != nil {
		t.Fatal(err)
	}
	for _, e := range entries {
		if strings.Contains(e.Name(), ".tmp-") {
			t.Fatalf("leftover temp file: %s", e.Name())
		}
	}
	// The chunk must exist under its hash name.
	if _, err := os.Stat(filepath.Join(dir, h[:2], h)); err != nil {
		t.Fatalf("chunk missing: %v", err)
	}
}

// TestStoreFileAtomicOnOverwrite verifies a stored chunk stays intact when
// the same content is stored again.
// TestStoreFileAtomicOnOverwrite verifica que un chunk siga intacto al
// almacenar el mismo contenido de nuevo.
func TestStoreFileAtomicOnOverwrite(t *testing.T) {
	dir := t.TempDir()
	s, _ := NewStore(dir)
	src := filepath.Join(dir, "f")
	if err := os.WriteFile(src, []byte("hello"), 0644); err != nil {
		t.Fatal(err)
	}
	h1, err := s.StoreFile(src)
	if err != nil {
		t.Fatal(err)
	}
	h2, err := s.StoreFile(src)
	if err != nil {
		t.Fatal(err)
	}
	if h1 != h2 {
		t.Fatalf("hash changed: %s vs %s", h1, h2)
	}
	dst := filepath.Join(dir, "out")
	if err := s.RetrieveFile(h1, dst); err != nil {
		t.Fatal(err)
	}
	got, _ := os.ReadFile(dst)
	if string(got) != "hello" {
		t.Fatalf("content mismatch: %q", got)
	}
}

// TestGCIgnoresTempFiles verifies GC never deletes an in-flight temp file.
// TestGCIgnoresTempFiles verifica que GC nunca borre un temporal en vuelo.
func TestGCIgnoresTempFiles(t *testing.T) {
	dir := t.TempDir()
	s, _ := NewStore(dir)
	bucket := filepath.Join(dir, "ab")
	if err := os.MkdirAll(bucket, 0755); err != nil {
		t.Fatal(err)
	}
	tmp := filepath.Join(bucket, strings.Repeat("ab", 32)+".tmp-123456")
	if err := os.WriteFile(tmp, []byte("partial"), 0644); err != nil {
		t.Fatal(err)
	}
	orphan := filepath.Join(bucket, strings.Repeat("cd", 32))
	if err := os.WriteFile(orphan, []byte("orphan"), 0644); err != nil {
		t.Fatal(err)
	}
	if _, _, err := s.GarbageCollect(); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(tmp); err != nil {
		t.Fatal("GC removed an in-flight temp file")
	}
	if _, err := os.Stat(orphan); err == nil {
		t.Fatal("GC did not remove an unreferenced chunk")
	}
}
