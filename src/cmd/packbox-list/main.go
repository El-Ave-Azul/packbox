// packbox-list lists installed apps with their real on-disk size (hardlinks
// shared between apps counted once) and the saving versus the sum of their
// files.
// packbox-list lista las apps instaladas con su tamaño real en disco (los
// hardlinks compartidos entre apps contados una vez) y el ahorro frente a la
// suma de sus archivos.
package main

import (
	"fmt"
	"os"
	"path/filepath"

	"github.com/packbox/packbox/internal/appsize"
	"github.com/packbox/packbox/internal/manifest"
)

func main() {
	tsv := false
	for _, a := range os.Args[1:] {
		if a == "--tsv" {
			tsv = true
		}
	}

	home := os.Getenv("HOME")
	dir := filepath.Join(home, ".local/share/packbox/apps")
	entries, err := os.ReadDir(dir)
	if err != nil {
		if !tsv {
			fmt.Println("No apps installed")
		}
		return
	}
	var ids []string
	for _, e := range entries {
		if e.IsDir() {
			ids = append(ids, e.Name())
		}
	}
	stats, _ := appsize.Compute(dir, filepath.Join(home, ".local/share/packbox/mods"), ids)

	if tsv {
		for _, id := range ids {
			m, err := manifest.Load(filepath.Join(dir, id, "manifest.json"))
			if err != nil {
				continue
			}
			s := stats[id]
			fmt.Printf("%s\t%s\t%d\t%d\t%s\n", m.Name, m.Version, s.Real, s.Apparent, tags(m))
		}
		return
	}

	fmt.Println("Installed apps:")
	fmt.Println("-----------------------------------------------------------")
	var totReal, totApar int64
	n := 0
	for _, id := range ids {
		m, err := manifest.Load(filepath.Join(dir, id, "manifest.json"))
		if err != nil {
			continue
		}
		s := stats[id]
		totReal += s.Real
		totApar += s.Apparent
		fmt.Printf("  * %-28s v%-10s real %-9s suma %-9s (-%d%%)%s\n",
			m.Name, m.Version, appsize.Human(s.Real), appsize.Human(s.Apparent), s.SavingPct(), tags(m))
		n++
	}
	fmt.Println("-----------------------------------------------------------")
	fmt.Printf("Total: %d apps · real %s · suma %s · ahorro %d%%\n",
		n, appsize.Human(totReal), appsize.Human(totApar), savingPct(totReal, totApar))
}

// tags builds the "[PORTABLE] [GUI/GTK4] [NET]" suffix.
// tags construye el sufijo "[PORTABLE] [GUI/GTK4] [NET]".
func tags(m *manifest.Manifest) string {
	s := ""
	if m.Portable {
		s += " [PORTABLE]"
	}
	if m.GUI {
		s += " [GUI"
		if m.Toolkit != "" {
			s += "/" + m.Toolkit
		}
		s += "]"
	}
	if m.Network {
		s += " [NET]"
	}
	return s
}

// savingPct returns 1 - real/sum as a percentage.
// savingPct devuelve 1 - real/suma como porcentaje.
func savingPct(real, apar int64) int {
	if apar <= 0 {
		return 0
	}
	return int((apar - real) * 100 / apar)
}
