[English](../../README.md) · [Español](../../README.es.md) · [Français](../fr/README.md) · [Deutsch](../de/README.md) · [Italiano](../it/README.md) · **简体中文** · [繁體中文](../zh-TW/README.md) · [日本語](../ja/README.md) · [한국어](../ko/README.md)

---

![许可证：MIT](https://img.shields.io/badge/许可证-MIT-yellow.svg)
![平台：Linux](https://img.shields.io/badge/平台-Linux-blue)
![版本](https://img.shields.io/badge/版本-0.1.0--alpha-orange)
![Go](https://img.shields.io/badge/Go-1.22+-00ADD8?logo=go&logoColor=white)
![i18n](https://img.shields.io/badge/i18n-9_种语言-green)
![状态](https://img.shields.io/badge/状态-alpha-red)

# Packbox

**面向 Linux 的下一代应用程序打包系统。** 受 Flatpak 启发，但采用根本
不同的复用模型：Packbox 不再为每个应用分发一个整体运行时，而是将每个
文件存储为按内容寻址的块（BLAKE3 CAS）。两个共享 90% 库的应用只存储不同
的 10%。

> [!NOTE]
> **Packbox 处于 Alpha 阶段（v0.1.0）。** 核心工作流可用，但 `.pbox`
> 归档尚无签名验证，沙箱刻意比 Flatpak 更宽松。请先在非关键系统上使用。

---

## 目录

- [为什么选择 Packbox](#为什么选择-packbox)
- [与 Flatpak 的比较](#与-flatpak-的比较)
- [系统要求](#系统要求)
- [安装](#安装)
- [快速开始](#快速开始)
- [命令](#命令)
- [文件系统布局](#文件系统布局)
- [架构](#架构)
- [安全](#安全)
- [路线图](#路线图)
- [文档](#文档)
- [贡献](#贡献)
- [许可证](#许可证)
- [致谢](#致谢)

---

## 为什么选择 Packbox

Flatpak 解决了一个真实问题：沙箱化、可移植的 Linux 应用。但它的复用
模型过于粗糙。每个应用都附带（或引用）一个可能高达 **~1 GB** 的完整
运行时。如果两个应用使用不同的运行时，你就得付两次代价——即使它们共享
95% 的库。

Packbox 正是针对这个空缺：

- **块级去重。** 文件被切分、用 BLAKE3 哈希并作为块存储。相同的块
  （一个 `libfoo.so.3.2.1`、一个字体、一个翻译目录）在系统的所有应用
  之间共享。
- **跨应用库共享。** 使用同一个 `libQt6Core.so` 的两个应用在磁盘上只
  保留一份副本，无论它们属于哪个"运行时"。
- **选择性使用主机库。** 应用可以声明它们信任哪些主机库（通过
  `host_contract.delegate`），而不是打包所有内容。
- **每个应用的体积小。** 实际上，在现有集合上添加一个新应用只消耗其
  体积的 ~5–15%，而不是 ~100%。

Packbox **并不试图**取代 Flatpak。它探索的是一个不同的细分场景：
那些无法干净地映射到运行时的应用，或者为了运行一个 50 MB 的工具而
发送 1 GB 显得过度的场景。

---

## 与 Flatpak 的比较

| 特性          | Flatpak（当前）           | Packbox（提议）          |
|---------------|---------------------------|--------------------------|
| 复用单元      | 完整运行时（~1 GB）       | 原子单元（~5–50 MB）     |
| 去重          | 文件级（OSTree）          | 块级（BLAKE3 CAS）       |
| 库共享        | 同一运行时内              | 跨所有应用               |
| 主机库使用    | 无（完全沙箱）            | 选择性（ABI 兼容）       |
| 更新          | OSTree 对象增量           | 块增量 + 重排序          |
| 每应用开销    | 运行时不同则 ~100%        | ~5–15%（仅差异）         |

---

## 系统要求

- **Linux**（在 Debian 12、Fedora 40、当前 Arch 上测试）
- **Bash 4+**
- **Go 1.22+**（如缺失会自动安装）
- **bubblewrap**（`bwrap`）——自动安装
- **binutils**（`ldd`、`readelf`）——自动安装
- **压缩工具**：`zstd`、`xz`、`gzip`（至少一个）
- **约 500 MB 可用磁盘** 用于构建 + 工具链（若从零安装 Go）

支持的发行版家族：**Debian/Ubuntu/Mint/Pop**、**Fedora/RHEL/Rocky**、
**Arch/Manjaro/EndeavourOS**、**openSUSE**。

---

## 安装

```bash
git clone https://github.com/El-Ave-Azul/packbox.git
cd packbox
./packbox-installer-v0.1.0.sh
source ~/.bashrc
packbox-diagnose
```

安装程序是交互式的，会：

1. 检测你的发行版和包管理器。
2. 安装依赖前询问（`bubblewrap binutils jq bc curl tar`）。
3. 若缺失则安装 Go 1.22+。
4. 创建 `~/.packbox/{bin,src}` 和
   `~/.local/share/packbox/{store,apps,mods,exports,tmp}`。
5. 从本地源码生成 11 个 Go 二进制文件 + 内部包。
6. 编译全部内容（现代硬件上约 2–3 分钟）。
7. 将 `~/.packbox/bin` 添加到 `PATH` 并创建 `~/.local/bin` 中的符号链接。
8. 验证全部 11 个二进制文件存在。

**语言**：安装程序启动时提示选择 9 种语言之一——English、Español、
Français、Deutsch、Italiano、简体中文、繁體中文、日本語、한국어。

### 卸载

运行同一脚本并选择选项 `2`：

- 模式 `s` → 完全删除（二进制 + 应用 + 存储 + 菜单 + 配置）
- 模式 `k` → 仅二进制（保留应用和存储）
- 模式 `q` → 取消

需要输入 `DELETE` 以确认。

---

## 快速开始

### 交互式打包器（推荐）

```bash
./packbox-packager-v0.1.0.sh
```

菜单：打包、列出、gc、导出、导入、卸载。

### 命令行

```bash
# 1. 将目录打包为 CAS 块 + manifest.json
packbox-pack ./firefox-tree \
    --name org.mozilla.firefox \
    --version 128.0 \
    --description "Mozilla Firefox" \
    --gui --toolkit GTK3

# 2. 从生成的 manifest 安装
packbox-install ./firefox-tree/manifest.json

# 3. 在 bwrap 沙箱中运行（已应用 DNS + GUI 修复）
packbox-run org.mozilla.firefox

# 4. 查看已安装内容
packbox-list

# 5. 卸载并释放块
packbox-remove org.mozilla.firefox
packbox-gc
```

---

## 命令

十一个 Go 二进制文件，全部位于 `~/.packbox/bin/`：

| 命令                | 用途                                                |
|---------------------|-----------------------------------------------------|
| `packbox-pack`      | 将目录哈希为 CAS 块 + `manifest.json`               |
| `packbox-install`   | 从 manifest 安装（从 CAS 硬链接）                   |
| `packbox-run`       | 在 `bwrap` 中执行，带 DNS + GUI                     |
| `packbox-list`      | 列出已安装应用及版本和标签                          |
| `packbox-remove`    | 卸载应用并释放其 CAS 引用                           |
| `packbox-gc`        | 垃圾回收孤立块                                      |
| `packbox-verify`    | 基于 `ldd` 的库兼容性检查                           |
| `packbox-export`    | 导出应用到 `.pbox`（zstd/xz/gzip）                  |
| `packbox-import`    | 导入 `.pbox` 并验证路径穿越                         |
| `packbox-module`    | 管理共享库模块（`list`、`create`）                  |
| `packbox-diagnose`  | 打印环境报告用于错误报告                            |

完整参考（含选项、退出码和示例）：
[`commands.md`](commands.md) · [EN](../en/commands.md) · [ES](../es/commands.md)

### 交互式脚本

- `packbox-installer-v0.1.0.sh` — 安装 / 卸载
- `packbox-packager-v0.1.0.sh` — 打包、列出、gc、导出、导入、卸载
- `packbox-i18n.sh` — 共享翻译层

---

## 文件系统布局

```
~/.packbox/                     # 安装（二进制 + Go 源码）
├── bin/                        # 11 个 Go 二进制文件
└── src/                        # Go 模块源码

~/.local/share/packbox/         # 数据
├── store/                      # CAS — 按 BLAKE3 哈希存储的块
│   └── <ab>/<完整哈希>         # 每块附一个 .refs 文件
├── apps/                       # 已安装应用（tree + manifest.json）
├── mods/                       # 共享库模块
├── exports/                    # .pbox 归档
└── tmp/                        # 临时工作区

~/.config/packbox/lang/         # 9 个语言文件
```

---

## 架构

三个组件：

```
┌──────────────┐   pack    ┌──────────────┐   install   ┌──────────────┐
│   源目录     │ ────────► │     CAS      │ ──────────► │  应用 tree   │
│  (fs tree)   │           │   (块)       │             │  (硬链接)    │
└──────────────┘           └──────────────┘             └──────────────┘
                                  │
                                  │ run
                                  ▼
                         ┌──────────────────┐
                         │  bwrap 沙箱      │
                         │  (DNS/GUI 修复)  │
                         └──────────────────┘
```

- **CAS** — `~/.local/share/packbox/store/`，BLAKE3 哈希，每块一个
  `.refs` 文件，安装时使用 `SafeLink`（硬链接 → 复制回退）。
- **Manifest** — `schema_version: "1.5"`，`layers.app.files` 将相对
  路径映射到 `{chunks, size, mode}`，还有用于主机库信任的
  `host_contract.delegate`。
- **沙箱** — `bwrap --unshare-all --share-net`，`--clearenv` 之后的
  环境白名单，绑定 `/etc/resolv.conf` 前的 DNS 符号链接解析
  （`EvalSymlinks`），GUI 支持（X11、Wayland、D-Bus、`/dev/dri`、
  fontconfig 缓存），使用 `--bind-try` 的启发式每应用数据映射。

完整架构（CAS 内部、manifest 模式、沙箱挂载、主机契约）：
[`architecture.md`](../en/architecture.md) · [ES](../es/architecture.md)

---

## 安全

> [!WARNING]
> v0.1.0 Alpha 中 `.pbox` 归档**未签名**。将任何导入的归档视为不可信。
> 签名验证在路线图中。

已实现的关键缓解措施：

- **路径穿越防护** — `cas.isValidHash()` 强制 64 个小写十六进制字符。
  `.pbox` 导入通过 `security.ValidatePath` 对每个 tar 条目与提取根进行
  验证。
- **符号链接安全导入** — 只处理 `tar.TypeDir` 和 `tar.TypeReg`；符号
  链接、硬链接和设备文件被静默跳过。
- **环境清理** — `--clearenv` 后跟显式白名单，阻止来自主机的
  `LD_PRELOAD` / `LD_LIBRARY_PATH` 注入。
- **XAUTHORITY 隔离** — 主机的 `~/.Xauthority` 在绑定到沙箱之前被复制
  到每进程临时文件（`/tmp/packbox-xauth-<pid>`，模式 0600）。
- **引用计数** — 每个块有一个 `.refs` 文件；`packbox-gc` 只删除未引用
  的块。
- **无 setuid、无 root** — Packbox 完全以调用用户身份运行。`sudo` 仅
  由安装程序用于发行版包。

已知限制和威胁模型：
[`security.md`](../en/security.md) · [ES](../es/security.md)

报告漏洞时请附上 `packbox-diagnose` 的输出。对于敏感发现，请使用仓库
的私密安全联系方式。

---

## 路线图

### v0.1.x — 稳定化
- [ ] `.pbox` 归档的签名验证
- [ ] 每应用网络策略（当前 `--share-net` 是全局的）
- [ ] 实现 `packbox-module remove` 和 `info`
- [ ] 针对真实 GTK4/Qt6 应用压力测试 `host_contract.delegate`
- [ ] CI：每个 PR 上运行 `shellcheck`、`gofmt`、`go vet`
- [ ] 测试矩阵：Debian 12、Fedora 40、Arch、openSUSE Tumbleweed

### v0.2 — 覆盖范围
- [ ] 为 x86_64 和 aarch64 预编译二进制（发布页）
- [ ] `packbox-update` 用于就地版本升级
- [ ] GUI 前端（可选，GTK4）
- [ ] `packbox-export` 的块级增量下载

### 更远
- [ ] Flatpak 运行时导入器（尽力而为）
- [ ] 通过 minisign 或 sigstore 进行签名验证
- [ ] 用于不可信插件的 WASM 沙箱层

---

## 文档

9 种语言的完整文档。英文和西班牙文有完整集（README + 命令 + 架构 +
安全）；其余七种有 README + 命令。

| 语言     | README                                 | 命令                                            | 架构                                                | 安全                                          |
|----------|----------------------------------------|-------------------------------------------------|-----------------------------------------------------|-----------------------------------------------|
| English  | [en](../en/README.md)                  | [en](../en/commands.md)                         | [en](../en/architecture.md)                         | [en](../en/security.md)                       |
| Español  | [es](../es/README.md)                  | [es](../es/commands.md)                         | [es](../es/architecture.md)                         | [es](../es/security.md)                       |
| Français | [fr](../fr/README.md)                  | [fr](../fr/commands.md)                         | —                                                   | —                                             |
| Deutsch  | [de](../de/README.md)                  | [de](../de/commands.md)                         | —                                                   | —                                             |
| Italiano | [it](../it/README.md)                  | [it](../it/commands.md)                         | —                                                   | —                                             |
| 简体中文 | **zh-CN**                              | [zh-CN](commands.md)                            | —                                                   | —                                             |
| 繁體中文 | [zh-TW](../zh-TW/README.md)            | [zh-TW](../zh-TW/commands.md)                   | —                                                   | —                                             |
| 日本語   | [ja](../ja/README.md)                  | [ja](../ja/commands.md)                         | —                                                   | —                                             |
| 한국어   | [ko](../ko/README.md)                  | [ko](../ko/commands.md)                         | —                                                   | —                                             |

索引：[`docs/README.md`](../README.md)

---

## 贡献

欢迎贡献，尤其是：

- **翻译** — 通过复制 `install_lang_files()` 中的 `en` 块并翻译每个
  `L_*` 键，向 `packbox-i18n.sh` 添加新语言。
- **沙箱配置** — 针对浏览器、IDE、游戏的每应用数据映射。
- **CAS 分块策略** — 滚动哈希变体、并行分块。
- **错误报告** — 始终附上 `packbox-diagnose` 输出。

开始：

```bash
git clone https://github.com/TU_USUARIO/packbox.git
cd packbox
# 阅读 CONTRIBUTING.md 获取完整指南
```

- 🐛 [打开 issue](https://github.com/TU_USUARIO/packbox/issues)
- 💬 [发起讨论](https://github.com/TU_USUARIO/packbox/discussions)
- 🔧 [CONTRIBUTING.md](../../CONTRIBUTING.md)

提交 PR 前，请对 shell 脚本运行 `shellcheck`，对 Go 代码运行
`gofmt` + `go vet`。

---

## 许可证

[MIT](../../LICENSE) © 2025 TU_NOMBRE

Packbox 可自由使用、修改和再分发。详情见
[LICENSE](../../LICENSE)。

---

## 致谢

- **[bubblewrap](https://github.com/containers/bubblewrap)** — 使
  `packbox-run` 成为可能的沙箱原语。
- **[BLAKE3](https://github.com/BLAKE3-team/BLAKE3)** — 快速、安全的
  内容寻址。
- **[Flatpak](https://flatpak.org/)** — 证明了沙箱化 Linux 应用可以大
  规模运行的项目，其设计决策为我们提供了许多参考（即使我们有所分歧）。
- 9 种语言的 i18n 层存在是因为 Linux 社区是全球性的；感谢所有审阅
  过翻译的人。
