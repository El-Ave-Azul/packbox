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

// Create writes a .desktop entry for an app and copies its icon, so it can be
// launched from the system menu. GUI apps run without a terminal; CLI apps run
// in one (Terminal=true). It returns (false, nil) only for a nil manifest.
// Create escribe una entrada .desktop para una app y copia su icono, para poder
// lanzarla desde el menú del sistema. Las apps GUI se ejecutan sin terminal; las
// CLI en una (Terminal=true). Devuelve (false, nil) solo si el manifiesto es nil.
func Create(home string, m *manifest.Manifest) (bool, error) {
	if m == nil {
		return false, nil
	}
	appID := m.Name
	if err := os.MkdirAll(desktopDir(home), 0755); err != nil {
		return false, err
	}
	if err := os.MkdirAll(iconsDir(home), 0755); err != nil {
		return false, err
	}

	// Icon: copy it into our icon dir and reference it by ABSOLUTE PATH, so it
	// renders with any icon theme (a bare name only resolves in the active one).
	// Icono: se copia a nuestro dir de iconos y se referencia por RUTA ABSOLUTA,
	// así se ve con cualquier tema (un nombre solo resuelve en el tema activo).
	iconRef := ""
	if src, ext := findIcon(home, m); src != "" {
		tgt := filepath.Join(iconsDir(home), "packbox-"+appID+ext)
		if err := copyFile(src, tgt); err == nil {
			iconRef = tgt
		}
	}
	if iconRef == "" {
		names := []string{"application-x-executable"}
		if !m.GUI {
			names = []string{"utilities-terminal", "application-x-executable"}
		}
		iconRef = resolveIcon(names...)
	}
	iconLine := ""
	if iconRef != "" {
		iconLine = "Icon=" + iconRef + "\n"
	}

	// CLI apps open in a terminal; GUI apps don't. WM class only matters for GUI.
	// Las apps CLI se abren en una terminal; las GUI no. WM class solo para GUI.
	terminal := "false"
	wmclass := "StartupWMClass=" + appID + "\n"
	// Categories: use the source app's own ones when known (from its .desktop),
	// else the name heuristic.
	// Categorías: usa las de la app original si se conocen (de su .desktop), si
	// no, la heurística por nombre.
	cats := strings.TrimSpace(m.Categories)
	if cats == "" {
		cats = categories(appID)
	}
	if !m.GUI {
		terminal = "true"
		wmclass = ""
		if cats == "" {
			cats = "Utility;"
		}
	}

	content := fmt.Sprintf(`[Desktop Entry]
Type=Application
Version=1.0
Name=%s
Comment=%s
Exec=%s %s
TryExec=%s
%sTerminal=%s
StartupNotify=true
%sCategories=%s
Keywords=packbox;%s;
X-Packbox-ID=%s
X-Packbox-Version=%s
X-Packbox-Toolkit=%s
`, sanitize(m.Name), sanitize(m.Description), runBin(home), appID, runBin(home),
		iconLine, terminal, wmclass, cats, appID, appID, sanitize(m.Version), sanitize(m.Toolkit))

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

// resolveIcon returns an absolute path to a real icon file for the first name
// found on the host (hicolor sizes and pixmaps), or "" if none exists. Used as
// a fallback so the .desktop entry is never blank.
// resolveIcon devuelve la ruta absoluta a un icono real para el primer nombre
// encontrado en el host (tamaños hicolor y pixmaps), o "" si no hay. Se usa como
// fallback para que la entrada .desktop nunca quede en blanco.
func resolveIcon(names ...string) string {
	dirs := []string{
		"/usr/share/icons/hicolor/256x256/apps",
		"/usr/share/icons/hicolor/128x128/apps",
		"/usr/share/icons/hicolor/64x64/apps",
		"/usr/share/icons/hicolor/scalable/apps",
		"/usr/share/pixmaps",
	}
	for _, n := range names {
		for _, d := range dirs {
			for _, e := range []string{".png", ".svg", ".xpm"} {
				p := filepath.Join(d, n+e)
				if fi, err := os.Stat(p); err == nil && !fi.IsDir() {
					return p
				}
			}
		}
	}
	return ""
}

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
