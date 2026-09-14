<!-- Selector de idioma -->
[English](README.md) · **Español** · [Français](docs/fr/README.md) · [Deutsch](docs/de/README.md) · [Italiano](docs/it/README.md) · [简体中文](docs/zh-CN/README.md) · [繁體中文](docs/zh-TW/README.md) · [日本語](docs/ja/README.md) · [한국어](docs/ko/README.md)

---

<!-- Insignias -->
![Licencia: MIT](https://img.shields.io/badge/Licencia-MIT-yellow.svg)
![Plataforma: Linux](https://img.shields.io/badge/plataforma-Linux-blue)
![Versión](https://img.shields.io/badge/versión-0.1.0--alpha-orange)
![Go](https://img.shields.io/badge/Go-1.22+-00ADD8?logo=go&logoColor=white)
![i18n](https://img.shields.io/badge/i18n-9_idiomas-green)
![Estado](https://img.shields.io/badge/estado-alpha-red)

# Packbox

**Sistema de empaquetado de aplicaciones de nueva generación para Linux.**
Inspirado en Flatpak, pero con un modelo de reutilización fundamentalmente
distinto: en lugar de enviar un runtime monolítico por aplicación, Packbox
almacena cada archivo como chunks direccionados por contenido (BLAKE3 CAS).
Dos apps que comparten el 90% de sus librerías solo almacenan el 10% que
difiere.

> [!NOTE]
> **Packbox está en Alpha (v0.1.0).** Los flujos principales funcionan, pero
> todavía no hay verificación de firmas en archivos `.pbox` y el sandbox es
> intencionalmente más permisivo que Flatpak. Úsalo primero en sistemas no
> críticos.

---

## Tabla de contenidos

- [Por qué Packbox](#por-qué-packbox)
- [Comparación con Flatpak](#comparación-con-flatpak)
- [Requisitos](#requisitos)
- [Instalación](#instalación)
- [Uso rápido](#uso-rápido)
- [Comandos](#comandos)
- [Estructura del sistema de archivos](#estructura-del-sistema-de-archivos)
- [Arquitectura](#arquitectura)
- [Seguridad](#seguridad)
- [Hoja de ruta](#hoja-de-ruta)
- [Documentación](#documentación)
- [Contribuir](#contribuir)
- [Licencia](#licencia)
- [Agradecimientos](#agradecimientos)

---

## Por qué Packbox

Flatpak resolvió un problema real: apps Linux sandboxeadas y portables. Pero
su modelo de reutilización es grueso. Cada app envía (o referencia) un
runtime completo que puede pesar **~1 GB**. Si dos apps usan runtimes
distintos, pagas el costo dos veces — incluso si comparten el 95% de sus
librerías.

Packbox ataca ese hueco específico:

- **Deduplicación a nivel de chunk.** Los archivos se dividen, se hashean
  con BLAKE3 y se almacenan como chunks. Chunks idénticos (una
  `libfoo.so.3.2.1`, una fuente, un catálogo de traducciones) se comparten
  entre todas las apps del sistema.
- **Compartición de librerías entre apps.** Dos apps que usan la misma
  `libQt6Core.so` mantienen una sola copia en disco, sin importar a qué
  "runtime" pertenezcan.
- **Uso selectivo de librerías del host.** Las apps pueden declarar en qué
  librerías del host confían (vía `host_contract.delegate`), en vez de
  empaquetar todo.
- **Huella pequeña por app.** En la práctica, añadir una nueva app sobre un
  conjunto existente cuesta ~5–15% de su tamaño, no ~100%.

Packbox **no** intenta reemplazar a Flatpak. Explora un nicho distinto: apps
que no encajan limpiamente en un runtime, o donde enviar 1 GB para correr
una herramienta de 50 MB es exagerado.

---

## Comparación con Flatpak

| Característica       | Flatpak (actual)                 | Packbox (propuesto)             |
|----------------------|----------------------------------|---------------------------------|
| Unidad de reuso      | Runtime completo (~1 GB)         | Celda atómica (~5–50 MB)        |
| Deduplicación        | A nivel de archivo (OSTree)      | A nivel de chunk (BLAKE3 CAS)   |
| Compartición de libs | Dentro del mismo runtime         | Cruzada entre todas las apps    |
| Uso de libs del host | Ninguno (sandbox completo)       | Selectivo (ABI compatible)      |
| Actualizaciones      | Delta de objetos OSTree          | Delta de chunks + reordenación  |
| Overhead por app     | ~100% si runtime distinto        | ~5–15% (solo diferencias)       |

---

## Requisitos

- **Linux** (probado en Debian 12, Fedora 40, Arch actual)
- **Bash 4+**
- **Go 1.22+** (auto-instalado si falta)
- **bubblewrap** (`bwrap`) — auto-instalado
- **binutils** (`ldd`, `readelf`) — auto-instalado
- **Herramientas de compresión**: `zstd`, `xz`, `gzip` (al menos una)
- **~500 MB libres** para el build + toolchain si Go se instala desde cero

Familias soportadas: **Debian/Ubuntu/Mint/Pop**, **Fedora/RHEL/Rocky**,
**Arch/Manjaro/EndeavourOS**, **openSUSE**.

---

## Instalación

```bash
git clone https://github.com/El-Ave-Azul/packbox.git
cd packbox
./packbox-installer-v0.1.0.sh
source ~/.bashrc
packbox-diagnose
```

El instalador es interactivo y:

1. Detecta tu distro y gestor de paquetes.
2. Pregunta antes de instalar dependencias
   (`bubblewrap binutils jq bc curl tar`).
3. Instala Go 1.22+ si falta.
4. Crea `~/.packbox/{bin,src}` y
   `~/.local/share/packbox/{store,apps,mods,exports,tmp}`.
5. Genera 11 binarios Go + paquetes internos desde el código local.
6. Compila todo (~2–3 minutos en hardware moderno).
7. Añade `~/.packbox/bin` al `PATH` y crea symlinks en `~/.local/bin`.
8. Verifica que los 11 binarios estén presentes.

**Idiomas**: el instalador pregunta por uno de 9 locales al inicio —
English, Español, Français, Deutsch, Italiano, 简体中文, 繁體中文, 日本語,
한국어.

### Desinstalación

Ejecuta el mismo script y elige la opción `2`:

- Modo `s` → eliminación completa (binarios + apps + store + menús + config)
- Modo `k` → solo binarios (conserva apps y store)
- Modo `q` → cancelar

Requiere escribir `DELETE` para confirmar.

---

## Uso rápido

### Empaquetador interactivo (recomendado para nuevos usuarios)

```bash
./packbox-packager-v0.1.0.sh
```

Menú: empaquetar, listar, gc, exportar, importar, desinstalar.

### Línea de comandos

```bash
# 1. Empaquetar un directorio en chunks CAS + manifest.json
packbox-pack ./firefox-tree \
    --name org.mozilla.firefox \
    --version 128.0 \
    --description "Mozilla Firefox" \
    --gui --toolkit GTK3

# 2. Instalar desde el manifest generado
packbox-install ./firefox-tree/manifest.json

# 3. Ejecutar dentro de un sandbox bwrap (con fix DNS + GUI)
packbox-run org.mozilla.firefox

# 4. Ver qué está instalado
packbox-list

# 5. Desinstalar y liberar chunks
packbox-remove org.mozilla.firefox
packbox-gc
```

---

## Comandos

Once binarios Go, todos en `~/.packbox/bin/`:

| Comando             | Propósito                                                   |
|---------------------|-------------------------------------------------------------|
| `packbox-pack`      | Hashear un directorio en chunks CAS + `manifest.json`       |
| `packbox-install`   | Instalar desde manifest (hardlink desde CAS)                |
| `packbox-run`       | Ejecutar dentro de `bwrap` con DNS + GUI                    |
| `packbox-list`      | Listar apps instaladas con versión y etiquetas              |
| `packbox-remove`    | Desinstalar app y liberar sus referencias CAS               |
| `packbox-gc`        | Recolectar chunks huérfanos                                 |
| `packbox-verify`    | Verificación de compatibilidad de libs vía `ldd`            |
| `packbox-export`    | Exportar app a `.pbox` (zstd/xz/gzip)                       |
| `packbox-import`    | Importar `.pbox` con validación anti path-traversal         |
| `packbox-module`    | Gestionar módulos de librerías compartidas (`list`, `create`) |
| `packbox-diagnose`  | Imprimir reporte del entorno para reportes de bugs          |

Referencia completa con opciones, códigos de salida y ejemplos:
[`docs/es/commands.md`](docs/es/commands.md) ·
[`docs/en/commands.md`](docs/en/commands.md)

### Scripts interactivos

- `packbox-installer-v0.1.0.sh` — instalar / desinstalar
- `packbox-packager-v0.1.0.sh` — empaquetar, listar, gc, exportar, importar, desinstalar
- `packbox-i18n.sh` — capa de traducción compartida (sourceada por los dos anteriores)

---

## Estructura del sistema de archivos

```
~/.packbox/                     # Instalación (binarios + código Go)
├── bin/                        # 11 binarios Go
└── src/                        # Código fuente del módulo Go

~/.local/share/packbox/         # Datos
├── store/                      # CAS — chunks por hash BLAKE3
│   └── <ab>/<hash-completo>    # más un archivo .refs por chunk
├── apps/                       # Apps instaladas (tree + manifest.json)
├── mods/                       # Módulos de librerías compartidas
├── exports/                    # Archivos .pbox
└── tmp/                        # Espacio de trabajo temporal

~/.config/packbox/lang/         # 9 archivos de idioma
```

---

## Arquitectura

Tres piezas móviles:

```
┌──────────────┐   pack    ┌──────────────┐   install   ┌──────────────┐
│  Dir fuente  │ ────────► │     CAS      │ ──────────► │  Tree de app │
│  (árbol fs)  │           │  (chunks)    │             │ (hardlinks)  │
└──────────────┘           └──────────────┘             └──────────────┘
                                  │
                                  │ run
                                  ▼
                         ┌──────────────────┐
                         │  Sandbox bwrap   │
                         │  (fix DNS/GUI)   │
                         └──────────────────┘
```

- **CAS** — `~/.local/share/packbox/store/`, hashes BLAKE3, un archivo
  `.refs` por chunk, `SafeLink` (hardlink → copia como fallback) al instalar.
- **Manifest** — `schema_version: "1.5"`, `layers.app.files` mapea rutas
  relativas a `{chunks, size, mode}`, más `host_contract.delegate` para
  confianza en librerías del host.
- **Sandbox** — `bwrap --unshare-all --share-net`, whitelist de env después
  de `--clearenv`, resolución de symlinks DNS (`EvalSymlinks`) antes de
  bindear `/etc/resolv.conf`, soporte GUI (X11, Wayland, D-Bus, `/dev/dri`,
  caché fontconfig), mapa heurístico de datos por app con `--bind-try`.

Arquitectura completa (internals del CAS, esquema del manifest, mounts del
sandbox, host contract):
[`docs/es/architecture.md`](docs/es/architecture.md) ·
[`docs/en/architecture.md`](docs/en/architecture.md)

---

## Seguridad

> [!WARNING]
> Los archivos `.pbox` **no están firmados** en v0.1.0 Alpha. Trata cualquier
> archivo importado como no confiable. La verificación de firmas está en la
> hoja de ruta.

Mitigaciones ya implementadas:

- **Protección anti path-traversal** — `cas.isValidHash()` exige 64 chars
  hex lowercase. La importación `.pbox` valida cada entrada tar contra la
  raíz de extracción vía `security.ValidatePath`.
- **Importación segura ante symlinks** — solo se manejan `tar.TypeDir` y
  `tar.TypeReg`; symlinks, hardlinks y device files se saltan silenciosamente.
- **Limpieza de entorno** — `--clearenv` seguido de whitelist explícita
  bloquea inyección de `LD_PRELOAD` / `LD_LIBRARY_PATH` desde el host.
- **Aislamiento de XAUTHORITY** — el `~/.Xauthority` del host se copia a un
  archivo temporal por proceso (`/tmp/packbox-xauth-<pid>`, modo 0600) antes
  de bindearse al sandbox.
- **Reference counting** — cada chunk tiene un archivo `.refs`;
  `packbox-gc` solo borra chunks no referenciados.
- **Sin setuid, sin root** — Packbox corre enteramente como el usuario que
  lo invoca. `sudo` solo lo usa el instalador para paquetes de la distro.

Limitaciones conocidas y modelo de amenazas:
[`docs/es/security.md`](docs/es/security.md) ·
[`docs/en/security.md`](docs/en/security.md)

Reporta vulnerabilidades con la salida de `packbox-diagnose` adjunta. Para
hallazgos sensibles, usa el contacto privado de seguridad del repositorio.

---

## Hoja de ruta

### v0.1.x — Estabilización
- [ ] Verificación de firmas para archivos `.pbox`
- [ ] Política de red por app (actualmente `--share-net` es global)
- [ ] Implementar `packbox-module remove` e `info`
- [ ] Probar `host_contract.delegate` contra apps reales GTK4/Qt6
- [ ] CI: `shellcheck`, `gofmt`, `go vet` en cada PR
- [ ] Matriz de tests: Debian 12, Fedora 40, Arch, openSUSE Tumbleweed

### v0.2 — Alcance
- [ ] Binarios precompilados para x86_64 y aarch64 (página de releases)
- [ ] `packbox-update` para subir versiones in-place
- [ ] Frontend GUI (opcional, GTK4)
- [ ] Descargas delta a nivel de chunk para `packbox-export`

### Más adelante
- [ ] Importador de runtimes Flatpak (best-effort)
- [ ] Verificación de firmas vía minisign o sigstore
- [ ] Sandbox WASM opcional para plugins no confiables

---

## Documentación

Documentación completa en 9 idiomas. Inglés y español tienen el set completo
(README + comandos + arquitectura + seguridad); los otros siete tienen
README + comandos.

| Idioma   | README                                 | Comandos                                       | Arquitectura                                        | Seguridad                                     |
|----------|----------------------------------------|------------------------------------------------|-----------------------------------------------------|-----------------------------------------------|
| English  | [en](docs/en/README.md)                | [en](docs/en/commands.md)                      | [en](docs/en/architecture.md)                       | [en](docs/en/security.md)                     |
| Español  | [es](docs/es/README.md)                | [es](docs/es/commands.md)                      | [es](docs/es/architecture.md)                       | [es](docs/es/security.md)                     |
| Français | [fr](docs/fr/README.md)                | [fr](docs/fr/commands.md)                      | —                                                   | —                                             |
| Deutsch  | [de](docs/de/README.md)                | [de](docs/de/commands.md)                      | —                                                   | —                                             |
| Italiano | [it](docs/it/README.md)                | [it](docs/it/commands.md)                      | —                                                   | —                                             |
| 简体中文 | [zh-CN](docs/zh-CN/README.md)          | [zh-CN](docs/zh-CN/commands.md)                | —                                                   | —                                             |
| 繁體中文 | [zh-TW](docs/zh-TW/README.md)          | [zh-TW](docs/zh-TW/commands.md)                | —                                                   | —                                             |
| 日本語   | [ja](docs/ja/README.md)                | [ja](docs/ja/commands.md)                      | —                                                   | —                                             |
| 한국어   | [ko](docs/ko/README.md)                | [ko](docs/ko/commands.md)                      | —                                                   | —                                             |

Índice: [`docs/README.md`](docs/README.md)

---

## Contribuir

Contribuciones bienvenidas, especialmente:

- **Traducciones** — añade un nuevo locale a `packbox-i18n.sh` copiando el
  bloque `en` de `install_lang_files()` y traduciendo cada clave `L_*`.
- **Perfiles de sandbox** — mapas de datos por app para navegadores, IDEs,
  juegos.
- **Estrategias de chunking del CAS** — variantes de rolling hash, chunking
  paralelo.
- **Reportes de bugs** — incluye siempre la salida de `packbox-diagnose`.

Cómo empezar:

```bash
git clone https://github.com/TU_USUARIO/packbox.git
cd packbox
# Lee CONTRIBUTING.md para las guías completas
```

- 🐛 [Abrir un issue](https://github.com/TU_USUARIO/packbox/issues)
- 💬 [Iniciar una discusión](https://github.com/TU_USUARIO/packbox/discussions)
- 🔧 [CONTRIBUTING.md](CONTRIBUTING.md)

Por favor corre `shellcheck` sobre los scripts shell y `gofmt` + `go vet`
sobre el código Go antes de enviar un PR.

---

## Licencia

[MIT](LICENSE) © 2025 TU_NOMBRE

Packbox es libre de usar, modificar y redistribuir. Ver [LICENSE](LICENSE)
para detalles.

---

## Agradecimientos

- **[bubblewrap](https://github.com/containers/bubblewrap)** — la primitiva
  de sandbox que hace posible `packbox-run`.
- **[BLAKE3](https://github.com/BLAKE3-team/BLAKE3)** — content-addressing
  rápido y seguro.
- **[Flatpak](https://flatpak.org/)** — el proyecto que demostró que las apps
  Linux sandboxeadas funcionan a escala, y cuyas decisiones de diseño
  informaron muchas de las nuestras (incluso donde divergimos).
- La capa i18n de 9 idiomas existe porque la comunidad Linux es global;
  gracias a todos los que han revisado las traducciones.
