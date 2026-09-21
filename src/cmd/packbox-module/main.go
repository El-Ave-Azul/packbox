// packbox-module manages reusable lib modules and cells.
// packbox-module gestiona módulos de libs reutilizables y celdas.
package main

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"runtime"

	"github.com/packbox/packbox/internal/cas"
	"github.com/packbox/packbox/internal/hostcontract"
	"github.com/packbox/packbox/internal/libpath"
	"github.com/packbox/packbox/internal/security"
)

func usage() {
	fmt.Println("Usage: packbox-module list|create|cell")
	fmt.Println("  list                                   list modules/cells")
	fmt.Println("  create <bin> <name> <version>           module from a binary + its libs")
	fmt.Println("  cell <lib>...                           make one cell per lib, print refs (name@version)")
	os.Exit(1)
}

func main() {
	if len(os.Args) < 2 {
		usage()
	}
	home := os.Getenv("HOME")
	modsDir := filepath.Join(home, ".local/share/packbox/mods")

	switch os.Args[1] {
	case "list":
		fmt.Println("Modules:")
		fmt.Println("-----------------------------------------------------------")
		n := 0
		es, _ := os.ReadDir(modsDir)
		for _, e := range es {
			if !e.IsDir() {
				continue
			}
			vs, _ := os.ReadDir(filepath.Join(modsDir, e.Name()))
			for _, v := range vs {
				if v.IsDir() {
					fmt.Printf("  * %-40s v%s\n", e.Name(), v.Name())
					n++
				}
			}
		}
		fmt.Printf("Total: %d\n", n)

	case "create":
		if len(os.Args) < 5 {
			usage()
		}
		binPath, modName, modVer := os.Args[2], os.Args[3], os.Args[4]
		if _, err := os.Stat(binPath); err != nil {
			fmt.Printf("ERROR: bin does not exist: %s\n", binPath)
			os.Exit(1)
		}
		tmpParent := filepath.Join(home, ".local/share/packbox/tmp")
		_ = os.MkdirAll(tmpParent, 0755)
		tmp, err := os.MkdirTemp(tmpParent, "mod-")
		if err != nil {
			fmt.Printf("ERROR: %v\n", err)
			os.Exit(1)
		}
		defer os.RemoveAll(tmp)

		binDir := filepath.Join(tmp, "bin")
		_ = os.MkdirAll(binDir, 0755)
		binCopy := filepath.Join(binDir, filepath.Base(binPath))
		if err := security.SafeCopy(binPath, binCopy, 0755); err != nil {
			fmt.Printf("ERROR: copy bin: %v\n", err)
			os.Exit(1)
		}

		libDir := filepath.Join(tmp, "lib")
		_ = os.MkdirAll(libDir, 0755)
		libs, _ := hostcontract.AnalyzeDependencies(binPath)
		cnt := 0
		for _, l := range libs {
			lp, err := libpath.Find(l)
			if err != nil {
				continue
			}
			if err := security.SafeCopy(lp, filepath.Join(libDir, l), 0644); err == nil {
				cnt++
			}
		}
		mm := map[string]interface{}{
			"schema_version": "1.6",
			"type":           "module",
			"name":           modName,
			"version":        modVer,
			"entrypoint":     "/app/bin/" + filepath.Base(binPath),
			"arch":           runtime.GOARCH,
			"libs_count":     cnt,
		}
		writeManifest(tmp, mm)
		dest := filepath.Join(modsDir, modName, modVer)
		_ = os.MkdirAll(filepath.Dir(dest), 0755)
		_ = os.RemoveAll(dest)
		if err := os.Rename(tmp, dest); err != nil {
			fmt.Printf("ERROR: %v\n", err)
			os.Exit(1)
		}
		fmt.Printf("[ok] module %s v%s (%d libs)\n", modName, modVer, cnt)

	case "cell":
		// One cell per lib, versioned by content hash (idempotent). Prints one
		// "name@version" ref per line for the packager to collect.
		// Una celda por lib, versionada por hash de contenido (idempotente).
		// Imprime un ref "name@version" por línea para que el packager lo recoja.
		if len(os.Args) < 3 {
			usage()
		}
		seen := map[string]bool{}
		for _, lib := range os.Args[2:] {
			real, err := filepath.EvalSymlinks(lib)
			if err != nil {
				real = lib
			}
			if seen[real] {
				continue
			}
			seen[real] = true
			ref, err := makeCell(modsDir, real)
			if err != nil {
				fmt.Fprintf(os.Stderr, "WARN cell %s: %v\n", lib, err)
				continue
			}
			fmt.Println(ref)
		}

	default:
		usage()
	}
}

// writeManifest writes a map as pretty JSON to <dir>/manifest.json.
// writeManifest escribe un map como JSON indentado en <dir>/manifest.json.
func writeManifest(dir string, mm map[string]interface{}) {
	data, _ := json.MarshalIndent(mm, "", "  ")
	_ = os.WriteFile(filepath.Join(dir, "manifest.json"), data, 0644)
}

// makeCell creates (idempotently) a cell for one lib and returns its ref.
// makeCell crea (idempotentemente) una celda para una lib y devuelve su ref.
func makeCell(modsDir, libPath string) (string, error) {
	base := filepath.Base(libPath)
	h, err := cas.HashFile(libPath)
	if err != nil {
		return "", err
	}
	name := cellName(base)
	ver := h[:12]
	dest := filepath.Join(modsDir, name, ver)
	libDir := filepath.Join(dest, "lib")
	target := filepath.Join(libDir, base)
	ref := name + "@" + ver

	if _, err := os.Stat(target); err == nil {
		return ref, nil // already present (same content -> same hash -> same cell)
	}
	if err := os.MkdirAll(libDir, 0755); err != nil {
		return "", err
	}
	if err := security.SafeCopy(libPath, target, 0644); err != nil {
		return "", err
	}
	writeManifest(dest, map[string]interface{}{
		"schema_version": "1.6",
		"type":           "cell",
		"name":           name,
		"version":        ver,
		"lib":            base,
		"blake3":         h,
	})
	return ref, nil
}

// cellName derives a cell name from a lib basename (e.g. libgtk-4.so.1).
// cellName deriva el nombre de una celda a partir del basename de una lib.
func cellName(base string) string {
	out := make([]byte, 0, len(base)+8)
	out = append(out, "org.lib."...)
	for i := 0; i < len(base); i++ {
		c := base[i]
		ok := (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') ||
			c == '.' || c == '_' || c == '-'
		if ok {
			out = append(out, c)
		} else {
			out = append(out, '-')
		}
	}
	// The prefix "org.lib." already starts alphanumeric, so validName holds.
	// El prefijo "org.lib." ya empieza alfanumérico, así que validName se cumple.
	return string(out)
}
