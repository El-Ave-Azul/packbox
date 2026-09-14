═══════════════════════════════════════════════════════════════════════════════
PACKBOX v0.1.0 ALPHA — DOCUMENTACIÓN COMPLETA / COMPLETE DOCUMENTATION
9 idiomas / 9 languages: EN · ES · FR · DE · IT · zh-CN · zh-TW · JA · KO
═══════════════════════════════════════════════════════════════════════════════

ÍNDICE / INDEX
──────────────
  1. English ................ README, Commands, Architecture, Security
  2. Español ................ README, Comandos, Arquitectura, Seguridad
  3. Français ............... README, Commandes
  4. Deutsch ................ README, Befehle
  5. Italiano ............... README, Comandi
  6. 简体中文 ................ README, 命令
  7. 繁體中文 ................ README, 命令
  8. 日本語 .................. README, コマンド
  9. 한국어 .................. README, 명령어


═══════════════════════════════════════════════════════════════════════════════
1. ENGLISH
═══════════════════════════════════════════════════════════════════════════════

───────────────────────────────────────────────────────────────────────────────
1.1 README
───────────────────────────────────────────────────────────────────────────────

Packbox v0.1.0 Alpha — English

A next-generation application packaging system, inspired by Flatpak but with
a fundamentally different reuse model.

WHAT MAKES PACKBOX DIFFERENT
────────────────────────────

  Feature              Flatpak (current)          Packbox (proposed)
  ─────────────────────────────────────────────────────────────────────
  Reuse unit           Full runtime (~1 GB)       Atomic cell (~5–50 MB)
  Deduplication        File-level (OSTree)        Chunk-level (CAS)
  Library sharing      Within same runtime        Across all apps
  Host library usage   None (full sandbox)        Selective (ABI-compatible)
  Updates              OSTree object delta        Chunk delta + reordering
  Per-app overhead     ~100% if different runtime ~5–15% (only differences)

Core idea: instead of shipping a monolithic runtime per app, Packbox stores
every file as content-addressed chunks. Two apps that share 90% of their
libraries only store the differing 10%. Cross-app library reuse is automatic.

INSTALLATION
────────────

  git clone <repo>
  cd packbox
  ./packbox-installer-v0.1.0.sh

The installer:
  1. Detects your distro (Debian/Ubuntu, Fedora, Arch, openSUSE families)
  2. Installs Go 1.22+ if missing
  3. Creates ~/.packbox/ (hidden) with bin/ and src/
  4. Generates and compiles 11 Go binaries
  5. Adds ~/.packbox/bin to your PATH
  6. Installs language files to ~/.config/packbox/lang/

After install: source ~/.bashrc  then  packbox-diagnose.

QUICK USAGE
───────────

  # Interactive packager (recommended for first-time users)
  ./packbox-packager-v0.1.0.sh

  # Or use the binaries directly
  packbox-pack firefox-dir/ --name org.mozilla.firefox --version 128.0 \
      --description "Web browser" --gui --toolkit GTK3
  packbox-install firefox-dir/manifest.json
  packbox-run org.mozilla.firefox

FILESYSTEM LAYOUT
─────────────────

  ~/.packbox/                     Install (binaries + Go source)
  ├── bin/                        11 Go binaries
  └── src/                        Go module source

  ~/.local/share/packbox/         Data
  ├── store/                      CAS — chunks by BLAKE3 hash
  ├── apps/                       Installed apps (tree + manifest)
  ├── mods/                       Shared library modules
  ├── exports/                    .pbox archives
  └── tmp/                        Temporary workspace

  ~/.config/packbox/lang/         9 language files

COMMANDS
────────

  See section 1.2 for the full reference.

  packbox-pack      Package a directory → CAS chunks + manifest
  packbox-install   Install app from manifest (hardlink from CAS)
  packbox-run       Run app in bwrap sandbox (DNS/GUI fix included)
  packbox-list      List installed apps
  packbox-remove    Uninstall app and release CAS references
  packbox-gc        Garbage-collect orphaned chunks
  packbox-verify    Verify library compatibility (ldd)
  packbox-export    Export app to .pbox (zstd/xz/gzip)
  packbox-import    Import .pbox with path-traversal validation
  packbox-module    Manage shared library modules
  packbox-diagnose  Diagnose environment (dirs, tools, DNS, kernel)

FURTHER READING
───────────────

  Section 1.3 — Architecture (CAS, manifest, sandbox internals)
  Section 1.4 — Security (threat model and mitigations)

LICENSE / CONTRIBUTING
──────────────────────

Packbox v0.1.0 Alpha is a work in progress. Contributions are welcome,
especially: translations, additional sandbox profiles, and CAS chunking
strategies.


───────────────────────────────────────────────────────────────────────────────
1.2 COMMAND REFERENCE
───────────────────────────────────────────────────────────────────────────────

All commands are installed to ~/.packbox/bin/ and symlinked into
~/.local/bin/. They accept --help where noted.

1.2.1  packbox-pack
───────────────────

Purpose
  Package a directory tree into CAS chunks and write a manifest.json.

Syntax
  packbox-pack <directory> --name <id> [options]

Options
  --name <id>            App ID (required). Example: org.mozilla.firefox
  --version <v>          Version string (default: 1.0.0)
  --description <text>   Human-readable description
  --entrypoint <path>    Path inside tree (e.g. /app/bin/firefox)
  --mods <a,b,c>         Comma-separated module names
  --gui                  Mark as GUI application (default: false)
  --toolkit <name>       GTK3, GTK4, Qt5, Qt6, SDL
  --icon <path>          Icon path inside tree

Behavior
  • Hashes every file with BLAKE3 and stores chunks in
    ~/.local/share/packbox/store/<xx>/<hash>.
  • Creates manifest.json inside the given directory.
  • If --entrypoint is omitted, picks the largest executable in bin/
    and uses /app/bin/<name>.
  • Skips manifest.json itself during hashing.

Examples
  # Firefox bundle
  packbox-pack ./firefox-tree --name org.mozilla.firefox --version 128.0 \
      --description "Mozilla Firefox" --gui --toolkit GTK3

  # CLI tool
  packbox-pack ./htop-tree --name org.packbox.htop --version 3.3.0 \
      --description "Interactive process viewer"

Output
  [ok] <path>/manifest.json  archivos=N

Exit codes
  0 = success
  1 = missing args / nonexistent dir / store error

Related
  packbox-install

1.2.2  packbox-install
──────────────────────

Purpose
  Install an app from a manifest.json by hardlinking chunks from CAS.

Syntax
  packbox-install <manifest.json>

Behavior
  • If app already installed, reads its old manifest and removes all CAS
    references first.
  • Creates ~/.local/share/packbox/apps/<name>/tree/.
  • Hardlinks each chunk into the tree; falls back to copy if cross-device.
  • Preserves original file mode.
  • Registers a reference per chunk (<hash>.refs) for GC.

Examples
  packbox-install ./firefox-tree/manifest.json
  packbox-install ~/builds/myapp/manifest.json

Output
  [install] <name> v<ver>
  [ok] <name> instalado  archivos=N

Exit codes
  0 = success
  1 = invalid manifest / store error

Related
  packbox-pack, packbox-gc

1.2.3  packbox-run
──────────────────

Purpose
  Execute an installed app inside a bwrap sandbox with DNS/GUI support.

Syntax
  packbox-run <app-id> [args...]

Behavior
  • Requires bubblewrap (bwrap) in PATH.
  • Mounts the app tree read-only at /app.
  • Read-only bind-mounts /usr, /etc, /lib, /lib64, /bin, /sbin, /var.
  • --unshare-all --share-net (network allowed, other namespaces isolated).
  • Clears environment, then whitelists: LANG, TZ, DISPLAY, WAYLAND_DISPLAY,
    XAUTHORITY, XDG_*, etc.
  • DNS fix: bind-mounts /etc/resolv.conf, /etc/hosts, /etc/nsswitch.conf,
    /etc/hostname, /etc/gai.conf, /etc/host.conf — and resolves symlinks
    (important on systemd-resolved hosts).
  • GUI support: X11 socket, Wayland socket, D-Bus session + system bus,
    /dev/dri, /dev/shm, fontconfig cache, user themes/icons.
  • App data: heuristic map (Firefox → ~/.mozilla, Chrome →
    ~/.config/google-chrome, etc.). --bind-try avoids errors if dir
    doesn't exist.

Examples
  packbox-run org.mozilla.firefox
  packbox-run org.packbox.htop --tree
  packbox-run org.gimp.gimp --version

Exit codes
  0 = success
  1 = missing app, missing bwrap, or run failure

Related
  packbox-verify

1.2.4  packbox-list
───────────────────

Purpose
  List installed apps with version and tags.

Syntax
  packbox-list

Output
  Apps instaladas:
  -----------------------------------------------------------
    * org.mozilla.firefox  v128.0    [GUI/GTK3]
    * org.packbox.htop     v3.3.0
    * org.gimp.gimp        v2.10.38 [GUI/GTK3] [PORTABLE]
  -----------------------------------------------------------
  Total: 3

Exit codes
  Always 0.

Related
  packbox-remove

1.2.5  packbox-remove
─────────────────────

Purpose
  Uninstall an app, remove its CAS references, and clean up desktop entries.

Syntax
  packbox-remove <app-id>

Behavior
  • Loads manifest, removes each chunk's reference for this app.
  • Deletes ~/.local/share/packbox/apps/<app-id>/.
  • Deletes ~/.local/share/applications/packbox-<app-id>.desktop.
  • Deletes ~/.local/share/icons/hicolor/256x256/apps/packbox-<app-id>.{png,svg}.
  • Does NOT run GC automatically — use packbox-gc.

Examples
  packbox-remove org.mozilla.firefox

Exit codes
  0 = success
  1 = if app not installed

Related
  packbox-gc

1.2.6  packbox-gc
─────────────────

Purpose
  Garbage-collect orphaned chunks (no .refs file or empty .refs).

Syntax
  packbox-gc

Behavior
  • Walks ~/.local/share/packbox/store/<xx>/.
  • For each chunk without <hash>.refs or with empty refs → deletes chunk
    + refs.
  • Returns count and bytes freed.

Output
  [gc]
  [ok] chunks=N  bytes=B

When to run
  After packbox-remove, or periodically.

Exit codes
  0 = success
  1 = store error

1.2.7  packbox-verify
─────────────────────

Purpose
  Check whether an installed app's libraries are available on the host.

Syntax
  packbox-verify <app-id>

Behavior
  • If app is PORTABLE, immediately succeeds.
  • Resolves real binary (handles launcher.sh redirect).
  • Runs ldd and checks each library against /lib/x86_64-linux-gnu,
    /lib64, /usr/lib, /usr/lib64.
  • Reports count of resolved libs or lists missing ones.

Output (success)
  [ok] COMPATIBLE  libs=42

Output (failure)
  [fail] faltan 3 libs
     [X] libfoo.so.1
     [X] libbar.so.2
     [X] libbaz.so.3

Exit codes
  0 = compatible
  1 = missing libs or manifest error

Note
  Not exposed in the packager menu — CLI-only, for scripting.

1.2.8  packbox-export
─────────────────────

Purpose
  Export an installed app to a .pbox archive.

Syntax
  packbox-export app <app-id>

Behavior
  • Tars the entire ~/.local/share/packbox/apps/<app-id>/ directory.
  • Compresses with the best available tool, in priority order:
      1. zstd -19 -T0  (fast, best ratio/speed)
      2. xz -9e -T0    (slowest, best ratio)
      3. gzip          (fallback)
  • Output: ~/.local/share/packbox/exports/<app-id>.pbox.

Examples
  packbox-export app org.mozilla.firefox
  → ~/.local/share/packbox/exports/org.mozilla.firefox.pbox

Exit codes
  0 = success
  1 = app not found

Related
  packbox-import

1.2.9  packbox-import
─────────────────────

Purpose
  Import a .pbox archive with path-traversal protection.

Syntax
  packbox-import app <file.pbox>

Behavior
  • Detects format by magic bytes: gzip (1f 8b), zstd (28 b5 2f fd),
    xz (fd 37 7a 58).
  • Streams through tar reader.
  • Validates each entry path against the extraction root
    (security.ValidatePath) to prevent ../ escapes.
  • If app already exists, warns and overwrites.
  • Extracts to ~/.local/share/packbox/apps/<name>/.

Examples
  packbox-import app ~/Downloads/org.mozilla.firefox.pbox

Output
  [import] <path>
  [ok] importado: <name>

Exit codes
  0 = success
  1 = unknown format / missing decompressor / path escape

Security note
  Never skip the path validation. See section 1.4.

1.2.10  packbox-module
──────────────────────

Purpose
  Manage shared library modules (independently versioned lib bundles).

Syntax
  packbox-module list
  packbox-module create <binary> <name> <version>
  packbox-module remove <name> <version>       (not yet implemented)
  packbox-module info <name> <version>         (not yet implemented)

Behavior (create)
  • Runs ldd on <binary>, collects dependencies.
  • Copies each library into mods/<name>/<version>/lib/.
  • Writes manifest.json with type: "module".
  • Registers under ~/.local/share/packbox/mods/<name>/<version>/.

Examples
  packbox-module list
  packbox-module create /usr/bin/htop org.packbox.htop-libs 1.0.0

Exit codes
  0 = success
  1 = missing args

1.2.11  packbox-diagnose
────────────────────────

Purpose
  Print environment diagnostics for bug reports.

Syntax
  packbox-diagnose

Output sections
  • Install dir, data dir, config dir
  • Directory structure check (~/.packbox/bin, ~/.local/share/packbox/store, ...)
  • Tools check (bwrap, readelf, ldd, jq, zstd, xz, tar)
  • DNS files check (with symlink resolution)
  • Kernel, arch, Go version

Examples
  packbox-diagnose > /tmp/packbox-diag.txt

Exit codes
  Always 0.

When to run
  Before opening any bug report.

1.2.12  packbox-installer-v0.1.0.sh
───────────────────────────────────

Purpose
  Interactive installer / uninstaller.

Syntax
  ./packbox-installer-v0.1.0.sh

Menu
  1  Install Packbox
  2  Uninstall Packbox
  0  Exit

Install flow
  1. Detect distro
  2. Prompt before installing deps (bubblewrap binutils jq bc curl tar)
  3. Install Go 1.22+ if missing
  4. Create ~/.packbox/{bin,src} and
     ~/.local/share/packbox/{store,apps,mods,exports,tmp}
  5. Generate Go source (11 commands + 4 internal packages)
  6. Compile binaries
  7. Configure PATH (adds to .bashrc, symlinks to ~/.local/bin)
  8. Verify all 11 binaries exist

Uninstall flow
  • Scans what will be removed, shows sizes
  • Mode s = full removal (binaries + apps + store + menus + config)
  • Mode k = binaries only (~/.packbox/ + symlinks; keeps apps/store)
  • Mode q = cancel
  • Requires typing DELETE to confirm
  • Cleans .bashrc (backup: ~/.bashrc.packbox-uninstall.bak)
  • Refreshes desktop and icon caches
  • Optionally removes legacy ~/packbox/

Language
  Prompts for one of 9 languages at start.

1.2.13  packbox-packager-v0.1.0.sh
──────────────────────────────────

Purpose
  Interactive frontend to the packager binaries.

Syntax
  ./packbox-packager-v0.1.0.sh

Menu
  1  Pack system application
  2  List installed apps
  3  Garbage collection
  4  Export app to file
  5  Import app from file
  6  Uninstall application
  0  Exit

