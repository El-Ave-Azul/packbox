// Package desktop creates and removes XDG .desktop entries for Packbox apps.
// El paquete desktop crea y elimina entradas XDG .desktop para apps de Packbox.
//
// Single source of truth: both `packbox-install` (on install) and the shell
// frontend (via `packbox-install --desktop` / `--remove-desktop`) go through
// this package.
// Fuente única de verdad: tanto `packbox-install` (al instalar) como el
// frontend shell (vía `packbox-install --desktop` / `--remove-desktop`) pasan
// por este paquete.
package desktop

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"github.com/packbox/packbox/internal/manifest"
)

// ─── Paths ──────────────────────────────────────────────────────────────────

func appsDir(home string) string {
	return filepath.Join(home, ".local/share/packbox/apps")
}
func desktopDir(home string) string {
	return filepath.Join(home, ".local/share/applications")
}
func iconsBase(home string) string {
	return filepath.Join(home, ".local/share/icons/hicolor")
}
func iconsDir(home string) string {
	return filepath.Join(iconsBase(home), "256x256/apps")
}
func runBin(home string) string {
	return filepath.Join(home, ".packbox/bin/packbox-run")
}

// DesktopPath returns the .desktop file path for an app id.
// DesktopPath devuelve la ruta del archivo .desktop de un app id.
func DesktopPath(home, appID string) string {
	return filepath.Join(desktopDir(home), "packbox-"+appID+".desktop")
}

// ─── Create ─────────────────────────────────────────────────────────────────

// Create writes a .desktop entry for a GUI app and copies its icon.
// It is a no-op returning (false, nil) for non-GUI apps.
// Create escribe una entrada .desktop para una app GUI y copia su icono.
// No hace nada, devolviendo (false, nil), para apps no-GUI.
func Create(home string, m *manifest.Manifest) (bool, error) {
	if m == nil || !m.GUI {
		return false, nil
	}
	appID := m.Name
	if err := os.MkdirAll(desktopDir(home), 0755); err != nil {
		return false, err
	}
	if err := os.MkdirAll(iconsDir(home), 0755); err != nil {
		return false, err
	}

	iconRef := "application-x-executable"
	if src, ext := findIcon(home, m); src != "" {
		tgt := filepath.Join(iconsDir(home), "packbox-"+appID+ext)
		if err := copyFile(src, tgt); err == nil {
			iconRef = "packbox-" + appID
		}
	}

	content := fmt.Sprintf(`[Desktop Entry]
Type=Application
Version=1.0
Name=%s
Comment=%s
Exec=%s %s
TryExec=%s
Icon=%s
Terminal=false
StartupNotify=true
StartupWMClass=%s
Categories=%s
Keywords=packbox;%s;
X-Packbox-ID=%s
X-Packbox-Version=%s
X-Packbox-Toolkit=%s
`, sanitize(m.Name), sanitize(m.Description), runBin(home), appID, runBin(home),
		iconRef, appID, categories(appID), appID, appID, sanitize(m.Version), sanitize(m.Toolkit))

	df := DesktopPath(home, appID)
	if err := os.WriteFile(df, []byte(content), 0644); err != nil {
		return false, err
	}
	_ = os.Chmod(df, 0755)
	refreshCaches(home)
	return true, nil
}

// Remove deletes the .desktop entry and icon for an app id.
// Remove elimina la entrada .desktop y el icono de un app id.
func Remove(home, appID string) error {
	if appID == "" {
		return fmt.Errorf("empty app id")
	}
	if err := os.Remove(DesktopPath(home, appID)); err != nil && !os.IsNotExist(err) {
		return err
	}
	for _, ext := range []string{".png", ".svg", ".xpm"} {
		_ = os.Remove(filepath.Join(iconsDir(home), "packbox-"+appID+ext))
	}
	refreshCaches(home)
	return nil
}

// ─── Icon discovery ─────────────────────────────────────────────────────────

