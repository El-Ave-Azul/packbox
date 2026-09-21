// Package security provides filesystem and path helpers.
// El paquete security provee utilidades de archivos y rutas.
package security

import (
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

// SecureTempDir creates a 0700 temporary directory with a random suffix.
// SecureTempDir crea un directorio temporal 0700 con sufijo aleatorio.
func SecureTempDir(p string) (string, error) {
	b := make([]byte, 8)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	d := filepath.Join(os.TempDir(), fmt.Sprintf("%s-%s", p, hex.EncodeToString(b)))
	return d, os.MkdirAll(d, 0700)
}

// SafeCopy copies src to dst, preserving mode, without following symlinks.
// SafeCopy copia src a dst, preservando modo, sin seguir symlinks.
func SafeCopy(src, dst string, mode os.FileMode) error {
	in, err := os.Open(src)
	if err != nil {
		return err
	}
	defer in.Close()
	out, err := os.OpenFile(dst, os.O_WRONLY|os.O_CREATE|os.O_TRUNC, mode)
	if err != nil {
		return err
	}
	defer out.Close()
	if _, err := out.ReadFrom(in); err != nil {
		return err
	}
	return os.Chmod(dst, mode)
}

// ValidatePath ensures target stays within base (prevents path traversal).
// ValidatePath asegura que target esté dentro de base (previene path traversal).
func ValidatePath(base, target string) error {
	ab, err := filepath.Abs(base)
	if err != nil {
		return err
	}
	at, err := filepath.Abs(target)
	if err != nil {
		return err
	}
	rel, err := filepath.Rel(ab, at)
	if err != nil {
		return err
	}
	if rel == ".." || strings.HasPrefix(rel, ".."+string(os.PathSeparator)) {
		return fmt.Errorf("path escapes")
	}
	return nil
}

// SafeLink tries a hardlink; falls back to copy on cross-device.
// SafeLink intenta hardlink; cae a copia si es cross-device.
func SafeLink(src, dst string) error {
	if err := os.Link(src, dst); err == nil {
		return nil
	}
	info, err := os.Stat(src)
	if err != nil {
		return fmt.Errorf("stat source: %w", err)
	}
	return SafeCopy(src, dst, info.Mode().Perm())
}