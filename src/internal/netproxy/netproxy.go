// Package netproxy implements a best-effort network filter for the "limited"
// network mode: an HTTP proxy that refuses to reach private, loopback,
// link-local, CGNAT and other reserved ranges.
// El paquete netproxy implementa un filtro de red best-effort para el modo de
// red "limited": un proxy HTTP que se niega a alcanzar rangos privados,
// loopback, link-local, CGNAT y otros reservados.
//
// SCOPE / ALCANCE: it only affects apps that honor the http_proxy/https_proxy
// environment variables. An app opening raw sockets is NOT restricted (the
// sandbox shares the host network namespace in "limited" mode). Treat "limited"
// as a convenience filter, not a hard boundary.
// Solo afecta a apps que respetan http_proxy/https_proxy. Una app que abre
// sockets crudos NO queda restringida (el sandbox comparte la red del host en
// modo "limited"). Trátalo como filtro de comodidad, no como barrera sólida.
package netproxy

import (
	"errors"
	"io"
	"net"
	"net/http"
	"syscall"
	"time"
)

// errBlocked is returned by the filtered dialer when the target is not allowed.
// errBlocked lo devuelve el dialer filtrado cuando el destino no está permitido.
var errBlocked = errors.New("packbox: address blocked by the 'limited' network policy")

// reservedCIDRs are the non-global ranges "limited" must never reach.
// reservedCIDRs son los rangos no globales que "limited" nunca debe alcanzar.
var reservedCIDRs = func() []*net.IPNet {
	cidrs := []string{
		// IPv4
		"0.0.0.0/8",       // "this network"
		"10.0.0.0/8",      // RFC1918
		"100.64.0.0/10",   // CGNAT (RFC6598)
		"127.0.0.0/8",     // loopback
		"169.254.0.0/16",  // link-local
		"172.16.0.0/12",   // RFC1918
		"192.0.0.0/24",    // IETF protocol assignments
		"192.0.2.0/24",    // TEST-NET-1
		"192.168.0.0/16",  // RFC1918
		"198.18.0.0/15",   // benchmarking
		"198.51.100.0/24", // TEST-NET-2
		"203.0.113.0/24",  // TEST-NET-3
		"224.0.0.0/4",     // multicast
		"240.0.0.0/4",     // reserved
		"255.255.255.255/32",
		// IPv6
		"::/128",        // unspecified
		"::1/128",       // loopback
		"fc00::/7",      // unique local
		"fe80::/10",     // link-local
		"ff00::/8",      // multicast
		"2001:db8::/32", // documentation
	}
	out := make([]*net.IPNet, 0, len(cidrs))
	for _, s := range cidrs {
		if _, n, err := net.ParseCIDR(s); err == nil {
			out = append(out, n)
		}
	}
	return out
}()

// IsPrivateIP reports whether ip is not a global (public) address: loopback,
// private, link-local, CGNAT, multicast, unspecified or otherwise reserved. A
// nil IP is blocked (fail closed).
// IsPrivateIP indica si ip no es una dirección global (pública): loopback,
// privada, link-local, CGNAT, multicast, no especificada u otra reservada. Un
// IP nil se bloquea (fail closed).
func IsPrivateIP(ip net.IP) bool {
	if ip == nil {
		return true
	}
	if ip.IsLoopback() || ip.IsUnspecified() || ip.IsLinkLocalUnicast() ||
		ip.IsLinkLocalMulticast() || ip.IsInterfaceLocalMulticast() || ip.IsMulticast() {
		return true
	}
	for _, n := range reservedCIDRs {
		if n.Contains(ip) {
			return true
		}
	}
	return false
}

// filteredDialer returns a dialer that refuses blocked addresses at connect
// time (Control runs with the resolved address, so it also covers redirects
// and avoids a DNS-rebinding gap between check and dial).
// filteredDialer devuelve un dialer que rechaza direcciones bloqueadas al
// conectar (Control recibe la dirección ya resuelta, así cubre también las
// redirecciones y evita un hueco de DNS-rebinding entre comprobar y conectar).
func filteredDialer() *net.Dialer {
	return &net.Dialer{
		Timeout: 10 * time.Second,
		Control: func(_, address string, _ syscall.RawConn) error {
			host, _, err := net.SplitHostPort(address)
			if err != nil {
				return err
			}
			if IsPrivateIP(net.ParseIP(host)) {
				return errBlocked
			}
			return nil
		},
	}
}

