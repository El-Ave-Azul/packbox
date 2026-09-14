[English](../../README.md) · [Español](../../README.es.md) · [Français](../fr/README.md) · [Deutsch](../de/README.md) · [Italiano](../it/README.md) · [简体中文](../zh-CN/README.md) · **繁體中文** · [日本語](../ja/README.md) · [한국어](../ko/README.md)

---

![授權條款：MIT](https://img.shields.io/badge/授權條款-MIT-yellow.svg)
![平台：Linux](https://img.shields.io/badge/平台-Linux-blue)
![版本](https://img.shields.io/badge/版本-0.1.0--alpha-orange)
![Go](https://img.shields.io/badge/Go-1.22+-00ADD8?logo=go&logoColor=white)
![i18n](https://img.shields.io/badge/i18n-9_種語言-green)
![狀態](https://img.shields.io/badge/狀態-alpha-red)

# Packbox

**適用於 Linux 的新一代應用程式封裝系統。** 受 Flatpak 啟發，但採用
根本不同的重用模型：Packbox 不再為每個應用程式散佈一個整體執行階段，
而是將每個檔案儲存為按內容定址的區塊（BLAKE3 CAS）。兩個共享 90% 函式庫
的應用程式只儲存不同的 10%。

> [!NOTE]
> **Packbox 處於 Alpha 階段（v0.1.0）。** 核心工作流程可用，但 `.pbox`
> 封存檔尚無簽章驗證，沙箱刻意比 Flatpak 更寬鬆。請先在非關鍵系統上
> 使用。

---

## 目錄

- [為什麼選擇 Packbox](#為什麼選擇-packbox)
- [與 Flatpak 的比較](#與-flatpak-的比較)
- [系統需求](#系統需求)
- [安裝](#安裝)
- [快速開始](#快速開始)
- [指令](#指令)
- [檔案系統配置](#檔案系統配置)
- [架構](#架構)
- [安全](#安全)
- [發展藍圖](#發展藍圖)
- [文件](#文件)
- [貢獻](#貢獻)
- [授權條款](#授權條款)
- [致謝](#致謝)

---

## 為什麼選擇 Packbox

Flatpak 解決了一個真實問題：沙箱化、可攜的 Linux 應用程式。但它的重用
模型過於粗糙。每個應用程式都附帶（或引用）一個可能高達 **~1 GB** 的
完整執行階段。如果兩個應用程式使用不同的執行階段，你就得付兩次代價
——即使它們共享 95% 的函式庫。

Packbox 正是針對這個空缺：

- **區塊層級去重。** 檔案被切分、以 BLAKE3 雜湊並儲存為區塊。相同的
  區塊（一個 `libfoo.so.3.2.1`、一個字型、一個翻譯目錄）在系統的所有
  應用程式之間共享。
- **跨應用程式函式庫共享。** 使用同一個 `libQt6Core.so` 的兩個應用
  程式在磁碟上只保留一份副本，無論它們屬於哪個「執行階段」。
- **選擇性使用主機函式庫。** 應用程式可以宣告它們信任哪些主機函式庫
  （透過 `host_contract.delegate`），而不是封裝所有內容。
- **每個應用程式體積小。** 實際上，在現有集合上新增一個應用程式只
  消耗其體積的 ~5–15%，而不是 ~100%。

Packbox **並不試圖**取代 Flatpak。它探索的是一個不同的細分場景：
那些無法乾淨地對應到執行階段的應用程式，或者為了執行一個 50 MB 的
工具而傳送 1 GB 顯得過度的場景。

---

## 與 Flatpak 的比較

| 特性          | Flatpak（目前）           | Packbox（提議）          |
|---------------|---------------------------|--------------------------|
| 重用單元      | 完整執行階段（~1 GB）     | 原子單元（~5–50 MB）     |
| 去重          | 檔案層級（OSTree）        | 區塊層級（BLAKE3 CAS）   |
| 函式庫共享    | 同一執行階段內            | 跨所有應用程式           |
| 主機函式庫使用| 無（完全沙箱）            | 選擇性（ABI 相容）       |
| 更新          | OSTree 物件增量           | 區塊增量 + 重排序        |
| 每應用程式開銷| 執行階段不同則 ~100%      | ~5–15%（僅差異）         |

---

## 系統需求

- **Linux**（在 Debian 12、Fedora 40、目前 Arch 上測試）
- **Bash 4+**
- **Go 1.22+**（如缺少會自動安裝）
- **bubblewrap**（`bwrap`）——自動安裝
- **binutils**（`ldd`、`readelf`）——自動安裝
- **壓縮工具**：`zstd`、`xz`、`gzip`（至少一個）
- **約 500 MB 可用磁碟** 用於建置 + 工具鏈（若從零安裝 Go）

支援的發行版家族：**Debian/Ubuntu/Mint/Pop**、**Fedora/RHEL/Rocky**、
**Arch/Manjaro/EndeavourOS**、**openSUSE**。

---

## 安裝

```bash
git clone https://github.com/TU_USUARIO/packbox.git
cd packbox
./packbox-installer-v0.1.0.sh
source ~/.bashrc
packbox-diagnose
```

安裝程式是互動式的，會：

1. 偵測你的發行版和套件管理器。
2. 安裝依賴前詢問（`bubblewrap binutils jq bc curl tar`）。
3. 若缺少則安裝 Go 1.22+。
4. 建立 `~/.packbox/{bin,src}` 和
   `~/.local/share/packbox/{store,apps,mods,exports,tmp}`。
5. 從本機原始碼產生 11 個 Go 二進位檔 + 內部套件。
6. 編譯全部內容（現代硬體上約 2–3 分鐘）。
7. 將 `~/.packbox/bin` 加入 `PATH` 並在 `~/.local/bin` 建立符號連結。
8. 驗證全部 11 個二進位檔存在。

**語言**：安裝程式啟動時提示選擇 9 種語言之一——English、Español、
Français、Deutsch、Italiano、简体中文、繁體中文、日本語、한국어。

### 解除安裝

執行同一指令碼並選擇選項 `2`：

- 模式 `s` → 完全刪除（二進位檔 + 應用程式 + 儲存 + 選單 + 設定）
- 模式 `k` → 僅二進位檔（保留應用程式和儲存）
- 模式 `q` → 取消

需要輸入 `DELETE` 以確認。

---

## 快速開始

### 互動式封裝器（推薦）

```bash
./packbox-packager-v0.1.0.sh
```

選單：封裝、列出、gc、匯出、匯入、解除安裝。

### 命令列

```bash
# 1. 將目錄封裝為 CAS 區塊 + manifest.json
packbox-pack ./firefox-tree \
    --name org.mozilla.firefox \
    --version 128.0 \
    --description "Mozilla Firefox" \
    --gui --toolkit GTK3

# 2. 從產生的 manifest 安裝
packbox-install ./firefox-tree/manifest.json

# 3. 在 bwrap 沙箱中執行（已套用 DNS + GUI 修正）
packbox-run org.mozilla.firefox

# 4. 查看已安裝內容
packbox-list

# 5. 解除安裝並釋放區塊
packbox-remove org.mozilla.firefox
packbox-gc
```

---

## 指令

十一個 Go 二進位檔，全部位於 `~/.packbox/bin/`：

| 指令                | 用途                                                |
|---------------------|-----------------------------------------------------|
| `packbox-pack`      | 將目錄雜湊為 CAS 區塊 + `manifest.json`             |
| `packbox-install`   | 從 manifest 安裝（從 CAS 硬連結）                   |
| `packbox-run`       | 在 `bwrap` 中執行，帶 DNS + GUI                     |
| `packbox-list`      | 列出已安裝應用程式及版本和標籤                      |
| `packbox-remove`    | 解除安裝應用程式並釋放其 CAS 引用                   |
| `packbox-gc`        | 垃圾回收孤立區塊                                    |
| `packbox-verify`    | 基於 `ldd` 的函式庫相容性檢查                       |
| `packbox-export`    | 匯出應用程式至 `.pbox`（zstd/xz/gzip）              |
| `packbox-import`    | 匯入 `.pbox` 並驗證路徑穿越                         |
| `packbox-module`    | 管理共享函式庫模組（`list`、`create`）              |
| `packbox-diagnose`  | 列印環境報告用於錯誤報告                            |

完整參考（含選項、結束碼和範例）：
[`commands.md`](commands.md) · [EN](../en/commands.md) · [ES](../es/commands.md)

### 互動式指令碼

- `packbox-installer-v0.1.0.sh` — 安裝 / 解除安裝
- `packbox-packager-v0.1.0.sh` — 封裝、列出、gc、匯出、匯入、解除安裝
- `packbox-i18n.sh` — 共享翻譯層

---

## 檔案系統配置

```
~/.packbox/                     # 安裝（二進位檔 + Go 原始碼）
├── bin/                        # 11 個 Go 二進位檔
└── src/                        # Go 模組原始碼

~/.local/share/packbox/         # 資料
├── store/                      # CAS — 按 BLAKE3 雜湊儲存的區塊
│   └── <ab>/<完整雜湊>         # 每區塊附一個 .refs 檔案
├── apps/                       # 已安裝應用程式（tree + manifest.json）
├── mods/                       # 共享函式庫模組
├── exports/                    # .pbox 封存檔
└── tmp/                        # 暫時工作區

~/.config/packbox/lang/         # 9 個語言檔案
```

---

## 架構

三個元件：

```
┌──────────────┐   pack    ┌──────────────┐   install   ┌──────────────┐
│   來源目錄   │ ────────► │     CAS      │ ──────────► │  應用 tree   │
│  (fs tree)   │           │   (區塊)     │             │  (硬連結)    │
└──────────────┘           └──────────────┘             └──────────────┘
                                  │
                                  │ run
                                  ▼
                         ┌──────────────────┐
                         │  bwrap 沙箱      │
                         │  (DNS/GUI 修正)  │
                         └──────────────────┘
```

- **CAS** — `~/.local/share/packbox/store/`，BLAKE3 雜湊，每區塊一個
  `.refs` 檔案，安裝時使用 `SafeLink`（硬連結 → 複製回退）。
- **Manifest** — `schema_version: "1.5"`，`layers.app.files` 將相對
  路徑對應到 `{chunks, size, mode}`，還有用於主機函式庫信任的
  `host_contract.delegate`。
- **沙箱** — `bwrap --unshare-all --share-net`，`--clearenv` 之後的
  環境白名單，綁定 `/etc/resolv.conf` 前的 DNS 符號連結解析
  （`EvalSymlinks`），GUI 支援（X11、Wayland、D-Bus、`/dev/dri`、
  fontconfig 快取），使用 `--bind-try` 的啟發式每應用程式資料對應。

完整架構（CAS 內部、manifest 模式、沙箱掛載、主機契約）：
[`architecture.md`](../en/architecture.md) · [ES](../es/architecture.md)

---

## 安全

> [!WARNING]
> v0.1.0 Alpha 中 `.pbox` 封存檔**未簽章**。將任何匯入的封存檔視為
> 不可信。簽章驗證在發展藍圖中。

已實作的關鍵緩解措施：

- **路徑穿越防護** — `cas.isValidHash()` 強制 64 個小寫十六進位字元。
  `.pbox` 匯入透過 `security.ValidatePath` 對每個 tar 項目與提取根進行
  驗證。
- **符號連結安全匯入** — 只處理 `tar.TypeDir` 和 `tar.TypeReg`；符號
  連結、硬連結和裝置檔案被靜默跳過。
- **環境清理** — `--clearenv` 後跟明確白名單，阻止來自主機的
  `LD_PRELOAD` / `LD_LIBRARY_PATH` 注入。
- **XAUTHORITY 隔離** — 主機的 `~/.Xauthority` 在綁定到沙箱之前被複製
  到每行程暫存檔（`/tmp/packbox-xauth-<pid>`，模式 0600）。
- **引用計數** — 每個區塊有一個 `.refs` 檔案；`packbox-gc` 只刪除未
  引用的區塊。
- **無 setuid、無 root** — Packbox 完全以呼叫使用者身分執行。`sudo`
  僅由安裝程式用於發行版套件。

已知限制和威脅模型：
[`security.md`](../en/security.md) · [ES](../es/security.md)

報告漏洞時請附上 `packbox-diagnose` 的輸出。對於敏感發現，請使用
倉庫的私密安全聯絡方式。

---

## 發展藍圖

### v0.1.x — 穩定化
- [ ] `.pbox` 封存檔的簽章驗證
- [ ] 每應用程式網路策略（目前 `--share-net` 是全域的）
- [ ] 實作 `packbox-module remove` 和 `info`
- [ ] 針對真實 GTK4/Qt6 應用程式壓力測試 `host_contract.delegate`
- [ ] CI：每個 PR 上執行 `shellcheck`、`gofmt`、`go vet`
- [ ] 測試矩陣：Debian 12、Fedora 40、Arch、openSUSE Tumbleweed

### v0.2 — 涵蓋範圍
- [ ] 為 x86_64 和 aarch64 預編譯二進位檔（發佈頁）
- [ ] `packbox-update` 用於就地版本升級
- [ ] GUI 前端（選用，GTK4）
- [ ] `packbox-export` 的區塊層級增量下載

### 更遠
- [ ] Flatpak 執行階段匯入器（盡力而為）
- [ ] 透過 minisign 或 sigstore 進行簽章驗證
- [ ] 用於不可信外掛的 WASM 沙箱層

---

## 文件

9 種語言的完整文件。英文和西班牙文有完整集（README + 指令 + 架構 +
安全）；其餘七種有 README + 指令。

| 語言     | README                                 | 指令                                            | 架構                                                | 安全                                          |
|----------|----------------------------------------|-------------------------------------------------|-----------------------------------------------------|-----------------------------------------------|
| English  | [en](../en/README.md)                  | [en](../en/commands.md)                         | [en](../en/architecture.md)                         | [en](../en/security.md)                       |
| Español  | [es](../es/README.md)                  | [es](../es/commands.md)                         | [es](../es/architecture.md)                         | [es](../es/security.md)                       |
| Français | [fr](../fr/README.md)                  | [fr](../fr/commands.md)                         | —                                                   | —                                             |
| Deutsch  | [de](../de/README.md)                  | [de](../de/commands.md)                         | —                                                   | —                                             |
| Italiano | [it](../it/README.md)                  | [it](../it/commands.md)                         | —                                                   | —                                             |
| 简体中文 | [zh-CN](../zh-CN/README.md)            | [zh-CN](../zh-CN/commands.md)                   | —                                                   | —                                             |
| 繁體中文 | **zh-TW**                              | [zh-TW](commands.md)                            | —                                                   | —                                             |
| 日本語   | [ja](../ja/README.md)                  | [ja](../ja/commands.md)                         | —                                                   | —                                             |
| 한국어   | [ko](../ko/README.md)                  | [ko](../ko/commands.md)                         | —                                                   | —                                             |

索引：[`docs/README.md`](../README.md)

---

## 貢獻

歡迎貢獻，尤其是：

- **翻譯** — 透過複製 `install_lang_files()` 中的 `en` 區塊並翻譯每個
  `L_*` 鍵，向 `packbox-i18n.sh` 新增語言。
- **沙箱設定** — 針對瀏覽器、IDE、遊戲的每應用程式資料對應。
- **CAS 分塊策略** — 滾動雜湊變體、平行分塊。
- **錯誤報告** — 始終附上 `packbox-diagnose` 輸出。

開始：

```bash
git clone https://github.com/TU_USUARIO/packbox.git
cd packbox
# 閱讀 CONTRIBUTING.md 取得完整指南
```

- 🐛 [開啟 issue](https://github.com/TU_USUARIO/packbox/issues)
- 💬 [發起討論](https://github.com/TU_USUARIO/packbox/discussions)
- 🔧 [CONTRIBUTING.md](../../CONTRIBUTING.md)

提交 PR 前，請對 shell 指令碼執行 `shellcheck`，對 Go 程式碼執行
`gofmt` + `go vet`。

---

## 授權條款

[MIT](../../LICENSE) © 2025 TU_NOMBRE

Packbox 可自由使用、修改和再散布。詳情見
[LICENSE](../../LICENSE)。

---

## 致謝

- **[bubblewrap](https://github.com/containers/bubblewrap)** — 使
  `packbox-run` 成為可能的沙箱原語。
- **[BLAKE3](https://github.com/BLAKE3-team/BLAKE3)** — 快速、安全的
  內容定址。
- **[Flatpak](https://flatpak.org/)** — 證明了沙箱化 Linux 應用程式
  可以大規模運作的專案，其設計決策為我們提供了許多參考（即使我們
  有所分歧）。
- 9 種語言的 i18n 層存在是因為 Linux 社群是全球性的；感謝所有審閱
  過翻譯的人。