Option 1 workflow
  1. Detect apps from .desktop files + common binaries + /opt/* +
     /usr/lib/* (with symlink in /usr/bin)
  2. Show Top 15 by size (with f=filter MB, b=search, r=more, q=cancel)
  3. Show details, ask to pack
  4. Configure App ID, Version, Description, Mode
  5. Modes: 1=Normal, 2=Portable, 3=Module, 4=Bundle
     (recommended for bundles)
  6. Invoke packbox-pack → packbox-install → optionally
     create_desktop_entry
  7. Optionally export to .pbox
  8. Optionally run

Dual detection
  Prefers ~/.packbox/bin, falls back to ~/packbox/bin (legacy).

Language
  Picks from ~/.config/packbox/lang/ (installed by installer).

EXIT CODE CONVENTIONS
─────────────────────

  0 = Success
  1 = Error (missing args, missing resource, etc.)

All binaries use fmt.Printf("ERROR: ...") + os.Exit(1) on failure.
Shell scripts use err() which prints in red and exits 1.

ENVIRONMENT VARIABLES
─────────────────────

  HOME                 Used by all commands; base for ~/.packbox, data, etc.
  PACKBOX_LANG         installer, packager; force language code
  PACKBOX_LANG_DIR     i18n; override lang directory
  DISPLAY, WAYLAND_DISPLAY, XAUTHORITY, XDG_*
                       packbox-run; passed through to sandbox
  LD_LIBRARY_PATH      launchers inside apps; set by generated launcher.sh


───────────────────────────────────────────────────────────────────────────────
1.3 ARCHITECTURE
───────────────────────────────────────────────────────────────────────────────

OVERVIEW
────────

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

CONTENT-ADDRESSED STORE (CAS)
─────────────────────────────

  • Root: ~/.local/share/packbox/store/
  • Layout: store/<first-2-hex>/<full-hash>
  • Hash: BLAKE3 (32 bytes = 64 hex chars)
  • Reference file per chunk: <hash>.refs — one app name per line

Why BLAKE3?
  • ~10× faster than SHA-256
  • Cryptographically secure (128-bit security)
  • Deterministic, tree-hashable (future: parallel chunking)

Validation
  isValidHash() enforces exactly 64 lowercase hex chars. This blocks
  manifest-based path traversal (../../etc/passwd in a chunk name).

Link strategy
  • StoreFile(src) → hash, store if absent
  • LinkFile(hash, dst) → hardlink; fallback SafeCopy on cross-device
  • Hardlinks give ~50% space savings vs. copy and are instant

MANIFEST FORMAT (manifest.json)
───────────────────────────────

  {
    "schema_version": "1.5",
    "name": "org.mozilla.firefox",
    "version": "128.0",
    "description": "Mozilla Firefox",
    "entrypoint": "/app/bin/firefox",
    "arch": "x86_64",
    "gui": true,
    "toolkit": "GTK3",
    "icon": "",
    "layers": {
      "app": {
        "files": {
          "bin/firefox": {
            "chunks": ["<blake3-hash>"],
            "size": 1234567,
            "mode": "0755"
          }
        }
      }
    },
    "mods": [],
    "host_contract": {
      "version": "1",
      "delegate": ["libc.so.6", "libm.so.6"],
      "required_symbols": {},
      "fallback_mods": {}
    },
    "portable": false
  }

Fields
  schema_version       Currently 1.5
  layers.app.files     Map of relative path → chunk list + size + mode
  host_contract.delegate
                       Libs allowed to come from host (not bundled)
  portable             If true, all non-universal libs are bundled in lib/
  bundle               (optional) true if packaged as a full app bundle
  bundle_dir           (optional) original /opt/... or /usr/lib/... source

SANDBOX (bwrap)
───────────────

Constructed in internal/sandbox/sandbox.go.

Base mounts
  --ro-bind <appDir>/tree  /app
  --ro-bind /usr           /usr
  --ro-bind /lib           /lib          (if exists)
  --ro-bind /lib64         /lib64        (if exists)
  --ro-bind /etc           /etc
  --ro-bind /bin           /bin
  --ro-bind /sbin          /sbin
  --ro-bind /var           /var
  --dev /dev --proc /proc
  --tmpfs /tmp --tmpfs /run

Namespace
  --unshare-all --share-net (network allowed, rest isolated)

Env whitelist (after --clearenv)
  LANG, LANGUAGE, LC_*, TZ, XDG_SESSION_TYPE, XDG_CURRENT_DESKTOP,
  DISPLAY, WAYLAND_DISPLAY, XAUTHORITY, XDG_RUNTIME_DIR

DNS fix
  Bind-mounts /etc/resolv.conf, /etc/hosts, /etc/nsswitch.conf,
  /etc/hostname, /etc/gai.conf, /etc/host.conf. If the source is a
  symlink (systemd-resolved → /run/systemd/resolve/stub-resolv.conf),
  resolves it first with EvalSymlinks and binds the target. This fixes
  the classic "no DNS inside bwrap" bug.

  Also binds: /run/systemd/resolve, /run/NetworkManager,
  /run/avahi-daemon, /run/nscd.

GUI support
  • XAUTHORITY: copies host file to /tmp/packbox-xauth-<pid>, then binds
    to /tmp/packbox-xauth
  • X11: /tmp/.X11-unix
  • Wayland: $XDG_RUNTIME_DIR/$WAYLAND_DISPLAY
  • D-Bus: session bus + /run/dbus/system_bus_socket
  • /dev/dri, /dev/shm (dev-bind)
  • Fonts: ~/.local/share/fonts, ~/.fonts, ~/.themes, ~/.icons
  • fontconfig cache: ~/.cache/fontconfig (bind, writable)

App data map (heuristic, keyed on app name substring)
  • firefox     → ~/.mozilla, ~/.cache/mozilla
  • chrome      → ~/.config/google-chrome, ~/.cache/google-chrome
  • gimp        → ~/.config/GIMP
  • ... (see source for full list)
  Each matched dir is mkdir -p + --bind-try (no error if missing).

HOST CONTRACT
─────────────

internal/hostcontract/hostcontract.go:

  • AllowedLibs: libc.so.6, libm.so.6, libdl.so.2, libpthread.so.0,
    libz.so.1
  • AnalyzeDependencies(bin): parses ldd output
  • ExtractRequiredSymbols(bin): parses readelf -s (still experimental)
  • FilterDelegatable(deps): returns only libs in AllowedLibs
  • FindLibPath(lib): searches standard paths

Concept
  Apps declare which host libraries they trust. Non-delegated libs are
  bundled. This is the "selective host library usage" from the comparison
  table.

SECURITY PRIMITIVES
───────────────────

internal/security/security.go:

  • SecureTempDir(prefix): random hex suffix, mode 0700
  • SafeCopy(src, dst, mode): io.ReadFrom + chmod
  • ValidatePath(base, target): rejects targets escaping base
  • SafeLink(src, dst): hardlink → fallback copy

I18N SYSTEM
───────────

packbox-i18n.sh provides:

  • select_language: 9-language prompt
  • install_lang_files: writes ~/.config/packbox/lang/<code>.sh
  • load_lang: sources chosen file + sets English fallbacks via
    : "${L_X:=...}"
  • t KEY: echoes $KEY

Each lang file declares L_* variables. Missing keys fall back to English.


───────────────────────────────────────────────────────────────────────────────
1.4 SECURITY
───────────────────────────────────────────────────────────────────────────────

THREAT MODEL
────────────

Packbox assumes:

  • Untrusted: app trees, .pbox archives, remote manifests.
  • Trusted: the host kernel, bwrap binary, ~/.local/share/packbox/store/.
  • Semi-trusted: apps packaged from the host itself (they were already
    running there).

MITIGATIONS
───────────

1. Path traversal in CAS chunk names
   cas.isValidHash() rejects any hash that isn't exactly 64 lowercase hex
   chars. This blocks a malicious manifest declaring:
       {"chunks": ["../../../etc/passwd"]}

2. Path traversal in .pbox import
   security.ValidatePath(base, target) uses filepath.Rel and rejects any
   target whose relative path starts with "..". Applied to every tar
   entry during packbox-import.

3. Symlink escapes in tar
   packbox-import only handles tar.TypeDir and tar.TypeReg. It silently
   ignores tar.TypeSymlink, tar.TypeLink, and device files. This prevents
   symlink-based escapes.

4. Sandbox isolation
   bwrap --unshare-all --share-net:
     • Isolated: PID, mount, IPC, UTS, cgroup, user namespaces
     • Shared: network (needed for browsers, package managers)
     • --die-with-parent --new-session: kills sandbox when parent dies

5. Environment scrubbing
   --clearenv wipes inherited env. Only a whitelist is re-injected. This
   blocks LD_PRELOAD, LD_LIBRARY_PATH injection from the host.

6. XAUTHORITY handling
   Instead of binding the host ~/.Xauthority directly, Packbox copies it
   to /tmp/packbox-xauth-<pid> (mode 0600, unique per process), then
   binds that to /tmp/packbox-xauth inside the sandbox. The sandboxed app
   can read its own X auth but not the original.

7. Write confinement
   • App tree: read-only (--ro-bind).
   • /tmp, /run: tmpfs, wiped on exit.
   • App-specific config dirs: --bind (writable), but only the ones in
     the heuristic map for that app family.
   • Everything else under $HOME: not mounted.

8. Reference counting for GC
   Each chunk has <hash>.refs. packbox-remove removes the app's line.
   packbox-gc deletes chunks with no refs or empty refs. This prevents
   use-after-free of shared chunks and space leaks from orphaned data.

9. No setuid, no root
   Packbox never requires root at runtime. packbox-installer uses sudo
   only for distro package installation. All Packbox binaries run as the
   invoking user.

KNOWN LIMITATIONS (v0.1.0 Alpha)
────────────────────────────────

  • --share-net: apps can reach the network. Per-app firewall is not yet
    implemented.
  • readelf symbol extraction: experimental; not enforced.
  • mods/: remove and info subcommands are declared but not implemented.
  • No signature verification on .pbox files yet. Treat imported archives
    as untrusted.
  • LD_LIBRARY_PATH in launchers: bundled libs take priority over host
    libs. If a bundle is compromised, it can shadow host libs.
    Mitigation: verify bundle origin before install.

REPORTING VULNERABILITIES
─────────────────────────

Open an issue with packbox-diagnose output attached. For sensitive
findings, use the repository's private security contact.


═══════════════════════════════════════════════════════════════════════════════
2. ESPAÑOL
═══════════════════════════════════════════════════════════════════════════════

───────────────────────────────────────────────────────────────────────────────
2.1 README
───────────────────────────────────────────────────────────────────────────────

Packbox v0.1.0 Alpha — Español

Sistema de empaquetado de aplicaciones de nueva generación, inspirado en
Flatpak pero con un modelo de reutilización fundamentalmente distinto.

QUÉ HACE DIFERENTE A PACKBOX
────────────────────────────

  Característica       Flatpak (actual)           Packbox (propuesto)
  ─────────────────────────────────────────────────────────────────────
  Unidad de reuso      Runtime completo (~1 GB)   Celda atómica (~5–50 MB)
  Deduplicación        A nivel de archivo (OSTree) A nivel de chunk (CAS)
  Compartición de libs Dentro del mismo runtime    Cruzada entre todas las apps
  Uso de libs del host Ninguno (sandbox completo)  Selectivo (ABI compatible)
  Actualizaciones      Delta de objetos OSTree    Delta de chunks + reordenación
  Overhead por app     ~100% si runtime distinto  ~5–15% (solo diferencias)

Idea central: en lugar de enviar un runtime monolítico por app, Packbox
almacena cada archivo como chunks direccionados por contenido. Dos apps
que comparten el 90% de sus librerías solo almacenan el 10% que difiere.
La reutilización de librerías entre apps es automática.

INSTALACIÓN
───────────

  git clone <repo>
  cd packbox
  ./packbox-installer-v0.1.0.sh

El instalador:
  1. Detecta tu distro (familias Debian/Ubuntu, Fedora, Arch, openSUSE)
  2. Instala Go 1.22+ si falta
  3. Crea ~/.packbox/ (oculto) con bin/ y src/
  4. Genera y compila 11 binarios Go
  5. Agrega ~/.packbox/bin a tu PATH
  6. Instala los archivos de idioma en ~/.config/packbox/lang/

Después: source ~/.bashrc  y luego  packbox-diagnose.

USO RÁPIDO
──────────

  # Empaquetador interactivo (recomendado para nuevos usuarios)
  ./packbox-packager-v0.1.0.sh

  # O usar los binarios directamente
  packbox-pack firefox-dir/ --name org.mozilla.firefox --version 128.0 \
      --description "Navegador web" --gui --toolkit GTK3
  packbox-install firefox-dir/manifest.json
  packbox-run org.mozilla.firefox

ESTRUCTURA DEL SISTEMA DE ARCHIVOS
──────────────────────────────────

  ~/.packbox/                     Instalación (binarios + código Go)
  ├── bin/                        11 binarios Go
  └── src/                        Código fuente del módulo Go

  ~/.local/share/packbox/         Datos
  ├── store/                      CAS — chunks por hash BLAKE3
  ├── apps/                       Apps instaladas (tree + manifest)
  ├── mods/                       Módulos de librerías compartidas
  ├── exports/                    Archivos .pbox
  └── tmp/                        Espacio de trabajo temporal

  ~/.config/packbox/lang/         9 archivos de idioma

COMANDOS
────────

  Ver sección 2.2 para la referencia completa.

  packbox-pack      Empaqueta un directorio → chunks CAS + manifest
  packbox-install   Instala app desde manifest (hardlink desde CAS)
  packbox-run       Ejecuta app en sandbox bwrap (con fix DNS/GUI)
  packbox-list      Lista apps instaladas
  packbox-remove    Desinstala app y libera referencias CAS
  packbox-gc        Recolecta chunks huérfanos
  packbox-verify    Verifica compatibilidad de librerías (ldd)
  packbox-export    Exporta app a .pbox (zstd/xz/gzip)
  packbox-import    Importa .pbox con validación anti path-traversal
  packbox-module    Gestiona módulos de librerías compartidas
  packbox-diagnose  Diagnostica el entorno (dirs, tools, DNS, kernel)

LECTURAS ADICIONALES
────────────────────

  Sección 2.3 — Arquitectura (CAS, manifest, sandbox internals)
  Sección 2.4 — Seguridad (modelo de amenazas y mitigaciones)

LICENCIA / CONTRIBUIR
─────────────────────

Packbox v0.1.0 Alpha es un trabajo en progreso. Las contribuciones son
bienvenidas, especialmente: traducciones, perfiles de sandbox adicionales,
y estrategias de chunking del CAS.


───────────────────────────────────────────────────────────────────────────────
2.2 REFERENCIA DE COMANDOS
───────────────────────────────────────────────────────────────────────────────

Todos los comandos se instalan en ~/.packbox/bin/ y se enlazan
simbólicamente en ~/.local/bin/. Aceptan --help donde se indica.

2.2.1  packbox-pack
───────────────────

Propósito
  Empaquetar un árbol de directorios en chunks CAS y escribir un
  manifest.json.

Sintaxis
  packbox-pack <directorio> --name <id> [opciones]

Opciones
  --name <id>            App ID (obligatorio). Ej: org.mozilla.firefox
  --version <v>          Cadena de versión (defecto: 1.0.0)
  --description <texto>  Descripción legible
  --entrypoint <ruta>    Ruta dentro del tree (ej. /app/bin/firefox)
  --mods <a,b,c>         Nombres de módulos separados por coma
  --gui                  Marcar como aplicación GUI (defecto: false)
  --toolkit <nombre>     GTK3, GTK4, Qt5, Qt6, SDL
  --icon <ruta>          Ruta del icono dentro del tree

Comportamiento
  • Hashea cada archivo con BLAKE3 y guarda los chunks en
    ~/.local/share/packbox/store/<xx>/<hash>.
  • Crea manifest.json dentro del directorio dado.
  • Si se omite --entrypoint, elige el ejecutable más grande en bin/ y
    usa /app/bin/<nombre>.
  • Salta manifest.json durante el hashing.

Ejemplos
  # Bundle de Firefox
  packbox-pack ./firefox-tree --name org.mozilla.firefox --version 128.0 \
      --description "Mozilla Firefox" --gui --toolkit GTK3

  # Herramienta CLI
  packbox-pack ./htop-tree --name org.packbox.htop --version 3.3.0 \
      --description "Visor de procesos interactivo"

Salida
  [ok] <ruta>/manifest.json  archivos=N

Códigos de salida
  0 = éxito
  1 = faltan argumentos / dir inexistente / error del store

Relacionado
  packbox-install

2.2.2  packbox-install
──────────────────────

Propósito
  Instalar una app desde un manifest.json enlazando duro los chunks desde
  el CAS.

Sintaxis
  packbox-install <manifest.json>

Comportamiento
  • Si la app ya está instalada, lee su manifest antiguo y elimina primero
    todas las referencias CAS.
  • Crea ~/.local/share/packbox/apps/<nombre>/tree/.
  • Enlaza duro cada chunk al tree; si falla (cross-device) copia.
  • Preserva el modo original del archivo.
  • Registra una referencia por chunk (<hash>.refs) para el GC.

Ejemplos
  packbox-install ./firefox-tree/manifest.json
  packbox-install ~/builds/miapp/manifest.json

Salida
  [install] <nombre> v<ver>
  [ok] <nombre> instalado  archivos=N

Códigos de salida
  0 = éxito
  1 = manifest inválido / error del store

Relacionado
  packbox-pack, packbox-gc

2.2.3  packbox-run
──────────────────

Propósito
  Ejecutar una app instalada dentro de un sandbox bwrap con soporte
  DNS/GUI.

Sintaxis
  packbox-run <app-id> [args...]

Comportamiento
  • Requiere bubblewrap (bwrap) en el PATH.
  • Monta el tree de la app como solo-lectura en /app.
  • Bind-mounts solo-lectura de /usr, /etc, /lib, /lib64, /bin, /sbin,
    /var.
  • --unshare-all --share-net (red permitida, otros namespaces aislados).
  • Limpia el entorno, luego permite: LANG, TZ, DISPLAY, WAYLAND_DISPLAY,
    XAUTHORITY, XDG_*, etc.
  • Fix DNS: bind-mounts de /etc/resolv.conf, /etc/hosts,
    /etc/nsswitch.conf, /etc/hostname, /etc/gai.conf, /etc/host.conf —
    y resuelve symlinks (importante en hosts con systemd-resolved).
  • Soporte GUI: socket X11, socket Wayland, D-Bus sesión + sistema,
    /dev/dri, /dev/shm, caché de fontconfig, temas e iconos del usuario.
  • Datos de app: mapa heurístico (Firefox → ~/.mozilla, Chrome →
    ~/.config/google-chrome, etc.). --bind-try evita errores si el dir
    no existe.

Ejemplos
  packbox-run org.mozilla.firefox
  packbox-run org.packbox.htop --tree
  packbox-run org.gimp.gimp --version

Códigos de salida
  0 = éxito
  1 = si falta la app, falta bwrap, o falla la ejecución

Relacionado
  packbox-verify

2.2.4  packbox-list
───────────────────

Propósito
  Listar apps instaladas con versión y etiquetas.

Sintaxis
  packbox-list

Salida
  Apps instaladas:
  -----------------------------------------------------------
    * org.mozilla.firefox  v128.0    [GUI/GTK3]
    * org.packbox.htop     v3.3.0
    * org.gimp.gimp        v2.10.38 [GUI/GTK3] [PORTABLE]
  -----------------------------------------------------------
  Total: 3

Códigos de salida
  Siempre 0.

Relacionado
  packbox-remove

2.2.5  packbox-remove
─────────────────────

Propósito
  Desinstalar una app, borrar sus referencias CAS, y limpiar entradas de
  menú.

Sintaxis
  packbox-remove <app-id>

Comportamiento
  • Carga el manifest, elimina la referencia de cada chunk para esta app.
  • Borra ~/.local/share/packbox/apps/<app-id>/.
  • Borra ~/.local/share/applications/packbox-<app-id>.desktop.
  • Borra ~/.local/share/icons/hicolor/256x256/apps/packbox-<app-id>.{png,svg}.
  • NO ejecuta GC automáticamente — usa packbox-gc.

Ejemplos
  packbox-remove org.mozilla.firefox

Códigos de salida
  0 = éxito
  1 = si la app no está instalada

Relacionado
  packbox-gc

2.2.6  packbox-gc
─────────────────

Propósito
  Recolectar chunks huérfanos (sin .refs o con .refs vacío).

Sintaxis
  packbox-gc

Comportamiento
  • Recorre ~/.local/share/packbox/store/<xx>/.
  • Para cada chunk sin <hash>.refs o con refs vacío → borra chunk + refs.
  • Devuelve cantidad y bytes liberados.

Salida
  [gc]
  [ok] chunks=N  bytes=B

Cuándo ejecutar
  Después de packbox-remove, o periódicamente.

Códigos de salida
  0 = éxito
  1 = error del store

2.2.7  packbox-verify
─────────────────────

Propósito
  Verificar si las librerías de una app instalada están disponibles en el
  host.

Sintaxis
  packbox-verify <app-id>

Comportamiento
  • Si la app es PORTABLE, sale con éxito inmediatamente.
  • Resuelve el binario real (maneja redirección de launcher.sh).
  • Ejecuta ldd y comprueba cada librería contra /lib/x86_64-linux-gnu,
    /lib64, /usr/lib, /usr/lib64.
  • Reporta cantidad de libs resueltas o lista las faltantes.

Salida (éxito)
  [ok] COMPATIBLE  libs=42

Salida (fallo)
  [fail] faltan 3 libs
     [X] libfoo.so.1
     [X] libbar.so.2
     [X] libbaz.so.3

Códigos de salida
  0 = compatible
  1 = libs faltantes o error de manifest

Nota
  No está expuesto en el menú del packager — solo CLI, para scripting.

2.2.8  packbox-export
─────────────────────

Propósito
  Exportar una app instalada a un archivo .pbox.

Sintaxis
  packbox-export app <app-id>

Comportamiento
  • Empaqueta (tar) todo el directorio
    ~/.local/share/packbox/apps/<app-id>/.
  • Comprime con la mejor herramienta disponible, en orden de prioridad:
      1. zstd -19 -T0  (rápido, mejor relación ratio/velocidad)
      2. xz -9e -T0    (lento, mejor ratio)
      3. gzip          (fallback)
  • Salida: ~/.local/share/packbox/exports/<app-id>.pbox.

Ejemplos
  packbox-export app org.mozilla.firefox
  → ~/.local/share/packbox/exports/org.mozilla.firefox.pbox

Códigos de salida
  0 = éxito
  1 = app no encontrada

Relacionado
  packbox-import

2.2.9  packbox-import
─────────────────────

Propósito
  Importar un archivo .pbox con protección anti path-traversal.

Sintaxis
  packbox-import app <archivo.pbox>

Comportamiento
  • Detecta el formato por bytes mágicos: gzip (1f 8b),
    zstd (28 b5 2f fd), xz (fd 37 7a 58).
  • Transmite a través del lector tar.
  • Valida la ruta de cada entrada contra la raíz de extracción
    (security.ValidatePath) para prevenir escapes con ../.
  • Si la app ya existe, advierte y sobrescribe.
  • Extrae a ~/.local/share/packbox/apps/<nombre>/.

Ejemplos
  packbox-import app ~/Descargas/org.mozilla.firefox.pbox

Salida
  [import] <ruta>
  [ok] importado: <nombre>

Códigos de salida
  0 = éxito
  1 = formato desconocido / falta descompresor / escape de ruta

Nota de seguridad
  Nunca omitas la validación de ruta. Ver sección 2.4.

2.2.10  packbox-module
──────────────────────

Propósito
  Gestionar módulos de librerías compartidas (bundles de libs versionados
  independientemente).

Sintaxis
  packbox-module list
  packbox-module create <binario> <nombre> <versión>
  packbox-module remove <nombre> <versión>       (aún no implementado)
  packbox-module info <nombre> <versión>         (aún no implementado)

Comportamiento (create)
  • Ejecuta ldd sobre <binario>, recolecta dependencias.
  • Copia cada librería a mods/<nombre>/<versión>/lib/.
  • Escribe manifest.json con type: "module".
  • Registra bajo ~/.local/share/packbox/mods/<nombre>/<versión>/.

Ejemplos
  packbox-module list
  packbox-module create /usr/bin/htop org.packbox.htop-libs 1.0.0

Códigos de salida
  0 = éxito
  1 = si faltan argumentos

2.2.11  packbox-diagnose
────────────────────────

Propósito
  Imprimir diagnóstico del entorno para reportes de bugs.

Sintaxis
  packbox-diagnose

Secciones de salida
  • Dir de instalación, datos, config
  • Chequeo de estructura de directorios
  • Chequeo de herramientas (bwrap, readelf, ldd, jq, zstd, xz, tar)
  • Chequeo de archivos DNS (con resolución de symlinks)
  • Kernel, arquitectura, versión de Go

Ejemplos
  packbox-diagnose > /tmp/packbox-diag.txt

Códigos de salida
  Siempre 0.

Cuándo ejecutar
  Antes de abrir cualquier reporte de bug.

2.2.12  packbox-installer-v0.1.0.sh
───────────────────────────────────

Propósito
  Instalador / desinstalador interactivo.

Sintaxis
  ./packbox-installer-v0.1.0.sh

Menú
  1  Instalar Packbox
  2  Desinstalar Packbox
  0  Salir

Flujo de instalación
  1. Detectar distro
  2. Confirmar antes de instalar deps (bubblewrap binutils jq bc curl tar)
  3. Instalar Go 1.22+ si falta
  4. Crear ~/.packbox/{bin,src} y
     ~/.local/share/packbox/{store,apps,mods,exports,tmp}
  5. Generar el código Go (11 comandos + 4 paquetes internos)
  6. Compilar binarios
  7. Configurar PATH (agrega a .bashrc, symlinks a ~/.local/bin)
  8. Verificar los 11 binarios

Flujo de desinstalación
  • Escanea qué se eliminará, muestra tamaños
  • Modo s = eliminación completa (binarios + apps + store + menús + config)
  • Modo k = solo binarios (~/.packbox/ + symlinks; conserva apps/store)
  • Modo q = cancelar
  • Requiere escribir DELETE para confirmar
  • Limpia .bashrc (backup: ~/.bashrc.packbox-uninstall.bak)
  • Refresca cachés de menú e iconos
  • Opcionalmente elimina el ~/packbox/ antiguo

Idioma
  Pregunta por uno de 9 idiomas al inicio.

2.2.13  packbox-packager-v0.1.0.sh
──────────────────────────────────

Propósito
  Frontend interactivo de los binarios del empaquetador.

Sintaxis
  ./packbox-packager-v0.1.0.sh

Menú
  1  Empaquetar aplicación del sistema
  2  Listar apps instaladas
  3  Recolección de basura
  4  Exportar app a archivo
  5  Importar app desde archivo
  6  Desinstalar aplicación
  0  Salir

Flujo de la opción 1
  1. Detecta apps desde archivos .desktop + binarios comunes + /opt/* +
     /usr/lib/* (con symlink en /usr/bin)
  2. Muestra Top 15 por tamaño (con f=filtrar MB, b=buscar, r=más,
     q=cancelar)
  3. Muestra detalles, pregunta si empaquetar
  4. Configura App ID, Versión, Descripción, Modo
  5. Modos: 1=Normal, 2=Portable, 3=Módulo, 4=Bundle
     (recomendado para bundles)
  6. Invoca packbox-pack → packbox-install → opcionalmente
     create_desktop_entry
  7. Opcionalmente exporta a .pbox
  8. Opcionalmente ejecuta

Detección dual
  Prefiere ~/.packbox/bin, fallback a ~/packbox/bin (legacy).

Idioma
  Lee de ~/.config/packbox/lang/ (instalado por el instalador).

CONVENCIONES DE CÓDIGOS DE SALIDA
─────────────────────────────────

  0 = Éxito
  1 = Error (faltan args, recurso inexistente, etc.)

Todos los binarios usan fmt.Printf("ERROR: ...") + os.Exit(1) al fallar.
Los scripts shell usan err() que imprime en rojo y sale con 1.

VARIABLES DE ENTORNO
────────────────────

  HOME                 Usada por todos; base de ~/.packbox, datos, etc.
  PACKBOX_LANG         instalador, packager; forzar código de idioma
  PACKBOX_LANG_DIR     i18n; sobrescribir dir de idiomas
  DISPLAY, WAYLAND_DISPLAY, XAUTHORITY, XDG_*
                       packbox-run; se pasan al sandbox
  LD_LIBRARY_PATH      launchers dentro de apps; seteado por launcher.sh


───────────────────────────────────────────────────────────────────────────────
2.3 ARQUITECTURA
───────────────────────────────────────────────────────────────────────────────

VISIÓN GENERAL
──────────────

   ┌──────────────┐   pack    ┌──────────────┐   install   ┌──────────────┐
   │  Dir fuente  │ ────────► │     CAS      │ ──────────► │  Tree de app │
   │  (árbol fs)  │           │  (chunks)    │             │ (hardlinks)  │
   └──────────────┘           └──────────────┘             └──────────────┘
                                      │
                                      │ run
                                      ▼
                             ┌──────────────────┐
                             │  Sandbox bwrap   │
                             │  (fix DNS/GUI)   │
                             └──────────────────┘

CONTENT-ADDRESSED STORE (CAS)
─────────────────────────────

  • Raíz: ~/.local/share/packbox/store/
  • Layout: store/<2-hex>/<hash-completo>
  • Hash: BLAKE3 (32 bytes = 64 chars hex)
  • Archivo de referencia por chunk: <hash>.refs — un nombre de app por línea

¿Por qué BLAKE3?
  • ~10× más rápido que SHA-256
  • Criptográficamente seguro (128 bits de seguridad)
  • Determinista, hashable en árbol (futuro: chunking paralelo)

Validación
  isValidHash() exige exactamente 64 chars hex lowercase. Esto bloquea
  path traversal basado en manifest (../../etc/passwd en el nombre de un
  chunk).

Estrategia de enlace
  • StoreFile(src) → hash, guarda si no existe
  • LinkFile(hash, dst) → hardlink; fallback SafeCopy si cross-device
  • Los hardlinks dan ~50% de ahorro de espacio vs. copia y son
    instantáneos

FORMATO DEL MANIFEST (manifest.json)
────────────────────────────────────

  {
    "schema_version": "1.5",
    "name": "org.mozilla.firefox",
    "version": "128.0",
    "description": "Mozilla Firefox",
    "entrypoint": "/app/bin/firefox",
    "arch": "x86_64",
    "gui": true,
    "toolkit": "GTK3",
    "icon": "",
    "layers": {
      "app": {
        "files": {
          "bin/firefox": {
            "chunks": ["<hash-blake3>"],
            "size": 1234567,
            "mode": "0755"
          }
        }
      }
    },
    "mods": [],
    "host_contract": {
      "version": "1",
      "delegate": ["libc.so.6", "libm.so.6"],
      "required_symbols": {},
      "fallback_mods": {}
    },
    "portable": false
  }

Campos
  schema_version       Actualmente 1.5
  layers.app.files     Mapa ruta relativa → lista de chunks + size + mode
  host_contract.delegate
                       Libs permitidas desde el host (no empaquetadas)
  portable             Si true, todas las libs no universales van en lib/
  bundle               (opcional) true si se empaquetó como bundle completo
  bundle_dir           (opcional) origen original /opt/... o /usr/lib/...

SANDBOX (bwrap)
───────────────

Construido en internal/sandbox/sandbox.go.

Mounts base
  --ro-bind <appDir>/tree  /app
  --ro-bind /usr           /usr
  --ro-bind /lib           /lib          (si existe)
  --ro-bind /lib64         /lib64        (si existe)
  --ro-bind /etc           /etc
  --ro-bind /bin           /bin
  --ro-bind /sbin          /sbin
  --ro-bind /var           /var
  --dev /dev --proc /proc
  --tmpfs /tmp --tmpfs /run

Namespace
  --unshare-all --share-net (red permitida, resto aislado)

Whitelist de env (después de --clearenv)
  LANG, LANGUAGE, LC_*, TZ, XDG_SESSION_TYPE, XDG_CURRENT_DESKTOP,
  DISPLAY, WAYLAND_DISPLAY, XAUTHORITY, XDG_RUNTIME_DIR

Fix DNS
  Bind-mounts de /etc/resolv.conf, /etc/hosts, /etc/nsswitch.conf,
  /etc/hostname, /etc/gai.conf, /etc/host.conf. Si el origen es un
  symlink (systemd-resolved → /run/systemd/resolve/stub-resolv.conf),
  lo resuelve antes con EvalSymlinks y bindea el target. Esto arregla el
  clásico bug "sin DNS dentro de bwrap".

  También bindea: /run/systemd/resolve, /run/NetworkManager,
  /run/avahi-daemon, /run/nscd.

Soporte GUI
  • XAUTHORITY: copia el archivo del host a /tmp/packbox-xauth-<pid>,
    luego bindea a /tmp/packbox-xauth
  • X11: /tmp/.X11-unix
  • Wayland: $XDG_RUNTIME_DIR/$WAYLAND_DISPLAY
  • D-Bus: bus de sesión + /run/dbus/system_bus_socket
  • /dev/dri, /dev/shm (dev-bind)
  • Fuentes: ~/.local/share/fonts, ~/.fonts, ~/.themes, ~/.icons
  • Caché fontconfig: ~/.cache/fontconfig (bind, escribible)

Mapa de datos de app (heurístico, por substring del nombre de app)
  • firefox     → ~/.mozilla, ~/.cache/mozilla
  • chrome      → ~/.config/google-chrome, ~/.cache/google-chrome
  • gimp        → ~/.config/GIMP
  • ... (ver fuente para lista completa)
  Cada dir coincidente se hace mkdir -p + --bind-try (sin error si falta).

HOST CONTRACT
─────────────

internal/hostcontract/hostcontract.go:

  • AllowedLibs: libc.so.6, libm.so.6, libdl.so.2, libpthread.so.0,
    libz.so.1
  • AnalyzeDependencies(bin): parsea salida de ldd
  • ExtractRequiredSymbols(bin): parsea readelf -s (aún experimental)
  • FilterDelegatable(deps): devuelve solo libs en AllowedLibs
  • FindLibPath(lib): busca en rutas estándar

Concepto
  Las apps declaran en qué librerías del host confían. Las libs no
  delegadas se empaquetan. Esto es el "uso selectivo de libs del host"
  de la tabla comparativa.

PRIMITIVAS DE SEGURIDAD
───────────────────────

internal/security/security.go:

  • SecureTempDir(prefix): sufijo hex aleatorio, modo 0700
  • SafeCopy(src, dst, mode): io.ReadFrom + chmod
  • ValidatePath(base, target): rechaza targets que escapan de base
  • SafeLink(src, dst): hardlink → fallback copia

SISTEMA I18N
────────────

packbox-i18n.sh provee:

  • select_language: prompt de 9 idiomas
  • install_lang_files: escribe ~/.config/packbox/lang/<code>.sh
  • load_lang: sourcea el archivo elegido + fallbacks en inglés vía
    : "${L_X:=...}"
  • t KEY: imprime $KEY

Cada archivo de idioma declara variables L_*. Las claves faltantes caen
al inglés.


───────────────────────────────────────────────────────────────────────────────
2.4 SEGURIDAD
───────────────────────────────────────────────────────────────────────────────

MODELO DE AMENAZAS
──────────────────

Packbox asume:

  • No confiable: trees de apps, archivos .pbox, manifests remotos.
  • Confiable: el kernel del host, el binario bwrap,
    ~/.local/share/packbox/store/.
  • Semi-confiable: apps empaquetadas desde el propio host (ya corrían
    ahí).

MITIGACIONES
────────────

1. Path traversal en nombres de chunk CAS
   cas.isValidHash() rechaza cualquier hash que no sea exactamente 64
   chars hex lowercase. Esto bloquea un manifest malicioso declarando:
       {"chunks": ["../../../etc/passwd"]}

2. Path traversal en importación .pbox
   security.ValidatePath(base, target) usa filepath.Rel y rechaza
   cualquier target cuyo path relativo empiece con "..". Se aplica a
   cada entrada tar durante packbox-import.

3. Escapes por symlink en tar
   packbox-import solo maneja tar.TypeDir y tar.TypeReg. Ignora
   silenciosamente tar.TypeSymlink, tar.TypeLink, y archivos de
   dispositivo. Esto previene escapes basados en symlinks.

4. Aislamiento del sandbox
   bwrap --unshare-all --share-net:
     • Aislados: PID, mount, IPC, UTS, cgroup, user namespaces
     • Compartido: red (necesario para navegadores, gestores de paquetes)
     • --die-with-parent --new-session: mata el sandbox cuando muere el
       padre

5. Limpieza de entorno
   --clearenv borra el env heredado. Solo se reinyecta una whitelist.
   Esto bloquea inyección de LD_PRELOAD, LD_LIBRARY_PATH desde el host.

6. Manejo de XAUTHORITY
   En lugar de bindear directamente el ~/.Xauthority del host, Packbox
   lo copia a /tmp/packbox-xauth-<pid> (modo 0600, único por proceso), y
   luego bindea eso a /tmp/packbox-xauth dentro del sandbox. La app en
   sandbox puede leer su propio X auth pero no el original.

7. Confinamiento de escritura
   • Tree de app: solo-lectura (--ro-bind).
   • /tmp, /run: tmpfs, borrados al salir.
   • Dirs de config específicos de la app: --bind (escribible), pero
     solo los del mapa heurístico de esa familia de apps.
   • Todo lo demás bajo $HOME: no se monta.

8. Reference counting para GC
   Cada chunk tiene <hash>.refs. packbox-remove elimina la línea de la
   app. packbox-gc borra chunks sin refs o con refs vacío. Esto previene
   use-after-free de chunks compartidos y fugas de espacio por datos
   huérfanos.

9. Sin setuid, sin root
   Packbox nunca requiere root en runtime. packbox-installer usa sudo
   solo para instalar paquetes de la distro. Todos los binarios de
   Packbox corren como el usuario que los invoca.

LIMITACIONES CONOCIDAS (v0.1.0 Alpha)
─────────────────────────────────────

  • --share-net: las apps pueden acceder a la red. Firewall por app aún
    no implementado.
  • Extracción de símbolos con readelf: experimental; no aplicada.
  • mods/: subcomandos remove e info declarados pero no implementados.
  • Sin verificación de firmas en archivos .pbox todavía. Trata los
    archivos importados como no confiables.
  • LD_LIBRARY_PATH en launchers: las libs empaquetadas tienen prioridad
    sobre las del host. Si un bundle es comprometido, puede hacer
    shadowing de libs del host. Mitigación: verificar el origen del
    bundle antes de instalar.

REPORTAR VULNERABILIDADES
─────────────────────────

Abre un issue con la salida de packbox-diagnose adjunta. Para hallazgos
sensibles, usa el contacto privado de seguridad del repositorio.


═══════════════════════════════════════════════════════════════════════════════
3. FRANÇAIS
═══════════════════════════════════════════════════════════════════════════════

───────────────────────────────────────────────────────────────────────────────
3.1 README
───────────────────────────────────────────────────────────────────────────────

Packbox v0.1.0 Alpha — Français

Système d'empaquetage d'applications nouvelle génération, inspiré de
Flatpak mais avec un modèle de réutilisation fondamentalement différent.

CE QUI DISTINGUE PACKBOX
────────────────────────

  Caractéristique        Flatpak (actuel)           Packbox (proposé)
  ─────────────────────────────────────────────────────────────────────
  Unité de réutilisation Runtime complet (~1 Go)    Cellule atomique (~5–50 Mo)
  Déduplication          Au niveau fichier (OSTree) Au niveau chunk (CAS)
  Partage de libs        Dans le même runtime       Entre toutes les apps
  Utilisation libs hôte  Aucune (sandbox complet)   Sélectif (ABI compatible)
  Mises à jour           Delta d'objets OSTree      Delta de chunks + réordonnancement
  Overhead par app       ~100% si runtime différent ~5–15% (seulement les différences)

Idée centrale : au lieu d'envoyer un runtime monolithique par app,
Packbox stocke chaque fichier sous forme de chunks adressés par contenu.
Deux apps partageant 90% de leurs bibliothèques ne stockent que les 10%
restants. La réutilisation inter-apps est automatique.

INSTALLATION
────────────

  git clone <repo>
  cd packbox
  ./packbox-installer-v0.1.0.sh

L'installateur :
  1. Détecte votre distribution (Debian/Ubuntu, Fedora, Arch, openSUSE)
  2. Installe Go 1.22+ si absent
  3. Crée ~/.packbox/ (caché) avec bin/ et src/
  4. Génère et compile 11 binaires Go
  5. Ajoute ~/.packbox/bin à votre PATH
  6. Installe les fichiers de langue dans ~/.config/packbox/lang/

Après : source ~/.bashrc  puis  packbox-diagnose.

UTILISATION RAPIDE
──────────────────

  # Empaqueteur interactif (recommandé)
  ./packbox-packager-v0.1.0.sh

  # Ou directement les binaires
  packbox-pack firefox-dir/ --name org.mozilla.firefox --version 128.0 \
      --description "Navigateur web" --gui --toolkit GTK3
  packbox-install firefox-dir/manifest.json
  packbox-run org.mozilla.firefox

COMMANDES
─────────

  Voir section 3.2 pour la référence complète.

  packbox-pack      Empaquette un répertoire → chunks CAS + manifest
  packbox-install   Installe depuis manifest (lien dur depuis CAS)
  packbox-run       Exécute en sandbox bwrap (fix DNS/GUI)
  packbox-list      Liste les apps installées
  packbox-remove    Désinstalle et libère les références CAS
  packbox-gc        Collecte les chunks orphelins
  packbox-verify    Vérifie la compatibilité des libs (ldd)
  packbox-export    Exporte en .pbox (zstd/xz/gzip)
  packbox-import    Importe .pbox avec validation anti path-traversal
  packbox-module    Gère les modules de libs partagées
  packbox-diagnose  Diagnostique l'environnement

LECTURES COMPLÉMENTAIRES
────────────────────────

  Section 1.3 — Architecture (EN)
  Section 1.4 — Sécurité (EN)

LICENCE / CONTRIBUER
────────────────────

Packbox v0.1.0 Alpha est en cours de développement. Les contributions
sont bienvenues, notamment : traductions, profils de sandbox
supplémentaires, et stratégies de chunking du CAS.


───────────────────────────────────────────────────────────────────────────────
3.2 RÉFÉRENCE DES COMMANDES
───────────────────────────────────────────────────────────────────────────────

Toutes les commandes sont installées dans ~/.packbox/bin/ et liées
symboliquement dans ~/.local/bin/.

3.2.1  packbox-pack
───────────────────

Rôle
  Empaqueter un arbre de répertoires en chunks CAS et écrire un
  manifest.json.

Syntaxe
  packbox-pack <répertoire> --name <id> [options]

Options
  --name <id>            App ID (obligatoire). Ex : org.mozilla.firefox
  --version <v>          Chaîne de version (défaut : 1.0.0)
  --description <texte>  Description lisible
  --entrypoint <chemin>  Chemin dans le tree (ex : /app/bin/firefox)
  --mods <a,b,c>         Noms de modules séparés par virgule
  --gui                  Marquer comme application GUI (défaut : false)
  --toolkit <nom>        GTK3, GTK4, Qt5, Qt6, SDL
  --icon <chemin>        Chemin de l'icône dans le tree

Comportement
  • Hache chaque fichier avec BLAKE3, stocke les chunks dans
    ~/.local/share/packbox/store/<xx>/<hash>.
  • Crée manifest.json dans le répertoire donné.
  • Sans --entrypoint, choisit le plus gros exécutable dans bin/.
  • Ignore manifest.json lors du hachage.

Exemples
  packbox-pack ./firefox-tree --name org.mozilla.firefox --version 128.0 \
      --description "Mozilla Firefox" --gui --toolkit GTK3

  packbox-pack ./htop-tree --name org.packbox.htop --version 3.3.0 \
      --description "Moniteur de processus"

Sortie
  [ok] <chemin>/manifest.json  archivos=N

Codes de sortie
  0 = succès
  1 = args manquants / dir inexistant / erreur store

3.2.2  packbox-install
──────────────────────

Rôle
  Installer une app depuis un manifest.json par lien dur depuis le CAS.

Syntaxe
  packbox-install <manifest.json>

Comportement
  • Si l'app est déjà installée, supprime d'abord ses références CAS.
  • Crée ~/.local/share/packbox/apps/<nom>/tree/.
  • Lie en dur chaque chunk ; copie si cross-device.
  • Préserve le mode original.
  • Enregistre une référence par chunk (<hash>.refs) pour le GC.

Exemples
  packbox-install ./firefox-tree/manifest.json

Sortie
  [install] <nom> v<ver>
  [ok] <nom> instalado  archivos=N

Codes de sortie
  0 = succès
  1 = manifest invalide / erreur store

3.2.3  packbox-run
──────────────────

Rôle
  Exécuter une app installée dans un sandbox bwrap avec support DNS/GUI.

Syntaxe
  packbox-run <app-id> [args...]

Comportement
  • Nécessite bubblewrap (bwrap) dans le PATH.
  • Monte le tree de l'app en lecture seule sur /app.
  • Bind-mounts lecture seule de /usr, /etc, /lib, /lib64, /bin, /sbin,
    /var.
  • --unshare-all --share-net (réseau autorisé, autres namespaces isolés).
  • Nettoie l'environnement, puis autorise : LANG, TZ, DISPLAY,
    WAYLAND_DISPLAY, XAUTHORITY, XDG_*, etc.
  • Fix DNS : bind-mounts de /etc/resolv.conf, /etc/hosts,
    /etc/nsswitch.conf, /etc/hostname, /etc/gai.conf, /etc/host.conf —
    et résout les symlinks (important sur systemd-resolved).
  • Support GUI : socket X11, socket Wayland, D-Bus session + système,
    /dev/dri, /dev/shm, cache fontconfig, thèmes et icônes utilisateur.
  • Données d'app : map heuristique (Firefox → ~/.mozilla, Chrome →
    ~/.config/google-chrome, etc.). --bind-try évite les erreurs si le
    dir n'existe pas.

Exemples
  packbox-run org.mozilla.firefox
  packbox-run org.packbox.htop --tree

Codes de sortie
  0 = succès
  1 = app manquante, bwrap manquant, ou échec

3.2.4  packbox-list
───────────────────

Rôle
  Lister les apps installées avec version et tags.

Syntaxe
  packbox-list

Sortie
  Apps instaladas:
  -----------------------------------------------------------
    * org.mozilla.firefox  v128.0    [GUI/GTK3]
    * org.packbox.htop     v3.3.0
  -----------------------------------------------------------
  Total: 2

Codes de sortie
  Toujours 0.

3.2.5  packbox-remove
─────────────────────

Rôle
  Désinstaller une app, retirer ses références CAS, nettoyer les entrées
  de menu.

Syntaxe
  packbox-remove <app-id>

Comportement
  • Charge le manifest, retire la référence de chaque chunk pour cette
    app.
  • Supprime ~/.local/share/packbox/apps/<app-id>/.
  • Supprime ~/.local/share/applications/packbox-<app-id>.desktop.
  • Supprime les icônes associées.
  • Ne lance pas le GC automatiquement — voir packbox-gc.

Exemples
  packbox-remove org.mozilla.firefox

Codes de sortie
  0 = succès
  1 = si l'app n'est pas installée

3.2.6  packbox-gc
─────────────────

Rôle
  Collecter les chunks orphelins (sans .refs ou .refs vide).

Syntaxe
  packbox-gc

Comportement
  • Parcourt ~/.local/share/packbox/store/<xx>/.
  • Pour chaque chunk sans <hash>.refs ou refs vide → supprime chunk
    + refs.
  • Retourne le nombre et les octets libérés.

Sortie
  [gc]
  [ok] chunks=N  bytes=B

Quand exécuter
  Après packbox-remove, ou périodiquement.

Codes de sortie
  0 = succès
  1 = erreur store

3.2.7  packbox-verify
─────────────────────

Rôle
  Vérifier si les bibliothèques d'une app installée sont disponibles sur
  l'hôte.

Syntaxe
  packbox-verify <app-id>

Comportement
  • Si l'app est PORTABLE, succès immédiat.
  • Résout le vrai binaire (gère la redirection launcher.sh).
  • Lance ldd, vérifie chaque lib contre /lib/x86_64-linux-gnu,
    /lib64, /usr/lib, /usr/lib64.
  • Rapporte le nombre de libs résolues ou liste les manquantes.

Sortie (succès)
  [ok] COMPATIBLE  libs=42

Sortie (échec)
  [fail] faltan 3 libs
     [X] libfoo.so.1

Codes de sortie
  0 = compatible
  1 = libs manquantes ou erreur manifest

Note
  Non exposé dans le menu du packager — CLI uniquement.

3.2.8  packbox-export
─────────────────────

Rôle
  Exporter une app installée vers une archive .pbox.

Syntaxe
  packbox-export app <app-id>

Comportement
  • Tar l'intégralité de ~/.local/share/packbox/apps/<app-id>/.
  • Compresse avec le meilleur outil disponible, par priorité :
      1. zstd -19 -T0
      2. xz -9e -T0
      3. gzip (fallback)
  • Sortie : ~/.local/share/packbox/exports/<app-id>.pbox.

Exemples
  packbox-export app org.mozilla.firefox

Codes de sortie
  0 = succès
  1 = app introuvable

3.2.9  packbox-import
─────────────────────

Rôle
  Importer une archive .pbox avec protection anti path-traversal.

Syntaxe
  packbox-import app <fichier.pbox>

Comportement
  • Détecte le format par magic bytes : gzip (1f 8b),
    zstd (28 b5 2f fd), xz (fd 37 7a 58).
  • Stream à travers le lecteur tar.
  • Valide chaque chemin d'entrée contre la racine d'extraction
    (security.ValidatePath) pour empêcher les évasions ../.
  • Si l'app existe déjà, avertit et écrase.
  • Extrait vers ~/.local/share/packbox/apps/<nom>/.

Exemples
  packbox-import app ~/Téléchargements/org.mozilla.firefox.pbox

Codes de sortie
  0 = succès
  1 = format inconnu / décompresseur manquant / évasion de chemin

3.2.10  packbox-module
──────────────────────

Rôle
  Gérer les modules de bibliothèques partagées.

Syntaxe
  packbox-module list
  packbox-module create <binaire> <nom> <version>
  packbox-module remove <nom> <version>       (pas encore implémenté)
  packbox-module info <nom> <version>         (pas encore implémenté)

Comportement (create)
  • Lance ldd sur <binaire>, collecte les dépendances.
  • Copie chaque lib dans mods/<nom>/<version>/lib/.
  • Écrit manifest.json avec type: "module".
  • Enregistre sous ~/.local/share/packbox/mods/<nom>/<version>/.

Exemples
  packbox-module list
  packbox-module create /usr/bin/htop org.packbox.htop-libs 1.0.0

Codes de sortie
  0 = succès
  1 = args manquants

3.2.11  packbox-diagnose
────────────────────────

Rôle
  Afficher un diagnostic de l'environnement pour les rapports de bugs.

Syntaxe
  packbox-diagnose

Sections
  • Dir d'installation, données, config
  • Vérification de la structure de répertoires
  • Vérification des outils (bwrap, readelf, ldd, jq, zstd, xz, tar)
  • Vérification des fichiers DNS (avec résolution de symlinks)
  • Kernel, architecture, version Go

Exemples
  packbox-diagnose > /tmp/packbox-diag.txt

Codes de sortie
  Toujours 0.

3.2.12  packbox-installer-v0.1.0.sh
───────────────────────────────────

Rôle
  Installateur / désinstallateur interactif.

Syntaxe
  ./packbox-installer-v0.1.0.sh

Menu
  1  Installer Packbox
  2  Désinstaller Packbox
  0  Quitter

Flux d'installation
  1. Détecter la distribution
  2. Confirmer avant d'installer les deps
     (bubblewrap binutils jq bc curl tar)
  3. Installer Go 1.22+ si absent
  4. Créer ~/.packbox/{bin,src} et
     ~/.local/share/packbox/{store,apps,mods,exports,tmp}
  5. Générer le code Go (11 commandes + 4 packages internes)
  6. Compiler les binaires
  7. Configurer PATH (ajoute à .bashrc, symlinks dans ~/.local/bin)
  8. Vérifier les 11 binaires

Flux de désinstallation
  • Scanne ce qui sera supprimé, montre les tailles
  • Mode s = suppression complète
  • Mode k = binaires uniquement (garde apps/store)
  • Mode q = annuler
  • Exige de taper DELETE pour confirmer
  • Nettoie .bashrc (backup : ~/.bashrc.packbox-uninstall.bak)
  • Rafraîchit les caches menu et icônes

Langue
  Propose l'un des 9 idiomes au démarrage.

3.2.13  packbox-packager-v0.1.0.sh
──────────────────────────────────

Rôle
  Frontend interactif des binaires du packager.

Syntaxe
  ./packbox-packager-v0.1.0.sh

Menu
  1  Empaqueter une application système
  2  Lister les applications installées
  3  Collecte de miettes (GC)
  4  Exporter une app vers un fichier
  5  Importer une app depuis un fichier
  6  Désinstaller une application
  0  Quitter

Flux de l'option 1
  1. Détecte les apps depuis les fichiers .desktop + binaires communs
     + /opt/* + /usr/lib/* (avec symlink dans /usr/bin)
  2. Affiche le Top 15 par taille (avec f=filtrer Mo, b=chercher,
     r=plus, q=annuler)
  3. Montre les détails, demande à empaqueter
  4. Configure App ID, Version, Description, Mode
  5. Modes : 1=Normal, 2=Portable, 3=Module, 4=Bundle
     (recommandé pour les bundles)
  6. Invoque packbox-pack → packbox-install → optionnellement
     create_desktop_entry
  7. Optionnellement exporte en .pbox
  8. Optionnellement exécute

Détection double
  Préfère ~/.packbox/bin, fallback ~/packbox/bin (legacy).

Langue
  Lit depuis ~/.config/packbox/lang/.

CONVENTIONS DE CODES DE SORTIE
──────────────────────────────

  0 = Succès
  1 = Erreur (args manquants, ressource absente…)

VARIABLES D'ENVIRONNEMENT
─────────────────────────

  HOME                 Base de ~/.packbox, données
  PACKBOX_LANG         Forcer le code de langue
  PACKBOX_LANG_DIR     Remplacer le dir des langues
  DISPLAY, WAYLAND_DISPLAY, XAUTHORITY, XDG_*
                       Passés au sandbox
  LD_LIBRARY_PATH      Défini par le launcher.sh


═══════════════════════════════════════════════════════════════════════════════
4. DEUTSCH
═══════════════════════════════════════════════════════════════════════════════

───────────────────────────────────────────────────────────────────────────────
4.1 README
───────────────────────────────────────────────────────────────────────────────

Packbox v0.1.0 Alpha — Deutsch

Ein Anwendungspaketierungssystem der nächsten Generation, inspiriert von
Flatpak, aber mit einem grundlegend anderen Wiederverwendungsmodell.

WAS PACKBOX ANDERS MACHT
────────────────────────

  Merkmal                  Flatpak (aktuell)          Packbox (vorgeschlagen)
  ─────────────────────────────────────────────────────────────────────
  Wiederverwendungseinheit Vollständige Runtime       Atomare Zelle
                           (~1 GB)                    (~5–50 MB)
  Deduplizierung           Datei-Ebene (OSTree)       Chunk-Ebene (CAS)
  Bibliotheks-Sharing      Innerhalb derselben Runtime Über alle Apps hinweg
  Nutzung Host-Libs        Keine (vollständige Sandbox) Selektiv (ABI-kompatibel)
  Updates                  OSTree-Objekt-Delta        Chunk-Delta + Neuanordnung
  Overhead pro App         ~100% bei anderer Runtime  ~5–15% (nur Unterschiede)

Kernidee: Statt einer monolithischen Runtime pro App speichert Packbox
jede Datei als inhaltsadressierte Chunks. Zwei Apps, die 90% ihrer
Bibliotheken teilen, speichern nur die abweichenden 10%.

INSTALLATION
────────────

  git clone <repo>
  cd packbox
  ./packbox-installer-v0.1.0.sh

Der Installer:
  1. Erkennt deine Distribution (Debian/Ubuntu, Fedora, Arch, openSUSE)
  2. Installiert Go 1.22+, falls nicht vorhanden
  3. Erstellt ~/.packbox/ (versteckt) mit bin/ und src/
  4. Generiert und kompiliert 11 Go-Binärdateien
  5. Fügt ~/.packbox/bin zum PATH hinzu
  6. Installiert Sprachdateien nach ~/.config/packbox/lang/

Danach: source ~/.bashrc  und  packbox-diagnose.

SCHNELLSTART
────────────

  # Interaktiver Packager (empfohlen)
  ./packbox-packager-v0.1.0.sh

  # Oder die Binärdateien direkt
  packbox-pack firefox-dir/ --name org.mozilla.firefox --version 128.0 \
      --description "Webbrowser" --gui --toolkit GTK3
  packbox-install firefox-dir/manifest.json
  packbox-run org.mozilla.firefox

BEFEHLE
───────

  Siehe Abschnitt 4.2 für die vollständige Referenz.

  packbox-pack      Verzeichnis → CAS-Chunks + Manifest paketieren
  packbox-install   Aus Manifest installieren (Hardlink aus CAS)
  packbox-run       In bwrap-Sandbox ausführen (DNS/GUI-Fix)
  packbox-list      Installierte Apps auflisten
  packbox-remove    App deinstallieren und CAS-Referenzen freigeben
  packbox-gc        Verwaiste Chunks aufräumen
  packbox-verify    Bibliotheks-Kompatibilität prüfen (ldd)
  packbox-export    App nach .pbox exportieren (zstd/xz/gzip)
  packbox-import    .pbox mit Path-Traversal-Schutz importieren
  packbox-module    Shared-Library-Module verwalten
  packbox-diagnose  Umgebung diagnostizieren

WEITERFÜHRENDE LEKTÜRE
──────────────────────

  Abschnitt 1.3 — Architektur (EN)
  Abschnitt 1.4 — Sicherheit (EN)

LIZENZ / BEITRAGEN
──────────────────

Packbox v0.1.0 Alpha ist ein Work in Progress. Beiträge sind willkommen,
insbesondere: Übersetzungen, zusätzliche Sandbox-Profile und
CAS-Chunking-Strategien.


───────────────────────────────────────────────────────────────────────────────
4.2 BEFEHLSPREFERENZ
───────────────────────────────────────────────────────────────────────────────

Alle Befehle werden nach ~/.packbox/bin/ installiert und nach
~/.local/bin/ verlinkt.

4.2.1  packbox-pack
───────────────────

Zweck
  Ein Verzeichnis in CAS-Chunks paketieren und eine manifest.json
  schreiben.

Syntax
  packbox-pack <verzeichnis> --name <id> [optionen]

Optionen
  --name <id>            App-ID (erforderlich). Z.B. org.mozilla.firefox
  --version <v>          Versionsstring (Standard: 1.0.0)
  --description <text>   Lesbare Beschreibung
  --entrypoint <pfad>    Pfad im Tree (z.B. /app/bin/firefox)
  --mods <a,b,c>         Kommagetrennte Modulnamen
  --gui                  Als GUI-Anwendung markieren (Standard: false)
  --toolkit <name>       GTK3, GTK4, Qt5, Qt6, SDL
  --icon <pfad>          Icon-Pfad im Tree

Verhalten
  • Hasht jede Datei mit BLAKE3, speichert Chunks in
    ~/.local/share/packbox/store/<xx>/<hash>.
  • Erstellt manifest.json im angegebenen Verzeichnis.
  • Ohne --entrypoint wird die größte ausführbare Datei in bin/ gewählt.
  • Überspringt manifest.json beim Hashing.

Beispiele
  packbox-pack ./firefox-tree --name org.mozilla.firefox --version 128.0 \
      --description "Mozilla Firefox" --gui --toolkit GTK3

  packbox-pack ./htop-tree --name org.packbox.htop --version 3.3.0 \
      --description "Interaktiver Prozessbetrachter"

Ausgabe
  [ok] <pfad>/manifest.json  archivos=N

Exit-Codes
  0 = Erfolg
  1 = fehlende Args / nicht existierendes Verzeichnis / Store-Fehler

4.2.2  packbox-install
──────────────────────

Zweck
  Eine App aus einer manifest.json installieren, indem Chunks per
  Hardlink aus dem CAS verlinkt werden.

Syntax
  packbox-install <manifest.json>

Verhalten
  • Wenn die App bereits installiert ist, werden zuerst die alten
    CAS-Referenzen entfernt.
  • Erstellt ~/.local/share/packbox/apps/<name>/tree/.
  • Verlinkt jeden Chunk hart; Fallback auf Kopie bei Cross-Device.
  • Erhält den ursprünglichen Dateimodus.
  • Registriert eine Referenz pro Chunk (<hash>.refs) für GC.

Beispiele
  packbox-install ./firefox-tree/manifest.json

Ausgabe
  [install] <name> v<ver>
  [ok] <name> instalado  archivos=N

Exit-Codes
  0 = Erfolg
  1 = ungültiges Manifest / Store-Fehler

4.2.3  packbox-run
──────────────────

Zweck
  Eine installierte App in einer bwrap-Sandbox mit DNS/GUI-Unterstützung
  ausführen.

Syntax
  packbox-run <app-id> [args...]

Verhalten
  • Erfordert bubblewrap (bwrap) im PATH.
  • Bindet den App-Tree read-only auf /app.
  • Read-only Bind-Mounts von /usr, /etc, /lib, /lib64, /bin, /sbin,
    /var.
  • --unshare-all --share-net (Netzwerk erlaubt, andere Namespaces
    isoliert).
  • Leert die Umgebung, dann Whitelist: LANG, TZ, DISPLAY,
    WAYLAND_DISPLAY, XAUTHORITY, XDG_*, usw.
  • DNS-Fix: Bind-Mounts von /etc/resolv.conf, /etc/hosts,
    /etc/nsswitch.conf, /etc/hostname, /etc/gai.conf, /etc/host.conf —
    und löst Symlinks auf (wichtig bei systemd-resolved).
  • GUI-Unterstützung: X11-Socket, Wayland-Socket, D-Bus Session +
    System-Bus, /dev/dri, /dev/shm, fontconfig-Cache, User-Themes/Icons.
  • App-Daten: Heuristische Map (Firefox → ~/.mozilla, Chrome →
    ~/.config/google-chrome, usw.). --bind-try vermeidet Fehler, wenn
    das Verzeichnis fehlt.

Beispiele
  packbox-run org.mozilla.firefox
  packbox-run org.packbox.htop --tree

Exit-Codes
  0 = Erfolg
  1 = App fehlt, bwrap fehlt, oder Ausführung fehlgeschlagen

4.2.4  packbox-list
───────────────────

Zweck
  Installierte Apps mit Version und Tags auflisten.

Syntax
  packbox-list

Ausgabe
  Apps instaladas:
  -----------------------------------------------------------
    * org.mozilla.firefox  v128.0    [GUI/GTK3]
    * org.packbox.htop     v3.3.0
  -----------------------------------------------------------
  Total: 2

Exit-Codes
  Immer 0.

4.2.5  packbox-remove
─────────────────────

Zweck
  Eine App deinstallieren, ihre CAS-Referenzen entfernen und Menüeinträge
  aufräumen.

Syntax
  packbox-remove <app-id>

Verhalten
  • Lädt das Manifest, entfernt jede Chunk-Referenz für diese App.
  • Löscht ~/.local/share/packbox/apps/<app-id>/.
  • Löscht ~/.local/share/applications/packbox-<app-id>.desktop.
  • Löscht zugehörige Icons.
  • Führt GC nicht automatisch aus — nutze packbox-gc.

Beispiele
  packbox-remove org.mozilla.firefox

Exit-Codes
  0 = Erfolg
  1 = wenn nicht installiert

4.2.6  packbox-gc
─────────────────

Zweck
  Verwaiste Chunks aufräumen (keine .refs oder leere .refs).

Syntax
  packbox-gc

Verhalten
  • Durchläuft ~/.local/share/packbox/store/<xx>/.
  • Für jeden Chunk ohne <hash>.refs oder mit leerer refs → löscht Chunk
    + Refs.
  • Gibt Anzahl und freigegebene Bytes zurück.

Ausgabe
  [gc]
  [ok] chunks=N  bytes=B

Wann ausführen
  Nach packbox-remove oder regelmäßig.

Exit-Codes
  0 = Erfolg
  1 = Store-Fehler

4.2.7  packbox-verify
─────────────────────

Zweck
  Prüfen, ob die Bibliotheken einer installierten App auf dem Host
  verfügbar sind.

Syntax
  packbox-verify <app-id>

Verhalten
  • Wenn die App PORTABLE ist, sofortiger Erfolg.
  • Löst die echte Binärdatei auf (behandelt launcher.sh-Umleitung).
  • Führt ldd aus, prüft jede Lib gegen /lib/x86_64-linux-gnu,
    /lib64, /usr/lib, /usr/lib64.
  • Meldet Anzahl aufgelöster Libs oder listet fehlende.

Ausgabe (Erfolg)
  [ok] COMPATIBLE  libs=42

Ausgabe (Fehler)
  [fail] faltan 3 libs
     [X] libfoo.so.1

Exit-Codes
  0 = kompatibel
  1 = fehlende Libs oder Manifest-Fehler

Hinweis
  Nicht im Packager-Menü — nur CLI.

4.2.8  packbox-export
─────────────────────

Zweck
  Eine installierte App in ein .pbox-Archiv exportieren.

Syntax
  packbox-export app <app-id>

Verhalten
  • Tared das gesamte ~/.local/share/packbox/apps/<app-id>/.
  • Komprimiert mit dem besten verfügbaren Tool, nach Priorität:
      1. zstd -19 -T0
      2. xz -9e -T0
      3. gzip (Fallback)
  • Ausgabe: ~/.local/share/packbox/exports/<app-id>.pbox.

Beispiele
  packbox-export app org.mozilla.firefox

Exit-Codes
  0 = Erfolg
  1 = App nicht gefunden

4.2.9  packbox-import
─────────────────────

Zweck
  Ein .pbox-Archiv mit Path-Traversal-Schutz importieren.

Syntax
  packbox-import app <datei.pbox>

Verhalten
  • Erkennt Format anhand Magic Bytes: gzip (1f 8b),
    zstd (28 b5 2f fd), xz (fd 37 7a 58).
  • Streamt durch tar-Reader.
  • Validiert jeden Eintragspfad gegen die Extraktionswurzel
    (security.ValidatePath), um ../-Ausbrüche zu verhindern.
  • Wenn die App bereits existiert, wird gewarnt und überschrieben.
  • Extrahiert nach ~/.local/share/packbox/apps/<name>/.

Beispiele
  packbox-import app ~/Downloads/org.mozilla.firefox.pbox

Exit-Codes
  0 = Erfolg
  1 = unbekanntes Format / fehlender Dekompressor / Pfad-Ausbruch

4.2.10  packbox-module
──────────────────────

Zweck
  Shared-Library-Module verwalten.

Syntax
  packbox-module list
  packbox-module create <binär> <name> <version>
  packbox-module remove <name> <version>       (noch nicht implementiert)
  packbox-module info <name> <version>         (noch nicht implementiert)

Verhalten (create)
  • Führt ldd auf <binär> aus, sammelt Abhängigkeiten.
  • Kopiert jede Lib nach mods/<name>/<version>/lib/.
  • Schreibt manifest.json mit type: "module".
  • Registriert unter ~/.local/share/packbox/mods/<name>/<version>/.

Beispiele
  packbox-module list
  packbox-module create /usr/bin/htop org.packbox.htop-libs 1.0.0

Exit-Codes
  0 = Erfolg
  1 = fehlende Args

4.2.11  packbox-diagnose
────────────────────────

Zweck
  Umgebungsdiagnose für Bug-Reports ausgeben.

Syntax
  packbox-diagnose

Abschnitte
  • Install-Dir, Daten-Dir, Config-Dir
  • Verzeichnisstruktur-Check
  • Tool-Check (bwrap, readelf, ldd, jq, zstd, xz, tar)
  • DNS-Datei-Check (mit Symlink-Auflösung)
  • Kernel, Arch, Go-Version

Beispiele
  packbox-diagnose > /tmp/packbox-diag.txt

Exit-Codes
  Immer 0.

4.2.12  packbox-installer-v0.1.0.sh
───────────────────────────────────

Zweck
  Interaktiver Installer / Deinstaller.

Syntax
  ./packbox-installer-v0.1.0.sh

Menü
  1  Packbox installieren
  2  Packbox deinstallieren
  0  Beenden

Installationsablauf
  1. Distribution erkennen
  2. Vor Installation der Deps bestätigen
     (bubblewrap binutils jq bc curl tar)
  3. Go 1.22+ installieren, falls nicht vorhanden
  4. ~/.packbox/{bin,src} und
     ~/.local/share/packbox/{store,apps,mods,exports,tmp} erstellen
  5. Go-Code generieren (11 Befehle + 4 interne Pakete)
  6. Binärdateien kompilieren
  7. PATH konfigurieren (zu .bashrc hinzufügen, Symlinks in
     ~/.local/bin)
  8. Alle 11 Binärdateien verifizieren

Deinstallationsablauf
  • Scannt, was entfernt wird, zeigt Größen
  • Modus s = vollständige Entfernung
  • Modus k = nur Binärdateien (Apps/Store bleiben)
  • Modus q = abbrechen
  • Erfordert Eingabe von DELETE zur Bestätigung
  • Bereinigt .bashrc (Backup: ~/.bashrc.packbox-uninstall.bak)
  • Aktualisiert Menü- und Icon-Caches

Sprache
  Fragt zu Beginn nach einer von 9 Sprachen.

4.2.13  packbox-packager-v0.1.0.sh
──────────────────────────────────

Zweck
  Interaktives Frontend für die Packager-Binärdateien.

Syntax
  ./packbox-packager-v0.1.0.sh

Menü
  1  Systemanwendung paketieren
  2  Installierte Apps auflisten
  3  Speicherbereinigung (GC)
  4  App in Datei exportieren
  5  App aus Datei importieren
  6  Anwendung deinstallieren
  0  Beenden

Ablauf von Option 1
  1. Erkennt Apps aus .desktop-Dateien + gängigen Binärdateien
     + /opt/* + /usr/lib/* (mit Symlink in /usr/bin)
  2. Zeigt Top 15 nach Größe (f=MB filtern, b=suchen, r=mehr,
     q=abbrechen)
  3. Zeigt Details, fragt nach Paketierung
  4. Konfiguriert App-ID, Version, Beschreibung, Modus
  5. Modi: 1=Normal, 2=Portabel, 3=Modul, 4=Bundle
  6. Ruft packbox-pack → packbox-install → optional
     create_desktop_entry auf
  7. Optionaler Export nach .pbox
  8. Optionale Ausführung

Duale Erkennung
  Bevorzugt ~/.packbox/bin, Fallback ~/packbox/bin.

Sprache
  Liest aus ~/.config/packbox/lang/.

EXIT-CODE-KONVENTIONEN
──────────────────────

  0 = Erfolg
  1 = Fehler (fehlende Args, fehlende Ressource…)

UMGEBUNGSVARIABLEN
──────────────────

  HOME                 Basis für ~/.packbox, Daten
  PACKBOX_LANG         Sprachcode erzwingen
  PACKBOX_LANG_DIR     Sprachverzeichnis überschreiben
  DISPLAY, WAYLAND_DISPLAY, XAUTHORITY, XDG_*
                       Werden an Sandbox weitergegeben
  LD_LIBRARY_PATH      Von launcher.sh gesetzt


═══════════════════════════════════════════════════════════════════════════════
5. ITALIANO
═══════════════════════════════════════════════════════════════════════════════

───────────────────────────────────────────────────────────────────────────────
5.1 README
───────────────────────────────────────────────────────────────────────────────

Packbox v0.1.0 Alpha — Italiano

Sistema di packaging di applicazioni di nuova generazione, ispirato a
Flatpak ma con un modello di riuso fondamentalmente diverso.

COSA RENDE PACKBOX DIVERSO
──────────────────────────

  Caratteristica          Flatpak (attuale)          Packbox (proposto)
  ─────────────────────────────────────────────────────────────────────
  Unità di riuso          Runtime completo (~1 GB)   Cella atomica (~5–50 MB)
  Deduplicazione          A livello di file (OSTree) A livello di chunk (CAS)
  Condivisione librerie   Nello stesso runtime       Tra tutte le app
  Uso librerie host       Nessuno (sandbox completa) Selettivo (ABI compatibile)
  Aggiornamenti           Delta oggetti OSTree       Delta chunk + riordino
  Overhead per app        ~100% se runtime diverso   ~5–15% (solo differenze)

Idea centrale: invece di spedire un runtime monolitico per app, Packbox
memorizza ogni file come chunk indirizzati per contenuto. Due app che
condividono il 90% delle librerie memorizzano solo il 10% differente.

INSTALLAZIONE
─────────────

  git clone <repo>
  cd packbox
  ./packbox-installer-v0.1.0.sh

L'installer:
  1. Rileva la tua distro (famiglie Debian/Ubuntu, Fedora, Arch, openSUSE)
  2. Installa Go 1.22+ se assente
  3. Crea ~/.packbox/ (nascosto) con bin/ e src/
  4. Genera e compila 11 binari Go
  5. Aggiunge ~/.packbox/bin al PATH
  6. Installa i file di lingua in ~/.config/packbox/lang/

Dopo: source ~/.bashrc  e poi  packbox-diagnose.

USO RAPIDO
──────────

  # Packager interattivo (consigliato)
  ./packbox-packager-v0.1.0.sh

  # Oppure i binari direttamente
  packbox-pack firefox-dir/ --name org.mozilla.firefox --version 128.0 \
      --description "Browser web" --gui --toolkit GTK3
  packbox-install firefox-dir/manifest.json
  packbox-run org.mozilla.firefox

COMANDI
───────

  Vedi sezione 5.2 per il riferimento completo.

  packbox-pack      Impacchetta directory → chunk CAS + manifest
  packbox-install   Installa da manifest (hardlink dal CAS)
  packbox-run       Esegue in sandbox bwrap (fix DNS/GUI)
  packbox-list      Elenca app installate
  packbox-remove    Disinstalla e rilascia i riferimenti CAS
  packbox-gc        Raccoglie chunk orfani
  packbox-verify    Verifica compatibilità librerie (ldd)
  packbox-export    Esporta in .pbox (zstd/xz/gzip)
  packbox-import    Importa .pbox con validazione anti path-traversal
  packbox-module    Gestisce moduli di librerie condivise
  packbox-diagnose  Diagnostica l'ambiente

LETTURE AGGIUNTIVE
──────────────────

  Sezione 1.3 — Architettura (EN)
  Sezione 1.4 — Sicurezza (EN)

LICENZA / CONTRIBUIRE
─────────────────────

Packbox v0.1.0 Alpha è in sviluppo. I contributi sono benvenuti,
specialmente: traduzioni, profili di sandbox aggiuntivi e strategie di
chunking del CAS.


───────────────────────────────────────────────────────────────────────────────
5.2 RIFERIMENTO COMANDI
───────────────────────────────────────────────────────────────────────────────

Tutti i comandi sono installati in ~/.packbox/bin/ e linkati in
~/.local/bin/.

5.2.1  packbox-pack
───────────────────

Scopo
  Impacchettare un albero di directory in chunk CAS e scrivere un
  manifest.json.

Sintassi
  packbox-pack <directory> --name <id> [opzioni]

Opzioni
  --name <id>            App ID (obbligatorio). Es: org.mozilla.firefox
  --version <v>          Stringa di versione (default: 1.0.0)
  --description <testo>  Descrizione leggibile
  --entrypoint <percorso> Percorso nel tree (es. /app/bin/firefox)
  --mods <a,b,c>         Nomi moduli separati da virgola
  --gui                  Marca come applicazione GUI (default: false)
  --toolkit <nome>       GTK3, GTK4, Qt5, Qt6, SDL
  --icon <percorso>      Percorso icona nel tree

Comportamento
  • Calcola BLAKE3 di ogni file, memorizza i chunk in
    ~/.local/share/packbox/store/<xx>/<hash>.
  • Crea manifest.json nella directory data.
  • Senza --entrypoint, sceglie l'eseguibile più grande in bin/.
  • Salta manifest.json durante l'hashing.

Esempi
  packbox-pack ./firefox-tree --name org.mozilla.firefox --version 128.0 \
      --description "Mozilla Firefox" --gui --toolkit GTK3

  packbox-pack ./htop-tree --name org.packbox.htop --version 3.3.0

Output
  [ok] <percorso>/manifest.json  archivos=N

Exit code
  0 = successo
  1 = args mancanti / dir inesistente / errore store

5.2.2  packbox-install
──────────────────────

Scopo
  Installare un'app da manifest.json collegando i chunk dal CAS.

Sintassi
  packbox-install <manifest.json>

Comportamento
  • Se l'app è già installata, rimuove prima i vecchi riferimenti CAS.
  • Crea ~/.local/share/packbox/apps/<nome>/tree/.
  • Collega in hardlink ogni chunk; fallback a copia se cross-device.
  • Preserva il modo originale.
  • Registra un riferimento per chunk (<hash>.refs) per il GC.

Esempi
  packbox-install ./firefox-tree/manifest.json

Output
  [install] <nome> v<ver>
  [ok] <nome> instalado  archivos=N

Exit code
  0 = successo
  1 = manifest invalido / errore store

5.2.3  packbox-run
──────────────────

Scopo
  Eseguire un'app installata in una sandbox bwrap con supporto DNS/GUI.

Sintassi
  packbox-run <app-id> [args...]

Comportamento
  • Richiede bubblewrap (bwrap) nel PATH.
  • Monta il tree dell'app in sola lettura su /app.
  • Bind-mount sola lettura di /usr, /etc, /lib, /lib64, /bin, /sbin,
    /var.
  • --unshare-all --share-net (rete permessa, altri namespace isolati).
  • Pulisce l'ambiente, poi whitelist: LANG, TZ, DISPLAY,
    WAYLAND_DISPLAY, XAUTHORITY, XDG_*, ecc.
  • Fix DNS: bind-mount di /etc/resolv.conf, /etc/hosts,
    /etc/nsswitch.conf, /etc/hostname, /etc/gai.conf, /etc/host.conf —
    e risolve i symlink (importante su systemd-resolved).
  • Supporto GUI: socket X11, socket Wayland, D-Bus sessione + sistema,
    /dev/dri, /dev/shm, cache fontconfig, temi e icone utente.
  • Dati app: mappa euristica (Firefox → ~/.mozilla, Chrome →
    ~/.config/google-chrome, ecc.). --bind-try evita errori se la dir
    non esiste.

Esempi
  packbox-run org.mozilla.firefox
  packbox-run org.packbox.htop --tree

Exit code
  0 = successo
  1 = app mancante, bwrap mancante, o errore

5.2.4  packbox-list
───────────────────

Scopo
  Elencare le app installate con versione e tag.

Sintassi
  packbox-list

Output
  Apps instaladas:
  -----------------------------------------------------------
    * org.mozilla.firefox  v128.0    [GUI/GTK3]
    * org.packbox.htop     v3.3.0
  -----------------------------------------------------------
  Total: 2

Exit code
  Sempre 0.

5.2.5  packbox-remove
─────────────────────

Scopo
  Disinstallare un'app, rimuovere i riferimenti CAS e pulire le voci di
  menu.

Sintassi
  packbox-remove <app-id>

Comportamento
  • Carica il manifest, rimuove il riferimento di ogni chunk per questa
    app.
  • Elimina ~/.local/share/packbox/apps/<app-id>/.
  • Elimina ~/.local/share/applications/packbox-<app-id>.desktop.
  • Elimina le icone associate.
  • Non esegue il GC automaticamente — vedi packbox-gc.

Esempi
  packbox-remove org.mozilla.firefox

Exit code
  0 = successo
  1 = se non installata

5.2.6  packbox-gc
─────────────────

Scopo
  Raccogliere chunk orfani (senza .refs o .refs vuoto).

Sintassi
  packbox-gc

Comportamento
  • Attraversa ~/.local/share/packbox/store/<xx>/.
  • Per ogni chunk senza <hash>.refs o refs vuoto → elimina chunk + refs.
  • Restituisce numero e byte liberati.

Output
  [gc]
  [ok] chunks=N  bytes=B

Quando eseguire
  Dopo packbox-remove, o periodicamente.

Exit code
  0 = successo
  1 = errore store

5.2.7  packbox-verify
─────────────────────

Scopo
  Verificare se le librerie di un'app installata sono disponibili
  sull'host.

Sintassi
  packbox-verify <app-id>

Comportamento
  • Se l'app è PORTABLE, successo immediato.
  • Risolve il binario reale (gestisce reindirizzamento launcher.sh).
  • Esegue ldd, controlla ogni lib contro /lib/x86_64-linux-gnu,
    /lib64, /usr/lib, /usr/lib64.
  • Riporta il numero di lib risolte o elenca le mancanti.

Output (successo)
  [ok] COMPATIBLE  libs=42

Output (errore)
  [fail] faltan 3 libs
     [X] libfoo.so.1

Exit code
  0 = compatibile
  1 = lib mancanti o errore manifest

Nota
  Non esposto nel menu del packager — solo CLI.

5.2.8  packbox-export
─────────────────────

Scopo
  Esportare un'app installata in un archivio .pbox.

Sintassi
  packbox-export app <app-id>

Comportamento
  • Crea tar di tutto ~/.local/share/packbox/apps/<app-id>/.
  • Comprime con il miglior tool disponibile, in ordine di priorità:
      1. zstd -19 -T0
      2. xz -9e -T0
      3. gzip (fallback)
  • Output: ~/.local/share/packbox/exports/<app-id>.pbox.

Esempi
  packbox-export app org.mozilla.firefox

Exit code
  0 = successo
  1 = app non trovata

5.2.9  packbox-import
─────────────────────

Scopo
  Importare un archivio .pbox con protezione anti path-traversal.

Sintassi
  packbox-import app <file.pbox>

Comportamento
  • Rileva il formato dai magic bytes: gzip (1f 8b),
    zstd (28 b5 2f fd), xz (fd 37 7a 58).
  • Stream attraverso il tar reader.
  • Valida ogni percorso di ingresso contro la radice di estrazione
    (security.ValidatePath) per prevenire escape ../.
  • Se l'app esiste già, avvisa e sovrascrive.
  • Estrae in ~/.local/share/packbox/apps/<nome>/.

Esempi
  packbox-import app ~/Download/org.mozilla.firefox.pbox

Exit code
  0 = successo
  1 = formato sconosciuto / decompressore mancante / escape percorso

5.2.10  packbox-module
──────────────────────

Scopo
  Gestire moduli di librerie condivise.

Sintassi
  packbox-module list
  packbox-module create <binario> <nome> <versione>
  packbox-module remove <nome> <versione>       (non ancora implementato)
  packbox-module info <nome> <versione>         (non ancora implementato)

Comportamento (create)
  • Esegue ldd su <binario>, raccoglie le dipendenze.
  • Copia ogni libreria in mods/<nome>/<versione>/lib/.
  • Scrive manifest.json con type: "module".
  • Registra sotto ~/.local/share/packbox/mods/<nome>/<versione>/.

Esempi
  packbox-module list
  packbox-module create /usr/bin/htop org.packbox.htop-libs 1.0.0

Exit code
  0 = successo
  1 = args mancanti

5.2.11  packbox-diagnose
────────────────────────

Scopo
  Stampare diagnostica dell'ambiente per bug report.

Sintassi
  packbox-diagnose

Sezioni
  • Dir installazione, dati, config
  • Check struttura directory
  • Check tool (bwrap, readelf, ldd, jq, zstd, xz, tar)
  • Check file DNS (con risoluzione symlink)
  • Kernel, arch, versione Go

Esempi
  packbox-diagnose > /tmp/packbox-diag.txt

Exit code
  Sempre 0.

5.2.12  packbox-installer-v0.1.0.sh
───────────────────────────────────

Scopo
  Installer / disinstaller interattivo.

Sintassi
  ./packbox-installer-v0.1.0.sh

Menu
  1  Installa Packbox
  2  Disinstalla Packbox
  0  Esci

Flusso di installazione
  1. Rileva distro
  2. Conferma prima di installare deps
     (bubblewrap binutils jq bc curl tar)
  3. Installa Go 1.22+ se assente
  4. Crea ~/.packbox/{bin,src} e
     ~/.local/share/packbox/{store,apps,mods,exports,tmp}
  5. Genera codice Go (11 comandi + 4 package interni)
  6. Compila binari
  7. Configura PATH (aggiunge a .bashrc, symlink in ~/.local/bin)
  8. Verifica gli 11 binari

Flusso di disinstallazione
  • Analizza cosa sarà rimosso, mostra dimensioni
  • Modalità s = rimozione completa
  • Modalità k = solo binari (mantiene apps/store)
  • Modalità q = annulla
  • Richiede digitare DELETE per confermare
  • Pulisce .bashrc (backup: ~/.bashrc.packbox-uninstall.bak)
  • Aggiorna cache menu e icone

Lingua
  Chiede una delle 9 lingue all'avvio.

5.2.13  packbox-packager-v0.1.0.sh
──────────────────────────────────

Scopo
  Frontend interattivo dei binari del packager.

Sintassi
  ./packbox-packager-v0.1.0.sh

Menu
  1  Impacchetta applicazione di sistema
  2  Elenca app installate
  3  Garbage collection
  4  Esporta app su file
  5  Importa app da file
  6  Disinstalla applicazione
  0  Esci

Flusso opzione 1
  1. Rileva app da file .desktop + binari comuni + /opt/* +
     /usr/lib/* (con symlink in /usr/bin)
  2. Mostra Top 15 per dimensione (f=filtra MB, b=cerca, r=più,
     q=annulla)
  3. Mostra dettagli, chiede se impacchettare
  4. Configura App ID, Versione, Descrizione, Modalità
  5. Modalità: 1=Normale, 2=Portabile, 3=Modulo, 4=Bundle
  6. Invoca packbox-pack → packbox-install → opzionalmente
     create_desktop_entry
  7. Opzionalmente esporta in .pbox
  8. Opzionalmente esegue

Rilevamento duale
  Preferisce ~/.packbox/bin, fallback ~/packbox/bin.

Lingua
  Legge da ~/.config/packbox/lang/.

CONVENZIONI EXIT CODE
─────────────────────

  0 = Successo
  1 = Errore (args mancanti, risorsa assente, ...)

VARIABILI D'AMBIENTE
────────────────────

  HOME                 Base per ~/.packbox, dati
  PACKBOX_LANG         Forza codice lingua
  PACKBOX_LANG_DIR     Override dir lingue
  DISPLAY, WAYLAND_DISPLAY, XAUTHORITY, XDG_*
                       Passate alla sandbox
  LD_LIBRARY_PATH      Impostato da launcher.sh


═══════════════════════════════════════════════════════════════════════════════
6. 简体中文 (ZH-CN)
═══════════════════════════════════════════════════════════════════════════════

───────────────────────────────────────────────────────────────────────────────
6.1 README
───────────────────────────────────────────────────────────────────────────────

Packbox v0.1.0 Alpha — 简体中文

新一代应用程序打包系统，受 Flatpak 启发，但采用根本不同的复用模型。

PACKBOX 的不同之处
──────────────────

  特性              Flatpak（当前）              Packbox（提议）
  ─────────────────────────────────────────────────────────────────────
  复用单元          完整运行时（约 1 GB）        原子单元（约 5–50 MB）
  去重              文件级（OSTree）             块级（CAS）
  库共享            同一运行时内                跨所有应用
  主机库使用        无（完全沙箱）              选择性（ABI 兼容）
  更新              OSTree 对象增量             块增量 + 重排序
  每应用开销        若运行时不同则约 100%       约 5–15%（仅差异）

核心思想：Packbox 不再为每个应用分发一个整体运行时，而是将每个文件
存储为按内容寻址的块。两个共享 90% 库的应用只存储不同的 10%。跨应用
的库复用是自动的。

安装
────

  git clone <repo>
  cd packbox
  ./packbox-installer-v0.1.0.sh

安装程序将：
  1. 检测你的发行版（Debian/Ubuntu、Fedora、Arch、openSUSE 系列）
  2. 若缺失则安装 Go 1.22+
  3. 创建 ~/.packbox/（隐藏）包含 bin/ 和 src/
  4. 生成并编译 11 个 Go 二进制文件
  5. 将 ~/.packbox/bin 添加到 PATH
  6. 安装语言文件到 ~/.config/packbox/lang/

安装后：source ~/.bashrc  然后  packbox-diagnose。

快速使用
────────

  # 交互式打包器（推荐首次使用者）
  ./packbox-packager-v0.1.0.sh

  # 或直接使用二进制文件
  packbox-pack firefox-dir/ --name org.mozilla.firefox --version 128.0 \
      --description "Web 浏览器" --gui --toolkit GTK3
  packbox-install firefox-dir/manifest.json
  packbox-run org.mozilla.firefox

文件系统布局
────────────

  ~/.packbox/                     安装（二进制 + Go 源码）
  ├── bin/                        11 个 Go 二进制文件
  └── src/                        Go 模块源码

  ~/.local/share/packbox/         数据
  ├── store/                      CAS — 按 BLAKE3 哈希存储的块
  ├── apps/                       已安装应用（tree + manifest）
  ├── mods/                       共享库模块
  ├── exports/                    .pbox 归档
  └── tmp/                        临时工作区

  ~/.config/packbox/lang/         9 个语言文件

命令
────

  完整参考见第 6.2 节。

  packbox-pack      将目录打包为 CAS 块 + manifest
  packbox-install   从 manifest 安装（从 CAS 硬链接）
  packbox-run       在 bwrap 沙箱中运行（含 DNS/GUI 修复）
  packbox-list      列出已安装应用
  packbox-remove    卸载应用并释放 CAS 引用
  packbox-gc        垃圾回收孤立块
  packbox-verify    验证库兼容性（ldd）
  packbox-export    导出应用到 .pbox（zstd/xz/gzip）
  packbox-import    导入 .pbox 并验证路径穿越
  packbox-module    管理共享库模块
  packbox-diagnose  诊断环境（目录、工具、DNS、内核）

延伸阅读
────────

  第 1.3 节 — 架构（EN）
  第 1.4 节 — 安全（EN）

许可证 / 贡献
─────────────

Packbox v0.1.0 Alpha 仍在开发中。欢迎贡献，尤其是：翻译、额外的
沙箱配置文件，以及 CAS 分块策略。


───────────────────────────────────────────────────────────────────────────────
6.2 命令参考
───────────────────────────────────────────────────────────────────────────────

所有命令安装到 ~/.packbox/bin/ 并符号链接到 ~/.local/bin/。

6.2.1  packbox-pack
───────────────────

用途
  将目录树打包为 CAS 块并写入 manifest.json。

语法
  packbox-pack <目录> --name <id> [选项]

选项
  --name <id>            App ID（必需）。例如 org.mozilla.firefox
  --version <v>          版本字符串（默认 1.0.0）
  --description <文本>   人类可读的描述
  --entrypoint <路径>    tree 内的路径（例如 /app/bin/firefox）
  --mods <a,b,c>         逗号分隔的模块名
  --gui                  标记为 GUI 应用（默认 false）
  --toolkit <名称>       GTK3、GTK4、Qt5、Qt6、SDL
  --icon <路径>          tree 内的图标路径

行为
  • 使用 BLAKE3 哈希每个文件，将块存储在
    ~/.local/share/packbox/store/<xx>/<hash>。
  • 在给定目录内创建 manifest.json。
  • 如果省略 --entrypoint，选择 bin/ 中最大的可执行文件，使用
    /app/bin/<名称>。
  • 哈希时跳过 manifest.json 本身。

示例
  # Firefox 捆绑
  packbox-pack ./firefox-tree --name org.mozilla.firefox --version 128.0 \
      --description "Mozilla Firefox" --gui --toolkit GTK3

  # CLI 工具
  packbox-pack ./htop-tree --name org.packbox.htop --version 3.3.0 \
      --description "交互式进程查看器"

输出
  [ok] <路径>/manifest.json  archivos=N

退出码
  0 = 成功
  1 = 缺少参数 / 目录不存在 / 存储错误

6.2.2  packbox-install
──────────────────────

用途
  从 manifest.json 安装应用，通过硬链接从 CAS 引用块。

语法
  packbox-install <manifest.json>

行为
  • 若应用已安装，先读取旧 manifest 并删除所有 CAS 引用。
  • 创建 ~/.local/share/packbox/apps/<名称>/tree/。
  • 硬链接每个块到 tree；跨设备时回退为复制。
  • 保留原始文件模式。
  • 为每个块注册引用（<hash>.refs）用于 GC。

示例
  packbox-install ./firefox-tree/manifest.json

输出
  [install] <名称> v<版本>
  [ok] <名称> instalado  archivos=N

退出码
  0 = 成功
  1 = manifest 无效 / 存储错误

6.2.3  packbox-run
──────────────────

用途
  在 bwrap 沙箱中运行已安装应用，支持 DNS/GUI。

语法
  packbox-run <app-id> [参数...]

行为
  • 需要 PATH 中有 bubblewrap（bwrap）。
  • 将应用 tree 以只读方式挂载到 /app。
  • 只读绑定挂载 /usr、/etc、/lib、/lib64、/bin、/sbin、/var。
  • --unshare-all --share-net（允许网络，其他命名空间隔离）。
  • 清除环境变量，然后白名单：LANG、TZ、DISPLAY、WAYLAND_DISPLAY、
    XAUTHORITY、XDG_* 等。
  • DNS 修复：绑定挂载 /etc/resolv.conf、/etc/hosts、
    /etc/nsswitch.conf、/etc/hostname、/etc/gai.conf、/etc/host.conf
    —— 并解析符号链接（在 systemd-resolved 主机上很重要）。
  • GUI 支持：X11 socket、Wayland socket、D-Bus 会话 + 系统总线、
    /dev/dri、/dev/shm、fontconfig 缓存、用户主题/图标。
  • 应用数据：启发式映射（Firefox → ~/.mozilla，Chrome →
    ~/.config/google-chrome 等）。--bind-try 避免目录不存在时报错。

示例
  packbox-run org.mozilla.firefox
  packbox-run org.packbox.htop --tree
  packbox-run org.gimp.gimp --version

退出码
  0 = 成功
  1 = 应用不存在、bwrap 不存在或运行失败

6.2.4  packbox-list
───────────────────

用途
  列出已安装应用的版本和标签。

语法
  packbox-list

输出
  Apps instaladas:
  -----------------------------------------------------------
    * org.mozilla.firefox  v128.0    [GUI/GTK3]
    * org.packbox.htop     v3.3.0
    * org.gimp.gimp        v2.10.38 [GUI/GTK3] [PORTABLE]
  -----------------------------------------------------------
  Total: 3

退出码
  总是 0。

6.2.5  packbox-remove
─────────────────────

用途
  卸载应用、移除其 CAS 引用并清理桌面条目。

语法
  packbox-remove <app-id>

行为
  • 加载 manifest，为该应用移除每个块的引用。
  • 删除 ~/.local/share/packbox/apps/<app-id>/。
  • 删除 ~/.local/share/applications/packbox-<app-id>.desktop。
  • 删除 ~/.local/share/icons/hicolor/256x256/apps/packbox-<app-id>.{png,svg}。
  • 不自动运行 GC —— 使用 packbox-gc。

示例
  packbox-remove org.mozilla.firefox

退出码
  0 = 成功
  1 = 应用未安装

6.2.6  packbox-gc
─────────────────

用途
  垃圾回收孤立块（无 .refs 文件或 .refs 为空）。

语法
  packbox-gc

行为
  • 遍历 ~/.local/share/packbox/store/<xx>/。
  • 对于没有 <hash>.refs 或 refs 为空的块 → 删除块 + refs。
  • 返回数量与释放的字节数。

输出
  [gc]
  [ok] chunks=N  bytes=B

何时运行
  packbox-remove 之后，或定期运行。

退出码
  0 = 成功
  1 = 存储错误

6.2.7  packbox-verify
─────────────────────

用途
  检查已安装应用的库在主机上是否可用。

语法
  packbox-verify <app-id>

行为
  • 如果应用是 PORTABLE，立即成功。
  • 解析真实二进制（处理 launcher.sh 重定向）。
  • 运行 ldd，检查每个库是否在 /lib/x86_64-linux-gnu、/lib64、
    /usr/lib、/usr/lib64 中。
  • 报告已解析库的数量或列出缺失的。

输出（成功）
  [ok] COMPATIBLE  libs=42

输出（失败）
  [fail] faltan 3 libs
     [X] libfoo.so.1
     [X] libbar.so.2
     [X] libbaz.so.3

退出码
  0 = 兼容
  1 = 缺少库或 manifest 错误

注意
  不在打包器菜单中 —— 仅 CLI，供脚本使用。

6.2.8  packbox-export
─────────────────────

用途
  将已安装应用导出为 .pbox 归档。

语法
  packbox-export app <app-id>

行为
  • 打包（tar）整个 ~/.local/share/packbox/apps/<app-id>/ 目录。
  • 按优先级使用最佳可用工具压缩：
      1. zstd -19 -T0  （快速，最佳比率/速度）
      2. xz -9e -T0    （最慢，最佳比率）
      3. gzip          （回退）
  • 输出：~/.local/share/packbox/exports/<app-id>.pbox。

示例
  packbox-export app org.mozilla.firefox
  → ~/.local/share/packbox/exports/org.mozilla.firefox.pbox

退出码
  0 = 成功
  1 = 应用不存在

6.2.9  packbox-import
─────────────────────

用途
  导入 .pbox 归档并防止路径穿越。

语法
  packbox-import app <文件.pbox>

行为
  • 通过魔术字节检测格式：gzip (1f 8b)、zstd (28 b5 2f fd)、
    xz (fd 37 7a 58)。
  • 通过 tar reader 流式处理。
  • 对每个条目路径针对提取根（security.ValidatePath）进行验证，防止
    ../ 逃逸。
  • 如果应用已存在，警告并覆盖。
  • 提取到 ~/.local/share/packbox/apps/<名称>/。

示例
  packbox-import app ~/Downloads/org.mozilla.firefox.pbox

输出
  [import] <路径>
  [ok] importado: <名称>

退出码
  0 = 成功
  1 = 格式未知 / 缺少解压器 / 路径逃逸

安全提示
  永远不要跳过路径验证。见第 1.4 节。

6.2.10  packbox-module
──────────────────────

用途
  管理共享库模块（独立版本化的库捆绑）。

语法
  packbox-module list
  packbox-module create <二进制> <名称> <版本>
  packbox-module remove <名称> <版本>       （尚未实现）
  packbox-module info <名称> <版本>         （尚未实现）

行为（create）
  • 在 <二进制> 上运行 ldd，收集依赖。
  • 将每个库复制到 mods/<名称>/<版本>/lib/。
  • 写入 manifest.json，type: "module"。
  • 注册到 ~/.local/share/packbox/mods/<名称>/<版本>/。

示例
  packbox-module list
  packbox-module create /usr/bin/htop org.packbox.htop-libs 1.0.0

退出码
  0 = 成功
  1 = 缺少参数

6.2.11  packbox-diagnose
────────────────────────

用途
  输出环境诊断信息，用于错误报告。

语法
  packbox-diagnose

输出部分
  • 安装目录、数据目录、配置目录
  • 目录结构检查（~/.packbox/bin、~/.local/share/packbox/store 等）
  • 工具检查（bwrap、readelf、ldd、jq、zstd、xz、tar）
  • DNS 文件检查（含符号链接解析）
  • 内核、架构、Go 版本

示例
  packbox-diagnose > /tmp/packbox-diag.txt

退出码
  总是 0。

何时运行
  打开任何错误报告之前。

6.2.12  packbox-installer-v0.1.0.sh
───────────────────────────────────

用途
  交互式安装 / 卸载程序。

语法
  ./packbox-installer-v0.1.0.sh

菜单
  1  安装 Packbox
  2  卸载 Packbox
  0  退出

安装流程
  1. 检测发行版
  2. 安装依赖前确认（bubblewrap binutils jq bc curl tar）
  3. 若缺失则安装 Go 1.22+
  4. 创建 ~/.packbox/{bin,src} 和
     ~/.local/share/packbox/{store,apps,mods,exports,tmp}
  5. 生成 Go 源码（11 个命令 + 4 个内部包）
  6. 编译二进制
  7. 配置 PATH（添加到 .bashrc，符号链接到 ~/.local/bin）
  8. 验证 11 个二进制文件

卸载流程
  • 扫描将删除的内容，显示大小
  • 模式 s = 完全删除（二进制 + 应用 + 存储 + 菜单 + 配置）
  • 模式 k = 仅二进制（~/.packbox/ + 符号链接；保留应用/存储）
  • 模式 q = 取消
  • 需要输入 DELETE 确认
  • 清理 .bashrc（备份：~/.bashrc.packbox-uninstall.bak）
  • 刷新桌面和图标缓存
  • 可选删除旧版 ~/packbox/

语言
  启动时提示选择 9 种语言之一。

6.2.13  packbox-packager-v0.1.0.sh
──────────────────────────────────

用途
  打包器二进制的交互式前端。

语法
  ./packbox-packager-v0.1.0.sh

菜单
  1  打包系统应用
  2  列出已安装应用
  3  垃圾回收
  4  导出应用到文件
  5  从文件导入应用
  6  卸载应用
  0  退出

选项 1 工作流
  1. 从 .desktop 文件 + 常用二进制 + /opt/* + /usr/lib/*（在
     /usr/bin 中有符号链接）检测应用
  2. 按大小显示 Top 15（f=过滤 MB、b=搜索、r=更多、q=取消）
  3. 显示详情，询问是否打包
  4. 配置 App ID、版本、描述、模式
  5. 模式：1=普通、2=便携、3=模块、4=捆绑（推荐用于捆绑）
  6. 调用 packbox-pack → packbox-install → 可选 create_desktop_entry
  7. 可选导出为 .pbox
  8. 可选运行

双检测
  优先 ~/.packbox/bin，回退到 ~/packbox/bin（旧版）。

语言
  从 ~/.config/packbox/lang/ 读取（由安装程序安装）。

退出码约定
──────────

  0 = 成功
  1 = 错误（缺少参数、缺少资源等）

环境变量
────────

  HOME                 所有命令使用；~/.packbox、数据的基路径
  PACKBOX_LANG         installer、packager；强制语言代码
  PACKBOX_LANG_DIR     i18n；覆盖语言目录
  DISPLAY、WAYLAND_DISPLAY、XAUTHORITY、XDG_*
                       packbox-run；传递到沙箱
  LD_LIBRARY_PATH      应用内的启动器；由生成的 launcher.sh 设置


═══════════════════════════════════════════════════════════════════════════════
7. 繁體中文 (ZH-TW)
═══════════════════════════════════════════════════════════════════════════════

───────────────────────────────────────────────────────────────────────────────
7.1 README
───────────────────────────────────────────────────────────────────────────────

Packbox v0.1.0 Alpha — 繁體中文

新一代應用程式封裝系統，受 Flatpak 啟發，但採用根本不同的重用模型。

PACKBOX 的不同之處
──────────────────

  特性              Flatpak（目前）              Packbox（提議）
  ─────────────────────────────────────────────────────────────────────
  重用單元          完整執行階段（約 1 GB）      原子單元（約 5–50 MB）
  去重              檔案層級（OSTree）           區塊層級（CAS）
  程式庫共享        同一執行階段內               跨所有應用程式
  主機程式庫使用    無（完全沙箱）               選擇性（ABI 相容）
  更新              OSTree 物件增量              區塊增量 + 重排序
  每應用程式開銷    若執行階段不同則約 100%      約 5–15%（僅差異）

核心思想：Packbox 不再為每個應用程式分發一個整體執行階段，而是將每個
檔案儲存為按內容定址的區塊。兩個共享 90% 程式庫的應用程式只儲存不同
的 10%。跨應用程式的程式庫重用是自動的。

安裝
────

  git clone <repo>
  cd packbox
  ./packbox-installer-v0.1.0.sh

安裝程式將：
  1. 偵測你的發行版（Debian/Ubuntu、Fedora、Arch、openSUSE 系列）
  2. 若缺少則安裝 Go 1.22+
  3. 建立 ~/.packbox/（隱藏）包含 bin/ 和 src/
  4. 產生並編譯 11 個 Go 二進位檔
  5. 將 ~/.packbox/bin 加入 PATH
  6. 安裝語言檔到 ~/.config/packbox/lang/

安裝後：source ~/.bashrc  然後  packbox-diagnose。

快速使用
────────

  # 互動式封裝器（推薦首次使用者）
  ./packbox-packager-v0.1.0.sh

  # 或直接使用二進位檔
  packbox-pack firefox-dir/ --name org.mozilla.firefox --version 128.0 \
      --description "Web 瀏覽器" --gui --toolkit GTK3
  packbox-install firefox-dir/manifest.json
  packbox-run org.mozilla.firefox

檔案系統佈局
────────────

  ~/.packbox/                     安裝（二進位 + Go 原始碼）
  ├── bin/                        11 個 Go 二進位檔
  └── src/                        Go 模組原始碼

  ~/.local/share/packbox/         資料
  ├── store/                      CAS — 按 BLAKE3 雜湊儲存的區塊
  ├── apps/                       已安裝應用程式（tree + manifest）
  ├── mods/                       共享程式庫模組
  ├── exports/                    .pbox 封存
  └── tmp/                        暫存工作區

  ~/.config/packbox/lang/         9 個語言檔

命令
────

  完整參考見第 7.2 節。

  packbox-pack      將目錄封裝為 CAS 區塊 + manifest
  packbox-install   從 manifest 安裝（從 CAS 硬連結）
  packbox-run       在 bwrap 沙箱中執行（含 DNS/GUI 修正）
  packbox-list      列出已安裝應用程式
  packbox-remove    解除安裝並釋放 CAS 參考
  packbox-gc        垃圾回收孤立區塊
  packbox-verify    驗證程式庫相容性（ldd）
  packbox-export    匯出應用程式為 .pbox（zstd/xz/gzip）
  packbox-import    匯入 .pbox 並驗證路徑穿越
  packbox-module    管理共享程式庫模組
  packbox-diagnose  診斷環境（目錄、工具、DNS、核心）

延伸閱讀
────────

  第 1.3 節 — 架構（EN）
  第 1.4 節 — 安全（EN）

授權 / 貢獻
───────────

Packbox v0.1.0 Alpha 仍在開發中。歡迎貢獻，尤其是：翻譯、額外的
沙箱設定檔，以及 CAS 分塊策略。


───────────────────────────────────────────────────────────────────────────────
7.2 命令參考
───────────────────────────────────────────────────────────────────────────────

所有命令安裝到 ~/.packbox/bin/ 並符號連結到 ~/.local/bin/。

7.2.1  packbox-pack
───────────────────

用途
  將目錄樹封裝為 CAS 區塊並寫入 manifest.json。

語法
  packbox-pack <目錄> --name <id> [選項]

選項
  --name <id>            App ID（必要）。例如 org.mozilla.firefox
  --version <v>          版本字串（預設 1.0.0）
  --description <文字>   人類可讀的描述
  --entrypoint <路徑>    tree 內的路徑（例如 /app/bin/firefox）
  --mods <a,b,c>         逗號分隔的模組名稱
  --gui                  標記為 GUI 應用程式（預設 false）
  --toolkit <名稱>       GTK3、GTK4、Qt5、Qt6、SDL
  --icon <路徑>          tree 內的圖示路徑

行為
  • 使用 BLAKE3 雜湊每個檔案，將區塊儲存在
    ~/.local/share/packbox/store/<xx>/<hash>。
  • 在給定目錄內建立 manifest.json。
  • 若省略 --entrypoint，選擇 bin/ 中最大的可執行檔，使用
    /app/bin/<名稱>。
  • 雜湊時略過 manifest.json 本身。

範例
  packbox-pack ./firefox-tree --name org.mozilla.firefox --version 128.0 \
      --description "Mozilla Firefox" --gui --toolkit GTK3

  packbox-pack ./htop-tree --name org.packbox.htop --version 3.3.0

輸出
  [ok] <路徑>/manifest.json  archivos=N

結束碼
  0 = 成功
  1 = 缺少參數 / 目錄不存在 / 儲存錯誤

7.2.2  packbox-install
──────────────────────

用途
  從 manifest.json 安裝應用程式，透過硬連結從 CAS 引用區塊。

語法
  packbox-install <manifest.json>

行為
  • 若應用程式已安裝，先讀取舊 manifest 並刪除所有 CAS 參考。
  • 建立 ~/.local/share/packbox/apps/<名稱>/tree/。
  • 硬連結每個區塊到 tree；跨裝置時回退為複製。
  • 保留原始檔案模式。
  • 為每個區塊註冊參考（<hash>.refs）用於 GC。

範例
  packbox-install ./firefox-tree/manifest.json

輸出
  [install] <名稱> v<版本>
  [ok] <名稱> instalado  archivos=N

結束碼
  0 = 成功
  1 = manifest 無效 / 儲存錯誤

7.2.3  packbox-run
──────────────────

用途
  在 bwrap 沙箱中執行已安裝應用程式，支援 DNS/GUI。

語法
  packbox-run <app-id> [參數...]

行為
  • 需要 PATH 中有 bubblewrap（bwrap）。
  • 將應用程式 tree 以唯讀方式掛載到 /app。
  • 唯讀綁定掛載 /usr、/etc、/lib、/lib64、/bin、/sbin、/var。
  • --unshare-all --share-net（允許網路，其他命名空間隔離）。
  • 清除環境變數，然後白名單：LANG、TZ、DISPLAY、WAYLAND_DISPLAY、
    XAUTHORITY、XDG_* 等。
  • DNS 修正：綁定掛載 /etc/resolv.conf、/etc/hosts、
    /etc/nsswitch.conf、/etc/hostname、/etc/gai.conf、/etc/host.conf
    —— 並解析符號連結（在 systemd-resolved 主機上很重要）。
  • GUI 支援：X11 socket、Wayland socket、D-Bus 工作階段 + 系統匯流排、
    /dev/dri、/dev/shm、fontconfig 快取、使用者主題/圖示。
  • 應用程式資料：啟發式對應（Firefox → ~/.mozilla，Chrome →
    ~/.config/google-chrome 等）。--bind-try 避免目錄不存在時報錯。

範例
  packbox-run org.mozilla.firefox
  packbox-run org.packbox.htop --tree

結束碼
  0 = 成功
  1 = 應用程式不存在、bwrap 不存在或執行失敗

7.2.4  packbox-list
───────────────────

用途
  列出已安裝應用程式的版本和標籤。

語法
  packbox-list

輸出
  Apps instaladas:
  -----------------------------------------------------------
    * org.mozilla.firefox  v128.0    [GUI/GTK3]
    * org.packbox.htop     v3.3.0
  -----------------------------------------------------------
  Total: 2

結束碼
  總是 0。

7.2.5  packbox-remove
─────────────────────

用途
  解除安裝應用程式、移除其 CAS 參考並清理桌面項目。

語法
  packbox-remove <app-id>

行為
  • 載入 manifest，為該應用程式移除每個區塊的參考。
  • 刪除 ~/.local/share/packbox/apps/<app-id>/。
  • 刪除 ~/.local/share/applications/packbox-<app-id>.desktop。
  • 刪除相關圖示。
  • 不自動執行 GC —— 使用 packbox-gc。

範例
  packbox-remove org.mozilla.firefox

結束碼
  0 = 成功
  1 = 應用程式未安裝

7.2.6  packbox-gc
─────────────────

用途
  垃圾回收孤立區塊（無 .refs 檔案或 .refs 為空）。

語法
  packbox-gc

行為
  • 遍歷 ~/.local/share/packbox/store/<xx>/。
  • 對於沒有 <hash>.refs 或 refs 為空的區塊 → 刪除區塊 + refs。
  • 返回數量與釋放的位元組數。

輸出
  [gc]
  [ok] chunks=N  bytes=B

何時執行
  packbox-remove 之後，或定期執行。

結束碼
  0 = 成功
  1 = 儲存錯誤

7.2.7  packbox-verify
─────────────────────

用途
  檢查已安裝應用程式的程式庫在主機上是否可用。

語法
  packbox-verify <app-id>

行為
  • 如果應用程式是 PORTABLE，立即成功。
  • 解析真實二進位檔（處理 launcher.sh 重定向）。
  • 執行 ldd，檢查每個程式庫是否在 /lib/x86_64-linux-gnu、/lib64、
    /usr/lib、/usr/lib64 中。
  • 報告已解析程式庫的數量或列出缺少的。

輸出（成功）
  [ok] COMPATIBLE  libs=42

輸出（失敗）
  [fail] faltan 3 libs
     [X] libfoo.so.1

結束碼
  0 = 相容
  1 = 缺少程式庫或 manifest 錯誤

注意
  不在封裝器選單中 —— 僅 CLI，供指令碼使用。

7.2.8  packbox-export
─────────────────────

用途
  將已安裝應用程式匯出為 .pbox 封存。

語法
  packbox-export app <app-id>

行為
  • 封裝（tar）整個 ~/.local/share/packbox/apps/<app-id>/ 目錄。
  • 按優先順序使用最佳可用工具壓縮：
      1. zstd -19 -T0
      2. xz -9e -T0
      3. gzip（回退）
  • 輸出：~/.local/share/packbox/exports/<app-id>.pbox。

範例
  packbox-export app org.mozilla.firefox

結束碼
  0 = 成功
  1 = 應用程式不存在

7.2.9  packbox-import
─────────────────────

用途
  匯入 .pbox 封存並防止路徑穿越。

語法
  packbox-import app <檔案.pbox>

行為
  • 透過魔術位元組偵測格式：gzip (1f 8b)、zstd (28 b5 2f fd)、
    xz (fd 37 7a 58)。
  • 透過 tar reader 串流處理。
  • 對每個項目路徑針對提取根（security.ValidatePath）進行驗證，
    防止 ../ 逃逸。
  • 如果應用程式已存在，警告並覆寫。
  • 提取到 ~/.local/share/packbox/apps/<名稱>/。

範例
  packbox-import app ~/Downloads/org.mozilla.firefox.pbox

結束碼
  0 = 成功
  1 = 格式未知 / 缺少解壓器 / 路徑逃逸

安全提示
  永遠不要跳過路徑驗證。見第 1.4 節。

7.2.10  packbox-module
──────────────────────

用途
  管理共享程式庫模組（獨立版本化的程式庫捆綁）。

語法
  packbox-module list
  packbox-module create <二進位> <名稱> <版本>
  packbox-module remove <名稱> <版本>       （尚未實作）
  packbox-module info <名稱> <版本>         （尚未實作）

行為（create）
  • 在 <二進位> 上執行 ldd，收集相依性。
  • 將每個程式庫複製到 mods/<名稱>/<版本>/lib/。
  • 寫入 manifest.json，type: "module"。
  • 註冊到 ~/.local/share/packbox/mods/<名稱>/<版本>/。

範例
  packbox-module list
  packbox-module create /usr/bin/htop org.packbox.htop-libs 1.0.0

結束碼
  0 = 成功
  1 = 缺少參數

7.2.11  packbox-diagnose
────────────────────────

用途
  輸出環境診斷資訊，用於錯誤報告。

語法
  packbox-diagnose

輸出部分
  • 安裝目錄、資料目錄、設定目錄
  • 目錄結構檢查
  • 工具檢查（bwrap、readelf、ldd、jq、zstd、xz、tar）
  • DNS 檔案檢查（含符號連結解析）
  • 核心、架構、Go 版本

範例
  packbox-diagnose > /tmp/packbox-diag.txt

結束碼
  總是 0。

7.2.12  packbox-installer-v0.1.0.sh
───────────────────────────────────

用途
  互動式安裝 / 解除安裝程式。

語法
  ./packbox-installer-v0.1.0.sh

選單
  1  安裝 Packbox
  2  解除安裝 Packbox
  0  結束

安裝流程
  1. 偵測發行版
  2. 安裝相依性前確認（bubblewrap binutils jq bc curl tar）
  3. 若缺少則安裝 Go 1.22+
  4. 建立 ~/.packbox/{bin,src} 和
     ~/.local/share/packbox/{store,apps,mods,exports,tmp}
  5. 產生 Go 原始碼（11 個命令 + 4 個內部套件）
  6. 編譯二進位檔
  7. 設定 PATH（加入 .bashrc，符號連結到 ~/.local/bin）
  8. 驗證 11 個二進位檔

解除安裝流程
  • 掃描將刪除的內容，顯示大小
  • 模式 s = 完全刪除
  • 模式 k = 僅二進位檔（保留應用程式/儲存）
  • 模式 q = 取消
  • 需要輸入 DELETE 確認
  • 清理 .bashrc（備份：~/.bashrc.packbox-uninstall.bak）
  • 重新整理桌面和圖示快取

語言
  啟動時提示選擇 9 種語言之一。

7.2.13  packbox-packager-v0.1.0.sh
──────────────────────────────────

用途
  封裝器二進位檔的互動式前端。

語法
  ./packbox-packager-v0.1.0.sh

選單
  1  封裝系統應用程式
  2  列出已安裝應用程式
  3  垃圾回收
  4  匯出應用程式為檔案
  5  從檔案匯入應用程式
  6  解除安裝應用程式
  0  結束

選項 1 工作流程
  1. 從 .desktop 檔案 + 常用二進位檔 + /opt/* + /usr/lib/*（在
     /usr/bin 中有符號連結）偵測應用程式
  2. 按大小顯示 Top 15（f=過濾 MB、b=搜尋、r=更多、q=取消）
  3. 顯示詳情，詢問是否封裝
  4. 設定 App ID、版本、描述、模式
  5. 模式：1=一般、2=可攜、3=模組、4=捆綁
  6. 呼叫 packbox-pack → packbox-install → 可選 create_desktop_entry
  7. 可選匯出為 .pbox
  8. 可選執行

雙重偵測
  優先 ~/.packbox/bin，回退到 ~/packbox/bin（舊版）。

語言
  從 ~/.config/packbox/lang/ 讀取。

結束碼慣例
──────────

  0 = 成功
  1 = 錯誤（缺少參數、缺少資源等）

環境變數
────────

  HOME                 所有命令使用；~/.packbox、資料的基底路徑
  PACKBOX_LANG         installer、packager；強制語言代碼
  PACKBOX_LANG_DIR     i18n；覆寫語言目錄
  DISPLAY、WAYLAND_DISPLAY、XAUTHORITY、XDG_*
                       packbox-run；傳遞到沙箱
  LD_LIBRARY_PATH      應用程式內的啟動器；由產生的 launcher.sh 設定


═══════════════════════════════════════════════════════════════════════════════
8. 日本語 (JA)
═══════════════════════════════════════════════════════════════════════════════

───────────────────────────────────────────────────────────────────────────────
8.1 README
───────────────────────────────────────────────────────────────────────────────

Packbox v0.1.0 Alpha — 日本語

Flatpak にインスパイアされた次世代アプリケーションパッケージングシステム
ですが、根本的に異なる再利用モデルを持っています。

PACKBOX の違い
──────────────

  機能                 Flatpak（現在）               Packbox（提案）
  ─────────────────────────────────────────────────────────────────────
  再利用単位           完全なランタイム（約1 GB）    原子セル（約5–50 MB）
  重複排除             ファイル単位（OSTree）        チャンク単位（CAS）
  ライブラリ共有       同一ランタイム内              全アプリ間
  ホストライブラリ使用 なし（完全サンドボックス）    選択的（ABI 互換）
  更新                 OSTree オブジェクト差分       チャンク差分 + 並べ替え
  アプリごとのオーバー ランタイムが異なれば約100%   約5–15%（差分のみ）

中核となる考え方：Packbox はアプリごとにモノリシックなランタイムを配布
する代わりに、各ファイルをコンテンツアドレス指定のチャンクとして保存し
ます。ライブラリの 90% を共有する 2 つのアプリは、異なる 10% のみを保
存します。アプリ間のライブラリ再利用は自動です。

インストール
────────────

  git clone <repo>
  cd packbox
  ./packbox-installer-v0.1.0.sh

インストーラーは：
  1. ディストリビューションを検出（Debian/Ubuntu、Fedora、Arch、openSUSE）
  2. 不足していれば Go 1.22+ をインストール
  3. ~/.packbox/（隠し）に bin/ と src/ を作成
  4. 11 個の Go バイナリを生成・コンパイル
  5. ~/.packbox/bin を PATH に追加
  6. 言語ファイルを ~/.config/packbox/lang/ にインストール

インストール後：source ~/.bashrc  その後  packbox-diagnose。

クイック使用
────────────

  # 対話型パッケージャー（初回ユーザー推奨）
  ./packbox-packager-v0.1.0.sh

  # またはバイナリを直接使用
  packbox-pack firefox-dir/ --name org.mozilla.firefox --version 128.0 \
      --description "Web ブラウザ" --gui --toolkit GTK3
  packbox-install firefox-dir/manifest.json
  packbox-run org.mozilla.firefox

ファイルシステムレイアウト
──────────────────────────

  ~/.packbox/                     インストール（バイナリ + Go ソース）
  ├── bin/                        11 個の Go バイナリ
  └── src/                        Go モジュールソース

  ~/.local/share/packbox/         データ
  ├── store/                      CAS — BLAKE3 ハッシュ別のチャンク
  ├── apps/                       インストール済みアプリ（tree + manifest）
  ├── mods/                       共有ライブラリモジュール
  ├── exports/                    .pbox アーカイブ
  └── tmp/                        一時作業領域

  ~/.config/packbox/lang/         9 個の言語ファイル

コマンド
────────

  完全なリファレンスはセクション 8.2 を参照。

  packbox-pack      ディレクトリを CAS チャンク + manifest にパッケージ
  packbox-install   manifest からインストール（CAS からハードリンク）
  packbox-run       bwrap サンドボックスで実行（DNS/GUI 修正込み）
  packbox-list      インストール済みアプリを一覧表示
  packbox-remove    アンインストールして CAS 参照を解放
  packbox-gc        孤立チャンクをガベージコレクト
  packbox-verify    ライブラリ互換性を検証（ldd）
  packbox-export    アプリを .pbox にエクスポート（zstd/xz/gzip）
  packbox-import    パストラバーサル検証付きで .pbox をインポート
  packbox-module    共有ライブラリモジュールを管理
  packbox-diagnose  環境を診断（ディレクトリ、ツール、DNS、カーネル）

関連資料
────────

  セクション 1.3 — アーキテクチャ（EN）
  セクション 1.4 — セキュリティ（EN）

ライセンス / 貢献
─────────────────

Packbox v0.1.0 Alpha は開発中です。貢献を歓迎します。特に：翻訳、
追加のサンドボックスプロファイル、CAS チャンク戦略など。


───────────────────────────────────────────────────────────────────────────────
8.2 コマンドリファレンス
───────────────────────────────────────────────────────────────────────────────

すべてのコマンドは ~/.packbox/bin/ にインストールされ、~/.local/bin/ に
シンボリックリンクされます。

8.2.1  packbox-pack
───────────────────

目的
  ディレクトリツリーを CAS チャンクにパッケージし、manifest.json を
  書き出します。

構文
  packbox-pack <ディレクトリ> --name <id> [オプション]

オプション
  --name <id>            App ID（必須）。例：org.mozilla.firefox
  --version <v>          バージョン文字列（デフォルト：1.0.0）
  --description <テキスト> 人間が読める説明
  --entrypoint <パス>    tree 内のパス（例：/app/bin/firefox）
  --mods <a,b,c>         カンマ区切りのモジュール名
  --gui                  GUI アプリとしてマーク（デフォルト：false）
  --toolkit <名前>       GTK3、GTK4、Qt5、Qt6、SDL
  --icon <パス>          tree 内のアイコンパス

動作
  • BLAKE3 で各ファイルをハッシュし、チャンクを
    ~/.local/share/packbox/store/<xx>/<hash> に保存します。
  • 指定されたディレクトリ内に manifest.json を作成します。
  • --entrypoint を省略した場合、bin/ 内の最大の実行可能ファイルを
    選択し、/app/bin/<名前> を使用します。
  • ハッシュ時に manifest.json 自体をスキップします。

例
  packbox-pack ./firefox-tree --name org.mozilla.firefox --version 128.0 \
      --description "Mozilla Firefox" --gui --toolkit GTK3

  packbox-pack ./htop-tree --name org.packbox.htop --version 3.3.0

出力
  [ok] <パス>/manifest.json  archivos=N

終了コード
  0 = 成功
  1 = 引数不足 / ディレクトリが存在しない / ストアエラー

8.2.2  packbox-install
──────────────────────

目的
  manifest.json からアプリをインストールし、CAS からチャンクを
  ハードリンクします。

構文
  packbox-install <manifest.json>

動作
  • アプリが既にインストールされている場合、最初に古い manifest を
    読み込み、すべての CAS 参照を削除します。
  • ~/.local/share/packbox/apps/<名前>/tree/ を作成します。
  • 各チャンクを tree にハードリンク；クロスデバイスの場合はコピー
    にフォールバックします。
  • 元のファイルモードを保持します。
  • GC 用に各チャンクの参照（<hash>.refs）を登録します。

例
  packbox-install ./firefox-tree/manifest.json

出力
  [install] <名前> v<バージョン>
  [ok] <名前> instalado  archivos=N

終了コード
  0 = 成功
  1 = 無効な manifest / ストアエラー

8.2.3  packbox-run
──────────────────

目的
  インストール済みアプリを DNS/GUI サポート付きで bwrap サンドボックス
  内で実行します。

構文
  packbox-run <app-id> [引数...]

動作
  • PATH に bubblewrap（bwrap）が必要です。
  • アプリ tree を /app に読み取り専用でマウントします。
  • /usr、/etc、/lib、/lib64、/bin、/sbin、/var を読み取り専用で
    バインドマウントします。
  • --unshare-all --share-net（ネットワーク許可、他の名前空間は隔離）。
  • 環境変数を消去してからホワイトリスト：LANG、TZ、DISPLAY、
    WAYLAND_DISPLAY、XAUTHORITY、XDG_* など。
  • DNS 修正：/etc/resolv.conf、/etc/hosts、/etc/nsswitch.conf、
    /etc/hostname、/etc/gai.conf、/etc/host.conf をバインドマウント
    —— シンボリックリンクを解決します（systemd-resolved ホストで重要）。
  • GUI サポート：X11 ソケット、Wayland ソケット、D-Bus セッション +
    システムバス、/dev/dri、/dev/shm、fontconfig キャッシュ、ユーザー
    テーマ/アイコン。
  • アプリデータ：ヒューリスティックマップ（Firefox → ~/.mozilla、
    Chrome → ~/.config/google-chrome など）。--bind-try はディレクトリ
    が存在しない場合のエラーを回避します。

例
  packbox-run org.mozilla.firefox
  packbox-run org.packbox.htop --tree

終了コード
  0 = 成功
  1 = アプリなし、bwrap なし、または実行失敗

8.2.4  packbox-list
───────────────────

目的
  インストール済みアプリをバージョンとタグ付きで一覧表示します。

構文
  packbox-list

出力
  Apps instaladas:
  -----------------------------------------------------------
    * org.mozilla.firefox  v128.0    [GUI/GTK3]
    * org.packbox.htop     v3.3.0
  -----------------------------------------------------------
  Total: 2

終了コード
  常に 0。

8.2.5  packbox-remove
─────────────────────

目的
  アプリをアンインストールし、CAS 参照を削除し、デスクトップエントリ
  をクリーンアップします。

構文
  packbox-remove <app-id>

動作
  • manifest をロードし、このアプリの各チャンク参照を削除します。
  • ~/.local/share/packbox/apps/<app-id>/ を削除します。
  • ~/.local/share/applications/packbox-<app-id>.desktop を削除します。
  • 関連するアイコンを削除します。
  • GC を自動実行しません —— packbox-gc を使用してください。

例
  packbox-remove org.mozilla.firefox

終了コード
  0 = 成功
  1 = インストールされていない

8.2.6  packbox-gc
─────────────────

目的
  孤立したチャンク（.refs なし、または .refs が空）をガベージ
  コレクトします。

構文
  packbox-gc

動作
  • ~/.local/share/packbox/store/<xx>/ を走査します。
  • <hash>.refs がない、または refs が空の各チャンク → チャンク +
    refs を削除します。
  • 数と解放されたバイト数を返します。

出力
  [gc]
  [ok] chunks=N  bytes=B

実行タイミング
  packbox-remove の後、または定期的に。

終了コード
  0 = 成功
  1 = ストアエラー

8.2.7  packbox-verify
─────────────────────

目的
  インストール済みアプリのライブラリがホストで利用可能かどうかを
  確認します。

構文
  packbox-verify <app-id>

動作
  • アプリが PORTABLE の場合、即座に成功します。
  • 実際のバイナリを解決します（launcher.sh リダイレクトを処理）。
  • ldd を実行し、各ライブラリを /lib/x86_64-linux-gnu、/lib64、
    /usr/lib、/usr/lib64 に対してチェックします。
  • 解決されたライブラリの数、または不足しているものを報告します。

出力（成功）
  [ok] COMPATIBLE  libs=42

出力（失敗）
  [fail] faltan 3 libs
     [X] libfoo.so.1

終了コード
  0 = 互換
  1 = ライブラリ不足または manifest エラー

注意
  パッケージャーメニューには公開されていません —— CLI 専用、スクリプト用。

8.2.8  packbox-export
─────────────────────

目的
  インストール済みアプリを .pbox アーカイブにエクスポートします。

構文
  packbox-export app <app-id>

動作
  • ~/.local/share/packbox/apps/<app-id>/ ディレクトリ全体を tar します。
  • 利用可能な最良のツールで、優先順位順に圧縮します：
      1. zstd -19 -T0
      2. xz -9e -T0
      3. gzip（フォールバック）
  • 出力：~/.local/share/packbox/exports/<app-id>.pbox。

例
  packbox-export app org.mozilla.firefox

終了コード
  0 = 成功
  1 = アプリが見つからない

8.2.9  packbox-import
─────────────────────

目的
  パストラバーサル保護付きで .pbox アーカイブをインポートします。

構文
  packbox-import app <ファイル.pbox>

動作
  • マジックバイトで形式を検出：gzip (1f 8b)、zstd (28 b5 2f fd)、
    xz (fd 37 7a 58)。
  • tar リーダーを通してストリームします。
  • 各エントリパスを抽出ルート（security.ValidatePath）に対して
    検証し、../ エスケープを防ぎます。
  • アプリが既に存在する場合、警告して上書きします。
  • ~/.local/share/packbox/apps/<名前>/ に抽出します。

例
  packbox-import app ~/Downloads/org.mozilla.firefox.pbox

終了コード
  0 = 成功
  1 = 不明な形式 / 解凍ツールなし / パスエスケープ

セキュリティ注意
  パス検証を省略しないでください。セクション 1.4 を参照。

8.2.10  packbox-module
──────────────────────

目的
  共有ライブラリモジュールを管理します。

構文
  packbox-module list
  packbox-module create <バイナリ> <名前> <バージョン>
  packbox-module remove <名前> <バージョン>       （未実装）
  packbox-module info <名前> <バージョン>         （未実装）

動作（create）
  • <バイナリ> に対して ldd を実行し、依存関係を収集します。
  • 各ライブラリを mods/<名前>/<バージョン>/lib/ にコピーします。
  • type: "module" で manifest.json を書き出します。
  • ~/.local/share/packbox/mods/<名前>/<バージョン>/ に登録します。

例
  packbox-module list
  packbox-module create /usr/bin/htop org.packbox.htop-libs 1.0.0

終了コード
  0 = 成功
  1 = 引数不足

8.2.11  packbox-diagnose
────────────────────────

目的
  バグレポート用に環境診断を出力します。

構文
  packbox-diagnose

出力セクション
  • インストールディレクトリ、データディレクトリ、設定ディレクトリ
  • ディレクトリ構造チェック
  • ツールチェック（bwrap、readelf、ldd、jq、zstd、xz、tar）
  • DNS ファイルチェック（シンボリックリンク解決付き）
  • カーネル、アーキテクチャ、Go バージョン

例
  packbox-diagnose > /tmp/packbox-diag.txt

終了コード
  常に 0。

8.2.12  packbox-installer-v0.1.0.sh
───────────────────────────────────

目的
  対話型インストーラー / アンインストーラー。

構文
  ./packbox-installer-v0.1.0.sh

メニュー
  1  Packbox をインストール
  2  Packbox をアンインストール
  0  終了

インストールフロー
  1. ディストリビューションを検出
  2. 依存関係をインストールする前に確認
     （bubblewrap binutils jq bc curl tar）
  3. 不足していれば Go 1.22+ をインストール
  4. ~/.packbox/{bin,src} と
     ~/.local/share/packbox/{store,apps,mods,exports,tmp} を作成
  5. Go コードを生成（11 コマンド + 4 内部パッケージ）
  6. バイナリをコンパイル
  7. PATH を設定（.bashrc に追加、~/.local/bin にシンボリックリンク）
  8. 11 個すべてのバイナリを検証

アンインストールフロー
  • 削除されるものをスキャンし、サイズを表示
  • モード s = 完全削除
  • モード k = バイナリのみ（アプリ/ストアは保持）
  • モード q = キャンセル
  • 確認のため DELETE の入力を要求
  • .bashrc をクリーンアップ（バックアップ：~/.bashrc.packbox-uninstall.bak）
  • デスクトップとアイコンキャッシュを更新

言語
  開始時に 9 言語のいずれかを尋ねます。

8.2.13  packbox-packager-v0.1.0.sh
──────────────────────────────────

目的
  パッケージャーバイナリの対話型フロントエンド。

構文
  ./packbox-packager-v0.1.0.sh

メニュー
  1  システムアプリをパッケージ
  2  インストール済みアプリを一覧表示
  3  ガベージコレクション
  4  アプリをファイルにエクスポート
  5  ファイルからアプリをインポート
  6  アプリケーションをアンインストール
  0  終了

オプション 1 ワークフロー
  1. .desktop ファイル + 一般的なバイナリ + /opt/* + /usr/lib/*
     （/usr/bin にシンボリックリンクあり）からアプリを検出
  2. サイズ順に Top 15 を表示（f=MB フィルタ、b=検索、r=もっと、
     q=キャンセル）
  3. 詳細を表示し、パッケージ化するか尋ねる
  4. App ID、バージョン、説明、モードを設定
  5. モード：1=通常、2=ポータブル、3=モジュール、4=バンドル
  6. packbox-pack → packbox-install → オプションで create_desktop_entry
     を呼び出し
  7. オプションで .pbox にエクスポート
  8. オプションで実行

デュアル検出
  ~/.packbox/bin を優先、~/packbox/bin（レガシー）にフォールバック。

言語
  ~/.config/packbox/lang/ から読み込み。

終了コードの規約
────────────────

  0 = 成功
  1 = エラー（引数不足、リソースなしなど）

環境変数
────────

  HOME                 ~/.packbox、データの基底パス
  PACKBOX_LANG         言語コードを強制
  PACKBOX_LANG_DIR     言語ディレクトリを上書き
  DISPLAY、WAYLAND_DISPLAY、XAUTHORITY、XDG_*
                       サンドボックスに渡される
  LD_LIBRARY_PATH      アプリ内のランチャー；生成された launcher.sh が設定


═══════════════════════════════════════════════════════════════════════════════
9. 한국어 (KO)
═══════════════════════════════════════════════════════════════════════════════

───────────────────────────────────────────────────────────────────────────────
9.1 README
───────────────────────────────────────────────────────────────────────────────

Packbox v0.1.0 Alpha — 한국어

Flatpak에서 영감을 받았지만 근본적으로 다른 재사용 모델을 가진 차세대
애플리케이션 패키징 시스템입니다.

PACKBOX가 다른 점
─────────────────

  기능              Flatpak (현재)               Packbox (제안)
  ─────────────────────────────────────────────────────────────────────
  재사용 단위       전체 런타임 (약 1 GB)        원자 셀 (약 5–50 MB)
  중복 제거         파일 수준 (OSTree)           청크 수준 (CAS)
  라이브러리 공유   동일 런타임 내               모든 앱 간
  호스트 라이브러리 없음 (완전 샌드박스)         선택적 (ABI 호환)
  업데이트          OSTree 객체 델타             청크 델타 + 재정렬
  앱당 오버헤드     런타임이 다르면 약 100%      약 5–15% (차이만)

핵심 아이디어: Packbox는 앱마다 모놀리식 런타임을 배포하는 대신 각 파일을
콘텐츠 주소 지정 청크로 저장합니다. 라이브러리의 90%를 공유하는 두 앱은
차이나는 10%만 저장합니다. 앱 간 라이브러리 재사용은 자동입니다.

설치
────

  git clone <repo>
  cd packbox
  ./packbox-installer-v0.1.0.sh

설치 프로그램:
  1. 배포판 감지 (Debian/Ubuntu, Fedora, Arch, openSUSE 계열)
  2. 없으면 Go 1.22+ 설치
  3. ~/.packbox/ (숨김)에 bin/과 src/ 생성
  4. 11개의 Go 바이너리 생성 및 컴파일
  5. ~/.packbox/bin을 PATH에 추가
  6. 언어 파일을 ~/.config/packbox/lang/에 설치

설치 후: source ~/.bashrc  그리고  packbox-diagnose.

빠른 사용
─────────

  # 대화형 패키저 (초보자 권장)
  ./packbox-packager-v0.1.0.sh

  # 또는 바이너리 직접 사용
  packbox-pack firefox-dir/ --name org.mozilla.firefox --version 128.0 \
      --description "웹 브라우저" --gui --toolkit GTK3
  packbox-install firefox-dir/manifest.json
  packbox-run org.mozilla.firefox

파일 시스템 레이아웃
────────────────────

  ~/.packbox/                     설치 (바이너리 + Go 소스)
  ├── bin/                        11개 Go 바이너리
  └── src/                        Go 모듈 소스

  ~/.local/share/packbox/         데이터
  ├── store/                      CAS — BLAKE3 해시별 청크
  ├── apps/                       설치된 앱 (tree + manifest)
  ├── mods/                       공유 라이브러리 모듈
  ├── exports/                    .pbox 아카이브
  └── tmp/                        임시 작업 공간

  ~/.config/packbox/lang/         9개 언어 파일

명령어
──────

  전체 참조는 섹션 9.2를 참조하세요.

  packbox-pack      디렉터리를 CAS 청크 + manifest로 패키징
  packbox-install   manifest에서 설치 (CAS에서 하드링크)
  packbox-run       bwrap 샌드박스에서 실행 (DNS/GUI 수정 포함)
  packbox-list      설치된 앱 나열
  packbox-remove    앱 제거 및 CAS 참조 해제
  packbox-gc        고아 청크 가비지 컬렉션
  packbox-verify    라이브러리 호환성 검증 (ldd)
  packbox-export    앱을 .pbox로 내보내기 (zstd/xz/gzip)
  packbox-import    경로 탐색 검증과 함께 .pbox 가져오기
  packbox-module    공유 라이브러리 모듈 관리
  packbox-diagnose  환경 진단 (디렉터리, 도구, DNS, 커널)

추가 자료
─────────

  섹션 1.3 — 아키텍처 (EN)
  섹션 1.4 — 보안 (EN)

라이선스 / 기여
───────────────

Packbox v0.1.0 Alpha는 진행 중입니다. 기여를 환영합니다. 특히 번역,
추가 샌드박스 프로파일, CAS 청킹 전략 등을 환영합니다.


───────────────────────────────────────────────────────────────────────────────
9.2 명령어 참조
───────────────────────────────────────────────────────────────────────────────

모든 명령은 ~/.packbox/bin/에 설치되고 ~/.local/bin/에 심볼릭 링크됩니다.

9.2.1  packbox-pack
───────────────────

목적
  디렉터리 트리를 CAS 청크로 패키징하고 manifest.json을 작성합니다.

구문
  packbox-pack <디렉터리> --name <id> [옵션]

옵션
  --name <id>            App ID (필수). 예: org.mozilla.firefox
  --version <v>          버전 문자열 (기본값: 1.0.0)
  --description <텍스트> 사람이 읽을 수 있는 설명
  --entrypoint <경로>    tree 내부 경로 (예: /app/bin/firefox)
  --mods <a,b,c>         쉼표로 구분된 모듈 이름
  --gui                  GUI 앱으로 표시 (기본값: false)
  --toolkit <이름>       GTK3, GTK4, Qt5, Qt6, SDL
  --icon <경로>          tree 내부 아이콘 경로

동작
  • BLAKE3로 각 파일을 해싱하고 청크를
    ~/.local/share/packbox/store/<xx>/<hash>에 저장합니다.
  • 주어진 디렉터리 내에 manifest.json을 생성합니다.
  • --entrypoint를 생략하면 bin/에서 가장 큰 실행 파일을 선택하고
    /app/bin/<이름>을 사용합니다.
  • 해싱 중 manifest.json 자체를 건너뜁니다.

예제
  packbox-pack ./firefox-tree --name org.mozilla.firefox --version 128.0 \
      --description "Mozilla Firefox" --gui --toolkit GTK3

  packbox-pack ./htop-tree --name org.packbox.htop --version 3.3.0

출력
  [ok] <경로>/manifest.json  archivos=N

종료 코드
  0 = 성공
  1 = 인수 누락 / 디렉터리 없음 / 스토어 오류

9.2.2  packbox-install
──────────────────────

목적
  manifest.json에서 앱을 설치하고 CAS에서 청크를 하드링크합니다.

구문
  packbox-install <manifest.json>

동작
  • 앱이 이미 설치되어 있으면 먼저 이전 manifest를 읽고 모든 CAS
    참조를 제거합니다.
  • ~/.local/share/packbox/apps/<이름>/tree/를 생성합니다.
  • 각 청크를 tree에 하드링크; 크로스 디바이스면 복사로 폴백합니다.
  • 원본 파일 모드를 유지합니다.
  • GC를 위해 각 청크당 참조(<hash>.refs)를 등록합니다.

예제
  packbox-install ./firefox-tree/manifest.json

출력
  [install] <이름> v<버전>
  [ok] <이름> instalado  archivos=N

종료 코드
  0 = 성공
  1 = 잘못된 manifest / 스토어 오류

9.2.3  packbox-run
──────────────────

목적
  DNS/GUI 지원으로 bwrap 샌드박스에서 설치된 앱을 실행합니다.

구문
  packbox-run <app-id> [인수...]

동작
  • PATH에 bubblewrap(bwrap)이 필요합니다.
  • 앱 tree를 /app에 읽기 전용으로 마운트합니다.
  • /usr, /etc, /lib, /lib64, /bin, /sbin, /var를 읽기 전용으로
    바인드 마운트합니다.
  • --unshare-all --share-net (네트워크 허용, 다른 네임스페이스 격리).
  • 환경을 정리한 후 화이트리스트: LANG, TZ, DISPLAY, WAYLAND_DISPLAY,
    XAUTHORITY, XDG_* 등.
  • DNS 수정: /etc/resolv.conf, /etc/hosts, /etc/nsswitch.conf,
    /etc/hostname, /etc/gai.conf, /etc/host.conf를 바인드 마운트
    —— 심볼릭 링크를 해석합니다 (systemd-resolved 호스트에서 중요).
  • GUI 지원: X11 소켓, Wayland 소켓, D-Bus 세션 + 시스템 버스,
    /dev/dri, /dev/shm, fontconfig 캐시, 사용자 테마/아이콘.
  • 앱 데이터: 휴리스틱 맵 (Firefox → ~/.mozilla, Chrome →
    ~/.config/google-chrome 등). --bind-try는 디렉터리가 없어도 오류를
    방지합니다.

예제
  packbox-run org.mozilla.firefox
  packbox-run org.packbox.htop --tree

종료 코드
  0 = 성공
  1 = 앱 없음, bwrap 없음 또는 실행 실패

9.2.4  packbox-list
───────────────────

목적
  설치된 앱을 버전과 태그와 함께 나열합니다.

구문
  packbox-list

출력
  Apps instaladas:
  -----------------------------------------------------------
    * org.mozilla.firefox  v128.0    [GUI/GTK3]
    * org.packbox.htop     v3.3.0
  -----------------------------------------------------------
  Total: 2

종료 코드
  항상 0.

9.2.5  packbox-remove
─────────────────────

목적
  앱을 제거하고 CAS 참조를 제거하며 데스크톱 항목을 정리합니다.

구문
  packbox-remove <app-id>

동작
  • manifest를 로드하고 이 앱의 각 청크 참조를 제거합니다.
  • ~/.local/share/packbox/apps/<app-id>/를 삭제합니다.
  • ~/.local/share/applications/packbox-<app-id>.desktop을 삭제합니다.
  • 관련 아이콘을 삭제합니다.
  • GC를 자동으로 실행하지 않습니다 —— packbox-gc를 사용하세요.

예제
  packbox-remove org.mozilla.firefox

종료 코드
  0 = 성공
  1 = 설치되지 않음

9.2.6  packbox-gc
─────────────────

목적
  고아 청크(.refs 없음 또는 빈 .refs)를 가비지 컬렉트합니다.

구문
  packbox-gc

동작
  • ~/.local/share/packbox/store/<xx>/를 순회합니다.
  • <hash>.refs가 없거나 refs가 비어 있는 각 청크 → 청크 + refs를
    삭제합니다.
  • 개수와 해제된 바이트 수를 반환합니다.

출력
  [gc]
  [ok] chunks=N  bytes=B

실행 시기
  packbox-remove 후 또는 주기적으로.

종료 코드
  0 = 성공
  1 = 스토어 오류

9.2.7  packbox-verify
─────────────────────

목적
  설치된 앱의 라이브러리가 호스트에서 사용 가능한지 확인합니다.

구문
  packbox-verify <app-id>

동작
  • 앱이 PORTABLE이면 즉시 성공합니다.
  • 실제 바이너리를 해석합니다 (launcher.sh 리디렉션 처리).
  • ldd를 실행하고 각 라이브러리를 /lib/x86_64-linux-gnu, /lib64,
    /usr/lib, /usr/lib64에 대해 확인합니다.
  • 해석된 라이브러리 수를 보고하거나 누락된 것을 나열합니다.

출력 (성공)
  [ok] COMPATIBLE  libs=42

출력 (실패)
  [fail] faltan 3 libs
     [X] libfoo.so.1

종료 코드
  0 = 호환
  1 = 라이브러리 누락 또는 manifest 오류

참고
  패키저 메뉴에 노출되지 않음 —— CLI 전용, 스크립팅용.

9.2.8  packbox-export
─────────────────────

목적
  설치된 앱을 .pbox 아카이브로 내보냅니다.

구문
  packbox-export app <app-id>

동작
  • 전체 ~/.local/share/packbox/apps/<app-id>/ 디렉터리를 tar합니다.
  • 사용 가능한 최선의 도구로 우선순위에 따라 압축합니다:
      1. zstd -19 -T0
      2. xz -9e -T0
      3. gzip (폴백)
  • 출력: ~/.local/share/packbox/exports/<app-id>.pbox.

예제
  packbox-export app org.mozilla.firefox

종료 코드
  0 = 성공
  1 = 앱을 찾을 수 없음

9.2.9  packbox-import
─────────────────────

목적
  경로 탐색 보호와 함께 .pbox 아카이브를 가져옵니다.

구문
  packbox-import app <파일.pbox>

동작
  • 매직 바이트로 형식을 감지: gzip (1f 8b), zstd (28 b5 2f fd),
    xz (fd 37 7a 58).
  • tar 리더를 통해 스트림합니다.
  • 각 항목 경로를 추출 루트(security.ValidatePath)에 대해 검증하여
    ../ 이스케이프를 방지합니다.
  • 앱이 이미 존재하면 경고하고 덮어씁니다.
  • ~/.local/share/packbox/apps/<이름>/에 추출합니다.

예제
  packbox-import app ~/Downloads/org.mozilla.firefox.pbox

종료 코드
  0 = 성공
  1 = 알 수 없는 형식 / 압축 해제기 누락 / 경로 이스케이프

보안 참고
  경로 검증을 절대 건너뛰지 마세요. 섹션 1.4를 참조하세요.

9.2.10  packbox-module
──────────────────────

목적
  공유 라이브러리 모듈을 관리합니다.

구문
  packbox-module list
  packbox-module create <바이너리> <이름> <버전>
  packbox-module remove <이름> <버전>       (아직 구현되지 않음)
  packbox-module info <이름> <버전>         (아직 구현되지 않음)

동작 (create)
  • <바이너리>에 대해 ldd를 실행하고 종속성을 수집합니다.
  • 각 라이브러리를 mods/<이름>/<버전>/lib/에 복사합니다.
  • type: "module"로 manifest.json을 작성합니다.
  • ~/.local/share/packbox/mods/<이름>/<버전>/에 등록합니다.

예제
  packbox-module list
  packbox-module create /usr/bin/htop org.packbox.htop-libs 1.0.0

종료 코드
  0 = 성공
  1 = 인수 누락

9.2.11  packbox-diagnose
────────────────────────

목적
  버그 보고를 위한 환경 진단을 출력합니다.

구문
  packbox-diagnose

출력 섹션
  • 설치 디렉터리, 데이터 디렉터리, 설정 디렉터리
  • 디렉터리 구조 확인
  • 도구 확인 (bwrap, readelf, ldd, jq, zstd, xz, tar)
  • DNS 파일 확인 (심볼릭 링크 해석 포함)
  • 커널, 아키텍처, Go 버전

예제
  packbox-diagnose > /tmp/packbox-diag.txt

종료 코드
  항상 0.

9.2.12  packbox-installer-v0.1.0.sh
───────────────────────────────────

목적
  대화형 설치 / 제거 프로그램.

구문
  ./packbox-installer-v0.1.0.sh

메뉴
  1  Packbox 설치
  2  Packbox 제거
  0  종료

설치 흐름
  1. 배포판 감지
  2. 종속성 설치 전 확인 (bubblewrap binutils jq bc curl tar)
  3. 없으면 Go 1.22+ 설치
  4. ~/.packbox/{bin,src} 및
     ~/.local/share/packbox/{store,apps,mods,exports,tmp} 생성
  5. Go 코드 생성 (11개 명령 + 4개 내부 패키지)
  6. 바이너리 컴파일
  7. PATH 구성 (.bashrc에 추가, ~/.local/bin에 심볼릭 링크)
  8. 11개 바이너리 모두 검증

제거 흐름
  • 제거될 항목을 스캔하고 크기를 표시
  • 모드 s = 완전 제거
  • 모드 k = 바이너리만 (앱/스토어 유지)
  • 모드 q = 취소
  • 확인을 위해 DELETE 입력 요구
  • .bashrc 정리 (백업: ~/.bashrc.packbox-uninstall.bak)
  • 데스크톱 및 아이콘 캐시 새로고침

언어
  시작 시 9개 언어 중 하나를 묻습니다.

9.2.13  packbox-packager-v0.1.0.sh
──────────────────────────────────

목적
  패키저 바이너리의 대화형 프런트엔드.

구문
  ./packbox-packager-v0.1.0.sh

메뉴
  1  시스템 앱 패키징
  2  설치된 앱 나열
  3  가비지 컬렉션
  4  앱을 파일로 내보내기
  5  파일에서 앱 가져오기
  6  애플리케이션 제거
  0  종료

옵션 1 워크플로
  1. .desktop 파일 + 일반 바이너리 + /opt/* + /usr/lib/*
     (/usr/bin에 심볼릭 링크 있음)에서 앱을 감지
  2. 크기순 Top 15 표시 (f=MB 필터, b=검색, r=더보기, q=취소)
  3. 세부 정보를 표시하고 패키징할지 묻기
  4. App ID, 버전, 설명, 모드 구성
  5. 모드: 1=일반, 2=포터블, 3=모듈, 4=번들
  6. packbox-pack → packbox-install → 선택적으로 create_desktop_entry
     호출
  7. 선택적으로 .pbox로 내보내기
  8. 선택적으로 실행

이중 감지
  ~/.packbox/bin 선호, ~/packbox/bin(레거시)으로 폴백.

언어
  ~/.config/packbox/lang/에서 읽음.

종료 코드 규약
──────────────

  0 = 성공
  1 = 오류 (인수 누락, 리소스 없음 등)

환경 변수
─────────

  HOME                 ~/.packbox, 데이터의 기본 경로
  PACKBOX_LANG         언어 코드 강제
  PACKBOX_LANG_DIR     언어 디렉터리 재정의
  DISPLAY, WAYLAND_DISPLAY, XAUTHORITY, XDG_*
                       샌드박스로 전달됨
  LD_LIBRARY_PATH      앱 내부 런처; 생성된 launcher.sh가 설정


═══════════════════════════════════════════════════════════════════════════════
FIN DEL DOCUMENTO / END OF DOCUMENT
═══════════════════════════════════════════════════════════════════════════════
