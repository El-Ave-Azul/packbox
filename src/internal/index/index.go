// Package index builds and reads a Packbox repository index: the signed
// catalogue of the apps a remote serves.
// El paquete index construye y lee un índice de repositorio Packbox: el catálogo
// firmado de las apps que sirve un remoto.
//
// Layout of a repository (served over any static HTTP server):
//
//	<base>/index.json          the catalogue (optionally <base>/index.json.sig)
//	<base>/<app-id>/manifest.json
//	<base>/store/<hh>/<hash>
//	<base>/mods/<name>/<ver>/…
package index

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"

	"github.com/packbox/packbox/internal/manifest"
)

// SchemaVersion is the index format version.
// SchemaVersion es la versión del formato del índice.
const SchemaVersion = "1"

// Entry describes one app in the catalogue.
// Entry describe una app del catálogo.
type Entry struct {
	ID          string `json:"id"`
	Name        string `json:"name"`
	Version     string `json:"version"`
	Description string `json:"description,omitempty"`
	Arch        string `json:"arch,omitempty"`
	GUI         bool   `json:"gui,omitempty"`
	Categories  string `json:"categories,omitempty"`
	// Size is the total bytes the remote holds for the app (its chunks + the
	// cells it references).
	// Size es el total de bytes que el remoto guarda para la app (sus chunks +
	// las celdas que referencia).
	Size   int64 `json:"size,omitempty"`
	Chunks int   `json:"chunks,omitempty"`
	Mods   int   `json:"mods,omitempty"`
}

// Index is the repository catalogue.
// Index es el catálogo del repositorio.
type Index struct {
	SchemaVersion string  `json:"schema_version"`
	Generated     string  `json:"generated,omitempty"`
	Apps          []Entry `json:"apps"`
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

// Build scans a published repository directory and returns its index. App
// directories (those holding a manifest.json) become entries; store/ and mods/
// are used only to total sizes.
// Build escanea un directorio de repositorio publicado y devuelve su índice. Los
// directorios de app (los que tienen manifest.json) pasan a entradas; store/ y
// mods/ se usan solo para sumar tamaños.
func Build(repoDir string) (*Index, error) {
	entries, err := os.ReadDir(repoDir)
	if err != nil {
		return nil, err
	}
	ix := &Index{
		SchemaVersion: SchemaVersion,
		Generated:     time.Now().UTC().Format(time.RFC3339),
	}
	for _, e := range entries {
		if !e.IsDir() {
			continue
		}
		id := e.Name()
		mp := filepath.Join(repoDir, id, "manifest.json")
		if _, err := os.Stat(mp); err != nil {
			continue
		}
		m, err := manifest.Load(mp)
		if err != nil {
			continue // skip a broken app rather than fail the whole index
		}
		ent := Entry{
			ID:          id,
			Name:        m.Name,
			Version:     m.Version,
			Description: m.Description,
			Arch:        m.Arch,
			GUI:         m.GUI,
			Categories:  m.Categories,
		}
		seen := map[string]bool{}
		for _, fi := range m.Layers.App.Files {
			for _, h := range fi.Chunks {
				if seen[h] || len(h) < 2 {
					continue
				}
				seen[h] = true
				if st, err := os.Stat(filepath.Join(repoDir, "store", h[:2], h)); err == nil {
					ent.Size += st.Size()
					ent.Chunks++
				}
			}
		}
		for _, ref := range m.Mods {
			name, ver := splitRef(ref)
			if name == "" || ver == "" {
				continue
			}
			ent.Mods++
			d := filepath.Join(repoDir, "mods", name, ver)
			_ = filepath.Walk(d, func(_ string, fi os.FileInfo, err error) error {
				if err != nil || fi.IsDir() {
					return nil
				}
				ent.Size += fi.Size()
				return nil
			})
		}
		ix.Apps = append(ix.Apps, ent)
	}
	sort.Slice(ix.Apps, func(i, j int) bool {
		if ix.Apps[i].Name == ix.Apps[j].Name {
			return ix.Apps[i].ID < ix.Apps[j].ID
		}
		return ix.Apps[i].Name < ix.Apps[j].Name
	})
	return ix, nil
}

// Parse decodes and minimally validates an index.
// Parse decodifica y valida mínimamente un índice.
func Parse(data []byte) (*Index, error) {
	var ix Index
	if err := json.Unmarshal(data, &ix); err != nil {
		return nil, err
	}
	if ix.SchemaVersion == "" {
		return nil, fmt.Errorf("not a packbox index (missing schema_version)")
	}
	return &ix, nil
}

// Bytes serializes the index as pretty JSON.
// Bytes serializa el índice como JSON indentado.
func (ix *Index) Bytes() ([]byte, error) {
	return json.MarshalIndent(ix, "", "  ")
}

// Save writes the index as pretty JSON to path.
// Save escribe el índice como JSON indentado en path.
func (ix *Index) Save(path string) error {
	data, err := ix.Bytes()
	if err != nil {
		return err
	}
	return os.WriteFile(path, append(data, '\n'), 0644)
}

// Find returns the entry with the given id.
// Find devuelve la entrada con el id dado.
func (ix *Index) Find(id string) (Entry, bool) {
	for _, e := range ix.Apps {
		if e.ID == id || e.Name == id {
			return e, true
		}
	}
	return Entry{}, false
}

// Search returns the entries matching a free-text query (case-insensitive
// substring over id, name, description and categories). An empty query returns
// everything.
// Search devuelve las entradas que casan con una búsqueda libre (substring, sin
// distinguir mayúsculas, sobre id, nombre, descripción y categorías). Una
// búsqueda vacía devuelve todo.
func (ix *Index) Search(query string) []Entry {
	q := strings.ToLower(strings.TrimSpace(query))
	if q == "" {
		return ix.Apps
	}
	var out []Entry
	for _, e := range ix.Apps {
		hay := strings.ToLower(e.ID + " " + e.Name + " " + e.Description + " " + e.Categories)
		if strings.Contains(hay, q) {
			out = append(out, e)
		}
	}
	return out
}
