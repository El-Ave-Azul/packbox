//go:build linux

// Seccomp filter construction for the sandbox.
// Construcción del filtro seccomp para el sandbox.
package sandbox

import (
	"encoding/binary"

	"golang.org/x/sys/unix"
)

// Classic BPF / seccomp constants.
// Constantes de BPF clásico / seccomp.
const (
	bpfLdAbs  = 0x20 // BPF_LD | BPF_W | BPF_ABS
	bpfJmpEqK = 0x15 // BPF_JMP | BPF_JEQ | BPF_K
	bpfRetK   = 0x06 // BPF_RET | BPF_K

	seccompRetAllow = 0x7fff0000
	seccompRetErrno = 0x00050000
	seccompErrEPERM = 1
)

// buildSeccompFilter returns an allow-by-default filter that makes the listed
// syscalls fail with EPERM:
//
//	LD  seccomp_data.nr
//	for each nr: JEQ nr (else skip); RET ERRNO(EPERM)
//	RET ALLOW
//
// buildSeccompFilter devuelve un filtro que permite por defecto y hace fallar
// con EPERM los syscalls listados.
func buildSeccompFilter(nrs []uint32) []unix.SockFilter {
	f := make([]unix.SockFilter, 0, 2*len(nrs)+2)
	f = append(f, unix.SockFilter{Code: bpfLdAbs, K: 0})
	for _, nr := range nrs {
		f = append(f, unix.SockFilter{Code: bpfJmpEqK, Jt: 0, Jf: 1, K: nr})
		f = append(f, unix.SockFilter{Code: bpfRetK, K: seccompRetErrno | seccompErrEPERM})
	}
	f = append(f, unix.SockFilter{Code: bpfRetK, K: seccompRetAllow})
	return f
}

// seccompBytes serializes a filter to the raw sock_filter array the kernel (and
// bwrap's --seccomp) expect.
// seccompBytes serializa un filtro al array sock_filter crudo que esperan el
// kernel (y el --seccomp de bwrap).
func seccompBytes(f []unix.SockFilter) []byte {
	out := make([]byte, 0, len(f)*8)
	var b [8]byte
	for _, ins := range f {
		binary.LittleEndian.PutUint16(b[0:2], ins.Code)
		b[2] = ins.Jt
		b[3] = ins.Jf
		binary.LittleEndian.PutUint32(b[4:8], ins.K)
		out = append(out, b[:]...)
	}
	return out
}

// defaultBlockedSyscalls is a conservative deny-list: dangerous kernel surface
// a normal app never needs (modules, keyring, ptrace, bpf, perf, io_uring,
// userfaultfd, cross-process memory, file-handles, reboot/swap).
// defaultBlockedSyscalls es una lista negra conservadora: superficie peligrosa
// del kernel que una app normal no necesita.
func defaultBlockedSyscalls() []uint32 {
	return []uint32{
		uint32(unix.SYS_ADD_KEY),
		uint32(unix.SYS_REQUEST_KEY),
		uint32(unix.SYS_KEYCTL),
		uint32(unix.SYS_PTRACE),
		uint32(unix.SYS_BPF),
		uint32(unix.SYS_PERF_EVENT_OPEN),
		uint32(unix.SYS_USERFAULTFD),
		uint32(unix.SYS_IO_URING_SETUP),
		uint32(unix.SYS_IO_URING_ENTER),
		uint32(unix.SYS_IO_URING_REGISTER),
		uint32(unix.SYS_PROCESS_VM_READV),
		uint32(unix.SYS_PROCESS_VM_WRITEV),
		uint32(unix.SYS_OPEN_BY_HANDLE_AT),
		uint32(unix.SYS_NAME_TO_HANDLE_AT),
		uint32(unix.SYS_INIT_MODULE),
		uint32(unix.SYS_FINIT_MODULE),
		uint32(unix.SYS_DELETE_MODULE),
		uint32(unix.SYS_KEXEC_LOAD),
		uint32(unix.SYS_KEXEC_FILE_LOAD),
		uint32(unix.SYS_REBOOT),
		uint32(unix.SYS_SWAPON),
		uint32(unix.SYS_SWAPOFF),
		uint32(unix.SYS_ACCT),
	}
}
