# Packbox

[Español](../../README.md) · [English](../en/README.md) · [Français](../fr/README.md) · [Deutsch](../de/README.md) · [Italiano](../it/README.md) · [Português](../pt/README.md) · **[中文](README.md)** · [日本語](../ja/README.md) · [한국어](../ko/README.md)

---

![Licencia](https://img.shields.io/badge/Licencia-Apache_2.0-blue.svg)
![Versión](https://img.shields.io/badge/Versión-0.1.1-orange.svg)
![Plataforma](https://img.shields.io/badge/Plataforma-Linux-blue.svg)
![Go](https://img.shields.io/badge/Go-1.22+-00ADD8.svg?logo=go&logoColor=white)
![i18n](https://img.shields.io/badge/i18n-9_idiomas-green.svg)
![Estado](https://img.shields.io/badge/Estado-Alpha-red.svg)

**基于块级二进制去重的 Linux 应用打包器。**
灵感来自 Flatpak，但采用了不同的复用模型：不是为每个应用维护一个单体
runtime，Packbox 将内容保存在一个按内容寻址的存储（BLAKE3 CAS）中，
使用**基于内容的切块（CDC）**和可复用的**单元（celdas）**。两个共享
90 % 库的应用只存储这 10 % 的差异部分。

> [!WARNING]
> **Alpha 状态（v0.1.1）。** 主要流程可以工作，并且已经具备签名、
> 强化的沙箱（seccomp、过滤的 D-Bus、私有 HOME）和 HTTP 远程仓库，但
> 项目还很年轻，没有 Flatpak 那样的生态和成熟度。请先在非关键系统上
> 使用。

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
**基于内容的切块**来打包 Linux 应用，从而实现应用之间真正的二进制去重。

不同于每个应用约 1 GB 的 runtime（Flatpak），Packbox 将每个文件保存为按
内容寻址的块，并在所有应用之间共享。此外，它把每个库转换为一个**单元**
（一个带版本的可复用单位），供多个应用共享，而将通用库（`libc`、`libm` 等）
留给宿主。

### 设计原则

- **块级去重。** 相同字节 = 相同哈希 = 只存储一次（大文件使用 CDC；小文件
  作为单个文件，以便硬链接和共享）。
- **单元（原子化分片）。** 每个非通用库都是一个单元；应用声明它，安装器
  负责解析。
- **跨应用共享。** 所有应用共享同一个全局 CAS 和相同的单元。
- **Host contract v1。** 对通用库进行选择性委托，并对所需符号做 **ABI 检查**。
- **强化沙箱（bubblewrap）。** `--unshare-all`、`--cap-drop ALL`、
  **seccomp**、**过滤的 D-Bus**（`xdg-dbus-proxy`）、**每个应用私有的 HOME**、
  网络选择性启用，以及**带自动检测的 X11 选择性启用**。
- **overlay 分层。** `/app` 由 A（应用）叠加在 C（单元）之上构成，S（宿主）
  通过 `/usr` 提供。
- **签名与分发。** 可签名的 `.pbox`（ed25519）以及支持增量下载的 HTTP 远程仓库。
- **4 种打包模式。** Normal、Portable、Bundle、Module。

---

## 与 Flatpak 的比较

| 特性                 | Flatpak（当前）             | Packbox v0.1.1                       |
|----------------------|-----------------------------|--------------------------------------|
| 复用单位             | 完整 runtime（约 1 GB）     | 按库的**单元**（无 runtime）         |
| 去重                 | 文件级（OSTree）            | **块级**（BLAKE3 + CDC）             |
| 库共享               | 同一 runtime 内部           | 在所有应用之间交叉共享               |
| 使用宿主库           | 无                          | 选择性（host contract + ABI）        |
| 更新                 | OSTree 对象增量             | `packbox-update`（块增量 + GC）      |
| 分发                 | Flathub + OSTree remotes    | 使用 `publish`/`fetch` 的 HTTP 远程仓库 |
| 签名                 | GPG                         | ed25519（`.pbox.sig`）               |
| 沙箱                 | bwrap + seccomp + portals   | bwrap + seccomp + dbus-proxy + portals |
| 每应用开销           | 若 runtime 不同则约 100 %   | 应用间共享时 **约 5–15 %**           |

**实测节省**（基于本代码库）：两个中等规模的 GTK4 应用，若共享其技术栈，
分开计算合计约 264 MB，而实际占用**约 141 MB（−46 %）**；混合 10 个应用时，
节省升到**约 69 %**。库的重叠越大，节省越多——但最好按实际情况测量，不要
假定共享 runtime 的 90–99 %。

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

### 安装器做了什么

1. 让你从 9 种语言中选择一种。
2. 检测你的 Linux 发行版和包管理器。
3. 在安装依赖前请求确认。
4. 如有需要，下载并校验 Go（默认 1.27.1）到 `~/.packbox/go`。
5. 创建目录结构（`~/.packbox/` 和 `~/.local/share/packbox/`）。
6. 复制源码并编译 **15 个 Go 二进制文件**（约 1–2 分钟）。
7. 在 `~/.bashrc` 中配置你的 `PATH`，并在 `~/.local/bin` 创建符号链接。
8. 将语言文件安装到 `~/.config/packbox/lang/`。
9. 验证所有二进制文件都存在且可用。

### 卸载

运行同一个脚本并选择选项 **2**：

```bash
./packbox-install.sh --uninstall
```

| 模式 | 说明 |
|------|-------------|
| `s`  | 完整：二进制文件 + 应用 + CAS store + 单元 + 菜单 + 图标 + 配置 |
| `k`  | 仅二进制文件：`~/.packbox/` 和符号链接（保留应用和 CAS store） |
| `q`  | 取消 |

---

## 快速上手

### 1. 交互式打包器（推荐）

```bash
./packbox-packager.sh
```

菜单：打包、列出、垃圾回收、导出、导入、卸载、语言。
从 `/usr/share/applications/` 中的 `.desktop` 检测应用、从 `/opt/*` 检测
bundle，以及常见二进制文件（`htop`、`btop`、`firefox`、`gimp` 等）。

在 **Normal** 和 **Portable** 模式下，`ldd` 闭包中每个非通用库都会自动
变成一个**单元**。

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

### 3. 导出、签名、导入与分发

```bash
# 导出并签名
packbox-sign keygen                       # 创建你的密钥（并信任它）
packbox-export --sign app org.ejemplo.miapp
packbox-sign verify ~/.local/share/packbox/exports/org.ejemplo.miapp.pbox

# 发布 HTTP 远程仓库并从另一台机器使用它
packbox-fetch publish org.ejemplo.miapp /srv/packbox
(cd /srv/packbox && python3 -m http.server 8000)
packbox-fetch fetch org.ejemplo.miapp --from http://host:8000

# 导入（若存在签名则校验它）
packbox-import app org.ejemplo.miapp.pbox
```

---

## 可用命令

Packbox v0.1.1 在 `~/.packbox/bin/` 中包含 **15 个 Go 二进制文件**：

| 命令               | 用途                                                          |
|--------------------|--------------------------------------------------------------------|
| `packbox-pack`     | 将目录按 CAS 块进行哈希并生成 `manifest.json`        |
| `packbox-install`  | 从清单安装应用（+ `--desktop`/`--remove-desktop`） |
| `packbox-run`      | 在 `bwrap` 沙箱中运行应用（overlay A/C，私有 HOME）   |
| `packbox-list`     | 列出应用及其**真实大小**和共享节省（`--tsv`）   |
| `packbox-remove`   | 卸载应用并释放其 CAS 引用                    |
| `packbox-gc`       | 回收无引用的块**和单元**                      |
| `packbox-verify`   | 检查可解析的库 + 宿主的 **ABI 兼容性**        |
| `packbox-export`   | 导出为 `.pbox`，使用**自适应压缩**和可选的 `--sign` |
| `packbox-import`   | 导入 `.pbox`（防 tar-slip、路径穿越和签名）             |
| `packbox-update`   | 复用块更新应用 + 增量报告（`--no-gc`）   |
| `packbox-module`   | 模块/单元：`list`、`create`、`cell <lib>...`                  |
| `packbox-sign`     | ed25519 密钥与签名：`keygen`、`sign`、`verify`、`trust`       |
| `packbox-fetch`    | HTTP 远程仓库：`publish <id> <dir>` 和 `fetch <id> --from <url>`      |
| `packbox-debug`    | 附加已安装应用的调试符号（单独的单元）  |
| `packbox-diagnose` | 用于 bug 报告的环境报告                          |

---

## 文件结构

```
~/.packbox/                              # 安装
├── bin/                                 # 15 个已编译的 Go 二进制文件
└── src/                                 # Go 源代码

~/.local/share/packbox/                  # 用户数据
├── store/                               # CAS：按 BLAKE3 哈希存放的块
│   └── <ab>/<hash-completo>             # + 每个块的 .refs 文件
├── apps/                                # 已安装的应用
│   └── <app-id>/
│       ├── manifest.json
│       ├── tree/                        # 指向 CAS 的硬链接（层 A）
│       └── home/                        # 私有 HOME（首次运行时创建）
├── mods/                                # 单元（org.lib.*、org.debug.*）
├── exports/                             # .pbox 文件（+ .sig）
└── tmp/                                 # 临时文件

~/.config/packbox/
├── lang/                                # 9 个语言文件
├── signing.key / signing.pub            # 你的签名密钥
└── trusted/                             # 受信任的公钥
```

---

## 架构

### 打包流程

```
┌──────────────┐   pack    ┌──────────────┐  install  ┌──────────────┐
│  源目录      │ ────────► │     CAS      │ ─────────► │  应用树      │
│ （fs 树）    │           │  (chunks)    │           │ (hardlinks)  │
└──────────────┘           └──────────────┘           └──────┬───────┘
                                  │                          │ + 单元（层 C）
                                  │ run                      ▼
                         ┌──────────────────────────────────────────┐
                         │  bwrap 沙箱：/app = A 叠加在 C 之上       │
                         │  私有 HOME · seccomp · 过滤的 D-Bus       │
                         └──────────────────────────────────────────┘
```

### 内部组件

- **CAS + chunker** — 按 **BLAKE3** 哈希保存块。大文件用 **CDC** 切分
  （*gear* 型滚动哈希）；小文件作为单个块（可硬链接，便于共享）。
  写入是**原子**的（temp+rename）。
- **清单**（`schema_version: "1.6"`）— 将路径映射到块，列出**单元**
  （`mods`）、`host_contract`（delegate + required_symbols）、X11 符号，
  以及（如适用）**debug** 单元。
- **单元** — 一个库 = 一个单元 `org.lib.<soname>@<hash>`，位于 `mods/`。
  在应用之间共享。`packbox-gc` 删除未被引用的单元。
- **沙箱** — `bwrap --unshare-all --cap-drop ALL --clearenv`、**seccomp**
  （阻止 ptrace/bpf/keyring/io_uring/模块……）、使用 `xdg-dbus-proxy` 的
  **过滤 D-Bus**（portals + dconf）、**私有 HOME**（`apps/<id>/home`）、
  网络**选择性启用**和 **X11 选择性启用**（默认 Wayland + portals；仅当
  清单要求或会话仅支持 X11 时才启用）。
- **分层 overlay** — `/app` 通过 `--overlay-src` 组合（C 在下，A 在上）；
  S（宿主）通过 `/usr` 提供。避免在每个树中复制单元。
- **Host contract** — `packbox-verify` 检查宿主是否提供所需的符号（ABI）。
- **签名与远程仓库** — `packbox-sign`（ed25519）对 `.pbox` 签名；
  `packbox-fetch` 发布并仅下载增量部分（块 + 单元）。

### 去重是如何工作的

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

## 安全性

### 已实现的缓解措施

- **按应用隔离数据** — 每个应用以**私有 HOME**（`apps/<id>/home`）运行；
  只以**只读**方式暴露字体/主题。它看不到也碰不到你真实的配置。
- **过滤的 D-Bus** — 使用白名单的 `xdg-dbus-proxy`（默认是 portals 和
  `dconf`；系统总线什么都没有）。应用无法与真实总线通信。
- **seccomp** — 默认过滤器阻止危险的内核攻击面（ptrace、bpf、keyring、
  io_uring、userfaultfd、模块、reboot/swap……）。
- **X11 选择性启用** — 默认 Wayland + `xdg-desktop-portal`（暴露 portal
  的文档挂载）；X11 通过清单中的 `x11` 标志启用，或者当宿主会话仅支持
  X11 时自动启用。
- **防 tar-slip / 路径穿越** — `.pbox` 解压会校验每个条目
  （`safeJoin` + `O_NOFOLLOW` + 符号链接目标），并拒绝逃逸出应用目录的
  `name`/路径。
- **环境清理** — `--clearenv` + 显式白名单：阻止从宿主注入的
  `LD_PRELOAD`/`LD_LIBRARY_PATH`。
- **无 setuid，无 root** — 一切都以你的用户身份运行；`sudo` 仅用于安装时
  的系统依赖。
- **引用计数 + GC** — 每个块都有一个 `.refs`；`packbox-gc` 只删除未被引用
  的部分（块**和单元**）。
- **签名** — `.pbox` 可使用 **ed25519** 签名；`import` 会校验并**拒绝**被
  篡改或来自不受信任签名者的包。
- **CAS 完整性** — 哈希在用作路径之前经过校验；写入是原子的。

### 已知局限（v0.1.1 Alpha）

> [!WARNING]
> 最欢迎反馈的几个方面。

- ⚠️ **portals 不完整。** 允许与 portals 通信并暴露文档挂载，但尚未为
  所有功能使用 portal（摄像头、剪贴板等）。
- ⚠️ **`packbox-module remove`/`info`** 仍未实现（`cell` 已存在）。
- ⚠️ **自适应压缩**是在包级别，而非按条目（格式是 tar + 一个压缩器）。
- ⚠️ **无目录/索引。** HTTP 远程仓库提供数据，但不提供信任或公共索引。

---

## 路线图

### v0.1.x — 稳定化

- [x] `.pbox` 的签名校验（ed25519 + 密钥管理）
- [x] 强化沙箱：私有 HOME、过滤的 D-Bus、seccomp
- [x] 自动单元 + 分层 overlay（A/C/S）
- [x] 带块增量 + 自动 GC 的 `packbox-update`
- [x] 支持增量下载的 HTTP 远程仓库（`publish`/`fetch`）
- [x] 单独的调试符号（`cell-debug`）
- [x] `export` 中的自适应压缩
- [x] 端到端集成测试（`tests/integration.sh`）
- [ ] 按应用的网络策略
- [ ] 完整的 portals（文件、摄像头、剪贴板）
- [ ] CI/CD：每个 PR 运行 `shellcheck`、`gofmt`、`go vet`
- [ ] 测试矩阵：Debian 12、Fedora 40、Arch、openSUSE Tumbleweed

### v0.2 — 范围

- [ ] 预编译的 x86_64 和 aarch64 二进制文件（releases 页面）
- [ ] 签名的中央索引/仓库（从远程 `search`/`install`）
- [ ] 可选的 GUI 前端（GTK4）

### 未来

- [ ] Flatpak runtime 导入器（best-effort）
- [ ] 面向不受信任插件的 WASM 沙箱

---

## 参与贡献

欢迎贡献！特别需要帮助的几个方面：

- **翻译** — 复制 `i18n/` 中现有的一个块并翻译每个 `L_*` 键，即可添加
  一个 locale。
- **Portals** — 集成 `xdg-desktop-portal` 以实现文件访问。
- **Chunking / dedup** — 改进 CDC 和阈值策略。
- **Bug 报告** — 请务必附上 `packbox-diagnose` 的输出。

### 如何开始

```bash
git clone https://github.com/El-Ave-Azul/packbox.git
cd packbox
cd src && go test ./...     # 单元测试
bash tests/integration.sh   # 端到端（pack → export → import → run）
```

- 🐛 [提交 issue](https://github.com/El-Ave-Azul/packbox/issues)
- 💬 [发起讨论](https://github.com/El-Ave-Azul/packbox/discussions)

> [!TIP]
> 提交 PR 之前，请对 bash 脚本运行 `shellcheck`，对 Go 运行 `gofmt` + `go vet`。

---

## 许可证

以 **Apache License 2.0** 分发。参见 [LICENSE](../../LICENSE)。

Apache 2.0 提供了**明确的专利授权条款**，保护用户和贡献者免受有关去重
和沙箱技术的诉讼，并且与 GPLv3 兼容。

---

## 致谢

- **[bubblewrap](https://github.com/containers/bubblewrap)** — 让
  `packbox-run` 成为可能的 Linux 沙箱原语。
- **[BLAKE3](https://github.com/BLAKE3-team/BLAKE3)** — 快速且加密安全的
  内容哈希。
- **[xdg-desktop-portal](https://flatpak.github.io/xdg-desktop-portal/)** 和
  **xdg-dbus-proxy** — 经中介的文件访问和 D-Bus 过滤。
- **[Flatpak](https://flatpak.org/)** — 证明了沙箱化的 Linux 应用可以大规模
  运行；它的许多决策启发了我们的设计，即便在我们有分歧之处也是如此。
- **全球 Linux 社区** — 9 种语言的 i18n 层因他们的审阅和贡献而存在。
