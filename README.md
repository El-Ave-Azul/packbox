<!-- Language selector -->
**English** · [Español](README.es.md) · [Français](docs/fr/README.md) · [Deutsch](docs/de/README.md) · [Italiano](docs/it/README.md) · [简体中文](docs/zh-CN/README.md) · [繁體中文](docs/zh-TW/README.md) · [日本語](docs/ja/README.md) · [한국어](docs/ko/README.md)

---

<!-- Badges -->
![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)
![Platform: Linux](https://img.shields.io/badge/platform-Linux-blue)
![Version](https://img.shields.io/badge/version-0.1.0--alpha-orange)
![Go](https://img.shields.io/badge/Go-1.22+-00ADD8?logo=go&logoColor=white)
![i18n](https://img.shields.io/badge/i18n-9_languages-green)
![Status](https://img.shields.io/badge/status-alpha-red)

# Packbox

**A next-generation application packaging system for Linux.** Inspired by
Flatpak, but with a fundamentally different reuse model: instead of shipping
a monolithic runtime per app, Packbox stores every file as content-addressed
chunks (BLAKE3 CAS). Two apps that share 90% of their libraries only store
the differing 10%.

> [!NOTE]
> **Packbox is in Alpha (v0.1.0).** Core workflows work, but there is no
> signature verification on `.pbox` archives yet, and the sandbox is
> intentionally more permissive than Flatpak. Use it on non-critical
> systems first.

---

## Table of contents

- [Why Packbox](#why-packbox)
- [Comparison with Flatpak](#comparison-with-flatpak)
- [Requirements](#requirements)
- [Installation](#installation)
- [Quick start](#quick-start)
- [Commands](#commands)
- [Filesystem layout](#filesystem-layout)
- [Architecture](#architecture)
- [Security](#security)
- [Roadmap](#roadmap)
- [Documentation](#documentation)
- [Contributing](#contributing)
- [License](#license)
- [Acknowledgements](#acknowledgements)

---

## Why Packbox

Flatpak solved a real problem: sandboxed, portable Linux apps. But its reuse
model is coarse. Each app ships (or references) a full runtime that can be
**~1 GB**. If two apps use different runtimes, you pay the cost twice — even
if they share 95% of their libraries.

Packbox attacks that specific gap:

- **Chunk-level deduplication.** Files are split, hashed with BLAKE3, and
  stored as chunks. Identical chunks (a `libfoo.so.3.2.1`, a font, a
  translation catalog) are shared across all apps on the system.
- **Cross-app library sharing.** Two apps that use the same `libQt6Core.so`
  keep only one copy on disk, regardless of which "runtime" they belong to.
- **Selective host library usage.** Apps can declare which host libraries
  they trust (via `host_contract.delegate`), instead of bundling everything.
- **Small per-app footprint.** In practice, adding a new app on top of an
  existing set costs ~5–15% of its size, not ~100%.

Packbox is **not** trying to replace Flatpak. It explores a different niche:
apps that don't map cleanly to a runtime, or where shipping 1 GB to run a
50 MB tool is overkill.

---

## Comparison with Flatpak

| Feature              | Flatpak (current)                | Packbox (proposed)              |
|----------------------|----------------------------------|---------------------------------|
| Reuse unit           | Full runtime (~1 GB)             | Atomic cell (~5–50 MB)          |
| Deduplication        | File-level (OSTree)              | Chunk-level (BLAKE3 CAS)        |
| Library sharing      | Within same runtime              | Across all apps                 |
| Host library usage   | None (full sandbox)              | Selective (ABI-compatible)      |
| Updates              | OSTree object delta              | Chunk delta + reordering        |
| Per-app overhead     | ~100% if different runtime       | ~5–15% (only differences)       |

---

## Requirements

- **Linux** (tested on Debian 12, Fedora 40, Arch current)
- **Bash 4+**
- **Go 1.22+** (auto-installed if missing)
- **bubblewrap** (`bwrap`) — auto-installed
- **binutils** (`ldd`, `readelf`) — auto-installed
- **Standard compression tools**: `zstd`, `xz`, `gzip` (at least one)
- **~500 MB free disk** for the build + toolchain if Go is installed from scratch

Supported distro families: **Debian/Ubuntu/Mint/Pop**, **Fedora/RHEL/Rocky**,
**Arch/Manjaro/EndeavourOS**, **openSUSE**.

---

## Installation

```bash
git clone (https://github.com/El-Ave-Azul/packbox.git)
cd packbox
./packbox-installer-v0.1.0.sh
source ~/.bashrc
packbox-diagnose
```

The installer is interactive and:

1. Detects your distro and package manager.
2. Prompts before installing dependencies (`bubblewrap binutils jq bc curl tar`).
3. Installs Go 1.22+ if missing.
4. Creates `~/.packbox/{bin,src}` and `~/.local/share/packbox/{store,apps,mods,exports,tmp}`.
5. Generates 11 Go binaries + internal packages from local source.
6. Compiles everything (~2–3 minutes on modern hardware).
7. Adds `~/.packbox/bin` to `PATH` and symlinks into `~/.local/bin`.
8. Verifies all 11 binaries are present.

**Languages**: the installer prompts for one of 9 locales at start —
English, Español, Français, Deutsch, Italiano, 简体中文, 繁體中文, 日本語,
한국어.

### Uninstall

Run the same script and pick option `2`:

- Mode `s` → full removal (binaries + apps + store + menus + config)
- Mode `k` → binaries only (keeps apps and store)
- Mode `q` → cancel

Requires typing `DELETE` to confirm.

---

## Quick start

### Interactive packager (recommended for new users)

```bash
./packbox-packager-v0.1.0.sh
```

Menu: pack, list, gc, export, import, uninstall.

### Command line

```bash
# 1. Package a directory into CAS chunks + manifest.json
packbox-pack ./firefox-tree \
    --name org.mozilla.firefox \
    --version 128.0 \
    --description "Mozilla Firefox" \
    --gui --toolkit GTK3

# 2. Install from the generated manifest
packbox-install ./firefox-tree/manifest.json

# 3. Run inside a bwrap sandbox (DNS + GUI fixes applied)
packbox-run org.mozilla.firefox

# 4. List what's installed
packbox-list

# 5. Uninstall and reclaim chunks
packbox-remove org.mozilla.firefox
packbox-gc
```

---

## Commands

Eleven Go binaries, all under `~/.packbox/bin/`:

| Command             | Purpose                                                    |
|---------------------|------------------------------------------------------------|
| `packbox-pack`      | Hash a directory into CAS chunks + `manifest.json`         |
| `packbox-install`   | Install from manifest (hardlink from CAS)                  |
| `packbox-run`       | Execute inside `bwrap` with DNS + GUI passthrough          |
| `packbox-list`      | List installed apps with version and tags                  |
| `packbox-remove`    | Uninstall app and release its CAS references               |
| `packbox-gc`        | Garbage-collect orphaned chunks                            |
| `packbox-verify`    | `ldd`-based library compatibility check                    |
| `packbox-export`    | Export app to `.pbox` (zstd/xz/gzip)                       |
| `packbox-import`    | Import `.pbox` with path-traversal validation              |
| `packbox-module`    | Manage shared library modules (`list`, `create`)           |
| `packbox-diagnose`  | Print environment report for bug reports                   |

Full reference with options, exit codes, and examples:
[`docs/en/commands.md`](docs/en/commands.md) ·
[`docs/es/commands.md`](docs/es/commands.md)

### Interactive scripts

- `packbox-installer-v0.1.0.sh` — install / uninstall
- `packbox-packager-v0.1.0.sh` — pack, list, gc, export, import, uninstall
- `packbox-i18n.sh` — shared translation layer (sourced by the two above)

---

## Filesystem layout

```
~/.packbox/                     # Install (binaries + Go source)
├── bin/                        # 11 Go binaries
└── src/                        # Go module source

~/.local/share/packbox/         # Data
├── store/                      # CAS — chunks by BLAKE3 hash
│   └── <ab>/<full-hash>        # plus .refs file per chunk
├── apps/                       # Installed apps (tree + manifest.json)
├── mods/                       # Shared library modules
├── exports/                    # .pbox archives
└── tmp/                        # Temporary workspace

~/.config/packbox/lang/         # 9 language files
```

---

## Architecture

Three moving parts:

```
┌──────────────┐   pack    ┌──────────────┐   install   ┌──────────────┐
│  Source dir  │ ────────► │     CAS      │ ──────────► │  App tree    │
│  (fs tree)   │           │  (chunks)    │             │ (hardlinks)  │
└──────────────┘           └──────────────┘             └──────────────┘
                                  │
                                  │ run
                                  ▼
                         ┌──────────────────┐
                         │  bwrap sandbox   │
                         │  (DNS/GUI fix)   │
                         └──────────────────┘
```

- **CAS** — `~/.local/share/packbox/store/`, BLAKE3 hashes, one `.refs` file
  per chunk, `SafeLink` (hardlink → copy fallback) on install.
- **Manifest** — `schema_version: "1.5"`, `layers.app.files` maps relative
  paths to `{chunks, size, mode}`, plus `host_contract.delegate` for host
  library trust.
- **Sandbox** — `bwrap --unshare-all --share-net`, env whitelist after
  `--clearenv`, DNS symlink resolution (`EvalSymlinks`) before binding
  `/etc/resolv.conf`, GUI support (X11, Wayland, D-Bus, `/dev/dri`,
  fontconfig cache), heuristic per-app data map with `--bind-try`.

Full architecture (CAS internals, manifest schema, sandbox mounts, host
contract): [`docs/en/architecture.md`](docs/en/architecture.md) ·
[`docs/es/architecture.md`](docs/es/architecture.md)

---

## Security

> [!WARNING]
> `.pbox` archives are **not signed** in v0.1.0 Alpha. Treat any imported
> archive as untrusted. Signature verification is on the roadmap.

Key mitigations already implemented:

- **Path-traversal protection** — `cas.isValidHash()` enforces 64 lowercase
  hex chars. `.pbox` import validates every tar entry against the extraction
  root via `security.ValidatePath`.
- **Symlink-safe import** — only `tar.TypeDir` and `tar.TypeReg` are
  handled; symlinks, hardlinks, and device files are silently skipped.
- **Environment scrubbing** — `--clearenv` followed by an explicit whitelist
  blocks `LD_PRELOAD` / `LD_LIBRARY_PATH` injection from the host.
- **XAUTHORITY isolation** — the host `~/.Xauthority` is copied to a
  per-process temp file (`/tmp/packbox-xauth-<pid>`, mode 0600) before being
  bound into the sandbox.
- **Reference counting** — each chunk has a `.refs` file; `packbox-gc`
  deletes only unreferenced chunks.
- **No setuid, no root** — Packbox runs entirely as the invoking user.
  `sudo` is used only by the installer for distro packages.

Known limitations and threat model:
[`docs/en/security.md`](docs/en/security.md) ·
[`docs/es/security.md`](docs/es/security.md)

Report vulnerabilities with the output of `packbox-diagnose` attached. For
sensitive findings, use the repository's private security contact.

---

## Roadmap

### v0.1.x — Stabilization
- [ ] Signature verification for `.pbox` archives
- [ ] Per-app network policy (currently `--share-net` is global)
- [ ] Implement `packbox-module remove` and `info`
- [ ] Stress-test `host_contract.delegate` against real GTK4/Qt6 apps
- [ ] CI: `shellcheck`, `gofmt`, `go vet` on every PR
- [ ] Test matrix: Debian 12, Fedora 40, Arch, openSUSE Tumbleweed

### v0.2 — Reach
- [ ] Prebuilt binaries for x86_64 and aarch64 (releases page)
- [ ] `packbox-update` for in-place version bumps
- [ ] GUI frontend (optional, GTK4)
- [ ] Chunk-level delta downloads for `packbox-export`

### Later
- [ ] Flatpak runtime importer (best-effort)
- [ ] Signature verification via minisign or sigstore
- [ ] WASM-based sandbox tier for untrusted plugins

---

## Documentation

Full docs in 9 languages. English and Spanish have the complete set
(README + commands + architecture + security); the other seven have
README + commands.

| Language | README                                 | Commands                                       | Architecture                                        | Security                                      |
|----------|----------------------------------------|------------------------------------------------|-----------------------------------------------------|-----------------------------------------------|
| English  | [en](docs/en/README.md)                | [en](docs/en/commands.md)                      | [en](docs/en/architecture.md)                       | [en](docs/en/security.md)                     |
| Español  | [es](docs/es/README.md)                | [es](docs/es/commands.md)                      | [es](docs/es/architecture.md)                       | [es](docs/es/security.md)                     |
| Français | [fr](docs/fr/README.md)                | [fr](docs/fr/commands.md)                      | —                                                   | —                                             |
| Deutsch  | [de](docs/de/README.md)                | [de](docs/de/commands.md)                      | —                                                   | —                                             |
| Italiano | [it](docs/it/README.md)                | [it](docs/it/commands.md)                      | —                                                   | —                                             |
| 简体中文 | [zh-CN](docs/zh-CN/README.md)          | [zh-CN](docs/zh-CN/commands.md)                | —                                                   | —                                             |
| 繁體中文 | [zh-TW](docs/zh-TW/README.md)          | [zh-TW](docs/zh-TW/commands.md)                | —                                                   | —                                             |
| 日本語   | [ja](docs/ja/README.md)                | [ja](docs/ja/commands.md)                      | —                                                   | —                                             |
| 한국어   | [ko](docs/ko/README.md)                | [ko](docs/ko/commands.md)                      | —                                                   | —                                             |

Index: [`docs/README.md`](docs/README.md)

---

## Contributing

Contributions welcome, especially:

- **Translations** — add a new locale to `packbox-i18n.sh` by copying the
  `en` block in `install_lang_files()` and translating every `L_*` key.
- **Sandbox profiles** — per-app data maps for browsers, IDEs, games.
- **CAS chunking strategies** — rolling hash variants, parallel chunking.
- **Bug reports** — always include `packbox-diagnose` output.

Getting started:

```bash
git clone https://github.com/TU_USUARIO/packbox.git
cd packbox
# Read CONTRIBUTING.md for full guidelines
```

- 🐛 [Open an issue](https://github.com/TU_USUARIO/packbox/issues)
- 💬 [Start a discussion](https://github.com/TU_USUARIO/packbox/discussions)
- 🔧 [CONTRIBUTING.md](CONTRIBUTING.md)

Please run `shellcheck` on shell scripts and `gofmt` + `go vet` on Go code
before submitting a PR.

---

## License

[MIT](LICENSE) © 2025 TU_NOMBRE

Packbox is free to use, modify, and redistribute. See [LICENSE](LICENSE)
for details.

---

## Acknowledgements

- **[bubblewrap](https://github.com/containers/bubblewrap)** — the sandbox
  primitive that makes `packbox-run` possible.
- **[BLAKE3](https://github.com/BLAKE3-team/BLAKE3)** — fast, secure
  content-addressing.
- **[Flatpak](https://flatpak.org/)** — the project that proved sandboxed
  Linux apps can work at scale, and whose design decisions informed many
  of ours (even where we diverge).
- The 9-language i18n layer exists because the Linux community is global;
  thanks to everyone who has reviewed the translations.
