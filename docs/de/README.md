# Packbox

**[Español](../../README.md)** · [English](../en/README.md) · [Français](../fr/README.md) · **[Deutsch](README.md)** · [Italiano](../it/README.md) · [Português](../pt/README.md) · [中文](../zh/README.md) · [日本語](../ja/README.md) · [한국어](../ko/README.md)

---

![CI](https://github.com/El-Ave-Azul/packbox/actions/workflows/ci.yml/badge.svg)
![Lizenz](https://img.shields.io/badge/Lizenz-Apache_2.0-blue.svg)
![Version](https://img.shields.io/badge/Version-0.3.0-orange.svg)
![Plattform](https://img.shields.io/badge/Plattform-Linux-blue.svg)
![Go](https://img.shields.io/badge/Go-1.22+-00ADD8.svg?logo=go&logoColor=white)
![i18n](https://img.shields.io/badge/i18n-9_Sprachen-green.svg)
![Status](https://img.shields.io/badge/Status-Beta-blue.svg)

**Linux-Anwendungspackager mit binärer Deduplizierung pro Chunk und Zstd-komprimiertem `.pbox`-Export.**
Inspiriert von Flatpak, aber mit einem anderen Wiederverwendungsmodell: statt einer
monolithischen Runtime pro App speichert Packbox den Inhalt in einem
inhaltsadressierten Speicher (BLAKE3 CAS), mit optimiertem **inhaltsdefiniertem Chunking
(CDC)** und wiederverwendbaren **Zellen**. Zwei Apps, die 90 % ihrer
Bibliotheken teilen, speichern nur die 10 %, die abweichen.

> [!IMPORTANT]
> **Beta-Status (v0.3.0).** Das System hat die Kernstabilität verbessert und dabei LRU-Garbage-Collection und Zstd-Komprimierung beim Export implementiert.

---

## Inhaltsverzeichnis

- [Was ist Packbox?](#was-ist-packbox)
- [Vergleich mit Flatpak](#vergleich-mit-flatpak)
- [Anforderungen](#anforderungen)
- [Installation](#installation)
- [Schnellstart](#schnellstart)
- [Verfügbare Befehle](#verfügbare-befehle)
- [Dateistruktur](#dateistruktur)
- [Architektur](#architektur)
- [Sicherheit](#sicherheit)
- [Roadmap](#roadmap)
- [Mitwirken](#mitwirken)
- [Lizenz](#lizenz)
- [Danksagungen](#danksagungen)

---

## Was ist Packbox?

Packbox paketiert Linux-Anwendungen mit **Content-Addressable Storage (CAS)**
mit **BLAKE3**-Hashing und optimiertem **inhaltsbasiertem Chunking**, um echte binäre
Deduplizierung zwischen Apps zu erreichen.

Statt einer Runtime von ~1 GB pro Anwendung (Flatpak) speichert Packbox jede
Datei in Chunks (nach Inhalt dedupliziert) und teilt sie zwischen allen
Apps; die **Zstd**-Komprimierung wird beim Exportieren der `.pbox` angewendet. Außerdem macht es jede Bibliothek zu einer **Zelle** (einer versionierten
Wiederverwendungseinheit), die mehrere Apps teilen, und überlässt die
universellen Bibliotheken (`libc`, `libm`, …) dem Host.

### Designprinzipien

- **Deduplizierung auf Chunk-Ebene.** Gleiche Bytes = gleicher Hash = einmal
  gespeichert (CDC optimiert für ELF-Binärdateien; Einzeldatei bei kleinen).
- **Roh gespeichert, komprimiert exportiert.** Der CAS hält die Chunks unkomprimiert, damit die Installation sie **hardlinken** kann (echte Dedup auf der Festplatte); die **Zstd**-Komprimierung wird beim Erstellen der `.pbox` angewendet.
- **Zellen (atomare Fragmentierung).** Jede nicht universelle Lib ist eine Zelle;
  die App deklariert sie und der Installer löst sie auf.
- **App-übergreifendes Sharing.** Alle Apps teilen denselben globalen CAS und
  dieselben Zellen.
- **Host contract v1.** Selektive Delegierung universeller Bibliotheken mit
  **ABI-Prüfung** der erforderlichen Symbole.
- **Verstärkter Sandbox (bubblewrap).** `--unshare-all`, `--cap-drop ALL`,
  **seccomp**, **gefiltertes D-Bus** (`xdg-dbus-proxy`), **privates HOME pro App**,
  granulare Netzwerkrichtlinien (none/limited/full) und **X11 opt-in mit Autodetektion**.
- **Overlay pro Schicht.** `/app` wird als Overlay von A (App) über C (Zellen)
  zusammengesetzt, mit S (Host) über `/usr`.
- **Signaturen und Verteilung.** `.pbox` signierbar (ed25519) und HTTP-Remote mit
  konkurrentem Delta-Download.
- **4 Paketierungsmodi.** Normal, Portable, Bundle, Module.

---

## Vergleich mit Flatpak

| Merkmal              | Flatpak (aktuell)           | Packbox v0.3.0                       |
|----------------------|-----------------------------|--------------------------------------|
| Wiederverwendungseinheit | Vollständige Runtime (~1 GB) | **Zellen** pro Lib (ohne Runtimes) |
| Deduplizierung       | Auf Dateiebene (OSTree)     | Auf **Chunk**-Ebene (BLAKE3 + CDC)   |
| Speicherung         | Komprimiert pro Runtime     | **Rohe Chunks + Hardlink** (Dedup)    |
| Sharing von Libs     | Innerhalb derselben Runtime | App-übergreifend zwischen allen Apps |
| Nutzung von Host-Libs | Keine                      | Selektiv (Host contract + ABI)       |
| Aktualisierungen     | Delta von OSTree-Objekten   | `packbox-update` (Delta + LRU GC)    |
| Verteilung           | Flathub + OSTree-Remotes    | Konkurrenter HTTP-Remote              |
| Signaturen           | GPG                         | ed25519 (`.pbox.sig`)                |
| Sandbox              | bwrap + seccomp + Portale   | bwrap + seccomp + dbus-proxy + Portale |
| Benutzeroberfläche   | GNOME Software / CLI        | **TUI** + CLI                          |
| Overhead pro App     | ~100 % bei abweichender Runtime | **~5–15 %** bei Apps mit Sharing  |

---

## Anforderungen

- **Betriebssystem**: Linux (Debian 12+, Ubuntu 22.04+, Fedora 40+, Arch,
  openSUSE Tumbleweed)
- **Kernel**: 5.15+ mit aktivierten User-Namespaces
- **Shell**: Bash 4.0+
- **Go**: 1.22+ (der Installer lädt bei Bedarf eine eigene Kopie herunter)
- **Speicherplatz**: ~500 MB frei für die erste Kompilierung
- **Internet**: nur für die Erstinstallation

### Systemabhängigkeiten

Werden nach Möglichkeit vom Installer installiert; auch manuell nützlich:

`bubblewrap` · `binutils` (`ldd`/`readelf`) · `jq` · `bc` · `curl` · `tar` ·
`xdg-dbus-proxy` (D-Bus-Filterung) · `zstd` oder `xz` (kompakterer Export)

---

## Installation

### Schritt 1 — Klonen und ausführen

```bash
git clone https://github.com/El-Ave-Azul/packbox.git
cd packbox
./packbox-install.sh
```

Der Installer öffnet ein Menü; wähle die Option **1** (Installieren).

### Schritt 2 — Die Shell neu laden

```bash
source ~/.bashrc
```

### Schritt 3 — Überprüfen

```bash
packbox-diagnose
```

---

## Schnellstart

### 1. Interaktiver Packager (TUI)

```bash
./packbox-packager.sh
```

Die Option **1 (Paketieren)** sucht nach **bereits installierten** Apps und **erzeugt eine**
`.pbox` in `~/.local/share/packbox/exports/`. Nach Abschluss wird gefragt, ob du sie
zusätzlich **auf diesem Rechner installieren** möchtest (Standard: **nein**, um dein
System nicht zu überladen). Zum Installieren einer `.pbox` verwende Option **5 (Importieren)**.

### 2. Kommandozeile

```bash
# Ein Verzeichnis paketieren
packbox-pack ./mi-app --name org.ejemplo.miapp --version 1.0.0

# Aus dem generierten Manifest installieren
packbox-install ./mi-app/manifest.json

# Im Sandbox ausführen (Overlay A über C; privates HOME)
packbox-run org.ejemplo.miapp

# Apps auflisten (echte Größe und Sharing-Ersparnis) und Speicher freigeben
packbox-list
packbox-remove org.ejemplo.miapp
packbox-gc

# Eine installierte App aktualisieren und dabei Chunks aus dem Store wiederverwenden
packbox-update org.ejemplo.miapp ./nuevo/manifest.json

# ...oder nur das Delta von einem Remote holen (die fehlenden Chunks)
packbox-update org.ejemplo.miapp --from https://repo.ejemplo/mi-app
```

---

## Verfügbare Befehle

Packbox v0.3.0 enthält **15 Go-Binärdateien** in `~/.packbox/bin/`:

| Befehl             | Zweck                                                              |
|--------------------|--------------------------------------------------------------------|
| `packbox-pack`     | Hasht ein Verzeichnis in CAS-Chunks und erzeugt `manifest.json`    |
| `packbox-install`  | Installiert eine App aus dem Manifest (+ `--desktop`/`--remove-desktop`) |
| `packbox-run`      | Führt die App im `bwrap`-Sandbox aus (Overlay A/C, privates HOME)  |
| `packbox-list`     | Listet Apps mit ihrer **echten Größe** und Sharing-Ersparnis (`--tsv`) |
| `packbox-remove`   | Deinstalliert eine App (`--all` = alle, `--dry-run`) und gibt ihre Referenzen frei |
| `packbox-gc`       | Sammelt Chunks **und Zellen** ohne Referenzen ein (Unterstützt LRU)            |
| `packbox-verify`   | Prüft auflösbare Libs + **ABI-Kompatibilität** des Hosts           |
| `packbox-export`   | Exportiert nach `.pbox` mit **adaptiver Kompression** und optionalem `--sign` |
| `packbox-import`   | Importiert ein `.pbox` (Anti-tar-slip, Traversal und Signaturen)        |
| `packbox-update`   | Aktualisiert eine App unter Wiederverwendung von Chunks aus dem Store; `--from <url>` lädt das Delta herunter |
| `packbox-module`   | Module/Zellen: `list`, `create`, `cell <lib>...`                   |
| `packbox-sign`     | ed25519-Schlüssel und -Signaturen: `keygen`, `sign`, `verify`, `trust` |
| `packbox-fetch`    | HTTP-Remote: `publish`, `index`/`search`/`install` mit **signiertem Index**, und `fetch` (konkurrentes Delta) |
| `packbox-debug`    | Hängt die Debug-Symbole (separate Zelle) einer installierten App an |
| `packbox-diagnose` | Umgebungsbericht für Bug-Reports                                   |

---

## Architektur

### Paketierungsablauf

```
┌──────────────┐   pack    ┌──────────────┐  install  ┌──────────────┐
│  Quelldir.   │ ────────► │     CAS      │ ─────────► │  App-Tree    │
│  (fs-Baum)   │           │  (chunks)    │           │ (hardlinks)  │
└──────────────┘           └──────────────┘           └──────┬───────┘
                                    │                          │ + Zellen (Schicht C)
                                    │ run                      ▼
                         ┌──────────────────────────────────────────┐
                         │  Sandbox bwrap: /app = Overlay A über C   │
                         │  privates HOME · seccomp · gefiltertes D-Bus │
                         └──────────────────────────────────────────┘
```

### Interne Komponenten

- **CAS + Chunker** — Speichert rohe Chunks (ohne Rekomprimierung, damit sie hardlinkbar sind) per **BLAKE3**-Hash. Große Dateien werden mit **optimiertem CDC** aufgeteilt; kleine gehen als einzelner Chunk ein. **Atomare** Schreibvorgänge.
- **Manifest** (`schema_version: \"1.7\"`) — Bildet Pfade auf Chunks ab, definiert die Netzwerkrichtlinie (`none`, `limited`, `full`), den Host Contract und das X11-Symbol.
- **Zellen** — Eine Lib = eine Zelle `org.lib.<soname>@<hash>` in `mods/`. Zwischen Apps geteilt. `packbox-gc` löscht nicht referenzierte oder alte Zellen (LRU).
- **Sandbox** — `bwrap --unshare-all --cap-drop ALL --clearenv`, **seccomp**, **gefiltertes D-Bus** mit `xdg-dbus-proxy`, **privates HOME**, granulare Netzwerkrichtlinien und **Multimedia-Unterstützung** (PipeWire/PulseAudio).
- **Schicht-Overlay** — `/app` wird mit `--overlay-src` zusammengesetzt (C unten, A oben); S (Host) kommt über `/usr`.
- **Host contract** — `packbox-verify` prüft, dass der Host die erforderlichen Symbole (ABI) bereitstellt.
- **Signaturen und Remote** — `packbox-sign` (ed25519) signiert das `.pbox` und den **Repository-Index**; `packbox-fetch` veröffentlicht, **sucht** (`search`) und installiert per id, mit **konkurrenten Downloads**.

---

## Sicherheit

### Implementierte Gegenmaßnahmen

- **Datenisolierung pro App** — Jede App läuft mit ihrem **privaten HOME**; nur Schriften/Themes werden **schreibgeschützt** eingebunden.
- **Gefiltertes D-Bus** — `xdg-dbus-proxy` mit Whitelist (Portale + `dconf`).
- **seccomp** — Standardfilter, der gefährliche Kernel-Oberflächen blockiert.
- **Granulare Netzwerkrichtlinien** — Modi `none`/`limited`/`full`. `limited` verwendet einen internen **best-effort**-Proxy, der private/reservierte Bereiche blockiert; er wirkt sich nur auf Apps aus, die `http_proxy`/`https_proxy` beachten (rohe Sockets werden nicht gefiltert).
- **Sichere Multimedia-Unterstützung** — Vermittelter Zugriff auf Audio und Kamera via Portale.
- **Anti-tar-slip / Traversal** — Strikte Pfadvalidierung in `.pbox`.
- **Bereinigung der Umgebung** — `--clearenv` + explizite Whitelist.
- **Reference counting + LRU GC** — Intelligente Chunk-Bereinigung basierend auf der Zugriffszeit.
- **Signaturen** — `.pbox` signierbar mit **ed25519**.

---

## Roadmap

### v0.1.x — Stabilisierung
- [x] Signaturprüfung für `.pbox`
- [x] Verstärkter Sandbox: privates HOME, gefiltertes D-Bus, seccomp
- [x] Automatische Zellen + Schicht-Overlay (A/C/S)
- [x] `packbox-update` mit Chunk-Delta + automatischem GC
- [x] HTTP-Remote mit konkurrentem Delta-Download
- [x] Zstd-Komprimierung im `.pbox`-Export
- [x] CDC-Tuning für ELF-Binärdateien
- [x] LRU-Garbage-Collection

### v0.2 — Umfang
- [ ] GUI-Frontend in GTK4 (aufgeschoben)
- [ ] Vorkompilierte Binärdateien x86_64 und aarch64
- [x] Signierter zentraler Index/Repository

### Zukunft
- [ ] Flatpak-Runtime-Importer (best-effort)
- [ ] WASM-Sandbox für nicht vertrauenswürdige Plugins

---

## Lizenz

Verteilt unter der **Apache License 2.0**. Siehe [LICENSE](../../LICENSE).
