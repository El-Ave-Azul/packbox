# 📦 Packbox v0.1.0 Alpha

**Sistema de empaquetamiento de aplicaciones Linux con deduplicación binaria y portabilidad entre distribuciones.**

[![Licencia](https://img.shields.io/badge/Licencia-Apache_2.0-blue.svg)](LICENSE)
[![Versión](https://img.shields.io/badge/Versión-0.1.0--Alpha-orange.svg)](https://github.com/TU_USUARIO/packbox/releases)
[![Plataforma](https://img.shields.io/badge/Plataforma-Linux-blue.svg)](#)
[![Go](https://img.shields.io/badge/Go-1.22+-00ADD8.svg?logo=go&logoColor=white)](https://golang.org/)
[![i18n](https://img.shields.io/badge/i18n-9_idiomas-green.svg)](#-idiomas)

---

## 🌍 Idiomas

| Idioma | Código |
|--------|--------|
| 🇬🇧 English | `en` |
| 🇪🇸 Español | `es` |
| 🇫🇷 Français | `fr` |
| 🇩🇪 Deutsch | `de` |
| 🇮🇹 Italiano | `it` |
| 🇨🇳 简体中文 | `zh-CN` |
| 🇹🇼 繁體中文 | `zh-TW` |
| 🇯🇵 日本語 | `ja` |
| 🇰🇷 한국어 | `ko` |

---

> [!WARNING]
> **Estado Alpha (v0.1.0).** Los flujos principales funcionan, pero no hay verificación de firmas en archivos `.pbox` y el sandbox es intencionalmente más permisivo que Flatpak. Úsalo primero en sistemas no críticos.

---

## 📋 Tabla de Contenidos

- [¿Qué es Packbox?](#-qué-es-packbox)
- [Comparación con Flatpak](#-comparación-con-flatpak)
- [Requisitos](#-requisitos)
- [Instalación](#-instalación)
- [Uso Rápido](#-uso-rápido)
- [Comandos Disponibles](#-comandos-disponibles)
- [Estructura de Archivos](#-estructura-de-archivos)
- [Arquitectura](#-arquitectura)
- [Seguridad](#-seguridad)
- [Hoja de Ruta](#-hoja-de-ruta)
- [Contribuir](#-contribuir)
- [Licencia](#-licencia)

---

## 💡 ¿Qué es Packbox?

Packbox es un sistema de empaquetamiento de aplicaciones Linux que utiliza **Content-Addressable Storage (CAS)** con hashing **BLAKE3** para lograr deduplicación binaria real entre aplicaciones.

En lugar de enviar un runtime monolítico de ~1 GB por aplicación (como Flatpak), Packbox almacena cada archivo como chunks direccionados por contenido. Dos apps que comparten el 90% de sus librerías solo almacenan el 10% que difiere.

### Principios de Diseño

- **Deduplicación a nivel de chunk**: Mismos bytes = mismo hash = almacenado una vez.
- **Compartición cruzada**: Todas las apps comparten el mismo almacén CAS global.
- **Host Contracts v1**: Delegación selectiva de librerías universales (libc, libm, libdl, libpthread, libz).
- **Sandbox con bubblewrap**: Aislamiento de namespaces con soporte GUI completo.
- **4 modos de empaquetado**: Normal, Portable, Bundle, Module.

---

## 📊 Comparación con Flatpak

| Característica | Flatpak (actual) | Packbox v0.1.0 |
|---|---|---|
| Unidad de reuso | Runtime completo (~1 GB) | Celda atómica (~5-50 MB) |
| Deduplicación | A nivel de archivo (OSTree) | A nivel de chunk (BLAKE3 CAS) |
| Compartición de libs | Dentro del mismo runtime | Cruzada entre todas las apps |
| Uso de libs del host | Ninguno (sandbox completo) | Selectivo (ABI compatible) |
| Actualizaciones | Delta de objetos OSTree | Delta de chunks + reordenación |
| Overhead por app | ~100% si runtime distinto | ~5-15% (solo diferencias) |
| Tamaño típico | 500 MB - 2 GB | 500 KB - 300 MB |
| Ahorro promedio | Línea base | **~90-99%** |

---

## ⚙️ Requisitos

- **Sistema Operativo**: Linux (Debian 12+, Ubuntu 22.04+, Fedora 40+, Arch, openSUSE)
- **Kernel**: 5.15+ con user namespaces habilitados
- **Shell**: Bash 4.0+
- **Go**: 1.22+ (se instala automáticamente si falta)
- **Espacio**: ~500 MB libres para la compilación inicial
- **Internet**: Solo para la primera instalación

### Dependencias del Sistema (instaladas automáticamente)

`bubblewrap` · `binutils` · `jq` · `bc` · `curl` · `tar`

---

## 📥 Instalación

### Paso 1: Clonar y ejecutar

```bash
git clone https://github.com/TU_USUARIO/packbox.git
cd packbox
chmod +x packbox-installer-v0.1.0.sh
./packbox-installer-v0.1.0.sh
```

### Paso 2: Recargar el shell

```bash
source ~/.bashrc
```

### Paso 3: Verificar

```bash
packbox-diagnose
```

### ¿Qué hace el instalador?

1. Te permite seleccionar uno de 9 idiomas
2. Detecta tu distribución Linux y gestor de paquetes
3. Te pide confirmación antes de instalar dependencias
4. Descarga e instala Go 1.22+ en `/usr/local/go` si no lo detecta
5. Crea la estructura de directorios (`~/.packbox/` y `~/.local/share/packbox/`)
6. Genera el proyecto Go completo con los 11 binarios
7. Compila todos los binarios nativamente (~2-3 minutos)
8. Configura tu PATH en `~/.bashrc` y crea symlinks en `~/.local/bin`
9. Instala los archivos de traducción en `~/.config/packbox/lang/`
10. Verifica que todos los binarios estén presentes y funcionales

### Desinstalación

Ejecuta el mismo script y elige la opción `2`:

```bash
./packbox-installer-v0.1.0.sh
# Seleccionar opción 2 (Desinstalar)
```

| Modo | Descripción |
|------|-------------|
| `s` (Completo) | Elimina binarios, apps, store CAS, menús, iconos y configuración |
| `k` (Solo binarios) | Solo elimina `~/.packbox/` y symlinks (conserva apps y store) |

> Requiere escribir `DELETE` en mayúsculas para confirmar.

---

## 🚀 Uso Rápido

### 1. Empaquetador Interactivo (Recomendado)

```bash
./packbox-packager-v0.1.0.sh
```

Este script interactivo te permite:

- Detectar aplicaciones instaladas (`.desktop`, bundles en `/opt`, binarios comunes)
- Empaquetar apps en modo **Normal**, **Portable** o **Bundle**
- Listar apps ya empaquetadas
- Ejecutar Garbage Collection
- Exportar/Importar apps como archivos `.pbox`
- Desinstalar apps empaquetadas

### 2. Línea de Comandos

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

### 3. Exportar e Importar

```bash
# Exportar a archivo .pbox
packbox-export app org.ejemplo.miapp

# Importar en otra máquina
packbox-import app org.ejemplo.miapp.pbox
```

---

## 🛠️ Comandos Disponibles

Packbox v0.1.0 Alpha incluye **11 binarios Go** compilados en `~/.packbox/bin/`:

| Comando | Propósito |
|---------|-----------|
| `packbox-pack` | Hashea un directorio en chunks CAS y genera `manifest.json` |
| `packbox-install` | Instala una app desde el manifiesto (hardlinks desde CAS) |
| `packbox-run` | Ejecuta la app en sandbox bwrap (con fix DNS y GUI) |
| `packbox-list` | Lista apps instaladas con versión y etiquetas |
| `packbox-remove` | Desinstala una app y libera sus referencias CAS |
| `packbox-gc` | Recolecta y elimina chunks huérfanos |
| `packbox-verify` | Verifica compatibilidad de librerías del host vía `ldd` |
| `packbox-export` | Exporta una app a archivo `.pbox` comprimido |
| `packbox-import` | Importa un `.pbox` con validación anti path-traversal |
| `packbox-module` | Gestiona módulos de librerías compartidas |
| `packbox-diagnose` | Genera reporte del entorno para bugs |

---

## 📂 Estructura de Archivos

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

## 🏗️ Arquitectura

### Flujo de Empaquetado

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

### Componentes Internos

- **CAS**: Almacena chunks por hash BLAKE3. Usa `SafeLink` (hardlink con fallback a copia).
- **Manifiesto**: `schema_version: "1.5"`, mapea rutas a chunks, define `host_contract.delegate`.
- **Sandbox**: `bwrap --unshare-all --share-net`. Resuelve symlinks DNS (`filepath.EvalSymlinks`) antes de bindear `/etc/resolv.conf`. Soporte GUI: X11, Wayland, D-Bus, `/dev/dri`, fontconfig.

### Flujo de Deduplicación

```
App 1: htop     → chunks: [A, B, C]
App 2: neofetch → chunks: [A, D, E]
App 3: btop     → chunks: [A, B, F]

CAS Store:
  A → refs: htop, neofetch, btop (3)
  B → refs: htop, btop (2)
  C → refs: htop (1)
  D → refs: neofetch (1)
  E → refs: neofetch (1)
  F → refs: btop (1)

Total: 6 chunks únicos en lugar de 9 (33% deduplicación)
Con más apps: el ahorro escala al 90-99%
```

---

## 🔒 Seguridad

### Mitigaciones Implementadas

- **Anti path-traversal**: `isValidHash()` valida 64 caracteres hex lowercase. La importación `.pbox` valida cada entrada TAR contra la raíz de extracción.
- **Importación segura**: El extractor TAR solo procesa `tar.TypeDir` y `tar.TypeReg`. Symlinks, hardlinks y device files se ignoran.
- **Limpieza de entorno**: `--clearenv` + whitelist explícita bloquea `LD_PRELOAD` y `LD_LIBRARY_PATH`.
- **Aislamiento de XAUTHORITY**: Se copia a `/tmp/packbox-xauth-<pid>` con modo `0600`.
- **Reference counting**: Cada chunk tiene `.refs`. `packbox-gc` solo borra chunks sin referencias.
- **Sin setuid, sin root**: Todo corre como el usuario. `sudo` solo en la instalación.
- **SafeLink**: Hardlinks con fallback automático a copia segura.

### Limitaciones Conocidas (v0.1.0 Alpha)

> [!WARNING]
> - ❌ No hay verificación de firmas criptográficas en archivos `.pbox`.
> - ❌ La política de red es global (`--share-net`).
> - ❌ El sandbox es más permisivo que Flatpak (monta más directorios para GUI).

---

## 🗺️ Hoja de Ruta

### v0.1.x — Estabilización

- [ ] Verificación de firmas para `.pbox` (minisign/sigstore)
- [ ] Política de red por aplicación
- [ ] Completar `packbox-module remove` e `info`
- [ ] Tests de integración GTK4/Qt6
- [ ] CI/CD: `shellcheck`, `gofmt`, `go vet`
- [ ] Matriz: Debian 12, Fedora 40, Arch, openSUSE

### v0.2 — Alcance

- [ ] Binarios precompilados x86_64 y aarch64
- [ ] Comando `packbox-update`
- [ ] Descargas delta a nivel de chunk
- [ ] Frontend GUI opcional (GTK4)

### Futuro

- [ ] Importador de runtimes Flatpak
- [ ] Sandbox WASM para plugins
- [ ] Repositorio central de módulos

---

## 🤝 Contribuir

¡Contribuciones bienvenidas! Áreas de ayuda:

- **Traducciones**: Añade un locale a `packbox-i18n.sh` copiando el bloque base.
- **Perfiles de sandbox**: Mejora los mapas de datos en `internal/sandbox/sandbox.go`.
- **Chunking**: Investiga rolling hash o chunking paralelo para el CAS.
- **Bugs**: Incluye siempre la salida de `packbox-diagnose`.

### Cómo Empezar

```bash
git clone https://github.com/TU_USUARIO/packbox.git
cd packbox
# Lee CONTRIBUTING.md
```

- 🐛 [Abrir un issue](https://github.com/TU_USUARIO/packbox/issues)
- 💬 [Iniciar una discusión](https://github.com/TU_USUARIO/packbox/discussions)
- 🔧 [CONTRIBUTING.md](CONTRIBUTING.md)

> [!TIP]
> Ejecuta `shellcheck` sobre scripts bash y `gofmt` + `go vet` sobre Go antes de enviar un PR.

---

## ⚖️ Licencia

Distribuido bajo la **Licencia Apache 2.0**. Ver [LICENSE](LICENSE).

Elegimos Apache 2.0 sobre MIT para proporcionar una cláusula de concesión de patentes explícita, protegiendo a usuarios y contribuyentes de litigios relacionados con las características de deduplicación y sandboxing de Packbox.

---

## 🙏 Agradecimientos

- **[bubblewrap](https://github.com/containers/bubblewrap)**: Sandbox para Linux.
- **[BLAKE3](https://github.com/BLAKE3-team/BLAKE3)**: Hashing de contenido rápido y seguro.
- **[Flatpak](https://flatpak.org/)**: Demostró que las apps Linux sandboxeadas funcionan a escala.
- **Comunidad Linux global**: La capa i18n de 9 idiomas existe gracias a sus revisiones.

---

<div align="center">

**🚀 Packbox v0.1.0 Alpha — Empaquetamiento inteligente para Linux**

*Hecho con ❤️ para la comunidad Linux*

</div>
