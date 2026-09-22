# Packbox

[Español](../../README.md) · [English](../en/README.md) · [Français](../fr/README.md) · **[Deutsch](README.md)** · [Italiano](../it/README.md) · [Português](../pt/README.md) · [中文](../zh/README.md) · [日本語](../ja/README.md) · [한국어](../ko/README.md)

---

![Lizenz](https://img.shields.io/badge/Licencia-Apache_2.0-blue.svg)
![Version](https://img.shields.io/badge/Versión-0.2.0-orange.svg)
![Plattform](https://img.shields.io/badge/Plataforma-Linux-blue.svg)
![Go](https://img.shields.io/badge/Go-1.22+-00ADD8.svg?logo=go&logoColor=white)
![i18n](https://img.shields.io/badge/i18n-9_idiomas-green.svg)
![Status](https://img.shields.io/badge/Estado-Alpha-red.svg)

**Linux-Anwendungspackager mit binärer Deduplizierung pro Chunk.**
Inspiriert von Flatpak, aber mit einem anderen Wiederverwendungsmodell: statt einer
monolithischen Runtime pro App speichert Packbox den Inhalt in einem
inhaltsadressierten Speicher (BLAKE3 CAS), mit **inhaltsdefiniertem Chunking
(CDC)** und wiederverwendbaren **Zellen**. Zwei Apps, die 90 % ihrer
Bibliotheken teilen, speichern nur die 10 %, die abweichen.

> [!WARNING]
> **Alpha-Status (v0.2.0).** Die Hauptabläufe funktionieren, und es gibt bereits
> Signaturen, verstärkten Sandbox (seccomp, gefiltertes D-Bus, privates HOME) und
> HTTP-Remote, aber das Projekt ist jung und hat weder das Ökosystem noch die
> Reife von Flatpak. Nutze es zunächst auf unkritischen Systemen.

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
mit **BLAKE3**-Hashing und **inhaltsbasiertem Chunking**, um echte binäre
Deduplizierung zwischen Apps zu erreichen.

Statt einer Runtime von ~1 GB pro Anwendung (Flatpak) speichert Packbox jede
Datei als inhaltsadressierte Chunks und teilt sie zwischen allen Apps. Außerdem
macht es jede Bibliothek zu einer **Zelle** (einer versionierten
Wiederverwendungseinheit), die mehrere Apps teilen, und überlässt die
universellen Bibliotheken (`libc`, `libm`, …) dem Host.

### Designprinzipien

- **Deduplizierung auf Chunk-Ebene.** Gleiche Bytes = gleicher Hash = einmal
  gespeichert (CDC bei großen Dateien; Einzeldatei bei kleinen, um hardlinken und
  teilen zu können).
- **Zellen (atomare Fragmentierung).** Jede nicht universelle Lib ist eine Zelle;
  die App deklariert sie und der Installer löst sie auf.
- **App-übergreifendes Sharing.** Alle Apps teilen denselben globalen CAS und
  dieselben Zellen.
- **Host contract v1.** Selektive Delegierung universeller Bibliotheken mit
  **ABI-Prüfung** der erforderlichen Symbole.
- **Verstärkter Sandbox (bubblewrap).** `--unshare-all`, `--cap-drop ALL`,
  **seccomp**, **gefiltertes D-Bus** (`xdg-dbus-proxy`), **privates HOME pro App**,
  Netzwerk opt-in und **X11 opt-in mit Autodetektion**.
- **Overlay pro Schicht.** `/app` wird als Overlay von A (App) über C (Zellen)
  zusammengesetzt, mit S (Host) über `/usr`.
- **Signaturen und Verteilung.** `.pbox` signierbar (ed25519) und HTTP-Remote mit
  Delta-Download.
- **4 Paketierungsmodi.** Normal, Portable, Bundle, Module.

---

## Vergleich mit Flatpak

| Merkmal              | Flatpak (aktuell)           | Packbox v0.2.0                       |
|----------------------|-----------------------------|--------------------------------------|
| Wiederverwendungseinheit | Vollständige Runtime (~1 GB) | **Zellen** pro Lib (ohne Runtimes) |
| Deduplizierung       | Auf Dateiebene (OSTree)     | Auf **Chunk**-Ebene (BLAKE3 + CDC)   |
| Sharing von Libs     | Innerhalb derselben Runtime | App-übergreifend zwischen allen Apps |
| Nutzung von Host-Libs | Keine                      | Selektiv (Host contract + ABI)       |
| Aktualisierungen     | Delta von OSTree-Objekten   | `packbox-update` (Chunk-Delta + GC)  |
| Verteilung           | Flathub + OSTree-Remotes    | HTTP-Remote mit `publish`/`fetch`    |
| Signaturen           | GPG                         | ed25519 (`.pbox.sig`)                |
| Sandbox              | bwrap + seccomp + Portale   | bwrap + seccomp + dbus-proxy + Portale |
| Overhead pro App     | ~100 % bei abweichender Runtime | **~5–15 %** bei Apps mit Sharing  |

**Gemessene Ersparnis** (diese Codebasis): zwei mittelgroße GTK4-Apps, die ihren
Stack teilen, ergeben getrennt ~264 MB und belegen **~141 MB real (−46 %)**; bei
10 gemischten Apps steigt die Ersparnis auf **~69 %**. Je größer die
Überschneidung der Bibliotheken, desto größer die Ersparnis — aber es empfiehlt
sich, sie im Einzelfall zu messen und nicht die 90–99 % einer geteilten Runtime
anzunehmen.

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

### Was der Installer tut

1. Er lässt dich eine von 9 Sprachen auswählen.
2. Erkennt deine Linux-Distribution und deinen Paketmanager.
3. Fragt vor der Installation von Abhängigkeiten nach Bestätigung.
4. Lädt Go herunter und verifiziert es (standardmäßig 1.27.1) in `~/.packbox/go`, falls nötig.
5. Erstellt die Verzeichnisstruktur (`~/.packbox/` und `~/.local/share/packbox/`).
6. Kopiert die Quellen und kompiliert die **15 Go-Binärdateien** (~1–2 Minuten).
7. Konfiguriert dein `PATH` in `~/.bashrc` und erstellt Symlinks in `~/.local/bin`.
8. Installiert die Sprachdateien in `~/.config/packbox/lang/`.
9. Überprüft, dass alle Binärdateien vorhanden und funktionsfähig sind.

### Deinstallation

Führe dasselbe Skript aus und wähle die Option **2**:

```bash
./packbox-install.sh --uninstall
```

| Modus | Beschreibung |
|------|-------------|
| `s`  | Vollständig: Binärdateien + Apps + CAS-Store + Zellen + Menüs + Icons + Konfiguration |
| `k`  | Nur Binärdateien: `~/.packbox/` und Symlinks (behält Apps und CAS-Store) |
| `q`  | Abbrechen |

---

## Schnellstart

### 1. Interaktiver Packager (empfohlen)

```bash
./packbox-packager.sh
```

Menü: paketieren, auflisten, Garbage Collection, exportieren, importieren,
deinstallieren, Sprache. Erkennt Apps aus `.desktop` in
`/usr/share/applications/`, Bundles in `/opt/*` und gängige Binärdateien
(`htop`, `btop`, `firefox`, `gimp`, …).

In den Modi **Normal** und **Portable** wird jede nicht universelle Lib der
`ldd`-Closure automatisch in eine **Zelle** umgewandelt.

### 2. Kommandozeile

```bash
# Ein Verzeichnis paketieren
packbox-pack ./mi-app --name org.ejemplo.miapp --version 1.0.0

# Aus dem generierten Manifest installieren
packbox-install ./mi-app/manifest.json

# Im Sandbox ausführen (Overlay A über C; privates HOME)
packbox-run org.ejemplo.miapp

# Apps auflisten (echte Größe und Ersparnis durch Sharing) und Speicher freigeben
packbox-list
packbox-remove org.ejemplo.miapp
packbox-gc

# Eine installierte App aktualisieren und dabei Chunks aus dem Store wiederverwenden
packbox-update org.ejemplo.miapp ./nuevo/manifest.json
```

### 3. Exportieren, signieren, importieren und verteilen

```bash
# Exportieren und signieren
packbox-sign keygen                       # erstellt deinen Schlüssel (und vertraut ihm)
packbox-export --sign app org.ejemplo.miapp
packbox-sign verify ~/.local/share/packbox/exports/org.ejemplo.miapp.pbox

# Ein HTTP-Remote veröffentlichen und von einem anderen Rechner aus nutzen
packbox-fetch publish org.ejemplo.miapp /srv/packbox
(cd /srv/packbox && python3 -m http.server 8000)
packbox-fetch fetch org.ejemplo.miapp --from http://host:8000

# Importieren (verifiziert die Signatur, falls vorhanden)
packbox-import app org.ejemplo.miapp.pbox
```

---

## Verfügbare Befehle

Packbox v0.2.0 enthält **15 Go-Binärdateien** in `~/.packbox/bin/`:

| Befehl             | Zweck                                                              |
|--------------------|--------------------------------------------------------------------|
| `packbox-pack`     | Hasht ein Verzeichnis in CAS-Chunks und erzeugt `manifest.json`    |
| `packbox-install`  | Installiert eine App aus dem Manifest (+ `--desktop`/`--remove-desktop`) |
| `packbox-run`      | Führt die App im `bwrap`-Sandbox aus (Overlay A/C, privates HOME)  |
| `packbox-list`     | Listet Apps mit ihrer **echten Größe** und Sharing-Ersparnis (`--tsv`) |
| `packbox-remove`   | Deinstalliert eine App und gibt ihre CAS-Referenzen frei           |
| `packbox-gc`       | Sammelt Chunks **und Zellen** ohne Referenzen ein                  |
| `packbox-verify`   | Prüft auflösbare Libs + **ABI-Kompatibilität** des Hosts           |
| `packbox-export`   | Exportiert nach `.pbox` mit **adaptiver Kompression** und optionalem `--sign` |
| `packbox-import`   | Importiert ein `.pbox` (Anti-tar-slip, Traversal und Signaturen)   |
| `packbox-update`   | Aktualisiert eine App unter Wiederverwendung von Chunks + Delta-Bericht (`--no-gc`) |
| `packbox-module`   | Module/Zellen: `list`, `create`, `cell <lib>...`                   |
| `packbox-sign`     | ed25519-Schlüssel und -Signaturen: `keygen`, `sign`, `verify`, `trust` |
| `packbox-fetch`    | HTTP-Remote: `publish <id> <dir>` und `fetch <id> --from <url>`    |
| `packbox-debug`    | Hängt die Debug-Symbole (separate Zelle) einer installierten App an |
| `packbox-diagnose` | Umgebungsbericht für Bug-Reports                                   |

---

## Dateistruktur

```
~/.packbox/                              # Installation
├── bin/                                 # 15 kompilierte Go-Binärdateien
└── src/                                 # Go-Quellcode

~/.local/share/packbox/                  # Benutzerdaten
├── store/                               # CAS: Chunks per BLAKE3-Hash
│   └── <ab>/<hash-completo>             # + .refs-Datei pro Chunk
├── apps/                                # Installierte Apps
│   └── <app-id>/
│       ├── manifest.json
│       ├── tree/                        # Hardlinks zum CAS (Schicht A)
│       └── home/                        # privates HOME (wird beim ersten Lauf erstellt)
├── mods/                                # Zellen (org.lib.*, org.debug.*)
├── exports/                             # .pbox-Dateien (+ .sig)
└── tmp/                                 # Temporäre Dateien

~/.config/packbox/
├── lang/                                # 9 Sprachdateien
├── signing.key / signing.pub            # dein Signaturschlüssel
└── trusted/                             # vertrauenswürdige öffentliche Schlüssel
```

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
                         ┌───────────────────────────────────────────┐
                         │  Sandbox bwrap: /app = Overlay A über C   │
                         │  eigenes HOME · seccomp · D-Bus gefiltert │
                         └───────────────────────────────────────────┘
```

### Interne Komponenten

- **CAS + Chunker** — Speichert Chunks per **BLAKE3**-Hash. Große Dateien werden
  mit **CDC** (rollierender *gear*-Hash) aufgeteilt; kleine gehen als einzelner
  Chunk ein (hardlinkbar, zum Teilen). **Atomare** Schreibvorgänge (temp+rename).
- **Manifest** (`schema_version: "1.6"`) — Bildet Pfade auf Chunks ab, listet die
  **Zellen** (`mods`), den `host_contract` (delegate + required_symbols), das
  X11-Symbol und, falls zutreffend, die **Debug**-Zelle.
- **Zellen** — Eine Lib = eine Zelle `org.lib.<soname>@<hash>` in `mods/`.
  Zwischen Apps geteilt. `packbox-gc` löscht die nicht referenzierten.
- **Sandbox** — `bwrap --unshare-all --cap-drop ALL --clearenv`, **seccomp**
  (blockiert ptrace/bpf/keyring/io_uring/Module…), **gefiltertes D-Bus** mit
  `xdg-dbus-proxy` (Portale + dconf), **privates HOME** (`apps/<id>/home`),
  Netzwerk **opt-in** und **X11 opt-in** (standardmäßig Wayland + Portale; wird
  nur aktiviert, wenn das Manifest es verlangt oder die Sitzung nur X11 ist).
- **Schicht-Overlay** — `/app` wird mit `--overlay-src` zusammengesetzt (C unten, A
  oben); S (Host) kommt über `/usr`. Vermeidet das Kopieren der Zellen in jeden
  Baum.
- **Host contract** — `packbox-verify` prüft, dass der Host die erforderlichen
  Symbole (ABI) bereitstellt.
- **Signaturen und Remote** — `packbox-sign` (ed25519) signiert das `.pbox`;
  `packbox-fetch` veröffentlicht und lädt nur das Delta herunter (Chunks + Zellen).

### Wie die Deduplizierung funktioniert

```
App 1: htop     → chunks: [A, B, C]
App 2: neofetch → chunks: [A, D, E]
App 3: btop     → chunks: [A, B, F]

CAS Store:
  A → Referenzen: htop, neofetch, btop      (3 apps)
  B → Referenzen: htop, btop                (2 apps)
  C → htop · D → neofetch · E → neofetch · F → btop

Gesamt: 6 eindeutige Chunks statt 9.
```

---

## Sicherheit

### Implementierte Gegenmaßnahmen

- **Datenisolierung pro App** — Jede App läuft mit ihrem **privaten HOME**
  (`apps/<id>/home`); nur Schriften/Themes werden **schreibgeschützt**
  eingebunden. Sie sieht und berührt deine echte Konfiguration nicht.
- **Gefiltertes D-Bus** — `xdg-dbus-proxy` mit Whitelist (standardmäßig Portale
  und `dconf`; der Systembus: nichts). Die App spricht nicht mit dem echten Bus.
- **seccomp** — Standardfilter, der gefährliche Kernel-Oberflächen blockiert
  (ptrace, bpf, keyring, io_uring, userfaultfd, Module, reboot/swap…).
- **X11 opt-in** — Standardmäßig Wayland + `xdg-desktop-portal` (mit Einbindung
  der Dokumenten-Mounts des Portals); X11 wird mit dem Flag `x11` des Manifests
  aktiviert oder automatisch, wenn die Host-Sitzung nur X11 ist.
- **Anti-tar-slip / Traversal** — Die `.pbox`-Extraktion validiert jeden Eintrag
  (`safeJoin` + `O_NOFOLLOW` + Symlink-Ziele) und lehnt `name`/Pfade ab, die aus
  dem App-Verzeichnis ausbrechen.
- **Bereinigung der Umgebung** — `--clearenv` + explizite Whitelist: blockiert
  vom Host injizierte `LD_PRELOAD`/`LD_LIBRARY_PATH`.
- **Kein setuid, kein root** — Alles läuft als dein Benutzer; `sudo` nur für die
  Systemabhängigkeiten bei der Installation.
- **Reference Counting + GC** — Jeder Chunk hat eine `.refs`; `packbox-gc` löscht
  nur nicht Referenziertes (Chunks **und Zellen**).
- **Signaturen** — `.pbox` mit **ed25519** signierbar; `import` verifiziert und
  **lehnt** veränderte Pakete oder solche von nicht vertrauenswürdigen
  Unterzeichnern ab.
- **CAS-Integrität** — Hashes werden vor der Verwendung als Pfad validiert;
  atomare Schreibvorgänge.

### Bekannte Einschränkungen (v0.2.0 Alpha)

> [!WARNING]
> Bereiche, für die Feedback am meisten geschätzt wird.

- ⚠️ **Teilweise Portale.** Der Dialog mit den Portalen ist erlaubt und die
  Dokumenten-Mounts werden eingebunden, aber es laufen noch nicht alle Zugriffe
  über Portale (Kamera, Zwischenablage usw.).
- ⚠️ **`packbox-module remove`/`info`** sind weiterhin nicht implementiert
  (`cell` hingegen existiert).
- ⚠️ **Adaptive Kompression** auf Paketebene, nicht pro Eintrag (das Format ist
  tar + ein Kompressor).
- ⚠️ **Kein Katalog.** Das HTTP-Remote liefert Daten, aber kein Vertrauen und
  keinen öffentlichen Index.

---

## Roadmap

### v0.1.x — Stabilisierung

- [x] Signaturprüfung für `.pbox` (ed25519 + Schlüsselverwaltung)
- [x] Verstärkter Sandbox: privates HOME, gefiltertes D-Bus, seccomp
- [x] Automatische Zellen + Schicht-Overlay (A/C/S)
- [x] `packbox-update` mit Chunk-Delta + automatischem GC
- [x] HTTP-Remote (`publish`/`fetch`) mit Delta-Download
- [x] Debug-Symbole separat (`cell-debug`)
- [x] Adaptive Kompression in `export`
- [x] End-to-End-Integrationstests (`tests/integration.sh`)
- [ ] Netzwerkrichtlinie pro Anwendung
- [ ] Vollständige Portale (Dateien, Kamera, Zwischenablage)
- [ ] CI/CD: `shellcheck`, `gofmt`, `go vet` in jedem PR
- [ ] Testmatrix: Debian 12, Fedora 40, Arch, openSUSE Tumbleweed

### v0.2 — Umfang

- [ ] Vorkompilierte Binärdateien x86_64 und aarch64 (Releases-Seite)
- [ ] Signierter zentraler Index/Repository (`search`/`install` aus der Ferne)
- [ ] Optionales GUI-Frontend (GTK4)

### Zukunft

- [ ] Flatpak-Runtime-Importer (best-effort)
- [ ] WASM-Sandbox für nicht vertrauenswürdige Plugins

---

## Mitwirken

Beiträge sind willkommen! Bereiche, in denen Hilfe besonders nützlich ist:

- **Übersetzungen** — Füge ein Locale hinzu, indem du einen bestehenden Block in
  `i18n/` kopierst und jeden `L_*`-Schlüssel übersetzt.
- **Portale** — `xdg-desktop-portal` für Dateizugriff integrieren.
- **Chunking / Dedup** — Das CDC und die Schwellenwert-Strategie verbessern.
- **Bug-Reports** — Füge immer die Ausgabe von `packbox-diagnose` bei.

### Erste Schritte

```bash
git clone https://github.com/El-Ave-Azul/packbox.git
cd packbox
cd src && go test ./...     # Unit-Tests
bash tests/integration.sh   # End-to-End (pack → export → import → run)
```

- 🐛 [Ein Issue öffnen](https://github.com/El-Ave-Azul/packbox/issues)
- 💬 [Eine Diskussion starten](https://github.com/El-Ave-Azul/packbox/discussions)

> [!TIP]
> Lass `shellcheck` über die Bash-Skripte und `gofmt` + `go vet` über Go laufen,
> bevor du einen PR einreichst.

---

## Lizenz

Verteilt unter der **Apache License 2.0**. Siehe [LICENSE](../../LICENSE).

Apache 2.0 bietet eine **explizite Klausel zur Patentgewährung**, die Nutzer und
Beitragende vor Rechtsstreitigkeiten über die Techniken zur Deduplizierung und
zum Sandboxing schützt, und ist mit GPLv3 kompatibel.

---

## Danksagungen

- **[bubblewrap](https://github.com/containers/bubblewrap)** — Linux-Sandbox-
  Primitiv, das `packbox-run` möglich macht.
- **[BLAKE3](https://github.com/BLAKE3-team/BLAKE3)** — Schnelles und
  kryptografisch sicheres Content-Hashing.
- **[xdg-desktop-portal](https://flatpak.github.io/xdg-desktop-portal/)** und
  **xdg-dbus-proxy** — Vermittelter Dateizugriff und D-Bus-Filterung.
- **[Flatpak](https://flatpak.org/)** — Bewies, dass sandboxed Linux-Apps im
  großen Maßstab funktionieren; viele seiner Entscheidungen haben unsere geprägt,
  auch dort, wo wir abweichen.
- **Globale Linux-Community** — Die i18n-Schicht mit 9 Sprachen existiert dank
  ihrer Reviews und Beiträge.
