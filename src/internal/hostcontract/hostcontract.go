// Package hostcontract handles host-library delegation.
// El paquete hostcontract gestiona la delegación de librerías al host.
package hostcontract

import (
	"bufio"
	"os/exec"
	"strings"
)

// AllowedLibs lists libs that are safe to delegate to the host.
// AllowedLibs lista librerías seguras de delegar al host.
var AllowedLibs = []string{
	"libc.so.6", "libm.so.6", "libdl.so.2", "libpthread.so.0", "libz.so.1",
}

// AnalyzeDependencies runs ldd on a binary and returns the dep names.
// AnalyzeDependencies corre ldd sobre un binario y devuelve las deps.
func AnalyzeDependencies(p string) ([]string, error) {
	out, err := exec.Command("ldd", p).Output()
	if err != nil {
		return nil, err
	}
	var deps []string
	s := bufio.NewScanner(strings.NewReader(string(out)))
	for s.Scan() {
		l := s.Text()
		if strings.Contains(l, "=>") {
			parts := strings.Fields(l)
			if len(parts) >= 1 && !strings.HasPrefix(parts[0], "linux-vdso") {
				deps = append(deps, parts[0])
			}
		}
	}
	return deps, nil
}

// ExtractRequiredSymbols returns, per host lib, the symbols a binary requires.
// ExtractRequiredSymbols devuelve, por lib del host, los símbolos que requiere
// un binario.
func ExtractRequiredSymbols(p string) (map[string][]string, error) {
	out, err := exec.Command("readelf", "-sW", p).Output()
	if err != nil {
		return nil, err
	}
	return ParseRequiredSymbols(out), nil
}

// ParseRequiredSymbols parses `readelf -sW` output for undefined symbols and
// groups them by the host lib each is versioned against.
// ParseRequiredSymbols parsea la salida de `readelf -sW` buscando símbolos
// indefinidos y los agrupa por la lib del host contra la que están versionados.
func ParseRequiredSymbols(out []byte) map[string][]string {
	sym := map[string][]string{}
	seen := map[string]bool{}
	s := bufio.NewScanner(strings.NewReader(string(out)))
	s.Buffer(make([]byte, 0, 64*1024), 1<<20)
	for s.Scan() {
		f := strings.Fields(s.Text())
		if len(f) < 8 || f[6] != "UND" {
			continue
		}
		name := f[7]
		at := strings.Index(name, "@")
		if at <= 0 {
			continue
		}
		base := name[:at]
		ver := strings.TrimPrefix(name[at+1:], "@") // "@@VER" -> "VER"
		lib := versionToLib(ver)
		if lib == "" {
			continue
		}
		key := lib + "|" + base
		if seen[key] {
			continue
		}
		seen[key] = true
		sym[lib] = append(sym[lib], base)
	}
	return sym
}

// versionToLib maps a symbol version tag to the host lib that provides it.
// versionToLib mapea una etiqueta de versión de símbolo a la lib del host que
// lo provee.
func versionToLib(ver string) string {
	switch {
	case strings.HasPrefix(ver, "GLIBC_"):
		return "libc.so.6"
	case strings.HasPrefix(ver, "GLIBCXX_"), strings.HasPrefix(ver, "CXXABI_"):
		return "libstdc++.so.6"
	case strings.HasPrefix(ver, "GCC_"):
		return "libgcc_s.so.1"
	case strings.HasPrefix(ver, "ZLIB_"):
		return "libz.so.1"
	}
	return ""
}

// FilterDelegatable keeps only allowed libs.
// FilterDelegatable conserva solo las libs permitidas.
func FilterDelegatable(d []string) []string {
	var r []string
	for _, x := range d {
		for _, a := range AllowedLibs {
			if x == a {
				r = append(r, x)
				break
			}
		}
	}
	return r
}

// DefinedSymbols returns the base names of the dynamic symbols libPath defines.
// DefinedSymbols devuelve los nombres base de los símbolos dinámicos que
// libPath define.
func DefinedSymbols(libPath string) (map[string]bool, error) {
	out, err := exec.Command("readelf", "-sW", libPath).Output()
	if err != nil {
		return nil, err
	}
	defined := map[string]bool{}
	s := bufio.NewScanner(strings.NewReader(string(out)))
	s.Buffer(make([]byte, 0, 64*1024), 1<<20)
	for s.Scan() {
		f := strings.Fields(s.Text())
		if len(f) < 8 || f[6] == "UND" {
			continue
		}
		name := f[7]
		if at := strings.Index(name, "@"); at > 0 {
			name = name[:at]
		}
		defined[name] = true
	}
	return defined, nil
}

// HasSymbols returns the required symbols that the dynamic symbol table of
// libPath does not define (an ABI-compatibility check).
// HasSymbols devuelve los símbolos requeridos que la tabla de símbolos
// dinámicos de libPath no define (chequeo de compatibilidad de ABI).
func HasSymbols(libPath string, required []string) ([]string, error) {
	defined, err := DefinedSymbols(libPath)
	if err != nil {
		return nil, err
	}
	var missing []string
	for _, r := range required {
		if !defined[r] {
			missing = append(missing, r)
		}
	}
	return missing, nil
}