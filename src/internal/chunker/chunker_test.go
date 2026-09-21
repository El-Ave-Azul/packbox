// Tests for the chunker package.
// Tests para el paquete chunker.
package chunker

import (
	"bytes"
	"io"
	"math/rand"
	"testing"
)

func splitAll(t *testing.T, data []byte, cfg Config) [][]byte {
	t.Helper()
	sp := NewSplitter(bytes.NewReader(data), cfg)
	var out [][]byte
	for {
		c, err := sp.Next()
		if err == io.EOF {
			break
		}
		if err != nil {
			t.Fatal(err)
		}
		out = append(out, c)
	}
	return out
}

func TestReassemble(t *testing.T) {
	data := make([]byte, 4<<20)
	rand.New(rand.NewSource(1)).Read(data)
	cfg := DefaultConfig()
	chunks := splitAll(t, data, cfg)
	if len(chunks) < 2 {
		t.Fatalf("expected multiple chunks, got %d", len(chunks))
	}
	var got []byte
	for _, c := range chunks {
		got = append(got, c...)
	}
	if !bytes.Equal(got, data) {
		t.Fatal("reassembly mismatch")
	}
	for i, c := range chunks {
		if len(c) > cfg.Max {
			t.Fatalf("chunk %d too big: %d", i, len(c))
		}
		if i < len(chunks)-1 && len(c) < cfg.Min {
			t.Fatalf("chunk %d too small: %d", i, len(c))
		}
	}
}

func TestDeterministic(t *testing.T) {
	data := make([]byte, 2<<20)
	rand.New(rand.NewSource(2)).Read(data)
	a := splitAll(t, data, DefaultConfig())
	b := splitAll(t, data, DefaultConfig())
	if len(a) != len(b) {
		t.Fatalf("different chunk counts: %d vs %d", len(a), len(b))
	}
	for i := range a {
		if !bytes.Equal(a[i], b[i]) {
			t.Fatalf("chunk %d differs", i)
		}
	}
}

func TestSmallAndEmpty(t *testing.T) {
	if c := splitAll(t, []byte("hello"), DefaultConfig()); len(c) != 1 || string(c[0]) != "hello" {
		t.Fatalf("small input: %v", c)
	}
	if c := splitAll(t, nil, DefaultConfig()); len(c) != 0 {
		t.Fatalf("empty input: %v", c)
	}
}

func TestEditIsLocal(t *testing.T) {
	data := make([]byte, 4<<20)
	rand.New(rand.NewSource(3)).Read(data)
	cfg := DefaultConfig()
	a := splitAll(t, data, cfg)

	mod := append([]byte(nil), data...)
	mod[len(mod)/2] ^= 0xFF // flip one byte in the middle
	b := splitAll(t, mod, cfg)

	same := 0
	for i := 0; i < len(a) && i < len(b); i++ {
		if bytes.Equal(a[i], b[i]) {
			same++
		}
	}
	if same == 0 {
		t.Fatal("a one-byte edit disturbed every chunk (not content-defined?)")
	}
}
