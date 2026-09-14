[English](../../README.md) · [Español](../../README.es.md) · [Français](../fr/README.md) · [Deutsch](../de/README.md) · [Italiano](../it/README.md) · [简体中文](../zh-CN/README.md) · [繁體中文](../zh-TW/README.md) · **日本語** · [한국어](../ko/README.md)

---

![ライセンス: MIT](https://img.shields.io/badge/ライセンス-MIT-yellow.svg)
![プラットフォーム: Linux](https://img.shields.io/badge/プラットフォーム-Linux-blue)
![バージョン](https://img.shields.io/badge/バージョン-0.1.0--alpha-orange)
![Go](https://img.shields.io/badge/Go-1.22+-00ADD8?logo=go&logoColor=white)
![i18n](https://img.shields.io/badge/i18n-9_言語-green)
![ステータス](https://img.shields.io/badge/ステータス-alpha-red)

# Packbox

**Linux 向けの次世代アプリケーションパッケージングシステム。**
Flatpak にインスパイアされていますが、根本的に異なる再利用モデルを
採用しています。Packbox はアプリごとにモノリシックなランタイムを配布
する代わりに、各ファイルをコンテンツアドレス指定のチャンク
（BLAKE3 CAS）として保存します。ライブラリの 90% を共有する 2 つの
アプリは、異なる 10% のみを保存します。

> [!NOTE]
> **Packbox は Alpha 段階（v0.1.0）です。** コアワークフローは動作
> しますが、`.pbox` アーカイブの署名検証は未実装で、サンドボックスは
> Flatpak よりも意図的に寛容です。まず重要でないシステムで使用して
> ください。

---

## 目次

- [なぜ Packbox か](#なぜ-packbox-か)
- [Flatpak との比較](#flatpak-との比較)
- [要件](#要件)
- [インストール](#インストール)
- [クイックスタート](#クイックスタート)
- [コマンド](#コマンド)
- [ファイルシステムレイアウト](#ファイルシステムレイアウト)
- [アーキテクチャ](#アーキテクチャ)
- [セキュリティ](#セキュリティ)
- [ロードマップ](#ロードマップ)
- [ドキュメント](#ドキュメント)
- [コントリビュート](#コントリビュート)
- [ライセンス](#ライセンス)
- [謝辞](#謝辞)

---

## なぜ Packbox か

Flatpak は実際の問題を解決しました：サンドボックス化されたポータブルな
Linux アプリです。しかし、その再利用モデルは粗すぎます。各アプリは
**~1 GB** にもなる完全なランタイムを同梱（または参照）します。2 つの
アプリが異なるランタイムを使うと、ライブラリの 95% を共有していても
二重にコストを払います。

Packbox はそのギャップに焦点を当てます：

- **チャンクレベルの重複排除。** ファイルは分割され、BLAKE3 で
  ハッシュ化され、チャンクとして保存されます。同一のチャンク
  （`libfoo.so.3.2.1`、フォント、翻訳カタログ）はシステム上のすべての
  アプリ間で共有されます。
- **アプリ間のライブラリ共有。** 同じ `libQt6Core.so` を使う 2 つの
  アプリは、どの「ランタイム」に属していてもディスク上に 1 つのコピー
  しか持ちません。
- **ホストライブラリの選択的使用。** アプリは信頼するホスト
  ライブラリを（`host_contract.delegate` 経由で）宣言でき、すべてを
  同梱する必要がありません。
- **アプリごとのフットプリントが小さい。** 実際には、既存のセットに
  新しいアプリを追加するコストはそのサイズの ~5–15% で、~100% では
  ありません。

Packbox は Flatpak を**置き換えようとしているわけではありません**。
別のニッチを探求しています：ランタイムにきれいに対応しないアプリ、ま
たは 50 MB のツールを実行するために 1 GB を送るのが過剰なケースです。

---

## Flatpak との比較

| 機能                  | Flatpak（現在）              | Packbox（提案）            |
|-----------------------|------------------------------|----------------------------|
| 再利用単位            | 完全なランタイム（~1 GB）    | 原子セル（~5–50 MB）       |
| 重複排除              | ファイル単位（OSTree）       | チャンク単位（BLAKE3 CAS） |
| ライブラリ共有        | 同一ランタイム内             | すべてのアプリ間           |
| ホストライブラリ使用  | なし（完全サンドボックス）   | 選択的（ABI 互換）         |
| 更新                  | OSTree オブジェクト差分      | チャンク差分 + 並べ替え    |
| アプリごとのオーバーヘッド | ランタイムが異なれば ~100% | ~5–15%（差分のみ）         |

---

## 要件

- **Linux**（Debian 12、Fedora 40、現行 Arch でテスト済み）
- **Bash 4+**
- **Go 1.22+**（不足していれば自動インストール）
- **bubblewrap**（`bwrap`）—— 自動インストール
- **binutils**（`ldd`、`readelf`）—— 自動インストール
- **圧縮ツール**：`zstd`、`xz`、`gzip`（少なくとも 1 つ）
- **~500 MB の空きディスク**（Go をゼロからインストールする場合）

サポートするディストリビューション：**Debian/Ubuntu/Mint/Pop**、
**Fedora/RHEL/Rocky**、**Arch/Manjaro/EndeavourOS**、**openSUSE**。

---

## インストール

```bash
git clone https://github.com/El-Ave-Azul/packbox.git
cd packbox
./packbox-installer-v0.1.0.sh
source ~/.bashrc
packbox-diagnose
```

インストーラーは対話型で：

1. ディストリビューションとパッケージマネージャを検出します。
2. 依存関係（`bubblewrap binutils jq bc curl tar`）のインストール前に
   確認します。
3. 不足していれば Go 1.22+ をインストールします。
4. `~/.packbox/{bin,src}` と
   `~/.local/share/packbox/{store,apps,mods,exports,tmp}` を作成します。
5. ローカルソースから 11 個の Go バイナリ + 内部パッケージを生成します。
6. すべてをコンパイルします（現代のハードウェアで ~2–3 分）。
7. `~/.packbox/bin` を `PATH` に追加し、`~/.local/bin` に
   シンボリックリンクを作成します。
8. 11 個すべてのバイナリが存在することを検証します。

**言語**：インストーラーは起動時に 9 言語のいずれかを尋ねます —
English、Español、Français、Deutsch、Italiano、简体中文、繁體中文、
日本語、한국어。

### アンインストール

同じスクリプトを実行し、オプション `2` を選択：

- モード `s` → 完全削除（バイナリ + アプリ + ストア + メニュー + 設定）
- モード `k` → バイナリのみ（アプリとストアは保持）
- モード `q` → キャンセル

確認のため `DELETE` の入力を要求します。

---

## クイックスタート

### 対話型パッケージャー（推奨）

```bash
./packbox-packager-v0.1.0.sh
```

メニュー：パッケージ、リスト、gc、エクスポート、インポート、
アンインストール。

### コマンドライン

```bash
# 1. ディレクトリを CAS チャンク + manifest.json にパッケージ
packbox-pack ./firefox-tree \
    --name org.mozilla.firefox \
    --version 128.0 \
    --description "Mozilla Firefox" \
    --gui --toolkit GTK3

# 2. 生成された manifest からインストール
packbox-install ./firefox-tree/manifest.json

# 3. bwrap サンドボックス内で実行（DNS + GUI 修正適用済み）
packbox-run org.mozilla.firefox

# 4. インストール済みの内容を表示
packbox-list

# 5. アンインストールしてチャンクを解放
packbox-remove org.mozilla.firefox
packbox-gc
```

---

## コマンド

11 個の Go バイナリ、すべて `~/.packbox/bin/` 配下：

| コマンド            | 目的                                                  |
|---------------------|-------------------------------------------------------|
| `packbox-pack`      | ディレクトリを CAS チャンク + `manifest.json` にハッシュ |
| `packbox-install`   | manifest からインストール（CAS からハードリンク）     |
| `packbox-run`       | `bwrap` 内で実行、DNS + GUI 対応                      |
| `packbox-list`      | インストール済みアプリをバージョンとタグ付きで一覧    |
| `packbox-remove`    | アンインストールして CAS 参照を解放                   |
| `packbox-gc`        | 孤立チャンクをガベージコレクト                        |
| `packbox-verify`    | `ldd` ベースのライブラリ互換性チェック                |
| `packbox-export`    | アプリを `.pbox` にエクスポート（zstd/xz/gzip）       |
| `packbox-import`    | パストラバーサル検証付きで `.pbox` をインポート       |
| `packbox-module`    | 共有ライブラリモジュールを管理（`list`、`create`）    |
| `packbox-diagnose`  | バグレポート用に環境レポートを出力                    |

オプション、終了コード、例を含む完全なリファレンス：
[`commands.md`](commands.md) · [EN](../en/commands.md) · [ES](../es/commands.md)

### 対話型スクリプト

- `packbox-installer-v0.1.0.sh` — インストール / アンインストール
- `packbox-packager-v0.1.0.sh` — パッケージ、リスト、gc、エクスポート、インポート、アンインストール
- `packbox-i18n.sh` — 共有翻訳レイヤー

---

## ファイルシステムレイアウト

```
~/.packbox/                     # インストール（バイナリ + Go ソース）
├── bin/                        # 11 個の Go バイナリ
└── src/                        # Go モジュールソース

~/.local/share/packbox/         # データ
├── store/                      # CAS — BLAKE3 ハッシュ別のチャンク
│   └── <ab>/<完全ハッシュ>      # チャンクごとに .refs ファイル
├── apps/                       # インストール済みアプリ（tree + manifest.json）
├── mods/                       # 共有ライブラリモジュール
├── exports/                    # .pbox アーカイブ
└── tmp/                        # 一時作業領域

~/.config/packbox/lang/         # 9 個の言語ファイル
```

---

## アーキテクチャ

3 つの可動部：

```
┌──────────────┐   pack    ┌──────────────┐   install   ┌──────────────┐
│  ソースディレクトリ │ ──► │     CAS      │ ──────────► │  アプリ tree │
│  (fs tree)   │           │  (チャンク)  │             │  (ハードリンク) │
└──────────────┘           └──────────────┘             └──────────────┘
                                  │
                                  │ run
                                  ▼
                         ┌──────────────────┐
                         │  bwrap サンドボックス │
                         │  (DNS/GUI 修正)  │
                         └──────────────────┘
```

- **CAS** — `~/.local/share/packbox/store/`、BLAKE3 ハッシュ、チャンク
  ごとに `.refs` ファイル、インストール時の `SafeLink`（ハードリンク
  → コピーへのフォールバック）。
- **Manifest** — `schema_version: "1.5"`、`layers.app.files` が相対
  パスを `{chunks, size, mode}` にマップ、さらにホストライブラリの
  信頼のための `host_contract.delegate`。
- **サンドボックス** — `bwrap --unshare-all --share-net`、
  `--clearenv` 後の環境ホワイトリスト、`/etc/resolv.conf` をバインド
  する前の DNS シンボリックリンク解決（`EvalSymlinks`）、GUI サポート
  （X11、Wayland、D-Bus、`/dev/dri`、fontconfig キャッシュ）、
  `--bind-try` を使ったアプリごとのヒューリスティックデータマップ。

完全なアーキテクチャ（CAS 内部、manifest スキーマ、サンドボックス
マウント、ホスト契約）：[`architecture.md`](../en/architecture.md) ·
[ES](../es/architecture.md)

---

## セキュリティ

> [!WARNING]
> v0.1.0 Alpha では `.pbox` アーカイブは**署名されていません**。
> インポートしたアーカイブは信頼できないものとして扱ってください。
> 署名検証はロードマップにあります。

すでに実装されている主な緩和策：

- **パストラバーサル保護** — `cas.isValidHash()` は 64 文字の小文字
  16 進数を強制します。`.pbox` インポートは `security.ValidatePath` を
  介して各 tar エントリを抽出ルートに対して検証します。
- **シンボリックリンク安全なインポート** — `tar.TypeDir` と
  `tar.TypeReg` のみを処理；シンボリックリンク、ハードリンク、デバイス
  ファイルは静かにスキップされます。
- **環境のスクラブ** — `--clearenv` の後に明示的なホワイトリストで、
  ホストからの `LD_PRELOAD` / `LD_LIBRARY_PATH` 注入をブロックします。
- **XAUTHORITY の分離** — ホストの `~/.Xauthority` はサンドボックスに
  バインドする前にプロセスごとの一時ファイル
  （`/tmp/packbox-xauth-<pid>`、モード 0600）にコピーされます。
- **参照カウント** — 各チャンクは `.refs` ファイルを持ち、
  `packbox-gc` は参照されていないチャンクのみを削除します。
- **setuid なし、root なし** — Packbox は完全に呼び出しユーザーとして
  動作します。`sudo` はインストーラーがディストリビューション
  パッケージに使用するだけです。

既知の制限と脅威モデル：
[`security.md`](../en/security.md) · [ES](../es/security.md)

脆弱性を報告する際は `packbox-diagnose` の出力を添付してください。
機密性の高い発見については、リポジトリのプライベートセキュリティ窓口を
使用してください。

---

## ロードマップ

### v0.1.x — 安定化
- [ ] `.pbox` アーカイブの署名検証
- [ ] アプリごとのネットワークポリシー（現在 `--share-net` はグローバル）
- [ ] `packbox-module remove` と `info` の実装
- [ ] 実際の GTK4/Qt6 アプリに対する `host_contract.delegate` の
      ストレステスト
- [ ] CI：各 PR で `shellcheck`、`gofmt`、`go vet`
- [ ] テストマトリクス：Debian 12、Fedora 40、Arch、openSUSE Tumbleweed

### v0.2 — リーチ
- [ ] x86_64 と aarch64 のプリビルドバイナリ（リリースページ）
- [ ] インプレース更新のための `packbox-update`
- [ ] GUI フロントエンド（オプション、GTK4）
- [ ] `packbox-export` のチャンクレベル差分ダウンロード

### さらに先
- [ ] Flatpak ランタイムインポーター（ベストエフォート）
- [ ] minisign または sigstore による署名検証
- [ ] 信頼できないプラグイン用の WASM サンドボックス層

---

## ドキュメント

9 言語の完全なドキュメント。英語とスペイン語は完全なセット
（README + コマンド + アーキテクチャ + セキュリティ）、他の 7 言語は
README + コマンドです。

| 言語     | README                                 | コマンド                                        | アーキテクチャ                                      | セキュリティ                                  |
|----------|----------------------------------------|-------------------------------------------------|-----------------------------------------------------|-----------------------------------------------|
| English  | [en](../en/README.md)                  | [en](../en/commands.md)                         | [en](../en/architecture.md)                         | [en](../en/security.md)                       |
| Español  | [es](../es/README.md)                  | [es](../es/commands.md)                         | [es](../es/architecture.md)                         | [es](../es/security.md)                       |
| Français | [fr](../fr/README.md)                  | [fr](../fr/commands.md)                         | —                                                   | —                                             |
| Deutsch  | [de](../de/README.md)                  | [de](../de/commands.md)                         | —                                                   | —                                             |
| Italiano | [it](../it/README.md)                  | [it](../it/commands.md)                         | —                                                   | —                                             |
| 简体中文 | [zh-CN](../zh-CN/README.md)            | [zh-CN](../zh-CN/commands.md)                   | —                                                   | —                                             |
| 繁體中文 | [zh-TW](../zh-TW/README.md)            | [zh-TW](../zh-TW/commands.md)                   | —                                                   | —                                             |
| 日本語   | **ja**                                 | [ja](commands.md)                               | —                                                   | —                                             |
| 한국어   | [ko](../ko/README.md)                  | [ko](../ko/commands.md)                         | —                                                   | —                                             |

インデックス：[`docs/README.md`](../README.md)

---

## コントリビュート

コントリビュートを歓迎します。特に：

- **翻訳** — `install_lang_files()` 内の `en` ブロックをコピーし、
  すべての `L_*` キーを翻訳して `packbox-i18n.sh` にロケールを追加。
- **サンドボックスプロファイル** — ブラウザ、IDE、ゲームのアプリごと
  データマップ。
- **CAS チャンキング戦略** — ローリングハッシュ変種、並列チャンキング。
- **バグレポート** — 常に `packbox-diagnose` 出力を添付。

はじめに：

```bash
git clone https://github.com/TU_USUARIO/packbox.git
cd packbox
# CONTRIBUTING.md で完全なガイドラインを読む
```

- 🐛 [Issue を開く](https://github.com/TU_USUARIO/packbox/issues)
- 💬 [ディスカッションを開始](https://github.com/TU_USUARIO/packbox/discussions)
- 🔧 [CONTRIBUTING.md](../../CONTRIBUTING.md)

PR を送る前に、シェルスクリプトに `shellcheck`、Go コードに `gofmt` +
`go vet` を実行してください。

---

## ライセンス

[MIT](../../LICENSE) © 2025 TU_NOMBRE

Packbox は自由に使用、変更、再配布できます。詳細は
[LICENSE](../../LICENSE) を参照。

---

## 謝辞

- **[bubblewrap](https://github.com/containers/bubblewrap)** —
  `packbox-run` を可能にするサンドボックスプリミティブ。
- **[BLAKE3](https://github.com/BLAKE3-team/BLAKE3)** — 高速で安全な
  コンテンツアドレス指定。
- **[Flatpak](https://flatpak.org/)** — サンドボックス化された Linux
  アプリが大規模に機能することを証明したプロジェクトで、その設計上の
  決定は（私たちが分岐する箇所でも）多くの参考になりました。
- 9 言語の i18n レイヤーは Linux コミュニティがグローバルであるため
  存在します；翻訳をレビューしてくれたすべての人に感謝します。