// findIcon returns the best icon source path and its extension.
// findIcon devuelve la mejor ruta de icono y su extensión.
func findIcon(home string, m *manifest.Manifest) (string, string) {
	tree := filepath.Join(appsDir(home), m.Name, "tree")

	// 1. Explicit icon from the manifest.
	// 1. Icono explícito del manifiesto.
	if m.Icon != "" {
		p := m.Icon
		switch {
		case filepath.IsAbs(p):
			// use as-is
		case strings.HasPrefix(p, "/app/"):
			p = filepath.Join(tree, strings.TrimPrefix(p, "/app/"))
		default:
			p = filepath.Join(tree, p)
		}
		if fi, err := os.Stat(p); err == nil && !fi.IsDir() {
			return p, iconExt(p)
		}
	}

	// 2. Best match under tree/ by score.
	// 2. Mejor coincidencia bajo tree/ por puntuación.
	best, bestScore := "", -1
	_ = filepath.Walk(tree, func(p string, fi os.FileInfo, err error) error {
		if err != nil || fi.IsDir() {
			return nil
		}
		ext := strings.ToLower(filepath.Ext(p))
		if ext != ".png" && ext != ".svg" {
			return nil
		}
		score := 0
		if strings.Contains(strings.ToLower(filepath.Base(p)), strings.ToLower(m.Name)) {
			score += 1000
		}
		if strings.Contains(p, "256x256") {
			score += 200
		}
		if strings.Contains(p, "128x128") {
			score += 150
		}
		if strings.Contains(p, "scalable") {
			score += 120
		}
		if score > bestScore {
			bestScore, best = score, p
		}
		return nil
	})
	if best != "" {
		return best, iconExt(best)
	}
	return "", ""
}

// iconExt returns a lowercase extension with a leading dot, defaulting to .png.
// iconExt devuelve una extensión en minúsculas con punto, por defecto .png.
func iconExt(p string) string {
	ext := strings.ToLower(filepath.Ext(p))
	if ext == "" {
		return ".png"
	}
	return ext
}

// ─── Categories ─────────────────────────────────────────────────────────────

// categories maps an app id to freedesktop categories.
// categories mapea un app id a categorías freedesktop.
func categories(appID string) string {
	a := strings.ToLower(appID)
	switch {
	case containsAny(a, "firefox", "chrome", "chromium", "brave", "browser", "opera"):
		return "Network;WebBrowser;"
	case containsAny(a, "thunderbird", "mail"):
		return "Network;Email;"
	case containsAny(a, "vlc", "mpv", "celluloid", "media", "audio"):
		return "AudioVideo;Player;"
	case containsAny(a, "gimp", "inkscape", "photo", "image"):
		return "Graphics;"
	case containsAny(a, "libreoffice", "writer", "calc", "impress"):
		return "Office;"
	case containsAny(a, "code", "editor", "vim", "emacs"):
		return "Development;TextEditor;"
	case containsAny(a, "terminal", "console"):
		return "System;TerminalEmulator;"
	}
	return "Utility;"
}

func containsAny(s string, subs ...string) bool {
	for _, sub := range subs {
		if strings.Contains(s, sub) {
			return true
		}
	}
	return false
}

// ─── Helpers ────────────────────────────────────────────────────────────────

// sanitize strips characters that would break the .desktop format.
// sanitize elimina caracteres que romperían el formato .desktop.
func sanitize(s string) string {
	s = strings.ReplaceAll(s, "\r", " ")
	s = strings.ReplaceAll(s, "\n", " ")
	return s
}

func copyFile(src, dst string) error {
	data, err := os.ReadFile(src)
	if err != nil {
		return err
	}
	return os.WriteFile(dst, data, 0644)
}

// refreshCaches best-effort refreshes the desktop and icon caches.
// refreshCaches refresca las cachés de escritorio e iconos (best-effort).
func refreshCaches(home string) {
	if p, err := exec.LookPath("update-desktop-database"); err == nil {
		_ = exec.Command(p, desktopDir(home)).Run()
	}
	if p, err := exec.LookPath("gtk-update-icon-cache"); err == nil {
		_ = exec.Command(p, "-f", "-t", iconsBase(home)).Run()
	}
	if p, err := exec.LookPath("xdg-desktop-menu"); err == nil {
		_ = exec.Command(p, "forceupdate").Run()
	}
}
