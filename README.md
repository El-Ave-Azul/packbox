# Packbox

**[Español](README.md)** · [English](docs/en/README.md) · [Français](docs/fr/README.md) · [Deutsch](docs/de/README.md) · [Italiano](docs/it/README.md) · [Português](docs/pt/README.md) · [中文](docs/zh/README.md) · [日本語](docs/ja/README.md) · [한국어](docs/ko/README.md)

---

![CI](https://github.com/El-Ave-Azul/packbox/actions/workflows/ci.yml/badge.svg)
![Licencia](https://img.shields.io/badge/Licencia-Apache_2.0-blue.svg)
![Versión](https://img.shields.io/badge/Versión-0.2.0-orange.svg)
![Plataforma](https://img.shields.io/badge/Plataforma-Linux-blue.svg)
![Go](https://img.shields.io/badge/Go-1.22+-00ADD8.svg?logo=go&logoColor=white)
![i18n](https://img.shields.io/badge/i18n-9_idiomas-green.svg)
![Estado](https://img.shields.io/badge/Estado-Alpha-red.svg)

**Empaquetador de aplicaciones Linux con deduplicación binaria por chunk.**
Inspirado en Flatpak, pero con un modelo de reuso distinto: en vez de un
runtime monolítico por app, Packbox guarda el contenido en un almacén
direccionado por contenido (BLAKE3 CAS), con **chunking definido por contenido
(CDC)** y **celdas** reutilizables. Dos apps que comparten el 90 % de sus
librerías solo almacenan el 10 % que difiere.

> [!WARNING]
> **Estado Alpha (v0.2.0).** Los flujos principales funcionan y ya hay firmas,
> sandbox reforzado (seccomp, D-Bus filtrado, HOME privado) y remoto HTTP, pero
> el proyecto es joven y no tiene el ecosistema ni la madurez de Flatpak. Úsalo
> primero en sistemas no críticos.

---

## Tabla de contenidos

- [¿Qué es Packbox?](#qué-es-packbox)
- [Comparación con Flatpak](#comparación-con-flatpak)
- [Requisitos](#requisitos)
- [Instalación](#instalación)
- [Uso rápido](#uso-rápido)
- [Comandos disponibles](#comandos-disponibles)
- [Estructura de archivos](#estructura-de-archivos)
- [Arquitectura](#arquitectura)
- [Seguridad](#seguridad)
- [Hoja de ruta](#hoja-de-ruta)
- [Contribuir](#contribuir)
- [Licencia](#licencia)
- [Agradecimientos](#agradecimientos)

---

## ¿Qué es Packbox?

Packbox empaqueta aplicaciones Linux usando **Content-Addressable Storage (CAS)**
con hashing **BLAKE3** y **chunking por contenido**, para lograr deduplicación
binaria real entre apps.

En vez de un runtime de ~1 GB por aplicación (Flatpak), Packbox guarda cada
archivo como chunks direccionados por contenido y lo comparte entre todas las
apps. Además convierte cada librería en una **celda** (una unidad de reuso
versionada) que varias apps comparten, y deja las librerías universales
(`libc`, `libm`, …) al host.

### Principios de diseño

- **Deduplicación a nivel de chunk.** Mismos bytes = mismo hash = almacenado una
  vez (CDC en archivos grandes; archivo único en los pequeños, para poder
  hardlinkear y compartir).
- **Celdas (fragmentación atómica).** Cada lib no universal es una celda;
  la app la declara y el instalador la resuelve.
- **Compartición cruzada.** Todas las apps comparten el mismo CAS global y las
  mismas celdas.
- **Host contract v1.** Delegación selectiva de librerías universales, con
  **chequeo ABI** de los símbolos requeridos.
- **Sandbox reforzado (bubblewrap).** `--unshare-all`, `--cap-drop ALL`,
  **seccomp**, **D-Bus filtrado** (`xdg-dbus-proxy`), **HOME privado por app**,
  red opt-in y **X11 opt-in con autodetección**.
- **Capa por overlay.** `/app` se compone como overlay de A (app) sobre C
  (celdas), con S (host) vía `/usr`.
- **Firmas y distribución.** `.pbox` firmables (ed25519) y remoto HTTP con
  descarga delta.
- **4 modos de empaquetado.** Normal, Portable, Bundle, Module.

---

## Comparación con Flatpak

| Característica       | Flatpak (actual)            | Packbox v0.2.0                       |
|----------------------|-----------------------------|--------------------------------------|
| Unidad de reuso      | Runtime completo (~1 GB)    | **Celdas** por lib (sin runtimes)    |
| Deduplicación        | A nivel de archivo (OSTree) | A nivel de **chunk** (BLAKE3 + CDC)  |
| Compartición de libs | Dentro del mismo runtime    | Cruzada entre todas las apps         |
| Uso de libs del host | Ninguno                     | Selectivo (host contract + ABI)      |
| Actualizaciones      | Delta de objetos OSTree     | `packbox-update` (delta de chunks + GC) |
| Distribución         | Flathub + remotes OSTree    | Remoto HTTP con `publish`/`fetch`    |
| Firmas               | GPG                         | ed25519 (`.pbox.sig`)                |
| Sandbox              | bwrap + seccomp + portales  | bwrap + seccomp + dbus-proxy + portales |
| Overhead por app     | ~100 % si runtime distinto  | **~5–15 %** con apps que comparten   |

**Ahorro medido** (esta base de código): dos apps GTK4 medianas que comparten su
stack suman ~264 MB por separado y ocupan **~141 MB reales (−46 %)**; con 10
apps mixtas el ahorro sube a **~69 %**. Cuanto mayor es la superposición de
librerías, mayor el ahorro — pero conviene medirlo por caso, no asumir el 90–99 %
de un runtime compartido.

---

## Requisitos

- **Sistema operativo**: Linux (Debian 12+, Ubuntu 22.04+, Fedora 40+, Arch,
  openSUSE Tumbleweed)
- **Kernel**: 5.15+ con user namespaces habilitados
- **Shell**: Bash 4.0+
- **Go**: 1.22+ (el instalador descarga su propia copia si falta)
- **Espacio**: ~500 MB libres para la compilación inicial
- **Internet**: solo para la primera instalación

### Dependencias del sistema

Instaladas por el instalador cuando es posible; útiles también a mano:

`bubblewrap` · `binutils` (`ldd`/`readelf`) · `jq` · `bc` · `curl` · `tar` ·
`xdg-dbus-proxy` (filtrado de D-Bus) · `zstd` o `xz` (export más compacto)

---

## Instalación

### Paso 1 — Clonar y ejecutar

```bash
git clone https://github.com/El-Ave-Azul/packbox.git
cd packbox
./packbox-install.sh
```

El instalador abre un menú; elige la opción **1** (Instalar).

### Paso 2 — Recargar el shell

```bash
source ~/.bashrc
```

### Paso 3 — Verificar

```bash
packbox-diagnose
```

### Qué hace el instalador

1. Te permite seleccionar uno de 9 idiomas.
2. Detecta tu distribución Linux y gestor de paquetes.
3. Pide confirmación antes de instalar dependencias.
4. Descarga y verifica Go (por defecto 1.27.1) en `~/.packbox/go` si hace falta.
5. Crea la estructura de directorios (`~/.packbox/` y `~/.local/share/packbox/`).
6. Copia las fuentes y compila los **15 binarios** Go (~1–2 minutos).
7. Configura tu `PATH` en `~/.bashrc` y crea symlinks en `~/.local/bin`.
8. Instala los archivos de idioma en `~/.config/packbox/lang/`.
9. Verifica que todos los binarios estén presentes y funcionales.

### Desinstalación

Ejecuta el mismo script y elige la opción **2**:

```bash
./packbox-install.sh --uninstall
```

| Modo | Descripción |
|------|-------------|
| `s`  | Completo: binarios + apps + store CAS + celdas + menús + iconos + config |
| `k`  | Solo binarios: `~/.packbox/` y symlinks (conserva apps y store CAS) |
| `q`  | Cancelar |

---

## Uso rápido

### 1. Empaquetador interactivo (recomendado)

```bash
./packbox-packager.sh
```

Menú: empaquetar, listar, garbage collection, exportar, importar, desinstalar,
idioma. Detecta apps desde `.desktop` en `/usr/share/applications/`, bundles en
`/opt/*` y binarios comunes (`htop`, `btop`, `firefox`, `gimp`, …).

En los modos **Normal** y **Portable** cada lib no universal del cierre `ldd`
se convierte en una **celda** automáticamente.

### 2. Línea de comandos

```bash
# Empaquetar un directorio
packbox-pack ./mi-app --name org.ejemplo.miapp --version 1.0.0

# Instalar desde el manifiesto generado
packbox-install ./mi-app/manifest.json

# Ejecutar en sandbox (overlay A sobre C; HOME privado)
packbox-run org.ejemplo.miapp

# Listar apps (tamaño real y ahorro por sharing) y liberar espacio
packbox-list
packbox-remove org.ejemplo.miapp
packbox-gc

# Actualizar una app instalada reusando chunks del store
packbox-update org.ejemplo.miapp ./nuevo/manifest.json
```

### 3. Exportar, firmar, importar y distribuir

```bash
# Exportar y firmar
packbox-sign keygen                       # crea tu clave (y la confía)
packbox-export --sign app org.ejemplo.miapp
packbox-sign verify ~/.local/share/packbox/exports/org.ejemplo.miapp.pbox

# Publicar un remoto HTTP y usarlo desde otra máquina
packbox-fetch publish org.ejemplo.miapp /srv/packbox
(cd /srv/packbox && python3 -m http.server 8000)
packbox-fetch fetch org.ejemplo.miapp --from http://host:8000

# Importar (verifica la firma si existe)
packbox-import app org.ejemplo.miapp.pbox
```

---

## Comandos disponibles

Packbox v0.2.0 incluye **15 binarios Go** en `~/.packbox/bin/`:

| Comando            | Propósito                                                          |
|--------------------|--------------------------------------------------------------------|
| `packbox-pack`     | Hashea un directorio en chunks CAS y genera `manifest.json`        |
| `packbox-install`  | Instala una app desde el manifiesto (+ `--desktop`/`--remove-desktop`) |
| `packbox-run`      | Ejecuta la app en el sandbox `bwrap` (overlay A/C, HOME privado)   |
| `packbox-list`     | Lista apps con su **tamaño real** y ahorro por sharing (`--tsv`)   |
| `packbox-remove`   | Desinstala una app (`--all` = todas, `--dry-run`) y libera sus refs |
| `packbox-gc`       | Recolecta chunks **y celdas** sin referencias                      |
| `packbox-verify`   | Comprueba libs resolubles + **compatibilidad ABI** del host        |
| `packbox-export`   | Exporta a `.pbox` con **compresión adaptativa** y `--sign` opcional |
| `packbox-import`   | Importa un `.pbox` (anti tar-slip, traversal y firmas)             |
| `packbox-update`   | Actualiza una app reusando chunks + informe de delta (`--no-gc`)   |
| `packbox-module`   | Módulos/celdas: `list`, `create`, `cell <lib>...`                  |
| `packbox-sign`     | Claves y firmas ed25519: `keygen`, `sign`, `verify`, `trust`       |
| `packbox-fetch`    | Remoto HTTP: `publish <id> <dir>` y `fetch <id> --from <url>`      |
| `packbox-debug`    | Adjunta los símbolos de debug (celda aparte) de una app instalada  |
| `packbox-diagnose` | Reporte del entorno para reportes de bugs                          |

---

## Estructura de archivos

```
~/.packbox/                              # Instalación
├── bin/                                 # 15 binarios Go compilados
└── src/                                 # Código fuente Go

~/.local/share/packbox/                  # Datos de usuario
├── store/                               # CAS: chunks por hash BLAKE3
│   └── <ab>/<hash-completo>             # + archivo .refs por chunk
├── apps/                                # Apps instaladas
│   └── <app-id>/
│       ├── manifest.json
│       ├── tree/                        # Hardlinks al CAS (capa A)
│       └── home/                        # HOME privado (se crea al primer run)
├── mods/                                # Celdas (org.lib.*, org.debug.*)
├── exports/                             # Archivos .pbox (+ .sig)
└── tmp/                                 # Temporales

~/.config/packbox/
├── lang/                                # 9 archivos de idioma
├── signing.key / signing.pub            # tu clave de firma
└── trusted/                             # claves públicas de confianza
```

---

## Arquitectura

### Flujo de empaquetado

```
┌──────────────┐   pack    ┌──────────────┐  install  ┌──────────────┐
│  Dir fuente  │ ────────► │     CAS      │ ─────────► │  Tree de app │
│  (árbol fs)  │           │  (chunks)    │           │ (hardlinks)  │
└──────────────┘           └──────────────┘           └──────┬───────┘
                                  │                          │ + celdas (capa C)
                                  │ run                      ▼
                         ┌──────────────────────────────────────────┐
                         │  Sandbox bwrap: /app = overlay A sobre C  │
                         │  HOME privado · seccomp · D-Bus filtrado  │
                         └──────────────────────────────────────────┘
```

### Componentes internos

- **CAS + chunker** — Guarda chunks por hash **BLAKE3**. Los archivos grandes se
  parten con **CDC** (hash rodante tipo *gear*); los pequeños van como un solo
  chunk (hardlinkeables, para compartir). Escrituras **atómicas** (temp+rename).
- **Manifiesto** (`schema_version: "1.6"`) — Mapea rutas a chunks, lista las
  **celdas** (`mods`), el `host_contract` (delegate + required_symbols), el
  símbolo X11 y, si aplica, la celda de **debug**.
- **Celdas** — Una lib = una celda `org.lib.<soname>@<hash>` en `mods/`.
  Compartidas entre apps. `packbox-gc` borra las no referenciadas.
- **Sandbox** — `bwrap --unshare-all --cap-drop ALL --clearenv`, **seccomp**
  (bloquea ptrace/bpf/keyring/io_uring/módulos…), **D-Bus filtrado** con
  `xdg-dbus-proxy` (portales + dconf), **HOME privado** (`apps/<id>/home`), red
  **opt-in** y **X11 opt-in** (por defecto Wayland + portales; se activa solo si
  el manifiesto lo pide o si la sesión es solo-X11).
- **Overlay de capas** — `/app` se compone con `--overlay-src` (C abajo, A
  arriba); S (host) llega vía `/usr`. Evita copiar las celdas en cada árbol.
- **Host contract** — `packbox-verify` comprueba que el host provee los símbolos
  requeridos (ABI).
- **Firmas y remoto** — `packbox-sign` (ed25519) firma el `.pbox`;
  `packbox-fetch` publica y descarga solo el delta (chunks + celdas).

### Cómo funciona la deduplicación

```
App 1: htop     → chunks: [A, B, C]
App 2: neofetch → chunks: [A, D, E]
App 3: btop     → chunks: [A, B, F]

CAS Store:
  A → referencias: htop, neofetch, btop      (3 apps)
  B → referencias: htop, btop                (2 apps)
  C → htop · D → neofetch · E → neofetch · F → btop

Total: 6 chunks únicos en lugar de 9.
```

---

## Seguridad

### Mitigaciones implementadas

- **Aislamiento de datos por app** — Cada app corre con su **HOME privado**
  (`apps/<id>/home`); solo se exponen fuentes/temas en **solo lectura**. No ve
  ni toca tu configuración real.
- **D-Bus filtrado** — `xdg-dbus-proxy` con lista blanca (por defecto, portales
  y `dconf`; el bus de sistema, nada). La app no habla con el bus real.
- **seccomp** — Filtro por defecto que bloquea superficie peligrosa del kernel
  (ptrace, bpf, keyring, io_uring, userfaultfd, módulos, reboot/swap…).
- **X11 opt-in** — Por defecto Wayland + `xdg-desktop-portal` (exponiendo el
  montaje de documentos del portal); X11 se habilita con el flag `x11` del
  manifiesto o automáticamente si la sesión del host es solo X11.
- **Anti tar-slip / traversal** — La extracción `.pbox` valida cada entrada
  (`safeJoin` + `O_NOFOLLOW` + destinos de symlink) y rechaza `name`/rutas que
  escapen del directorio de la app.
- **Limpieza de entorno** — `--clearenv` + whitelist explícita: bloquea
  `LD_PRELOAD`/`LD_LIBRARY_PATH` inyectados desde el host.
- **Sin setuid, sin root** — Todo corre como tu usuario; `sudo` solo para las
  dependencias del sistema al instalar.
- **Reference counting + GC** — Cada chunk tiene un `.refs`; `packbox-gc` solo
  borra lo no referenciado (chunks **y celdas**).
- **Firmas** — `.pbox` firmables con **ed25519**; `import` verifica y **rechaza**
  paquetes alterados o de firmantes no confiables.
- **Integridad del CAS** — Hashes validados antes de usarse como ruta;
  escrituras atómicas.

### Limitaciones conocidas (v0.2.0 Alpha)

> [!WARNING]
> Áreas donde más feedback se agradece.

- ⚠️ **Portales parciales.** Se permite hablar con los portales y se expone el
  montaje de documentos, pero aún no se usan portales para todo (cámara,
  portapapeles, etc.).
- ⚠️ **`packbox-module remove`/`info`** siguen sin implementar (sí existe
  `cell`).
- ⚠️ **Compresión adaptativa** a nivel de paquete, no por-entrada (el formato es
  tar + un compresor).
- ⚠️ **Sin catálogo.** El remoto HTTP sirve datos, no confianza ni un índice
  público.

---

## Hoja de ruta

### v0.1.x — Estabilización

- [x] Verificación de firmas para `.pbox` (ed25519 + gestión de claves)
- [x] Sandbox reforzado: HOME privado, D-Bus filtrado, seccomp
- [x] Celdas automáticas + overlay de capas (A/C/S)
- [x] `packbox-update` con delta de chunks + GC automático
- [x] Remoto HTTP (`publish`/`fetch`) con descarga delta
- [x] Símbolos de debug aparte (`cell-debug`)
- [x] Compresión adaptativa en `export`
- [x] Tests de integración end-to-end (`tests/integration.sh`)
- [ ] Política de red por aplicación
- [ ] Portales completos (archivos, cámara, portapapeles)
- [ ] CI/CD: `shellcheck`, `gofmt`, `go vet` en cada PR
- [ ] Matriz de tests: Debian 12, Fedora 40, Arch, openSUSE Tumbleweed

### v0.2 — Alcance

- [ ] Binarios precompilados x86_64 y aarch64 (página de releases)
- [ ] Índice/repositorio central firmado (`search`/`install` desde remoto)
- [ ] Frontend GUI opcional (GTK4)

### Futuro

- [ ] Importador de runtimes Flatpak (best-effort)
- [ ] Sandbox WASM para plugins no confiables

---

## Contribuir

¡Contribuciones bienvenidas! Áreas donde la ayuda es especialmente útil:

- **Traducciones** — Añade un locale copiando un bloque existente en
  `i18n/` y traduciendo cada clave `L_*`.
- **Portales** — Integrar `xdg-desktop-portal` para acceso a archivos.
- **Chunking / dedup** — Mejorar el CDC y la política de umbral.
- **Reportes de bugs** — Incluye siempre la salida de `packbox-diagnose`.

### Cómo empezar

```bash
git clone https://github.com/El-Ave-Azul/packbox.git
cd packbox
cd src && go test ./...     # unit tests
bash tests/integration.sh   # end-to-end (pack → export → import → run)
```

La **CI** (`.github/workflows/ci.yml`) corre `gofmt`, `go vet`, `go test`,
`shellcheck` y el test de integración en cada push/PR.

- 🐛 [Abrir un issue](https://github.com/El-Ave-Azul/packbox/issues)
- 💬 [Iniciar una discusión](https://github.com/El-Ave-Azul/packbox/discussions)

> [!TIP]
> Pasa `shellcheck` a los scripts bash y `gofmt` + `go vet` a Go antes de
> enviar un PR.

---

## Licencia

Distribuido bajo la **Apache License 2.0**. Ver [LICENSE](LICENSE).

Apache 2.0 aporta una **cláusula explícita de concesión de patentes**, que
protege a usuarios y contribuyentes frente a litigios sobre las técnicas de
deduplicación y sandboxing, y es compatible con GPLv3.

---

## Agradecimientos

- **[bubblewrap](https://github.com/containers/bubblewrap)** — Primitiva de
  sandbox Linux que hace posible `packbox-run`.
- **[BLAKE3](https://github.com/BLAKE3-team/BLAKE3)** — Hashing de contenido
  rápido y criptográficamente seguro.
- **[xdg-desktop-portal](https://flatpak.github.io/xdg-desktop-portal/)** y
  **xdg-dbus-proxy** — Acceso mediado a archivos y filtrado de D-Bus.
- **[Flatpak](https://flatpak.org/)** — Demostró que las apps Linux
  sandboxeadas funcionan a escala; muchas de sus decisiones informaron las
  nuestras, incluso donde divergimos.
- **Comunidad Linux global** — La capa i18n de 9 idiomas existe gracias a sus
  revisiones y contribuciones.
