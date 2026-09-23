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
	if fi, err := os.Stat(id); err == nil && fi.IsDir() {
		appDir = id // a directory was given (an app dir or a packing working dir)
	}
	m, err := manifest.Load(filepath.Join(appDir, "manifest.json"))
	if err != nil {
		fmt.Printf("ERROR: no manifest in %s (%v)\n", appDir, err)
		os.Exit(1)
	}
	id = m.Name
	out := filepath.Join(expDir, id+".pbox")
	fmt.Printf("[export] %s\n", id)

	// Stage a copy with the app-dir layout (manifest.json + tree/) and the
	// cells materialized, so the .pbox is self-contained.
	// Copia a staging con el layout de app (manifest.json + tree/) y las celdas
	// materializadas, para que el .pbox sea autocontenido.
	staged := appDir
	if stageRoot, err := os.MkdirTemp("", "packbox-export-"); err == nil {
		defer os.RemoveAll(stageRoot)
		dst := filepath.Join(stageRoot, "app")
		if err := stageDir(appDir, dst); err != nil {
			fmt.Printf("   WARN staging: %v\n", err)
		} else {
			if _, err := appinstall.LinkCells(home, filepath.Join(dst, "tree"), m.Mods); err != nil {
				fmt.Printf("   WARN cells: %v\n", err)
			}
			staged = dst
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

	fmt.Printf("[ok] %s\n", out)
	fmt.Printf("   Algorithm: %s\n", comp)
	if m.Portable {
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

// stageDir copies src into dst with the app-dir layout: manifest.json at the
// root and every other entry under tree/. If src already looks like an app dir
// (it has a tree/ subdir) it is copied as-is.
// stageDir copia src en dst con el layout de app: manifest.json en la raíz y el
// resto bajo tree/. Si src ya parece un dir de app (tiene tree/) se copia tal cual.
func stageDir(src, dst string) error {
	if fi, err := os.Stat(filepath.Join(src, "tree")); err == nil && fi.IsDir() {
		return copyTree(src, dst)
	}
	if err := os.MkdirAll(filepath.Join(dst, "tree"), 0755); err != nil {
		return err
	}
	entries, err := os.ReadDir(src)
	if err != nil {
		return err
	}
	for _, e := range entries {
		s := filepath.Join(src, e.Name())
		if e.Name() == "manifest.json" {
			if err := copyFileTo(s, filepath.Join(dst, "manifest.json")); err != nil {
				return err
			}
			continue
		}
		if err := copyTree(s, filepath.Join(dst, "tree", e.Name())); err != nil {
			return err
		}
	}
	return nil
}

// copyFileTo copies a single file from src to dst.
// copyFileTo copia un solo archivo de src a dst.
func copyFileTo(src, dst string) error {
	in, err := os.Open(src)
	if err != nil {
		return err
	}
	defer in.Close()
	fi, err := in.Stat()
	if err != nil {
		return err
	}
	out, err := os.OpenFile(dst, os.O_WRONLY|os.O_CREATE|os.O_TRUNC, fi.Mode().Perm())
	if err != nil {
		return err
	}
	defer out.Close()
	_, err = io.Copy(out, in)
	return err
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
