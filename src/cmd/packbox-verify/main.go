// packbox-verify checks that an installed app's libs are resolvable.
// packbox-verify comprueba que las libs de una app instalada se resuelvan.
package main

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"

	"github.com/packbox/packbox/internal/hostcontract"
	"github.com/packbox/packbox/internal/libpath"
	"github.com/packbox/packbox/internal/manifest"
)

func main() {
	if len(os.Args) < 2 {
		fmt.Println("Usage: packbox-verify <app-id>")
		os.Exit(1)
	}
	id := os.Args[1]
	home := os.Getenv("HOME")
	appDir := filepath.Join(home, ".local/share/packbox/apps", id)
	m, err := manifest.Load(filepath.Join(appDir, "manifest.json"))
	if err != nil {
		fmt.Printf("ERROR: %v\n", err)
		os.Exit(1)
	}

	// Host-contract ABI check: the host must provide every delegated lib and
	// the symbols the app requires from them. GLIBC-versioned symbols may live
	// in libc or libm, so required symbols are checked against the union of the
	// delegated libs rather than per lib.
	// Chequeo ABI del host contract: el host debe proveer cada lib delegada y
	// los símbolos que la app requiere de ellas. Los símbolos con versión GLIBC
	// pueden estar en libc o en libm, así que se comprueban contra la unión de
	// las libs delegadas, no por lib.
	if len(m.HostContract.RequiredSymbols) > 0 {
		defined := map[string]bool{}
		for _, lib := range m.HostContract.Delegate {
			hp, err := libpath.Find(lib)
			if err != nil {
				fmt.Printf("[fail] host lib missing: %s\n", lib)
				os.Exit(1)
			}
			defs, err := hostcontract.DefinedSymbols(hp)
			if err != nil {
				fmt.Printf("[fail] %s: %v\n", lib, err)
				os.Exit(1)
			}
			for s := range defs {
				defined[s] = true
			}
		}
		var missing []string
		seen := map[string]bool{}
		for _, syms := range m.HostContract.RequiredSymbols {
			for _, s := range syms {
				if !seen[s] {
					seen[s] = true
					if !defined[s] {
						missing = append(missing, s)
					}
				}
			}
		}
		if len(missing) > 0 {
			fmt.Printf("[fail] %d symbols missing (ABI)\n", len(missing))
			for _, s := range missing {
				fmt.Printf("   [X] %s\n", s)
			}
			os.Exit(1)
		}
	}

	if m.Portable {
		fmt.Printf("[ok] %s PORTABLE\n", id)
		os.Exit(0)
	}
	if m.Arch != "" && m.Arch != runtime.GOARCH {
		fmt.Printf("[fail] arch mismatch: manifest=%s host=%s\n", m.Arch, runtime.GOARCH)
		os.Exit(1)
	}
	treeDir := filepath.Join(appDir, "tree")
	bin := filepath.Join(treeDir, strings.TrimPrefix(m.Entrypoint, "/app"))
	if strings.HasSuffix(bin, "launcher.sh") {
		entries, _ := os.ReadDir(filepath.Join(treeDir, "bin"))
		for _, e := range entries {
			if !e.IsDir() && e.Name() != "launcher.sh" {
				if i, _ := e.Info(); i.Mode()&0111 != 0 {
					bin = filepath.Join(treeDir, "bin", e.Name())
					break
				}
			}
		}
	}
	if _, err := os.Stat(bin); err != nil {
		fmt.Printf("[fail] binary not found: %s\n", bin)
		os.Exit(2)
	}
	out, err := exec.Command("ldd", bin).Output()
	if err != nil {
		fmt.Printf("[fail] ldd: %v\n", err)
		os.Exit(2)
	}
	var missing []string
	ok := 0
	for _, l := range strings.Split(string(out), "\n") {
		if !strings.Contains(l, "=>") {
			continue
		}
		parts := strings.Fields(l)
		if len(parts) < 1 || strings.HasPrefix(parts[0], "linux-vdso") {
			continue
		}
		// The dynamic loader is listed as an absolute path; check it directly
		// instead of joining it with the library search directories.
		// El cargador dinámico aparece con ruta absoluta; compruébalo directo
		// en vez de unirlo a los directorios de búsqueda de libs.
		if filepath.IsAbs(parts[0]) {
			target := parts[0]
			if len(parts) >= 3 {
				target = parts[2]
			}
			if _, err := os.Stat(target); err == nil {
				ok++
			} else {
				missing = append(missing, target)
			}
			continue
		}
		found := false
		for _, d := range libpath.SearchPaths() {
			if _, err := os.Stat(filepath.Join(d, parts[0])); err == nil {
				found = true
				ok++
				break
			}
		}
		if !found {
			missing = append(missing, parts[0])
		}
	}
	if len(missing) == 0 {
		fmt.Printf("[ok] COMPATIBLE  libs=%d\n", ok)
		os.Exit(0)
	}
	fmt.Printf("[fail] missing %d libs\n", len(missing))
	for _, x := range missing {
		fmt.Printf("   [X] %s\n", x)
	}
	os.Exit(1)
}