// packbox-gui is the Packbox desktop manager: a GTK4 window that lists the
// installed apps, shows how much disk space deduplication saves, and lets you
// run or remove each app.
// packbox-gui es el gestor de escritorio de Packbox: una ventana GTK4 que lista
// las apps instaladas, muestra cuánto espacio ahorra la deduplicación y permite
// ejecutar o desinstalar cada una.
package main

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"

	"github.com/diamondburned/gotk4/pkg/gio/v2"
	"github.com/diamondburned/gotk4/pkg/glib/v2"
	"github.com/diamondburned/gotk4/pkg/gtk/v4"

	"github.com/packbox/packbox/internal/appsize"
	"github.com/packbox/packbox/internal/manifest"
)

type manager struct {
	app     *gtk.Application
	win     *gtk.ApplicationWindow
	list    *gtk.ListBox
	summary *gtk.Label
	status  *gtk.Label

	appsDir string
	modsDir string
	binDir  string
}

func main() {
	home, _ := os.UserHomeDir()
	if home == "" {
		home = os.Getenv("HOME")
	}
	m := &manager{
		appsDir: filepath.Join(home, ".local/share/packbox/apps"),
		modsDir: filepath.Join(home, ".local/share/packbox/mods"),
		binDir:  filepath.Join(home, ".packbox/bin"),
	}
	app := gtk.NewApplication("dev.packbox.Manager", gio.ApplicationFlagsNone)
	m.app = app
	app.ConnectActivate(m.activate)
	app.Run(os.Args)
}

func (m *manager) activate() {
	if m.win != nil {
		m.refresh()
		m.win.Present()
		return
	}

	m.win = gtk.NewApplicationWindow(m.app)
	m.win.SetTitle("Packbox Manager")
	m.win.SetDefaultSize(920, 640)

	header := gtk.NewHeaderBar()
	header.SetTitleWidget(titl("Packbox", "title"))
	refreshBtn := gtk.NewButtonWithLabel("Actualizar")
	refreshBtn.SetTooltipText("Relee las apps instaladas y recalcula el ahorro")
	refreshBtn.ConnectClicked(m.refresh)
	header.PackStart(refreshBtn)

	m.summary = titl("", "dim-label")
	m.summary.SetXAlign(0)
	m.summary.SetMarginStart(12)
	m.summary.SetMarginEnd(12)
	m.summary.SetMarginTop(10)

	m.list = gtk.NewListBox()
	m.list.SetSelectionMode(gtk.SelectionNone)
	m.list.AddCSSClass("boxed-list")
	m.list.SetMarginStart(12)
	m.list.SetMarginEnd(12)
	m.list.SetMarginBottom(6)

	scrolled := gtk.NewScrolledWindow()
	scrolled.SetChild(m.list)
	scrolled.SetVExpand(true)

	m.status = titl("Listo.", "dim-label")
	m.status.SetXAlign(0)
	m.status.SetMarginStart(12)
	m.status.SetMarginEnd(12)
	m.status.SetMarginBottom(10)

	root := gtk.NewBox(gtk.OrientationVertical, 8)
	root.Append(m.summary)
	root.Append(scrolled)
	root.Append(m.status)

	m.win.SetTitlebar(header)
	m.win.SetChild(root)
	m.win.Present()
	m.refresh()
}

// refresh rebuilds the whole view from the installed apps on disk.
// refresh reconstruye toda la vista a partir de las apps instaladas en disco.
func (m *manager) refresh() {
	m.list.RemoveAll()

	ids := m.appIDs()
	stats, _ := appsize.Compute(m.appsDir, m.modsDir, ids)
	var real, apparent int64
	for _, s := range stats {
		real += s.Real
		apparent += s.Apparent
	}
	saving := 0
	if apparent > 0 {
		saving = int((apparent - real) * 100 / apparent)
	}
	m.summary.SetText(fmt.Sprintf("Apps: %d    ·    Ahorro real: %s de %s    ·    Deduplicación: %d%%",
		len(ids), appsize.Human(real), appsize.Human(apparent), saving))

	if len(ids) == 0 {
		row := gtk.NewListBoxRow()
		row.SetActivatable(false)
		msg := titl("No hay apps instaladas.\nEmpaqueta o importa un .pbox y aparecerán aquí.", "dim-label")
		msg.SetMarginTop(20)
		msg.SetMarginBottom(20)
		row.SetChild(msg)
		m.list.Append(row)
		m.setStatus("Sin apps.")
		return
	}

	for _, id := range ids {
		m.list.Append(m.appRow(id, stats[id]))
	}
	m.setStatus(fmt.Sprintf("%d apps instaladas.", len(ids)))
}

