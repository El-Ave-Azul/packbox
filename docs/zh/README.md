# Packbox

**[Español](../../README.md)** · [English](../en/README.md) · [Français](../fr/README.md) · [Deutsch](../de/README.md) · [Italiano](../it/README.md) · [Português](../pt/README.md) · **[中文](README.md)** · [日本語](../ja/README.md) · [한국어](../ko/README.md)

---

![CI](https://github.com/El-Ave-Azul/packbox/actions/workflows/ci.yml/badge.svg)
![许可证](https://img.shields.io/badge/Licencia-Apache_2.0-blue.svg)
![版本](https://img.shields.io/badge/Versión-0.3.0-orange.svg)
![平台](https://img.shields.io/badge/Plataforma-Linux-blue.svg)
![Go](https://img.shields.io/badge/Go-1.22+-00ADD8.svg?logo=go&logoColor=white)
![i18n](https://img.shields.io/badge/i18n-9_语言-green.svg)
![状态](https://img.shields.io/badge/Estado-Beta-blue.svg)

**基于块级二进制去重和 Zstd 压缩 `.pbox` 导出的 Linux 应用打包器。**
灵感来自 Flatpak，但采用了不同的复用模型：不是为每个应用维护一个单体
runtime，Packbox 将内容保存在一个按内容寻址的存储（BLAKE3 CAS）中，
使用优化后的**基于内容的切块（CDC）**和可复用的**单元**。两个共享
90 % 库的应用只存储这 10 % 的差异部分。

> [!IMPORTANT]
> **Beta 状态 (v0.3.0)。** 系统已增强核心稳定性，实现了 LRU 垃圾回收、导出时的 Zstd 压缩。

---

## 目录

- [Packbox 是什么？](#packbox-是什么)
- [与 Flatpak 的比较](#与-flatpak-的比较)
- [环境要求](#环境要求)
- [安装](#安装)
- [快速上手](#快速上手)
- [可用命令](#可用命令)
- [文件结构](#文件结构)
- [架构](#架构)
- [安全性](#安全性)
- [路线图](#路线图)
- [参与贡献](#参与贡献)
- [许可证](#许可证)
- [致谢](#致谢)

---

## Packbox 是什么？

Packbox 使用 **Content-Addressable Storage (CAS)**、**BLAKE3** 哈希和
优化后的**基于内容的切块**来打包 Linux 应用，从而实现应用之间真正的二进制去重。

不同于每个应用约 1 GB 的 runtime（Flatpak），Packbox 将每个文件保存为
按内容去重的块，并在所有应用之间共享；**Zstd** 压缩在导出 `.pbox` 时应用。此外，它把每个库转换为一个**单元**
（一个带版本的可复用单位），供多个应用共享，而将通用库（`libc`、`libm` 等）
留给宿主。

### 设计原则

- **块级去重。** 相同字节 = 相同哈希 = 只存储一次（针对 ELF 二进制文件优化 CDC；小文件作为单个块）。
- **原始存储，压缩导出。** CAS 保持块不压缩，以便安装时能够**硬链接**它们（真正的磁盘去重）；**Zstd** 压缩在构建 `.pbox` 时应用。
- **单元（原子化分片）。** 每个非通用库都是一个单元；应用声明它，安装器
  负责解析。
- **跨应用共享。** 所有应用共享同一个全局 CAS 和相同的单元。
- **Host contract v1。** 对通用库进行选择性委托，并对所需符号做 **ABI 检查**。
- **强化沙箱（bubblewrap）。** `--unshare-all`、`--cap-drop ALL`、
  **seccomp**、**过滤的 D-Bus**（`xdg-dbus-proxy`）、**每个应用私有的 HOME**、
  细粒度网络策略 (none/limited/full) 以及**带自动检测的 X11 选择性启用**。
- **overlay 分层。** `/app` 由 A（应用）叠加在 C（单元）之上构成，S（宿主）
  通过 `/usr` 提供。
- **签名与分发。** 可签名的 `.pbox`（ed25519）以及支持并发增量下载的 HTTP 远程仓库。
- **4 种打包模式。** Normal、Portable、Bundle、Module。

---

## 与 Flatpak 的比较

| 特性                 | Flatpak（当前）             | Packbox v0.3.0                       |
|----------------------|-----------------------------|--------------------------------------|
| 复用单位             | 完整 runtime（约 1 GB）     | 按库的**单元**（无 runtime）         |
| 去重                 | 文件级（OSTree）            | **块级**（BLAKE3 + CDC）             |
| 存储                 | 按 runtime 压缩             | **原始块 + 硬链接**（去重）          |
| 库共享               | 同一 runtime 内部           | 在所有应用之间交叉共享               |
| 使用宿主库           | 无                          | 选择性（host contract + ABI）        |
| 更新                 | OSTree 对象增量             | `packbox-update`（增量 + LRU GC）    |
| 分发                 | Flathub + OSTree remotes    | 并发 HTTP 远程仓库                  |
| 签名                 | GPG                         | ed25519（`.pbox.sig`）               |
| 沙箱                 | bwrap + seccomp + portals   | bwrap + seccomp + dbus-proxy + portals |
| 界面                 | GNOME Software / CLI        | **TUI** + CLI                          |
| 每应用开销           | 若 runtime 不同则约 100 %   | 应用间共享时 **约 5–15 %**           |

---

## 环境要求

- **操作系统**：Linux（Debian 12+、Ubuntu 22.04+、Fedora 40+、Arch、
  openSUSE Tumbleweed）
- **内核**：5.15+，且启用 user namespaces
- **Shell**：Bash 4.0+
- **Go**：1.22+（若缺失，安装器会下载自带副本）
- **空间**：初始编译需要约 500 MB 可用空间
- **网络**：仅首次安装需要

### 系统依赖

安装器会尽可能安装它们；手动安装也有用：

`bubblewrap` · `binutils`（`ldd`/`readelf`） · `jq` · `bc` · `curl` · `tar` ·
`xdg-dbus-proxy`（D-Bus 过滤） · `zstd` 或 `xz`（更紧凑的导出）

---

## 安装

### 第 1 步 — 克隆并运行

```bash
git clone https://github.com/El-Ave-Azul/packbox.git
cd packbox
./packbox-install.sh
```

安装器会打开一个菜单；选择选项 **1**（安装）。

### 第 2 步 — 重新加载 shell

```bash
source ~/.bashrc
```

### 第 3 步 — 验证

```bash
packbox-diagnose
```

---

## 快速上手

### 1. 交互式打包器 (TUI)

```bash
./packbox-packager.sh
```

选项 **1 (打包)** 会搜索**已安装**的应用并**生成**
`.pbox` 文件存放在 `~/.local/share/packbox/exports/`。完成后，它会询问是否
同时**将其安装到此设备**（默认 **否**，以避免污染系统）。要安装 `.pbox`，请使用选项 **5 (导入)**。

### 2. 命令行

```bash
# 打包一个目录
packbox-pack ./mi-app --name org.ejemplo.miapp --version 1.0.0

# 从生成的清单安装
packbox-install ./mi-app/manifest.json

# 在沙箱中运行（overlay A 叠加在 C 之上；私有 HOME）
packbox-run org.ejemplo.miapp

# 列出应用（真实大小和共享节省）并释放空间
packbox-list
packbox-remove org.ejemplo.miapp
packbox-gc

# 复用 store 中的块更新已安装的应用
packbox-update org.ejemplo.miapp ./nuevo/manifest.json
```

---

## 可用命令

Packbox v0.3.0 在 `~/.packbox/bin/` 中包含 **15 个 Go 二进制文件**：

| 命令               | 用途                                                          |
|--------------------|--------------------------------------------------------------------|
| `packbox-pack`     | 将目录按 CAS 块进行哈希并生成 `manifest.json`        |
| `packbox-install`  | 从清单安装应用（+ `--desktop`/`--remove-desktop`） |
| `packbox-run`      | 在 `bwrap` 沙箱中运行应用（overlay A/C，私有 HOME）   |
| `packbox-list`     | 列出应用及其**真实大小**和共享节省（`--tsv`）   |
| `packbox-remove`   | 卸载应用（`--all` = 全部, `--dry-run`）并释放其引用 |
| `packbox-gc`       | 回收无引用的块**和单元**（支持 LRU）                      |
| `packbox-verify`   | 检查可解析的库 + 宿主的 **ABI 兼容性**        |
| `packbox-export`   | 导出为 `.pbox`，使用**自适应压缩**和可选的 `--sign` |
| `packbox-import`   | 导入 `.pbox`（防 tar-slip、路径穿越和签名）             |
| `packbox-update`   | 复用块更新应用 + 增量报告（`--no-gc`）   |
| `packbox-module`   | 模块/单元：`list`、`create`、`cell <lib>...`                  |
| `packbox-sign`     | ed25519 密钥与签名：`keygen`、`sign`, `verify`, `trust`       |
| `packbox-fetch`    | HTTP 远程仓库：`publish`、使用**签名索引**的 `index`/`search`/`install`，以及 `fetch`（并发增量）      |
| `packbox-debug`    | 附加已安装应用的调试符号（单独的单元）  |
| `packbox-diagnose` | 用于 bug 报告的环境报告                          |

---

## 架构

### 打包流程

```
┌──────────────┐   pack    ┌──────────────┐  install  ┌──────────────┐
│  源目录      │ ────────► │     CAS      │ ─────────► │  应用树      │
│  (fs 树)    │           │  (chunks)    │           │ (hardlinks)  │
└──────────────┘           └──────────────┘           └──────┬───────┘
                                    │                          │ + 单元（层 C）
                                    │ run                      ▼
                         ┌──────────────────────────────────────────┐
                         │  bwrap 沙箱：/app = A 叠加在 C 之上       │
                         │  私有 HOME · seccomp · 过滤的 D-Bus       │
                         └──────────────────────────────────────────┘
```

### 内部组件

- **CAS + chunker** — 按 **BLAKE3** 哈希保存原始块（不做重新压缩，以便硬链接）。大文件使用**优化后的 CDC** 分割；小文件作为单个块。写入是**原子**的。
- **清单** (`schema_version: \"1.7\"`) — 将路径映射到块，定义网络策略 (`none`, `limited`, `full`)、host contract 和 X11 符号。
- **单元** — 一个库 = 一个单元 `org.lib.<soname>@<hash>`，位于 `mods/`。在应用之间共享。`packbox-gc` 删除未被引用或旧的单元 (LRU)。
- **沙箱** — `bwrap --unshare-all --cap-drop ALL --clearenv`、**seccomp**、使用 `xdg-dbus-proxy` 的**过滤 D-Bus**、**私有 HOME**、细粒度网络以及**多媒体支持** (PipeWire/PulseAudio)。
- **分层 overlay** — `/app` 通过 `--overlay-src` 组合（C 在下，A 在上）；S（宿主）通过 `/usr` 提供。
- **Host contract** — `packbox-verify` 检查宿主是否提供所需的符号 (ABI)。
- **签名与远程仓库** — `packbox-sign` (ed25519) 对 `.pbox` 和**仓库索引**签名；`packbox-fetch` 发布、**搜索**（`search`）并按 id 安装，支持**并发下载**。

---

## 安全性

### 已实现的缓解措施

- **按应用隔离数据** — 每个应用以**私有 HOME** 运行；仅以**只读**方式公开字体/主题。
- **过滤的 D-Bus** — `xdg-dbus-proxy` 配合白名单（portals + `dconf`）。
- **seccomp** — 默认过滤器，拦截危险的内核表面。
- **细粒度网络** — `none`/`limited`/`full` 模式。`limited` 使用内部 **best-effort** 代理，拦截私有/保留网段；它只影响遵循 `http_proxy`/`https_proxy` 的应用（原始套接字不会被过滤）。
- **安全多媒体支持** — 通过 portals 实现对音频和摄像头的中介访问。
- **防 tar-slip / 路径穿越** — 对 `.pbox` 路径进行严格校验。
- **环境清理** — `--clearenv` + 显式白名单。
- **引用计数 + LRU GC** — 基于访问时间的智能块清理。
- **签名** — `.pbox` 支持 **ed25519** 签名。

---

## 路线图

### v0.1.x — 稳定化
- [x] `.pbox` 签名校验
- [x] 强化沙箱：私有 HOME、过滤的 D-Bus、seccomp
- [x] 自动单元 + 分层 overlay (A/C/S)
- [x] 带块增量 + 自动 GC 的 `packbox-update`
- [x] 支持并发增量下载的 HTTP 远程仓库
- [x] `.pbox` 导出中的 Zstd 压缩
- [x] 针对 ELF 二进制文件的 CDC 优化
- [x] LRU 垃圾回收

### v0.2 — 范围
- [ ] GTK4 GUI 前端（暂缓）
- [ ] 预编译的 x86_64 和 aarch64 二进制文件
- [x] 签名的中央索引/仓库

### 未来
- [ ] Flatpak runtime 导入器 (best-effort)
- [ ] 面向不受信任插件的 WASM 沙箱

---

## 许可证

以 **Apache License 2.0** 分发。参见 [LICENSE](../../LICENSE)。
