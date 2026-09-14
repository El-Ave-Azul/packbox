[English](../../README.md) · [Español](../../README.es.md) · [Français](../fr/README.md) · [Deutsch](../de/README.md) · [Italiano](../it/README.md) · [简体中文](../zh-CN/README.md) · [繁體中文](../zh-TW/README.md) · [日本語](../ja/README.md) · **한국어**

---

![라이선스: MIT](https://img.shields.io/badge/라이선스-MIT-yellow.svg)
![플랫폼: Linux](https://img.shields.io/badge/플랫폼-Linux-blue)
![버전](https://img.shields.io/badge/버전-0.1.0--alpha-orange)
![Go](https://img.shields.io/badge/Go-1.22+-00ADD8?logo=go&logoColor=white)
![i18n](https://img.shields.io/badge/i18n-9개_언어-green)
![상태](https://img.shields.io/badge/상태-alpha-red)

# Packbox

**Linux용 차세대 애플리케이션 패키징 시스템.** Flatpak에서 영감을 받았지만
근본적으로 다른 재사용 모델을 채택합니다. Packbox는 앱마다 모놀리식
런타임을 배포하는 대신, 각 파일을 콘텐츠 주소 지정 청크(BLAKE3 CAS)로
저장합니다. 라이브러리의 90%를 공유하는 두 앱은 차이나는 10%만
저장합니다.

> [!NOTE]
> **Packbox는 Alpha 단계(v0.1.0)입니다.** 핵심 워크플로는 동작하지만
> `.pbox` 아카이브의 서명 검증이 아직 없고, 샌드박스는 Flatpak보다
> 의도적으로 더 관대합니다. 먼저 중요하지 않은 시스템에서 사용하세요.

---

## 목차

- [Packbox를 선택하는 이유](#packbox를-선택하는-이유)
- [Flatpak과의 비교](#flatpak과의-비교)
- [요구 사항](#요구-사항)
- [설치](#설치)
- [빠른 시작](#빠른-시작)
- [명령어](#명령어)
- [파일 시스템 레이아웃](#파일-시스템-레이아웃)
- [아키텍처](#아키텍처)
- [보안](#보안)
- [로드맵](#로드맵)
- [문서](#문서)
- [기여](#기여)
- [라이선스](#라이선스)
- [감사의 글](#감사의-글)

---

## Packbox를 선택하는 이유

Flatpak은 실제 문제를 해결했습니다: 샌드박스화되고 이식 가능한 Linux
앱입니다. 하지만 그 재사용 모델은 너무 거칩니다. 각 앱은 **~1 GB**에
달할 수 있는 완전한 런타임을 동봉(또는 참조)합니다. 두 앱이 다른
런타임을 사용하면 라이브러리의 95%를 공유하더라도 두 번 비용을
지불합니다.

Packbox는 바로 그 틈을 공략합니다:

- **청크 수준 중복 제거.** 파일이 분할되고 BLAKE3로 해싱되어 청크로
  저장됩니다. 동일한 청크(`libfoo.so.3.2.1`, 폰트, 번역 카탈로그)는
  시스템의 모든 앱 간에 공유됩니다.
- **앱 간 라이브러리 공유.** 같은 `libQt6Core.so`를 사용하는 두 앱은
  어떤 "런타임"에 속하든 디스크에 사본을 하나만 유지합니다.
- **호스트 라이브러리의 선택적 사용.** 앱은 모든 것을 동봉하는 대신
  (`host_contract.delegate`를 통해) 신뢰하는 호스트 라이브러리를
  선언할 수 있습니다.
- **앱당 작은 풋프린트.** 실제로 기존 세트 위에 새 앱을 추가하는
  비용은 그 크기의 ~5–15%이지, ~100%가 아닙니다.

Packbox는 Flatpak을 **대체하려는 것이 아닙니다**. 런타임에 깔끔하게
매핑되지 않는 앱, 또는 50 MB 도구를 실행하기 위해 1 GB를 보내는 것이
과한 경우라는 다른 틈새를 탐구합니다.

---

## Flatpak과의 비교

| 기능               | Flatpak (현재)             | Packbox (제안)             |
|--------------------|----------------------------|----------------------------|
| 재사용 단위        | 전체 런타임 (~1 GB)        | 원자 셀 (~5–50 MB)         |
| 중복 제거          | 파일 수준 (OSTree)         | 청크 수준 (BLAKE3 CAS)     |
| 라이브러리 공유    | 동일 런타임 내             | 모든 앱 간                 |
| 호스트 라이브러리  | 없음 (완전 샌드박스)       | 선택적 (ABI 호환)          |
| 업데이트           | OSTree 객체 델타           | 청크 델타 + 재정렬         |
| 앱당 오버헤드      | 런타임이 다르면 ~100%      | ~5–15% (차이만)            |

---

## 요구 사항

- **Linux** (Debian 12, Fedora 40, 최신 Arch에서 테스트)
- **Bash 4+**
- **Go 1.22+** (없으면 자동 설치)
- **bubblewrap** (`bwrap`) — 자동 설치
- **binutils** (`ldd`, `readelf`) — 자동 설치
- **압축 도구**: `zstd`, `xz`, `gzip` (최소 하나)
- **~500 MB 여유 디스크** (Go를 처음부터 설치하는 경우)

지원 배포판: **Debian/Ubuntu/Mint/Pop**, **Fedora/RHEL/Rocky**,
**Arch/Manjaro/EndeavourOS**, **openSUSE**.

---

## 설치

```bash
git clone https://github.com/TU_USUARIO/packbox.git
cd packbox
./packbox-installer-v0.1.0.sh
source ~/.bashrc
packbox-diagnose
```

설치 프로그램은 대화형이며:

1. 배포판과 패키지 관리자를 감지합니다.
2. 종속성(`bubblewrap binutils jq bc curl tar`) 설치 전 확인합니다.
3. 없으면 Go 1.22+를 설치합니다.
4. `~/.packbox/{bin,src}` 및
   `~/.local/share/packbox/{store,apps,mods,exports,tmp}`를 생성합니다.
5. 로컬 소스에서 11개 Go 바이너리 + 내부 패키지를 생성합니다.
6. 모두 컴파일합니다 (현대 하드웨어에서 ~2–3분).
7. `~/.packbox/bin`을 `PATH`에 추가하고 `~/.local/bin`에 심볼릭 링크를
   만듭니다.
8. 11개 바이너리가 모두 있는지 검증합니다.

**언어**: 설치 프로그램은 시작 시 9개 언어 중 하나를 묻습니다 —
English, Español, Français, Deutsch, Italiano, 简体中文, 繁體中文,
日本語, 한국어.

### 제거

같은 스크립트를 실행하고 옵션 `2` 선택:

- 모드 `s` → 완전 제거 (바이너리 + 앱 + 스토어 + 메뉴 + 설정)
- 모드 `k` → 바이너리만 (앱과 스토어 유지)
- 모드 `q` → 취소

확인을 위해 `DELETE` 입력이 필요합니다.

---

## 빠른 시작

### 대화형 패키저 (권장)

```bash
./packbox-packager-v0.1.0.sh
```

메뉴: 패키징, 목록, gc, 내보내기, 가져오기, 제거.

### 명령줄

```bash
# 1. 디렉터리를 CAS 청크 + manifest.json으로 패키징
packbox-pack ./firefox-tree \
    --name org.mozilla.firefox \
    --version 128.0 \
    --description "Mozilla Firefox" \
    --gui --toolkit GTK3

# 2. 생성된 manifest에서 설치
packbox-install ./firefox-tree/manifest.json

# 3. bwrap 샌드박스에서 실행 (DNS + GUI 수정 적용)
packbox-run org.mozilla.firefox

# 4. 설치된 항목 보기
packbox-list

# 5. 제거하고 청크 회수
packbox-remove org.mozilla.firefox
packbox-gc
```

---

## 명령어

11개 Go 바이너리, 모두 `~/.packbox/bin/` 아래:

| 명령어              | 목적                                                |
|---------------------|-----------------------------------------------------|
| `packbox-pack`      | 디렉터리를 CAS 청크 + `manifest.json`으로 해싱      |
| `packbox-install`   | manifest에서 설치 (CAS에서 하드링크)                |
| `packbox-run`       | `bwrap`에서 실행, DNS + GUI 지원                    |
| `packbox-list`      | 설치된 앱을 버전과 태그와 함께 나열                 |
| `packbox-remove`    | 앱 제거 및 CAS 참조 해제                            |
| `packbox-gc`        | 고아 청크 가비지 컬렉션                             |
| `packbox-verify`    | `ldd` 기반 라이브러리 호환성 검사                   |
| `packbox-export`    | 앱을 `.pbox`로 내보내기 (zstd/xz/gzip)              |
| `packbox-import`    | 경로 탐색 검증과 함께 `.pbox` 가져오기              |
| `packbox-module`    | 공유 라이브러리 모듈 관리 (`list`, `create`)        |
| `packbox-diagnose`  | 버그 보고용 환경 보고서 출력                        |

옵션, 종료 코드, 예제가 포함된 전체 참조:
[`commands.md`](commands.md) · [EN](../en/commands.md) · [ES](../es/commands.md)

### 대화형 스크립트

- `packbox-installer-v0.1.0.sh` — 설치 / 제거
- `packbox-packager-v0.1.0.sh` — 패키징, 목록, gc, 내보내기, 가져오기, 제거
- `packbox-i18n.sh` — 공유 번역 레이어

---

## 파일 시스템 레이아웃

```
~/.packbox/                     # 설치 (바이너리 + Go 소스)
├── bin/                        # 11개 Go 바이너리
└── src/                        # Go 모듈 소스

~/.local/share/packbox/         # 데이터
├── store/                      # CAS — BLAKE3 해시별 청크
│   └── <ab>/<전체-해시>        # 청크당 .refs 파일
├── apps/                       # 설치된 앱 (tree + manifest.json)
├── mods/                       # 공유 라이브러리 모듈
├── exports/                    # .pbox 아카이브
└── tmp/                        # 임시 작업 공간

~/.config/packbox/lang/         # 9개 언어 파일
```

---

## 아키텍처

세 가지 구성 요소:

```
┌──────────────┐   pack    ┌──────────────┐   install   ┌──────────────┐
│  소스 디렉터리 │ ────►   │     CAS      │ ──────────► │  앱 tree     │
│  (fs tree)   │           │  (청크)      │             │ (하드링크)   │
└──────────────┘           └──────────────┘             └──────────────┘
                                  │
                                  │ run
                                  ▼
                         ┌──────────────────┐
                         │  bwrap 샌드박스  │
                         │  (DNS/GUI 수정)  │
                         └──────────────────┘
```

- **CAS** — `~/.local/share/packbox/store/`, BLAKE3 해시, 청크당 하나의
  `.refs` 파일, 설치 시 `SafeLink` (하드링크 → 복사 폴백).
- **Manifest** — `schema_version: "1.5"`, `layers.app.files`가 상대
  경로를 `{chunks, size, mode}`에 매핑하고, 호스트 라이브러리 신뢰를
  위한 `host_contract.delegate`도 포함.
- **샌드박스** — `bwrap --unshare-all --share-net`, `--clearenv` 후
  환경 화이트리스트, `/etc/resolv.conf` 바인드 전 DNS 심볼릭 링크 해석
  (`EvalSymlinks`), GUI 지원 (X11, Wayland, D-Bus, `/dev/dri`,
  fontconfig 캐시), `--bind-try`를 사용한 앱별 휴리스틱 데이터 맵.

전체 아키텍처 (CAS 내부, manifest 스키마, 샌드박스 마운트, 호스트
계약): [`architecture.md`](../en/architecture.md) ·
[ES](../es/architecture.md)

---

## 보안

> [!WARNING]
> v0.1.0 Alpha에서 `.pbox` 아카이브는 **서명되지 않습니다**. 가져온
> 아카이브는 신뢰할 수 없는 것으로 취급하세요. 서명 검증은
> 로드맵에 있습니다.

이미 구현된 주요 완화책:

- **경로 탐색 방지** — `cas.isValidHash()`는 64개 소문자 16진수를
  강제합니다. `.pbox` 가져오기는 `security.ValidatePath`를 통해 각 tar
  항목을 추출 루트에 대해 검증합니다.
- **심볼릭 링크 안전 가져오기** — `tar.TypeDir`과 `tar.TypeReg`만
  처리하고, 심볼릭 링크, 하드링크, 장치 파일은 조용히 건너뜁니다.
- **환경 정리** — `--clearenv` 후 명시적 화이트리스트로 호스트로부터의
  `LD_PRELOAD` / `LD_LIBRARY_PATH` 주입을 차단합니다.
- **XAUTHORITY 격리** — 호스트의 `~/.Xauthority`는 샌드박스에 바인드
  되기 전에 프로세스별 임시 파일 (`/tmp/packbox-xauth-<pid>`, 모드
  0600)로 복사됩니다.
- **참조 카운팅** — 각 청크는 `.refs` 파일을 가지며, `packbox-gc`는
  참조되지 않은 청크만 삭제합니다.
- **setuid 없음, root 없음** — Packbox는 전적으로 호출 사용자로
  실행됩니다. `sudo`는 설치 프로그램이 배포판 패키지에만 사용합니다.

알려진 제한과 위협 모델:
[`security.md`](../en/security.md) · [ES](../es/security.md)

취약점을 보고할 때는 `packbox-diagnose` 출력을 첨부하세요. 민감한
발견에는 저장소의 비공개 보안 연락처를 사용하세요.

---

## 로드맵

### v0.1.x — 안정화
- [ ] `.pbox` 아카이브의 서명 검증
- [ ] 앱별 네트워크 정책 (현재 `--share-net`은 전역)
- [ ] `packbox-module remove` 및 `info` 구현
- [ ] 실제 GTK4/Qt6 앱에 대한 `host_contract.delegate` 스트레스 테스트
- [ ] CI: 모든 PR에서 `shellcheck`, `gofmt`, `go vet`
- [ ] 테스트 매트릭스: Debian 12, Fedora 40, Arch, openSUSE Tumbleweed

### v0.2 — 도달 범위
- [ ] x86_64 및 aarch64용 사전 빌드 바이너리 (릴리스 페이지)
- [ ] 즉석 버전 업을 위한 `packbox-update`
- [ ] GUI 프런트엔드 (선택, GTK4)
- [ ] `packbox-export`의 청크 수준 델타 다운로드

### 더 나중
- [ ] Flatpak 런타임 임포터 (최선의 노력)
- [ ] minisign 또는 sigstore를 통한 서명 검증
- [ ] 신뢰할 수 없는 플러그인을 위한 WASM 샌드박스 계층

---

## 문서

9개 언어의 전체 문서. 영어와 스페인어는 전체 세트
(README + 명령어 + 아키텍처 + 보안)를, 나머지 7개는 README + 명령어를
가집니다.

| 언어     | README                                 | 명령어                                          | 아키텍처                                            | 보안                                          |
|----------|----------------------------------------|-------------------------------------------------|-----------------------------------------------------|-----------------------------------------------|
| English  | [en](../en/README.md)                  | [en](../en/commands.md)                         | [en](../en/architecture.md)                         | [en](../en/security.md)                       |
| Español  | [es](../es/README.md)                  | [es](../es/commands.md)                         | [es](../es/architecture.md)                         | [es](../es/security.md)                       |
| Français | [fr](../fr/README.md)                  | [fr](../fr/commands.md)                         | —                                                   | —                                             |
| Deutsch  | [de](../de/README.md)                  | [de](../de/commands.md)                         | —                                                   | —                                             |
| Italiano | [it](../it/README.md)                  | [it](../it/commands.md)                         | —                                                   | —                                             |
| 简体中文 | [zh-CN](../zh-CN/README.md)            | [zh-CN](../zh-CN/commands.md)                   | —                                                   | —                                             |
| 繁體中文 | [zh-TW](../zh-TW/README.md)            | [zh-TW](../zh-TW/commands.md)                   | —                                                   | —                                             |
| 日本語   | [ja](../ja/README.md)                  | [ja](../ja/commands.md)                         | —                                                   | —                                             |
| 한국어   | **ko**                                 | [ko](commands.md)                               | —                                                   | —                                             |

색인: [`docs/README.md`](../README.md)

---

## 기여

기여를 환영합니다, 특히:

- **번역** — `install_lang_files()` 내 `en` 블록을 복사하고 모든 `L_*`
  키를 번역하여 `packbox-i18n.sh`에 새 로케일을 추가합니다.
- **샌드박스 프로필** — 브라우저, IDE, 게임용 앱별 데이터 맵.
- **CAS 청킹 전략** — 롤링 해시 변형, 병렬 청킹.
- **버그 보고** — 항상 `packbox-diagnose` 출력을 첨부하세요.

시작하기:

```bash
git clone https://github.com/TU_USUARIO/packbox.git
cd packbox
# CONTRIBUTING.md에서 전체 지침을 읽으세요
```

- 🐛 [이슈 열기](https://github.com/TU_USUARIO/packbox/issues)
- 💬 [토론 시작](https://github.com/TU_USUARIO/packbox/discussions)
- 🔧 [CONTRIBUTING.md](../../CONTRIBUTING.md)

PR을 제출하기 전에 셸 스크립트에는 `shellcheck`를, Go 코드에는
`gofmt` + `go vet`을 실행하세요.

---

## 라이선스

[MIT](../../LICENSE) © 2025 TU_NOMBRE

Packbox는 자유롭게 사용, 수정, 재배포할 수 있습니다. 자세한 내용은
[LICENSE](../../LICENSE)를 참조하세요.

---

## 감사의 글

- **[bubblewrap](https://github.com/containers/bubblewrap)** —
  `packbox-run`을 가능하게 하는 샌드박스 프리미티브.
- **[BLAKE3](https://github.com/BLAKE3-team/BLAKE3)** — 빠르고 안전한
  콘텐츠 주소 지정.
- **[Flatpak](https://flatpak.org/)** — 샌드박스화된 Linux 앱이 대규모로
  작동함을 증명한 프로젝트로, 그 설계 결정은 (우리가 분기하는 곳에서도)
  많은 참고가 되었습니다.
- 9개 언어 i18n 레이어는 Linux 커뮤니티가 글로벌하기 때문에
  존재합니다. 번역을 검토해주신 모든 분께 감사드립니다.
