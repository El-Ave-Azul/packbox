[English](../../README.md) · [Español](../../README.es.md) · [Français](../fr/README.md) · [Deutsch](../de/README.md) · **Italiano** · [简体中文](../zh-CN/README.md) · [繁體中文](../zh-TW/README.md) · [日本語](../ja/README.md) · [한국어](../ko/README.md)

---

![Licenza: MIT](https://img.shields.io/badge/Licenza-MIT-yellow.svg)
![Piattaforma: Linux](https://img.shields.io/badge/piattaforma-Linux-blue)
![Versione](https://img.shields.io/badge/versione-0.1.0--alpha-orange)
![Go](https://img.shields.io/badge/Go-1.22+-00ADD8?logo=go&logoColor=white)
![i18n](https://img.shields.io/badge/i18n-9_lingue-green)
![Stato](https://img.shields.io/badge/stato-alpha-red)

# Packbox

**Sistema di packaging di applicazioni di nuova generazione per Linux.**
Ispirato a Flatpak, ma con un modello di riuso fondamentalmente diverso:
invece di spedire un runtime monolitico per app, Packbox memorizza ogni file
come chunk indirizzati per contenuto (BLAKE3 CAS). Due app che condividono
il 90 % delle librerie memorizzano solo il 10 % differente.

> [!NOTE]
> **Packbox è in Alpha (v0.1.0).** I flussi principali funzionano, ma non
> c'è ancora verifica delle firme sugli archivi `.pbox`, e la sandbox è
> intenzionalmente più permissiva di Flatpak. Usalo prima su sistemi non
> critici.

---

## Indice

- [Perché Packbox](#perché-packbox)
- [Confronto con Flatpak](#confronto-con-flatpak)
- [Requisiti](#requisiti)
- [Installazione](#installazione)
- [Avvio rapido](#avvio-rapido)
- [Comandi](#comandi)
- [Struttura del filesystem](#struttura-del-filesystem)
- [Architettura](#architettura)
- [Sicurezza](#sicurezza)
- [Roadmap](#roadmap)
- [Documentazione](#documentazione)
- [Contribuire](#contribuire)
- [Licenza](#licenza)
- [Ringraziamenti](#ringraziamenti)

---

## Perché Packbox

Flatpak ha risolto un problema reale: app Linux sandboxate e portabili. Ma
il suo modello di riuso è grossolano. Ogni app spedisce (o referenzia) un
runtime completo che può pesare **~1 GB**. Se due app usano runtime diversi,
paghi due volte — anche se condividono il 95 % delle librerie.

Packbox attacca proprio quel vuoto:

- **Deduplicazione a livello di chunk.** I file vengono divisi, hashati con
  BLAKE3 e memorizzati come chunk. Chunk identici (una `libfoo.so.3.2.1`,
  un font, un catalogo di traduzioni) sono condivisi tra tutte le app del
  sistema.
- **Condivisione di librerie tra app.** Due app che usano la stessa
  `libQt6Core.so` tengono una sola copia su disco, indipendentemente dal
  loro "runtime".
- **Uso selettivo delle librerie dell'host.** Le app possono dichiarare in
  quali librerie dell'host confidano (via `host_contract.delegate`), invece
  di impacchettare tutto.
- **Impronta ridotta per app.** In pratica, aggiungere una nuova app su un
  set esistente costa ~5–15 % della sua dimensione, non ~100 %.

Packbox **non** cerca di sostituire Flatpak. Esplora una nicchia diversa:
app che non si inseriscono pulitamente in un runtime, o dove spedire 1 GB
per eseguire uno strumento da 50 MB è eccessivo.

---

## Confronto con Flatpak

| Caratteristica        | Flatpak (attuale)                | Packbox (proposto)              |
|-----------------------|----------------------------------|---------------------------------|
| Unità di riuso        | Runtime completo (~1 GB)         | Cella atomica (~5–50 MB)        |
| Deduplicazione        | A livello file (OSTree)          | A livello chunk (BLAKE3 CAS)    |
| Condivisione librerie | Nello stesso runtime             | Tra tutte le app                |
| Uso librerie host     | Nessuno (sandbox completa)       | Selettivo (ABI compatibile)     |
| Aggiornamenti         | Delta oggetti OSTree             | Delta chunk + riordino          |
| Overhead per app      | ~100 % se runtime diverso        | ~5–15 % (solo differenze)       |

---

## Requisiti

- **Linux** (testato su Debian 12, Fedora 40, Arch attuale)
- **Bash 4+**
- **Go 1.22+** (auto-installato se assente)
- **bubblewrap** (`bwrap`) — auto-installato
- **binutils** (`ldd`, `readelf`) — auto-installato
- **Strumenti di compressione**: `zstd`, `xz`, `gzip` (almeno uno)
- **~500 MB liberi** per build + toolchain se Go viene installato da zero

Famiglie supportate: **Debian/Ubuntu/Mint/Pop**, **Fedora/RHEL/Rocky**,
**Arch/Manjaro/EndeavourOS**, **openSUSE**.

---

## Installazione

```bash
git clone https://github.com/TU_USUARIO/packbox.git
cd packbox
./packbox-installer-v0.1.0.sh
source ~/.bashrc
packbox-diagnose
```

L'installer è interattivo e:

1. Rileva la tua distro e il package manager.
2. Chiede conferma prima di installare le dipendenze
   (`bubblewrap binutils jq bc curl tar`).
3. Installa Go 1.22+ se assente.
4. Crea `~/.packbox/{bin,src}` e
   `~/.local/share/packbox/{store,apps,mods,exports,tmp}`.
5. Genera 11 binari Go + package interni dal codice locale.
6. Compila tutto (~2–3 minuti su hardware moderno).
7. Aggiunge `~/.packbox/bin` al `PATH` e crea symlink in `~/.local/bin`.
8. Verifica che tutti gli 11 binari siano presenti.

**Lingue**: l'installer chiede una delle 9 locale all'avvio — English,
Español, Français, Deutsch, Italiano, 简体中文, 繁體中文, 日本語, 한국어.

### Disinstallazione

Esegui lo stesso script e scegli l'opzione `2`:

- Modalità `s` → rimozione completa (binari + app + store + menu + config)
- Modalità `k` → solo binari (mantiene app e store)
- Modalità `q` → annulla

Richiede di digitare `DELETE` per confermare.

---

## Avvio rapido

### Packager interattivo (consigliato)

```bash
./packbox-packager-v0.1.0.sh
```

Menu: impacchetta, elenca, gc, esporta, importa, disinstalla.

### Riga di comando

```bash
# 1. Impacchetta una directory in chunk CAS + manifest.json
packbox-pack ./firefox-tree \
    --name org.mozilla.firefox \
    --version 128.0 \
    --description "Mozilla Firefox" \
    --gui --toolkit GTK3

# 2. Installa dal manifest generato
packbox-install ./firefox-tree/manifest.json

# 3. Esegui in una sandbox bwrap (con fix DNS + GUI)
packbox-run org.mozilla.firefox

# 4. Vedi cosa è installato
packbox-list

# 5. Disinstalla e libera i chunk
packbox-remove org.mozilla.firefox
packbox-gc
```

---

## Comandi

Undici binari Go, tutti in `~/.packbox/bin/`:

| Comando             | Scopo                                                       |
|---------------------|-------------------------------------------------------------|
| `packbox-pack`      | Hasha una directory in chunk CAS + `manifest.json`          |
| `packbox-install`   | Installa dal manifest (hardlink dal CAS)                    |
| `packbox-run`       | Esegui dentro `bwrap` con DNS + GUI                         |
| `packbox-list`      | Elenca app installate con versione e tag                    |
| `packbox-remove`    | Disinstalla e rilascia i riferimenti CAS                    |
| `packbox-gc`        | Raccogli chunk orfani                                       |
| `packbox-verify`    | Verifica compatibilità librerie via `ldd`                   |
| `packbox-export`    | Esporta app in `.pbox` (zstd/xz/gzip)                       |
| `packbox-import`    | Importa `.pbox` con validazione anti path-traversal         |
| `packbox-module`    | Gestisci moduli di librerie condivise (`list`, `create`)    |
| `packbox-diagnose`  | Stampa un report dell'ambiente per bug report               |

Riferimento completo con opzioni, exit code ed esempi:
[`commands.md`](commands.md) · [EN](../en/commands.md) · [ES](../es/commands.md)

### Script interattivi

- `packbox-installer-v0.1.0.sh` — installa / disinstalla
- `packbox-packager-v0.1.0.sh` — impacchetta, elenca, gc, esporta, importa, disinstalla
- `packbox-i18n.sh` — livello di traduzione condiviso

---

## Struttura del filesystem

```
~/.packbox/                     # Installazione (binari + sorgente Go)
├── bin/                        # 11 binari Go
└── src/                        # Sorgente del modulo Go

~/.local/share/packbox/         # Dati
├── store/                      # CAS — chunk per hash BLAKE3
│   └── <ab>/<hash-completo>    # più un file .refs per chunk
├── apps/                       # App installate (tree + manifest.json)
├── mods/                       # Moduli di librerie condivise
├── exports/                    # Archivi .pbox
└── tmp/                        # Spazio di lavoro temporaneo

~/.config/packbox/lang/         # 9 file di lingua
```

---

## Architettura

Tre parti mobili:

```
┌──────────────┐   pack    ┌──────────────┐   install   ┌──────────────┐
│  Directory   │ ────────► │     CAS      │ ──────────► │  Tree app    │
│  (fs tree)   │           │  (chunk)     │             │ (hardlink)   │
└──────────────┘           └──────────────┘             └──────────────┘
                                  │
                                  │ run
                                  ▼
                         ┌──────────────────┐
                         │  Sandbox bwrap   │
                         │  (fix DNS/GUI)   │
                         └──────────────────┘
```

- **CAS** — `~/.local/share/packbox/store/`, hash BLAKE3, un file `.refs`
  per chunk, `SafeLink` (hardlink → copia di fallback) all'installazione.
- **Manifest** — `schema_version: "1.5"`, `layers.app.files` mappa i
  percorsi relativi a `{chunks, size, mode}`, più `host_contract.delegate`
  per la fiducia nelle librerie dell'host.
- **Sandbox** — `bwrap --unshare-all --share-net`, whitelist env dopo
  `--clearenv`, risoluzione dei symlink DNS (`EvalSymlinks`) prima di
  bindare `/etc/resolv.conf`, supporto GUI (X11, Wayland, D-Bus, `/dev/dri`,
  cache fontconfig), mappa euristica dei dati per app con `--bind-try`.

Architettura completa (internals del CAS, schema del manifest, mount della
sandbox, host contract): [`architecture.md`](../en/architecture.md) ·
[ES](../es/architecture.md)

---

## Sicurezza

> [!WARNING]
> Gli archivi `.pbox` **non sono firmati** in v0.1.0 Alpha. Tratta qualsiasi
> archivio importato come non affidabile. La verifica delle firme è nella
> roadmap.

Mitigazioni già implementate:

- **Protezione anti path-traversal** — `cas.isValidHash()` impone 64
  caratteri hex minuscoli. L'import `.pbox` valida ogni voce tar contro la
  radice di estrazione via `security.ValidatePath`.
- **Import sicuro rispetto ai symlink** — solo `tar.TypeDir` e `tar.TypeReg`
  sono gestiti; symlink, hardlink e file di dispositivo vengono saltati
  silenziosamente.
- **Pulizia dell'ambiente** — `--clearenv` seguito da una whitelist
  esplicita blocca l'iniezione di `LD_PRELOAD` / `LD_LIBRARY_PATH`.
- **Isolamento di XAUTHORITY** — il `~/.Xauthority` dell'host viene copiato
  in un file temporaneo per processo (`/tmp/packbox-xauth-<pid>`, modo 0600)
  prima di essere bindato nella sandbox.
- **Reference counting** — ogni chunk ha un file `.refs`; `packbox-gc`
  elimina solo chunk non referenziati.
- **Niente setuid, niente root** — Packbox gira interamente come l'utente
  chiamante. `sudo` è usato solo dall'installer.

Limitazioni note e modello di minaccia:
[`security.md`](../en/security.md) · [ES](../es/security.md)

Segnala vulnerabilità con l'output di `packbox-diagnose` allegato. Per
scoperte sensibili, usa il contatto privato di sicurezza.

---

## Roadmap

### v0.1.x — Stabilizzazione
- [ ] Verifica delle firme per archivi `.pbox`
- [ ] Politica di rete per app (`--share-net` è attualmente globale)
- [ ] Implementare `packbox-module remove` e `info`
- [ ] Stress test di `host_contract.delegate` su app reali GTK4/Qt6
- [ ] CI: `shellcheck`, `gofmt`, `go vet` a ogni PR
- [ ] Matrice test: Debian 12, Fedora 40, Arch, openSUSE Tumbleweed

### v0.2 — Portata
- [ ] Binari precompilati per x86_64 e aarch64 (pagina releases)
- [ ] `packbox-update` per aggiornamenti in place
- [ ] Frontend GUI (opzionale, GTK4)
- [ ] Download delta a livello di chunk per `packbox-export`

### Più avanti
- [ ] Importatore di runtime Flatpak (best-effort)
- [ ] Verifica delle firme via minisign o sigstore
- [ ] Sandbox WASM opzionale per plugin non affidabili

---

## Documentazione

Documentazione completa in 9 lingue. Inglese e spagnolo hanno il set
completo (README + comandi + architettura + sicurezza); gli altri sette
hanno README + comandi.

| Lingua   | README                                 | Comandi                                         | Architettura                                        | Sicurezza                                     |
|----------|----------------------------------------|-------------------------------------------------|-----------------------------------------------------|-----------------------------------------------|
| English  | [en](../en/README.md)                  | [en](../en/commands.md)                         | [en](../en/architecture.md)                         | [en](../en/security.md)                       |
| Español  | [es](../es/README.md)                  | [es](../es/commands.md)                         | [es](../es/architecture.md)                         | [es](../es/security.md)                       |
| Français | [fr](../fr/README.md)                  | [fr](../fr/commands.md)                         | —                                                   | —                                             |
| Deutsch  | [de](../de/README.md)                  | [de](../de/commands.md)                         | —                                                   | —                                             |
| Italiano | **it**                                 | [it](commands.md)                               | —                                                   | —                                             |
| 简体中文 | [zh-CN](../zh-CN/README.md)            | [zh-CN](../zh-CN/commands.md)                   | —                                                   | —                                             |
| 繁體中文 | [zh-TW](../zh-TW/README.md)            | [zh-TW](../zh-TW/commands.md)                   | —                                                   | —                                             |
| 日本語   | [ja](../ja/README.md)                  | [ja](../ja/commands.md)                         | —                                                   | —                                             |
| 한국어   | [ko](../ko/README.md)                  | [ko](../ko/commands.md)                         | —                                                   | —                                             |

Indice: [`docs/README.md`](../README.md)

---

## Contribuire

Contributi benvenuti, specialmente:

- **Traduzioni** — aggiungi una nuova locale a `packbox-i18n.sh` copiando
  il blocco `en` in `install_lang_files()` e traducendo ogni chiave `L_*`.
- **Profili sandbox** — mappe dati per app per browser, IDE, giochi.
- **Strategie di chunking del CAS** — varianti rolling hash, chunking
  parallelo.
- **Bug report** — includi sempre l'output di `packbox-diagnose`.

Per iniziare:

```bash
git clone https://github.com/TU_USUARIO/packbox.git
cd packbox
# Leggi CONTRIBUTING.md per le linee guida complete
```

- 🐛 [Apri un issue](https://github.com/TU_USUARIO/packbox/issues)
- 💬 [Avvia una discussione](https://github.com/TU_USUARIO/packbox/discussions)
- 🔧 [CONTRIBUTING.md](../../CONTRIBUTING.md)

Esegui `shellcheck` sugli script shell e `gofmt` + `go vet` sul codice Go
prima di inviare una PR.

---

## Licenza

[MIT](../../LICENSE) © 2025 TU_NOMBRE

Packbox è libero di usare, modificare e ridistribuire. Vedi
[LICENSE](../../LICENSE) per i dettagli.

---

## Ringraziamenti

- **[bubblewrap](https://github.com/containers/bubblewrap)** — la primitiva
  di sandbox che rende possibile `packbox-run`.
- **[BLAKE3](https://github.com/BLAKE3-team/BLAKE3)** — content-addressing
  veloce e sicuro.
- **[Flatpak](https://flatpak.org/)** — il progetto che ha dimostrato che le
  app Linux sandboxate funzionano su larga scala, e le cui decisioni di
  design hanno informato molte delle nostre (anche dove divergiamo).
- Il livello i18n a 9 lingue esiste perché la comunità Linux è globale;
  grazie a tutti coloro che hanno revisionato le traduzioni.
