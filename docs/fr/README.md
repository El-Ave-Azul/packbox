# Packbox

[Español](../../README.md) · [English](../en/README.md) · **[Français](README.md)** · [Deutsch](../de/README.md) · [Italiano](../it/README.md) · [Português](../pt/README.md) · [中文](../zh/README.md) · [日本語](../ja/README.md) · [한국어](../ko/README.md)

---

![Licence](https://img.shields.io/badge/Licencia-Apache_2.0-blue.svg)
![Version](https://img.shields.io/badge/Versión-0.2.0-orange.svg)
![Plateforme](https://img.shields.io/badge/Plataforma-Linux-blue.svg)
![Go](https://img.shields.io/badge/Go-1.22+-00ADD8.svg?logo=go&logoColor=white)
![i18n](https://img.shields.io/badge/i18n-9_idiomas-green.svg)
![État](https://img.shields.io/badge/Estado-Alpha-red.svg)

**Empaqueteur d'applications Linux avec déduplication binaire par chunk.**
Inspiré de Flatpak, mais avec un modèle de réutilisation différent : au lieu d'un
runtime monolithique par application, Packbox stocke le contenu dans un magasin
adressé par contenu (BLAKE3 CAS), avec un **chunking défini par le contenu
(CDC)** et des **cellules** réutilisables. Deux applications qui partagent 90 % de
leurs bibliothèques ne stockent que les 10 % qui diffèrent.

> [!WARNING]
> **État Alpha (v0.2.0).** Les flux principaux fonctionnent et il existe déjà des
> signatures, un sandbox renforcé (seccomp, D-Bus filtré, HOME privé) et un
> remote HTTP, mais le projet est jeune et n'a ni l'écosystème ni la maturité de
> Flatpak. Utilisez-le d'abord sur des systèmes non critiques.

---

## Table des matières

- [Qu'est-ce que Packbox ?](#quest-ce-que-packbox)
- [Comparaison avec Flatpak](#comparaison-avec-flatpak)
- [Prérequis](#prérequis)
- [Installation](#installation)
- [Utilisation rapide](#utilisation-rapide)
- [Commandes disponibles](#commandes-disponibles)
- [Structure des fichiers](#structure-des-fichiers)
- [Architecture](#architecture)
- [Sécurité](#sécurité)
- [Feuille de route](#feuille-de-route)
- [Contribuer](#contribuer)
- [Licence](#licence)
- [Remerciements](#remerciements)

---

## Qu'est-ce que Packbox ?

Packbox empaquette des applications Linux en utilisant un **Content-Addressable
Storage (CAS)** avec hachage **BLAKE3** et **chunking par contenu**, afin
d'obtenir une véritable déduplication binaire entre les applications.

Au lieu d'un runtime d'environ 1 GB par application (Flatpak), Packbox stocke
chaque fichier sous forme de chunks adressés par contenu et le partage entre
toutes les applications. De plus, il convertit chaque bibliothèque en une
**cellule** (une unité de réutilisation versionnée) que plusieurs applications
partagent, et laisse les bibliothèques universelles (`libc`, `libm`, …) à l'hôte.

### Principes de conception

- **Déduplication au niveau du chunk.** Mêmes octets = même hash = stocké une
  seule fois (CDC pour les fichiers volumineux ; fichier unique pour les petits,
  afin de pouvoir créer des hardlinks et partager).
- **Cellules (fragmentation atomique).** Chaque bibliothèque non universelle est
  une cellule ; l'application la déclare et l'installeur la résout.
- **Partage croisé.** Toutes les applications partagent le même CAS global et les
  mêmes cellules.
- **Host contract v1.** Délégation sélective des bibliothèques universelles, avec
  **vérification ABI** des symboles requis.
- **Sandbox renforcé (bubblewrap).** `--unshare-all`, `--cap-drop ALL`,
  **seccomp**, **D-Bus filtré** (`xdg-dbus-proxy`), **HOME privé par
  application**, réseau opt-in et **X11 opt-in avec auto-détection**.
- **Couche par overlay.** `/app` est composé comme un overlay de A (application)
  sur C (cellules), avec S (hôte) via `/usr`.
- **Signatures et distribution.** `.pbox` signables (ed25519) et remote HTTP avec
  téléchargement delta.
- **4 modes d'empaquetage.** Normal, Portable, Bundle, Module.

---

## Comparaison avec Flatpak

| Caractéristique          | Flatpak (actuel)            | Packbox v0.2.0                       |
|--------------------------|-----------------------------|--------------------------------------|
| Unité de réutilisation   | Runtime complet (~1 GB)     | **Cellules** par lib (sans runtimes) |
| Déduplication            | Au niveau du fichier (OSTree) | Au niveau du **chunk** (BLAKE3 + CDC) |
| Partage des libs         | Au sein du même runtime     | Croisé entre toutes les applications  |
| Utilisation des libs de l'hôte | Aucune               | Sélective (host contract + ABI)      |
| Mises à jour             | Delta d'objets OSTree       | `packbox-update` (delta de chunks + GC) |
| Distribution             | Flathub + remotes OSTree    | Remote HTTP avec `publish`/`fetch`   |
| Signatures               | GPG                         | ed25519 (`.pbox.sig`)                |
| Sandbox                  | bwrap + seccomp + portails  | bwrap + seccomp + dbus-proxy + portails |
| Surcoût par application  | ~100 % si runtime différent | **~5–15 %** avec des applications partagées |

**Économie mesurée** (cette base de code) : deux applications GTK4 moyennes qui
partagent leur pile totalisent ~264 MB séparément et occupent **~141 MB réels
(−46 %)** ; avec 10 applications mixtes, l'économie monte à **~69 %**. Plus le
recouvrement des bibliothèques est important, plus l'économie est grande — mais
il convient de la mesurer au cas par cas, plutôt que de supposer les 90–99 %
d'un runtime partagé.

---

## Prérequis

- **Système d'exploitation** : Linux (Debian 12+, Ubuntu 22.04+, Fedora 40+,
  Arch, openSUSE Tumbleweed)
- **Kernel** : 5.15+ avec les user namespaces activés
- **Shell** : Bash 4.0+
- **Go** : 1.22+ (l'installeur télécharge sa propre copie si elle manque)
- **Espace** : ~500 MB libres pour la compilation initiale
- **Internet** : uniquement pour la première installation

### Dépendances du système

Installées par l'installeur lorsque c'est possible ; utiles aussi manuellement :

`bubblewrap` · `binutils` (`ldd`/`readelf`) · `jq` · `bc` · `curl` · `tar` ·
`xdg-dbus-proxy` (filtrage de D-Bus) · `zstd` ou `xz` (export plus compact)

---

## Installation

### Étape 1 — Cloner et exécuter

```bash
git clone https://github.com/El-Ave-Azul/packbox.git
cd packbox
./packbox-install.sh
```

L'installeur ouvre un menu ; choisissez l'option **1** (Installer).

### Étape 2 — Recharger le shell

```bash
source ~/.bashrc
```

### Étape 3 — Vérifier

```bash
packbox-diagnose
```

### Ce que fait l'installeur

1. Il vous permet de sélectionner l'une des 9 langues.
2. Il détecte votre distribution Linux et votre gestionnaire de paquets.
3. Il demande confirmation avant d'installer les dépendances.
4. Il télécharge et vérifie Go (par défaut 1.27.1) dans `~/.packbox/go` si nécessaire.
5. Il crée l'arborescence de répertoires (`~/.packbox/` et `~/.local/share/packbox/`).
6. Il copie les sources et compile les **15 binaires** Go (~1–2 minutes).
7. Il configure votre `PATH` dans `~/.bashrc` et crée des symlinks dans `~/.local/bin`.
8. Il installe les fichiers de langue dans `~/.config/packbox/lang/`.
9. Il vérifie que tous les binaires sont présents et fonctionnels.

### Désinstallation

Exécutez le même script et choisissez l'option **2** :

```bash
./packbox-install.sh --uninstall
```

| Mode | Description |
|------|-------------|
| `s`  | Complet : binaires + applications + store CAS + cellules + menus + icônes + config |
| `k`  | Binaires uniquement : `~/.packbox/` et symlinks (conserve les applications et le store CAS) |
| `q`  | Annuler |

---

## Utilisation rapide

### 1. Empaqueteur interactif (recommandé)

```bash
./packbox-packager.sh
```

Menu : empaqueter, lister, garbage collection, exporter, importer, désinstaller,
langue. Détecte les applications depuis les `.desktop` dans
`/usr/share/applications/`, les bundles dans `/opt/*` et les binaires courants
(`htop`, `btop`, `firefox`, `gimp`, …).

Dans les modes **Normal** et **Portable**, chaque bibliothèque non universelle de
la fermeture `ldd` devient automatiquement une **cellule**.

### 2. Ligne de commande

```bash
# Empaqueter un répertoire
packbox-pack ./mi-app --name org.ejemplo.miapp --version 1.0.0

# Installer depuis le manifeste généré
packbox-install ./mi-app/manifest.json

# Exécuter dans le sandbox (overlay A sur C ; HOME privé)
packbox-run org.ejemplo.miapp

# Lister les applications (taille réelle et économie par sharing) et libérer de l'espace
packbox-list
packbox-remove org.ejemplo.miapp
packbox-gc

# Mettre à jour une application installée en réutilisant les chunks du store
packbox-update org.ejemplo.miapp ./nuevo/manifest.json
```

### 3. Exporter, signer, importer et distribuer

```bash
# Exporter et signer
packbox-sign keygen                       # crée ta clé (et la rend fiable)
packbox-export --sign app org.ejemplo.miapp
packbox-sign verify ~/.local/share/packbox/exports/org.ejemplo.miapp.pbox

# Publier un remote HTTP et l'utiliser depuis une autre machine
packbox-fetch publish org.ejemplo.miapp /srv/packbox
(cd /srv/packbox && python3 -m http.server 8000)
packbox-fetch fetch org.ejemplo.miapp --from http://host:8000

# Importer (vérifie la signature si elle existe)
packbox-import app org.ejemplo.miapp.pbox
```

---

## Commandes disponibles

Packbox v0.2.0 inclut **15 binaires Go** dans `~/.packbox/bin/` :

| Commande           | Objectif                                                          |
|--------------------|--------------------------------------------------------------------|
| `packbox-pack`     | Hache un répertoire en chunks CAS et génère `manifest.json`        |
| `packbox-install`  | Installe une application depuis le manifeste (+ `--desktop`/`--remove-desktop`) |
| `packbox-run`      | Exécute l'application dans le sandbox `bwrap` (overlay A/C, HOME privé) |
| `packbox-list`     | Liste les applications avec leur **taille réelle** et l'économie par sharing (`--tsv`) |
| `packbox-remove`   | Désinstalle une application et libère ses références CAS           |
| `packbox-gc`       | Collecte les chunks **et les cellules** sans références            |
| `packbox-verify`   | Vérifie les libs résolubles + la **compatibilité ABI** de l'hôte   |
| `packbox-export`   | Exporte vers `.pbox` avec **compression adaptative** et `--sign` optionnel |
| `packbox-import`   | Importe un `.pbox` (anti tar-slip, traversal et signatures)        |
| `packbox-update`   | Met à jour une application en réutilisant les chunks + rapport de delta (`--no-gc`) |
| `packbox-module`   | Modules/cellules : `list`, `create`, `cell <lib>...`               |
| `packbox-sign`     | Clés et signatures ed25519 : `keygen`, `sign`, `verify`, `trust`   |
| `packbox-fetch`    | Remote HTTP : `publish <id> <dir>` et `fetch <id> --from <url>`    |
| `packbox-debug`    | Attache les symboles de debug (cellule à part) d'une application installée |
| `packbox-diagnose` | Rapport de l'environnement pour les rapports de bugs              |

---

## Structure des fichiers

```
~/.packbox/                              # Installation
├── bin/                                 # 15 binaires Go compilés
└── src/                                 # Code source Go

~/.local/share/packbox/                  # Données utilisateur
├── store/                               # CAS : chunks par hash BLAKE3
│   └── <ab>/<hash-completo>             # + fichier .refs par chunk
├── apps/                                # Applications installées
│   └── <app-id>/
│       ├── manifest.json
│       ├── tree/                        # Hardlinks vers le CAS (couche A)
│       └── home/                        # HOME privé (créé au premier run)
├── mods/                                # Cellules (org.lib.*, org.debug.*)
├── exports/                             # Fichiers .pbox (+ .sig)
└── tmp/                                 # Fichiers temporaires

~/.config/packbox/
├── lang/                                # 9 fichiers de langue
├── signing.key / signing.pub            # ta clé de signature
└── trusted/                             # clés publiques de confiance
```

---

## Architecture

### Flux d'empaquetage

```
┌──────────────┐   pack    ┌──────────────┐  install  ┌──────────────┐
│  Dir source  │ ────────► │     CAS      │ ─────────► │ Tree de l'app│
│  (arbre fs)  │           │  (chunks)    │           │ (hardlinks)  │
└──────────────┘           └──────────────┘           └──────┬───────┘
                                  │                          │ + cellules (couche C)
                                  │ run                      ▼
                         ┌──────────────────────────────────────────┐
                         │  Sandbox bwrap: /app = overlay A sur C   │
                         │  HOME privé · seccomp · D-Bus filtré     │
                         └──────────────────────────────────────────┘
```

### Composants internes

- **CAS + chunker** — Stocke les chunks par hash **BLAKE3**. Les fichiers
  volumineux sont découpés avec **CDC** (hash roulant de type *gear*) ; les petits
  passent en un seul chunk (hardlinkables, pour le partage). Écritures
  **atomiques** (temp+rename).
- **Manifeste** (`schema_version: "1.6"`) — Associe les chemins aux chunks, liste
  les **cellules** (`mods`), le `host_contract` (delegate + required_symbols), le
  symbole X11 et, le cas échéant, la cellule de **debug**.
- **Cellules** — Une lib = une cellule `org.lib.<soname>@<hash>` dans `mods/`.
  Partagées entre les applications. `packbox-gc` supprime celles qui ne sont pas
  référencées.
- **Sandbox** — `bwrap --unshare-all --cap-drop ALL --clearenv`, **seccomp**
  (bloque ptrace/bpf/keyring/io_uring/modules…), **D-Bus filtré** avec
  `xdg-dbus-proxy` (portails + dconf), **HOME privé** (`apps/<id>/home`), réseau
  **opt-in** et **X11 opt-in** (par défaut Wayland + portails ; activé uniquement
  si le manifeste le demande ou si la session est X11 uniquement).
- **Overlay de couches** — `/app` est composé avec `--overlay-src` (C en bas, A en
  haut) ; S (hôte) arrive via `/usr`. Évite de copier les cellules dans chaque
  arbre.
- **Host contract** — `packbox-verify` vérifie que l'hôte fournit les symboles
  requis (ABI).
- **Signatures et remote** — `packbox-sign` (ed25519) signe le `.pbox` ;
  `packbox-fetch` publie et télécharge uniquement le delta (chunks + cellules).

### Comment fonctionne la déduplication

```
App 1: htop     → chunks: [A, B, C]
App 2: neofetch → chunks: [A, D, E]
App 3: btop     → chunks: [A, B, F]

CAS Store:
  A → références: htop, neofetch, btop      (3 apps)
  B → références: htop, btop                (2 apps)
  C → htop · D → neofetch · E → neofetch · F → btop

Total: 6 chunks uniques au lieu de 9.
```

---

## Sécurité

### Mesures implémentées

- **Isolation des données par application** — Chaque application s'exécute avec
  son **HOME privé** (`apps/<id>/home`) ; seules les polices/thèmes sont exposés
  en **lecture seule**. Elle ne voit ni ne touche votre configuration réelle.
- **D-Bus filtré** — `xdg-dbus-proxy` avec liste blanche (par défaut, les portails
  et `dconf` ; le bus système, rien). L'application ne parle pas au bus réel.
- **seccomp** — Filtre par défaut qui bloque la surface dangereuse du noyau
  (ptrace, bpf, keyring, io_uring, userfaultfd, modules, reboot/swap…).
- **X11 opt-in** — Par défaut Wayland + `xdg-desktop-portal` (en exposant le
  montage de documents du portail) ; X11 est activé avec le flag `x11` du
  manifeste ou automatiquement si la session de l'hôte est X11 uniquement.
- **Anti tar-slip / traversal** — L'extraction `.pbox` valide chaque entrée
  (`safeJoin` + `O_NOFOLLOW` + destinations de symlink) et rejette les `name`/chemins
  qui s'échappent du répertoire de l'application.
- **Nettoyage de l'environnement** — `--clearenv` + liste blanche explicite :
  bloque les `LD_PRELOAD`/`LD_LIBRARY_PATH` injectés depuis l'hôte.
- **Sans setuid, sans root** — Tout s'exécute avec votre utilisateur ; `sudo`
  uniquement pour les dépendances du système à l'installation.
- **Reference counting + GC** — Chaque chunk possède un `.refs` ; `packbox-gc` ne
  supprime que ce qui n'est pas référencé (chunks **et cellules**).
- **Signatures** — `.pbox` signables avec **ed25519** ; `import` vérifie et
  **rejette** les paquets altérés ou provenant de signataires non fiables.
- **Intégrité du CAS** — Hashes validés avant d'être utilisés comme chemin ;
  écritures atomiques.

### Limitations connues (v0.2.0 Alpha)

> [!WARNING]
> Les domaines où vos retours sont les plus appréciés.

- ⚠️ **Portails partiels.** Il est permis de parler aux portails et le montage de
  documents est exposé, mais les portails ne sont pas encore utilisés pour tout
  (caméra, presse-papiers, etc.).
- ⚠️ **`packbox-module remove`/`info`** restent non implémentés (`cell` existe
  bien).
- ⚠️ **Compression adaptative** au niveau du paquet, pas par entrée (le format est
  tar + un compresseur).
- ⚠️ **Sans catalogue.** Le remote HTTP sert des données, pas de la confiance ni un
  index public.

---

## Feuille de route

### v0.1.x — Stabilisation

- [x] Vérification des signatures pour `.pbox` (ed25519 + gestion des clés)
- [x] Sandbox renforcé : HOME privé, D-Bus filtré, seccomp
- [x] Cellules automatiques + overlay de couches (A/C/S)
- [x] `packbox-update` avec delta de chunks + GC automatique
- [x] Remote HTTP (`publish`/`fetch`) avec téléchargement delta
- [x] Symboles de debug à part (`cell-debug`)
- [x] Compression adaptative dans `export`
- [x] Tests d'intégration end-to-end (`tests/integration.sh`)
- [ ] Politique de réseau par application
- [ ] Portails complets (fichiers, caméra, presse-papiers)
- [ ] CI/CD : `shellcheck`, `gofmt`, `go vet` à chaque PR
- [ ] Matrice de tests : Debian 12, Fedora 40, Arch, openSUSE Tumbleweed

### v0.2 — Portée

- [ ] Binaires précompilés x86_64 et aarch64 (page de releases)
- [ ] Index/dépôt central signé (`search`/`install` depuis un remote)
- [ ] Frontend GUI optionnel (GTK4)

### Futur

- [ ] Importateur de runtimes Flatpak (best-effort)
- [ ] Sandbox WASM pour les plugins non fiables

---

## Contribuer

Contributions bienvenues ! Les domaines où l'aide est particulièrement utile :

- **Traductions** — Ajoutez une locale en copiant un bloc existant dans `i18n/`
  et en traduisant chaque clé `L_*`.
- **Portails** — Intégrer `xdg-desktop-portal` pour l'accès aux fichiers.
- **Chunking / dedup** — Améliorer le CDC et la politique de seuil.
- **Rapports de bugs** — Incluez toujours la sortie de `packbox-diagnose`.

### Comment commencer

```bash
git clone https://github.com/El-Ave-Azul/packbox.git
cd packbox
cd src && go test ./...     # tests unitaires
bash tests/integration.sh   # end-to-end (pack → export → import → run)
```

- 🐛 [Ouvrir un issue](https://github.com/El-Ave-Azul/packbox/issues)
- 💬 [Démarrer une discussion](https://github.com/El-Ave-Azul/packbox/discussions)

> [!TIP]
> Passez `shellcheck` sur les scripts bash et `gofmt` + `go vet` sur Go avant
> d'envoyer une PR.

---

## Licence

Distribué sous la **Apache License 2.0**. Voir [LICENSE](../../LICENSE).

Apache 2.0 apporte une **clause explicite de concession de brevets**, qui protège
les utilisateurs et les contributeurs contre les litiges portant sur les
techniques de déduplication et de sandboxing, et est compatible avec GPLv3.

---

## Remerciements

- **[bubblewrap](https://github.com/containers/bubblewrap)** — Primitives de
  sandbox Linux qui rendent possible `packbox-run`.
- **[BLAKE3](https://github.com/BLAKE3-team/BLAKE3)** — Hachage de contenu rapide
  et cryptographiquement sûr.
- **[xdg-desktop-portal](https://flatpak.github.io/xdg-desktop-portal/)** et
  **xdg-dbus-proxy** — Accès médié aux fichiers et filtrage de D-Bus.
- **[Flatpak](https://flatpak.org/)** — A démontré que les applications Linux
  sandboxées fonctionnent à grande échelle ; nombre de ses décisions ont inspiré
  les nôtres, y compris là où nous divergeons.
- **Communauté Linux mondiale** — La couche i18n de 9 langues existe grâce à ses
  relectures et contributions.
