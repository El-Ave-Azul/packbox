// packbox-sign manages signing keys and signs/verifies .pbox packages.
// packbox-sign gestiona claves de firma y firma/verifica paquetes .pbox.
package main

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/packbox/packbox/internal/sign"
)

func configDir() string {
	return filepath.Join(os.Getenv("HOME"), ".config/packbox")
}

func usage() {
	fmt.Println("Usage: packbox-sign <keygen|sign|verify|trust> [args]")
	fmt.Println("  keygen                 create a signing key (and trust it)")
	fmt.Println("  sign <file>            write <file>.sig for <file>")
	fmt.Println("  verify <file>          verify <file> against trusted keys")
	fmt.Println("  trust <pubkey|file>    trust a signer's public key (base64)")
	os.Exit(1)
}

func main() {
	if len(os.Args) < 2 {
		usage()
	}
	switch os.Args[1] {
	case "keygen":
		pub, err := sign.Keygen(configDir())
		if err != nil {
			fmt.Printf("ERROR: %v\n", err)
			os.Exit(1)
		}
		fmt.Printf("[ok] signing key created\n")
		fmt.Printf("public key: %s\n", pub)
		fmt.Println("Share it so others can trust your packages (packbox-sign trust <pubkey>).")

	case "sign":
		if len(os.Args) < 3 {
			usage()
		}
		p, err := sign.SignFile(os.Args[2], configDir())
		if err != nil {
			fmt.Printf("ERROR: %v\n", err)
			os.Exit(1)
		}
		fmt.Printf("[ok] signed: %s\n", p)

	case "verify":
		if len(os.Args) < 3 {
			usage()
		}
		signer, err := sign.VerifyFile(os.Args[2], configDir())
		if err != nil {
			fmt.Printf("[fail] %v\n", err)
			os.Exit(1)
		}
		fmt.Printf("[ok] signed by %s\n", signer)

	case "trust":
		if len(os.Args) < 3 {
			usage()
		}
		arg := os.Args[2]
		if b, err := os.ReadFile(arg); err == nil { // allow a file holding the key
			arg = strings.TrimSpace(string(b))
		}
		if err := sign.Trust(configDir(), arg); err != nil {
			fmt.Printf("ERROR: %v\n", err)
			os.Exit(1)
		}
		fmt.Println("[ok] trusted")

	default:
		usage()
	}
}
