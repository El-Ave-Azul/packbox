# Packbox

**[Español](../../README.md)** · [English](../en/README.md) · [Français](../fr/README.md) · [Deutsch](../de/README.md) · [Italiano](../it/README.md) · [Português](../pt/README.md) · [中文](../zh/README.md) · **[日本語](README.md)** · [한국어](../ko/README.md)

---

![CI](https://github.com/El-Ave-Azul/packbox/actions/workflows/ci.yml/badge.svg)
![ライセンス](https://img.shields.io/badge/Licencia-Apache_2.0-blue.svg)
![バージョン](https://img.shields.io/badge/Versión-0.3.0-orange.svg)
![プラットフォーム](https://img.shields.io/badge/Plataforma-Linux-blue.svg)
![Go](https://img.shields.io/badge/Go-1.22+-00ADD8.svg?logo=go&logoColor=white)
![i18n](https://img.shields.io/badge/i18n-9_languages-green.svg)
![ステータス](https://img.shields.io/badge/Estado-Beta-blue.svg)

**チャンク単位のバイナリ重複排除と、Zstd で圧縮された `.pbox` エクスポートを備えた Linux アプリケーションパッケージャ。**
Flatpak に着想を得ていますが、再利用のモデルは異なります。アプリごとの
モノリシックなランタイムの代わりに、Packbox はコンテンツをコンテンツ
アドレッサブルストレージ（BLAKE3 CAS）に保存し、最適化された**コンテンツ定義チャンキング
（CDC）** と再利用可能な **セル** を用います。ライブラリの 90 % を共有する
2 つのアプリは、差分である 10 % だけを保存します。

> [!IMPORTANT]
> **ベータ状態 (v0.3.0)。** コアの安定性が向上し、LRU ガベージコレクション、エクスポート時の Zstd 圧縮が実装されました。

---

## 目次

- [Packbox とは](#packbox-とは)
- [Flatpak との比較](#flatpak-との比較)
- [要件](#要件)
- [インストール](#インストール)
- [クイックスタート](#クイックスタート)
- [利用可能なコマンド](#利用可能なコマンド)
- [ファイル構造](#ファイル構造)
- [アーキテクチャ](#アーキテクチャ)
- [セキュリティ](#セキュリティ)
- [ロードマップ](#ロードマップ)
- [コントリビュート](#コントリビュート)
- [ライセンス](#ライセンス)
- [謝辞](#謝辞)

---

## Packbox とは

Packbox は **Content-Addressable Storage (CAS)** と **BLAKE3** ハッシュ、
および最適化された**コンテンツによるチャンキング**を用いて Linux アプリケーションを
パッケージ化し、アプリ間で真のバイナリ重複排除を実現します。

アプリケーションごとに約 1 GB のランタイム（Flatpak）を置く代わりに、
Packbox は各ファイルをチャンク（内容で重複排除）として保存し、
すべてのアプリ間で共有します。**Zstd** 圧縮は `.pbox` をエクスポートする際に適用されます。さらに各ライブラリを **セル**（バージョン管理
された再利用単位）に変換し、複数のアプリで共有するとともに、汎用的な
ライブラリ（`libc`、`libm`、…）はホスト側に残します。

### 設計原則

- **チャンクレベルの重複排除。** 同じバイト列 = 同じハッシュ = 一度だけ保存
  （ELF バイナリに最適化された CDC；小さいファイルは単一チャンクとして保存）。
- **生のストア、圧縮されたエクスポート。** CAS はチャンクを非圧縮で保持し、インストール時にそれらを **ハードリンク** できるようにします（ディスク上の実デデュープ）。**Zstd** 圧縮は `.pbox` をビルドする際に適用されます。
- **セル（原子的な断片化）。** 汎用的でない各ライブラリはセルであり、
  アプリがそれを宣言し、インストーラが解決します。
- **横断的な共有。** すべてのアプリが同じグローバル CAS と
  同じセルを共有します。
- **Host contract v1。** 汎用ライブラリの選択的な委譲と、
  必要なシンボルの **ABI チェック**。
- **強化されたサンドボックス（bubblewrap）。** `--unshare-all`、`--cap-drop ALL`、
  **seccomp**、**フィルタ済み D-Bus**（`xdg-dbus-proxy`）、**アプリごとのプライベート HOME**、
  細粒度ネットワーク (none/limited/full) および**自動検出付き X11 オプトイン**。
- **オーバーレイによるレイヤ化。** `/app` は C（セル）の上に A（アプリ）を重ねた
  オーバーレイとして構成され、S（ホスト）は `/usr` 経由で提供されます。
- **署名と配布。** `.pbox` は署名可能（ed25519）で、並行デルタダウンロード対応の
  HTTP リモートを備えます。
- **4 つのパッケージングモード。** Normal、Portable、Bundle、Module。

---

## Flatpak との比較

| 特徴                 | Flatpak（現状）             | Packbox v0.3.0                       |
|----------------------|-----------------------------|--------------------------------------|
| 再利用の単位         | 完全なランタイム（約 1 GB） | lib ごとの **セル**（ランタイムなし）|
| 重複排除             | ファイルレベル（OSTree）    | **チャンク**レベル（BLAKE3 + CDC）   |
| ストレージ           | ランタイムごとに圧縮         | **生のチャンク + ハードリンク**（デデュープ）        |
| ライブラリの共有     | 同じランタイム内            | すべてのアプリ間で横断的             |
| ホストライブラリの利用 | なし                      | 選択的（host contract + ABI）        |
| 更新                 | OSTree のオブジェクト delta | `packbox-update` (delta + LRU GC)    |
| 配布                 | Flathub + OSTree リモート   | 並行 HTTP リモート                  |
| 署名                 | GPG                         | ed25519 (`.pbox.sig`)                |
| サンドボックス       | bwrap + seccomp + ポータル  | bwrap + seccomp + dbus-proxy + ポータル |
| インターフェース     | GNOME Software / CLI        | **TUI** + CLI                          |
| アプリごとの負荷     | ランタイムが異なれば約 100 % | 共有アプリで **約 5〜15 %**    |

---

## 要件

- **オペレーティングシステム**: Linux（Debian 12+、Ubuntu 22.04+、Fedora 40+、Arch、
  openSUSE Tumbleweed）
- **カーネル**: 5.15+、user namespaces が有効であること
- **シェル**: Bash 4.0+
- **Go**: 1.22+（インストーラは、なければ独自のコピーをダウンロードします）
- **容量**: 初回のコンパイルに約 500 MB の空き容量
- **インターネット**: 初回インストール時のみ

### システム依存関係

可能な場合はインストーラによってインストールされます。手動でも役立ちます:

`bubblewrap` · `binutils` (`ldd`/`readelf`) · `jq` · `bc` · `curl` · `tar` ·
`xdg-dbus-proxy`（D-Bus のフィルタリング） · `zstd` または `xz`（よりコンパクトなエクスポート）

---

## インストール

### ステップ 1 — クローンして実行

```bash
git clone https://github.com/El-Ave-Azul/packbox.git
cd packbox
./packbox-install.sh
```

インストーラがメニューを開きます。オプション **1**（インストール）を選んでください。

**コンパイルなし（リリースのビルド済みバイナリ）:**

```bash
./packbox-install.sh --prebuilt
```

お使いのアーキテクチャ（amd64/arm64）のバイナリをダウンロードし、リリースの
`SHA256SUMS` を検証して数秒でインストールします — コンパイル不要、Go 不要。

### ステップ 2 — シェルを再読み込み

```bash
source ~/.bashrc
```

### ステップ 3 — 確認

```bash
packbox-diagnose
```

---

## クイックスタート

### 1. 対話式パッケージャ (TUI)

```bash
./packbox-packager.sh
```

オプション **1 (パッケージ化)** は、**既にインストールされている**アプリを検索し、
`~/.local/share/packbox/exports/` に `.pbox` を**生成**します。完了後、それを
**このマシンにインストール**するかどうかを尋ねます（デフォルトは**いいえ**で、システムを
汚さないようにします）。`.pbox` をインストールするには、オプション **5 (インポート)** を使用してください。

### 2. コマンドライン

```bash
# ディレクトリをパッケージ化する
packbox-pack ./mi-app --name org.ejemplo.miapp --version 1.0.0

# 生成されたマニフェストからインストールする
packbox-install ./mi-app/manifest.json

# サンドボックスで実行する（C の上にオーバーレイ A、プライベート HOME）
packbox-run org.ejemplo.miapp

# アプリを一覧表示し（実サイズと共有による節約量）、容量を解放する
packbox-list
packbox-remove org.ejemplo.miapp
packbox-gc

# ストアのチャンクを再利用してインストール済みアプリを更新する
packbox-update org.ejemplo.miapp ./nuevo/manifest.json

# ...またはリモートから差分（不足しているチャンク）だけを取得する
packbox-update org.ejemplo.miapp --from https://repo.ejemplo/mi-app
```

---

## 利用可能なコマンド

Packbox v0.3.0 には `~/.packbox/bin/` に **15 個の Go バイナリ** が含まれています:

| コマンド           | 目的                                                          |
|--------------------|--------------------------------------------------------------------|
| `packbox-pack`     | ディレクトリを CAS チャンクにハッシュ化し、`manifest.json` を生成する |
| `packbox-install`  | マニフェストからアプリをインストールする（+ `--desktop`/`--remove-desktop`） |
| `packbox-run`      | アプリを `bwrap` サンドボックスで実行する（オーバーレイ A/C、プライベート HOME） |
| `packbox-list`     | アプリを **実サイズ** と共有による節約量とともに一覧表示する（`--tsv`） |
| `packbox-remove`   | アプリをアンインストールし、その CAS 参照を解放する (`--all` = すべて, `--dry-run`) |
| `packbox-gc`       | 参照のないチャンク**とセル**を回収する (LRU をサポート)            |
| `packbox-verify`   | 解決可能な lib + ホストの **ABI 互換性** を確認する |
| `packbox-export`   | **適応型圧縮** と省略可能な `--sign` で `.pbox` にエクスポートする |
| `packbox-import`   | `.pbox` をインポートする（anti tar-slip、traversal、署名）        |
| `packbox-update`   | ストアのチャンクを再利用してアプリを更新する; `--from <url>` はデルタを取得する |
| `packbox-module`   | モジュール/セル: `list`、`create`、`cell <lib>...`                   |
| `packbox-sign`     | ed25519 のキーと署名: `keygen`、`sign`, `verify`, `trust`       |
| `packbox-fetch`    | HTTP リモート: `publish`、**署名付きインデックス**を使う `index`/`search`/`install`、そして `fetch` (並行デルタ) |
| `packbox-debug`    | インストール済みアプリのデバッグシンボル（別のセル）を添付する |
| `packbox-diagnose` | バグ報告用の環境レポート                                 |

---

## アーキテクチャ

### パッケージングの流れ

```
┌──────────────┐   pack    ┌──────────────┐  install  ┌──────────────┐
│  ソースdir.  │ ────────► │     CAS      │ ─────────► │  App Tree    │
│  (fs ツリー)  │           │  (chunks)    │           │ (hardlinks)  │
└──────────────┘           └──────────────┘           └──────┬───────┘
                                    │                          │ + セル (レイヤ C)
                                    │ run                      ▼
                         ┌──────────────────────────────────────────┐
                         │  bwrap サンドボックス: /app = A を C の上にオーバーレイ  │
                         │  プライベート HOME · seccomp · フィルタ済み D-Bus  │
                         └──────────────────────────────────────────┘
```

### 内部コンポーネント

- **CAS + チャンカ** — 生のチャンク（再圧縮せず、ハードリンクできるようにするため）を **BLAKE3** ハッシュで保存します。大きなファイルは**最適化された CDC** で分割され、小さいファイルは単一チャンクとして保存されます。書き込みは**アトミック**です。
- **マニフェスト** (`schema_version: \"1.7\"`) — パスをチャンクにマッピングし、ネットワークポリシー (`none`, `limited`, `full`)、host contract、および X11 シンボルを定義します。
- **セル** — 1 つの lib = `mods/` 内の 1 つのセル `org.lib.<soname>@<hash>`。アプリ間で共有されます。`packbox-gc` は参照されていない、または古いセル (LRU) を削除します。
- **サンドボックス** — `bwrap --unshare-all --cap-drop ALL --clearenv`、**seccomp**、`xdg-dbus-proxy` による**フィルタ済み D-Bus**、**プライベート HOME**、細粒度ネットワーク、および**マルチメディアサポート** (PipeWire/PulseAudio)。
- **オーバーレイによるレイヤ化** — `/app` は `--overlay-src` (C が下、A が上) で構成され、S (ホスト) は `/usr` 経由で提供されます。
- **Host contract** — `packbox-verify` は、ホストが必要なシンボル (ABI) を提供しているかを確認します。
- **署名とリモート** — `packbox-sign` (ed25519) は `.pbox` と**リポジトリインデックス**に署名し、`packbox-fetch` は公開、**検索** (`search`)、id によるインストールを行い、**並行ダウンロード**に対応します。

---

## セキュリティ

### 実装された緩和策

- **アプリごとのデータ分離** — 各アプリは**プライベート HOME** で実行され、フォント/テーマのみが**読み取り専用**で公開されます。
- **フィルタ済み D-Bus** — `xdg-dbus-proxy` とホワイトリスト（ポータル + `dconf`）。
- **seccomp** — 危険なカーネル表面をブロックするデフォルトフィルター。
- **細粒度ネットワーク** — `none`/`limited`/`full` モード。`limited` は、プライベート/予約済みレンジをブロックする内部の **best-effort** プロキシを使用します。これは `http_proxy`/`https_proxy` を尊重するアプリにのみ影響します（生のソケットはフィルタリングされません）。
- **安全なマルチメディアサポート** — ポータルを介してオーディオとカメラへのアクセスを制御します。
- **Anti tar-slip / traversal** — `.pbox` 内のパスの厳格な検証。
- **環境のクリーンアップ** — `--clearenv` + 明示的なホワイトリスト。
- **Reference counting + LRU GC** — アクセス時間に基づいたインテリジェントなチャンククリーンアップ。
- **署名** — `.pbox` は **ed25519** で署名可能です。

---

## ロードマップ

### v0.1.x — 安定化
- [x] `.pbox` の署名検証
- [x] 強化されたサンドボックス: プライベート HOME、フィルタ済み D-Bus、seccomp
- [x] 自動セル + レイヤのオーバーレイ (A/C/S)
- [x] チャンク デルタ + 自動 GC を備えた `packbox-update`
- [x] 並行デルタダウンロード対応の HTTP リモート
- [x] `.pbox` エクスポートでの Zstd 圧縮
- [x] ELF バイナリ向けの CDC チューニング
- [x] LRU ガベージコレクション

### v0.2 — スコープ
- [ ] GTK4 GUI フロントエンド (延期)
- [x] x86_64 および aarch64 の事前コンパイル済みバイナリ
- [x] 署名付き中央インデックス/リポジトリ

### 将来
- [ ] Flatpak ランタイム インポータ (best-effort)
- [ ] 信頼できないプラグイン向け WASM サンドボックス

---

## ライセンス

**Apache License 2.0** の下で配布されています。[LICENSE](../../LICENSE) を参照してください。
