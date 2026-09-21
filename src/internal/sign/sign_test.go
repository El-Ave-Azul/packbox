// Tests for the sign package.
// Tests para el paquete sign.
package sign

import (
	"os"
	"path/filepath"
	"testing"
)

func TestKeygenSignVerify(t *testing.T) {
	cfg := t.TempDir()
	pub, err := Keygen(cfg)
	if err != nil {
		t.Fatal(err)
	}
	if pub == "" {
		t.Fatal("empty public key")
	}

	file := filepath.Join(t.TempDir(), "app.pbox")
	if err := os.WriteFile(file, []byte("PBOX-CONTENT"), 0644); err != nil {
		t.Fatal(err)
	}
	if HasSignature(file) {
		t.Fatal("no signature expected before signing")
	}

	sig, err := SignFile(file, cfg)
	if err != nil {
		t.Fatal(err)
	}
	if sig != SigPath(file) || !HasSignature(file) {
		t.Fatalf("signature not written correctly: %s", sig)
	}

	signer, err := VerifyFile(file, cfg)
	if err != nil {
		t.Fatalf("verify failed: %v", err)
	}
	if signer == "" {
		t.Fatal("empty signer")
	}
}

func TestVerifyTampered(t *testing.T) {
	cfg := t.TempDir()
	if _, err := Keygen(cfg); err != nil {
		t.Fatal(err)
	}
	file := filepath.Join(t.TempDir(), "a.pbox")
	if err := os.WriteFile(file, []byte("good"), 0644); err != nil {
		t.Fatal(err)
	}
	if _, err := SignFile(file, cfg); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(file, []byte("evil"), 0644); err != nil {
		t.Fatal(err)
	}
	if _, err := VerifyFile(file, cfg); err == nil {
		t.Fatal("a tampered package verified")
	}
}

func TestVerifyUntrusted(t *testing.T) {
	cfgA := t.TempDir()
	if _, err := Keygen(cfgA); err != nil {
		t.Fatal(err)
	}
	file := filepath.Join(t.TempDir(), "a.pbox")
	if err := os.WriteFile(file, []byte("x"), 0644); err != nil {
		t.Fatal(err)
	}
	if _, err := SignFile(file, cfgA); err != nil {
		t.Fatal(err)
	}

	// A config that trusts a different key must reject the signer.
	cfgB := t.TempDir()
	if _, err := Keygen(cfgB); err != nil {
		t.Fatal(err)
	}
	if _, err := VerifyFile(file, cfgB); err == nil {
		t.Fatal("an untrusted signer was accepted")
	}

	// Trusting A's public key makes verification pass.
	b, err := os.ReadFile(PubPath(cfgA))
	if err != nil {
		t.Fatal(err)
	}
	if err := Trust(cfgB, string(b)); err != nil {
		t.Fatal(err)
	}
	if _, err := VerifyFile(file, cfgB); err != nil {
		t.Fatalf("verify after trusting failed: %v", err)
	}
}

func TestTrustRejectsGarbage(t *testing.T) {
	if err := Trust(t.TempDir(), "not-base64!!"); err == nil {
		t.Fatal("garbage public key accepted")
	}
}
