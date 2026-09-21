// Tests for the update argument parser.
// Tests para el parser de argumentos de update.
package main

import "testing"

func TestParseArgs(t *testing.T) {
	pos, noGC, help := parseArgs([]string{"--no-gc", "app", "m.json"})
	if len(pos) != 2 || pos[0] != "app" || pos[1] != "m.json" || !noGC || help {
		t.Fatalf("got pos=%v noGC=%v help=%v", pos, noGC, help)
	}

	pos, noGC, help = parseArgs([]string{"app", "m.json"})
	if len(pos) != 2 || noGC || help {
		t.Fatalf("default: pos=%v noGC=%v help=%v", pos, noGC, help)
	}

	pos, noGC, _ = parseArgs([]string{"-n", "app", "m.json"})
	if len(pos) != 2 || pos[0] != "app" || !noGC {
		t.Fatalf("short flag: pos=%v noGC=%v", pos, noGC)
	}

	_, _, help = parseArgs([]string{"--help"})
	if !help {
		t.Fatal("--help not detected")
	}

	_, _, help = parseArgs([]string{"-h"})
	if !help {
		t.Fatal("-h not detected")
	}
}
