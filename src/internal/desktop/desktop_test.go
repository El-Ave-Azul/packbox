// Tests for the desktop package.
// Tests para el paquete desktop.
package desktop

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/packbox/packbox/internal/manifest"
)

func TestCreateSkipsNonGUI(t *testing.T) {
	home := t.TempDir()
	m := &manifest.Manifest{Name: "cli-app", GUI: false}
	created, err := Create(home, m)
	if err != nil || created {
		t.Fatalf("Create(non-GUI) = %v, %v; want false, nil", created, err)
	}
	if _, err := os.Stat(DesktopPath(home, "cli-app")); err == nil {
		t.Fatal("desktop file created for non-GUI app")
	}
}

func TestCreateGUIFindsIconAndWritesEntry(t *testing.T) {
	home := t.TempDir()
	m := &manifest.Manifest{
		Name:        "org.example.App",
		Version:     "1.2.3",
		Description: "Example app",
		GUI:         true,
		Toolkit:     "GTK3",
	}
	tree := filepath.Join(home, ".local/share/packbox/apps", m.Name, "tree", "share", "icons", "256x256")
	if err := os.MkdirAll(tree, 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(tree, "org.example.App.png"), []byte("PNG"), 0644); err != nil {
		t.Fatal(err)
	}

	created, err := Create(home, m)
	if err != nil || !created {
		t.Fatalf("Create = %v, %v; want true, nil", created, err)
	}
	data, err := os.ReadFile(DesktopPath(home, m.Name))
	if err != nil {
		t.Fatal(err)
	}
	runBin := filepath.Join(home, ".packbox/bin/packbox-run")
	for _, want := range []string{
		"Name=org.example.App",
		"Exec=" + runBin + " " + m.Name,
		"Icon=packbox-" + m.Name,
		"StartupWMClass=" + m.Name,
		"Keywords=packbox;" + m.Name + ";",
		"X-Packbox-Version=1.2.3",
		"X-Packbox-Toolkit=GTK3",
	} {
		if !strings.Contains(string(data), want) {
			t.Fatalf("desktop entry missing %q\n---\n%s", want, data)
		}
	}
	iconDst := filepath.Join(home, ".local/share/icons/hicolor/256x256/apps", "packbox-"+m.Name+".png")
	if _, err := os.Stat(iconDst); err != nil {
		t.Fatalf("icon not copied: %v", err)
	}
}

func TestCreateUsesExplicitIcon(t *testing.T) {
	home := t.TempDir()
	icon := filepath.Join(home, "custom.svg")
	if err := os.WriteFile(icon, []byte("<svg/>"), 0644); err != nil {
		t.Fatal(err)
	}
	m := &manifest.Manifest{Name: "app", GUI: true, Icon: icon}
	if _, err := Create(home, m); err != nil {
		t.Fatal(err)
	}
	iconDst := filepath.Join(home, ".local/share/icons/hicolor/256x256/apps", "packbox-app.svg")
	if _, err := os.Stat(iconDst); err != nil {
		t.Fatalf("explicit icon not copied: %v", err)
	}
}

func TestCreateSanitizesNewlines(t *testing.T) {
	home := t.TempDir()
	m := &manifest.Manifest{Name: "app", GUI: true, Description: "line1\nExec=/evil"}
	if _, err := Create(home, m); err != nil {
		t.Fatal(err)
	}
	data, _ := os.ReadFile(DesktopPath(home, "app"))
	if strings.Contains(string(data), "\nExec=/evil") {
		t.Fatalf("newline injection not sanitized:\n%s", data)
	}
}

func TestRemove(t *testing.T) {
	home := t.TempDir()
	if _, err := Create(home, &manifest.Manifest{Name: "app", GUI: true}); err != nil {
		t.Fatal(err)
	}
	if err := Remove(home, "app"); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(DesktopPath(home, "app")); err == nil {
		t.Fatal("desktop file not removed")
	}
}

func TestCategories(t *testing.T) {
	cases := map[string]string{
		"org.bundle.firefox":   "Network;WebBrowser;",
		"org.bundle.vlc":       "AudioVideo;Player;",
		"org.bundle.gimp":      "Graphics;",
		"org.bundle.something": "Utility;",
	}
	for id, want := range cases {
		if got := categories(id); got != want {
			t.Fatalf("categories(%q) = %q, want %q", id, got, want)
		}
	}
}
