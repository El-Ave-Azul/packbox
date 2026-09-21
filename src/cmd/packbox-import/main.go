// packbox-import extracts a .pbox archive into the apps dir.
// packbox-import extrae un archivo .pbox en el directorio de apps.
package main

import (
	"archive/tar"
	"compress/gzip"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"syscall"

	"github.com/packbox/packbox/internal/manifest"
	"github.com/packbox/packbox/internal/security"
	"github.com/packbox/packbox/internal/sign"
)

func main() {
	if len(os.Args) < 3 {
		fmt.Println("Usage: packbox-import app <file.pbox>")
		os.Exit(1)
	}
	home := os.Getenv("HOME")
	tmpParent := filepath.Join(home, ".local/share/packbox/tmp")
	_ = os.MkdirAll(tmpParent, 0755)
	tmpDir, err := os.MkdirTemp(tmpParent, "import-")
	if err != nil {
		fmt.Printf("ERROR: %v\n", err)
		os.Exit(1)
	}
	defer os.RemoveAll(tmpDir)
	filePath := os.Args[2]
	if os.Args[1] != "app" {
		fmt.Println("ERROR: unknown subcommand")
		os.Exit(1)
	}
	fmt.Printf("[import] %s\n", filePath)
	// Verify the detached signature when present; refuse a bad one.
	// Verifica la firma separada si está; rechaza una incorrecta.
	cfgDir := filepath.Join(home, ".config/packbox")
	if sign.HasSignature(filePath) {
		signer, err := sign.VerifyFile(filePath, cfgDir)
		if err != nil {
			fmt.Printf("ERROR: signature invalid: %v\n", err)
			os.Exit(1)
		}
		fmt.Printf("[ok] signature verified (signer %s)\n", signer)
	} else {
		fmt.Printf("[warn] unsigned package (no %s)\n", filepath.Base(sign.SigPath(filePath)))
	}
	if err := extract(filePath, tmpDir); err != nil {
		fmt.Printf("ERROR: %v\n", err)
		os.Exit(1)
	}
	m, err := manifest.Load(filepath.Join(tmpDir, "manifest.json"))
	if err != nil {
		fmt.Printf("ERROR: %v\n", err)
		os.Exit(1)
	}
	if m.Arch != "" && m.Arch != runtime.GOARCH {
		fmt.Printf("[warn] package arch: %s (host: %s)\n", m.Arch, runtime.GOARCH)
	}
	appsDir := filepath.Join(home, ".local/share/packbox/apps")
	appDir := filepath.Join(appsDir, m.Name)
	if _, err := os.Stat(appDir); err == nil {
		fmt.Printf("[warn] %s already exists, overwriting\n", m.Name)
		os.RemoveAll(appDir)
	}
	_ = os.MkdirAll(appsDir, 0755)
	if err := os.Rename(tmpDir, appDir); err != nil {
		fmt.Printf("ERROR: %v\n", err)
		os.Exit(1)
	}
	fmt.Printf("[ok] imported: %s\n", m.Name)
}

