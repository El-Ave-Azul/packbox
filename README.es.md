[English](README.md) · **Español** · [Français](docs/fr/README.md) · [Deutsch](docs/de/README.md) · [Italiano](docs/it/README.md) · [简体中文](docs/zh-CN/README.md) · [繁體中文](docs/zh-TW/README.md) · [日本語](docs/ja/README.md) · [한국어](docs/ko/README.md)

---

![Licencia](https://img.shields.io/badge/Licencia-Apache_2.0-blue.svg)
![Versión](https://img.shields.io/badge/Versión-0.1.0--Alpha-orange.svg)
![Plataforma](https://img.shields.io/badge/Plataforma-Linux-blue.svg)
![Go](https://img.shields.io/badge/Go-1.22+-00ADD8.svg?logo=go&logoColor=white)
![i18n](https://img.shields.io/badge/i18n-9_idiomas-green.svg)
![Estado](https://img.shields.io/badge/Estado-Alpha-red.svg)

# Packbox

**Sistema de empaquetado de aplicaciones Linux con deduplicación binaria
a nivel de chunk.** Inspirado en Flatpak, pero con un modelo de
reutilización fundamentalmente distinto: en lugar de enviar un runtime
monolítico por aplicación, Packbox almacena cada archivo como chunks
direccionados por contenido (BLAKE3 CAS). Dos apps que comparten el 90% de
sus librerías solo almacenan el 10% que difiere.

> [!WARNING]
> **Estado Alpha (v0.1.0).** Los flujos principales funcionan, pero no hay
> verificación de firmas criptográficas en archivos `.pbox`, la política de
> red es global, y el sandbox es intencionalmente más permisivo que Flatpak.
> Úsalo primero en sistemas no críticos.

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

Packbox es un sistema de empaquetado de aplicaciones Linux que usa
**Content-Addressable Storage (CAS)** con hashing **BLAKE3** para lograr
deduplicación binaria real entre aplicaciones.

En lugar de enviar un runtime monolítico de ~1 GB por aplicación (como
Flatpak), Packbox almacena cada archivo como chunks direccionados por
contenido. Dos apps que comparten el 90% de sus librerías solo almacenan el
10% que difiere.

### Principios de diseño

- **Deduplicación a nivel de chunk.** Mismos bytes = mismo hash = almacenado
  una vez.
- **Compartición cruzada.** Todas las apps comparten el mismo almacén CAS
  global.
- **Host Contracts v1.** Delegación selectiva de librerías universales
  (`libc`, `libm`, `libdl`, `libpthread`, `libz`).
- **Sandbox con bubblewrap.** Aislamiento de namespaces con soporte GUI
  completo (X11, Wayland, D-Bus, `/dev/dri`).
- **4 modos de empaquetado.** Normal, Portable, Bundle, Module.

---

## Comparación con Flatpak

| Característica       | Flatpak (actual)             | Packbox v0.1.0                  |
|----------------------|------------------------------|---------------------------------|
| Unidad de reuso      | Runtime completo (~1 GB)     | Celda atómica (~5–50 MB)        |
| Deduplicación        | A nivel de archivo (OSTree)  | A nivel de chunk (BLAKE3 CAS)   |
| Compartición de libs | Dentro del mismo runtime     | Cruzada entre todas las apps    |
| Uso de libs del host | Ninguno (sandbox completo)   | Selectivo (ABI compatible)      |
| Actualizaciones      | Delta de objetos OSTree      | Delta de chunks + reordenación  |
| Overhead por app     | ~100% si runtime distinto    | ~5–15% (solo diferencias)       |

**Ahorro estimado**: en sistemas con 5–10 apps que comparten un conjunto
común de librerías, el ahorro de espacio observado está en el rango
**~90–99%** frente a empaquetar cada app con su runtime completo.

---

## Requisitos

- **Sistema operativo**: Linux (Debian 12+, Ubuntu 22.04+, Fedora 40+,
  Arch, openSUSE Tumbleweed)
- **Kernel**: 5.15+ con user namespaces habilitados
- **Shell**: Bash 4.0+
- **Go**: 1.22+ (se instala automáticamente si falta)
- **Espacio**: ~500 MB libres para la compilación inicial
- **Internet**: solo para la primera instalación

### Dependencias del sistema

Instaladas automáticamente por el instalador:

`bubblewrap` · `binutils` · `jq` · `bc` · `curl` · `tar`

---

## Instalación

### Paso 1 — Clonar y ejecutar

```bash
git clone https://github.com/El-Ave-Azul/packbox.git
cd packbox
chmod +x packbox-installer-v0.1.0.sh
./packbox-installer-v0.1.0.sh
```

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
4. Descarga e instala Go 1.22+ en `/usr/local/go` si no lo detecta.
5. Crea la estructura de directorios (`~/.packbox/` y
   `~/.local/share/packbox/`).
6. Genera el proyecto Go completo con los 11 binarios.
7. Compila todos los binarios nativamente (~2–3 minutos).
8. Configura tu `PATH` en `~/.bashrc` y crea symlinks en `~/.local/bin`.
9. Instala los archivos de traducción en `~/.config/packbox/lang/`.
10. Verifica que todos los binarios estén presentes y funcionales.

### Desinstalación

Ejecuta el mismo script y elige la opción `2`:

```bash
./packbox-installer-v0.1.0.sh
# Seleccionar opción 2 (Desinstalar)
```

| Modo | Descripción                                                              |
|------|--------------------------------------------------------------------------|
| `s`  | Completo: binarios + apps + store CAS + menús + iconos + configuración   |
| `k`  | Solo binarios: `~/.packbox/` y symlinks (conserva apps y store CAS)      |
| `q`  | Cancelar                                                                 |

Requiere escribir `DELETE` en mayúsculas para confirmar.

---

## Uso rápido

### 1. Empaquetador interactivo (recomendado)

```bash
./packbox-packager-v0.1.0.sh
```

Menú: empaquetar, listar, garbage collection, exportar, importar,
desinstalar.

El empaquetador detecta automáticamente aplicaciones desde:

- Archivos `.desktop` en `/usr/share/applications/`
- Bundles en `/opt/*` (con symlink en `/usr/bin`)
- Binarios comunes (`htop`, `vlc`, `firefox`, `gimp`, etc.)

### 2. Línea de comandos

```bash
# Empaquetar un directorio
packbox-pack ./mi-app --name org.ejemplo.miapp --version 1.0.0

# Instalar desde el manifiesto generado
packbox-install ./mi-app/manifest.json

# Ejecutar en sandbox
packbox-run org.ejemplo.miapp

# Listar apps instaladas
packbox-list

# Desinstalar y liberar espacio
packbox-remove org.ejemplo.miapp
packbox-gc
```

### 3. Exportar e importar

```bash
# Exportar a archivo .pbox
packbox-export app org.ejemplo.miapp

# Importar en otra máquina
packbox-import app org.ejemplo.miapp.pbox
```

---

## Comandos disponibles

Packbox v0.1.0 Alpha incluye **11 binarios Go** compilados en
`~/.packbox/bin/`:

| Comando            | Propósito                                                       |
|--------------------|-----------------------------------------------------------------|
| `packbox-pack`     | Hashea un directorio en chunks CAS y genera `manifest.json`     |
| `packbox-install`  | Instala una app desde el manifiesto (hardlinks desde CAS)       |
| `packbox-run`      | Ejecuta la app en sandbox `bwrap` (con fix DNS y GUI)           |
| `packbox-list`     | Lista apps instaladas con versión y etiquetas                   |
| `packbox-remove`   | Desinstala una app y libera sus referencias CAS                 |
| `packbox-gc`       | Recolecta y elimina chunks huérfanos                            |
| `packbox-verify`   | Verifica compatibilidad de librerías del host vía `ldd`         |
| `packbox-export`   | Exporta una app a archivo `.pbox` comprimido (zstd/xz/gzip)     |
| `packbox-import`   | Importa un `.pbox` con validación anti path-traversal           |
| `packbox-module`   | Gestiona módulos de librerías compartidas                       |
| `packbox-diagnose` | Genera reporte del entorno para reportes de bugs                |

Referencia completa con opciones, códigos de salida y ejemplos:
[`docs/es/commands.md`](docs/es/commands.md)

---

## Estructura de archivos

```
~/.packbox/                              # Instalación
├── bin/                                 # 11 binarios Go compilados
└── src/                                 # Código fuente Go

~/.local/share/packbox/                  # Datos de usuario
├── store/                               # CAS: chunks por hash BLAKE3
│   └── <ab>/<hash-completo>             # + archivo .refs por chunk
├── apps/                                # Apps instaladas
│   └── <app-id>/
│       ├── manifest.json
│       └── tree/                        # Hardlinks al CAS
├── mods/                                # Módulos compartidos
├── exports/                             # Archivos .pbox
└── tmp/                                 # Temporales

~/.config/packbox/
└── lang/                                # 9 archivos de idioma
```

---

## Arquitectura

### Flujo de empaquetado

```
┌──────────────┐   pack    ┌──────────────┐  install  ┌──────────────┐
│  Dir fuente  │ ────────► │     CAS      │ ─────────► │  Tree de app │
│  (árbol fs)  │           │  (chunks)    │           │ (hardlinks)  │
└──────────────┘           └──────────────┘           └──────────────┘
                                  │
                                  │ run
                                  ▼
                         ┌──────────────────┐
                         │  Sandbox bwrap   │
                         │ (fix DNS + GUI)  │
                         └──────────────────┘
```

### Componentes internos

- **CAS** — Almacena chunks por hash BLAKE3. Usa `SafeLink` (hardlink con
  fallback a copia si es cross-device).
- **Manifiesto** — `schema_version: "1.5"`. Mapea rutas a chunks, define
  `host_contract.delegate` para delegación selectiva de librerías.
- **Sandbox** — `bwrap --unshare-all --share-net`. Resuelve symlinks DNS
  (`filepath.EvalSymlinks`) antes de bindear `/etc/resolv.conf`, lo que
  soluciona el clásico bug "sin DNS dentro del sandbox" en hosts con
  systemd-resolved. Soporte GUI completo: X11, Wayland, D-Bus, `/dev/dri`,
  caché de fontconfig.

Arquitectura completa (CAS internals, esquema del manifiesto, mounts del
sandbox, host contracts): [`docs/es/architecture.md`](docs/es/architecture.md)

### Cómo funciona la deduplicación

Ejemplo con 3 apps que comparten una parte común de sus librerías:

```
App 1: htop     → chunks: [A, B, C]
App 2: neofetch → chunks: [A, D, E]
App 3: btop     → chunks: [A, B, F]

CAS Store:
  A → referencias: htop, neofetch, btop      (3 apps)
  B → referencias: htop, btop                (2 apps)
  C → referencias: htop                      (1 app)
  D → referencias: neofetch                  (1 app)
  E → referencias: neofetch                  (1 app)
  F → referencias: btop                      (1 app)

Total: 6 chunks únicos almacenados en lugar de 9 chunks brutos.
```

Con más apps sobre el mismo sistema el ahorro escala: cuanto mayor sea la
superposición de librerías, mayor es la deduplicación efectiva.

---

## Seguridad

### Mitigaciones implementadas

- **Anti path-traversal** — `cas.isValidHash()` valida exactamente 64
  caracteres hex lowercase. La importación `.pbox` valida cada entrada TAR
  contra la raíz de extracción vía `security.ValidatePath`.
- **Importación segura ante symlinks** — El extractor TAR solo procesa
  `tar.TypeDir` y `tar.TypeReg`. Symlinks, hardlinks y device files se
  ignoran silenciosamente, previniendo escapes por symlink.
- **Limpieza de entorno** — `--clearenv` seguido de una whitelist explícita
  bloquea inyección de `LD_PRELOAD` y `LD_LIBRARY_PATH` desde el host.
- **Aislamiento de XAUTHORITY** — Se copia a
  `/tmp/packbox-xauth-<pid>` con modo `0600` (único por proceso) antes de
  bindearse al sandbox. La app en sandbox nunca ve el archivo original.
- **Reference counting** — Cada chunk tiene un archivo `.refs`.
  `packbox-gc` solo borra chunks sin referencias, previniendo
  use-after-free de chunks compartidos.
- **Sin setuid, sin root** — Todo corre como el usuario que invoca Packbox.
  `sudo` solo se usa en la instalación de dependencias del sistema.
- **SafeLink** — Hardlinks con fallback automático a copia segura si el
  sistema de archivos destino no soporta hardlinks.

### Limitaciones conocidas (v0.1.0 Alpha)

> [!WARNING]
> Estos puntos están **en desarrollo activo** y son las áreas donde más
> feedback se agradece.

- ❌ **Sin verificación de firmas** criptográficas en archivos `.pbox`.
  Trata cualquier `.pbox` importado como no confiable.
- ❌ **Política de red global.** `--share-net` se aplica a todas las apps.
  No hay firewall por aplicación todavía.
- ❌ **Sandbox más permisivo que Flatpak.** Se montan más directorios para
  soportar GUI (X11, Wayland, D-Bus, `/dev/dri`). Es un tradeoff deliberado
  para el primer release.
- ❌ **`packbox-module remove` e `info`** declarados pero no implementados.
- ❌ **`host_contract.delegate`** implementado en el esquema pero sin
  stress-testing contra apps GTK4/Qt6 reales.

Modelo de amenazas completo: [`docs/es/security.md`](docs/es/security.md)

---

## Hoja de ruta

### v0.1.x — Estabilización

- [ ] Verificación de firmas para `.pbox` (minisign o sigstore)
- [ ] Política de red por aplicación
- [ ] Completar `packbox-module remove` e `info`
- [ ] Stress test de `host_contract.delegate` con apps GTK4/Qt6 reales
- [ ] CI/CD: `shellcheck`, `gofmt`, `go vet` en cada PR
- [ ] Matriz de tests: Debian 12, Fedora 40, Arch, openSUSE Tumbleweed

### v0.2 — Alcance

- [ ] Binarios precompilados x86_64 y aarch64 (página de releases)
- [ ] Comando `packbox-update` para actualizaciones in-place
- [ ] Descargas delta a nivel de chunk para `packbox-export`
- [ ] Frontend GUI opcional (GTK4)

### Futuro

- [ ] Importador de runtimes Flatpak (best-effort)
- [ ] Sandbox WASM para plugins no confiables
- [ ] Repositorio central de módulos compartidos

---

## Contribuir

¡Contribuciones bienvenidas! Áreas donde la ayuda es especialmente útil:

- **Traducciones** — Añade un locale a `packbox-i18n.sh` copiando el bloque
  `en` en `install_lang_files()` y traduciendo cada clave `L_*`.
- **Perfiles de sandbox** — Mejora los mapas de datos por app en
  `internal/sandbox/sandbox.go` (browsers, IDEs, juegos).
- **Chunking** — Investiga rolling hash o chunking paralelo para el CAS.
- **Reportes de bugs** — Incluye siempre la salida de `packbox-diagnose`.

### Cómo empezar

```bash
git clone https://github.com/El-Ave-Azul/packbox.git
cd packbox
# Lee CONTRIBUTING.md para las guías completas
```

- 🐛 [Abrir un issue](https://github.com/El-Ave-Azul/packbox/issues)
- 💬 [Iniciar una discusión](https://github.com/El-Ave-Azul/packbox/discussions)
- 🔧 [CONTRIBUTING.md](CONTRIBUTING.md)

> [!TIP]
> Ejecuta `shellcheck` sobre scripts bash y `gofmt` + `go vet` sobre Go
> antes de enviar un PR. Los mantenedores revisamos estos puntos en cada
> pull request.

---

## Licencia

Distribuido bajo la **Apache License 2.0**. Ver [LICENSE](LICENSE).

Elegimos Apache 2.0 sobre MIT para proporcionar una **cláusula explícita de
concesión de patentes**, que protege tanto a usuarios como a contribuyentes
frente a litigios relacionados con las técnicas de deduplicación y
sandboxing implementadas en Packbox. Apache 2.0 es además compatible con
GPLv3, lo que facilita la integración futura con otros proyectos del
ecosistema Linux.

---

## Agradecimientos

- **[bubblewrap](https://github.com/containers/bubblewrap)** — Primitive de
  sandbox para Linux que hace posible `packbox-run`.
- **[BLAKE3](https://github.com/BLAKE3-team/BLAKE3)** — Hashing de contenido
  rápido y criptográficamente seguro.
- **[Flatpak](https://flatpak.org/)** — Demostró que las apps Linux
  sandboxeadas funcionan a escala; muchas de sus decisiones de diseño
  informaron las nuestras, incluso donde divergimos.
- **Comunidad Linux global** — La capa i18n de 9 idiomas existe gracias a
  sus revisiones y contribuciones.
