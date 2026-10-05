# Packbox

**[Español](README.md)** · [English](docs/en/README.md) · [Français](docs/fr/README.md) · [Deutsch](docs/de/README.md) · [Italiano](docs/it/README.md) · [Português](docs/pt/README.md) · [中文](docs/zh/README.md) · [日本語](docs/ja/README.md) · [한국어](docs/ko/README.md)

---

![CI](https://github.com/El-Ave-Azul/packbox/actions/workflows/ci.yml/badge.svg)
![Licencia](https://img.shields.io/badge/Licencia-Apache_2.0-blue.svg)
![Versión](https://img.shields.io/badge/Versión-0.3.0-orange.svg)
![Plataforma](https://img.shields.io/badge/Plataforma-Linux-blue.svg)
![Go](https://img.shields.io/badge/Go-1.22+-00ADD8.svg?logo=go&logoColor=white)
![i18n](https://img.shields.io/badge/i18n-9_idiomas-green.svg)
![Estado](https://img.shields.io/badge/Estado-Beta-blue.svg)

**Empaquetador de aplicaciones Linux con deduplicación binaria por chunk y export `.pbox` comprimido con Zstd.**
Inspirado en Flatpak, pero con un modelo de reuso distinto: en vez de un
runtime monolítico por app, Packbox guarda el contenido en un almacén
direccionado por contenido (BLAKE3 CAS), con **chunking definido por contenido
(CDC)** optimizado y **celdas** reutilizables. Dos apps que comparten el 90 % de sus
librerías solo almacenan el 10 % que difiere.

> [!IMPORTANT]
> **Estado Beta (v0.3.0).** El sistema ha evolucionado la estabilidad del núcleo, implementando recolección de basura LRU y compresión Zstd en el export.

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
con hashing **BLAKE3** y **chunking por contenido** optimizado, para lograr deduplicación
binaria real entre apps.

En vez de un runtime de ~1 GB por aplicación (Flatpak), Packbox guarda cada
archivo en chunks (deduplicados por contenido) y lo comparte entre todas las
apps; la compresión **Zstd** se aplica al exportar el `.pbox`. Además convierte
cada librería en una **celda** (una unidad de reuso
versionada) que varias apps comparten, y deja las librerías universales
(`libc`, `libm`, …) al host.

### Principios de diseño

- **Deduplicación a nivel de chunk.** Mismos bytes = mismo hash = almacenado una
  vez (CDC optimizado para binarios ELF; archivo único en los pequeños).
- **Almacén crudo, export comprimido.** El CAS guarda los chunks sin comprimir
  para que la instalación los **hardlinkee** (dedup real en disco); la compresión
  **Zstd** se aplica al generar el `.pbox`.
- **Celdas (fragmentación atómica).** Cada lib no universal es una celda;
  la app la declara y el instalador la resuelve.
- **Compartición cruzada.** Todas las apps comparten el mismo CAS global y las
  mismas celdas.
- **Host contract v1.** Delegación selectiva de librerías universales, con
  **chequeo ABI** de los símbolos requeridos.
- **Sandbox reforzado (bubblewrap).** `--unshare-all`, `--cap-drop ALL`,
  **seccomp**, **D-Bus filtrado** (`xdg-dbus-proxy`), **HOME privado por app**,
  red granular (none/limited/full) y **X11 opt-in con autodetección**.
- **Capa por overlay.** `/app` se compone como overlay de A (app) sobre C
  (celdas), con S (host) vía `/usr`.
- **Firmas y distribución.** `.pbox` firmables (ed25519) y remoto HTTP con
  descarga delta concurrente.
- **4 modos de empaquetado.** Normal, Portable, Bundle, Module.

---

## Comparación con Flatpak

| Característica       | Flatpak (actual)            | Packbox v0.3.0                       |
|----------------------|-----------------------------|--------------------------------------|
| Unidad de reuso      | Runtime completo (~1 GB)    | **Celdas** por lib (sin runtimes)    |
| Deduplicación        | A nivel de archivo (OSTree) | A nivel de **chunk** (BLAKE3 + CDC)  |
| Almacenamiento       | Comprimido por runtime     | **Chunks crudos + hardlink** (dedup) |
| Compartición de libs | Dentro del mismo runtime    | Cruzada entre todas las apps         |
| Uso de libs del host | Ninguno                     | Selectivo (host contract + ABI)      |
| Actualizaciones      | Delta de objetos OSTree     | `packbox-update` (delta + GC LRU)    |
| Distribución         | Flathub + remotes OSTree    | Remoto HTTP concurrente              |
| Firmas               | GPG                         | ed25519 (`.pbox.sig`)                |
| Sandbox              | bwrap + seccomp + portales  | bwrap + seccomp + dbus-proxy + portales |
| Interfaz             | GNOME Software / CLI        | **TUI** + CLI                        |
| Overhead por app     | ~100 % si runtime distinto  | **~5–15 %** con apps que comparten   |

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

**Sin compilar (binarios precompilados del release):**

```bash
./packbox-install.sh --prebuilt
```

Descarga los binarios de tu arquitectura (amd64/arm64), verifica el `SHA256SUMS`
del release y los instala en segundos — sin compilar y sin Go.

### Paso 2 — Recargar el shell

```bash
source ~/.bashrc
```

### Paso 3 — Verificar

```bash
packbox-diagnose
```

---

## Uso rápido

### 1. Empaquetador interactivo (TUI)

```bash
./packbox-packager.sh
```

La opción **1 (Empaquetar)** busca las apps **ya instaladas** y **genera un**
`.pbox` en `~/.local/share/packbox/exports/`. Al terminar pregunta si además
quieres **instalarla en este equipo** (por defecto **no**, para no ensuciar tu
sistema). Para instalar un `.pbox` usa la opción **5 (Importar)**.

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

# ...o bajando del remoto solo el delta (los chunks que falten)
packbox-update org.ejemplo.miapp --from https://repo.ejemplo/mi-app
```

---

## Comandos disponibles

Packbox v0.3.0 incluye **15 binarios Go** en `~/.packbox/bin/`:

| Comando            | Propósito                                                          |
|--------------------|--------------------------------------------------------------------|
| `packbox-pack`     | Hashea un directorio en chunks CAS y genera `manifest.json`        |
| `packbox-install`  | Instala una app desde el manifiesto (+ `--desktop`/`--remove-desktop`) |
| `packbox-run`      | Ejecuta la app en el sandbox `bwrap` (overlay A/C, HOME privado)   |
| `packbox-list`     | Lista apps con su **tamaño real** y ahorro por sharing (`--tsv`)   |
| `packbox-remove`   | Desinstala una app (`--all` = todas, `--dry-run`) y libera sus refs |
| `packbox-gc`       | Recolecta chunks **y celdas** sin referencias (Soporta LRU)         |
| `packbox-verify`   | Comprueba libs resolubles + **compatibilidad ABI** del host        |
| `packbox-export`   | Exporta a `.pbox` con **compresión adaptativa** y `--sign` opcional |
| `packbox-import`   | Importa un `.pbox` (anti tar-slip, traversal y firmas)             |
| `packbox-update`   | Actualiza una app reusando chunks del store; `--from <url>` baja el delta |
| `packbox-module`   | Módulos/celdas: `list`, `create`, `cell <lib>...`                  |
| `packbox-sign`     | Claves y firmas ed25519: `keygen`, `sign`, `verify`, `trust`       |
| `packbox-fetch`    | Remoto HTTP: `publish`, `index`/`search`/`install` con **índice firmado**, y `fetch` (delta concurrente) |
| `packbox-debug`    | Adjunta los símbolos de debug (celda aparte) de una app instalada  |
| `packbox-diagnose` | Reporte del entorno para reportes de bugs                          |

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
                         │  HOME privado · seccomp · D-Bus filtrado   │
                         └──────────────────────────────────────────┘
```

### Componentes internos

- **CAS + chunker** — Guarda chunks crudos (sin recomprimir, para poder hardlinkear) por hash **BLAKE3**. Los archivos grandes se parten con **CDC optimizado**; los pequeños van como un solo chunk. Escrituras **atómicas**.
- **Manifiesto** (`schema_version: \"1.7\"`) — Mapea rutas a chunks, define la política de red (`none`, `limited`, `full`), la host contract y el símbolo X11.
- **Celdas** — Una lib = una celda `org.lib.<soname>@<hash>` en `mods/`. Compartidas entre apps. `packbox-gc` borra las no referenciadas o antiguas (LRU).
- **Sandbox** — `bwrap --unshare-all --cap-drop ALL --clearenv`, **seccomp**, **D-Bus filtrado** con `xdg-dbus-proxy`, **HOME privado**, red granular y **Soporte Multimedia** (PipeWire/PulseAudio).
- **Overlay de capas** — `/app` se compone con `--overlay-src` (C abajo, A arriba); S (host) llega vía `/usr`.
- **Host contract** — `packbox-verify` comprueba que el host provee los símbolos requeridos (ABI).
- **Firmas y remoto** — `packbox-sign` (ed25519) firma el `.pbox` y el **índice del repositorio**; `packbox-fetch` publica, **busca** (`search`) e instala por id, con **descargas concurrentes**.

---

## Seguridad

### Mitigaciones implementadas

- **Aislamiento de datos por app** — Cada app corre con su **HOME privado**; solo se exponen fuentes/temas en **solo lectura**.
- **D-Bus filtrado** — `xdg-dbus-proxy` con lista blanca (portales + `dconf`).
- **seccomp** — Filtro por defecto que bloquea superficie peligrosa del kernel.
- **Red Granular** — Modos `none`/`limited`/`full`. `limited` usa un proxy interno **best-effort** que bloquea rangos privados/reservados; solo afecta a apps que respetan `http_proxy`/`https_proxy` (los sockets crudos no se filtran).
- **Soporte Multimedia Seguro** — Acceso mediada a audio y cámara vía portales.
- **Anti tar-slip / traversal** — Validación estricta de rutas en `.pbox`.
- **Limpieza de entorno** — `--clearenv` + whitelist explícita.
- **Reference counting + LRU GC** — Limpieza inteligente de chunks basándose en el tiempo de acceso.
- **Firmas** — `.pbox` firmables con **ed25519**.

---

## Hoja de ruta

### v0.1.x — Estabilización
- [x] Verificación de firmas para `.pbox`
- [x] Sandbox reforzado: HOME privado, D-Bus filtrado, seccomp
- [x] Celdas automáticas + overlay de capas (A/C/S)
- [x] `packbox-update` con delta de chunks + GC automático
- [x] Remoto HTTP con descarga delta concurrente
- [x] Compresión Zstd en el export `.pbox`
- [x] Tuning de CDC para binarios ELF
- [x] Recolección de basura LRU

### v0.2 — Alcance
- [ ] Frontend GUI en GTK4 (aplazado)
- [x] Binarios precompilados x86_64 y aarch64
- [x] Índice/repositorio central firmado

### Futuro
- [ ] Importador de runtimes Flatpak (best-effort)
- [ ] Sandbox WASM para plugins no confiables

---

## Licencia

Distribuido bajo la **Apache License 2.0**. Ver [LICENSE](LICENSE).
