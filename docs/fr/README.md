# Packbox

**[Español](../../README.md)** · [English](../en/README.md) · **[Français](README.md)** · [Deutsch](../de/README.md) · [Italiano](../it/README.md) · [Português](../pt/README.md) · [中文](../zh/README.md) · [日本語](../ja/README.md) · [한국어](../ko/README.md)

---

![CI](https://github.com/El-Ave-Azul/packbox/actions/workflows/ci.yml/badge.svg)
![Licence](https://img.shields.io/badge/Licence-Apache_2.0-blue.svg)
![Version](https://img.shields.io/badge/Version-0.3.0-orange.svg)
![Plateforme](https://img.shields.io/badge/Plateforme-Linux-blue.svg)
![Go](https://img.shields.io/badge/Go-1.22+-00ADD8.svg?logo=go&logoColor=white)
![i18n](https://img.shields.io/badge/i18n-9_langues-green.svg)
![État](https://img.shields.io/badge/État-Beta-blue.svg)

**Empaqueteur d'applications Linux avec déduplication binaire par chunk et export `.pbox` compressé en Zstd.**
Inspiré de Flatpak, mais avec un modèle de réutilisation différent : au lieu d'un
runtime monolithique par application, Packbox stocke le contenu dans un magasin
adressé par contenu (BLAKE3 CAS), avec un **chunking défini par le contenu
(CDC)** optimisé et des **cellules** réutilisables. Deux applications qui partagent 90 % de
leurs bibliothèques ne stockent que les 10 % qui diffèrent.

> [!IMPORTANT]
> **État Beta (v0.3.0).** Le système a évolué vers une stabilité du noyau accrue, implémentant la collecte de déchets LRU et la compression Zstd à l'export.

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

Packbox empaquette des applications Linux en utilisant un **Content-Addressable Storage (CAS)**
avec hachage **BLAKE3** et **chunking par contenu** optimisé, afin
d'obtenir une véritable déduplication binaire entre les applications.

Au lieu d'un runtime d'environ 1 GB par application (Flatpak), Packbox stocke
chaque fichier sous forme de chunks (dédupliqués par contenu) et les partage entre
toutes les applications ; la compression **Zstd** est appliquée lors de l'export du `.pbox`. De plus, il convertit chaque bibliothèque en une
**cellule** (une unité de réutilisation versionnée) que plusieurs applications
partagent, et laisse les bibliothèques universelles (`libc`, `libm`, …) à l'hôte.

### Principes de conception

- **Déduplication au niveau du chunk.** Mêmes octets = même hash = stocké une
  seule fois (CDC optimisé pour les binaires ELF ; fichier unique pour les petits).
- **Stockage brut, export compressé.** Le CAS conserve les chunks non compressés pour que l'installation puisse les **hardlinker** (déduplication réelle sur disque) ; la compression **Zstd** est appliquée lors de la création du `.pbox`.
- **Cellules (fragmentation atomique).** Chaque bibliothèque non universelle est
  une cellule ; l'application la déclare et l'installeur la résout.
- **Partage croisé.** Toutes les applications partagent le même CAS global et les
  mêmes cellules.
- **Host contract v1.** Délégation sélective des bibliothèques universelles, avec
  **vérification ABI** des symboles requis.
- **Sandbox renforcé (bubblewrap).** `--unshare-all`, `--cap-drop ALL`,
  **seccomp**, **D-Bus filtré** (`xdg-dbus-proxy`), **HOME privé par
  application**, réseau granulaire (none/limited/full) et **X11 opt-in avec auto-détection**.
- **Couche par overlay.** `/app` est composé comme un overlay de A (application)
  sur C (cellules), avec S (hôte) via `/usr`.
- **Signatures et distribution.** `.pbox` signables (ed25519) et remote HTTP avec
  téléchargement delta concurrent.
- **4 modes d'empaquetage.** Normal, Portable, Bundle, Module.

---

## Comparaison avec Flatpak

| Caractéristique          | Flatpak (actuel)            | Packbox v0.3.0                       |
|--------------------------|-----------------------------|--------------------------------------|
| Unité de réutilisation   | Runtime complet (~1 GB)     | **Cellules** par lib (sans runtimes) |
| Déduplication            | Au niveau du fichier (OSTree) | Au niveau du **chunk** (BLAKE3 + CDC) |
| Stockage                 | Comprimé par runtime       | **Chunks bruts + hardlink** (dédup)   |
| Partage des libs         | Au sein du même runtime     | Croisé entre toutes les applications  |
| Utilisation des libs hôte | Aucune               | Sélective (host contract + ABI)      |
| Mises à jour             | Delta d'objets OSTree       | `packbox-update` (delta + GC LRU)    |
| Distribution             | Flathub + remotes OSTree    | Remote HTTP concurrent              |
| Signatures               | GPG                         | ed25519 (`.pbox.sig`)                |
| Sandbox                  | bwrap + seccomp + portails  | bwrap + seccomp + dbus-proxy + portails |
| Interface               | GNOME Software / CLI        | **TUI** + CLI                          |
| Surcoût par application  | ~100 % si runtime différent | **~5–15 %** avec des applications partagées |

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

---

## Utilisation rapide

### 1. Empaqueteur interactif (TUI)

```bash
./packbox-packager.sh
```

L'option **1 (Empaqueter)** recherche les applications **déjà installées** et **génère un**
`.pbox` dans `~/.local/share/packbox/exports/`. À la fin, il demande si vous voulez
également **l'installer sur cet ordinateur** (par défaut **non**, pour ne pas encombrer votre
système). Pour installer un `.pbox`, utilisez l'option **5 (Importer)**.

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

---

## Commandes disponibles

Packbox v0.3.0 inclut **15 binaires Go** dans `~/.packbox/bin/` :

| Commande           | Objectif                                                          |
|--------------------|--------------------------------------------------------------------|
| `packbox-pack`     | Hache un répertoire en chunks CAS et génère `manifest.json`        |
| `packbox-install`  | Installe une application depuis le manifeste (+ `--desktop`/`--remove-desktop`) |
| `packbox-run`      | Exécute l'application dans le sandbox `bwrap` (overlay A/C, HOME privé) |
| `packbox-list`     | Liste les applications avec leur **taille réelle** et l'économie par sharing (`--tsv`) |
| `packbox-remove`   | Désinstalle une application (`--all` = toutes, `--dry-run`) et libère ses refs |
| `packbox-gc`       | Collecte les chunks **et les cellules** sans références (Supporte LRU) |
| `packbox-verify`   | Vérifie les libs résolubles + la **compatibilité ABI** de l'hôte   |
| `packbox-export`   | Exporte vers `.pbox` avec **compression adaptative** et `--sign` optionnel |
| `packbox-import`   | Importe un `.pbox` (anti tar-slip, traversal et signatures)        |
| `packbox-update`   | Met à jour une application en réutilisant les chunks + rapport de delta (`--no-gc`) |
| `packbox-module`   | Modules/cellules : `list`, `create`, `cell <lib>...`               |
| `packbox-sign`     | Clés et signatures ed25519 : `keygen`, `sign`, `verify`, `trust`   |
| `packbox-fetch`    | Remote HTTP : `publish`, `index`/`search`/`install` avec un **index signé**, et `fetch` (delta concurrent) |
| `packbox-debug`    | Attache les symboles de debug (cellule à part) d'une application installée |
| `packbox-diagnose` | Rapport de l'environnement pour les rapports de bugs              |

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

- **CAS + chunker** — Stocke les chunks bruts (sans recompression, pour pouvoir les hardlinker) par hash **BLAKE3**. Les fichiers volumineux sont découpés avec un **CDC optimisé** ; les petits passent en un seul chunk. Écritures **atomiques**.
- **Manifeste** (`schema_version: \"1.7\"`) — Associe les chemins aux chunks, définit la politique de réseau (`none`, `limited`, `full`), le host contract et le symbole X11.
- **Cellules** — Une lib = une cellule `org.lib.<soname>@<hash>` dans `mods/`. Partagées entre les applications. `packbox-gc` supprime celles qui ne sont pas référencées ou les plus anciennes (LRU).
- **Sandbox** — `bwrap --unshare-all --cap-drop ALL --clearenv`, **seccomp**, **D-Bus filtré** avec `xdg-dbus-proxy`, **HOME privé**, réseau granulaire et **Soutien Multimédia** (PipeWire/PulseAudio).
- **Overlay de couches** — `/app` est composé avec `--overlay-src` (C en bas, A en haut) ; S (hôte) arrive via `/usr`.
- **Host contract** — `packbox-verify` vérifie que l'hôte fournit les symboles requis (ABI).
- **Signatures et remote** — `packbox-sign` (ed25519) signe le `.pbox` et l'**index du dépôt** ; `packbox-fetch` publie, **recherche** (`search`) et installe par id, avec des **téléchargements concurrents**.

---

## Sécurité

### Mesures implémentées

- **Isolation des données par application** — Chaque application s'exécute avec son **HOME privé** ; seules les polices/thèmes sont exposés en **lecture seule**.
- **D-Bus filtré** — `xdg-dbus-proxy` avec liste blanche (portails + `dconf`).
- **seccomp** — Filtre par défaut qui bloque la surface dangereuse du noyau.
- **Réseau Granulaire** — Modes `none`/`limited`/`full`. `limited` utilise un proxy interne **best-effort** qui bloque les plages privées/réservées ; il n'affecte que les applications qui respectent `http_proxy`/`https_proxy` (les sockets bruts ne sont pas filtrés).
- **Soutien Multimédia Sécurisé** — Accès médié à l'audio et à la caméra via les portails.
- **Anti tar-slip / traversal** — Validation stricte des chemins dans `.pbox`.
- **Nettoyage de l'environnement** — `--clearenv` + liste blanche explicite.
- **Reference counting + LRU GC** — Nettoyage intelligent des chunks basé sur le temps d'accès.
- **Signatures** — `.pbox` signables avec **ed25519**.

---

## Feuille de route

### v0.1.x — Stabilisation
- [x] Vérification des signatures pour `.pbox`
- [x] Sandbox renforcé : HOME privé, D-Bus filtré, seccomp
- [x] Cellules automatiques + overlay de couches (A/C/S)
- [x] `packbox-update` avec delta de chunks + GC automatique
- [x] Remote HTTP avec téléchargement delta concurrent
- [x] Compression Zstd dans l'export `.pbox`
- [x] Tuning de CDC pour les binaires ELF
- [x] Collecte de déchets LRU

### v0.2 — Portée
- [ ] Frontend GUI en GTK4 (reporté)
- [ ] Binaires précompilés x86_64 et aarch64
- [x] Index/dépôt central signé

### Futur
- [ ] Importateur de runtimes Flatpak (best-effort)
- [ ] Sandbox WASM pour les plugins non fiables

---

## Licence

Distribué sous la **Apache License 2.0**. Voir [LICENSE](../../LICENSE).
