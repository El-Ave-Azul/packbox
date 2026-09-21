// Package compress picks an adaptive compression plan for an export: content
// that is already compressed (images, video, archives) is not worth heavy
// recompression, while binaries and text are.
// El paquete compress elige un plan de compresión adaptativo para un export: el
// contenido ya comprimido (imágenes, vídeo, archivos) no merece recompresión
// pesada, mientras que los binarios y el texto sí.
package compress

import (
	"os"
	"path/filepath"
	"strings"
)

// precompressed maps already-compressed extensions.
// precompressed mapea extensiones ya comprimidas.
var precompressed = map[string]bool{
	".png": true, ".jpg": true, ".jpeg": true, ".gif": true, ".webp": true, ".avif": true, ".heic": true,
	".mp4": true, ".webm": true, ".mkv": true, ".mov": true, ".avi": true,
	".mp3": true, ".ogg": true, ".opus": true, ".flac": true, ".aac": true, ".m4a": true, ".wav": false,
	".zip": true, ".gz": true, ".xz": true, ".zst": true, ".bz2": true, ".7z": true, ".rar": true, ".lz4": true,
	".woff2": true, ".jar": true, ".apk": true, ".deb": true, ".rpm": true, ".whl": true,
}

// Precompressed reports whether a filename is already compressed.
// Precompressed indica si un nombre de archivo ya está comprimido.
func Precompressed(name string) bool {
	return precompressed[strings.ToLower(filepath.Ext(name))]
}

// Scan returns the total bytes and the bytes in already-compressed files under
// dir.
// Scan devuelve los bytes totales y los bytes en archivos ya comprimidos bajo
// dir.
func Scan(dir string) (total, pre int64) {
	_ = filepath.Walk(dir, func(p string, fi os.FileInfo, err error) error {
		if err != nil || fi.IsDir() || !fi.Mode().IsRegular() {
			return nil
		}
		total += fi.Size()
		if Precompressed(fi.Name()) {
			pre += fi.Size()
		}
		return nil
	})
	return total, pre
}

// Plan describes the chosen compressor.
// Plan describe el compresor elegido.
type Plan struct {
	Tool  string // "zstd" | "xz" | "gzip" | "store"
	Level int    // compression level for the tool
	Desc  string // human-readable justification
}

// Choose picks a plan for the given mode (auto|max|fast|store) and content.
// ratio = already-compressed bytes / total. haveZstd/haveXz say what is
// available on the host.
// Choose elige un plan para el modo dado (auto|max|fast|store) y el contenido.
// ratio = bytes ya comprimidos / total. haveZstd/haveXz indican qué hay.
func Choose(mode string, total, pre int64, haveZstd, haveXz bool) Plan {
	ratio := 0.0
	if total > 0 {
		ratio = float64(pre) / float64(total)
	}
	switch mode {
	case "store":
		return Plan{Tool: "store", Desc: "store (sin comprimir)"}
	case "fast":
		return fastPlan(haveZstd, "fast (forzado)")
	case "max":
		return maxPlan(haveZstd, haveXz, "max (forzado)")
	default: // auto
		if ratio >= 0.5 {
			return fastPlan(haveZstd, "auto: ~assets ya comprimidos")
		}
		return maxPlan(haveZstd, haveXz, "auto: contenido comprimible")
	}
}

// fastPlan prefers a fast level (cheap on incompressible data).
// fastPlan prefiere un nivel rápido (barato en datos incompresibles).
func fastPlan(haveZstd bool, why string) Plan {
	if haveZstd {
		return Plan{Tool: "zstd", Level: 3, Desc: "zstd -3 (" + why + ")"}
	}
	return Plan{Tool: "gzip", Level: 1, Desc: "gzip -1 (" + why + ")"}
}

// maxPlan prefers the strongest level available.
// maxPlan prefiere el nivel más fuerte disponible.
func maxPlan(haveZstd, haveXz bool, why string) Plan {
	switch {
	case haveZstd:
		return Plan{Tool: "zstd", Level: 19, Desc: "zstd -19 (" + why + ")"}
	case haveXz:
		return Plan{Tool: "xz", Level: 9, Desc: "xz -9 (" + why + ")"}
	default:
		return Plan{Tool: "gzip", Level: 9, Desc: "gzip -9 (" + why + ")"}
	}
}
