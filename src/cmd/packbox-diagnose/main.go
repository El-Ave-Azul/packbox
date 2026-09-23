// packbox-diagnose prints environment diagnostics.
// packbox-diagnose imprime diagnóstico del entorno.
package main

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"

	"github.com/packbox/packbox/internal/version"
)

func main() {
	home := os.Getenv("HOME")
	fmt.Printf("Packbox Diagnostics v%s\n", version.Version)
	fmt.Println("===============================================================")
	fmt.Printf("Install dir: %s\n", filepath.Join(home, ".packbox"))
	fmt.Printf("Data dir:    %s\n", filepath.Join(home, ".local/share/packbox"))
	fmt.Printf("Config dir:  %s\n", filepath.Join(home, ".config/packbox"))
	fmt.Println()
	fmt.Println("Structure:")
	for _, d := range []string{
		".packbox/bin", ".packbox/src", ".packbox/go",
		".local/share/packbox/store", ".local/share/packbox/apps",
		".config/packbox/lang",
	} {
		p := filepath.Join(home, d)
		if _, err := os.Stat(p); err == nil {
			fmt.Printf("  [ok] %s\n", d)
		} else {
			fmt.Printf("  [X]  %s\n", d)
		}
	}
	fmt.Println()
	fmt.Println("Tools:")
	for _, t := range []string{"bwrap", "readelf", "ldd", "jq", "zstd", "xz", "tar"} {
		if _, err := exec.LookPath(t); err == nil {
			fmt.Printf("  [ok] %s\n", t)
		} else {
			fmt.Printf("  [X]  %s\n", t)
		}
	}
	fmt.Println()
	fmt.Println("DNS files:")
	for _, f := range []string{
		"/etc/resolv.conf", "/etc/hosts", "/etc/nsswitch.conf",
		"/run/systemd/resolve/stub-resolv.conf",
	} {
		info, err := os.Lstat(f)
		if err != nil {
			fmt.Printf("  [X]  %s\n", f)
			continue
		}
		if info.Mode()&os.ModeSymlink != 0 {
			t, _ := filepath.EvalSymlinks(f)
			fmt.Printf("  [ok] %s -> %s\n", f, t)
		} else {
			fmt.Printf("  [ok] %s\n", f)
		}
	}
	fmt.Println()
	fmt.Printf("Kernel: %s\n", kernel())
	fmt.Printf("Arch: %s\n", runtime.GOARCH)
	fmt.Printf("Go: %s\n", runtime.Version())
}

// kernel returns the running kernel version.
// kernel devuelve la versión del kernel en ejecución.
func kernel() string {
	out, err := exec.Command("uname", "-r").Output()
	if err != nil {
		return "?"
	}
	return strings.TrimSpace(string(out))
}
