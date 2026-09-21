// packbox-install installs an app from a manifest.json.
// packbox-install instala una app desde un manifest.json.
package main

import (
	"fmt"
	"os"
	"path/filepath"

	"github.com/packbox/packbox/internal/appinstall"
	"github.com/packbox/packbox/internal/cas"
	"github.com/packbox/packbox/internal/desktop"
	"github.com/packbox/packbox/internal/manifest"
)

func main() {
	if len(os.Args) < 2 {
		usage()
	}

	// Subcommands that expose the shared desktop implementation to the
	// shell frontend (lib/desktop.sh). See internal/desktop.
	// Subcomandos que exponen la implementación compartida de escritorio al
	// frontend shell (lib/desktop.sh). Ver internal/desktop.
	switch os.Args[1] {
	case "--desktop", "-d":
		if len(os.Args) < 3 {
			usage()
		}
		os.Exit(runDesktop(os.Args[2]))
	case "--remove-desktop", "-D":
		if len(os.Args) < 3 {
			usage()
		}
		os.Exit(runRemoveDesktop(os.Args[2]))
	}

	m, err := manifest.Load(os.Args[1])
	if err != nil {
		fmt.Printf("ERROR: %v\n", err)
		os.Exit(1)
	}
	home := os.Getenv("HOME")
	store, err := cas.NewStore(filepath.Join(home, ".local/share/packbox/store"))
	if err != nil {
		fmt.Printf("ERROR: %v\n", err)
		os.Exit(1)
	}
	fmt.Printf("[install] %s v%s\n", m.Name, m.Version)
	appDir := filepath.Join(home, ".local/share/packbox/apps", m.Name)

	// Clean previous installation (drop its refs, then the tree).
	// Limpia instalación previa (suelta sus refs, luego el árbol).
	if old, err := manifest.Load(filepath.Join(appDir, "manifest.json")); err == nil {
		appinstall.DropRefs(store, old, m.Name)
	}
	os.RemoveAll(appDir)

	res, err := appinstall.Apply(home, store, m)
	if err != nil {
		fmt.Printf("ERROR: %v\n", err)
		os.Exit(1)
	}
	if res.Cells > 0 {
		fmt.Printf("   [ok] cells: %d libs linked\n", res.Cells)
	}

	// Create desktop entry for GUI apps (single shared implementation).
	// Crea entrada de escritorio para apps GUI (implementación única).
	if created, err := desktop.Create(home, m); err != nil {
		fmt.Printf("   WARN desktop: %v\n", err)
	} else if created {
		fmt.Printf("   [ok] desktop entry: %s\n", desktop.DesktopPath(home, m.Name))
	}

	fmt.Printf("[ok] %s installed  files=%d symlinks=%d failed=%d\n",
		m.Name, res.Files, res.Symlinks, res.Failed)
}

// usage prints the accepted invocations and exits.
// usage imprime las invocaciones aceptadas y sale.
func usage() {
	fmt.Println("Usage:")
	fmt.Println("  packbox-install <manifest.json>        install an app")
	fmt.Println("  packbox-install --desktop <app-id>     (re)create its .desktop entry")
	fmt.Println("  packbox-install --remove-desktop <id>  remove its .desktop entry")
	os.Exit(1)
}

// runDesktop (re)creates the .desktop entry for an installed app.
// runDesktop (re)crea la entrada .desktop de una app instalada.
func runDesktop(appID string) int {
	home := os.Getenv("HOME")
	m, err := manifest.Load(filepath.Join(home, ".local/share/packbox/apps", appID, "manifest.json"))
	if err != nil {
		fmt.Printf("ERROR: %v\n", err)
		return 1
	}
	created, err := desktop.Create(home, m)
	if err != nil {
		fmt.Printf("ERROR: %v\n", err)
		return 1
	}
	if !created {
		fmt.Printf("[skip] %s is not a GUI app\n", appID)
		return 0
	}
	fmt.Printf("[ok] desktop entry: %s\n", desktop.DesktopPath(home, appID))
	return 0
}

// runRemoveDesktop removes the .desktop entry for an installed app.
// runRemoveDesktop elimina la entrada .desktop de una app instalada.
func runRemoveDesktop(appID string) int {
	home := os.Getenv("HOME")
	if err := desktop.Remove(home, appID); err != nil {
		fmt.Printf("ERROR: %v\n", err)
		return 1
	}
	fmt.Printf("[ok] desktop entry removed: %s\n", appID)
	return 0
}
