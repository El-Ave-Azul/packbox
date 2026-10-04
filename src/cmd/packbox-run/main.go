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
	"github.com/packbox/packbox/internal/netproxy"
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
	sb.Network = string(m.Network)
	sb.X11 = m.X11
	sb.Caps = m.Sandbox
	sb.BusName = m.BusName
	// Red de seguridad: una app cuyo id parece un nombre de bus (org.gnome.Foo)
	// normalmente lo posee (es la convención de D-Bus y la de Flatpak).
	// Safety net: an app whose id looks like a bus name (org.gnome.Foo) usually
	// owns it (the D-Bus and Flatpak convention).
	if sb.BusName == "" && strings.Count(m.Name, ".") >= 2 {
		sb.BusName = m.Name
	}
	if m.BundleDir != "" {
		sb.ROBinds = []string{m.BundleDir}
	}
	sb.DelegateLibs = m.HostContract.Delegate
	sb.Layers = appinstall.CellDirs(home, m.Mods)

	// Network: if 'limited', start the internal proxy and configure environment.
	if m.Network == manifest.NetworkLimited {
		addr, err := netproxy.StartProxy()
		if err != nil {
			fmt.Printf("WARN: could not start network proxy: %v\n", err)
		} else {
			fmt.Printf("[net] limited mode: proxy at %s\n", addr)
			fmt.Printf("[net] best-effort: only apps honoring http_proxy/https_proxy are restricted\n")
			// We add the proxy as a capability so the sandbox can set the env vars.
			sb.Caps = append(sb.Caps, "net-proxy:"+addr)
		}
	}

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
