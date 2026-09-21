// Package remote fetches Packbox manifests, chunks and cells from an HTTP
// remote and publishes a local app as a static remote.
// El paquete remote obtiene manifiestos, chunks y celdas de un remoto HTTP y
// publica una app local como remoto estático.
package remote

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"

	"github.com/packbox/packbox/internal/cas"
	"github.com/packbox/packbox/internal/manifest"
)

// Layout of a remote (served over any static HTTP server):
//   <base>/<app-id>/manifest.json
//   <base>/store/<hh>/<hash>
//   <base>/mods/<name>/<ver>/{manifest.json,files.json,lib/<file>}
//
// Distribución de un remoto (servible con cualquier servidor HTTP estático):
//   <base>/<app-id>/manifest.json
//   <base>/store/<hh>/<hash>
//   <base>/mods/<name>/<ver>/{manifest.json,files.json,lib/<file>}

// Source points at a remote base URL.
// Source apunta a una URL base remota.
type Source struct {
	Base   string
	Client *http.Client
}

func (s *Source) client() *http.Client {
	if s.Client != nil {
		return s.Client
	}
	return http.DefaultClient
}

func (s *Source) get(url string) ([]byte, error) {
	resp, err := s.client().Get(url)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("GET %s: %s", url, resp.Status)
	}
	return io.ReadAll(resp.Body)
}

// Manifest downloads and validates <base>/<app-id>/manifest.json.
// Manifest descarga y valida <base>/<app-id>/manifest.json.
func (s *Source) Manifest(appID string) (*manifest.Manifest, error) {
	url := strings.TrimRight(s.Base, "/") + "/" + appID + "/manifest.json"
	data, err := s.get(url)
	if err != nil {
		return nil, err
	}
	f, err := os.CreateTemp("", "packbox-remote-*.json")
	if err != nil {
		return nil, err
	}
	name := f.Name()
	defer os.Remove(name)
	if _, err := f.Write(data); err != nil {
		f.Close()
		return nil, err
	}
	f.Close()
	return manifest.Load(name)
}

// Chunk downloads a chunk and verifies its hash.
// Chunk descarga un chunk y verifica su hash.
func (s *Source) Chunk(h string) ([]byte, error) {
	if len(h) < 4 {
		return nil, fmt.Errorf("bad hash: %q", h)
	}
	url := strings.TrimRight(s.Base, "/") + "/store/" + h[:2] + "/" + h
	data, err := s.get(url)
	if err != nil {
		return nil, err
	}
	if got := cas.HashBytes(data); got != h {
		return nil, fmt.Errorf("chunk %s: hash mismatch (got %s)", h, got)
	}
	return data, nil
}

// Result reports a fetch.
// Result informa de una descarga.
type Result struct {
	Total           int
	Reused          int
	Downloaded      int
	TotalBytes      int64
	ReusedBytes     int64
	DownloadedBytes int64
}

// add accumulates a reused or downloaded item.
// add acumula un elemento reusado o descargado.
func (r *Result) add(reused bool, size int64) {
	r.Total++
	r.TotalBytes += size
	if reused {
		r.Reused++
		r.ReusedBytes += size
	} else {
		r.Downloaded++
		r.DownloadedBytes += size
	}
}

// Fetch downloads the chunks of m that are not in store (verifying hashes).
// Fetch descarga los chunks de m que no están en store (verificando hashes).
func Fetch(store *cas.Store, src *Source, m *manifest.Manifest) (Result, error) {
	var r Result
	seen := map[string]bool{}
	for _, fi := range m.Layers.App.Files {
		for _, h := range fi.Chunks {
			if seen[h] {
				continue
			}
			seen[h] = true
			if sz, ok := store.ChunkSize(h); ok {
				r.add(true, sz)
				continue
			}
			data, err := src.Chunk(h)
			if err != nil {
				return r, err
			}
			if _, err := store.StoreBytes(data); err != nil {
				return r, err
			}
			r.add(false, int64(len(data)))
		}
	}
	return r, nil
}

// Publish writes a static remote for m into dir: the app manifest, its chunks,
// and the cells it references. Returns items and bytes written.
// Publish escribe un remoto estático para m en dir: el manifiesto de la app,
// sus chunks y las celdas que referencia. Devuelve elementos y bytes.
func Publish(store *cas.Store, m *manifest.Manifest, appID, dir string) (int, int64, error) {
	mdir := filepath.Join(dir, appID)
	if err := os.MkdirAll(mdir, 0755); err != nil {
		return 0, 0, err
	}
	if err := m.Save(filepath.Join(mdir, "manifest.json")); err != nil {
		return 0, 0, err
	}
	seen := map[string]bool{}
	n := 0
	var bytes int64
	for _, fi := range m.Layers.App.Files {
		for _, h := range fi.Chunks {
			if seen[h] {
				continue
			}
			seen[h] = true
			src := filepath.Join(store.RootPath, h[:2], h)
			dst := filepath.Join(dir, "store", h[:2], h)
			if err := os.MkdirAll(filepath.Dir(dst), 0755); err != nil {
				return n, bytes, err
			}
			sz, err := copyFile(src, dst)
			if err != nil {
				return n, bytes, err
			}
			n++
			bytes += sz
		}
	}
	return n, bytes, nil
}

