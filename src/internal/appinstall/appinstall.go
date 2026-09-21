// Package appinstall materializes a manifest into an installed app tree and
// computes update deltas. Shared by packbox-install and packbox-update.
// El paquete appinstall materializa un manifiesto en un árbol de app instalada
// y calcula deltas de actualización. Lo comparten packbox-install y
// packbox-update.
package appinstall

import (
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"

	"github.com/packbox/packbox/internal/cas"
	"github.com/packbox/packbox/internal/manifest"
	"github.com/packbox/packbox/internal/security"
)

// Result reports what Apply did.
// Result informa lo que hizo Apply.
type Result struct {
	Files    int
	Symlinks int
	Failed   int
	Cells    int
}

// Apply materializes m into <home>/.local/share/packbox/apps/<m.Name>, reusing
// store chunks (single-chunk files are hardlinked, multi-chunk rebuilt). It
// assumes any previous install was already removed and its refs dropped, and
// saves the manifest on success.
// Apply materializa m en <home>/.local/share/packbox/apps/<m.Name> reusando los
// chunks del store (los de un chunk se hardlinkean, los multi-chunk se
// reconstruyen). Asume que la instalación previa ya se borró y sus refs se
// soltaron, y guarda el manifiesto al terminar.
func Apply(home string, store *cas.Store, m *manifest.Manifest) (Result, error) {
	var res Result
	appDir := filepath.Join(home, ".local/share/packbox/apps", m.Name)
	treeDir := filepath.Join(appDir, "tree")
	if err := os.MkdirAll(treeDir, 0755); err != nil {
		return res, err
	}
	for rel, fi := range m.Layers.App.Files {
		target := filepath.Join(treeDir, rel)
		if err := security.ValidatePath(treeDir, target); err != nil {
			fmt.Printf("   WARN skip %s: %v\n", rel, err)
			res.Failed++
			continue
		}
		_ = os.MkdirAll(filepath.Dir(target), 0755)

		if fi.Link != "" {
			if err := os.Symlink(fi.Link, target); err != nil {
				fmt.Printf("   WARN symlink %s: %v\n", rel, err)
				res.Failed++
				continue
			}
			res.Symlinks++
			res.Files++
			continue
		}
		if len(fi.Chunks) == 0 {
			continue
		}
		mode, _ := strconv.ParseUint(fi.Mode, 8, 32)
		if len(fi.Chunks) == 1 {
			if err := store.LinkFile(fi.Chunks[0], target); err != nil {
				fmt.Printf("   WARN link %s: %v\n", rel, err)
				res.Failed++
				continue
			}
			_ = os.Chmod(target, os.FileMode(mode))
		} else {
			if err := store.Materialize(fi.Chunks, target, os.FileMode(mode)); err != nil {
				fmt.Printf("   WARN materialize %s: %v\n", rel, err)
				res.Failed++
				continue
			}
		}
		for _, c := range fi.Chunks {
			_ = store.AddReference(c, m.Name)
		}
		res.Files++
	}
	// Cells are a runtime layer (composed by the sandbox overlay at /app), not
	// copied into the tree.
	// Las celdas son una capa de runtime (compuesta por el overlay del sandbox
	// en /app), no se copian al árbol.
	if err := m.Save(filepath.Join(appDir, "manifest.json")); err != nil {
		return res, err
	}
	return res, nil
}

// CellDirs returns the existing cell directories referenced by mods.
// CellDirs devuelve los directorios de celda existentes referenciados por mods.
func CellDirs(home string, mods []string) []string {
	var dirs []string
	for _, ref := range mods {
		name, ver := splitModRef(ref)
		if name == "" || ver == "" {
			continue
		}
		d := filepath.Join(home, ".local/share/packbox/mods", name, ver)
		if _, err := os.Stat(d); err == nil {
			dirs = append(dirs, d)
		}
	}
	return dirs
}

// DropRefs removes, from the store, the references m holds for appID.
// DropRefs elimina del store las referencias que m tiene para appID.
func DropRefs(store *cas.Store, m *manifest.Manifest, appID string) {
	for _, fi := range m.Layers.App.Files {
		for _, c := range fi.Chunks {
			_ = store.RemoveReference(c, appID)
		}
	}
}

