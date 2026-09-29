// Tests that a DBusActivatable app may own its bus name.
// Tests de que una app DBusActivatable puede poseer su nombre de bus.
package sandbox

import "testing"

func TestBusNameOwn(t *testing.T) {
	if p := (&Sandbox{}).sessionPolicy(); len(p.Own) != 0 {
		t.Fatalf("no bus name should own nothing: %v", p.Own)
	}
	p := (&Sandbox{BusName: "org.gnome.Ptyxis"}).sessionPolicy()
	found := false
	for _, n := range p.Own {
		if n == "org.gnome.Ptyxis" {
			found = true
		}
	}
	if !found {
		t.Fatalf("BusName should be owned: %v", p.Own)
	}
	// y se emite --own=...
	sb := &Sandbox{BusName: "org.gnome.Ptyxis"}
	args := dbusProxyArgs("unix:path=/x", "/y", sb.sessionPolicy())
	ok := false
	for _, x := range args {
		if x == "--own=org.gnome.Ptyxis" {
			ok = true
		}
	}
	if !ok {
		t.Fatalf("--own not passed: %v", args)
	}
}
