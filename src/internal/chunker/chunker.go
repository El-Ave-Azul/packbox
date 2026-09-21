// Package chunker implements content-defined chunking (CDC) for Packbox.
// El paquete chunker implementa chunking definido por contenido (CDC) para
// Packbox.
//
// Splits a byte stream at content-defined boundaries (a gear rolling hash), so
// that edits to a file only disturb a few chunks — enabling chunk-level
// deduplication and cheap deltas.
// Parte un flujo de bytes en fronteras definidas por contenido (hash rodante
// tipo "gear"), de modo que editar un archivo solo perturba unos pocos chunks:
// eso habilita deduplicación por chunk y deltas baratos.
package chunker

import "io"

// Config holds the chunk size bounds.
// Config contiene los límites de tamaño de chunk.
type Config struct {
	Min int // smallest chunk (bytes)
	Avg int // target average size (bytes)
	Max int // largest chunk (bytes)
}

// DefaultConfig returns the default CDC parameters.
// DefaultConfig devuelve los parámetros CDC por defecto.
func DefaultConfig() Config {
	return Config{Min: 64 << 10, Avg: 256 << 10, Max: 1 << 20}
}

// gear is a fixed deterministic table of 64-bit values (splitmix64).
// gear es una tabla fija y determinista de valores de 64 bits (splitmix64).
var gear = func() [256]uint64 {
	var g [256]uint64
	x := uint64(0x9E3779B97F4A7C15)
	for i := 0; i < 256; i++ {
		x += 0x9E3779B97F4A7C15
		z := x
		z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9
		z = (z ^ (z >> 27)) * 0x94D049BB133111EB
		g[i] = z ^ (z >> 31)
	}
	return g
}()

// Splitter performs streaming content-defined chunking.
// Splitter hace chunking CDC en streaming.
//
// Memory use is bounded by ~Max bytes regardless of the stream length.
// El uso de memoria está acotado por ~Max bytes sin importar el largo del flujo.
type Splitter struct {
	r    io.Reader
	cfg  Config
	mask uint64
	buf  []byte // pending bytes, starting at the current chunk
	scan int    // scan position within buf
	hash uint64
	eof  bool
}

// NewSplitter returns a streaming splitter. Zero/invalid fields fall back to
// defaults, and Max is clamped to at least Min.
// NewSplitter devuelve un splitter en streaming. Los campos cero/inválidos
// caen a los valores por defecto, y Max se ajusta a al menos Min.
func NewSplitter(r io.Reader, cfg Config) *Splitter {
	d := DefaultConfig()
	if cfg.Min <= 0 {
		cfg.Min = d.Min
	}
	if cfg.Avg <= 0 {
		cfg.Avg = d.Avg
	}
	if cfg.Max < cfg.Min {
		cfg.Max = d.Max
		if cfg.Max < cfg.Min {
			cfg.Max = cfg.Min
		}
	}
	// mask with ~log2(Avg) low bits set.
	bits := 0
	for (1 << (bits + 1)) <= cfg.Avg {
		bits++
	}
	return &Splitter{r: r, cfg: cfg, mask: (uint64(1) << uint(bits)) - 1}
}

// Next returns the next chunk. It returns io.EOF when the stream is exhausted.
// The returned slice is owned by the caller.
// Next devuelve el siguiente chunk. Devuelve io.EOF al agotarse el flujo.
// El slice devuelto pertenece al llamador.
func (s *Splitter) Next() ([]byte, error) {
	for {
		for s.scan < len(s.buf) {
			s.hash = (s.hash << 1) + gear[s.buf[s.scan]]
			s.scan++
			if s.scan >= s.cfg.Min && (s.hash&s.mask == 0 || s.scan >= s.cfg.Max) {
				return s.emit(s.scan), nil
			}
		}
		if s.eof {
			if len(s.buf) > 0 {
				return s.emit(len(s.buf)), nil
			}
			return nil, io.EOF
		}
		tmp := make([]byte, s.cfg.Max)
		n, err := s.r.Read(tmp)
		if n > 0 {
			s.buf = append(s.buf, tmp[:n]...)
		}
		if err == io.EOF {
			s.eof = true
		} else if err != nil {
			return nil, err
		}
	}
}

// emit copies out buf[:n], keeps the remainder, and resets the scan state.
// emit copia buf[:n], conserva el resto y reinicia el estado de escaneo.
func (s *Splitter) emit(n int) []byte {
	out := make([]byte, n)
	copy(out, s.buf[:n])
	rest := append([]byte(nil), s.buf[n:]...)
	s.buf = rest
	s.scan = 0
	s.hash = 0
	return out
}