// Delta summarizes updating from one manifest to another.
// Delta resume una actualización de un manifiesto a otro.
type Delta struct {
	KeptFiles    int
	ChangedFiles int
	AddedFiles   int
	RemovedFiles int

	TotalChunks   int
	ReusedChunks  int // already in the store (no download)
	NewChunks     int // not present in the old version (the delta)
	MissingChunks int // not in the store (would need download)

	TotalBytes   int64
	ReusedBytes  int64 // of TotalBytes, already in the store
	NewBytes     int64 // of TotalBytes, not in the old version (the delta)
	MissingBytes int64 // of TotalBytes, not in the store (would need download)
}

// ComputeDelta compares oldM (may be nil) against newM using the store.
// ComputeDelta compara oldM (puede ser nil) contra newM usando el store.
func ComputeDelta(store *cas.Store, oldM, newM *manifest.Manifest) Delta {
	var d Delta
	oldChunks := chunkSet(oldM)
	newFiles := newM.Layers.App.Files

	oldFiles := map[string]manifest.FileInfo{}
	if oldM != nil {
		oldFiles = oldM.Layers.App.Files
	}
	for rel, nf := range newFiles {
		of, ok := oldFiles[rel]
		switch {
		case !ok:
			d.AddedFiles++
		case sameFile(of, nf):
			d.KeptFiles++
		default:
			d.ChangedFiles++
		}
	}
	for rel := range oldFiles {
		if _, ok := newFiles[rel]; !ok {
			d.RemovedFiles++
		}
	}

	// Chunk counts (unique chunks referenced by the new manifest).
	// Recuento de chunks (únicos referenciados por el nuevo manifiesto).
	for h := range chunkSet(newM) {
		d.TotalChunks++
		if _, present := store.ChunkSize(h); present {
			d.ReusedChunks++
		} else {
			d.MissingChunks++
		}
		if !oldChunks[h] {
			d.NewChunks++
		}
	}

	// Byte accounting per file: file.Size is authoritative, chunks that are in
	// the store give their exact size, and any shortfall is charged to missing
	// chunks (which are also new content).
	// Contabilidad de bytes por archivo: Size es la verdad, los chunks que
	// están en el store dan su tamaño exacto, y el déficit se imputa a los
	// chunks ausentes (que además son contenido nuevo).
	for _, fi := range newFiles {
		d.TotalBytes += fi.Size
		var known int64
		for _, h := range fi.Chunks {
			size, present := store.ChunkSize(h)
			if !present {
				continue
			}
			known += size
			d.ReusedBytes += size
			if !oldChunks[h] {
				d.NewBytes += size
			}
		}
		if shortfall := fi.Size - known; shortfall > 0 {
			d.MissingBytes += shortfall
			d.NewBytes += shortfall
		}
	}
	return d
}

// chunkSet returns the set of chunk hashes referenced by m.
// chunkSet devuelve el conjunto de hashes de chunk referenciados por m.
func chunkSet(m *manifest.Manifest) map[string]bool {
	set := map[string]bool{}
	if m == nil {
		return set
	}
	for _, fi := range m.Layers.App.Files {
		for _, c := range fi.Chunks {
			set[c] = true
		}
	}
	return set
}

// sameFile reports whether two FileInfo describe the same file content/mode.
// sameFile indica si dos FileInfo describen el mismo contenido/modo.
func sameFile(a, b manifest.FileInfo) bool {
	if a.Mode != b.Mode || a.Link != b.Link || a.Size != b.Size || len(a.Chunks) != len(b.Chunks) {
		return false
	}
	for i := range a.Chunks {
		if a.Chunks[i] != b.Chunks[i] {
			return false
		}
	}
	return true
}

