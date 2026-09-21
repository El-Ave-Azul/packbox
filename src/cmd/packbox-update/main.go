// packbox-update updates an installed app to a new manifest, reusing store
// chunks and reporting how much of the new content is the delta.
// packbox-update actualiza una app instalada a un nuevo manifiesto reusando los
// chunks del store e informando cuánto del contenido nuevo es el delta.
package main

import (
	"fmt"
	"os"
	"path/filepath"

	"github.com/packbox/packbox/internal/appinstall"
	"github.com/packbox/packbox/internal/appsize"
	"github.com/packbox/packbox/internal/cas"
	"github.com/packbox/packbox/internal/desktop"
	"github.com/packbox/packbox/internal/manifest"
)

func main() {
	pos, noGC, help := parseArgs(os.Args[1:])
	if help {
		usage(0)
	}
	if len(pos) < 2 {
		usage(1)
	}
	appID, newPath := pos[0], pos[1]
	home := os.Getenv("HOME")
	appDir := filepath.Join(home, ".local/share/packbox/apps", appID)

	oldM, err := manifest.Load(filepath.Join(appDir, "manifest.json"))
	if err != nil {
		fmt.Printf("ERROR: %s is not installed (%v)\n", appID, err)
		os.Exit(1)
	}
	newM, err := manifest.Load(newPath)
	if err != nil {
		fmt.Printf("ERROR: %v\n", err)
		os.Exit(1)
	}
	if newM.Name != appID {
		fmt.Printf("ERROR: new manifest name %q != app-id %q\n", newM.Name, appID)
		os.Exit(1)
	}
	store, err := cas.NewStore(filepath.Join(home, ".local/share/packbox/store"))
	if err != nil {
		fmt.Printf("ERROR: %v\n", err)
		os.Exit(1)
	}

	d := appinstall.ComputeDelta(store, oldM, newM)
	fmt.Printf("[update] %s  %s -> %s\n", appID, oldM.Version, newM.Version)
	fmt.Printf("  archivos:  %d iguales, %d cambiados, %d nuevos, %d quitados\n",
		d.KeptFiles, d.ChangedFiles, d.AddedFiles, d.RemovedFiles)
	fmt.Printf("  chunks:    %d totales - %d reutilizados del store, %d nuevos (delta)\n",
		d.TotalChunks, d.ReusedChunks, d.NewChunks)
	fmt.Printf("  bytes:     %s en total\n", appsize.Human(d.TotalBytes))
	pct := 0.0
	if d.TotalBytes > 0 {
		pct = float64(d.ReusedBytes) / float64(d.TotalBytes) * 100
	}
	fmt.Printf("             %s ya en el store (%.1f%% - sin descarga)\n", appsize.Human(d.ReusedBytes), pct)
	fmt.Printf("             %s son delta vs la version instalada\n", appsize.Human(d.NewBytes))
	if d.MissingBytes > 0 {
		fmt.Printf("ERROR: %s de chunks nuevos no estan en el store; abortando\n", appsize.Human(d.MissingBytes))
		os.Exit(1)
	}

	// Apply: drop old refs, rebuild the tree reusing store chunks.
	// Aplica: suelta refs viejas, reconstruye el árbol reusando chunks.
	appinstall.DropRefs(store, oldM, appID)
	os.RemoveAll(appDir)
	res, err := appinstall.Apply(home, store, newM)
	if err != nil {
		fmt.Printf("ERROR: %v\n", err)
		os.Exit(1)
	}
	if res.Cells > 0 {
		fmt.Printf("   [ok] cells: %d libs linked\n", res.Cells)
	}
	if created, err := desktop.Create(home, newM); err != nil {
		fmt.Printf("   WARN desktop: %v\n", err)
	} else if created {
		fmt.Printf("   [ok] desktop entry: %s\n", desktop.DesktopPath(home, newM.Name))
	}

	// Auto GC: drop the chunks the old version held that nothing references now.
	// GC automático: suelta los chunks que tenía la versión vieja y ya no usa nadie.
	// Skipped with --no-gc.
	// Se salta con --no-gc.
	if !noGC {
		if del, freed, err := store.GarbageCollect(); err != nil {
			fmt.Printf("   WARN gc: %v\n", err)
		} else if del > 0 {
			fmt.Printf("   [ok] gc: %d chunks liberados (%s)\n", del, appsize.Human(freed))
		}
	}

	fmt.Printf("[ok] %s updated to v%s  files=%d symlinks=%d failed=%d\n",
		appID, newM.Version, res.Files, res.Symlinks, res.Failed)
}

// parseArgs splits positional arguments from flags.
// parseArgs separa los argumentos posicionales de los flags.
func parseArgs(args []string) (pos []string, noGC, help bool) {
	for _, a := range args {
		switch a {
		case "--no-gc", "-n":
			noGC = true
		case "-h", "--help":
			help = true
		default:
			pos = append(pos, a)
		}
	}
	return pos, noGC, help
}

// usage prints the accepted invocations and exits with code.
// usage imprime las invocaciones aceptadas y sale con código.
func usage(code int) {
	fmt.Println("Usage: packbox-update [--no-gc] <app-id> <new-manifest.json>")
	fmt.Println()
	fmt.Println("Options:")
	fmt.Println("  --no-gc, -n   skip the automatic garbage collection at the end")
	fmt.Println("  -h, --help    show this help")
	os.Exit(code)
}