// appRow builds one row: name/version/size on the left, actions on the right.
// appRow construye una fila: nombre/versión/tamaño a la izquierda, acciones a la
// derecha.
func (m *manager) appRow(id string, st appsize.Stat) *gtk.ListBoxRow {
	name := id
	version := ""
	if man, err := manifest.Load(filepath.Join(m.appsDir, id, "manifest.json")); err == nil {
		if man.Name != "" {
			name = man.Name
		}
		version = man.Version
	}

	title := titl(name, "heading")
	title.SetXAlign(0)
	title.SetEllipsize(2) // pango.EllipsizeMiddle

	meta := fmt.Sprintf("%s   ·   real %s   ·   comparte %s (%d%%)",
		shortID(id), appsize.Human(st.Real), appsize.Human(st.Shared()), st.SavingPct())
	if version != "" {
		meta = "v" + version + "   ·   " + meta
	}
	sub := titl(meta, "dim-label")
	sub.SetXAlign(0)
	sub.SetEllipsize(2)

	info := gtk.NewBox(gtk.OrientationVertical, 2)
	info.SetVExpand(true)
	info.Append(title)
	info.Append(sub)

	run := gtk.NewButtonWithLabel("Ejecutar")
	run.SetTooltipText("Ejecuta la app en el sandbox (packbox-run)")
	run.ConnectClicked(func() { m.runApp(id, name) })

	remove := gtk.NewButtonWithLabel("Desinstalar")
	remove.AddCSSClass("destructive-action")
	remove.SetTooltipText("Quita la app y libera sus referencias")
	remove.ConnectClicked(func() { m.confirmRemove(id, name) })

	actions := gtk.NewBox(gtk.OrientationHorizontal, 6)
	actions.Append(run)
	actions.Append(remove)

	line := gtk.NewBox(gtk.OrientationHorizontal, 12)
	line.SetMarginTop(8)
	line.SetMarginBottom(8)
	line.SetMarginStart(10)
	line.SetMarginEnd(10)
	line.Append(info)
	line.Append(actions)

	row := gtk.NewListBoxRow()
	row.SetActivatable(false)
	row.SetChild(line)
	return row
}

func (m *manager) runApp(id, name string) {
	cmd := exec.Command(m.bin("packbox-run"), id)
	if err := cmd.Start(); err != nil {
		m.setStatus(fmt.Sprintf("No se pudo ejecutar %s: %v", name, err))
		return
	}
	go func() { _ = cmd.Wait() }() // reap it when the app exits
	m.setStatus(fmt.Sprintf("Ejecutando %s…  (log: ~/.cache/packbox/%s.log)", name, id))
}

// confirmRemove asks before a destructive uninstall.
// confirmRemove pide confirmación antes de una desinstalación destructiva.
func (m *manager) confirmRemove(id, name string) {
	dlg := gtk.NewWindow()
	dlg.SetTitle("Desinstalar")
	dlg.SetModal(true)
	dlg.SetResizable(false)
	dlg.SetDefaultSize(380, 150)
	if m.win != nil {
		dlg.SetTransientFor(&m.win.Window)
	}

	msg := titl(fmt.Sprintf("¿Desinstalar «%s»?\n\nSus referencias se liberan; los chunks que ya nadie\nuse se borran con `packbox-gc`.", name), "")
	msg.SetWrap(true)
	msg.SetXAlign(0)
	msg.SetMarginTop(14)
	msg.SetMarginStart(14)
	msg.SetMarginEnd(14)

	cancel := gtk.NewButtonWithLabel("Cancelar")
	cancel.ConnectClicked(func() { dlg.Destroy() })
	del := gtk.NewButtonWithLabel("Desinstalar")
	del.AddCSSClass("destructive-action")
	del.ConnectClicked(func() {
		dlg.Destroy()
		m.removeApp(id, name)
	})

	buttons := gtk.NewBox(gtk.OrientationHorizontal, 6)
	buttons.SetHomogeneous(true)
	buttons.SetMarginTop(6)
	buttons.SetMarginStart(14)
	buttons.SetMarginEnd(14)
	buttons.SetMarginBottom(14)
	buttons.Append(cancel)
	buttons.Append(del)

	box := gtk.NewBox(gtk.OrientationVertical, 8)
	box.Append(msg)
	box.Append(buttons)
	dlg.SetChild(box)
	dlg.Present()
}

func (m *manager) removeApp(id, name string) {
	m.setStatus(fmt.Sprintf("Desinstalando %s…", name))
	go func() {
		out, err := exec.Command(m.bin("packbox-remove"), id).CombinedOutput()
		glib.IdleAdd(func() {
			if err != nil {
				m.setStatus(fmt.Sprintf("Error al desinstalar %s: %v — %s", name, err, strings.TrimSpace(string(out))))
			} else {
				m.setStatus(fmt.Sprintf("Desinstalada %s.", name))
			}
			m.refresh()
		})
	}()
}

// appIDs returns the installed app ids, sorted.
// appIDs devuelve los ids de las apps instaladas, ordenados.
func (m *manager) appIDs() []string {
	entries, err := os.ReadDir(m.appsDir)
	if err != nil {
		return nil
	}
	var ids []string
	for _, e := range entries {
		if e.IsDir() {
			ids = append(ids, e.Name())
		}
	}
	sort.Strings(ids)
	return ids
}

// bin prefers the installed binary in ~/.packbox/bin, then PATH.
// bin prefiere el binario instalado en ~/.packbox/bin, luego el PATH.
func (m *manager) bin(name string) string {
	p := filepath.Join(m.binDir, name)
	if _, err := os.Stat(p); err == nil {
		return p
	}
	if p, err := exec.LookPath(name); err == nil {
		return p
	}
	return name
}

func (m *manager) setStatus(s string) {
	if m.status != nil {
		m.status.SetText(s)
	}
}

// shortID trims a reverse-DNS app id to its last component when it is long.
// shortID recorta un id de app en DNS inverso a su último componente si es largo.
func shortID(id string) string {
	if i := strings.LastIndex(id, "."); i >= 0 && len(id) > 24 {
		return "…" + id[i+1:]
	}
	return id
}

func titl(text, class string) *gtk.Label {
	l := gtk.NewLabel(text)
	if class != "" {
		l.AddCSSClass(class)
	}
	return l
}
