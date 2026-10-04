// Package netproxy implements a lightweight network proxy that filters
// access to private IP addresses to provide a "limited" network mode.
// El paquete netproxy implementa un proxy de red ligero que filtra el
// acceso a direcciones IP privadas para proporcionar un modo de red "limitado".
package netproxy

import (
	"io"
	"net"
	"net/http"
)

// IsPrivateIP checks if an IP address is within private or reserved ranges.
// IsPrivateIP comprueba si una dirección IP está en rangos privados o reservados.
func IsPrivateIP(ip net.IP) bool {
	if ip == nil {
		return true
	}
	if ip.IsLoopback() || ip.IsLinkLocalUnicast() || ip.IsLinkLocalMulticast() {
		return true
	}

	privateCIDRs := []string{
		"10.0.0.0/8",
		"172.16.0.0/12",
		"192.168.0.0/16",
		"100.64.0.0/10",
		"169.254.0.0/16",
	}

	for _, cidr := range privateCIDRs {
		_, block, err := net.ParseCIDR(cidr)
		if err == nil && block.Contains(ip) {
			return true
		}
	}
	return false
}

// ProxyHandler implements a basic HTTP proxy that blocks private IPs.
// ProxyHandler implementa un proxy HTTP básico que bloquea IPs privadas.
type ProxyHandler struct{}

func (h *ProxyHandler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	// Only handle HTTP CONNECT (for HTTPS) and standard GET/POST
	if r.Method == http.MethodConnect {
		host, _, err := net.SplitHostPort(r.Host)
		if err != nil {
			http.Error(w, "Invalid host", http.StatusBadRequest)
			return
		}

		ip := net.ParseIP(host)
		if ip == nil {
			// Resolve hostname to check if it's private
			ips, err := net.LookupIP(host)
			if err != nil || len(ips) == 0 {
				http.Error(w, "Could not resolve host", http.StatusBadGateway)
				return
			}
			ip = ips[0]
		}

		if IsPrivateIP(ip) {
			http.Error(w, "Access to private network is blocked by Packbox", http.StatusForbidden)
			return
		}

		// Establish connection to destination
		destConn, err := net.Dial("tcp", r.Host)
		if err != nil {
			http.Error(w, "Connection failed", http.StatusBadGateway)
			return
		}
		defer destConn.Close()

		hijacker, ok := w.(http.Hijacker)
		if !ok {
			http.Error(w, "Hijacking not supported", http.StatusInternalServerError)
			return
		}

		conn, _, err := hijacker.Hijack()
		if err != nil {
			return
		}
		defer conn.Close()

		conn.Write([]byte("HTTP/1.1 200 Connection Established\r\n\r\n"))

		// Tunnel data
		errChan := make(chan error, 2)
		go func() {
			_, err := io.Copy(destConn, conn)
			errChan <- err
		}()
		go func() {
			_, err := io.Copy(conn, destConn)
			errChan <- err
		}()
		<-errChan
	} else {
		// For standard HTTP, check the destination
		host := r.URL.Hostname()
		ip := net.ParseIP(host)
		if ip == nil {
			ips, _ := net.LookupIP(host)
			if len(ips) > 0 {
				ip = ips[0]
			}
		}

		if IsPrivateIP(ip) {
			http.Error(w, "Access to private network is blocked by Packbox", http.StatusForbidden)
			return
		}

		// Forward the request
		resp, err := http.DefaultClient.Do(r)
		if err != nil {
			http.Error(w, "Proxy error", http.StatusBadGateway)
			return
		}
		defer resp.Body.Close()

		for k, v := range resp.Header {
			for _, vv := range v {
				w.Header().Add(k, vv)
			}
		}
		w.WriteHeader(resp.StatusCode)
		io.Copy(w, resp.Body)
	}
}

// StartProxy starts the proxy on a random port and returns the address.
// StartProxy arranca el proxy en un puerto aleatorio y devuelve la dirección.
func StartProxy() (string, error) {
	l, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		return "", err
	}
	addr := l.Addr().String()

	go func() {
		server := &http.Server{Handler: &ProxyHandler{}}
		_ = server.Serve(l)
	}()

	return addr, nil
}
