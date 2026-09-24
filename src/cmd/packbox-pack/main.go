// packbox-pack creates a manifest from a directory tree.
// packbox-pack crea un manifiesto a partir de un árbol de directorios.
package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"strings"

	"github.com/packbox/packbox/internal/cas"
	"github.com/packbox/packbox/internal/chunker"
	"github.com/packbox/packbox/internal/debug"
	"github.com/packbox/packbox/internal/hostcontract"
	"github.com/packbox/packbox/internal/manifest"
)

// singleChunkMax: files up to this size are stored as a single chunk (so
// install can hardlink them, which preserves cross-app sharing). Larger files
// use content-defined chunking (chunk-level dedup + cheap deltas). Set high
// enough that typical libraries stay one chunk and keep sharing; only really
// large files (big bundles/binaries) get chunked.
// singleChunkMax: los archivos hasta este tamaño se guardan como un solo chunk
// (así install puede hardlinkearlos, preservando la compartición entre apps).
// Los archivos mayores usan CDC (dedup por chunk + deltas baratos). Alto para
// que las librerías típicas queden como archivo único y mantengan la
// compartición; solo los archivos realmente grandes se fragmentan.
const singleChunkMax = 32 << 20

var strFlags = map[string]bool{
	"--name": true, "-name": true,
	"--version": true, "-version": true,
	"--description": true, "-description": true,
	"--entrypoint": true, "-entrypoint": true,
	"--mods": true, "-mods": true,
	"--toolkit": true, "-toolkit": true,
	"--icon": true, "-icon": true,
	"--categories": true, "-categories": true,
	"--sandbox": true, "-sandbox": true,
}

// pre splits positional args from flags (allows dir before flags).
// pre separa args posicionales de flags (permite dir antes de flags).
func pre() (string, []string) {
	var dir string
	var flags []string
	a := os.Args[1:]
	for i := 0; i < len(a); i++ {
		if strings.HasPrefix(a[i], "-") {
			flags = append(flags, a[i])
			if !strings.Contains(a[i], "=") && strFlags[a[i]] && i+1 < len(a) {
				i++
				flags = append(flags, a[i])
			}
		} else if dir == "" {
			dir = a[i]
		}
	}
	return dir, flags
}

