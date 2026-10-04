// Tests for the netproxy package.
// Tests para el paquete netproxy.
package netproxy

import (
	"bufio"
	"errors"
	"net"
	"strings"
	"testing"
	"time"
)

func TestIsPrivateIP(t *testing.T) {
	blocked := []string{
		"127.0.0.1", "10.0.0.1", "172.16.5.4", "192.168.1.1", "100.64.0.1",
		"169.254.1.1", "0.0.0.0", "224.0.0.1", "240.0.0.1", "192.0.2.1",
		"::1", "fe80::1", "fc00::1", "ff02::1", "::ffff:10.0.0.1",
	}
	for _, s := range blocked {
		if !IsPrivateIP(net.ParseIP(s)) {
			t.Errorf("IsPrivateIP(%s) = false, want true", s)
		}
	}
	public := []string{"8.8.8.8", "1.1.1.1", "93.184.216.34", "2001:4860:4860::8888"}
	for _, s := range public {
		if IsPrivateIP(net.ParseIP(s)) {
			t.Errorf("IsPrivateIP(%s) = true, want false", s)
		}
	}
	if !IsPrivateIP(nil) {
		t.Error("IsPrivateIP(nil) = false, want true (fail closed)")
	}
}

func TestFilteredDialerBlocksPrivate(t *testing.T) {
	_, err := filteredDialer().Dial("tcp", "127.0.0.1:1")
	if !errors.Is(err, errBlocked) {
		t.Fatalf("dial to a private IP: err = %v, want errBlocked", err)
	}
}

// proxyReq sends a raw request to the proxy and returns its status line.
// proxyReq envía una petición cruda al proxy y devuelve su línea de estado.
func proxyReq(t *testing.T, addr, req string) string {
	t.Helper()
	conn, err := net.Dial("tcp", addr)
	if err != nil {
		t.Fatal(err)
	}
	defer conn.Close()
	_ = conn.SetDeadline(time.Now().Add(5 * time.Second))
	if _, err := conn.Write([]byte(req)); err != nil {
		t.Fatal(err)
	}
	line, err := bufio.NewReader(conn).ReadString('\n')
	if err != nil && line == "" {
		t.Fatalf("no response: %v", err)
	}
	return line
}

func TestProxyBlocksPrivate(t *testing.T) {
	addr, err := StartProxy()
	if err != nil {
		t.Fatal(err)
	}

	// CONNECT to a private address → 403 (checked before dialing).
	line := proxyReq(t, addr, "CONNECT 127.0.0.1:443 HTTP/1.1\r\nHost: 127.0.0.1:443\r\n\r\n")
	if !strings.Contains(line, "403") {
		t.Errorf("CONNECT to private: status = %q, want 403", strings.TrimSpace(line))
	}

	// Plain HTTP to a private address → 403.
	line = proxyReq(t, addr, "GET http://192.168.1.1/ HTTP/1.1\r\nHost: 192.168.1.1\r\n\r\n")
	if !strings.Contains(line, "403") {
		t.Errorf("GET to private: status = %q, want 403", strings.TrimSpace(line))
	}

	// An unresolvable host fails closed → 403.
	line = proxyReq(t, addr, "GET http://packbox-no-such-host.invalid/ HTTP/1.1\r\nHost: packbox-no-such-host.invalid\r\n\r\n")
	if !strings.Contains(line, "403") {
		t.Errorf("GET to unresolvable host: status = %q, want 403 (fail closed)", strings.TrimSpace(line))
	}
}