// ─── Cells ──────────────────────────────────────────────────────────────────

type cellFile struct {
	Path string `json:"path"`
	Hash string `json:"hash"`
	Size int64  `json:"size"`
}
type cellIndex struct {
	Files []cellFile `json:"files"`
}

// splitRef splits "name@version".
// splitRef parte "name@version".
func splitRef(ref string) (string, string) {
	ref = strings.TrimSpace(ref)
	if i := strings.LastIndex(ref, "@"); i > 0 {
		return ref[:i], ref[i+1:]
	}
	return ref, ""
}

// PublishCells copies the cells m references into <dir>/mods/... and writes a
// files.json index per cell. Returns files and bytes written.
// PublishCells copia las celdas que referencia m en <dir>/mods/... y escribe un
// índice files.json por celda. Devuelve archivos y bytes.
func PublishCells(modsDir string, m *manifest.Manifest, dir string) (int, int64, error) {
	n := 0
	var bytes int64
	for _, ref := range m.Mods {
		name, ver := splitRef(ref)
		if name == "" || ver == "" {
			continue
		}
		srcDir := filepath.Join(modsDir, name, ver)
		if _, err := os.Stat(srcDir); err != nil {
			return n, bytes, fmt.Errorf("cell %s: %w", ref, err)
		}
		dstDir := filepath.Join(dir, "mods", name, ver)
		var idx cellIndex
		err := filepath.Walk(srcDir, func(p string, fi os.FileInfo, e error) error {
			if e != nil || fi.IsDir() {
				return nil
			}
			rel, _ := filepath.Rel(srcDir, p)
			dst := filepath.Join(dstDir, rel)
			if err := os.MkdirAll(filepath.Dir(dst), 0755); err != nil {
				return err
			}
			sz, err := copyFile(p, dst)
			if err != nil {
				return err
			}
			h, err := cas.HashFile(p)
			if err != nil {
				return err
			}
			idx.Files = append(idx.Files, cellFile{Path: filepath.ToSlash(rel), Hash: h, Size: sz})
			n++
			bytes += sz
			return nil
		})
		if err != nil {
			return n, bytes, err
		}
		data, _ := json.MarshalIndent(idx, "", "  ")
		if err := os.WriteFile(filepath.Join(dstDir, "files.json"), data, 0644); err != nil {
			return n, bytes, err
		}
	}
	return n, bytes, nil
}

// FetchCells downloads the cells m references that are missing locally.
// FetchCells descarga las celdas que referencia m y faltan localmente.
func FetchCells(modsDir string, src *Source, m *manifest.Manifest) (Result, error) {
	var r Result
	for _, ref := range m.Mods {
		name, ver := splitRef(ref)
		if name == "" || ver == "" {
			continue
		}
		base := strings.TrimRight(src.Base, "/") + "/mods/" + name + "/" + ver
		idxData, err := src.get(base + "/files.json")
		if err != nil {
			return r, err
		}
		var idx cellIndex
		if err := json.Unmarshal(idxData, &idx); err != nil {
			return r, fmt.Errorf("cell %s: %w", ref, err)
		}
		dstDir := filepath.Join(modsDir, name, ver)
		for _, f := range idx.Files {
			dst := filepath.Join(dstDir, filepath.FromSlash(f.Path))
			if fi, err := os.Stat(dst); err == nil && fi.Size() == f.Size {
				r.add(true, fi.Size())
				continue
			}
			data, err := src.get(base + "/" + f.Path)
			if err != nil {
				return r, err
			}
			if got := cas.HashBytes(data); got != f.Hash {
				return r, fmt.Errorf("cell file %s: hash mismatch", f.Path)
			}
			if err := os.MkdirAll(filepath.Dir(dst), 0755); err != nil {
				return r, err
			}
			if err := os.WriteFile(dst, data, 0644); err != nil {
				return r, err
			}
			r.add(false, int64(len(data)))
		}
	}
	return r, nil
}

// copyFile copies src to dst and returns the number of bytes.
// copyFile copia src a dst y devuelve los bytes.
func copyFile(src, dst string) (int64, error) {
	in, err := os.Open(src)
	if err != nil {
		return 0, err
	}
	defer in.Close()
	out, err := os.OpenFile(dst, os.O_WRONLY|os.O_CREATE|os.O_TRUNC, 0644)
	if err != nil {
		return 0, err
	}
	defer out.Close()
	return io.Copy(out, in)
}