func main() {
	dir, flags := pre()
	os.Args = append([]string{os.Args[0]}, flags...)

	name := flag.String("name", "", "")
	ver := flag.String("version", "1.0.0", "")
	desc := flag.String("description", "", "")
	ep := flag.String("entrypoint", "", "")
	mods := flag.String("mods", "", "")
	gui := flag.Bool("gui", false, "")
	tk := flag.String("toolkit", "", "")
	icon := flag.String("icon", "", "")
	categories := flag.String("categories", "", "")
	sbCaps := flag.String("sandbox", "", "")
	network := flag.Bool("network", false, "")
	x11 := flag.Bool("x11", false, "")
	noDebug := flag.Bool("no-debug", false, "")
	flag.Parse()

	if *name == "" || dir == "" {
		fmt.Println("ERROR: --name and directory required")
		os.Exit(1)
	}
	if _, err := os.Stat(dir); os.IsNotExist(err) {
		fmt.Printf("ERROR: does not exist: %s\n", dir)
		os.Exit(1)
	}

	home := os.Getenv("HOME")
	store, err := cas.NewStore(filepath.Join(home, ".local/share/packbox/store"))
	if err != nil {
		fmt.Printf("ERROR: %v\n", err)
		os.Exit(1)
	}

	fmt.Printf("[pack] %s v%s\n", *name, *ver)

	binDir := filepath.Join(dir, "bin")
	mainBin := findMainBin(binDir)
	var epPath string
	if *ep != "" {
		epPath = *ep
	} else if mainBin != "" {
		epPath = "/app/bin/" + filepath.Base(mainBin)
	} else if _, err := os.Stat(binDir); err == nil {
		fmt.Println("ERROR: no executable found")
		os.Exit(1)
	} else {
		fmt.Println("ERROR: no bin/ and no --entrypoint")
		os.Exit(1)
	}

	// Host contract: libs delegated to the host + the symbols required from
	// them (for the ABI check done at install/verify time).
	// Host contract: libs delegadas al host + los símbolos requeridos de ellas
	// (para el chequeo de ABI en install/verify).
	delegate := []string{}
	required := map[string][]string{}
	if mainBin != "" {
		if deps, err := hostcontract.AnalyzeDependencies(mainBin); err == nil {
			delegate = hostcontract.FilterDelegatable(deps)
		}
		if syms, err := hostcontract.ExtractRequiredSymbols(mainBin); err == nil {
			for _, l := range delegate {
				if s := syms[l]; len(s) > 0 {
					required[l] = s
				}
			}
		}
	}

	// Debug symbols: split them into a separate cell (cell-debug) so the app
	// stays stripped and the symbols are only fetched when debugging.
	// Símbolos de debug: sepáralos a una celda aparte (cell-debug) para que la
	// app quede stripped y los símbolos solo se traigan al depurar.
	var dbgInfo *manifest.DebugInfo
	if !*noDebug && mainBin != "" && debug.HasDebug(mainBin) {
		modsDir := filepath.Join(home, ".local/share/packbox/mods")
		if os.MkdirAll(modsDir, 0755) == nil {
			if tmpDir, err := os.MkdirTemp(modsDir, "dbg-"); err == nil {
				tmpFile := filepath.Join(tmpDir, "debug")
				if err := debug.ExtractDebug(mainBin, tmpFile); err == nil {
					h, _ := cas.HashFile(tmpFile)
					cellName := debug.CellName(*name)
					ver := h[:12]
					cellDir := filepath.Join(modsDir, cellName, ver)
					_ = os.MkdirAll(cellDir, 0755)
					dbgDst := filepath.Join(cellDir, filepath.Base(mainBin)+".debug")
					if err := os.Rename(tmpFile, dbgDst); err == nil {
						if err := debug.StripAndLink(mainBin, dbgDst); err == nil {
							if rel, err := filepath.Rel(dir, mainBin); err == nil {
								dbgInfo = &manifest.DebugInfo{Cell: cellName + "@" + ver, Binary: rel}
								data, _ := json.MarshalIndent(map[string]interface{}{
									"type": "cell-debug", "name": cellName, "version": ver, "binary": rel,
								}, "", "  ")
								_ = os.WriteFile(filepath.Join(cellDir, "manifest.json"), data, 0644)
								fmt.Printf("   Debug: %s (symbols split out)\n", dbgInfo.Cell)
							}
						} else {
							fmt.Printf("   WARN strip-debug: %v\n", err)
						}
					}
				}
				os.RemoveAll(tmpDir)
			}
		}
	}

	files := map[string]manifest.FileInfo{}
	count := 0
	links := 0
	_ = filepath.Walk(dir, func(p string, i os.FileInfo, e error) error {
		if e != nil || i.IsDir() || filepath.Base(p) == "manifest.json" {
			return nil
		}
		rel, _ := filepath.Rel(dir, p)

		// Preserve symlinks without copying target content.
		// Preserva symlinks sin copiar el contenido del target.
		if i.Mode()&os.ModeSymlink != 0 {
			target, err := os.Readlink(p)
			if err != nil {
				fmt.Printf("   WARN readlink %s: %v\n", rel, err)
				return nil
			}
			files[rel] = manifest.FileInfo{
				Size: 0,
				Mode: "0777",
				Link: target,
			}
			links++
			count++
			return nil
		}

		mode := fmt.Sprintf("%04o", i.Mode().Perm())
		var chunks []string
		if i.Size() > singleChunkMax {
			// Large file: content-defined chunking (dedup + deltas).
			// Archivo grande: chunking por contenido (dedup + deltas).
			f, err := os.Open(p)
			if err != nil {
				fmt.Printf("   WARN %s: %v\n", rel, err)
				return nil
			}
			chunks, err = store.StoreChunks(f, chunker.DefaultConfig())
			f.Close()
			if err != nil {
				fmt.Printf("   WARN %s: %v\n", rel, err)
				return nil
			}
		} else {
			// Small file: one chunk == whole file, so install can hardlink it.
			// Archivo pequeño: un chunk == el archivo entero, así install lo
			// puede hardlinkear.
			h, err := store.StoreFile(p)
			if err != nil {
				fmt.Printf("   WARN %s: %v\n", rel, err)
				return nil
			}
			chunks = []string{h}
		}
		files[rel] = manifest.FileInfo{
			Chunks: chunks,
			Size:   i.Size(),
			Mode:   mode,
		}
		count++
		return nil
	})

	var mlist []string
	if *mods != "" {
		for _, m := range strings.Split(*mods, ",") {
			if m = strings.TrimSpace(m); m != "" {
				mlist = append(mlist, m)
			}
		}
	}

	appM := &manifest.Manifest{
		SchemaVersion: "1.6",
		Name:          *name,
		Version:       *ver,
		Description:   *desc,
		Entrypoint:    epPath,
		Arch:          runtime.GOARCH,
		GUI:           *gui,
		Toolkit:       *tk,
		Icon:          *icon,
		Categories:    *categories,
		Sandbox:       splitList(*sbCaps),
		Network:       *network,
		X11:           *x11,
		Layers:        manifest.Layers{App: manifest.AppLayer{Files: files}},
		Mods:          mlist,
		HostContract: manifest.HostContract{
			Version:         "1",
			Delegate:        delegate,
			RequiredSymbols: required,
			FallbackMods:    map[string]string{},
		},
		Debug: dbgInfo,
	}
	mp := filepath.Join(dir, "manifest.json")
	if err := appM.Save(mp); err != nil {
		fmt.Printf("ERROR: %v\n", err)
		os.Exit(1)
	}
	fmt.Printf("[ok] %s  files=%d symlinks=%d arch=%s\n", mp, count, links, runtime.GOARCH)
}

// findMainBin returns the largest executable file under binDir (the app's main
// binary), or "" if none.
// findMainBin devuelve el mayor ejecutable bajo binDir (el binario principal de
// la app), o "" si no hay.
func findMainBin(binDir string) string {
	var big string
	var bs int64
	_ = filepath.Walk(binDir, func(p string, i os.FileInfo, e error) error {
		if e != nil || i.IsDir() {
			return nil
		}
		if i.Mode()&0111 != 0 && i.Size() > bs {
			bs = i.Size()
			big = p
		}
		return nil
	})
	return big
}

// splitList splits a comma-separated list, trimming blanks.
// splitList parte una lista separada por comas, ignorando vacíos.
func splitList(s string) []string {
	var out []string
	for _, p := range strings.Split(s, ",") {
		if p = strings.TrimSpace(p); p != "" {
			out = append(out, p)
		}
	}
	return out
}
