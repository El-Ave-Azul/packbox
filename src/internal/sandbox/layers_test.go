// Tests the layer cap (mount options must fit in one page).
// Tests del tope de capas (las opciones de mount deben caber en una página).
package sandbox

import "testing"

func TestTooManyLayersFallBack(t *testing.T) {
	orig := OverlaySupported
	defer func() { OverlaySupported = orig }()
	OverlaySupported = func() bool { return true } // el bwrap sí lo soporta

	sb := NewSandbox("/apps/demo", "/app/bin/x", nil)
	sb.HostHome = t.TempDir()
	sb.Layers = make([]string, MaxOverlayLayers+1)
	for i := range sb.Layers {
		sb.Layers[i] = "/mods/c" + string(rune('a'+i%26)) + "/1"
	}
	args, cleanup, err := sb.bwrapArgs()
	if err != nil {
		t.Fatal(err)
	}
	defer cleanup()
	if !hasTriple(args, "--ro-bind", "/apps/demo/tree", "/app") {
		t.Fatalf("expected a plain bind with too many layers: %v", args)
	}
	if indexOf(args, "--ro-overlay", "/app") >= 0 {
		t.Fatal("overlay used despite too many layers")
	}
}

func TestOverlayUsable(t *testing.T) {
	if MaxOverlayLayers < 8 {
		t.Fatal("cap too low")
	}
}
