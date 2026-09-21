// Package appsize computes the on-disk size of installed apps without
// double-counting hardlinks shared between them.
// El paquete appsize calcula el tamaño en disco de las apps instaladas sin
// contar dos veces los hardlinks compartidos entre ellas.
package appsize

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"syscall"

	"github.com/packbox/packbox/internal/manifest"
)

// Human formats a byte count human-readably (IEC).
// Human formatea un número de bytes de forma legible (IEC).
func Human(b int64) string {
	const unit = 1024
	if b < unit {
		return fmt.Sprintf("%d B", b)
	}
	div, exp := int64(unit), 0
	for n := b / unit; n >= unit; n /= unit {
		div *= unit
		exp++
	}
	return fmt.Sprintf("%.1f %cB", float64(b)/float64(div), "KMGTPE"[exp])
}

// Stat holds the sizes of one app.
// Stat contiene los tamaños de una app.
type Stat struct {
	// Apparent is the sum of the app's file sizes (tree + its cells).
	// Apparent es la suma de los tamaños de sus archivos (árbol + sus celdas).
	Apparent int64
	// Real is the app's on-disk share: a file shared by N apps contributes
	// size/N to each, so hardlinked files are counted once overall and the
	// Real values of all apps sum to the total disk used.
	// Real es la parte en disco de la app: un archivo compartido por N apps
	// aporta size/N a cada una, así los hardlinks se cuentan una vez en total y
	// los Real de todas las apps suman el disco realmente usado.
	Real int64
}

// Shared returns the bytes this app shares and doesn't pay for alone.
// Shared devuelve los bytes que la app comparte y no paga en solitario.
func (s Stat) Shared() int64 { return s.Apparent - s.Real }

// SavingPct returns the percentage saved by sharing versus the app's own sum.
// SavingPct devuelve el porcentaje ahorrado por sharing frente a la suma de sus
// archivos.
func (s Stat) SavingPct() int {
	if s.Apparent <= 0 {
		return 0
	}
	return int(s.Shared() * 100 / s.Apparent)
}

type inode struct {
	dev uint64
	ino uint64
}

// Compute returns per-app sizes for the given app ids under appsDir
// (…/packbox/apps), counting each app's tree (layer A) and the cells it
// references (layer C, under modsDir). Files shared by several apps (hardlinks)
// are counted once overall.
// Compute devuelve los tamaños por app para los ids dados bajo appsDir
// (…/packbox/apps), contando el árbol de cada app (capa A) y las celdas que
// referencia (capa C, bajo modsDir). Los archivos compartidos por varias apps
// (hardlinks) se cuentan una vez en total.
func Compute(appsDir, modsDir string, ids []string) (map[string]Stat, error) {
	size := map[inode]int64{}
	owners := map[inode]int{}
	perApp := map[string]map[inode]bool{}

	count := func(set map[inode]bool, dir string) {
		_ = filepath.Walk(dir, func(p string, fi os.FileInfo, err error) error {
			if err != nil || fi.IsDir() || !fi.Mode().IsRegular() {
				return nil
			}
			st, ok := fi.Sys().(*syscall.Stat_t)
			if !ok {
				return nil
			}
			k := inode{uint64(st.Dev), st.Ino}
			if !set[k] { // count each inode once per app
				set[k] = true
				owners[k]++
				size[k] = fi.Size()
			}
			return nil
		})
	}

	for _, id := range ids {
		set := map[inode]bool{}
		perApp[id] = set
		count(set, filepath.Join(appsDir, id, "tree"))
		if modsDir == "" {
			continue
		}
		if m, err := manifest.Load(filepath.Join(appsDir, id, "manifest.json")); err == nil {
			for _, ref := range m.Mods {
				if d := cellDir(modsDir, ref); d != "" {
					count(set, d)
				}
			}
		}
	}

	res := map[string]Stat{}
	for _, id := range ids {
		var ap, real int64
		for k := range perApp[id] {
			ap += size[k]
			n := owners[k]
			if n < 1 {
				n = 1
			}
			real += size[k] / int64(n)
		}
		res[id] = Stat{Apparent: ap, Real: real}
	}
	return res, nil
}

// cellDir returns the directory of a cell ref "name@version", or "".
// cellDir devuelve el directorio de una celda "name@version", o "".
func cellDir(modsDir, ref string) string {
	ref = strings.TrimSpace(ref)
	i := strings.LastIndex(ref, "@")
	if i <= 0 {
		return ""
	}
	d := filepath.Join(modsDir, ref[:i], ref[i+1:])
	if _, err := os.Stat(d); err != nil {
		return ""
	}
	return d
}
