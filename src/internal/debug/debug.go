// Package debug splits debug symbols out of an app's binary into a separate
// cell (a "cell-debug") and attaches them on demand.
// El paquete debug separa los símbolos de debug del binario de una app a una
// celda aparte (una "cell-debug") y los adjunta a demanda.
package debug

import (
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

// CellName is the debug cell name for an app id.
// CellName es el nombre de la celda de debug de un app id.
func CellName(appID string) string { return "org.debug." + appID }

// HasDebug reports whether the binary has DWARF/debug sections.
// HasDebug indica si el binario tiene secciones de debug (DWARF).
func HasDebug(bin string) bool {
	out, err := exec.Command("readelf", "-S", bin).Output()
	if err != nil {
		return false
	}
	return strings.Contains(string(out), ".debug_")
}

// ExtractDebug writes the debug info of bin to out (objcopy --only-keep-debug).
// ExtractDebug escribe la info de debug de bin en out (--only-keep-debug).
func ExtractDebug(bin, out string) error {
	if o, err := exec.Command("objcopy", "--only-keep-debug", bin, out).CombinedOutput(); err != nil {
		return fmt.Errorf("objcopy --only-keep-debug: %v: %s", err, o)
	}
	return nil
}

// StripAndLink strips the debug sections from bin and points its gnu-debuglink
// at dbg (so gdb finds the symbols when they are placed next to the binary).
// StripAndLink quita las secciones de debug de bin y apunta su gnu-debuglink a
// dbg (para que gdb encuentre los símbolos colocados junto al binario).
func StripAndLink(bin, dbg string) error {
	if o, err := exec.Command("objcopy", "--strip-debug", bin).CombinedOutput(); err != nil {
		return fmt.Errorf("objcopy --strip-debug: %v: %s", err, o)
	}
	if o, err := exec.Command("objcopy", "--add-gnu-debuglink="+dbg, bin).CombinedOutput(); err != nil {
		return fmt.Errorf("objcopy --add-gnu-debuglink: %v: %s", err, o)
	}
	return nil
}

// Attach copies the debug file of the cell `ref` next to treeBinary (as
// <treeBinary>.debug), where the binary's gnu-debuglink expects it. Returns the
// path of the attached symbols.
// Attach copia el archivo de debug de la celda `ref` junto a treeBinary (como
// <treeBinary>.debug), donde lo espera el gnu-debuglink. Devuelve la ruta.
func Attach(modsDir, ref, treeBinary string) (string, error) {
	name, ver := splitRef(ref)
	if name == "" || ver == "" {
		return "", fmt.Errorf("bad debug cell ref: %q", ref)
	}
	srcDir := filepath.Join(modsDir, name, ver)
	entries, err := os.ReadDir(srcDir)
	if err != nil {
		return "", fmt.Errorf("debug cell not found (%s): %w", ref, err)
	}
	var dbg string
	for _, e := range entries {
		if !e.IsDir() && strings.HasSuffix(e.Name(), ".debug") {
			dbg = filepath.Join(srcDir, e.Name())
			break
		}
	}
	if dbg == "" {
		return "", fmt.Errorf("no .debug file in cell %s", ref)
	}
	dst := treeBinary + ".debug"
	if err := copyFile(dbg, dst); err != nil {
		return "", err
	}
	return dst, nil
}

// splitRef splits "name@version".
// splitRef parte "name@version".
func splitRef(ref string) (string, string) {
	ref = strings.TrimSpace(ref)
	if i := strings.LastIndex(ref, "@"); i > 0 {
		return ref[:i], ref[i+1:]
	}
	return ref, ""
}

// copyFile copies src to dst.
// copyFile copia src a dst.
func copyFile(src, dst string) error {
	in, err := os.Open(src)
	if err != nil {
		return err
	}
	defer in.Close()
	out, err := os.OpenFile(dst, os.O_WRONLY|os.O_CREATE|os.O_TRUNC, 0644)
	if err != nil {
		return err
	}
	defer out.Close()
	_, err = io.Copy(out, in)
	return err
}