// hostBlocked reports whether host is, or resolves to, a blocked address, or
// cannot be resolved (fail closed). Used to answer 403 before dialing.
// hostBlocked indica si host es, o resuelve a, una dirección bloqueada, o no se
// puede resolver (fail closed). Se usa para responder 403 antes de conectar.
func hostBlocked(host string) bool {
	if ip := net.ParseIP(host); ip != nil {
		return IsPrivateIP(ip)
	}
	ips, err := net.LookupIP(host)
	if err != nil || len(ips) == 0 {
		return true
	}
	for _, ip := range ips {
		if IsPrivateIP(ip) {
			return true
		}
	}
	return false
}

// ProxyHandler is an HTTP proxy that blocks non-global destinations.
// ProxyHandler es un proxy HTTP que bloquea destinos no globales.
type ProxyHandler struct{}

func (h *ProxyHandler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	if r.Method == http.MethodConnect {
		h.handleConnect(w, r)
		return
	}
	h.handleHTTP(w, r)
}

// handleConnect tunnels an HTTPS (CONNECT) session.
// handleConnect tunela una sesión HTTPS (CONNECT).
func (h *ProxyHandler) handleConnect(w http.ResponseWriter, r *http.Request) {
	host, _, err := net.SplitHostPort(r.Host)
	if err != nil {
		http.Error(w, "invalid host", http.StatusBadRequest)
		return
	}
	if hostBlocked(host) {
		http.Error(w, "private network blocked by Packbox (limited)", http.StatusForbidden)
		return
	}
	destConn, err := filteredDialer().Dial("tcp", r.Host)
	if err != nil {
		if errors.Is(err, errBlocked) {
			http.Error(w, "private network blocked by Packbox (limited)", http.StatusForbidden)
			return
		}
		http.Error(w, "connection failed", http.StatusBadGateway)
		return
	}
	defer destConn.Close()

	hj, ok := w.(http.Hijacker)
	if !ok {
		http.Error(w, "hijacking not supported", http.StatusInternalServerError)
		return
	}
	conn, _, err := hj.Hijack()
	if err != nil {
		return
	}
	defer conn.Close()
	if _, err := conn.Write([]byte("HTTP/1.1 200 Connection Established\r\n\r\n")); err != nil {
		return
	}

	done := make(chan struct{}, 2)
	go func() { _, _ = io.Copy(destConn, conn); done <- struct{}{} }()
	go func() { _, _ = io.Copy(conn, destConn); done <- struct{}{} }()
	<-done
}

// handleHTTP forwards a plain HTTP request, re-checking redirects.
// handleHTTP reenvía una petición HTTP plana, re-comprobando las redirecciones.
func (h *ProxyHandler) handleHTTP(w http.ResponseWriter, r *http.Request) {
	host := r.URL.Hostname()
	if host == "" {
		http.Error(w, "bad request", http.StatusBadRequest)
		return
	}
	if hostBlocked(host) {
		http.Error(w, "private network blocked by Packbox (limited)", http.StatusForbidden)
		return
	}
	client := &http.Client{
		Transport: &http.Transport{
			DialContext:           filteredDialer().DialContext,
			ResponseHeaderTimeout: 30 * time.Second,
		},
		CheckRedirect: func(req *http.Request, via []*http.Request) error {
			if len(via) >= 10 {
				return errors.New("too many redirects")
			}
			if hostBlocked(req.URL.Hostname()) {
				return errBlocked
			}
			return nil
		},
	}
	out := r.Clone(r.Context())
	out.RequestURI = "" // a client request must not carry the server's RequestURI
	resp, err := client.Do(out)
	if err != nil {
		http.Error(w, "proxy error", http.StatusBadGateway)
		return
	}
	defer resp.Body.Close()
	for k, vs := range resp.Header {
		for _, v := range vs {
			w.Header().Add(k, v)
		}
	}
	w.WriteHeader(resp.StatusCode)
	_, _ = io.Copy(w, resp.Body)
}

// StartProxy starts the proxy on a random loopback port and returns its address.
// StartProxy arranca el proxy en un puerto aleatorio de loopback y devuelve su
// dirección.
func StartProxy() (string, error) {
	l, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		return "", err
	}
	addr := l.Addr().String()
	go func() {
		srv := &http.Server{
			Handler:           &ProxyHandler{},
			ReadHeaderTimeout: 10 * time.Second,
		}
		_ = srv.Serve(l)
	}()
	return addr, nil
}
