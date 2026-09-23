// packbox-export streams an installed app to a .pbox archive.
// packbox-export transmite una app instalada a un archivo .pbox.
package main

import (
	"archive/tar"
	"compress/gzip"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"

	"github.com/packbox/packbox/internal/appinstall"
	"github.com/packbox/packbox/internal/compress"
	"github.com/packbox/packbox/internal/manifest"
	"github.com/packbox/packbox/internal/sign"
)

func main() {
	var (
		signIt bool
		pos    []string
		cmode  = "auto"
	)
	args := os.Args[1:]
	for i := 0; i < len(args); i++ {
		switch args[i] {
		case "--sign", "-s":
			signIt = true
		case "--compress", "-C":
			if i+1 < len(args) {
				cmode = args[i+1]
				i++
			}
		default:
			pos = append(pos, args[i])
		}
	}
	if len(pos) < 2 {
		fmt.Println("Usage: packbox-export [--sign] [--compress auto|max|fast|store] app <app-id>")
		os.Exit(1)
	}
	home := os.Getenv("HOME")
	expDir := filepath.Join(home, ".local/share/packbox/exports")
	_ = os.MkdirAll(expDir, 0755)
	if pos[0] != "app" {
		fmt.Println("ERROR: unknown subcommand")
		os.Exit(1)
	}
	id := pos[1]
	appDir := filepath.Join(home, ".local/share/packbox/apps", id)
	if _, err := os.Stat(appDir); os.IsNotExist(err) {
		fmt.Printf("ERROR: does not exist: %s\n", id)
		os.Exit(1)
	}
	out := filepath.Join(expDir, id+".pbox")
	fmt.Printf("[export] %s\n", id)

	// Materialize the app's cells into a staging copy so the .pbox is
	// self-contained: at runtime they are a separate overlay layer, but the
	// archive must carry them (import extracts a plain tree).
	// Materializa las celdas en una copia de staging para que el .pbox sea
	// autocontenido: en runtime son una capa aparte, pero el archivo debe
	// llevarlas (import extrae un árbol normal).
	staged := appDir
	if m, err := manifest.Load(filepath.Join(appDir, "manifest.json")); err == nil && len(m.Mods) > 0 {
		if stageRoot, err := os.MkdirTemp("", "packbox-export-"); err == nil {
			defer os.RemoveAll(stageRoot)
			dst := filepath.Join(stageRoot, filepath.Base(appDir))
			if err := copyTree(appDir, dst); err == nil {
				if _, err := appinstall.LinkCells(home, filepath.Join(dst, "tree"), m.Mods); err != nil {
					fmt.Printf("   WARN cells: %v\n", err)
				}
				staged = dst
			}
		}
	}

	// Adaptive compression: analyze the staged content and pick a plan.
	// Compresión adaptativa: analiza el contenido y elige un plan.
	total, pre := compress.Scan(staged)
	_, zstdErr := exec.LookPath("zstd")
	_, xzErr := exec.LookPath("xz")
	plan := compress.Choose(cmode, total, pre, zstdErr == nil, xzErr == nil)
	comp := plan.Desc

	switch plan.Tool {
	case "store", "gzip":
		f, err := os.Create(out)
		if err != nil {
			fmt.Printf("ERROR: %v\n", err)
			os.Exit(1)
		}
		var w io.WriteCloser = f
		if plan.Tool == "gzip" {
			gz, _ := gzip.NewWriterLevel(f, plan.Level)
			w = gz
		}
		tw := tar.NewWriter(w)
		if err := writeTar(tw, staged); err != nil {
			fmt.Printf("ERROR: %v\n", err)
			os.Exit(1)
		}
		tw.Close()
		w.Close()
		f.Close()
	default: // zstd or xz, streamed through the external tool
		bin, _ := exec.LookPath(plan.Tool)
		var cmd *exec.Cmd
		if plan.Tool == "zstd" {
			cmd = exec.Command(bin, fmt.Sprintf("-%d", plan.Level), "-T0", "-q", "-f", "-o", out)
		} else { // xz
			cmd = exec.Command(bin, fmt.Sprintf("-%d", plan.Level), "-T0", "-q", "-c")
		}
		pr, pw := io.Pipe()
		cmd.Stdin = pr
		if plan.Tool == "xz" {
			f, _ := os.Create(out)
			cmd.Stdout = f
			defer f.Close()
		}
		if err := cmd.Start(); err != nil {
			fmt.Printf("ERROR: %v\n", err)
			os.Exit(1)
		}
		tw := tar.NewWriter(pw)
		go func() {
			err := writeTar(tw, staged)
			_ = tw.Close()
			_ = pw.CloseWithError(err)
		}()
		if err := cmd.Wait(); err != nil {
			fmt.Printf("ERROR: compressor: %v\n", err)
			os.Exit(1)
		}
	}

	m, _ := manifest.Load(filepath.Join(appDir, "manifest.json"))
	fmt.Printf("[ok] %s\n", out)
	fmt.Printf("   Algorithm: %s\n", comp)
	if m != nil && m.Portable {
		fmt.Println("   Mode: PORTABLE")
	}
	if fi, err := os.Stat(out); err == nil {
		fmt.Printf("   Size: %d bytes\n", fi.Size())
	}
	if signIt {
		sp, err := sign.SignFile(out, filepath.Join(home, ".config/packbox"))
		if err != nil {
			fmt.Printf("ERROR: sign: %v\n", err)
			os.Exit(1)
		}
		fmt.Printf("   Signed: %s\n", sp)
	}
}

// writeTar walks srcDir and writes it as a tar stream.
// writeTar recorre srcDir y lo escribe como stream tar.
func writeTar(tw *tar.Writer, srcDir string) error {
	return filepath.Walk(srcDir, func(p string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}
		rel, _ := filepath.Rel(srcDir, p)
		if rel == "." {
			return nil
		}
		var link string
		if info.Mode()&os.ModeSymlink != 0 {
			t, err := os.Readlink(p)
			if err == nil {
				link = t
			}
		}
		h, err := tar.FileInfoHeader(info, link)
		if err != nil {
			return err
		}
		h.Name = rel
		if err := tw.WriteHeader(h); err != nil {
			return err
		}
		if info.Mode().IsRegular() {
			f, err := os.Open(p)
			if err != nil {
				return err
			}
			_, err = io.Copy(tw, f)
			f.Close()
			return err
		}
		return nil
	})
}

// copyTree copies a directory tree (files, dirs, symlinks) from src to dst.
// copyTree copia un árbol de directorios (archivos, dirs, symlinks) de src a dst.
func copyTree(src, dst string) error {
	return filepath.Walk(src, func(p string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}
		rel, _ := filepath.Rel(src, p)
		target := filepath.Join(dst, rel)
		switch {
		case info.IsDir():
			return os.MkdirAll(target, info.Mode().Perm())
		case info.Mode()&os.ModeSymlink != 0:
			l, err := os.Readlink(p)
			if err != nil {
				return err
			}
			return os.Symlink(l, target)
		default:
			in, err := os.Open(p)
			if err != nil {
				return err
			}
			defer in.Close()
			out, err := os.OpenFile(target, os.O_WRONLY|os.O_CREATE|os.O_TRUNC, info.Mode().Perm())
			if err != nil {
				return err
			}
			defer out.Close()
			_, err = io.Copy(out, in)
			return err
		}
	})
}
