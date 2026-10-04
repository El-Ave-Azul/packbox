# Packbox

**[Español](../../README.md)** · [English](../en/README.md) · [Français](../fr/README.md) · [Deutsch](../de/README.md) · **[Italiano](README.md)** · [Português](../pt/README.md) · [中文](../zh/README.md) · [日本語](../ja/README.md) · [한국어](../ko/README.md)

---

![CI](https://github.com/El-Ave-Azul/packbox/actions/workflows/ci.yml/badge.svg)
![Licenza](https://img.shields.io/badge/Licenza-Apache_2.0-blue.svg)
![Versione](https://img.shields.io/badge/Versione-0.3.0-orange.svg)
![Piattaforma](https://img.shields.io/badge/Piattaforma-Linux-blue.svg)
![Go](https://img.shields.io/badge/Go-1.22+-00ADD8.svg?logo=go&logoColor=white)
![i18n](https://img.shields.io/badge/i18n-9_lingue-green.svg)
![Stato](https://img.shields.io/badge/Stato-Beta-blue.svg)

**Impacchettatore di applicazioni Linux con deduplicazione binaria per chunk ed export `.pbox` compresso con Zstd.**
Ispirato a Flatpak, ma con un modello di riutilizzo diverso: invece di un
runtime monolitico per app, Packbox conserva il contenuto in un archivio
indirizzato per contenuto (BLAKE3 CAS), con **chunking definito per contenuto
(CDC)** ottimizzato e **celle** riutilizzabili. Due app che condividono il 90% delle loro
librerie memorizzano solo il 10% che differisce.

> [!IMPORTANT]
> **Stato Beta (v0.3.0).** Il sistema ha evoluto la stabilità del core, implementando la garbage collection LRU e la compressione Zstd in fase di export.

---

## Indice

- [Cos'è Packbox?](#cosè-packbox)
- [Confronto con Flatpak](#confronto-con-flatpak)
- [Requisiti](#requisiti)
- [Installazione](#installazione)
- [Avvio rapido](#avvio-rapido)
- [Comandi disponibili](#comandi-disponibili)
- [Struttura dei file](#struttura-dei-file)
- [Architettura](#architettura)
- [Sicurezza](#sicurezza)
- [Roadmap](#roadmap)
- [Contribuire](#contribuire)
- [Licenza](#licenza)
- [Ringraziamenti](#ringraziamenti)

---

## Cos'è Packbox?

Packbox impacchetta applicazioni Linux utilizzando **Content-Addressable Storage (CAS)**
con hashing **BLAKE3** e **chunking per contenuto** ottimizzato, per ottenere una deduplicazione
binaria reale tra le app.

Invece di un runtime di ~1 GB per applicazione (Flatpak), Packbox conserva ogni
file in chunk (deduplicati per contenuto) e li condivide tra tutte le
app; la compressione **Zstd** viene applicata durante l'export del `.pbox`. Inoltre, converte ogni libreria in una **cella** (un'unità di riutilizzo
versionata) che più app condividono, e lascia le librerie universali
(`libc`, `libm`, …) all'host.

### Principi di design

- **Deduplicazione a livello di chunk.** Stessi byte = stesso hash = memorizzato una
  volta (CDC ottimizzato per binari ELF; file singolo per quelli piccoli).
- **Archiviazione grezza, export compresso.** Il CAS mantiene i chunk non compressi così che l'installazione possa **hardlinkarli** (deduplicazione reale su disco); la compressione **Zstd** viene applicata durante la creazione del `.pbox`.
- **Celle (frammentazione atomica).** Ogni lib non universale è una cella;
  l'app la dichiara e l'installer la risolve.
- **Condivisione incrociata.** Tutte le app condividono lo stesso CAS globale e le
  stesse celle.
- **Host contract v1.** Delega selettiva di librerie universali, con
  **controllo ABI** dei simboli richiesti.
- **Sandbox rinforzato (bubblewrap).** `--unshare-all`, `--cap-drop ALL`,
  **seccomp**, **D-Bus filtrato** (`xdg-dbus-proxy`), **HOME privata per app**,
  rete granulare (none/limited/full) e **X11 opt-in con autodetezione**.
- **Strato per overlay.** `/app` è composto come overlay di A (app) su C
  (celle), con S (host) via `/usr`.
- **Firme e distribuzione.** `.pbox` firmabili (ed25519) e remoto HTTP con
  download delta concorrente.
- **4 modalità di impacchettamento.** Normale, Portatile, Bundle, Modulo.

---

## Confronto con Flatpak

| Caratteristica       | Flatpak (attuale)            | Packbox v0.3.0                       |
|----------------------|-----------------------------|--------------------------------------|
| Unità di riutilizzo      | Runtime completo (~1 GB)    | **Celle** per lib (senza runtimes)    |
| Deduplicazione        | A livello di file (OSTree) | A livello di **chunk** (BLAKE3 + CDC)  |
| Archiviazione       | Compresso per runtime     | **Chunk grezzi + hardlink** (dedup)    |
| Condivisione di libs | All'interno dello stesso runtime | Incrociata tra tutte le app         |
| Uso di libs dell'host | Nessuno                     | Selettivo (host contract + ABI)      |
| Aggiornamenti      | Delta di oggetti OSTree     | `packbox-update` (delta + GC LRU)    |
| Distribuzione         | Flathub + remotes OSTree    | Remoto HTTP concorrente              |
| Firme               | GPG                         | ed25519 (`.pbox.sig`)                |
| Sandbox              | bwrap + seccomp + portali  | bwrap + seccomp + dbus-proxy + portali |
| Interfaccia             | GNOME Software / CLI        | **TUI** + CLI                          |
| Overhead per app     | ~100 % se runtime distinto  | **~5–15 %** con app che condividono   |

---

## Requisiti

- **Sistema operativo**: Linux (Debian 12+, Ubuntu 22.04+, Fedora 40+, Arch,
  openSUSE Tumbleweed)
- **Kernel**: 5.15+ con user namespaces abilitati
- **Shell**: Bash 4.0+
- **Go**: 1.22+ (l'installer scarica la propria copia se manca)
- **Spazio**: ~500 MB liberi per la compilazione iniziale
- **Internet**: solo per la prima installazione

### Dipendenze di sistema

Installate dall'installer quando possibile; utili anche manualmente:

`bubblewrap` · `binutils` (`ldd`/`readelf`) · `jq` · `bc` · `curl` · `tar` ·
`xdg-dbus-proxy` (filtraggio D-Bus) · `zstd` o `xz` (export più compatto)

---

## Installazione

### Passo 1 — Clonare ed eseguire

```bash
git clone https://github.com/El-Ave-Azul/packbox.git
cd packbox
./packbox-install.sh
```

L'installer apre un menu; scegli l'opzione **1** (Installazione).

### Passo 2 — Ricaricare il shell

```bash
source ~/.bashrc
```

### Passo 3 — Verificare

```bash
packbox-diagnose
```

---

## Avvio rapido

### 1. Impacchettatore interattivo (TUI)

```bash
./packbox-packager.sh
```

L'opzione **1 (Impacchetta)** cerca le app **già installate** e **genera un**
`.pbox` in `~/.local/share/packbox/exports/`. Al termine, chiede se vuoi inoltre
**installarla su questo computer** (per impostazione predefinita **no**, per non sporcare il tuo
sistema). Per installare un `.pbox` usa l'opzione **5 (Importa)**.

### 2. Riga di comando

```bash
# Impacchetta una directory
packbox-pack ./mia-app --name org.esempio.miapp --version 1.0.0

# Installa dal manifesto generato
packbox-install ./mia-app/manifest.json

# Esegui nel sandbox (overlay A su C; HOME privata)
packbox-run org.esempio.miapp

# Elenca le app (dimensione reale e risparmio da condivisione) e libera spazio
packbox-list
packbox-remove org.esempio.miapp
packbox-gc

# Aggiorna un'app installata riutilizzando i chunk dallo store
packbox-update org.esempio.miapp ./nuovo/manifest.json
```

---

## Comandi disponibili

Packbox v0.3.0 include **15 binari Go** in `~/.packbox/bin/`:

| Comando            | Scopo                                                          |
|--------------------|--------------------------------------------------------------------|
| `packbox-pack`     | Crea l'hash di una directory in chunk CAS e genera `manifest.json`   |
| `packbox-install`  | Installa un'app dal manifesto (+ `--desktop`/`--remove-desktop`) |
| `packbox-run`      | Esegue l'app nel sandbox `bwrap` (overlay A/C, HOME privata)   |
| `packbox-list`     | Elenca le app con la loro **dimensione reale** e risparmio da condivisione (`--tsv`) |
| `packbox-remove`   | Disinstalla un'app (`--all` = tutte, `--dry-run`) e libera i riferimenti |
| `packbox-gc`       | Raccoglie chunk **e celle** senza riferimenti (Supporta LRU)         |
| `packbox-verify`   | Controlla le lib risolvibili + **compatibilità ABI** dell'host        |
| `packbox-export`   | Esporta in `.pbox` con **compressione adattiva** e `--sign` opzionale |
| `packbox-import`   | Importa un `.pbox` (anti tar-slip, traversal e firme)             |
| `packbox-update`   | Aggiorna un'app riutilizzando i chunk + report delta (`--no-gc`)   |
| `packbox-module`   | Moduli/celle: `list`, `create`, `cell <lib>...`                  |
| `packbox-sign`     | Chiavi e firme ed25519: `keygen`, `sign`, `verify`, `trust`       |
| `packbox-fetch`    | Remoto HTTP: `publish`, `index`/`search`/`install` con un **indice firmato**, e `fetch` (delta concorrente) |
| `packbox-debug`    | Allega i simboli di debug (cella a parte) di un'app installata  |
| `packbox-diagnose` | Report dell'ambiente per segnalazioni di bug                          |

---

## Architettura

### Flusso di impacchettamento

```
┌──────────────┐   pack    ┌──────────────┐  install  ┌──────────────┐
│  Dir fonte  │ ────────► │     CAS      │ ─────────► │  Tree di app │
│  (albero fs)  │           │  (chunks)    │           │ (hardlinks)  │
└──────────────┘           └──────────────┘           └──────┬───────┘
                                    │                          │ + celle (strato C)
                                    │ run                      ▼
                         ┌──────────────────────────────────────────┐
                         │  Sandbox bwrap: /app = overlay A su C     │
                         │  HOME privata · seccomp · D-Bus filtrato   │
                         └──────────────────────────────────────────┘
```

### Componenti interni

- **CAS + chunker** — Conserva chunk grezzi (senza ricompressione, così da poterli hardlinkare) per hash **BLAKE3**. I file grandi sono divisi con **CDC ottimizzato**; i piccoli come un singolo chunk. Scritture **atomiche**.
- **Manifesto** (`schema_version: \"1.7\"`) — Mappa i percorsi ai chunk, definisce la politica di rete (`none`, `limited`, `full`), l'host contract e il simbolo X11.
- **Celle** — Una lib = una cella `org.lib.<soname>@<hash>` in `mods/`. Condivise tra le app. `packbox-gc` elimina quelle non referenziate o vecchie (LRU).
- **Sandbox** — `bwrap --unshare-all --cap-drop ALL --clearenv`, **seccomp**, **D-Bus filtrato** con `xdg-dbus-proxy`, **HOME privata**, rete granulare e **Supporto Multimedia** (PipeWire/PulseAudio).
- **Strato per overlay** — `/app` è composto con `--overlay-src` (C sotto, A sopra); S (host) arriva via `/usr`.
- **Host contract** — `packbox-verify` controlla che l'host fornisca i simboli richiesti (ABI).
- **Firme e remoto** — `packbox-sign` (ed25519) firma il `.pbox` e l'**indice del repository**; `packbox-fetch` pubblica, **cerca** (`search`) e installa per id, con **download concorrenti**.

---

## Sicurezza

### Mitigazioni implementate

- **Isolamento dati per app** — Ogni app gira con la sua **HOME privata**; solo font/temi sono esposti in **sola lettura**.
- **D-Bus filtrato** — `xdg-dbus-proxy` con lista bianca (portali + `dconf`).
- **seccomp** — Filtro predefinito che blocca la superficie pericolosa del kernel.
- **Rete Granulare** — Modalità `none`/`limited`/`full`. `limited` usa un proxy interno **best-effort** che blocca gli intervalli privati/riservati; influisce solo sulle app che rispettano `http_proxy`/`https_proxy` (i socket grezzi non vengono filtrati).
- **Supporto Multimedia Sicuro** — Accesso mediato ad audio e camera via portali.
- **Anti tar-slip / traversal** — Validazione rigorosa dei percorsi in `.pbox`.
- **Pulizia dell'ambiente** — `--clearenv` + whitelist esplicita.
- **Reference counting + LRU GC** — Pulizia intelligente dei chunk basata sul tempo di accesso.
- **Firme** — `.pbox` firmabili con **ed25519**.

---

## Roadmap

### v0.1.x — Stabilizzazione
- [x] Verifica firme per `.pbox`
- [x] Sandbox rinforzato: HOME privata, D-Bus filtrato, seccomp
- [x] Celle automatiche + overlay di strati (A/C/S)
- [x] `packbox-update` con delta di chunk + GC automatico
- [x] Remoto HTTP con download delta concorrente
- [x] Compressione Zstd nell'export `.pbox`
- [x] Tuning di CDC per binari ELF
- [x] Garbage collection LRU

### v0.2 — Scope
- [ ] Frontend GUI in GTK4 (rinviato)
- [ ] Binari precompilati x86_64 e aarch64
- [x] Indice/repository centrale firmato

### Futuro
- [ ] Importatore di runtime Flatpak (best-effort)
- [ ] Sandbox WASM per plugin non attendibili

---

## Licenza

Distribuito sotto la **Apache License 2.0**. Vedi [LICENSE](../../LICENSE).
