# Packbox

**[Español](../../README.md)** · **[English](README.md)** · [Français](../fr/README.md) · [Deutsch](../de/README.md) · [Italiano](../it/README.md) · [Português](../pt/README.md) · [中文](../zh/README.md) · [日本語](../ja/README.md) · [한국어](../ko/README.md)

---

![CI](https://github.com/El-Ave-Azul/packbox/actions/workflows/ci.yml/badge.svg)
![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)
![Version](https://img.shields.io/badge/Version-0.3.0-orange.svg)
![Platform](https://img.shields.io/badge/Platform-Linux-blue.svg)
![Go](https://img.shields.io/badge/Go-1.22+-00ADD8.svg?logo=go&logoColor=white)
![i18n](https://img.shields.io/badge/i18n-9_languages-green.svg)
![Status](https://img.shields.io/badge/Status-Beta-blue.svg)

**Linux application packager with per-chunk binary deduplication and a Zstd-compressed `.pbox` export.**
Inspired by Flatpak, but with a different reuse model: instead of a
monolithic runtime per app, Packbox stores content in a
content-addressed store (BLAKE3 CAS), with optimized **content-defined chunking
(CDC)** and reusable **cells**. Two apps that share 90% of their
libraries only store the 10% that differs.

> [!IMPORTANT]
> **Beta Status (v0.3.0).** The system has evolved core stability, implementing LRU garbage collection, Zstd compression on export, and a modern graphical interface in GTK4.

---

## Table of contents

- [What is Packbox?](#what-is-packbox)
- [Comparison with Flatpak](#comparison-with-flatpak)
- [Requirements](#requirements)
- [Installation](#installation)
- [Quick start](#quick-start)
- [Available commands](#available-commands)
- [File structure](#file-structure)
- [Architecture](#architecture)
- [Security](#security)
- [Roadmap](#roadmap)
- [Contributing](#contributing)
- [License](#license)
- [Acknowledgments](#acknowledgments)

---

## What is Packbox?

Packbox packages Linux applications using **Content-Addressable Storage (CAS)**
with **BLAKE3** hashing and optimized **content-defined chunking**, to achieve real
binary deduplication between apps.

Instead of a ~1 GB runtime per application (Flatpak), Packbox stores each
file in chunks (deduplicated by content) and shares them across all
apps; **Zstd** compression is applied when exporting the `.pbox`. It also turns
each library into a **cell** (a versioned reuse
unit) that several apps share, and leaves the universal libraries
(`libc`, `libm`, …) to the host.

### Design principles

- **Chunk-level deduplication.** Same bytes = same hash = stored once
  (CDC optimized for ELF binaries; single file for small ones).
- **Raw store, compressed export.** The CAS keeps chunks uncompressed so install
  can **hardlink** them (real on-disk dedup); **Zstd** compression is applied when
  building the `.pbox`.
- **Cells (atomic fragmentation).** Each non-universal lib is a cell;
  the app declares it and the installer resolves it.
- **Cross-app sharing.** All apps share the same global CAS and the
  same cells.
- **Host contract v1.** Selective delegation of universal libraries, with
  **ABI checking** of the required symbols.
- **Hardened sandbox (bubblewrap).** `--unshare-all`, `--cap-drop ALL`,
  **seccomp**, **filtered D-Bus** (`xdg-dbus-proxy`), **private HOME per app**,
  granular network (none/limited/full) and **opt-in X11 with autodetection**.
- **Layered overlay.** `/app` is composed as an overlay of A (app) on C
  (cells), with S (host) via `/usr`.
- **Signatures and distribution.** Signable `.pbox` (ed25519) and HTTP remote with
  concurrent delta download.
- **4 packaging modes.** Normal, Portable, Bundle, Module.

---

## Comparison with Flatpak

| Feature               | Flatpak (current)            | Packbox v0.3.0                       |
|----------------------|-----------------------------|--------------------------------------|
| Reuse unit           | Complete runtime (~1 GB)    | **Cells** per lib (no runtimes)      |
| Deduplication        | File-level (OSTree)         | **Chunk**-level (BLAKE3 + CDC)       |
| Storage             | Compressed per runtime     | **Raw chunks + hardlink** (dedup)     |
| Lib sharing          | Within the same runtime     | Cross-app, across all apps           |
| Use of host libs     | None                        | Selective (host contract + ABI)      |
| Updates              | OSTree object delta         | `packbox-update` (delta + LRU GC)    |
| Distribution         | Flathub + OSTree remotes    | Concurrent HTTP remote              |
| Signatures           | GPG                         | ed25519 (`.pbox.sig`)                |
| Sandbox              | bwrap + seccomp + portals   | bwrap + seccomp + dbus-proxy + portals |
| Interface           | GNOME Software / CLI        | **GUI (GTK4)** + TUI + CLI            |
| Overhead per app     | ~100% if runtime differs    | **~5–15%** with apps that share      |

---

## Requirements

- **Operating system**: Linux (Debian 12+, Ubuntu 22.04+, Fedora 40+, Arch,
  openSUSE Tumbleweed)
- **Kernel**: 5.15+ with user namespaces enabled
- **Shell**: Bash 4.0+
- **Go**: 1.22+ (the installer downloads its own copy if missing)
- **Space**: ~500 MB free for the initial build
- **Internet**: only for the first installation

### System dependencies

Installed by the installer when possible; also useful manually:

`bubblewrap` · `binutils` (`ldd`/`readelf`) · `jq` · `bc` · `curl` · `tar` ·
`xdg-dbus-proxy` (D-Bus filtering) · `zstd` or `xz` (more compact export)

---

## Installation

### Step 1 — Clone and run

```bash
git clone https://github.com/El-Ave-Azul/packbox.git
cd packbox
./packbox-install.sh
```

The installer opens a menu; choose option **1** (Install).

### Step 2 — Reload the shell

```bash
source ~/.bashrc
```

### Step 3 — Verify

```bash
packbox-diagnose
```

---

## Quick start

### 1. Graphical Interface (Recommended)
Run `packbox-gui` to manage your applications, configure sandbox permissions, and monitor space savings in real-time.

### 2. Interactive packager (TUI)

```bash
./packbox-packager.sh
```

Option **1 (Package)** looks for **already installed** apps and **generates a**
`.pbox` in `~/.local/share/packbox/exports/`. Upon completion, it asks if you also
want to **install it on this machine** (default **no**, to avoid cluttering your
system). To install a `.pbox`, use option **5 (Import)**.

### 3. Command line

```bash
# Package a directory
packbox-pack ./my-app --name org.example.myapp --version 1.0.0

# Install from the generated manifest
packbox-install ./my-app/manifest.json

# Run in the sandbox (overlay A on C; private HOME)
packbox-run org.example.myapp

# List apps (real size and savings from sharing) and free space
packbox-list
packbox-remove org.example.myapp
packbox-gc

# Update an installed app reusing chunks from the store
packbox-update org.example.myapp ./new/manifest.json
```

---

## Available commands

Packbox v0.3.0 includes **16 Go binaries** in `~/.packbox/bin/`:

| Command            | Purpose                                                            |
|--------------------|--------------------------------------------------------------------|
| `packbox-gui`      | Graphical interface for app and permission management               |
| `packbox-pack`     | Hashes a directory into CAS chunks and generates `manifest.json`   |
| `packbox-install`  | Installs an app from the manifest (+ `--desktop`/`--remove-desktop`) |
| `packbox-run`      | Runs the app in the `bwrap` sandbox (overlay A/C, private HOME)    |
| `packbox-list`     | Lists apps with their **real size** and savings from sharing (`--tsv`) |
| `packbox-remove`   | Uninstalls an app (`--all` = all, `--dry-run`) and frees its refs   |
| `packbox-gc`       | Collects unreferenced chunks **and cells** (Supports LRU)            |
| `packbox-verify`   | Checks resolvable libs + **ABI compatibility** of the host         |
| `packbox-export`   | Exports to `.pbox` with **adaptive compression** and optional `--sign` |
| `packbox-import`   | Imports a `.pbox` (anti tar-slip, traversal and signatures)        |
| `packbox-update`   | Updates an app reusing chunks + delta report (`--no-gc`)           |
| `packbox-module`   | Modules/cells: `list`, `create`, `cell <lib>...`                   |
| `packbox-sign`     | ed25519 keys and signatures: `keygen`, `sign`, `verify`, `trust`   |
| `packbox-fetch`    | Concurrent HTTP remote: `publish <id> <dir>` and `fetch <id> --from <url>` |
| `packbox-debug`    | Attaches the debug symbols (separate cell) of an installed app     |
| `packbox-diagnose` | Environment report for bug reports                                 |

---

## Architecture

### Packaging flow

```
┌──────────────┐   pack    ┌──────────────┐  install  ┌──────────────┐
│  Source dir  │ ────────► │     CAS      │ ─────────► │  App tree    │
│  (fs tree)   │           │  (chunks)    │           │ (hardlinks)  │
└──────────────┘           └──────────────┘           └──────┬───────┘
                                    │                          │ + cells (layer C)
                                    │ run                      ▼
                         ┌──────────────────────────────────────────┐
                         │  bwrap sandbox: /app = overlay A on C    │
                         │  private HOME · seccomp · filtered D-Bus  │
                         └──────────────────────────────────────────┘
```

### Internal components

- **CAS + chunker** — Stores raw chunks (no recompression, so they can be hardlinked) by **BLAKE3** hash. Large files are split with **optimized CDC**; small ones go as a single chunk. **Atomic** writes.
- **Manifest** (`schema_version: \"1.7\"`) — Maps paths to chunks, defines the network policy (`none`, `limited`, `full`), the host contract, and the X11 symbol.
- **Cells** — One lib = one cell `org.lib.<soname>@<hash>` in `mods/`. Shared between apps. `packbox-gc` deletes unreferenced or old ones (LRU).
- **Sandbox** — `bwrap --unshare-all --cap-drop ALL --clearenv`, **seccomp**, **filtered D-Bus** with `xdg-dbus-proxy`, **private HOME**, granular network and **Multimedia Support** (PipeWire/PulseAudio).
- **Layer overlay** — `/app` is composed with `--overlay-src` (C below, A above); S (host) arrives via `/usr`.
- **Host contract** — `packbox-verify` checks that the host provides the required symbols (ABI).
- **Signatures and remote** — `packbox-sign` (ed25519) signs the `.pbox`; `packbox-fetch` publishes and downloads the delta via **concurrent downloads**.

---

## Security

### Implemented mitigations

- **Per-app data isolation** — Each app runs with its **private HOME**; only fonts/themes are exposed **read-only**.
- **Filtered D-Bus** — `xdg-dbus-proxy` with an allowlist (portals + `dconf`).
- **seccomp** — Default filter that blocks dangerous kernel surface.
- **Granular Network** — Supports `limited` mode which blocks local network access (RFC 1918) via an internal proxy.
- **Secure Multimedia Support** — Mediated access to audio and camera via portals.
- **Anti tar-slip / traversal** — Strict path validation in `.pbox`.
- **Environment cleanup** — `--clearenv` + explicit whitelist.
- **Reference counting + LRU GC** — Intelligent chunk cleanup based on access time.
- **Signatures** — `.pbox` signable with **ed25519**.

---

## Roadmap

### v0.1.x — Stabilization
- [x] Signature verification for `.pbox`
- [x] Hardened sandbox: private HOME, filtered D-Bus, seccomp
- [x] Automatic cells + layer overlay (A/C/S)
- [x] `packbox-update` with chunk delta + automatic GC
- [x] HTTP remote with concurrent delta download
- [x] Zstd compression in the `.pbox` export
- [x] CDC tuning for ELF binaries
- [x] LRU garbage collection

### v0.2 — Scope
- [x] GTK4 GUI Frontend
- [ ] Precompiled x86_64 and aarch64 binaries
- [ ] Signed central index/repository

### Future
- [ ] Flatpak runtime importer (best-effort)
- [ ] WASM sandbox for untrusted plugins

---

## License

Distributed under the **Apache License 2.0**. See [LICENSE](../../LICENSE).
