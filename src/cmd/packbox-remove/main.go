// packbox-remove uninstalls an app (or all of them) and its refs.
// packbox-remove desinstala una app (o todas) y sus refs.
package main

import (
	"fmt"
	"os"
	"path/filepath"

	"github.com/packbox/packbox/internal/cas"
	"github.com/packbox/packbox/internal/desktop"
	"github.com/packbox/packbox/internal/manifest"
)

func usage(code int) {
	fmt.Println("Usage: packbox-remove [--all] [--dry-run] <app-id>")
	fmt.Println("  --all, -a       remove every installed app")
	fmt.Println("  --dry-run, -n   show what would be removed, without removing")
	os.Exit(code)
}

// parseArgs splits positional arguments from flags.
// parseArgs separa los argumentos posicionales de los flags.
func parseArgs(args []string) (pos []string, all, dryRun, help bool) {
	for _, a := range args {
		switch a {
		case "--all", "-a":
			all = true
		case "--dry-run", "-n":
			dryRun = true
		case "-h", "--help":
			help = true
		default:
			pos = append(pos, a)
		}
	}
	return pos, all, dryRun, help
}

func main() {
	pos, all, dryRun, help := parseArgs(os.Args[1:])
	if help {
		usage(0)
	}
	if !all && len(pos) == 0 {
		usage(1)
	}

	home := os.Getenv("HOME")
	appsDir := filepath.Join(home, ".local/share/packbox/apps")

	ids := pos
	if all {
		ids = nil
		entries, _ := os.ReadDir(appsDir)
		for _, e := range entries {
			if e.IsDir() {
				ids = append(ids, e.Name())
			}
		}
		if len(ids) == 0 {
			fmt.Println("[skip] no apps installed")
			return
		}
	}

	store, err := cas.NewStore(filepath.Join(home, ".local/share/packbox/store"))
	if err != nil {
		fmt.Printf("ERROR: %v\n", err)
		os.Exit(1)
	}

	removed, failed := 0, 0
	for _, id := range ids {
		if dryRun {
			fmt.Printf("   would remove: %s\n", id)
			continue
		}
		if err := removeApp(home, appsDir, store, id); err != nil {
			fmt.Printf("   WARN %s: %v\n", id, err)
			failed++
			continue
		}
		fmt.Printf("[ok] %s removed\n", id)
		removed++
	}

	if dryRun {
		fmt.Printf("[dry-run] %d app(s)\n", len(ids))
		return
	}
	if all {
		fmt.Printf("[ok] removed=%d failed=%d\n", removed, failed)
	}
	if failed > 0 {
		os.Exit(1)
	}
}

// removeApp drops the refs, the desktop entry/icon and the app tree.
// removeApp suelta las refs, la entrada de menú/icono y el árbol de la app.
func removeApp(home, appsDir string, store *cas.Store, id string) error {
	appDir := filepath.Join(appsDir, id)
	if _, err := os.Stat(appDir); err != nil {
		return fmt.Errorf("not installed")
	}
	if m, err := manifest.Load(filepath.Join(appDir, "manifest.json")); err == nil {
		for _, fi := range m.Layers.App.Files {
			for _, c := range fi.Chunks {
				_ = store.RemoveReference(c, id)
			}
		}
	}
	_ = desktop.Remove(home, id)
	return os.RemoveAll(appDir)
}
