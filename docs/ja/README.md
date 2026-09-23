# Packbox

[Español](../../README.md) · [English](../en/README.md) · [Français](../fr/README.md) · [Deutsch](../de/README.md) · [Italiano](../it/README.md) · [Português](../pt/README.md) · [中文](../zh/README.md) · **[日本語](README.md)** · [한국어](../ko/README.md)

---

![CI](https://github.com/El-Ave-Azul/packbox/actions/workflows/ci.yml/badge.svg)
![Licencia](https://img.shields.io/badge/Licencia-Apache_2.0-blue.svg)
![Versión](https://img.shields.io/badge/Versión-0.2.0-orange.svg)
![Plataforma](https://img.shields.io/badge/Plataforma-Linux-blue.svg)
![Go](https://img.shields.io/badge/Go-1.22+-00ADD8.svg?logo=go&logoColor=white)
![i18n](https://img.shields.io/badge/i18n-9_idiomas-green.svg)
![Estado](https://img.shields.io/badge/Estado-Alpha-red.svg)

**チャンク単位のバイナリ重複排除を備えた Linux アプリケーションパッケージャ。**
Flatpak に着想を得ていますが、再利用のモデルは異なります。アプリごとの
モノリシックなランタイムの代わりに、Packbox はコンテンツをコンテンツ
アドレッサブルストレージ（BLAKE3 CAS）に保存し、**コンテンツ定義チャンキング
（CDC）** と再利用可能な **セル** を用います。ライブラリの 90 % を共有する
2 つのアプリは、差分である 10 % だけを保存します。

> [!WARNING]
> **アルファ状態（v0.2.0）。** 主要なフローは動作しており、署名、強化された
> サンドボックス（seccomp、フィルタ済み D-Bus、プライベート HOME）、HTTP
> リモートもすでにありますが、プロジェクトは若く、Flatpak のようなエコシステム
> や成熟度はありません。まずは重要でないシステムで使用してください。

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
**コンテンツによるチャンキング** を用いて Linux アプリケーションを
パッケージ化し、アプリ間で真のバイナリ重複排除を実現します。

アプリケーションごとに約 1 GB のランタイム（Flatpak）を置く代わりに、
Packbox は各ファイルをコンテンツでアドレス指定されたチャンクとして保存し、
すべてのアプリ間で共有します。さらに各ライブラリを **セル**（バージョン管理
された再利用単位）に変換し、複数のアプリで共有するとともに、汎用的な
ライブラリ（`libc`、`libm`、…）はホスト側に残します。

### 設計原則

- **チャンクレベルの重複排除。** 同じバイト列 = 同じハッシュ = 一度だけ保存
  （大きなファイルは CDC、小さなファイルは単一のチャンクとして扱い、
  ハードリンクして共有できるようにする）。
- **セル（原子的な断片化）。** 汎用的でない各ライブラリはセルであり、
  アプリがそれを宣言し、インストーラが解決する。
- **横断的な共有。** すべてのアプリが同じグローバル CAS と
  同じセルを共有する。
- **Host contract v1。** 汎用ライブラリの選択的な委譲と、
  必要なシンボルの **ABI チェック**。
- **強化されたサンドボックス（bubblewrap）。** `--unshare-all`、`--cap-drop ALL`、
  **seccomp**、**フィルタ済み D-Bus**（`xdg-dbus-proxy`）、**アプリごとのプライベート HOME**、
  ネットワークはオプトイン、**X11 は自動検出付きオプトイン**。
- **オーバーレイによるレイヤ化。** `/app` は C（セル）の上に A（アプリ）を重ねた
  オーバーレイとして構成され、S（ホスト）は `/usr` 経由で提供される。
- **署名と配布。** `.pbox` は署名可能（ed25519）で、デルタダウンロード対応の
  HTTP リモートを備える。
- **4 つのパッケージングモード。** Normal、Portable、Bundle、Module。

---

## Flatpak との比較

| 特徴                 | Flatpak（現状）             | Packbox v0.2.0                       |
|----------------------|-----------------------------|--------------------------------------|
| 再利用の単位         | 完全なランタイム（約 1 GB） | lib ごとの **セル**（ランタイムなし）|
| 重複排除             | ファイルレベル（OSTree）    | **チャンク**レベル（BLAKE3 + CDC）   |
| ライブラリの共有     | 同じランタイム内            | すべてのアプリ間で横断的             |
| ホストライブラリの利用 | なし                      | 選択的（host contract + ABI）        |
| 更新                 | OSTree のオブジェクト delta | `packbox-update`（チャンク delta + GC） |
| 配布                 | Flathub + OSTree リモート   | `publish`/`fetch` による HTTP リモート |
| 署名                 | GPG                         | ed25519（`.pbox.sig`）               |
| サンドボックス       | bwrap + seccomp + ポータル  | bwrap + seccomp + dbus-proxy + ポータル |
| アプリごとのオーバーヘッド | ランタイムが異なれば約 100 % | 共有アプリで **約 5〜15 %**    |

**計測された節約量**（このコードベース）: スタックを共有する中規模の GTK4
アプリ 2 つは、別々に合計約 264 MB となり、実際の占有は **約 141 MB（−46 %）**、
混在する 10 アプリでは節約量が **約 69 %** に上がります。ライブラリの重なりが
大きいほど節約量は大きくなりますが、共有ランタイムの 90〜99 % を想定するのでは
なく、ケースごとに計測することをおすすめします。

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

### ステップ 2 — シェルを再読み込み

```bash
source ~/.bashrc
```

### ステップ 3 — 確認

```bash
packbox-diagnose
```

### インストーラが行うこと

1. 9 つの言語から 1 つを選択できます。
2. Linux ディストリビューションとパッケージマネージャを検出します。
3. 依存関係をインストールする前に確認を求めます。
4. 必要に応じて Go（デフォルトでは 1.27.1）を `~/.packbox/go` にダウンロードして検証します。
5. ディレクトリ構造（`~/.packbox/` と `~/.local/share/packbox/`）を作成します。
6. ソースをコピーし、**15 個のバイナリ** Go をコンパイルします（約 1〜2 分）。
7. `~/.bashrc` に `PATH` を設定し、`~/.local/bin` に symlink を作成します。
8. 言語ファイルを `~/.config/packbox/lang/` にインストールします。
9. すべてのバイナリが存在し、機能することを検証します。

### アンインストール

同じスクリプトを実行し、オプション **2** を選んでください:

```bash
./packbox-install.sh --uninstall
```

| モード | 説明 |
|------|-------------|
| `s`  | 完全: バイナリ + アプリ + CAS ストア + セル + メニュー + アイコン + 設定 |
| `k`  | バイナリのみ: `~/.packbox/` と symlink（アプリと CAS ストアは保持） |
| `q`  | キャンセル |

---

## クイックスタート

### 1. 対話式パッケージャ（推奨）

```bash
./packbox-packager.sh
```

メニュー: パッケージ化、一覧表示、garbage collection、エクスポート、インポート、
アンインストール、言語。`/usr/share/applications/` の `.desktop` からアプリを検出し、
`/opt/*` のバンドルや一般的なバイナリ（`htop`、`btop`、`firefox`、`gimp`、…）も検出します。

**Normal** モードと **Portable** モードでは、`ldd` のクロージャの各非汎用ライブラリが
自動的に **セル** に変換されます。

### 2. コマンドライン

```bash
# ディレクトリをパッケージ化する
packbox-pack ./mi-app --name org.ejemplo.miapp --version 1.0.0

# 生成されたマニフェストからインストールする
packbox-install ./mi-app/manifest.json

# サンドボックスで実行する（C の上にオーバーレイ A、プライベート HOME）
packbox-run org.ejemplo.miapp

# アプリを一覧表示する（実サイズと sharing による節約量）そして容量を解放する
packbox-list
packbox-remove org.ejemplo.miapp
packbox-gc

# ストアのチャンクを再利用してインストール済みアプリを更新する
packbox-update org.ejemplo.miapp ./nuevo/manifest.json
```

### 3. エクスポート、署名、インポート、配布

```bash
# エクスポートして署名する
packbox-sign keygen                       # キーを作成する（そして信頼する）
packbox-export --sign app org.ejemplo.miapp
packbox-sign verify ~/.local/share/packbox/exports/org.ejemplo.miapp.pbox

# HTTP リモートを公開して別のマシンから使用する
packbox-fetch publish org.ejemplo.miapp /srv/packbox
(cd /srv/packbox && python3 -m http.server 8000)
packbox-fetch fetch org.ejemplo.miapp --from http://host:8000

# インポートする（署名があれば検証する）
packbox-import app org.ejemplo.miapp.pbox
```

---

## 利用可能なコマンド

Packbox v0.2.0 には `~/.packbox/bin/` に **15 個の Go バイナリ** が含まれています:

| コマンド           | 目的                                                          |
|--------------------|--------------------------------------------------------------------|
| `packbox-pack`     | ディレクトリを CAS チャンクにハッシュ化し、`manifest.json` を生成する |
| `packbox-install`  | マニフェストからアプリをインストールする（+ `--desktop`/`--remove-desktop`） |
| `packbox-run`      | アプリを `bwrap` サンドボックスで実行する（オーバーレイ A/C、プライベート HOME） |
| `packbox-list`     | アプリを **実サイズ** と sharing による節約量とともに一覧表示する（`--tsv`） |
| `packbox-remove`   | アプリをアンインストールし、その CAS 参照を解放する |
| `packbox-gc`       | 参照のないチャンク**とセル**を回収する |
| `packbox-verify`   | 解決可能な lib + ホストの **ABI 互換性** を確認する |
| `packbox-export`   | **適応型圧縮** と省略可能な `--sign` で `.pbox` にエクスポートする |
| `packbox-import`   | `.pbox` をインポートする（anti tar-slip、traversal、署名） |
| `packbox-update`   | チャンクを再利用してアプリを更新する + delta レポート（`--no-gc`） |
| `packbox-module`   | モジュール/セル: `list`、`create`、`cell <lib>...` |
| `packbox-sign`     | ed25519 のキーと署名: `keygen`、`sign`、`verify`、`trust` |
| `packbox-fetch`    | HTTP リモート: `publish <id> <dir>` と `fetch <id> --from <url>` |
| `packbox-debug`    | インストール済みアプリのデバッグシンボル（別のセル）を添付する |
| `packbox-diagnose` | バグ報告用の環境レポート |

---

## ファイル構造

```
~/.packbox/                              # インストール
├── bin/                                 # コンパイル済みの 15 個の Go バイナリ
└── src/                                 # Go ソースコード

~/.local/share/packbox/                  # ユーザーデータ
├── store/                               # CAS: BLAKE3 ハッシュごとのチャンク
│   └── <ab>/<hash-completo>             # + チャンクごとの .refs ファイル
├── apps/                                # インストール済みアプリ
│   └── <app-id>/
│       ├── manifest.json
│       ├── tree/                        # CAS へのハードリンク（レイヤ A）
│       └── home/                        # プライベート HOME（初回実行時に作成）
├── mods/                                # セル（org.lib.*、org.debug.*）
├── exports/                             # .pbox ファイル（+ .sig）
└── tmp/                                 # 一時ファイル

~/.config/packbox/
├── lang/                                # 9 個の言語ファイル
├── signing.key / signing.pub            # あなたの署名キー
└── trusted/                             # 信頼された公開キー
```

---

## アーキテクチャ

### パッケージングの流れ

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

### 内部コンポーネント

- **CAS + チャンカ** — **BLAKE3** ハッシュごとにチャンクを保存します。大きなファイルは
  **CDC**（*gear* 型のローリングハッシュ）で分割し、小さなファイルは単一の
  チャンク（ハードリンク可能で、共有できる）として扱います。書き込みは
  **アトミック**（temp+rename）。
- **マニフェスト**（`schema_version: "1.6"`）— パスをチャンクにマッピングし、
  **セル**（`mods`）、`host_contract`（delegate + required_symbols）、X11
  シンボル、そして該当する場合は **debug** セルを列挙します。
- **セル** — 1 つの lib = `mods/` 内の 1 つのセル `org.lib.<soname>@<hash>`。
  アプリ間で共有されます。`packbox-gc` は参照されていないものを削除します。
- **サンドボックス** — `bwrap --unshare-all --cap-drop ALL --clearenv`、**seccomp**
  （ptrace/bpf/keyring/io_uring/モジュール…をブロック）、`xdg-dbus-proxy` による
  **フィルタ済み D-Bus**（ポータル + dconf）、**プライベート HOME**（`apps/<id>/home`）、
  ネットワークは **オプトイン**、**X11 オプトイン**（デフォルトは Wayland + ポータル、
  マニフェストが要求する場合、またはセッションが X11 のみの場合にのみ有効化）。
- **レイヤのオーバーレイ** — `/app` は `--overlay-src` で構成されます（C が下、A が
  上）。S（ホスト）は `/usr` 経由で提供されます。各ツリーにセルをコピーするのを
  避けます。
- **Host contract** — `packbox-verify` は、ホストが必要なシンボル（ABI）を提供して
  いるかを確認します。
- **署名とリモート** — `packbox-sign`（ed25519）が `.pbox` に署名し、
  `packbox-fetch` は delta（チャンク + セル）のみを公開・ダウンロードします。

### 重複排除の仕組み

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

## セキュリティ

### 実装されている緩和策

- **アプリごとのデータ分離** — 各アプリは **プライベート HOME**
  （`apps/<id>/home`）で実行されます。フォント/テーマのみが **読み取り専用** で
  公開されます。あなたの実際の設定を見たり触ったりすることはありません。
- **フィルタ済み D-Bus** — ホワイトリスト付きの `xdg-dbus-proxy`（デフォルトでは
  ポータルと `dconf`、システムバスはなし）。アプリは実際のバスとは通信しません。
- **seccomp** — カーネルの危険な領域（ptrace、bpf、keyring、io_uring、userfaultfd、
  モジュール、reboot/swap…）をブロックするデフォルトフィルタ。
- **X11 オプトイン** — デフォルトは Wayland + `xdg-desktop-portal`（ポータルの
  ドキュメントマウントを公開）。X11 はマニフェストの `x11` フラグで有効化するか、
  ホストのセッションが X11 のみの場合は自動的に有効化されます。
- **anti tar-slip / traversal** — `.pbox` の展開は各エントリ（`safeJoin` +
  `O_NOFOLLOW` + シンボリックリンクの宛先）を検証し、アプリのディレクトリから
  抜け出す `name`/パスを拒否します。
- **環境のクリーンアップ** — `--clearenv` + 明示的なホワイトリスト: ホストから
  注入された `LD_PRELOAD`/`LD_LIBRARY_PATH` をブロックします。
- **setuid なし、root なし** — すべてがあなたのユーザーとして実行されます。
  `sudo` はインストール時のシステム依存関係にのみ必要です。
- **Reference counting + GC** — 各チャンクには `.refs` があります。`packbox-gc` は
  参照されていないもの（チャンク**とセル**）だけを削除します。
- **署名** — `.pbox` は **ed25519** で署名可能です。`import` は改ざんされた
  パッケージや信頼できない署名者のパッケージを検証して **拒否** します。
- **CAS の整合性** — ハッシュはパスとして使用される前に検証されます。
  書き込みはアトミックです。

### 既知の制限（v0.2.0 Alpha）

> [!WARNING]
> フィードバックを最も歓迎する領域です。

- ⚠️ **部分的なポータル。** ポータルとの通信は許可され、ドキュメントのマウントも
  公開されますが、すべて（カメラ、クリップボードなど）にポータルが使われている
  わけではありません。
- ⚠️ **`packbox-module remove`/`info`** はまだ実装されていません（`cell` は
  存在します）。
- ⚠️ **適応型圧縮** はパッケージレベルであり、エントリごとではありません（形式は
  tar + 1 つのコンプレッサです）。
- ⚠️ **カタログなし。** HTTP リモートはデータを配信するだけで、信頼や公開
  インデックスは提供しません。

---

## ロードマップ

### v0.1.x — 安定化

- [x] `.pbox` の署名検証（ed25519 + キー管理）
- [x] 強化されたサンドボックス: プライベート HOME、フィルタ済み D-Bus、seccomp
- [x] 自動セル + レイヤのオーバーレイ（A/C/S）
- [x] チャンク delta + 自動 GC を備えた `packbox-update`
- [x] delta ダウンロード対応の HTTP リモート（`publish`/`fetch`）
- [x] 分離されたデバッグシンボル（`cell-debug`）
- [x] `export` における適応型圧縮
- [x] エンドツーエンドの統合テスト（`tests/integration.sh`）
- [ ] アプリケーションごとのネットワークポリシー
- [ ] 完全なポータル（ファイル、カメラ、クリップボード）
- [ ] CI/CD: 各 PR での `shellcheck`、`gofmt`、`go vet`
- [ ] テストマトリクス: Debian 12、Fedora 40、Arch、openSUSE Tumbleweed

### v0.2 — スコープ

- [ ] 事前コンパイル済みバイナリ x86_64 および aarch64（リリースページ）
- [ ] 署名済みの集中インデックス/リポジトリ（リモートからの `search`/`install`）
- [ ] 省略可能な GUI フロントエンド（GTK4）

### 将来

- [ ] Flatpak ランタイムのインポータ（best-effort）
- [ ] 信頼できないプラグイン向けの WASM サンドボックス

---

## コントリビュート

コントリビューションを歓迎します！特に助けが役立つ領域:

- **翻訳** — `i18n/` 内の既存のブロックをコピーし、各 `L_*` キーを翻訳して
  locale を追加してください。
- **ポータル** — ファイルアクセスのための `xdg-desktop-portal` の統合。
- **チャンキング / dedup** — CDC としきい値ポリシーの改善。
- **バグ報告** — 常に `packbox-diagnose` の出力を含めてください。

### はじめかた

```bash
git clone https://github.com/El-Ave-Azul/packbox.git
cd packbox
cd src && go test ./...     # ユニットテスト
bash tests/integration.sh   # エンドツーエンド（pack → export → import → run）
```

- 🐛 [issue を開く](https://github.com/El-Ave-Azul/packbox/issues)
- 💬 [ディスカッションを開始する](https://github.com/El-Ave-Azul/packbox/discussions)

> [!TIP]
> PR を送る前に、bash スクリプトには `shellcheck` を、Go には `gofmt` + `go vet` を
> 実行してください。

---

## ライセンス

**Apache License 2.0** の下で配布されています。[LICENSE](../../LICENSE) を参照してください。

Apache 2.0 は **明示的な特許許諾条項** を提供し、重複排除やサンドボックスの技術に
関する訴訟からユーザーとコントリビューターを保護するとともに、GPLv3 と互換性が
あります。

---

## 謝辞

- **[bubblewrap](https://github.com/containers/bubblewrap)** — `packbox-run` を
  可能にする Linux サンドボックスのプリミティブ。
- **[BLAKE3](https://github.com/BLAKE3-team/BLAKE3)** — 高速で暗号学的に安全な
  コンテンツハッシュ。
- **[xdg-desktop-portal](https://flatpak.github.io/xdg-desktop-portal/)** と
  **xdg-dbus-proxy** — 仲介されたファイルアクセスと D-Bus のフィルタリング。
- **[Flatpak](https://flatpak.org/)** — サンドボックス化された Linux アプリが
  大規模に機能することを示しました。その多くの決定が、私たちが異なる道を選んだ
  箇所も含め、私たちの判断の参考になりました。
- **世界中の Linux コミュニティ** — 9 言語の i18n レイヤは、そのレビューと
  コントリビューションのおかげで存在しています。
