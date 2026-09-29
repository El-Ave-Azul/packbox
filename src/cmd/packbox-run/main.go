// packbox-run executes an installed app inside the sandbox.
// packbox-run ejecuta una app instalada dentro del sandbox.
package main

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"

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
	sb.BusName = m.BusName
	if m.BundleDir != "" {
		sb.ROBinds = []string{m.BundleDir}
	}
	sb.DelegateLibs = m.HostContract.Delegate
	sb.Layers = appinstall.CellDirs(home, m.Mods)
	// Deja un log (también desde el menú, donde no hay terminal que ver).
	// Leaves a log (also from the menu, where no terminal shows anything).
	logPath := filepath.Join(home, ".cache/packbox", appID+".log")
	if err := os.MkdirAll(filepath.Dir(logPath), 0755); err == nil {
		if f, err := os.OpenFile(logPath, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0644); err == nil {
			defer f.Close()
			fmt.Fprintf(f, "packbox-run %s %s\n", appID, strings.Join(args, " "))
			sb.LogWriter = f
		}
	}
	if err := sb.Run(); err != nil {
		fmt.Printf("ERROR: %v\n", err)
		fmt.Printf("   log: %s\n", logPath)
		os.Exit(1)
	}
}
