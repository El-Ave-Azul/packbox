// Package version exposes the Packbox project version.
// El paquete version expone la versión del proyecto Packbox.
//
// Single source of truth: the VERSION file next to this file. The shell side
// reads the same file (see lib/paths.sh), so the version lives in one place.
// Fuente única de verdad: el archivo VERSION junto a este archivo. El lado
// shell lee el mismo archivo (ver lib/paths.sh), así la versión vive en un
// solo lugar.
package version

import (
	_ "embed"
	"strings"
)

//go:embed VERSION
var raw string

// Version is the project version, read from VERSION at build time.
// Version es la versión del proyecto, leída de VERSION en tiempo de compilación.
var Version = strings.TrimSpace(raw)
