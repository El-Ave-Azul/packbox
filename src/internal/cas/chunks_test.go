// Tests for chunk-level storage in the cas package.
// Tests para el almacenamiento por chunks en el paquete cas.
package cas

import (
	"bytes"
	"math/rand"
	"os"
	"path/filepath"
	"testing"

	"github.com/packbox/packbox/internal/chunker"
)

func TestStoreChunksMaterializeRoundTrip(t *testing.T) {
	dir := t.TempDir()
	s, err := NewStore(dir)
	if err != nil {
		t.Fatal(err)
	}
	data := make([]byte, 3<<20)
	rand.New(rand.NewSource(7)).Read(data)

	hashes, err := s.StoreChunks(bytes.NewReader(data), chunker.DefaultConfig())
	if err != nil {
		t.Fatal(err)
	}
	if len(hashes) < 2 {
		t.Fatalf("expected multiple chunks, got %d", len(hashes))
	}

	dst := filepath.Join(dir, "out.bin")
	if err := s.Materialize(hashes, dst, 0644); err != nil {
		t.Fatal(err)
	}
	got, err := os.ReadFile(dst)
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(got, data) {
		t.Fatal("materialized content mismatch")
	}
}

func TestStoreChunksDeterministic(t *testing.T) {
	dir := t.TempDir()
	s, _ := NewStore(dir)
	data := make([]byte, 2<<20)
	rand.New(rand.NewSource(8)).Read(data)

	h1, err := s.StoreChunks(bytes.NewReader(data), chunker.DefaultConfig())
	if err != nil {
		t.Fatal(err)
	}
	h2, err := s.StoreChunks(bytes.NewReader(data), chunker.DefaultConfig())
	if err != nil {
		t.Fatal(err)
	}
	if len(h1) != len(h2) {
		t.Fatalf("chunk count differs: %d vs %d", len(h1), len(h2))
	}
	for i := range h1 {
		if h1[i] != h2[i] {
			t.Fatalf("chunk %d hash differs", i)
		}
	}
}
