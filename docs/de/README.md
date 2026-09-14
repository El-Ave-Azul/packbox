[English](../../README.md) · [Español](../../README.es.md) · [Français](../fr/README.md) · **Deutsch** · [Italiano](../it/README.md) · [简体中文](../zh-CN/README.md) · [繁體中文](../zh-TW/README.md) · [日本語](../ja/README.md) · [한국어](../ko/README.md)

---

![Lizenz: MIT](https://img.shields.io/badge/Lizenz-MIT-yellow.svg)
![Plattform: Linux](https://img.shields.io/badge/Plattform-Linux-blue)
![Version](https://img.shields.io/badge/version-0.1.0--alpha-orange)
![Go](https://img.shields.io/badge/Go-1.22+-00ADD8?logo=go&logoColor=white)
![i18n](https://img.shields.io/badge/i18n-9_Sprachen-green)
![Status](https://img.shields.io/badge/Status-alpha-red)

# Packbox

**Ein Anwendungspaketierungssystem der nächsten Generation für Linux.**
Inspiriert von Flatpak, aber mit einem grundlegend anderen
Wiederverwendungsmodell: Statt eine monolithische Runtime pro App zu
verteilen, speichert Packbox jede Datei als inhaltsadressierte Chunks
(BLAKE3 CAS). Zwei Apps, die 90 % ihrer Bibliotheken teilen, speichern nur
die abweichenden 10 %.

> [!NOTE]
> **Packbox ist in Alpha (v0.1.0).** Die Kern-Workflows funktionieren, aber
> es gibt noch keine Signaturprüfung für `.pbox`-Archive, und die Sandbox ist
> absichtlich permissiver als Flatpak. Nutze es zuerst auf unkritischen
> Systemen.

---

## Inhaltsverzeichnis

- [Warum Packbox](#warum-packbox)
- [Vergleich mit Flatpak](#vergleich-mit-flatpak)
- [Voraussetzungen](#voraussetzungen)
- [Installation](#installation)
- [Schnellstart](#schnellstart)
- [Befehle](#befehle)
- [Verzeichnisstruktur](#verzeichnisstruktur)
- [Architektur](#architektur)
- [Sicherheit](#sicherheit)
- [Roadmap](#roadmap)
- [Dokumentation](#dokumentation)
- [Mitwirken](#mitwirken)
- [Lizenz](#lizenz)
- [Danksagungen](#danksagungen)

---

## Warum Packbox

Flatpak hat ein echtes Problem gelöst: sandboxed, portable Linux-Apps. Aber
sein Wiederverwendungsmodell ist grob. Jede App liefert (oder referenziert)
eine vollständige Runtime, die **~1 GB** groß sein kann. Wenn zwei Apps
unterschiedliche Runtimes nutzen, zahlst du zweimal — selbst wenn sie 95 %
ihrer Bibliotheken teilen.

Packbox zielt auf genau diese Lücke:

- **Deduplizierung auf Chunk-Ebene.** Dateien werden aufgeteilt, mit BLAKE3
  gehasht und als Chunks gespeichert. Identische Chunks (eine
  `libfoo.so.3.2.1`, eine Schriftart, ein Übersetzungskatalog) werden über
  alle Apps des Systems geteilt.
- **App-übergreifendes Library-Sharing.** Zwei Apps, die dieselbe
  `libQt6Core.so` nutzen, halten nur eine Kopie auf der Platte, unabhängig
  von ihrer "Runtime".
- **Selektive Nutzung von Host-Libraries.** Apps können erklären, welchen
  Host-Bibliotheken sie vertrauen (über `host_contract.delegate`), statt
  alles zu bündeln.
- **Kleiner Footprint pro App.** In der Praxis kostet das Hinzufügen einer
  neuen App auf einem bestehenden Set ~5–15 % ihrer Größe, nicht ~100 %.

Packbox versucht **nicht**, Flatpak zu ersetzen. Es erkundet eine andere
Nische: Apps, die nicht sauber in eine Runtime passen, oder wo 1 GB für ein
50-MB-Tool übertrieben ist.

---

## Vergleich mit Flatpak

| Merkmal                  | Flatpak (aktuell)                | Packbox (vorgeschlagen)         |
|--------------------------|----------------------------------|---------------------------------|
| Wiederverwendungseinheit | Vollständige Runtime (~1 GB)     | Atomare Zelle (~5–50 MB)        |
| Deduplizierung           | Datei-Ebene (OSTree)             | Chunk-Ebene (BLAKE3 CAS)        |
| Library-Sharing          | Innerhalb derselben Runtime      | Über alle Apps hinweg           |
| Host-Lib-Nutzung         | Keine (vollständige Sandbox)     | Selektiv (ABI-kompatibel)       |
| Updates                  | OSTree-Objekt-Delta              | Chunk-Delta + Neuanordnung      |
| Overhead pro App         | ~100 % bei anderer Runtime       | ~5–15 % (nur Unterschiede)      |

---

## Voraussetzungen

- **Linux** (getestet auf Debian 12, Fedora 40, Arch aktuell)
- **Bash 4+**
- **Go 1.22+** (wird bei Bedarf automatisch installiert)
- **bubblewrap** (`bwrap`) — automatisch installiert
- **binutils** (`ldd`, `readelf`) — automatisch installiert
- **Kompressionswerkzeuge**: `zstd`, `xz`, `gzip` (mindestens eines)
- **~500 MB freier Speicher** für den Build + Toolchain

Unterstützte Distributionen: **Debian/Ubuntu/Mint/Pop**,
**Fedora/RHEL/Rocky**, **Arch/Manjaro/EndeavourOS**, **openSUSE**.

---

## Installation

```bash
git clone https://github.com/El-Ave-Azul/packbox.git
cd packbox
./packbox-installer-v0.1.0.sh
source ~/.bashrc
packbox-diagnose
```

Der Installer ist interaktiv und:

1. Erkennt deine Distribution und den Paketmanager.
2. Fragt vor der Installation der Abhängigkeiten
   (`bubblewrap binutils jq bc curl tar`).
3. Installiert Go 1.22+, falls nicht vorhanden.
4. Erstellt `~/.packbox/{bin,src}` und
   `~/.local/share/packbox/{store,apps,mods,exports,tmp}`.
5. Generiert 11 Go-Binärdateien + interne Pakete aus lokalem Quellcode.
6. Kompiliert alles (~2–3 Minuten auf moderner Hardware).
7. Fügt `~/.packbox/bin` zum `PATH` hinzu und legt Symlinks in
   `~/.local/bin` an.
8. Verifiziert, dass alle 11 Binärdateien vorhanden sind.

**Sprachen**: Der Installer fragt zu Beginn nach einer von 9 Sprachen —
English, Español, Français, Deutsch, Italiano, 简体中文, 繁體中文, 日本語,
한국어.

### Deinstallation

Führe dasselbe Skript aus und wähle Option `2`:

- Modus `s` → vollständige Entfernung (Binärdateien + Apps + Store + Menüs + Config)
- Modus `k` → nur Binärdateien (Apps und Store bleiben)
- Modus `q` → abbrechen

Erfordert die Eingabe von `DELETE` zur Bestätigung.

---

## Schnellstart

### Interaktiver Packager (empfohlen)

```bash
./packbox-packager-v0.1.0.sh
```

Menü: packen, auflisten, gc, exportieren, importieren, deinstallieren.

### Kommandozeile

```bash
# 1. Ein Verzeichnis in CAS-Chunks + manifest.json packen
packbox-pack ./firefox-tree \
    --name org.mozilla.firefox \
    --version 128.0 \
    --description "Mozilla Firefox" \
    --gui --toolkit GTK3

# 2. Aus dem generierten Manifest installieren
packbox-install ./firefox-tree/manifest.json

# 3. In einer bwrap-Sandbox ausführen (DNS + GUI fix angewendet)
packbox-run org.mozilla.firefox

# 4. Anzeigen, was installiert ist
packbox-list

# 5. Deinstallieren und Chunks freigeben
packbox-remove org.mozilla.firefox
packbox-gc
```

---

## Befehle

Elf Go-Binärdateien, alle unter `~/.packbox/bin/`:

| Befehl              | Zweck                                                       |
|---------------------|-------------------------------------------------------------|
| `packbox-pack`      | Verzeichnis in CAS-Chunks + `manifest.json` hashen          |
| `packbox-install`   | Aus Manifest installieren (Hardlink aus CAS)                |
| `packbox-run`       | In `bwrap` ausführen mit DNS + GUI                          |
| `packbox-list`      | Installierte Apps mit Version und Tags auflisten            |
| `packbox-remove`    | App deinstallieren und CAS-Referenzen freigeben             |
| `packbox-gc`        | Verwaiste Chunks aufräumen                                  |
| `packbox-verify`    | `ldd`-basierte Library-Kompatibilitätsprüfung               |
| `packbox-export`    | App nach `.pbox` exportieren (zstd/xz/gzip)                 |
| `packbox-import`    | `.pbox` mit Path-Traversal-Schutz importieren               |
| `packbox-module`    | Shared-Library-Module verwalten (`list`, `create`)          |
| `packbox-diagnose`  | Umgebungsbericht für Bug-Reports ausgeben                   |

Vollständige Referenz mit Optionen, Exit-Codes und Beispielen:
[`commands.md`](commands.md) · [EN](../en/commands.md) · [ES](../es/commands.md)

### Interaktive Skripte

- `packbox-installer-v0.1.0.sh` — installieren / deinstallieren
- `packbox-packager-v0.1.0.sh` — packen, auflisten, gc, exportieren, importieren, deinstallieren
- `packbox-i18n.sh` — gemeinsame Übersetzungsschicht

---

## Verzeichnisstruktur

```
~/.packbox/                     # Installation (Binärdateien + Go-Quellcode)
├── bin/                        # 11 Go-Binärdateien
└── src/                        # Go-Modul-Quellcode

~/.local/share/packbox/         # Daten
├── store/                      # CAS — Chunks nach BLAKE3-Hash
│   └── <ab>/<voller-hash>      # plus .refs-Datei pro Chunk
├── apps/                       # Installierte Apps (tree + manifest.json)
├── mods/                       # Shared-Library-Module
├── exports/                    # .pbox-Archive
└── tmp/                        # Temporärer Arbeitsbereich

~/.config/packbox/lang/         # 9 Sprachdateien
```

---

## Architektur

Drei bewegliche Teile:

```
┌──────────────┐   pack    ┌──────────────┐   install   ┌──────────────┐
│  Quellverz.  │ ────────► │     CAS      │ ──────────► │  App-Tree    │
│  (FS-Tree)   │           │  (Chunks)    │             │ (Hardlinks)  │
└──────────────┘           └──────────────┘             └──────────────┘
                                  │
                                  │ run
                                  ▼
                         ┌──────────────────┐
                         │  bwrap-Sandbox   │
                         │  (DNS/GUI-Fix)   │
                         └──────────────────┘
```

- **CAS** — `~/.local/share/packbox/store/`, BLAKE3-Hashes, eine
  `.refs`-Datei pro Chunk, `SafeLink` (Hardlink → Copy-Fallback) bei der
  Installation.
- **Manifest** — `schema_version: "1.5"`, `layers.app.files` mappt relative
  Pfade auf `{chunks, size, mode}`, plus `host_contract.delegate` für
  Host-Library-Vertrauen.
- **Sandbox** — `bwrap --unshare-all --share-net`, Env-Whitelist nach
  `--clearenv`, DNS-Symlink-Auflösung (`EvalSymlinks`) vor dem Binden von
  `/etc/resolv.conf`, GUI-Support (X11, Wayland, D-Bus, `/dev/dri`,
  fontconfig-Cache), heuristische Daten-Map pro App mit `--bind-try`.

Vollständige Architektur (CAS-Internals, Manifest-Schema, Sandbox-Mounts,
Host-Contract): [`architecture.md`](../en/architecture.md) ·
[ES](../es/architecture.md)

---

## Sicherheit

> [!WARNING]
> `.pbox`-Archive sind in v0.1.0 Alpha **nicht signiert**. Behandle jedes
> importierte Archiv als nicht vertrauenswürdig. Signaturprüfung steht auf
> der Roadmap.

Bereits implementierte Maßnahmen:

- **Path-Traversal-Schutz** — `cas.isValidHash()` erzwingt 64 Hex-Zeichen
  in Kleinschreibung. Der `.pbox`-Import validiert jeden Tar-Eintrag gegen
  die Extraktionswurzel via `security.ValidatePath`.
- **Symlink-sicherer Import** — nur `tar.TypeDir` und `tar.TypeReg` werden
  behandelt; Symlinks, Hardlinks und Gerätedateien werden stillschweigend
  übersprungen.
- **Environment-Bereinigung** — `--clearenv` gefolgt von einer expliziten
  Whitelist blockiert `LD_PRELOAD`- / `LD_LIBRARY_PATH`-Injektion.
- **XAUTHORITY-Isolation** — das Host-`~/.Xauthority` wird in eine
  prozess-eigene Temp-Datei (`/tmp/packbox-xauth-<pid>`, Modus 0600)
  kopiert, bevor sie in die Sandbox gebunden wird.
- **Reference Counting** — jeder Chunk hat eine `.refs`-Datei;
  `packbox-gc` löscht nur unreferenzierte Chunks.
- **Kein setuid, kein root** — Packbox läuft vollständig als der
  aufrufende Nutzer. `sudo` wird nur vom Installer verwendet.

Bekannte Einschränkungen und Threat-Model:
[`security.md`](../en/security.md) · [ES](../es/security.md)

Melde Schwachstellen mit der Ausgabe von `packbox-diagnose`. Für sensible
Funde nutze den privaten Security-Kontakt.

---

## Roadmap

### v0.1.x — Stabilisierung
- [ ] Signaturprüfung für `.pbox`-Archive
- [ ] Netzwerk-Policy pro App (`--share-net` ist derzeit global)
- [ ] `packbox-module remove` und `info` implementieren
- [ ] `host_contract.delegate` gegen echte GTK4/Qt6-Apps testen
- [ ] CI: `shellcheck`, `gofmt`, `go vet` bei jedem PR
- [ ] Test-Matrix: Debian 12, Fedora 40, Arch, openSUSE Tumbleweed

### v0.2 — Reichweite
- [ ] Vorcompilierte Binärdateien für x86_64 und aarch64 (Releases-Seite)
- [ ] `packbox-update` für In-Place-Updates
- [ ] GUI-Frontend (optional, GTK4)
- [ ] Chunk-Level-Delta-Downloads für `packbox-export`

### Später
- [ ] Flatpak-Runtime-Importer (Best-Effort)
- [ ] Signaturprüfung via minisign oder sigstore
- [ ] WASM-basierte Sandbox-Stufe für nicht vertrauenswürdige Plugins

---

## Dokumentation

Vollständige Doku in 9 Sprachen. Englisch und Spanisch haben das komplette
Set (README + Befehle + Architektur + Sicherheit); die anderen sieben haben
README + Befehle.

| Sprache  | README                                 | Befehle                                         | Architektur                                         | Sicherheit                                    |
|----------|----------------------------------------|-------------------------------------------------|-----------------------------------------------------|-----------------------------------------------|
| English  | [en](../en/README.md)                  | [en](../en/commands.md)                         | [en](../en/architecture.md)                         | [en](../en/security.md)                       |
| Español  | [es](../es/README.md)                  | [es](../es/commands.md)                         | [es](../es/architecture.md)                         | [es](../es/security.md)                       |
| Français | [fr](../fr/README.md)                  | [fr](../fr/commands.md)                         | —                                                   | —                                             |
| Deutsch  | **de**                                 | [de](commands.md)                               | —                                                   | —                                             |
| Italiano | [it](../it/README.md)                  | [it](../it/commands.md)                         | —                                                   | —                                             |
| 简体中文 | [zh-CN](../zh-CN/README.md)            | [zh-CN](../zh-CN/commands.md)                   | —                                                   | —                                             |
| 繁體中文 | [zh-TW](../zh-TW/README.md)            | [zh-TW](../zh-TW/commands.md)                   | —                                                   | —                                             |
| 日本語   | [ja](../ja/README.md)                  | [ja](../ja/commands.md)                         | —                                                   | —                                             |
| 한국어   | [ko](../ko/README.md)                  | [ko](../ko/commands.md)                         | —                                                   | —                                             |

Index: [`docs/README.md`](../README.md)

---

## Mitwirken

Beiträge willkommen, insbesondere:

- **Übersetzungen** — füge eine Locale zu `packbox-i18n.sh` hinzu, indem du
  den `en`-Block in `install_lang_files()` kopierst und jeden `L_*`-Schlüssel
  übersetzt.
- **Sandbox-Profile** — Daten-Maps pro App für Browser, IDEs, Spiele.
- **CAS-Chunking-Strategien** — Rolling-Hash-Varianten, paralleles Chunking.
- **Bug-Reports** — immer mit `packbox-diagnose`-Ausgabe.

Erste Schritte:

```bash
git clone https://github.com/TU_USUARIO/packbox.git
cd packbox
# Lies CONTRIBUTING.md für die vollständigen Richtlinien
```

- 🐛 [Issue öffnen](https://github.com/TU_USUARIO/packbox/issues)
- 💬 [Diskussion starten](https://github.com/TU_USUARIO/packbox/discussions)
- 🔧 [CONTRIBUTING.md](../../CONTRIBUTING.md)

Bitte führe `shellcheck` über die Shell-Skripte und `gofmt` + `go vet` über
den Go-Code aus, bevor du einen PR einreichst.

---

## Lizenz

[MIT](../../LICENSE) © 2025 TU_NOMBRE

Packbox ist frei zu nutzen, zu ändern und weiterzugeben. Siehe
[LICENSE](../../LICENSE) für Details.

---

## Danksagungen

- **[bubblewrap](https://github.com/containers/bubblewrap)** — die
  Sandbox-Primitive, die `packbox-run` möglich macht.
- **[BLAKE3](https://github.com/BLAKE3-team/BLAKE3)** — schnelles, sicheres
  Content-Addressing.
- **[Flatpak](https://flatpak.org/)** — das Projekt, das bewiesen hat, dass
  sandboxed Linux-Apps im großen Maßstab funktionieren, und dessen
  Design-Entscheidungen viele unserer geprägt haben (auch dort, wo wir
  abweichen).
- Die 9-Sprachen-i18n-Schicht existiert, weil die Linux-Community global
  ist; danke an alle, die die Übersetzungen geprüft haben.
