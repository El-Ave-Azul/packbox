// Package cas implements a content-addressed store with BLAKE3.
// El paquete cas implementa un almacén direccionado por contenido con BLAKE3.
package cas

import (
	"encoding/hex"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"syscall"

	"github.com/packbox/packbox/internal/chunker"
	"github.com/packbox/packbox/internal/security"
	"github.com/zeebo/blake3"
)

// Store is the content-addressed store root.
// Store es la raíz del almacén direccionado por contenido.
type Store struct{ RootPath string }

// NewStore initializes the store directory.
// NewStore inicializa el directorio del almacén.
func NewStore(r string) (*Store, error) {
	if err := os.MkdirAll(r, 0755); err != nil {
		return nil, err
	}
	return &Store{RootPath: r}, nil
}

// isValidHash checks a 64-char lowercase hex string (BLAKE3-256).
// isValidHash verifica un hex lowercase de 64 chars (BLAKE3-256).
func isValidHash(h string) bool {
	if len(h) != 64 {
		return false
	}
	for _, c := range h {
		if !((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f')) {
			return false
		}
	}
	return true
}

// HashFile returns the BLAKE3 hex digest of a file.
// HashFile devuelve el digest BLAKE3 hex de un archivo.
func HashFile(p string) (string, error) {
	f, err := os.Open(p)
	if err != nil {
		return "", err
	}
	defer f.Close()
	h := blake3.New()
	if _, err := io.Copy(h, f); err != nil {
		return "", err
	}
	return hex.EncodeToString(h.Sum(nil)), nil
}

// StoreFile stores a file and returns its hash.
// StoreFile almacena un archivo y devuelve su hash.
func (s *Store) StoreFile(src string) (string, error) {
	h, err := HashFile(src)
	if err != nil {
		return "", err
	}
	dir := filepath.Join(s.RootPath, h[:2])
	dst := filepath.Join(dir, h)
	if _, err := os.Stat(dst); err == nil {
		return h, nil
	}
	if err := os.MkdirAll(dir, 0755); err != nil {
		return "", err
	}
	// Write to a temp file in the same directory, then rename atomically.
	// A partial write can never leave a corrupt chunk under its final name.
	// Escribe a un temporal en el mismo directorio, luego rename atómico.
	// Una escritura parcial nunca deja un chunk corrupto con su nombre final.
	tmp, err := os.CreateTemp(dir, h+".tmp-")
	if err != nil {
		return "", err
	}
	tmpName := tmp.Name()
	tmp.Close()
	defer os.Remove(tmpName) // no-op after a successful rename
	if err := security.SafeCopy(src, tmpName, 0644); err != nil {
		return "", err
	}
	if err := os.Rename(tmpName, dst); err != nil {
		return "", err
	}
	return h, nil
}

// hashBytes returns the BLAKE3 hex digest of data.
// hashBytes devuelve el digest BLAKE3 hex de data.
func hashBytes(data []byte) string {
	h := blake3.New()
	_, _ = h.Write(data)
	return hex.EncodeToString(h.Sum(nil))
}

// HashBytes returns the BLAKE3 hex digest of data.
// HashBytes devuelve el digest BLAKE3 hex de data.
func HashBytes(data []byte) string { return hashBytes(data) }

// StoreBytes stores a byte slice as a chunk and returns its hash.
// StoreBytes almacena un slice de bytes como chunk y devuelve su hash.
func (s *Store) StoreBytes(data []byte) (string, error) {
	h := hashBytes(data)
	dir := filepath.Join(s.RootPath, h[:2])
	dst := filepath.Join(dir, h)
	if _, err := os.Stat(dst); err == nil {
		return h, nil
	}
	if err := os.MkdirAll(dir, 0755); err != nil {
		return "", err
	}
	tmp, err := os.CreateTemp(dir, h+".tmp-")
	if err != nil {
		return "", err
	}
	tmpName := tmp.Name()
	deferred := true
	defer func() {
		if deferred {
			os.Remove(tmpName)
		}
	}()
	if _, err := tmp.Write(data); err != nil {
		tmp.Close()
		return "", err
	}
	if err := tmp.Close(); err != nil {
		return "", err
	}
	if err := os.Chmod(tmpName, 0644); err != nil {
		return "", err
	}
	if err := os.Rename(tmpName, dst); err != nil {
		return "", err
	}
	deferred = false
	return h, nil
}

// StoreChunks splits r with content-defined chunking and stores each chunk,
// returning the chunk hashes in order.
// StoreChunks parte r con CDC y almacena cada chunk, devolviendo los hashes en
// orden.
func (s *Store) StoreChunks(r io.Reader, cfg chunker.Config) ([]string, error) {
	sp := chunker.NewSplitter(r, cfg)
	var hashes []string
	for {
		chunk, err := sp.Next()
		if err == io.EOF {
			break
		}
		if err != nil {
			return nil, err
		}
		h, err := s.StoreBytes(chunk)
		if err != nil {
			return nil, err
		}
		hashes = append(hashes, h)
	}
	return hashes, nil
}

// ChunkSize returns the size of a stored chunk and whether it exists.
// ChunkSize devuelve el tamaño de un chunk almacenado y si existe.
func (s *Store) ChunkSize(h string) (int64, bool) {
	if !isValidHash(h) {
		return 0, false
	}
	fi, err := os.Stat(filepath.Join(s.RootPath, h[:2], h))
	if err != nil {
		return 0, false
	}
	return fi.Size(), true
}

// Has reports whether a chunk is present in the store.
// Has indica si un chunk está presente en el almacén.
func (s *Store) Has(h string) bool {
	_, ok := s.ChunkSize(h)
	return ok
}

// Materialize writes the concatenation of chunks to dst with the given mode.
// Materialize escribe la concatenación de chunks en dst con el modo dado.
func (s *Store) Materialize(chunks []string, dst string, mode os.FileMode) error {
	for _, h := range chunks {
		if !isValidHash(h) {
			return fmt.Errorf("invalid hash: %q", h)
		}
	}
	if err := os.MkdirAll(filepath.Dir(dst), 0755); err != nil {
		return err
	}
	f, err := os.OpenFile(dst, os.O_WRONLY|os.O_CREATE|os.O_TRUNC, mode)
	if err != nil {
		return err
	}
	for _, h := range chunks {
		src := filepath.Join(s.RootPath, h[:2], h)
		in, err := os.Open(src)
		if err != nil {
			f.Close()
			return err
		}
		if _, err := io.Copy(f, in); err != nil {
			in.Close()
			f.Close()
			return err
		}
		in.Close()
	}
	if err := f.Close(); err != nil {
		return err
	}
	return os.Chmod(dst, mode)
}

// RetrieveFile copies a chunk from the store to dst.
// RetrieveFile copia un chunk del almacén a dst.
func (s *Store) RetrieveFile(h, dst string) error {
	if !isValidHash(h) {
		return fmt.Errorf("invalid hash: %q", h)
	}
	src := filepath.Join(s.RootPath, h[:2], h)
	if _, err := os.Stat(src); os.IsNotExist(err) {
		return fmt.Errorf("chunk %s not found", h)
	}
	return security.SafeCopy(src, dst, 0644)
}

// LinkFile hardlinks a chunk into dst (fallback: copy).
// LinkFile enlaza un chunk en dst (fallback: copia).
func (s *Store) LinkFile(h, dst string) error {
	if !isValidHash(h) {
		return fmt.Errorf("invalid hash: %q", h)
	}
	src := filepath.Join(s.RootPath, h[:2], h)
	if _, err := os.Stat(src); os.IsNotExist(err) {
		return fmt.Errorf("chunk %s not found", h)
	}
	if err := os.MkdirAll(filepath.Dir(dst), 0755); err != nil {
		return fmt.Errorf("mkdir: %w", err)
	}
	return security.SafeLink(src, dst)
}

// refsPath returns the .refs path for a chunk.
// refsPath devuelve la ruta .refs de un chunk.
func (s *Store) refsPath(h string) string {
	return filepath.Join(s.RootPath, h[:2], h+".refs")
}

// withRefsLock opens .refs and takes an exclusive flock.
// withRefsLock abre .refs y toma un flock exclusivo.
func (s *Store) withRefsLock(h string, create bool) (*os.File, func(), error) {
	rp := s.refsPath(h)
	flags := os.O_RDWR
	if create {
		flags |= os.O_CREATE
	}
	f, err := os.OpenFile(rp, flags, 0644)
	if err != nil {
		return nil, nil, err
	}
	if err := syscall.Flock(int(f.Fd()), syscall.LOCK_EX); err != nil {
		f.Close()
		return nil, nil, err
	}
	return f, func() {
		_ = syscall.Flock(int(f.Fd()), syscall.LOCK_UN)
		_ = f.Close()
	}, nil
}

// AddReference records that app uses chunk h.
// AddReference registra que app usa el chunk h.
func (s *Store) AddReference(h, app string) error {
	if !isValidHash(h) {
		return fmt.Errorf("invalid hash: %q", h)
	}
	cp := filepath.Join(s.RootPath, h[:2], h)
	if _, err := os.Stat(cp); os.IsNotExist(err) {
		return fmt.Errorf("chunk does not exist: %s", h)
	}
	f, unlock, err := s.withRefsLock(h, true)
	if err != nil {
		return err
	}
	defer unlock()

	data, _ := io.ReadAll(f)
	refs := map[string]bool{}
	for _, l := range strings.Split(string(data), "\n") {
		if l != "" {
			refs[l] = true
		}
	}
	refs[app] = true
	keys := make([]string, 0, len(refs))
	for k := range refs {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	var b strings.Builder
	for _, k := range keys {
		b.WriteString(k)
		b.WriteByte('\n')
	}
	if err := f.Truncate(0); err != nil {
		return err
	}
	if _, err := f.Seek(0, 0); err != nil {
		return err
	}
	_, err = f.WriteString(b.String())
	return err
}

// RemoveReference removes app from the refs of chunk h.
// RemoveReference quita app de las refs del chunk h.
func (s *Store) RemoveReference(h, app string) error {
	if !isValidHash(h) {
		return fmt.Errorf("invalid hash: %q", h)
	}
	rp := s.refsPath(h)
	if _, err := os.Stat(rp); os.IsNotExist(err) {
		return nil
	}
	f, unlock, err := s.withRefsLock(h, false)
	if err != nil {
		return err
	}
	defer unlock()

	data, _ := io.ReadAll(f)
	refs := map[string]bool{}
	for _, l := range strings.Split(string(data), "\n") {
		if l != "" && l != app {
			refs[l] = true
		}
	}
	keys := make([]string, 0, len(refs))
	for k := range refs {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	var b strings.Builder
	for _, k := range keys {
		b.WriteString(k)
		b.WriteByte('\n')
	}
	if err := f.Truncate(0); err != nil {
		return err
	}
	if _, err := f.Seek(0, 0); err != nil {
		return err
	}
	_, err = f.WriteString(b.String())
	return err
}

// GarbageCollect removes chunks with no refs and returns count + bytes freed.
// GarbageCollect elimina chunks sin refs y devuelve cantidad + bytes liberados.
func (s *Store) GarbageCollect() (int, int64, error) {
	del := 0
	var freed int64
	entries, err := os.ReadDir(s.RootPath)
	if err != nil {
		return 0, 0, err
	}
	for _, e := range entries {
		if !e.IsDir() || len(e.Name()) != 2 {
			continue
		}
		pd := filepath.Join(s.RootPath, e.Name())
		files, err := os.ReadDir(pd)
		if err != nil {
			continue
		}
		for _, f := range files {
			if f.IsDir() {
				continue
			}
			fn := f.Name()
			if filepath.Ext(fn) == ".refs" {
				continue
			}
			// Skip in-flight temp files from an atomic StoreFile.
			// Ignora temporales en vuelo de un StoreFile atómico.
			if strings.Contains(fn, ".tmp-") {
				continue
			}
			rp := filepath.Join(pd, fn+".refs")
			cp := filepath.Join(pd, fn)
			if _, err := os.Stat(rp); os.IsNotExist(err) {
				if fi, err := f.Info(); err == nil {
					freed += fi.Size()
				}
				_ = os.Remove(cp)
				del++
			} else {
				data, _ := os.ReadFile(rp)
				if len(data) == 0 {
					if fi, err := f.Info(); err == nil {
						freed += fi.Size()
					}
					_ = os.Remove(cp)
					_ = os.Remove(rp)
					del++
				}
			}
		}
	}
	return del, freed, nil
}