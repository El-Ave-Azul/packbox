// packbox-fetch installs an app from an HTTP remote (fetching only the missing
// chunks), publishes a local app as a static remote, and works with a remote's
// signed index (build, search, install).
// packbox-fetch instala una app desde un remoto HTTP (descargando solo los
// chunks que faltan), publica una app local como remoto estático, y trabaja con
// el índice firmado de un remoto (generar, buscar, instalar).
package main

import (
	"fmt"
	"os"
	"path/filepath"

	"github.com/packbox/packbox/internal/appinstall"
	"github.com/packbox/packbox/internal/appsize"
	"github.com/packbox/packbox/internal/cas"
	"github.com/packbox/packbox/internal/desktop"
	"github.com/packbox/packbox/internal/index"
	"github.com/packbox/packbox/internal/manifest"
	"github.com/packbox/packbox/internal/remote"
	"github.com/packbox/packbox/internal/sign"
)

func configDir() string {
	return filepath.Join(os.Getenv("HOME"), ".config/packbox")
}

func usage() {
	fmt.Println("Usage:")
	fmt.Println("  packbox-fetch index <dir> [--sign]          build a remote's index.json (and sign it)")
	fmt.Println("  packbox-fetch search <query> --from <url>   search a remote's signed index")
	fmt.Println("  packbox-fetch install <app-id> --from <url> verify the index, then install")
	fmt.Println("  packbox-fetch fetch <app-id> --from <url>   install from a remote (missing chunks only)")
	fmt.Println("  packbox-fetch publish <app-id> <dir>        write a static remote for an installed app")
	os.Exit(1)
}

// parseFrom extracts a positional id and a --from/-f URL from args.
// parseFrom extrae un id posicional y una URL --from/-f de args.
func parseFrom(args []string) (id, from string) {
	for i := 0; i < len(args); i++ {
		switch args[i] {
		case "--from", "-f":
			if i+1 < len(args) {
				from = args[i+1]
				i++
			}
		default:
			if id == "" {
				id = args[i]
			}
		}
	}
	return id, from
}

func main() {
	if len(os.Args) < 2 {
		usage()
	}
	switch os.Args[1] {
	case "fetch":
		id, from := parseFrom(os.Args[2:])
		if id == "" || from == "" {
			usage()
		}
		os.Exit(installApp(id, from))
	case "install":
		id, from := parseFrom(os.Args[2:])
		if id == "" || from == "" {
			usage()
		}
		os.Exit(installCmd(id, from))
	case "search":
		q, from := parseFrom(os.Args[2:])
		if from == "" {
			usage()
		}
		os.Exit(searchCmd(q, from))
	case "index":
		args := os.Args[2:]
		dir := ""
		signIt := false
		for _, a := range args {
			if a == "--sign" || a == "-s" {
				signIt = true
			} else if dir == "" {
				dir = a
			}
		}
		if dir == "" {
			usage()
		}
		os.Exit(indexCmd(dir, signIt))
	case "publish":
		if len(os.Args) < 4 {
			usage()
		}
		os.Exit(publishCmd(os.Args[2], os.Args[3]))
	default:
		usage()
	}
}

// verifyIndex downloads and (if signed) verifies a remote's index.
// verifyIndex descarga y, si está firmado, verifica el índice de un remoto.
func verifyIndex(from string) (*index.Index, error) {
	src := &remote.Source{Base: from}
	data, sig, err := src.Index()
	if err != nil {
		return nil, fmt.Errorf("index: %w", err)
	}
	if len(sig) > 0 {
		signer, err := sign.VerifyData(data, sig, configDir())
		if err != nil {
			return nil, fmt.Errorf("index signature: %w", err)
		}
		fmt.Printf("[ok] index signed by %s\n", signer)
	} else {
		fmt.Println("[warn] index is not signed")
	}
	return index.Parse(data)
}

// installCmd verifies the index, checks the app is catalogued, then installs.
// installCmd verifica el índice, comprueba que la app está en él e instala.
func installCmd(id, from string) int {
	ix, err := verifyIndex(from)
	if err != nil {
		fmt.Printf("ERROR: %v\n", err)
		return 1
	}
	if _, ok := ix.Find(id); !ok {
		fmt.Printf("ERROR: %q is not in the index (%d apps)\n", id, len(ix.Apps))
		return 1
	}
	return installApp(id, from)
}

// searchCmd prints the index entries matching a query.
// searchCmd imprime las entradas del índice que casan con una búsqueda.
func searchCmd(query, from string) int {
	ix, err := verifyIndex(from)
	if err != nil {
		fmt.Printf("ERROR: %v\n", err)
		return 1
	}
	res := ix.Search(query)
	if len(res) == 0 {
		fmt.Printf("no matches for %q (%d apps)\n", query, len(ix.Apps))
		return 0
	}
	fmt.Printf("%-26s %-10s %-9s %-5s %s\n", "ID", "VERSION", "SIZE", "KIND", "NAME")
	for _, e := range res {
		kind := "CLI"
		if e.GUI {
			kind = "GUI"
		}
		fmt.Printf("%-26s %-10s %-9s %-5s %s\n",
			trunc(e.ID, 26), e.Version, appsize.Human(e.Size), kind, e.Name)
	}
	fmt.Printf("\n%d of %d apps\n", len(res), len(ix.Apps))
	return 0
}

// indexCmd rebuilds a remote's index.json and optionally signs it.
// indexCmd regenera el index.json de un remoto y, opcionalmente, lo firma.
func indexCmd(dir string, signIt bool) int {
	ix, err := index.Build(dir)
	if err != nil {
		fmt.Printf("ERROR: %v\n", err)
		return 1
	}
	p := filepath.Join(dir, "index.json")
	if err := ix.Save(p); err != nil {
		fmt.Printf("ERROR: %v\n", err)
		return 1
	}
	fmt.Printf("[ok] index: %s (%d apps)\n", p, len(ix.Apps))
	if signIt {
		sp, err := sign.SignFile(p, configDir())
		if err != nil {
			fmt.Printf("ERROR: signing index: %v\n", err)
			return 1
		}
		fmt.Printf("[ok] signed: %s\n", sp)
	}
	return 0
}

// trunc shortens s to n runes (with an ellipsis).
// trunc acorta s a n runas (con puntos suspensivos).
func trunc(s string, n int) string {
	r := []rune(s)
	if len(r) <= n {
		return s
	}
	if n <= 1 {
		return string(r[:n])
	}
	return string(r[:n-1]) + "…"
}

// installApp downloads the missing chunks/cells for id and installs it.
// installApp descarga los chunks/celdas que faltan para id y lo instala.
func installApp(id, from string) int {
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
	fmt.Printf("   index:   packbox-fetch index %s --sign\n", dir)
	fmt.Printf("   serve:   (cd %s && python3 -m http.server 8000)\n", dir)
	fmt.Printf("   install: packbox-fetch install %s --from http://HOST:8000\n", id)
	return 0
}