// extract handles gzip/zstd/xz .pbox archives.
// extract maneja archivos .pbox gzip/zstd/xz.
func extract(src, dst string) error {
	f, err := os.Open(src)
	if err != nil {
		return err
	}
	header := make([]byte, 6)
	if _, err := io.ReadFull(f, header); err != nil {
		f.Close()
		return err
	}
	f.Close()

	var reader io.Reader
	var cmd *exec.Cmd

	switch {
	case header[0] == 0x1f && header[1] == 0x8b:
		f, err := os.Open(src)
		if err != nil {
			return err
		}
		defer f.Close()
		gz, err := gzip.NewReader(f)
		if err != nil {
			return err
		}
		defer gz.Close()
		reader = gz
	case header[0] == 0x28 && header[1] == 0xb5 && header[2] == 0x2f && header[3] == 0xfd:
		if _, err := exec.LookPath("zstd"); err != nil {
			return fmt.Errorf("zstd not installed")
		}
		cmd = exec.Command("zstd", "-dc", src)
		stdout, err := cmd.StdoutPipe()
		if err != nil {
			return err
		}
		if err := cmd.Start(); err != nil {
			return err
		}
		defer cmd.Wait()
		reader = stdout
	case header[0] == 0xfd && header[1] == 0x37 && header[2] == 0x7a && header[3] == 0x58:
		if _, err := exec.LookPath("xz"); err != nil {
			return fmt.Errorf("xz not installed")
		}
		cmd = exec.Command("xz", "-dc", src)
		stdout, err := cmd.StdoutPipe()
		if err != nil {
			return err
		}
		if err := cmd.Start(); err != nil {
			return err
		}
		defer cmd.Wait()
		reader = stdout
	default:
		// Plain (uncompressed) tar: the ustar magic sits at offset 257.
		// Tar plano (sin comprimir): el magic "ustar" está en el offset 257.
		pf, err := os.Open(src)
		if err != nil {
			return err
		}
		magic := make([]byte, 5)
		_, _ = pf.Seek(257, io.SeekStart)
		n, _ := io.ReadFull(pf, magic)
		if n != 5 || string(magic) != "ustar" {
			pf.Close()
			return fmt.Errorf("unknown format")
		}
		if _, err := pf.Seek(0, io.SeekStart); err != nil {
			pf.Close()
			return err
		}
		defer pf.Close()
		reader = pf
	}

	tr := tar.NewReader(reader)
	for {
		h, err := tr.Next()
		if err == io.EOF {
			break
		}
		if err != nil {
			return err
		}
		target, err := safeJoin(dst, h.Name)
		if err != nil {
			return err
		}
		switch h.Typeflag {
		case tar.TypeDir:
			if err := os.MkdirAll(target, 0755); err != nil {
				return err
			}
		case tar.TypeSymlink:
			if err := validateLinkTarget(dst, target, h.Linkname); err != nil {
				return err
			}
			if err := os.MkdirAll(filepath.Dir(target), 0755); err != nil {
				return err
			}
			_ = os.Remove(target)
			if err := os.Symlink(h.Linkname, target); err != nil {
				return err
			}
		case tar.TypeReg:
			if err := os.MkdirAll(filepath.Dir(target), 0755); err != nil {
				return err
			}
			// O_NOFOLLOW: never write through a symlink at the final path.
			// O_NOFOLLOW: nunca escribe a través de un symlink en el path final.
			f, err := os.OpenFile(target, os.O_WRONLY|os.O_CREATE|os.O_TRUNC|syscall.O_NOFOLLOW, os.FileMode(h.Mode))
			if err != nil {
				return err
			}
			if _, err := io.Copy(f, tr); err != nil {
				f.Close()
				return err
			}
			f.Close()
		}
	}
	return nil
}

// safeJoin resolves rel under dst, rejecting path traversal and any write
// that would pass through an existing symlink (tar-slip).
// safeJoin resuelve rel bajo dst, rechazando traversal y cualquier escritura
// que atravesaría un symlink existente (tar-slip).
func safeJoin(dst, rel string) (string, error) {
	target := filepath.Join(dst, rel)
	if err := security.ValidatePath(dst, target); err != nil {
		return "", err
	}
	cur := dst
	for _, p := range strings.Split(filepath.Clean(rel), string(os.PathSeparator)) {
		if p == "" || p == "." {
			continue
		}
		cur = filepath.Join(cur, p)
		fi, err := os.Lstat(cur)
		if err != nil {
			if os.IsNotExist(err) {
				break // remaining components do not exist yet — safe
			}
			return "", err
		}
		if fi.Mode()&os.ModeSymlink != 0 {
			return "", fmt.Errorf("refusing to write through symlink: %s", cur)
		}
	}
	return target, nil
}

// validateLinkTarget rejects symlink targets that escape dst.
// validateLinkTarget rechaza destinos de symlink que escapan de dst.
func validateLinkTarget(dst, linkPath, linkname string) error {
	if linkname == "" {
		return fmt.Errorf("empty symlink target: %s", linkPath)
	}
	if filepath.IsAbs(linkname) {
		return fmt.Errorf("absolute symlink target not allowed: %s -> %s", linkPath, linkname)
	}
	resolved := filepath.Join(filepath.Dir(linkPath), linkname)
	return security.ValidatePath(dst, resolved)
}