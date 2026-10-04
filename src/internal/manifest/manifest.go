// Package manifest defines the Packbox app manifest schema.
// El paquete manifest define el esquema del manifiesto de apps Packbox.
package manifest

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

// Manifest describes an app bundle.
// Manifest describe un bundle de aplicación.
type Manifest struct {
	SchemaVersion string      `json:"schema_version"`
	Name          string      `json:"name"`
	Version       string      `json:"version"`
	Description   string      `json:"description,omitempty"`
	Developer     string      `json:"developer,omitempty"`
	Website       string      `json:"website,omitempty"`
	License       string      `json:"license,omitempty"`
	Support       string      `json:"support,omitempty"`
	Entrypoint    string      `json:"entrypoint"`
	Arch          string      `json:"arch"`
	GUI           bool        `json:"gui,omitempty"`
	Toolkit       string      `json:"toolkit,omitempty"`
	Icon          string      `json:"icon,omitempty"`
	Categories    string      `json:"categories,omitempty"`
	Network       NetworkMode `json:"network,omitempty"` // "none", "limited", "full"
	X11           bool        `json:"x11,omitempty"`
	// Sandbox lists extra host capabilities to grant (opt-in), e.g.
	// "system-bus", "libvirt", "kvm" for VM apps like GNOME Boxes.
	// Sandbox lista capacidades extra del host a conceder (opt-in), p. ej.
	// "system-bus", "libvirt", "kvm" para apps de VM como GNOME Boxes.
	Sandbox []string `json:"sandbox,omitempty"`
	// BundleDir is the app bundle root (/opt/<app>), if any.
	// BundleDir es la raíz del bundle de la app (/opt/<app>), si la hay.
	BundleDir string `json:"bundle_dir,omitempty"`
	// BusName is the D-Bus name the app owns (from a DBusActivatable .desktop).
	// BusName es el nombre de D-Bus que posee la app (de un .desktop DBusActivatable).
	BusName      string       `json:"bus_name,omitempty"`
	Layers       Layers       `json:"layers"`
	Mods         []string     `json:"mods"`
	HostContract HostContract `json:"host_contract"`
	Portable     bool         `json:"portable,omitempty"`
	Debug        *DebugInfo   `json:"debug,omitempty"`
}

// NetworkMode is the app's network policy. It unmarshals from either the
// modern string form ("none"/"limited"/"full") or the legacy boolean form
// (true = full, false = none), so manifests written before schema 1.7 still
// load instead of failing with a type error.
// NetworkMode es la política de red de la app. Se deserializa tanto de la forma
// moderna (string "none"/"limited"/"full") como de la forma booleana antigua
// (true = full, false = none), para que los manifiestos previos al esquema 1.7
// sigan cargando en vez de fallar con un error de tipo.
type NetworkMode string

const (
	NetworkNone    NetworkMode = "none"
	NetworkLimited NetworkMode = "limited"
	NetworkFull    NetworkMode = "full"
)

// UnmarshalJSON accepts a JSON string, bool, or null.
// UnmarshalJSON acepta un string, bool o null de JSON.
func (n *NetworkMode) UnmarshalJSON(b []byte) error {
	s := strings.TrimSpace(string(b))
	switch s {
	case "", "null":
		*n = ""
		return nil
	case "true":
		*n = NetworkFull
		return nil
	case "false":
		*n = NetworkNone
		return nil
	}
	var str string
	if err := json.Unmarshal(b, &str); err != nil {
		return fmt.Errorf("network: %w", err)
	}
	*n = NetworkMode(str)
	return nil
}

// MarshalJSON always writes the modern string form.
// MarshalJSON siempre escribe la forma moderna de string.
func (n NetworkMode) MarshalJSON() ([]byte, error) {
	return json.Marshal(string(n))
}

// DebugInfo points at the debug-symbol cell split out of the app's binary (so
// the app itself stays stripped; the symbols are fetched only when debugging).
// DebugInfo apunta a la celda de símbolos de debug separada del binario de la
// app (la app queda stripped; los símbolos solo se traen al depurar).
type DebugInfo struct {
	Cell   string `json:"cell"`   // debug cell ref "name@version"
	Binary string `json:"binary"` // path of the stripped binary, relative to the tree
}

// Layers groups all layers (only "app" for now).
// Layers agrupa todas las capas (solo "app" por ahora).
type Layers struct {
	App AppLayer `json:"app"`
}

// AppLayer holds the file map.
// AppLayer contiene el mapa de archivos.
type AppLayer struct {
	Files map[string]FileInfo `json:"files"`
}

// FileInfo describes a single file in a layer.
// FileInfo describe un archivo en una capa.
type FileInfo struct {
	Chunks []string `json:"chunks,omitempty"`
	Size   int64    `json:"size"`
	Mode   string   `json:"mode"`
	Link   string   `json:"link,omitempty"` // symlink target
}

// HostContract declares symbols and libs delegated to the host.
// HostContract declara símbolos y libs delegadas al host.
type HostContract struct {
	Version         string              `json:"version"`
	Delegate        []string            `json:"delegate"`
	RequiredSymbols map[string][]string `json:"required_symbols"`
	FallbackMods    map[string]string   `json:"fallback_mods"`
}

// Load reads and validates a manifest.
// Load lee y valida un manifiesto.
func Load(p string) (*Manifest, error) {
	data, err := os.ReadFile(p)
	if err != nil {
		return nil, fmt.Errorf("read: %w", err)
	}
	var m Manifest
	if err := json.Unmarshal(data, &m); err != nil {
		return nil, fmt.Errorf("parse: %w", err)
	}
	if m.SchemaVersion == "" || m.Name == "" || m.Entrypoint == "" {
		return nil, fmt.Errorf("missing fields")
	}
	if m.SchemaVersion != "1.5" && m.SchemaVersion != "1.6" && m.SchemaVersion != "1.7" {
		return nil, fmt.Errorf("unsupported schema: %s", m.SchemaVersion)
	}
	// The name becomes a directory and the file keys become paths: reject
	// anything that could escape the app directory (path traversal).
	// El name se vuelve un directorio y las claves de archivo rutas: rechaza
	// cualquier cosa que pueda escapar del directorio de la app (traversal).
	if !validName(m.Name) {
		return nil, fmt.Errorf("invalid name: %q", m.Name)
	}
	for rel := range m.Layers.App.Files {
		if !validRelPath(rel) {
			return nil, fmt.Errorf("invalid file path: %q", rel)
		}
	}
	return &m, nil
}

// validName reports whether s is a safe single path component (app id).
// validName indica si s es un componente de ruta seguro (app id).
func validName(s string) bool {
	if s == "" || s == "." || s == ".." {
		return false
	}
	for i, c := range s {
		alnum := (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')
		if i == 0 && !alnum {
			return false // must start alphanumeric
		}
		if !alnum && c != '.' && c != '_' && c != '-' {
			return false
		}
	}
	return true
}

// validRelPath reports whether p is a relative path that stays put (no "..").
// validRelPath indica si p es una ruta relativa que no escapa (sin "..").
func validRelPath(p string) bool {
	if p == "" || filepath.IsAbs(p) {
		return false
	}
	c := filepath.Clean(p)
	if c == "." || c == ".." || strings.HasPrefix(c, ".."+string(os.PathSeparator)) {
		return false
	}
	return true
}

// Save writes the manifest as pretty JSON.
// Save escribe el manifiesto como JSON indentado.
func (m *Manifest) Save(p string) error {
	data, err := json.MarshalIndent(m, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(p, data, 0644)
}
