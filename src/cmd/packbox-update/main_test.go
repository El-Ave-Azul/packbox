// Tests for the update argument parser.
// Tests para el parser de argumentos de update.
package main

import "testing"

func TestParseArgs(t *testing.T) {
	pos, from, noGC, help := parseArgs([]string{"--no-gc", "app", "m.json"})
	if len(pos) != 2 || pos[0] != "app" || pos[1] != "m.json" || from != "" || !noGC || help {
		t.Fatalf("got pos=%v from=%q noGC=%v help=%v", pos, from, noGC, help)
	}

	pos, from, noGC, help = parseArgs([]string{"app", "m.json"})
	if len(pos) != 2 || from != "" || noGC || help {
		t.Fatalf("default: pos=%v from=%q noGC=%v help=%v", pos, from, noGC, help)
	}

	pos, from, noGC, _ = parseArgs([]string{"-n", "app", "m.json"})
	if len(pos) != 2 || pos[0] != "app" || from != "" || !noGC {
		t.Fatalf("short -n: pos=%v from=%q noGC=%v", pos, from, noGC)
	}

	// --from with a separate value.
	pos, from, _, _ = parseArgs([]string{"app", "--from", "http://x:8000"})
	if len(pos) != 1 || pos[0] != "app" || from != "http://x:8000" {
		t.Fatalf("--from value: pos=%v from=%q", pos, from)
	}

	// --from=URL form.
	pos, from, _, _ = parseArgs([]string{"app", "--from=http://y"})
	if len(pos) != 1 || from != "http://y" {
		t.Fatalf("--from=URL: pos=%v from=%q", pos, from)
	}

	// -f URL and the app-id order does not matter.
	pos, from, _, _ = parseArgs([]string{"-f", "http://z", "app"})
	if len(pos) != 1 || pos[0] != "app" || from != "http://z" {
		t.Fatalf("-f URL: pos=%v from=%q", pos, from)
	}

	_, _, _, help = parseArgs([]string{"--help"})
	if !help {
		t.Fatal("--help not detected")
	}
	_, _, _, help = parseArgs([]string{"-h"})
	if !help {
		t.Fatal("-h not detected")
	}
}
