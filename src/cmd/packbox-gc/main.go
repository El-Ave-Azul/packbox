// packbox-gc removes unreferenced chunks from the CAS and unreferenced cells.
// packbox-gc elimina chunks sin referencias del CAS y celdas sin referencias.
package main

import (
	"flag"
	"fmt"
	"os"
	"path/filepath"

	"github.com/packbox/packbox/internal/appinstall"
	"github.com/packbox/packbox/internal/cas"
)

func main() {
	// --days N: además de los chunks sin referencias, borra los que no se han
	// tocado en N días (LRU). 0 = solo sin referencias.
	// --days N: besides unreferenced chunks, drop the ones untouched for N days
	// (LRU). 0 = only unreferenced.
	days := flag.Int("days", 0, "borra chunks no accedidos en N días (LRU)")
	flag.Parse()

	home := os.Getenv("HOME")
	s, err := cas.NewStore(filepath.Join(home, ".local/share/packbox/store"))
	if err != nil {
		fmt.Printf("ERROR: %v\n", err)
		os.Exit(1)
	}
	fmt.Println("[gc]")
	d, b, err := s.GarbageCollectLRU(*days)
	if err != nil {
		fmt.Printf("ERROR: %v\n", err)
		os.Exit(1)
	}
	fmt.Printf("[ok] chunks=%d  bytes=%d\n", d, b)

	// Cells: drop the ones no installed app references.
	// Celdas: borra las que ninguna app instalada referencia.
	appsDir := filepath.Join(home, ".local/share/packbox/apps")
	modsDir := filepath.Join(home, ".local/share/packbox/mods")
	refs := appinstall.ReferencedCells(appsDir)
	cr, cb, err := appinstall.GCCells(modsDir, refs)
	if err != nil {
		fmt.Printf("ERROR: %v\n", err)
		os.Exit(1)
	}
	fmt.Printf("[ok] cells=%d  bytes=%d\n", cr, cb)
}
