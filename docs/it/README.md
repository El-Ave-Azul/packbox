# Packbox

[Español](../../README.md) · [English](../en/README.md) · [Français](../fr/README.md) · [Deutsch](../de/README.md) · **[Italiano](README.md)** · [Português](../pt/README.md) · [中文](../zh/README.md) · [日本語](../ja/README.md) · [한국어](../ko/README.md)

---

![Licenza](https://img.shields.io/badge/Licenza-Apache_2.0-blue.svg)
![Versione](https://img.shields.io/badge/Versione-0.1.1-orange.svg)
![Piattaforma](https://img.shields.io/badge/Piattaforma-Linux-blue.svg)
![Go](https://img.shields.io/badge/Go-1.22+-00ADD8.svg?logo=go&logoColor=white)
![i18n](https://img.shields.io/badge/i18n-9_lingue-green.svg)
![Stato](https://img.shields.io/badge/Stato-Alpha-red.svg)

**Impacchettatore di applicazioni Linux con deduplicazione binaria per chunk.**
Ispirato a Flatpak, ma con un modello di riuso diverso: invece di un
runtime monolitico per app, Packbox conserva il contenuto in un archivio
indirizzato per contenuto (BLAKE3 CAS), con **chunking definito dal contenuto
(CDC)** e **celle** riutilizzabili. Due app che condividono il 90 % delle loro
librerie memorizzano solo il 10 % che differisce.

> [!WARNING]
> **Stato Alpha (v0.1.1).** I flussi principali funzionano e ci sono già firme,
> sandbox rafforzata (seccomp, D-Bus filtrato, HOME privata) e remoto HTTP, ma
> il progetto è giovane e non ha l'ecosistema né la maturità di Flatpak. Usalo
> prima su sistemi non critici.

---

## Indice

- [Che cos'è Packbox?](#che-cosè-packbox)
- [Confronto con Flatpak](#confronto-con-flatpak)
- [Requisiti](#requisiti)
- [Installazione](#installazione)
- [Uso rapido](#uso-rapido)
- [Comandi disponibili](#comandi-disponibili)
- [Struttura dei file](#struttura-dei-file)
- [Architettura](#architettura)
- [Sicurezza](#sicurezza)
- [Roadmap](#roadmap)
- [Contribuire](#contribuire)
- [Licenza](#licenza)
- [Ringraziamenti](#ringraziamenti)

---

## Che cos'è Packbox?

Packbox impacchetta applicazioni Linux usando **Content-Addressable Storage (CAS)**
con hashing **BLAKE3** e **chunking per contenuto**, per ottenere una deduplicazione
binaria reale tra le app.

Invece di un runtime di ~1 GB per applicazione (Flatpak), Packbox conserva ogni
file come chunk indirizzati per contenuto e lo condivide tra tutte le
app. Inoltre converte ogni libreria in una **cella** (un'unità di riuso
versionata) che varie app condividono, e lascia le librerie universali
(`libc`, `libm`, …) all'host.

### Principi di progettazione

- **Deduplicazione a livello di chunk.** Stessi byte = stesso hash = memorizzato una
  volta (CDC nei file grandi; file unico in quelli piccoli, per poterli
  hardlinkare e condividere).
- **Celle (frammentazione atomica).** Ogni lib non universale è una cella;
  l'app la dichiara e l'installer la risolve.
- **Condivisione incrociata.** Tutte le app condividono lo stesso CAS globale e le
  stesse celle.
- **Host contract v1.** Delega selettiva delle librerie universali, con
  **controllo ABI** dei simboli richiesti.
- **Sandbox rafforzata (bubblewrap).** `--unshare-all`, `--cap-drop ALL`,
  **seccomp**, **D-Bus filtrato** (`xdg-dbus-proxy`), **HOME privata per app**,
  rete opt-in e **X11 opt-in con rilevamento automatico**.
- **Livello per overlay.** `/app` è composto come overlay di A (app) su C
  (celle), con S (host) tramite `/usr`.
- **Firme e distribuzione.** `.pbox` firmabili (ed25519) e remoto HTTP con
  download delta.
- **4 modalità di impacchettamento.** Normal, Portable, Bundle, Module.

---

## Confronto con Flatpak

| Caratteristica       | Flatpak (attuale)           | Packbox v0.1.1                       |
|----------------------|-----------------------------|--------------------------------------|
| Unità di riuso       | Runtime completo (~1 GB)    | **Celle** per lib (senza runtime)    |
| Deduplicazione       | A livello di file (OSTree)  | A livello di **chunk** (BLAKE3 + CDC) |
| Condivisione di lib  | Dentro lo stesso runtime    | Incrociata tra tutte le app          |
| Uso di lib dell'host | Nessuno                     | Selettivo (host contract + ABI)      |
| Aggiornamenti        | Delta di oggetti OSTree     | `packbox-update` (delta di chunk + GC) |
| Distribuzione        | Flathub + remoti OSTree     | Remoto HTTP con `publish`/`fetch`    |
| Firme                | GPG                         | ed25519 (`.pbox.sig`)                |
| Sandbox              | bwrap + seccomp + portali   | bwrap + seccomp + dbus-proxy + portali |
| Overhead per app     | ~100 % se runtime diverso   | **~5–15 %** con app che condividono  |

**Risparmio misurato** (questa base di codice): due app GTK4 medie che condividono il
loro stack sommano ~264 MB separatamente e occupano **~141 MB reali (−46 %)**; con 10
app miste il risparmio sale a **~69 %**. Più grande è la sovrapposizione di
librerie, maggiore è il risparmio — ma conviene misurarlo caso per caso, non assumere il 90–99 %
di un runtime condiviso.

---

## Requisiti

- **Sistema operativo**: Linux (Debian 12+, Ubuntu 22.04+, Fedora 40+, Arch,
  openSUSE Tumbleweed)
- **Kernel**: 5.15+ con user namespaces abilitati
- **Shell**: Bash 4.0+
- **Go**: 1.22+ (l'installer scarica una propria copia se manca)
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

L'installer apre un menu; scegli l'opzione **1** (Installa).

### Passo 2 — Ricaricare la shell

```bash
source ~/.bashrc
```

### Passo 3 — Verificare

```bash
packbox-diagnose
```

### Che cosa fa l'installer

1. Ti permette di selezionare una di 9 lingue.
2. Rileva la tua distribuzione Linux e il gestore di pacchetti.
3. Chiede conferma prima di installare le dipendenze.
4. Scarica e verifica Go (per impostazione predefinita 1.27.1) in `~/.packbox/go` se serve.
5. Crea la struttura di directory (`~/.packbox/` e `~/.local/share/packbox/`).
6. Copia i sorgenti e compila i **15 binari** Go (~1–2 minuti).
7. Configura il tuo `PATH` in `~/.bashrc` e crea i symlink in `~/.local/bin`.
8. Installa i file di lingua in `~/.config/packbox/lang/`.
9. Verifica che tutti i binari siano presenti e funzionanti.

### Disinstallazione

Esegui lo stesso script e scegli l'opzione **2**:

```bash
./packbox-install.sh --uninstall
```

| Modalità | Descrizione |
|------|-------------|
| `s`  | Completa: binari + app + store CAS + celle + menu + icone + config |
| `k`  | Solo binari: `~/.packbox/` e symlink (conserva app e store CAS) |
| `q`  | Annulla |

---

## Uso rapido

### 1. Impacchettatore interattivo (consigliato)

```bash
./packbox-packager.sh
```

Menu: impacchettare, elencare, garbage collection, esportare, importare, disinstallare,
lingua. Rileva app dai `.desktop` in `/usr/share/applications/`, bundle in
`/opt/*` e binari comuni (`htop`, `btop`, `firefox`, `gimp`, …).

Nelle modalità **Normal** e **Portable** ogni lib non universale della chiusura `ldd`
diventa automaticamente una **cella**.

### 2. Riga di comando

```bash
# Impacchettare una directory
packbox-pack ./mi-app --name org.ejemplo.miapp --version 1.0.0

# Installare dal manifesto generato
packbox-install ./mi-app/manifest.json

# Eseguire nella sandbox (overlay A su C; HOME privata)
packbox-run org.ejemplo.miapp

# Elencare le app (dimensione reale e risparmio per sharing) e liberare spazio
packbox-list
packbox-remove org.ejemplo.miapp
packbox-gc

# Aggiornare un'app installata riusando i chunk dello store
packbox-update org.ejemplo.miapp ./nuevo/manifest.json
```

### 3. Esportare, firmare, importare e distribuire

```bash
# Esportare e firmare
packbox-sign keygen                       # crea la tua chiave (e la considera attendibile)
packbox-export --sign app org.ejemplo.miapp
packbox-sign verify ~/.local/share/packbox/exports/org.ejemplo.miapp.pbox

# Pubblicare un remoto HTTP e usarlo da un'altra macchina
packbox-fetch publish org.ejemplo.miapp /srv/packbox
(cd /srv/packbox && python3 -m http.server 8000)
packbox-fetch fetch org.ejemplo.miapp --from http://host:8000

# Importare (verifica la firma se esiste)
packbox-import app org.ejemplo.miapp.pbox
```

---

## Comandi disponibili

Packbox v0.1.1 include **15 binari Go** in `~/.packbox/bin/`:

| Comando            | Scopo                                                              |
|--------------------|--------------------------------------------------------------------|
| `packbox-pack`     | Fa l'hash di una directory in chunk CAS e genera `manifest.json`   |
| `packbox-install`  | Installa un'app dal manifesto (+ `--desktop`/`--remove-desktop`)   |
| `packbox-run`      | Esegue l'app nella sandbox `bwrap` (overlay A/C, HOME privata)     |
| `packbox-list`     | Elenca le app con la loro **dimensione reale** e il risparmio per sharing (`--tsv`) |
| `packbox-remove`   | Disinstalla un'app e libera i suoi riferimenti CAS                 |
| `packbox-gc`       | Raccoglie chunk **e celle** senza riferimenti                      |
| `packbox-verify`   | Controlla lib risolvibili + **compatibilità ABI** dell'host         |
| `packbox-export`   | Esporta in `.pbox` con **compressione adattiva** e `--sign` opzionale |
| `packbox-import`   | Importa un `.pbox` (anti tar-slip, traversal e firme)              |
| `packbox-update`   | Aggiorna un'app riusando i chunk + report delta (`--no-gc`)        |
| `packbox-module`   | Moduli/celle: `list`, `create`, `cell <lib>...`                    |
| `packbox-sign`     | Chiavi e firme ed25519: `keygen`, `sign`, `verify`, `trust`        |
| `packbox-fetch`    | Remoto HTTP: `publish <id> <dir>` e `fetch <id> --from <url>`      |
| `packbox-debug`    | Allega i simboli di debug (cella separata) di un'app installata    |
| `packbox-diagnose` | Report dell'ambiente per le segnalazioni di bug                    |

---

## Struttura dei file

```
~/.packbox/                              # Installazione
├── bin/                                 # 15 binari Go compilati
└── src/                                 # Codice sorgente Go

~/.local/share/packbox/                  # Dati utente
├── store/                               # CAS: chunk per hash BLAKE3
│   └── <ab>/<hash-completo>             # + file .refs per chunk
├── apps/                                # App installate
│   └── <app-id>/
│       ├── manifest.json
│       ├── tree/                        # Hardlink al CAS (livello A)
│       └── home/                        # HOME privata (creata al primo run)
├── mods/                                # Celle (org.lib.*, org.debug.*)
├── exports/                             # File .pbox (+ .sig)
└── tmp/                                 # Temporanei

~/.config/packbox/
├── lang/                                # 9 file di lingua
├── signing.key / signing.pub            # la tua chiave di firma
└── trusted/                             # chiavi pubbliche attendibili
```

---

## Architettura

### Flusso di impacchettamento

```
┌──────────────┐   pack    ┌──────────────┐  install  ┌──────────────┐
│  Dir sorgente│ ────────► │     CAS      │ ─────────► │ Tree dell'app│
│  (albero fs) │           │  (chunks)    │           │ (hardlinks)  │
└──────────────┘           └──────────────┘           └──────┬───────┘
                                  │                          │ + celle (livello C)
                                  │ run                      ▼
                         ┌──────────────────────────────────────────┐
                         │ Sandbox bwrap: /app = overlay A su C      │
                         │ HOME privata · seccomp · D-Bus filtrato   │
                         └──────────────────────────────────────────┘
```

### Componenti interni

- **CAS + chunker** — Conserva i chunk per hash **BLAKE3**. I file grandi vengono
  divisi con **CDC** (hash rolling tipo *gear*); quelli piccoli vanno come un solo
  chunk (hardlinkabili, per condividere). Scritture **atomiche** (temp+rename).
- **Manifesto** (`schema_version: "1.6"`) — Mappa i percorsi ai chunk, elenca le
  **celle** (`mods`), l'`host_contract` (delegate + required_symbols), il
  simbolo X11 e, se applicabile, la cella di **debug**.
- **Celle** — Una lib = una cella `org.lib.<soname>@<hash>` in `mods/`.
  Condivise tra le app. `packbox-gc` elimina quelle non referenziate.
- **Sandbox** — `bwrap --unshare-all --cap-drop ALL --clearenv`, **seccomp**
  (blocca ptrace/bpf/keyring/io_uring/moduli…), **D-Bus filtrato** con
  `xdg-dbus-proxy` (portali + dconf), **HOME privata** (`apps/<id>/home`), rete
  **opt-in** e **X11 opt-in** (per impostazione predefinita Wayland + portali; si attiva solo se
  il manifesto lo richiede o se la sessione è solo-X11).
- **Overlay di livelli** — `/app` viene composto con `--overlay-src` (C sotto, A
  sopra); S (host) arriva tramite `/usr`. Evita di copiare le celle in ogni albero.
- **Host contract** — `packbox-verify` controlla che l'host fornisca i simboli
  richiesti (ABI).
- **Firme e remoto** — `packbox-sign` (ed25519) firma il `.pbox`;
  `packbox-fetch` pubblica e scarica solo il delta (chunk + celle).

### Come funziona la deduplicazione

```
App 1: htop     → chunk: [A, B, C]
App 2: neofetch → chunk: [A, D, E]
App 3: btop     → chunk: [A, B, F]

CAS Store:
  A → riferimenti: htop, neofetch, btop      (3 app)
  B → riferimenti: htop, btop                (2 app)
  C → htop · D → neofetch · E → neofetch · F → btop

Totale: 6 chunk unici invece di 9.
```

---

## Sicurezza

### Mitigazioni implementate

- **Isolamento dei dati per app** — Ogni app gira con la sua **HOME privata**
  (`apps/<id>/home`); vengono esposti solo font/temi in **sola lettura**. Non vede
  né tocca la tua configurazione reale.
- **D-Bus filtrato** — `xdg-dbus-proxy` con lista bianca (per impostazione predefinita, portali
  e `dconf`; il bus di sistema, niente). L'app non parla con il bus reale.
- **seccomp** — Filtro predefinito che blocca la superficie pericolosa del kernel
  (ptrace, bpf, keyring, io_uring, userfaultfd, moduli, reboot/swap…).
- **X11 opt-in** — Per impostazione predefinita Wayland + `xdg-desktop-portal` (esponendo il
  mount dei documenti del portale); X11 viene abilitato con il flag `x11` del
  manifesto o automaticamente se la sessione dell'host è solo X11.
- **Anti tar-slip / traversal** — L'estrazione `.pbox` valida ogni voce
  (`safeJoin` + `O_NOFOLLOW` + destinazioni dei symlink) e rifiuta `name`/percorsi che
  escano dalla directory dell'app.
- **Pulizia dell'ambiente** — `--clearenv` + whitelist esplicita: blocca
  `LD_PRELOAD`/`LD_LIBRARY_PATH` iniettati dall'host.
- **Senza setuid, senza root** — Tutto gira come il tuo utente; `sudo` solo per le
  dipendenze di sistema durante l'installazione.
- **Reference counting + GC** — Ogni chunk ha un file `.refs`; `packbox-gc` elimina
  solo ciò che non è referenziato (chunk **e celle**).
- **Firme** — `.pbox` firmabili con **ed25519**; `import` verifica e **rifiuta**
  pacchetti alterati o di firmatari non attendibili.
- **Integrità del CAS** — Hash validati prima di essere usati come percorso;
  scritture atomiche.

### Limitazioni note (v0.1.1 Alpha)

> [!WARNING]
> Aree in cui il feedback è più gradito.

- ⚠️ **Portali parziali.** È consentito parlare con i portali e viene esposto il
  mount dei documenti, ma i portali non sono ancora usati per tutto (fotocamera,
  appunti, ecc.).
- ⚠️ **`packbox-module remove`/`info`** restano non implementati (esiste invece
  `cell`).
- ⚠️ **Compressione adattiva** a livello di pacchetto, non per voce (il formato è
  tar + un compressore).
- ⚠️ **Senza catalogo.** Il remoto HTTP serve dati, non fiducia né un indice
  pubblico.

---

## Roadmap

### v0.1.x — Stabilizzazione

- [x] Verifica delle firme per `.pbox` (ed25519 + gestione delle chiavi)
- [x] Sandbox rafforzata: HOME privata, D-Bus filtrato, seccomp
- [x] Celle automatiche + overlay di livelli (A/C/S)
- [x] `packbox-update` con delta di chunk + GC automatico
- [x] Remoto HTTP (`publish`/`fetch`) con download delta
- [x] Simboli di debug separati (`cell-debug`)
- [x] Compressione adattiva in `export`
- [x] Test di integrazione end-to-end (`tests/integration.sh`)
- [ ] Politica di rete per applicazione
- [ ] Portali completi (file, fotocamera, appunti)
- [ ] CI/CD: `shellcheck`, `gofmt`, `go vet` a ogni PR
- [ ] Matrice di test: Debian 12, Fedora 40, Arch, openSUSE Tumbleweed

### v0.2 — Ambito

- [ ] Binari precompilati x86_64 e aarch64 (pagina delle release)
- [ ] Indice/repository centrale firmato (`search`/`install` da remoto)
- [ ] Frontend GUI opzionale (GTK4)

### Futuro

- [ ] Importatore di runtime Flatpak (best-effort)
- [ ] Sandbox WASM per plugin non attendibili

---

## Contribuire

Contributi benvenuti! Aree in cui l'aiuto è particolarmente utile:

- **Traduzioni** — Aggiungi un locale copiando un blocco esistente in
  `i18n/` e traducendo ogni chiave `L_*`.
- **Portali** — Integrare `xdg-desktop-portal` per l'accesso ai file.
- **Chunking / dedup** — Migliorare il CDC e la politica di soglia.
- **Segnalazioni di bug** — Includi sempre l'output di `packbox-diagnose`.

### Come iniziare

```bash
git clone https://github.com/El-Ave-Azul/packbox.git
cd packbox
cd src && go test ./...     # unit test
bash tests/integration.sh   # end-to-end (pack → export → import → run)
```

- 🐛 [Aprire una issue](https://github.com/El-Ave-Azul/packbox/issues)
- 💬 [Avviare una discussione](https://github.com/El-Ave-Azul/packbox/discussions)

> [!TIP]
> Passa `shellcheck` agli script bash e `gofmt` + `go vet` a Go prima di
> inviare una PR.

---

## Licenza

Distribuito sotto la **Apache License 2.0**. Vedi [LICENSE](../../LICENSE).

Apache 2.0 apporta una **clausola esplicita di concessione dei brevetti**, che
protegge utenti e contributori da contenziosi sulle tecniche di
deduplicazione e sandboxing, ed è compatibile con GPLv3.

---

## Ringraziamenti

- **[bubblewrap](https://github.com/containers/bubblewrap)** — Primitive di
  sandbox Linux che rendono possibile `packbox-run`.
- **[BLAKE3](https://github.com/BLAKE3-team/BLAKE3)** — Hashing del contenuto
  veloce e crittograficamente sicuro.
- **[xdg-desktop-portal](https://flatpak.github.io/xdg-desktop-portal/)** e
  **xdg-dbus-proxy** — Accesso mediato ai file e filtraggio di D-Bus.
- **[Flatpak](https://flatpak.org/)** — Ha dimostrato che le app Linux
  in sandbox funzionano su larga scala; molte delle sue decisioni hanno informato le
  nostre, anche dove divergiamo.
- **Comunità Linux globale** — Il livello i18n di 9 lingue esiste grazie alle sue
  revisioni e ai suoi contributi.
