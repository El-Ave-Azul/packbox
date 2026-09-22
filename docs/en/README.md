# Packbox

[Español](../../README.md) · **[English](README.md)** · [Français](../fr/README.md) · [Deutsch](../de/README.md) · [Italiano](../it/README.md) · [Português](../pt/README.md) · [中文](../zh/README.md) · [日本語](../ja/README.md) · [한국어](../ko/README.md)

---

![License](https://img.shields.io/badge/Licencia-Apache_2.0-blue.svg)
![Version](https://img.shields.io/badge/Versión-0.2.0-orange.svg)
![Platform](https://img.shields.io/badge/Plataforma-Linux-blue.svg)
![Go](https://img.shields.io/badge/Go-1.22+-00ADD8.svg?logo=go&logoColor=white)
![i18n](https://img.shields.io/badge/i18n-9_idiomas-green.svg)
![Status](https://img.shields.io/badge/Estado-Alpha-red.svg)

**Linux application packager with per-chunk binary deduplication.**
Inspired by Flatpak, but with a different reuse model: instead of a
monolithic runtime per app, Packbox stores content in a
content-addressed store (BLAKE3 CAS), with **content-defined chunking
(CDC)** and reusable **cells**. Two apps that share 90% of their
libraries only store the 10% that differs.

> [!WARNING]
> **Alpha status (v0.2.0).** The main workflows work and there are already signatures,
> hardened sandbox (seccomp, filtered D-Bus, private HOME) and HTTP remote, but
> the project is young and does not have the ecosystem or the maturity of Flatpak. Use it
> first on non-critical systems.

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
with **BLAKE3** hashing and **content-defined chunking**, to achieve real
binary deduplication between apps.

Instead of a ~1 GB runtime per application (Flatpak), Packbox stores each
file as content-addressed chunks and shares it across all
apps. It also turns each library into a **cell** (a versioned reuse
unit) that several apps share, and leaves the universal libraries
(`libc`, `libm`, …) to the host.

### Design principles

- **Chunk-level deduplication.** Same bytes = same hash = stored once
  (CDC on large files; a single file on small ones, so they can be
  hardlinked and shared).
- **Cells (atomic fragmentation).** Each non-universal lib is a cell;
  the app declares it and the installer resolves it.
- **Cross-app sharing.** All apps share the same global CAS and the
  same cells.
- **Host contract v1.** Selective delegation of universal libraries, with
  **ABI checking** of the required symbols.
- **Hardened sandbox (bubblewrap).** `--unshare-all`, `--cap-drop ALL`,
  **seccomp**, **filtered D-Bus** (`xdg-dbus-proxy`), **private HOME per app**,
  opt-in network and **opt-in X11 with autodetection**.
- **Layered overlay.** `/app` is composed as an overlay of A (app) on C
  (cells), with S (host) via `/usr`.
- **Signatures and distribution.** Signable `.pbox` (ed25519) and HTTP remote with
  delta download.
- **4 packaging modes.** Normal, Portable, Bundle, Module.

---

## Comparison with Flatpak

| Feature               | Flatpak (current)           | Packbox v0.2.0                       |
|----------------------|-----------------------------|--------------------------------------|
| Reuse unit           | Complete runtime (~1 GB)    | **Cells** per lib (no runtimes)      |
| Deduplication        | File-level (OSTree)         | **Chunk**-level (BLAKE3 + CDC)       |
| Lib sharing          | Within the same runtime     | Cross-app, across all apps           |
| Use of host libs     | None                        | Selective (host contract + ABI)      |
| Updates              | OSTree object delta         | `packbox-update` (chunk delta + GC)  |
| Distribution         | Flathub + OSTree remotes    | HTTP remote with `publish`/`fetch`   |
| Signatures           | GPG                         | ed25519 (`.pbox.sig`)                |
| Sandbox              | bwrap + seccomp + portals   | bwrap + seccomp + dbus-proxy + portals |
| Overhead per app     | ~100% if runtime differs    | **~5–15%** with apps that share      |

**Measured savings** (this codebase): two medium GTK4 apps that share their
stack add up to ~264 MB separately and take up **~141 MB real (−46%)**; with 10
mixed apps the savings rise to **~69%**. The greater the library
overlap, the greater the savings — but it is worth measuring it case by case, rather than
assuming the 90–99% of a shared runtime.

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

### What the installer does

1. Lets you select one of 9 languages.
2. Detects your Linux distribution and package manager.
3. Asks for confirmation before installing dependencies.
4. Downloads and verifies Go (1.27.1 by default) in `~/.packbox/go` if needed.
5. Creates the directory structure (`~/.packbox/` and `~/.local/share/packbox/`).
6. Copies the sources and builds the **15 Go binaries** (~1–2 minutes).
7. Configures your `PATH` in `~/.bashrc` and creates symlinks in `~/.local/bin`.
8. Installs the language files in `~/.config/packbox/lang/`.
9. Verifies that all binaries are present and functional.

### Uninstallation

Run the same script and choose option **2**:

```bash
./packbox-install.sh --uninstall
```

| Mode | Description |
|------|-------------|
| `s`  | Complete: binaries + apps + CAS store + cells + menus + icons + config |
| `k`  | Binaries only: `~/.packbox/` and symlinks (keeps apps and CAS store) |
| `q`  | Cancel |

---

## Quick start

### 1. Interactive packager (recommended)

```bash
./packbox-packager.sh
```

Menu: package, list, garbage collection, export, import, uninstall,
language. Detects apps from `.desktop` in `/usr/share/applications/`, bundles in
`/opt/*` and common binaries (`htop`, `btop`, `firefox`, `gimp`, …).

In **Normal** and **Portable** modes each non-universal lib of the `ldd`
closure automatically becomes a **cell**.

### 2. Command line

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

### 3. Export, sign, import and distribute

```bash
# Export and sign
packbox-sign keygen                       # creates your key (and trusts it)
packbox-export --sign app org.example.myapp
packbox-sign verify ~/.local/share/packbox/exports/org.example.myapp.pbox

# Publish an HTTP remote and use it from another machine
packbox-fetch publish org.example.myapp /srv/packbox
(cd /srv/packbox && python3 -m http.server 8000)
packbox-fetch fetch org.example.myapp --from http://host:8000

# Import (verifies the signature if it exists)
packbox-import app org.example.myapp.pbox
```

---

## Available commands

Packbox v0.2.0 includes **15 Go binaries** in `~/.packbox/bin/`:

| Command            | Purpose                                                            |
|--------------------|--------------------------------------------------------------------|
| `packbox-pack`     | Hashes a directory into CAS chunks and generates `manifest.json`   |
| `packbox-install`  | Installs an app from the manifest (+ `--desktop`/`--remove-desktop`) |
| `packbox-run`      | Runs the app in the `bwrap` sandbox (overlay A/C, private HOME)    |
| `packbox-list`     | Lists apps with their **real size** and savings from sharing (`--tsv`) |
| `packbox-remove`   | Uninstalls an app and frees its CAS references                     |
| `packbox-gc`       | Collects unreferenced chunks **and cells**                         |
| `packbox-verify`   | Checks resolvable libs + **ABI compatibility** of the host         |
| `packbox-export`   | Exports to `.pbox` with **adaptive compression** and optional `--sign` |
| `packbox-import`   | Imports a `.pbox` (anti tar-slip, traversal and signatures)        |
| `packbox-update`   | Updates an app reusing chunks + delta report (`--no-gc`)           |
| `packbox-module`   | Modules/cells: `list`, `create`, `cell <lib>...`                   |
| `packbox-sign`     | ed25519 keys and signatures: `keygen`, `sign`, `verify`, `trust`   |
| `packbox-fetch`    | HTTP remote: `publish <id> <dir>` and `fetch <id> --from <url>`    |
| `packbox-debug`    | Attaches the debug symbols (separate cell) of an installed app     |
| `packbox-diagnose` | Environment report for bug reports                                 |

---

## File structure

```
~/.packbox/                              # Installation
├── bin/                                 # 15 compiled Go binaries
└── src/                                 # Go source code

~/.local/share/packbox/                  # User data
├── store/                               # CAS: chunks by BLAKE3 hash
│   └── <ab>/<full-hash>                 # + a .refs file per chunk
├── apps/                                # Installed apps
│   └── <app-id>/
│       ├── manifest.json
│       ├── tree/                        # Hardlinks to the CAS (layer A)
│       └── home/                        # Private HOME (created on the first run)
├── mods/                                # Cells (org.lib.*, org.debug.*)
├── exports/                             # .pbox files (+ .sig)
└── tmp/                                 # Temporary files

~/.config/packbox/
├── lang/                                # 9 language files
├── signing.key / signing.pub            # your signing key
└── trusted/                             # trusted public keys
```

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
                         │  bwrap sandbox: /app = overlay A on C     │
                         │  private HOME · seccomp · filtered D-Bus  │
                         └──────────────────────────────────────────┘
```

### Internal components

- **CAS + chunker** — Stores chunks by **BLAKE3** hash. Large files are
  split with **CDC** (gear-type rolling hash); small ones go as a single
  chunk (hardlinkable, for sharing). **Atomic** writes (temp+rename).
- **Manifest** (`schema_version: "1.6"`) — Maps paths to chunks, lists the
  **cells** (`mods`), the `host_contract` (delegate + required_symbols), the
  X11 symbol and, if applicable, the **debug** cell.
- **Cells** — One lib = one cell `org.lib.<soname>@<hash>` in `mods/`.
  Shared between apps. `packbox-gc` deletes unreferenced ones.
- **Sandbox** — `bwrap --unshare-all --cap-drop ALL --clearenv`, **seccomp**
  (blocks ptrace/bpf/keyring/io_uring/modules…), **filtered D-Bus** with
  `xdg-dbus-proxy` (portals + dconf), **private HOME** (`apps/<id>/home`), network
  **opt-in** and **opt-in X11** (Wayland + portals by default; enabled only if
  the manifest requests it or if the session is X11-only).
- **Layer overlay** — `/app` is composed with `--overlay-src` (C below, A
  above); S (host) arrives via `/usr`. Avoids copying the cells into each tree.
- **Host contract** — `packbox-verify` checks that the host provides the required
  symbols (ABI).
- **Signatures and remote** — `packbox-sign` (ed25519) signs the `.pbox`;
  `packbox-fetch` publishes and downloads only the delta (chunks + cells).

### How deduplication works

```
App 1: htop     → chunks: [A, B, C]
App 2: neofetch → chunks: [A, D, E]
App 3: btop     → chunks: [A, B, F]

CAS Store:
  A → references: htop, neofetch, btop       (3 apps)
  B → references: htop, btop                 (2 apps)
  C → htop · D → neofetch · E → neofetch · F → btop

Total: 6 unique chunks instead of 9.
```

---

## Security

### Implemented mitigations

- **Per-app data isolation** — Each app runs with its **private HOME**
  (`apps/<id>/home`); only fonts/themes are exposed **read-only**. It does not see
  or touch your real configuration.
- **Filtered D-Bus** — `xdg-dbus-proxy` with an allowlist (by default, portals
  and `dconf`; the system bus, nothing). The app does not talk to the real bus.
- **seccomp** — Default filter that blocks dangerous kernel surface
  (ptrace, bpf, keyring, io_uring, userfaultfd, modules, reboot/swap…).
- **Opt-in X11** — Wayland + `xdg-desktop-portal` by default (exposing the
  portal's document mount); X11 is enabled with the manifest's `x11` flag
  or automatically if the host session is X11-only.
- **Anti tar-slip / traversal** — `.pbox` extraction validates each entry
  (`safeJoin` + `O_NOFOLLOW` + symlink destinations) and rejects `name`/paths that
  escape the app directory.
- **Environment cleanup** — `--clearenv` + explicit whitelist: blocks
  `LD_PRELOAD`/`LD_LIBRARY_PATH` injected from the host.
- **No setuid, no root** — Everything runs as your user; `sudo` only for the
  system dependencies when installing.
- **Reference counting + GC** — Each chunk has a `.refs`; `packbox-gc` only
  deletes what is unreferenced (chunks **and cells**).
- **Signatures** — Signable `.pbox` with **ed25519**; `import` verifies and **rejects**
  altered packages or ones from untrusted signers.
- **CAS integrity** — Hashes validated before being used as a path;
  atomic writes.

### Known limitations (v0.2.0 Alpha)

> [!WARNING]
> Areas where feedback is most appreciated.

- ⚠️ **Partial portals.** Talking to the portals is allowed and the document
  mount is exposed, but portals are not yet used for everything (camera,
  clipboard, etc.).
- ⚠️ **`packbox-module remove`/`info`** are still not implemented (`cell`
  does exist).
- ⚠️ **Adaptive compression** at the package level, not per-entry (the format is
  tar + a compressor).
- ⚠️ **No catalog.** The HTTP remote serves data, not trust or a public
  index.

---

## Roadmap

### v0.1.x — Stabilization

- [x] Signature verification for `.pbox` (ed25519 + key management)
- [x] Hardened sandbox: private HOME, filtered D-Bus, seccomp
- [x] Automatic cells + layer overlay (A/C/S)
- [x] `packbox-update` with chunk delta + automatic GC
- [x] HTTP remote (`publish`/`fetch`) with delta download
- [x] Separate debug symbols (`cell-debug`)
- [x] Adaptive compression in `export`
- [x] End-to-end integration tests (`tests/integration.sh`)
- [ ] Per-application network policy
- [ ] Complete portals (files, camera, clipboard)
- [ ] CI/CD: `shellcheck`, `gofmt`, `go vet` on every PR
- [ ] Test matrix: Debian 12, Fedora 40, Arch, openSUSE Tumbleweed

### v0.2 — Scope

- [ ] Precompiled x86_64 and aarch64 binaries (releases page)
- [ ] Signed central index/repository (`search`/`install` from remote)
- [ ] Optional GUI frontend (GTK4)

### Future

- [ ] Flatpak runtime importer (best-effort)
- [ ] WASM sandbox for untrusted plugins

---

## Contributing

Contributions welcome! Areas where help is especially useful:

- **Translations** — Add a locale by copying an existing block in
  `i18n/` and translating each `L_*` key.
- **Portals** — Integrate `xdg-desktop-portal` for file access.
- **Chunking / dedup** — Improve the CDC and the threshold policy.
- **Bug reports** — Always include the output of `packbox-diagnose`.

### How to get started

```bash
git clone https://github.com/El-Ave-Azul/packbox.git
cd packbox
cd src && go test ./...     # unit tests
bash tests/integration.sh   # end-to-end (pack → export → import → run)
```

- 🐛 [Open an issue](https://github.com/El-Ave-Azul/packbox/issues)
- 💬 [Start a discussion](https://github.com/El-Ave-Azul/packbox/discussions)

> [!TIP]
> Run `shellcheck` on the bash scripts and `gofmt` + `go vet` on the Go code before
> submitting a PR.

---

## License

Distributed under the **Apache License 2.0**. See [LICENSE](../../LICENSE).

Apache 2.0 provides an **explicit patent grant clause**, which
protects users and contributors against litigation over the deduplication
and sandboxing techniques, and is compatible with GPLv3.

---

## Acknowledgments

- **[bubblewrap](https://github.com/containers/bubblewrap)** — Linux sandbox
  primitive that makes `packbox-run` possible.
- **[BLAKE3](https://github.com/BLAKE3-team/BLAKE3)** — Fast and
  cryptographically secure content hashing.
- **[xdg-desktop-portal](https://flatpak.github.io/xdg-desktop-portal/)** and
  **xdg-dbus-proxy** — Mediated file access and D-Bus filtering.
- **[Flatpak](https://flatpak.org/)** — Demonstrated that sandboxed Linux
  apps work at scale; many of its decisions informed ours,
  even where we diverge.
- **The global Linux community** — The 9-language i18n layer exists thanks to their
  reviews and contributions.
