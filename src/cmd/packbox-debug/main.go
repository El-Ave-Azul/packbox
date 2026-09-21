// packbox-debug attaches an app's debug symbols (a separate cell-debug) on
// demand, so they are only fetched when actually debugging.
// packbox-debug adjunta los símbolos de debug de una app (una celda cell-debug
// aparte) a demanda, para traerlos solo cuando se depura.
package main

import (
	"fmt"
	"os"
	"path/filepath"

	"github.com/packbox/packbox/internal/debug"
	"github.com/packbox/packbox/internal/manifest"
)

func main() {
	if len(os.Args) < 2 {
		fmt.Println("Usage: packbox-debug <app-id>")
		os.Exit(1)
	}
	id := os.Args[1]
	home := os.Getenv("HOME")
	appDir := filepath.Join(home, ".local/share/packbox/apps", id)

	m, err := manifest.Load(filepath.Join(appDir, "manifest.json"))
	if err != nil {
		fmt.Printf("ERROR: %s is not installed (%v)\n", id, err)
		os.Exit(1)
	}
	if m.Debug == nil || m.Debug.Cell == "" {
		fmt.Printf("[skip] %s has no debug symbols\n", id)
		return
	}
	bin := filepath.Join(appDir, "tree", m.Debug.Binary)
	modsDir := filepath.Join(home, ".local/share/packbox/mods")
	got, err := debug.Attach(modsDir, m.Debug.Cell, bin)
	if err != nil {
		fmt.Printf("ERROR: %v\n", err)
		os.Exit(1)
	}
	fmt.Printf("[ok] debug symbols attached: %s\n", got)
	fmt.Printf("   gdb %s\n", bin)
}
