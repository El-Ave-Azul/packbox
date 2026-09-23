// Tests for the remove argument parser.
// Tests para el parser de argumentos de remove.
package main

import "testing"

func TestParseArgs(t *testing.T) {
	pos, all, dry, help := parseArgs([]string{"app1"})
	if len(pos) != 1 || pos[0] != "app1" || all || dry || help {
		t.Fatalf("plain: pos=%v all=%v dry=%v help=%v", pos, all, dry, help)
	}

	pos, all, dry, _ = parseArgs([]string{"--all", "--dry-run"})
	if len(pos) != 0 || !all || !dry {
		t.Fatalf("flags: pos=%v all=%v dry=%v", pos, all, dry)
	}

	pos, all, dry, _ = parseArgs([]string{"-a", "-n", "x"})
	if len(pos) != 1 || pos[0] != "x" || !all || !dry {
		t.Fatalf("short flags: pos=%v all=%v dry=%v", pos, all, dry)
	}

	_, _, _, help = parseArgs([]string{"--help"})
	if !help {
		t.Fatal("--help not detected")
	}
}
