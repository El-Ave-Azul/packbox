// Tests for the hostcontract package.
// Tests para el paquete hostcontract.
package hostcontract

import (
	"testing"

	"github.com/packbox/packbox/internal/libpath"
)

func TestVersionToLib(t *testing.T) {
	cases := map[string]string{
		"GLIBC_2.34":     "libc.so.6",
		"GLIBCXX_3.4.29": "libstdc++.so.6",
		"CXXABI_1.3.13":  "libstdc++.so.6",
		"GCC_3.0":        "libgcc_s.so.1",
		"ZLIB_1.2.0":     "libz.so.1",
		"OTHER_1":        "",
	}
	for in, want := range cases {
		if got := versionToLib(in); got != want {
			t.Fatalf("versionToLib(%q) = %q, want %q", in, got, want)
		}
	}
}

func TestFilterDelegatable(t *testing.T) {
	in := []string{"libc.so.6", "libstdc++.so.6", "libz.so.1", "libfoo.so"}
	want := []string{"libc.so.6", "libz.so.1"}
	got := FilterDelegatable(in)
	if len(got) != len(want) {
		t.Fatalf("FilterDelegatable = %v, want %v", got, want)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("FilterDelegatable = %v, want %v", got, want)
		}
	}
}

func TestParseRequiredSymbols(t *testing.T) {
	out := `
Symbol table '.dynsym' contains 6 entries:
   Num:    Value          Size Type    Bind   Vis      Ndx Name
     1: 0000000000000000     0 FUNC    GLOBAL DEFAULT  UND open64@GLIBC_2.2.5 (2)
     2: 0000000000000000     0 FUNC    GLOBAL DEFAULT  UND malloc@GLIBC_2.2.5
     3: 0000000000000000     0 FUNC    GLOBAL DEFAULT  UND _ZSt4cout@@GLIBCXX_3.4
     4: 0000000000000000     0 FUNC    GLOBAL DEFAULT  UND inflate@ZLIB_1.2.0
     5: 0000000000001000    42 FUNC    GLOBAL DEFAULT   12 defined_func
     6: 0000000000000000     0 FUNC    GLOBAL DEFAULT  UND weird_symbol
`
	sym := ParseRequiredSymbols([]byte(out))
	if len(sym["libc.so.6"]) != 2 {
		t.Fatalf("libc symbols = %v, want 2 (open64, malloc)", sym["libc.so.6"])
	}
	if len(sym["libstdc++.so.6"]) != 1 {
		t.Fatalf("libstdc++ symbols = %v, want 1", sym["libstdc++.so.6"])
	}
	if len(sym["libz.so.1"]) != 1 {
		t.Fatalf("libz symbols = %v, want 1", sym["libz.so.1"])
	}
}

func TestHasSymbolsLibc(t *testing.T) {
	libc, err := libpath.Find("libc.so.6")
	if err != nil {
		t.Skip("libc.so.6 not found on host")
	}
	missing, err := HasSymbols(libc, []string{"malloc", "definitely_not_a_symbol_xyz"})
	if err != nil {
		t.Fatal(err)
	}
	if len(missing) != 1 || missing[0] != "definitely_not_a_symbol_xyz" {
		t.Fatalf("missing = %v, want [definitely_not_a_symbol_xyz]", missing)
	}
}
