// Tests for the manifest package.
// Tests para el paquete manifest.
package manifest

import (
	"os"
	"path/filepath"
	"testing"
)

func TestLoadSave(t *testing.T) {
	m := &Manifest{
		SchemaVersion: "1.6",
		Name:          "test",
		Version:       "1.0.0",
		Entrypoint:    "/app/bin/foo",
		Arch:          "amd64",
		Layers:        Layers{App: AppLayer{Files: map[string]FileInfo{}}},
	}
	dir := t.TempDir()
	p := filepath.Join(dir, "m.json")
	if err := m.Save(p); err != nil {
		t.Fatal(err)
	}
	m2, err := Load(p)
	if err != nil {
		t.Fatal(err)
	}
	if m2.Name != "test" || m2.Version != "1.0.0" {
		t.Fatalf("bad round trip: %+v", m2)
	}
}

func TestLoadRejectsBadSchema(t *testing.T) {
	dir := t.TempDir()
	p := filepath.Join(dir, "bad.json")
	os.WriteFile(p, []byte(`{"schema_version":"9.9","name":"x","entrypoint":"/app/x"}`), 0644)
	if _, err := Load(p); err == nil {
		t.Fatal("unsupported schema accepted")
	}
}

func TestLoadRejectsTraversalName(t *testing.T) {
	dir := t.TempDir()
	for _, name := range []string{"..", "../../../tmp/pwn", "a/b", ".hidden", "", "a\\b"} {
		p := filepath.Join(dir, "m.json")
		body := `{"schema_version":"1.6","name":` + jsonStr(name) + `,"entrypoint":"/app/x"}`
		os.WriteFile(p, []byte(body), 0644)
		if _, err := Load(p); err == nil {
			t.Fatalf("unsafe name accepted: %q", name)
		}
	}
}

func TestLoadRejectsTraversalFilePath(t *testing.T) {
	dir := t.TempDir()
	for _, rel := range []string{"../x", "/etc/passwd", "a/../../b", ".."} {
		p := filepath.Join(dir, "m.json")
		body := `{"schema_version":"1.6","name":"ok","entrypoint":"/app/x","layers":{"app":{"files":{` +
			jsonStr(rel) + `:{"size":1,"mode":"0644"}}}}}`
		os.WriteFile(p, []byte(body), 0644)
		if _, err := Load(p); err == nil {
			t.Fatalf("unsafe file path accepted: %q", rel)
		}
	}
}

func TestNetworkModeCompat(t *testing.T) {
	dir := t.TempDir()
	cases := []struct {
		body string
		want NetworkMode
	}{
		// Legacy schema 1.5/1.6 wrote network as a boolean.
		{`{"schema_version":"1.6","name":"ok","entrypoint":"/app/x","network":true}`, NetworkFull},
		{`{"schema_version":"1.6","name":"ok","entrypoint":"/app/x","network":false}`, NetworkNone},
		// Schema 1.7 uses the string form.
		{`{"schema_version":"1.7","name":"ok","entrypoint":"/app/x","network":"limited"}`, NetworkLimited},
		{`{"schema_version":"1.7","name":"ok","entrypoint":"/app/x","network":"none"}`, NetworkNone},
		// Absent stays empty.
		{`{"schema_version":"1.7","name":"ok","entrypoint":"/app/x"}`, ""},
	}
	for i, c := range cases {
		p := filepath.Join(dir, "m.json")
		if err := os.WriteFile(p, []byte(c.body), 0644); err != nil {
			t.Fatal(err)
		}
		m, err := Load(p)
		if err != nil {
			t.Fatalf("case %d: %v", i, err)
		}
		if m.Network != c.want {
			t.Fatalf("case %d: Network = %q, want %q", i, m.Network, c.want)
		}
	}
}

// jsonStr is a minimal JSON string encoder for the tests.
// jsonStr es un codificador JSON de string mínimo para los tests.
func jsonStr(s string) string {
	b := []byte{'"'}
	for i := 0; i < len(s); i++ {
		switch s[i] {
		case '"', '\\':
			b = append(b, '\\', s[i])
		default:
			b = append(b, s[i])
		}
	}
	return string(append(b, '"'))
}
