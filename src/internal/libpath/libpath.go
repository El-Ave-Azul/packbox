// Package libpath resolves host library search directories.
// El paquete libpath resuelve los directorios de búsqueda de librerías del host.
//
// Single source of truth for where Packbox looks for shared libraries on the
// host: used by packbox-verify, the sandbox and module creation.
// Fuente única de verdad de dónde busca Packbox librerías compartidas en el
// host: la usan packbox-verify, el sandbox y la creación de módulos.
package libpath

import (
	"fmt"
	"os"
	"path/filepath"
	"runtime"
)

// SearchPaths returns the arch-specific directories to search for host libs.
// Order matters: the first hit wins.
// SearchPaths devuelve los directorios, según arquitectura, donde buscar libs
// del host. El orden importa: gana la primera coincidencia.
func SearchPaths() []string {
	switch runtime.GOARCH {
	case "arm64":
		return []string{
			"/lib/aarch64-linux-gnu", "/usr/lib/aarch64-linux-gnu",
			"/lib64", "/usr/lib64", "/lib", "/usr/lib",
		}
	case "arm":
		return []string{
			"/lib/arm-linux-gnueabihf", "/usr/lib/arm-linux-gnueabihf",
			"/lib", "/usr/lib",
		}
	default:
		return []string{
			"/lib/x86_64-linux-gnu", "/usr/lib/x86_64-linux-gnu",
			"/lib64", "/usr/lib64", "/lib", "/usr/lib",
		}
	}
}

// Find locates a library file across SearchPaths.
// Find localiza un archivo de librería en SearchPaths.
func Find(lib string) (string, error) {
	for _, d := range SearchPaths() {
		p := filepath.Join(d, lib)
		if info, err := os.Stat(p); err == nil && !info.IsDir() {
			return p, nil
		}
	}
	return "", fmt.Errorf("not found: %s", lib)
}
