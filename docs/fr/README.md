[English](../../README.md) · [Español](../../README.es.md) · **Français** · [Deutsch](../de/README.md) · [Italiano](../it/README.md) · [简体中文](../zh-CN/README.md) · [繁體中文](../zh-TW/README.md) · [日本語](../ja/README.md) · [한국어](../ko/README.md)

---

![Licence : MIT](https://img.shields.io/badge/Licence-MIT-yellow.svg)
![Plateforme : Linux](https://img.shields.io/badge/plateforme-Linux-blue)
![Version](https://img.shields.io/badge/version-0.1.0--alpha-orange)
![Go](https://img.shields.io/badge/Go-1.22+-00ADD8?logo=go&logoColor=white)
![i18n](https://img.shields.io/badge/i18n-9_langues-green)
![Statut](https://img.shields.io/badge/statut-alpha-red)

# Packbox

**Système d'empaquetage d'applications de nouvelle génération pour Linux.**
Inspiré de Flatpak, mais avec un modèle de réutilisation fondamentalement
différent : au lieu d'envoyer un runtime monolithique par app, Packbox stocke
chaque fichier sous forme de chunks adressés par contenu (BLAKE3 CAS). Deux
apps partageant 90 % de leurs bibliothèques ne stockent que les 10 % qui
diffèrent.

> [!NOTE]
> **Packbox est en Alpha (v0.1.0).** Les flux principaux fonctionnent, mais
> il n'y a pas encore de vérification de signature sur les archives `.pbox`,
> et le sandbox est intentionnellement plus permissif que Flatpak. Utilisez-le
> d'abord sur des systèmes non critiques.

---

## Table des matières

- [Pourquoi Packbox](#pourquoi-packbox)
- [Comparaison avec Flatpak](#comparaison-avec-flatpak)
- [Prérequis](#prérequis)
- [Installation](#installation)
- [Démarrage rapide](#démarrage-rapide)
- [Commandes](#commandes)
- [Arborescence](#arborescence)
- [Architecture](#architecture)
- [Sécurité](#sécurité)
- [Feuille de route](#feuille-de-route)
- [Documentation](#documentation)
- [Contribuer](#contribuer)
- [Licence](#licence)
- [Remerciements](#remerciements)

---

## Pourquoi Packbox

Flatpak a résolu un vrai problème : des apps Linux sandboxées et portables.
Mais son modèle de réutilisation est grossier. Chaque app embarque (ou
référence) un runtime complet qui peut peser **~1 Go**. Si deux apps utilisent
des runtimes différents, vous payez deux fois — même si elles partagent 95 %
de leurs bibliothèques.

Packbox s'attaque à ce manque précis :

- **Déduplication au niveau chunk.** Les fichiers sont découpés, hachés avec
  BLAKE3, et stockés en chunks. Les chunks identiques (une `libfoo.so.3.2.1`,
  une police, un catalogue de traduction) sont partagés entre toutes les apps
  du système.
- **Partage inter-apps.** Deux apps qui utilisent la même `libQt6Core.so`
  ne gardent qu'une copie sur disque, indépendamment de leur "runtime".
- **Utilisation sélective des libs de l'hôte.** Les apps peuvent déclarer
  quelles bibliothèques de l'hôte elles acceptent (via
  `host_contract.delegate`), au lieu de tout embarquer.
- **Empreinte réduite par app.** En pratique, ajouter une nouvelle app sur un
  ensemble existant coûte ~5–15 % de sa taille, pas ~100 %.

Packbox **ne cherche pas** à remplacer Flatpak. Il explore un autre créneau :
les apps qui ne s'insèrent pas proprement dans un runtime, ou là où envoyer
1 Go pour exécuter un outil de 50 Mo est excessif.

---

## Comparaison avec Flatpak

| Caractéristique          | Flatpak (actuel)                 | Packbox (proposé)               |
|--------------------------|----------------------------------|---------------------------------|
| Unité de réutilisation   | Runtime complet (~1 Go)          | Cellule atomique (~5–50 Mo)     |
| Déduplication            | Au niveau fichier (OSTree)       | Au niveau chunk (BLAKE3 CAS)    |
| Partage de libs          | Dans le même runtime             | Entre toutes les apps           |
| Utilisation libs hôte    | Aucune (sandbox complet)         | Sélectif (ABI compatible)       |
| Mises à jour             | Delta d'objets OSTree            | Delta de chunks + réordonnancement |
| Overhead par app         | ~100 % si runtime différent      | ~5–15 % (seulement les différences) |

---

## Prérequis

- **Linux** (testé sur Debian 12, Fedora 40, Arch actuel)
- **Bash 4+**
- **Go 1.22+** (auto-installé si absent)
- **bubblewrap** (`bwrap`) — auto-installé
- **binutils** (`ldd`, `readelf`) — auto-installé
- **Outils de compression** : `zstd`, `xz`, `gzip` (au moins un)
- **~500 Mo libres** pour le build + toolchain si Go est installé de zéro

Familles supportées : **Debian/Ubuntu/Mint/Pop**, **Fedora/RHEL/Rocky**,
**Arch/Manjaro/EndeavourOS**, **openSUSE**.

---

## Installation

```bash
git clone https://github.com/TU_USUARIO/packbox.git
cd packbox
./packbox-installer-v0.1.0.sh
source ~/.bashrc
packbox-diagnose
```

L'installateur est interactif et :

1. Détecte votre distribution et gestionnaire de paquets.
2. Demande confirmation avant d'installer les dépendances
   (`bubblewrap binutils jq bc curl tar`).
3. Installe Go 1.22+ si absent.
4. Crée `~/.packbox/{bin,src}` et
   `~/.local/share/packbox/{store,apps,mods,exports,tmp}`.
5. Génère 11 binaires Go + packages internes depuis les sources locales.
6. Compile le tout (~2–3 minutes sur matériel moderne).
7. Ajoute `~/.packbox/bin` au `PATH` et crée des symlinks dans
   `~/.local/bin`.
8. Vérifie que les 11 binaires sont présents.

**Langues** : l'installateur demande l'une des 9 locales au démarrage —
English, Español, Français, Deutsch, Italiano, 简体中文, 繁體中文, 日本語,
한국어.

### Désinstallation

Relancez le script et choisissez l'option `2` :

- Mode `s` → suppression complète (binaires + apps + store + menus + config)
- Mode `k` → binaires uniquement (garde apps et store)
- Mode `q` → annuler

Nécessite de taper `DELETE` pour confirmer.

---

## Démarrage rapide

### Empaqueteur interactif (recommandé)

```bash
./packbox-packager-v0.1.0.sh
```

Menu : empaqueter, lister, gc, exporter, importer, désinstaller.

### Ligne de commande

```bash
# 1. Empaqueter un répertoire en chunks CAS + manifest.json
packbox-pack ./firefox-tree \
    --name org.mozilla.firefox \
    --version 128.0 \
    --description "Mozilla Firefox" \
    --gui --toolkit GTK3

# 2. Installer depuis le manifest généré
packbox-install ./firefox-tree/manifest.json

# 3. Exécuter dans un sandbox bwrap (fix DNS + GUI appliqué)
packbox-run org.mozilla.firefox

# 4. Voir ce qui est installé
packbox-list

# 5. Désinstaller et libérer les chunks
packbox-remove org.mozilla.firefox
packbox-gc
```

---

## Commandes

Onze binaires Go, tous sous `~/.packbox/bin/` :

| Commande            | Rôle                                                        |
|---------------------|-------------------------------------------------------------|
| `packbox-pack`      | Hacher un répertoire en chunks CAS + `manifest.json`        |
| `packbox-install`   | Installer depuis le manifest (lien dur depuis le CAS)       |
| `packbox-run`       | Exécuter dans `bwrap` avec DNS + GUI                        |
| `packbox-list`      | Lister les apps installées avec version et tags             |
| `packbox-remove`    | Désinstaller et libérer les références CAS                  |
| `packbox-gc`        | Collecter les chunks orphelins                              |
| `packbox-verify`    | Vérification de compatibilité des libs via `ldd`            |
| `packbox-export`    | Exporter une app vers `.pbox` (zstd/xz/gzip)                |
| `packbox-import`    | Importer `.pbox` avec validation anti path-traversal        |
| `packbox-module`    | Gérer les modules de libs partagées (`list`, `create`)      |
| `packbox-diagnose`  | Imprimer un rapport d'environnement pour les rapports de bugs |

Référence complète avec options, codes de sortie et exemples :
[`commands.md`](commands.md) · [EN](../en/commands.md) · [ES](../es/commands.md)

### Scripts interactifs

- `packbox-installer-v0.1.0.sh` — installer / désinstaller
- `packbox-packager-v0.1.0.sh` — empaqueter, lister, gc, exporter, importer, désinstaller
- `packbox-i18n.sh` — couche de traduction partagée

---

## Arborescence

```
~/.packbox/                     # Installation (binaires + source Go)
├── bin/                        # 11 binaires Go
└── src/                        # Source du module Go

~/.local/share/packbox/         # Données
├── store/                      # CAS — chunks par hash BLAKE3
│   └── <ab>/<hash-complet>     # plus un fichier .refs par chunk
├── apps/                       # Apps installées (tree + manifest.json)
├── mods/                       # Modules de libs partagées
├── exports/                    # Archives .pbox
└── tmp/                        # Espace de travail temporaire

~/.config/packbox/lang/         # 9 fichiers de langue
```

---

## Architecture

Trois pièces mobiles :

```
┌──────────────┐   pack    ┌──────────────┐   install   ┌──────────────┐
│  Répertoire  │ ────────► │     CAS      │ ──────────► │  Tree app    │
│  (fs tree)   │           │  (chunks)    │             │ (hardlinks)  │
└──────────────┘           └──────────────┘             └──────────────┘
                                  │
                                  │ run
                                  ▼
                         ┌──────────────────┐
                         │  Sandbox bwrap   │
                         │  (fix DNS/GUI)   │
                         └──────────────────┘
```

- **CAS** — `~/.local/share/packbox/store/`, hachages BLAKE3, un fichier
  `.refs` par chunk, `SafeLink` (lien dur → copie en fallback) à
  l'installation.
- **Manifest** — `schema_version: "1.5"`, `layers.app.files` associe les
  chemins relatifs à `{chunks, size, mode}`, plus `host_contract.delegate`
  pour la confiance envers les libs de l'hôte.
- **Sandbox** — `bwrap --unshare-all --share-net`, whitelist d'env après
  `--clearenv`, résolution des symlinks DNS (`EvalSymlinks`) avant de binder
  `/etc/resolv.conf`, support GUI (X11, Wayland, D-Bus, `/dev/dri`, cache
  fontconfig), map heuristique de données par app avec `--bind-try`.

Architecture complète (internals du CAS, schéma du manifest, mounts du
sandbox, host contract) :
[`architecture.md`](../en/architecture.md) · [ES](../es/architecture.md)

---

## Sécurité

> [!WARNING]
> Les archives `.pbox` **ne sont pas signées** en v0.1.0 Alpha. Traitez
> toute archive importée comme non fiable. La vérification de signature est
> dans la feuille de route.

Mitigations déjà implémentées :

- **Protection anti path-traversal** — `cas.isValidHash()` impose 64
  caractères hex minuscules. L'import `.pbox` valide chaque entrée tar contre
  la racine d'extraction via `security.ValidatePath`.
- **Import sûr vis-à-vis des symlinks** — seuls `tar.TypeDir` et
  `tar.TypeReg` sont traités ; symlinks, hardlinks et fichiers de périphérique
  sont silencieusement ignorés.
- **Nettoyage d'environnement** — `--clearenv` suivi d'une whitelist
  explicite bloque l'injection de `LD_PRELOAD` / `LD_LIBRARY_PATH`.
- **Isolation de XAUTHORITY** — le `~/.Xauthority` de l'hôte est copié dans
  un fichier temporaire par processus (`/tmp/packbox-xauth-<pid>`, mode
  0600) avant d'être monté dans le sandbox.
- **Comptage de références** — chaque chunk a un fichier `.refs` ;
  `packbox-gc` ne supprime que les chunks non référencés.
- **Pas de setuid, pas de root** — Packbox tourne entièrement sous
  l'utilisateur appelant. `sudo` n'est utilisé que par l'installateur.

Limitations connues et modèle de menaces :
[`security.md`](../en/security.md) · [ES](../es/security.md)

Signalez les vulnérabilités avec la sortie de `packbox-diagnose` attachée.
Pour les découvertes sensibles, utilisez le contact privé de sécurité.

---

## Feuille de route

### v0.1.x — Stabilisation
- [ ] Vérification de signature pour les archives `.pbox`
- [ ] Politique réseau par app (actuellement `--share-net` est global)
- [ ] Implémenter `packbox-module remove` et `info`
- [ ] Tester `host_contract.delegate` sur de vraies apps GTK4/Qt6
- [ ] CI : `shellcheck`, `gofmt`, `go vet` à chaque PR
- [ ] Matrice de tests : Debian 12, Fedora 40, Arch, openSUSE Tumbleweed

### v0.2 — Portée
- [ ] Binaires précompilés pour x86_64 et aarch64 (page releases)
- [ ] `packbox-update` pour les mises à jour en place
- [ ] Frontend GUI (optionnel, GTK4)
- [ ] Téléchargements delta au niveau chunk pour `packbox-export`

### Plus tard
- [ ] Importateur de runtimes Flatpak (best-effort)
- [ ] Vérification de signature via minisign ou sigstore
- [ ] Sandbox WASM optionnel pour plugins non fiables

---

## Documentation

Documentation complète en 9 langues. L'anglais et l'espagnol ont l'ensemble
complet (README + commandes + architecture + sécurité) ; les sept autres ont
README + commandes.

| Langue   | README                                 | Commandes                                       | Architecture                                        | Sécurité                                      |
|----------|----------------------------------------|-------------------------------------------------|-----------------------------------------------------|-----------------------------------------------|
| English  | [en](../en/README.md)                  | [en](../en/commands.md)                         | [en](../en/architecture.md)                         | [en](../en/security.md)                       |
| Español  | [es](../es/README.md)                  | [es](../es/commands.md)                         | [es](../es/architecture.md)                         | [es](../es/security.md)                       |
| Français | **fr**                                 | [fr](commands.md)                               | —                                                   | —                                             |
| Deutsch  | [de](../de/README.md)                  | [de](../de/commands.md)                         | —                                                   | —                                             |
| Italiano | [it](../it/README.md)                  | [it](../it/commands.md)                         | —                                                   | —                                             |
| 简体中文 | [zh-CN](../zh-CN/README.md)            | [zh-CN](../zh-CN/commands.md)                   | —                                                   | —                                             |
| 繁體中文 | [zh-TW](../zh-TW/README.md)            | [zh-TW](../zh-TW/commands.md)                   | —                                                   | —                                             |
| 日本語   | [ja](../ja/README.md)                  | [ja](../ja/commands.md)                         | —                                                   | —                                             |
| 한국어   | [ko](../ko/README.md)                  | [ko](../ko/commands.md)                         | —                                                   | —                                             |

Index : [`docs/README.md`](../README.md)

---

## Contribuer

Contributions bienvenues, en particulier :

- **Traductions** — ajoutez une locale à `packbox-i18n.sh` en copiant le
  bloc `en` dans `install_lang_files()` et en traduisant chaque clé `L_*`.
- **Profils de sandbox** — maps de données par app pour navigateurs, IDE,
  jeux.
- **Stratégies de chunking du CAS** — variantes de rolling hash, chunking
  parallèle.
- **Rapports de bugs** — incluez toujours la sortie de `packbox-diagnose`.

Pour commencer :

```bash
git clone https://github.com/TU_USUARIO/packbox.git
cd packbox
# Lisez CONTRIBUTING.md pour les directives complètes
```

- 🐛 [Ouvrir un issue](https://github.com/TU_USUARIO/packbox/issues)
- 💬 [Démarrer une discussion](https://github.com/TU_USUARIO/packbox/discussions)
- 🔧 [CONTRIBUTING.md](../../CONTRIBUTING.md)

Merci de lancer `shellcheck` sur les scripts shell et `gofmt` + `go vet`
sur le code Go avant de soumettre une PR.

---

## Licence

[MIT](../../LICENSE) © 2025 TU_NOMBRE

Packbox est libre d'utilisation, de modification et de redistribution. Voir
[LICENSE](../../LICENSE) pour les détails.

---

## Remerciements

- **[bubblewrap](https://github.com/containers/bubblewrap)** — la primitive
  de sandbox qui rend `packbox-run` possible.
- **[BLAKE3](https://github.com/BLAKE3-team/BLAKE3)** — content-addressing
  rapide et sûr.
- **[Flatpak](https://flatpak.org/)** — le projet qui a prouvé que les apps
  Linux sandboxées fonctionnent à l'échelle, et dont les décisions de design
  ont informé beaucoup des nôtres (même là où nous divergons).
- La couche i18n à 9 langues existe parce que la communauté Linux est
  mondiale ; merci à tous ceux qui ont relu les traductions.
