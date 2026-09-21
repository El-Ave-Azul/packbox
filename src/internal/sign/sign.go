// Package sign implements ed25519 signing and verification of .pbox packages.
// El paquete sign implementa la firma y verificación ed25519 de paquetes .pbox.
//
// A detached signature <file>.pbox.sig holds the signer's public key and the
// signature over the package's SHA-256. Verification requires the signer's key
// to be trusted (in <config>/trusted/).
// Una firma separada <file>.pbox.sig contiene la clave pública del firmante y
// la firma sobre el SHA-256 del paquete. Verificar exige que la clave del
// firmante sea de confianza (en <config>/trusted/).
package sign

import (
	"crypto/ed25519"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
)

// Signature is the detached signature stored next to a package.
// Signature es la firma separada guardada junto a un paquete.
type Signature struct {
	Algo string `json:"algo"`
	Key  string `json:"key"` // base64 ed25519 public key
	Sig  string `json:"sig"` // base64 signature over sha256(file)
}

// KeyPath returns the private-key path.
func KeyPath(configDir string) string { return filepath.Join(configDir, "signing.key") }

// PubPath returns the public-key path.
func PubPath(configDir string) string { return filepath.Join(configDir, "signing.pub") }

// TrustedDir returns the trusted-keys directory.
func TrustedDir(configDir string) string { return filepath.Join(configDir, "trusted") }

// SigPath returns the detached-signature path for a file.
func SigPath(file string) string { return file + ".sig" }

// HasSignature reports whether file has a detached signature.
func HasSignature(file string) bool {
	_, err := os.Stat(SigPath(file))
	return err == nil
}

// Keygen creates a keypair (if absent) and self-trusts it, returning the public
// key (base64, std).
// Keygen crea un par de claves (si no existe) y se auto-confía, devolviendo la
// clave pública (base64 estándar).
func Keygen(configDir string) (string, error) {
	if err := os.MkdirAll(configDir, 0700); err != nil {
		return "", err
	}
	pub, priv, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		return "", err
	}
	if err := os.WriteFile(KeyPath(configDir), []byte(base64.StdEncoding.EncodeToString(priv)+"\n"), 0600); err != nil {
		return "", err
	}
	pubB64 := base64.StdEncoding.EncodeToString(pub)
	if err := os.WriteFile(PubPath(configDir), []byte(pubB64+"\n"), 0644); err != nil {
		return "", err
	}
	if err := Trust(configDir, pubB64); err != nil {
		return "", err
	}
	return pubB64, nil
}

// loadKey reads the private key.
// loadKey lee la clave privada.
func loadKey(configDir string) (ed25519.PrivateKey, error) {
	b, err := os.ReadFile(KeyPath(configDir))
	if err != nil {
		return nil, fmt.Errorf("no signing key (run: packbox-sign keygen): %w", err)
	}
	raw, err := base64.StdEncoding.DecodeString(strings.TrimSpace(string(b)))
	if err != nil {
		return nil, fmt.Errorf("bad key file: %w", err)
	}
	if len(raw) != ed25519.PrivateKeySize {
		return nil, fmt.Errorf("bad key size: %d", len(raw))
	}
	return ed25519.PrivateKey(raw), nil
}

// SignFile signs file and writes the detached signature beside it.
// SignFile firma file y escribe la firma separada a su lado.
func SignFile(file, configDir string) (string, error) {
	priv, err := loadKey(configDir)
	if err != nil {
		return "", err
	}
	digest, err := fileDigest(file)
	if err != nil {
		return "", err
	}
	sig := ed25519.Sign(priv, digest)
	pub := priv.Public().(ed25519.PublicKey)
	out := Signature{
		Algo: "ed25519",
		Key:  base64.StdEncoding.EncodeToString(pub),
		Sig:  base64.StdEncoding.EncodeToString(sig),
	}
	data, err := json.MarshalIndent(out, "", "  ")
	if err != nil {
		return "", err
	}
	p := SigPath(file)
	if err := os.WriteFile(p, data, 0644); err != nil {
		return "", err
	}
	return p, nil
}

// VerifyFile checks file against its detached signature and the trusted keys. It
// returns the signer's public key (hex) on success.
// VerifyFile comprueba file contra su firma separada y las claves de confianza.
// Devuelve la clave pública del firmante (hex) si va bien.
func VerifyFile(file, configDir string) (string, error) {
	data, err := os.ReadFile(SigPath(file))
	if err != nil {
		return "", fmt.Errorf("no signature: %w", err)
	}
	var s Signature
	if err := json.Unmarshal(data, &s); err != nil {
		return "", fmt.Errorf("bad signature file: %w", err)
	}
	if s.Algo != "ed25519" {
		return "", fmt.Errorf("unsupported algorithm %q", s.Algo)
	}
	pub, err := base64.StdEncoding.DecodeString(s.Key)
	if err != nil || len(pub) != ed25519.PublicKeySize {
		return "", fmt.Errorf("bad public key in signature")
	}
	if !isTrusted(configDir, s.Key) {
		return "", fmt.Errorf("signer %s is not trusted", hex.EncodeToString(pub))
	}
	sig, err := base64.StdEncoding.DecodeString(s.Sig)
	if err != nil {
		return "", fmt.Errorf("bad signature data")
	}
	digest, err := fileDigest(file)
	if err != nil {
		return "", err
	}
	if !ed25519.Verify(ed25519.PublicKey(pub), digest, sig) {
		return "", fmt.Errorf("signature does not match (tampered package?)")
	}
	return hex.EncodeToString(pub), nil
}

// Trust adds a public key (base64 std) to the trusted set.
// Trust añade una clave pública (base64 std) al conjunto de confianza.
func Trust(configDir, pubB64 string) error {
	pub, err := base64.StdEncoding.DecodeString(strings.TrimSpace(pubB64))
	if err != nil || len(pub) != ed25519.PublicKeySize {
		return fmt.Errorf("invalid public key")
	}
	dir := TrustedDir(configDir)
	if err := os.MkdirAll(dir, 0700); err != nil {
		return err
	}
	name := filepath.Join(dir, hex.EncodeToString(pub)+".pub")
	return os.WriteFile(name, []byte(base64.StdEncoding.EncodeToString(pub)+"\n"), 0644)
}

// isTrusted reports whether a public key is in the trusted set.
// isTrusted indica si una clave pública está en el conjunto de confianza.
func isTrusted(configDir, pubB64 string) bool {
	pub, err := base64.StdEncoding.DecodeString(pubB64)
	if err != nil {
		return false
	}
	_, err = os.Stat(filepath.Join(TrustedDir(configDir), hex.EncodeToString(pub)+".pub"))
	return err == nil
}

// fileDigest returns the SHA-256 of a file.
// fileDigest devuelve el SHA-256 de un archivo.
func fileDigest(file string) ([]byte, error) {
	f, err := os.Open(file)
	if err != nil {
		return nil, err
	}
	defer f.Close()
	h := sha256.New()
	if _, err := io.Copy(h, f); err != nil {
		return nil, err
	}
	return h.Sum(nil), nil
}
