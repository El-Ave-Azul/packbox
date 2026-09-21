// packbox-fetch installs an app from an HTTP remote (fetching only the missing
// chunks) or publishes a local app as a static remote.
// packbox-fetch instala una app desde un remoto HTTP (descargando solo los
// chunks que faltan) o publica una app local como remoto estático.
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
	"github.com/packbox/packbox/internal/remote"
)

func usage() {
	fmt.Println("Usage:")
	fmt.Println("  packbox-fetch fetch <app-id> --from <url>   install from a remote (missing chunks only)")
	fmt.Println("  packbox-fetch publish <app-id> <dir>        write a static remote for an installed app")
	os.Exit(1)
}

func main() {
	if len(os.Args) < 2 {
		usage()
	}
	switch os.Args[1] {
	case "fetch":
		args := os.Args[2:]
		var id, from string
		for i := 0; i < len(args); i++ {
			switch args[i] {
			case "--from", "-f":
				if i+1 < len(args) {
					from = args[i+1]
					i++
				}
			default:
				id = args[i]
			}
		}
		if id == "" || from == "" {
			usage()
		}
		os.Exit(fetchCmd(id, from))
	case "publish":
		if len(os.Args) < 4 {
			usage()
		}
		os.Exit(publishCmd(os.Args[2], os.Args[3]))
	default:
		usage()
	}
}

func fetchCmd(id, from string) int {
	home := os.Getenv("HOME")
	store, err := cas.NewStore(filepath.Join(home, ".local/share/packbox/store"))
	if err != nil {
		fmt.Printf("ERROR: %v\n", err)
		return 1
	}
	src := &remote.Source{Base: from}

	m, err := src.Manifest(id)
	if err != nil {
		fmt.Printf("ERROR: manifest: %v\n", err)
		return 1
	}
	fmt.Printf("[fetch] %s v%s from %s\n", m.Name, m.Version, from)

	r, err := remote.Fetch(store, src, m)
	if err != nil {
		fmt.Printf("ERROR: fetch: %v\n", err)
		return 1
	}
	fmt.Printf("  chunks: %d total, %d reused, %d downloaded\n", r.Total, r.Reused, r.Downloaded)
	fmt.Printf("  bytes:  %s total, %s downloaded (%s reused)\n",
		appsize.Human(r.TotalBytes), appsize.Human(r.DownloadedBytes), appsize.Human(r.ReusedBytes))

	// Cells referenced by the app.
	// Celdas referenciadas por la app.
	modsDir := filepath.Join(home, ".local/share/packbox/mods")
	cr, err := remote.FetchCells(modsDir, src, m)
	if err != nil {
		fmt.Printf("ERROR: cells: %v\n", err)
		return 1
	}
	if cr.Total > 0 {
		fmt.Printf("  cells:  %d files, %d reused, %d downloaded (%s downloaded)\n",
			cr.Total, cr.Reused, cr.Downloaded, appsize.Human(cr.DownloadedBytes))
	}

	appDir := filepath.Join(home, ".local/share/packbox/apps", m.Name)
	if old, err := manifest.Load(filepath.Join(appDir, "manifest.json")); err == nil {
		appinstall.DropRefs(store, old, m.Name)
	}
	os.RemoveAll(appDir)
	res, err := appinstall.Apply(home, store, m)
	if err != nil {
		fmt.Printf("ERROR: %v\n", err)
		return 1
	}
	if created, err := desktop.Create(home, m); err == nil && created {
		fmt.Printf("   [ok] desktop entry: %s\n", desktop.DesktopPath(home, m.Name))
	}
	fmt.Printf("[ok] %s installed  files=%d\n", m.Name, res.Files)
	return 0
}

func publishCmd(id, dir string) int {
	home := os.Getenv("HOME")
	store, err := cas.NewStore(filepath.Join(home, ".local/share/packbox/store"))
	if err != nil {
		fmt.Printf("ERROR: %v\n", err)
		return 1
	}
	m, err := manifest.Load(filepath.Join(home, ".local/share/packbox/apps", id, "manifest.json"))
	if err != nil {
		fmt.Printf("ERROR: %s is not installed (%v)\n", id, err)
		return 1
	}
	n, b, err := remote.Publish(store, m, id, dir)
	if err != nil {
		fmt.Printf("ERROR: %v\n", err)
		return 1
	}
	cn, cb, err := remote.PublishCells(filepath.Join(home, ".local/share/packbox/mods"), m, dir)
	if err != nil {
		fmt.Printf("ERROR: cells: %v\n", err)
		return 1
	}
	fmt.Printf("[ok] remote published: %s  chunks=%d (%s) cells=%d (%s)\n",
		dir, n, appsize.Human(b), cn, appsize.Human(cb))
	fmt.Printf("   serve:   (cd %s && python3 -m http.server 8000)\n", dir)
	fmt.Printf("   install: packbox-fetch fetch %s --from http://HOST:8000\n", id)
	return 0
}