// LinkCells hardlinks the libs of each referenced cell (module) into treeDir,
// so several apps share the same cell files by inode. Used to materialize the
// C layer when exporting (the sandbox composes cells at runtime instead).
// LinkCells enlaza (hardlink) las libs de cada celda referenciada dentro de
// treeDir, así varias apps comparten los archivos por inodo. Se usa para
// materializar la capa C al exportar (el sandbox compone las celdas en runtime).
func LinkCells(home, treeDir string, mods []string) (int, error) {
	libDir := filepath.Join(treeDir, "lib")
	linked := 0
	for _, ref := range mods {
		name, ver := splitModRef(ref)
		if name == "" || ver == "" {
			return linked, fmt.Errorf("invalid cell reference %q (want name@version)", ref)
		}
		srcLib := filepath.Join(home, ".local/share/packbox/mods", name, ver, "lib")
		entries, err := os.ReadDir(srcLib)
		if err != nil {
			return linked, fmt.Errorf("cell %s@%s: %w", name, ver, err)
		}
		if err := os.MkdirAll(libDir, 0755); err != nil {
			return linked, err
		}
		for _, e := range entries {
			if e.IsDir() {
				continue
			}
			dst := filepath.Join(libDir, e.Name())
			if _, err := os.Lstat(dst); err == nil {
				continue // the app's own lib wins
			}
			if err := security.SafeLink(filepath.Join(srcLib, e.Name()), dst); err != nil {
				return linked, err
			}
			linked++
		}
	}
	return linked, nil
}

// splitModRef splits a cell reference "name@version" (or "name/version").
// splitModRef parte una referencia de celda "name@version" (o "name/version").
func splitModRef(ref string) (string, string) {
	ref = strings.TrimSpace(ref)
	if i := strings.LastIndex(ref, "@"); i > 0 {
		return ref[:i], ref[i+1:]
	}
	if i := strings.LastIndex(ref, "/"); i > 0 {
		return ref[:i], ref[i+1:]
	}
	return ref, ""
}

// ReferencedCells returns the set of cell refs ("name@version") referenced by
// the installed apps under appsDir.
// ReferencedCells devuelve el conjunto de refs de celda ("name@version")
// referenciadas por las apps instaladas bajo appsDir.
func ReferencedCells(appsDir string) map[string]bool {
	refs := map[string]bool{}
	entries, err := os.ReadDir(appsDir)
	if err != nil {
		return refs
	}
	for _, e := range entries {
		if !e.IsDir() {
			continue
		}
		m, err := manifest.Load(filepath.Join(appsDir, e.Name(), "manifest.json"))
		if err != nil {
			continue
		}
		for _, r := range m.Mods {
			if name, ver := splitModRef(r); name != "" && ver != "" {
				refs[name+"@"+ver] = true
			}
		}
	}
	return refs
}

// GCCells removes the cell versions under modsDir that are not in refs,
// returning how many were removed and the bytes freed; cell directories left
// empty are removed too.
// GCCells elimina las versiones de celda bajo modsDir que no están en refs,
// devolviendo cuántas se borraron y los bytes liberados; los directorios de
// celda que quedan vacíos también se eliminan.
func GCCells(modsDir string, refs map[string]bool) (int, int64, error) {
	var removed int
	var freed int64
	names, err := os.ReadDir(modsDir)
	if err != nil {
		if os.IsNotExist(err) {
			return 0, 0, nil
		}
		return 0, 0, err
	}
	for _, n := range names {
		if !n.IsDir() {
			continue
		}
		nameDir := filepath.Join(modsDir, n.Name())
		vers, err := os.ReadDir(nameDir)
		if err != nil {
			continue
		}
		for _, v := range vers {
			if !v.IsDir() {
				continue
			}
			if refs[n.Name()+"@"+v.Name()] {
				continue
			}
			dir := filepath.Join(nameDir, v.Name())
			var sz int64
			_ = filepath.Walk(dir, func(_ string, fi os.FileInfo, err error) error {
				if err == nil && fi.Mode().IsRegular() {
					sz += fi.Size()
				}
				return nil
			})
			if err := os.RemoveAll(dir); err != nil {
				return removed, freed, err
			}
			removed++
			freed += sz
		}
		if es, err := os.ReadDir(nameDir); err == nil && len(es) == 0 {
			_ = os.Remove(nameDir)
		}
	}
	return removed, freed, nil
}
