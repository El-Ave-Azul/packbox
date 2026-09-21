// packbox-remove uninstalls an app and its refs.
// packbox-remove desinstala una app y sus refs.
package main

import (
	"fmt"
	"os"
	"path/filepath"

	"github.com/packbox/packbox/internal/cas"
	"github.com/packbox/packbox/internal/manifest"
)

func main() {
	if len(os.Args) < 2 {
		fmt.Println("Usage: packbox-remove <app-id>")
		os.Exit(1)
	}
	id := os.Args[1]
	home := os.Getenv("HOME")
	appDir := filepath.Join(home, ".local/share/packbox/apps", id)
	if _, err := os.Stat(appDir); os.IsNotExist(err) {
		fmt.Printf("ERROR: not installed: %s\n", id)
		os.Exit(1)
	}
	store, err := cas.NewStore(filepath.Join(home, ".local/share/packbox/store"))
	if err != nil {
		fmt.Printf("ERROR: %v\n", err)
		os.Exit(1)
	}
	if m, err := manifest.Load(filepath.Join(appDir, "manifest.json")); err == nil {
		for _, fi := range m.Layers.App.Files {
			for _, c := range fi.Chunks {
				_ = store.RemoveReference(c, id)
			}
		}
	}
	// Remove desktop entry and icon.
	// Elimina entrada de menú e icono.
	os.Remove(filepath.Join(home, ".local/share/applications", "packbox-"+id+".desktop"))
	for _, ext := range []string{".png", ".svg", ".xpm"} {
		os.Remove(filepath.Join(home, ".local/share/icons/hicolor/256x256/apps", "packbox-"+id+ext))
	}
	os.RemoveAll(appDir)
	fmt.Printf("[ok] %s removed\n", id)
}