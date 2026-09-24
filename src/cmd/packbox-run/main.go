// packbox-run executes an installed app inside the sandbox.
// packbox-run ejecuta una app instalada dentro del sandbox.
package main

import (
	"fmt"
	"os"
	"path/filepath"

	"github.com/packbox/packbox/internal/appinstall"
	"github.com/packbox/packbox/internal/manifest"
	"github.com/packbox/packbox/internal/sandbox"
)

func main() {
	if len(os.Args) < 2 {
		fmt.Println("Usage: packbox-run <app-id> [args...]")
		os.Exit(1)
	}
	appID := os.Args[1]
	args := os.Args[2:]
	home := os.Getenv("HOME")
	appDir := filepath.Join(home, ".local/share/packbox/apps", appID)
	if _, err := os.Stat(appDir); os.IsNotExist(err) {
		fmt.Printf("ERROR: not installed: %s\n", appID)
		os.Exit(1)
	}
	m, err := manifest.Load(filepath.Join(appDir, "manifest.json"))
	if err != nil {
		fmt.Printf("ERROR: %v\n", err)
		os.Exit(1)
	}
	fmt.Printf("[run] %s v%s\n", appID, m.Version)
	sb := sandbox.NewSandbox(appDir, m.Entrypoint, args)
	sb.IsGUI = m.GUI
	sb.Network = m.Network
	sb.X11 = m.X11
	sb.Caps = m.Sandbox
	sb.DelegateLibs = m.HostContract.Delegate
	sb.Layers = appinstall.CellDirs(home, m.Mods)
	if err := sb.Run(); err != nil {
		fmt.Printf("ERROR: %v\n", err)
		os.Exit(1)
	}
}
