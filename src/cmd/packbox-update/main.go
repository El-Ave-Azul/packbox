// packbox-update updates an installed app to a new manifest, reusing store
// chunks and reporting how much of the new content is the delta. The new
// manifest may be a local file or, with --from, a remote (and then any missing
// chunks/cells are downloaded too).
// packbox-update actualiza una app instalada a un nuevo manifiesto, reusando los
// chunks del store e informando cuánto del contenido nuevo es el delta. El
// manifiesto nuevo puede ser un archivo local o, con --from, un remoto (y
// entonces también se descargan los chunks/celdas que falten).
package main

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/packbox/packbox/internal/appinstall"
	"github.com/packbox/packbox/internal/appsize"
	"github.com/packbox/packbox/internal/cas"
	"github.com/packbox/packbox/internal/desktop"
	"github.com/packbox/packbox/internal/manifest"
	"github.com/packbox/packbox/internal/remote"
)

func main() {
	pos, from, noGC, help := parseArgs(os.Args[1:])
	if help {
		usage(0)
	}
	if len(pos) < 1 {
		usage(1)
	}
	appID := pos[0]
	home := os.Getenv("HOME")
	appDir := filepath.Join(home, ".local/share/packbox/apps", appID)

	oldM, err := manifest.Load(filepath.Join(appDir, "manifest.json"))
	if err != nil {
		fmt.Printf("ERROR: %s is not installed (%v)\n", appID, err)
		os.Exit(1)
	}

	// New manifest: a local file (default) or a remote (--from).
	// Manifiesto nuevo: un archivo local (por defecto) o un remoto (--from).
	var newM *manifest.Manifest
	var src *remote.Source
	if from != "" {
		src = &remote.Source{Base: from}
		newM, err = src.Manifest(appID)
		if err != nil {
			fmt.Printf("ERROR: remote manifest: %v\n", err)
			os.Exit(1)
		}
	} else {
		if len(pos) < 2 {
			usage(1)
		}
		newM, err = manifest.Load(pos[1])
		if err != nil {
			fmt.Printf("ERROR: %v\n", err)
			os.Exit(1)
		}
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
	modsDir := filepath.Join(home, ".local/share/packbox/mods")

	fmt.Printf("[update] %s  %s -> %s\n", appID, oldM.Version, newM.Version)

	d := appinstall.ComputeDelta(store, oldM, newM)

	// With a remote, download whatever the new version needs that is not in the
	// store yet (only the delta): app chunks and referenced cells.
	// Con un remoto, descarga lo que la versión nueva necesita y no está en el
	// store todavía (solo el delta): chunks de la app y celdas referenciadas.
	if src != nil {
		if d.MissingBytes > 0 {
			fmt.Printf("  [net] faltan %s en el store; bajando el delta desde %s\n", appsize.Human(d.MissingBytes), from)
			r, err := remote.Fetch(store, src, newM)
			if err != nil {
				fmt.Printf("ERROR: fetch: %v\n", err)
				os.Exit(1)
			}
			fmt.Printf("  [net] chunks: %d bajados (%s), %d ya presentes\n",
				r.Downloaded, appsize.Human(r.DownloadedBytes), r.Reused)
		}
		cr, err := remote.FetchCells(modsDir, src, newM)
		if err != nil {
			fmt.Printf("ERROR: cells: %v\n", err)
			os.Exit(1)
		}
		if cr.Downloaded > 0 {
			fmt.Printf("  [net] cells: %d archivos bajados (%s)\n", cr.Downloaded, appsize.Human(cr.DownloadedBytes))
		}
		// Recompute: after the download nothing should be missing.
		// Recalcula: tras la descarga no debería faltar nada.
		d = appinstall.ComputeDelta(store, oldM, newM)
	}

	printDelta(d)

	if d.MissingBytes > 0 {
		if src == nil {
			fmt.Printf("ERROR: %s de chunks no están en el store; vuelve a ejecutar con --from <url>\n", appsize.Human(d.MissingBytes))
		} else {
			fmt.Printf("ERROR: %s siguen sin estar en el store tras la descarga\n", appsize.Human(d.MissingBytes))
		}
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

// printDelta prints the update report.
// printDelta imprime el informe de la actualización.
func printDelta(d appinstall.Delta) {
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
}

// parseArgs splits positional arguments from flags.
// parseArgs separa los argumentos posicionales de los flags.
func parseArgs(args []string) (pos []string, from string, noGC, help bool) {
	for i := 0; i < len(args); i++ {
		a := args[i]
		switch {
		case a == "--no-gc" || a == "-n":
			noGC = true
		case a == "-h" || a == "--help":
			help = true
		case a == "--from" || a == "-f":
			if i+1 < len(args) {
				from = args[i+1]
				i++
			}
		case strings.HasPrefix(a, "--from="):
			from = strings.TrimPrefix(a, "--from=")
		default:
			pos = append(pos, a)
		}
	}
	return pos, from, noGC, help
}

// usage prints the accepted invocations and exits with code.
// usage imprime las invocaciones aceptadas y sale con código.
func usage(code int) {
	fmt.Println("Usage: packbox-update [--no-gc] <app-id> <new-manifest.json>")
	fmt.Println("       packbox-update [--no-gc] <app-id> --from <url>")
	fmt.Println()
	fmt.Println("Updates an installed app to a new manifest, reusing store chunks and")
	fmt.Println("reporting the delta. With --from, the new manifest and any missing")
	fmt.Println("chunks/cells are downloaded from the remote (only the delta).")
	fmt.Println()
	fmt.Println("Options:")
	fmt.Println("  --from, -f <url>  fetch the new manifest + missing chunks from a remote")
	fmt.Println("  --no-gc, -n       skip the automatic garbage collection at the end")
	fmt.Println("  -h, --help        show this help")
	os.Exit(code)
}
