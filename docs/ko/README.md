# Packbox

[Español](../../README.md) · [English](../en/README.md) · [Français](../fr/README.md) · [Deutsch](../de/README.md) · [Italiano](../it/README.md) · [Português](../pt/README.md) · [中文](../zh/README.md) · [日本語](../ja/README.md) · **[한국어](README.md)**

---

![Licencia](https://img.shields.io/badge/Licencia-Apache_2.0-blue.svg)
![Versión](https://img.shields.io/badge/Versión-0.1.1-orange.svg)
![Plataforma](https://img.shields.io/badge/Plataforma-Linux-blue.svg)
![Go](https://img.shields.io/badge/Go-1.22+-00ADD8.svg?logo=go&logoColor=white)
![i18n](https://img.shields.io/badge/i18n-9_idiomas-green.svg)
![Estado](https://img.shields.io/badge/Estado-Alpha-red.svg)

**청크 단위 바이너리 중복 제거를 지원하는 Linux 애플리케이션 패키저.**
Flatpak에서 영감을 받았지만 재사용 모델은 다릅니다. 앱마다 모놀리식 런타임을
두는 대신, Packbox는 콘텐츠 주소 지정 저장소(BLAKE3 CAS)에 콘텐츠를
보관하며, **콘텐츠 정의 청킹(CDC)** 과 재사용 가능한 **셀** 을 사용합니다.
라이브러리의 90 %를 공유하는 두 앱은 서로 다른 10 %만 저장합니다.

> [!WARNING]
> **Alpha 상태 (v0.1.1).** 주요 흐름은 동작하며 서명, 강화된 샌드박스(seccomp, 필터링된 D-Bus, 전용 HOME), HTTP 원격 저장소도 이미 갖추고 있습니다. 그러나 이 프로젝트는 아직 신생이라 Flatpak 수준의 생태계나 성숙도를 갖추지 못했습니다. 먼저 중요하지 않은 시스템에서 사용하십시오.

---

## 목차

- [Packbox란?](#packbox란)
- [Flatpak과의 비교](#flatpak과의-비교)
- [요구 사항](#요구-사항)
- [설치](#설치)
- [빠른 시작](#빠른-시작)
- [사용 가능한 명령어](#사용-가능한-명령어)
- [파일 구조](#파일-구조)
- [아키텍처](#아키텍처)
- [보안](#보안)
- [로드맵](#로드맵)
- [기여](#기여)
- [라이선스](#라이선스)
- [감사의 글](#감사의-글)

---

## Packbox란?

Packbox는 **BLAKE3** 해싱과 **콘텐츠 기반 청킹** 을 사용하는 **Content-Addressable Storage (CAS)** 로 Linux 애플리케이션을 패키징하여, 앱 간에 실제 바이너리 중복 제거를 달성합니다.

애플리케이션당 ~1 GB의 런타임(Flatpak)을 두는 대신, Packbox는 각 파일을 콘텐츠 주소 지정 청크로 저장하고 모든 앱 간에 공유합니다. 또한 각 라이브러리를 여러 앱이 공유하는 **셀**(버전이 지정된 재사용 단위)로 변환하고, 범용 라이브러리(`libc`, `libm`, …)는 호스트에 남겨둡니다.

### 설계 원칙

- **청크 수준 중복 제거.** 같은 바이트 = 같은 해시 = 한 번만 저장(큰 파일은
  CDC, 작은 파일은 단일 파일로 저장하여 하드링크 공유 가능).
- **셀 (원자적 조각화).** 범용이 아닌 각 라이브러리는 하나의 셀이며,
  앱이 이를 선언하고 설치 프로그램이 해석합니다.
- **교차 공유.** 모든 앱이 동일한 전역 CAS와 동일한 셀을 공유합니다.
- **Host contract v1.** 범용 라이브러리의 선택적 위임과 필수 심볼에 대한
  **ABI 검사**.
- **강화된 샌드박스 (bubblewrap).** `--unshare-all`, `--cap-drop ALL`,
  **seccomp**, **필터링된 D-Bus**(`xdg-dbus-proxy`), **앱별 전용 HOME**,
  옵트인 네트워크, **자동 감지가 포함된 옵트인 X11**.
- **오버레이 기반 레이어.** `/app`은 A(앱)를 C(셀) 위에 올린 오버레이로
  구성되며, S(호스트)는 `/usr`를 통해 제공됩니다.
- **서명 및 배포.** 서명 가능한 `.pbox`(ed25519)와 델타 다운로드를 지원하는
  HTTP 원격 저장소.
- **4가지 패키징 모드.** Normal, Portable, Bundle, Module.

---

## Flatpak과의 비교

| 항목                 | Flatpak (현재)              | Packbox v0.1.1                       |
|----------------------|-----------------------------|--------------------------------------|
| 재사용 단위          | 전체 런타임 (~1 GB)         | 라이브러리별 **셀** (런타임 없음)    |
| 중복 제거            | 파일 수준 (OSTree)          | **청크** 수준 (BLAKE3 + CDC)         |
| 라이브러리 공유      | 동일 런타임 내              | 모든 앱 간 교차 공유                 |
| 호스트 라이브러리 사용 | 없음                      | 선택적 (host contract + ABI)         |
| 업데이트             | OSTree 객체 델타             | `packbox-update` (청크 델타 + GC)    |
| 배포                 | Flathub + OSTree remotes    | `publish`/`fetch`를 사용한 HTTP 원격 |
| 서명                 | GPG                         | ed25519 (`.pbox.sig`)                |
| 샌드박스             | bwrap + seccomp + 포털      | bwrap + seccomp + dbus-proxy + 포털  |
| 앱당 오버헤드        | 런타임이 다르면 ~100 %      | 공유 앱 기준 **~5–15 %**             |

**측정된 절감 효과** (이 코드베이스 기준): 스택을 공유하는 중간 규모 GTK4 앱 두 개는 각각 합치면 ~264 MB이지만 실제로는 **~141 MB (−46 %)** 를 차지합니다. 10개의 혼합 앱에서는 절감 효과가 **~69 %** 로 올라갑니다. 라이브러리 중복이 클수록 절감 효과도 커지지만, 공유 런타임의 90–99 %를 가정하지 말고 사례별로 측정하는 것이 좋습니다.

---

## 요구 사항

- **운영 체제**: Linux (Debian 12+, Ubuntu 22.04+, Fedora 40+, Arch,
  openSUSE Tumbleweed)
- **커널**: user namespaces가 활성화된 5.15+
- **셸**: Bash 4.0+
- **Go**: 1.22+ (설치 프로그램이 없으면 자체 사본을 내려받습니다)
- **공간**: 최초 컴파일을 위한 ~500 MB 여유
- **인터넷**: 최초 설치 시에만 필요

### 시스템 의존성

가능한 경우 설치 프로그램이 설치하며, 수동으로도 유용합니다:

`bubblewrap` · `binutils` (`ldd`/`readelf`) · `jq` · `bc` · `curl` · `tar` ·
`xdg-dbus-proxy` (D-Bus 필터링) · `zstd` 또는 `xz` (더 압축된 export)

---

## 설치

### 1단계 — 복제 및 실행

```bash
git clone https://github.com/El-Ave-Azul/packbox.git
cd packbox
./packbox-install.sh
```

설치 프로그램이 메뉴를 엽니다. **1**번 옵션(설치)을 선택하십시오.

### 2단계 — 셸 다시 로드

```bash
source ~/.bashrc
```

### 3단계 — 확인

```bash
packbox-diagnose
```

### 설치 프로그램이 하는 일

1. 9개 언어 중 하나를 선택할 수 있게 합니다.
2. Linux 배포판과 패키지 관리자를 감지합니다.
3. 의존성을 설치하기 전에 확인을 요청합니다.
4. 필요한 경우 `~/.packbox/go`에 Go(기본값 1.27.1)를 내려받고 검증합니다.
5. 디렉터리 구조(`~/.packbox/` 및 `~/.local/share/packbox/`)를 만듭니다.
6. 소스를 복사하고 **15개의 바이너리** 를 컴파일합니다 (~1–2분).
7. `~/.bashrc`에 `PATH`를 설정하고 `~/.local/bin`에 심볼릭 링크를 만듭니다.
8. 언어 파일을 `~/.config/packbox/lang/`에 설치합니다.
9. 모든 바이너리가 존재하고 동작하는지 확인합니다.

### 제거

같은 스크립트를 실행하고 **2**번 옵션을 선택하십시오:

```bash
./packbox-install.sh --uninstall
```

| 모드 | 설명 |
|------|-------------|
| `s`  | 전체: 바이너리 + 앱 + CAS 저장소 + 셀 + 메뉴 + 아이콘 + 설정 |
| `k`  | 바이너리만: `~/.packbox/` 및 심볼릭 링크 (앱과 CAS 저장소는 보존) |
| `q`  | 취소 |

---

## 빠른 시작

### 1. 대화형 패키저 (권장)

```bash
./packbox-packager.sh
```

메뉴: 패키징, 목록, garbage collection, 내보내기, 가져오기, 제거,
언어. `/usr/share/applications/`의 `.desktop`에서 앱을, `/opt/*`의 번들을,
그리고 일반적인 바이너리(`htop`, `btop`, `firefox`, `gimp`, …)를 감지합니다.

**Normal** 및 **Portable** 모드에서는 `ldd` 클로저의 범용이 아닌 각 라이브러리가 자동으로 **셀** 로 변환됩니다.

### 2. 명령줄

```bash
# 디렉터리 패키징
packbox-pack ./mi-app --name org.ejemplo.miapp --version 1.0.0

# 생성된 매니페스트에서 설치
packbox-install ./mi-app/manifest.json

# 샌드박스에서 실행 (A를 C 위에 오버레이; 전용 HOME)
packbox-run org.ejemplo.miapp

# 앱 목록 (실제 크기와 공유로 인한 절감) 및 공간 확보
packbox-list
packbox-remove org.ejemplo.miapp
packbox-gc

# 저장소의 청크를 재사용하여 설치된 앱 업데이트
packbox-update org.ejemplo.miapp ./nuevo/manifest.json
```

### 3. 내보내기, 서명, 가져오기 및 배포

```bash
# 내보내기 및 서명
packbox-sign keygen                       # 키 생성 (및 신뢰)
packbox-export --sign app org.ejemplo.miapp
packbox-sign verify ~/.local/share/packbox/exports/org.ejemplo.miapp.pbox

# HTTP 원격 저장소 게시 및 다른 머신에서 사용
packbox-fetch publish org.ejemplo.miapp /srv/packbox
(cd /srv/packbox && python3 -m http.server 8000)
packbox-fetch fetch org.ejemplo.miapp --from http://host:8000

# 가져오기 (서명이 있으면 검증)
packbox-import app org.ejemplo.miapp.pbox
```

---

## 사용 가능한 명령어

Packbox v0.1.1은 `~/.packbox/bin/`에 **15개의 Go 바이너리** 를 포함합니다:

| 명령어             | 용도                                                          |
|--------------------|--------------------------------------------------------------------|
| `packbox-pack`     | 디렉터리를 CAS 청크로 해싱하고 `manifest.json`을 생성        |
| `packbox-install`  | 매니페스트에서 앱 설치 (+ `--desktop`/`--remove-desktop`) |
| `packbox-run`      | `bwrap` 샌드박스에서 앱 실행 (A/C 오버레이, 전용 HOME)   |
| `packbox-list`     | **실제 크기** 와 공유로 인한 절감과 함께 앱 나열 (`--tsv`)   |
| `packbox-remove`   | 앱을 제거하고 해당 CAS 참조를 해제                    |
| `packbox-gc`       | 참조되지 않는 청크 **및 셀** 을 수집                      |
| `packbox-verify`   | 해석 가능한 라이브러리 + 호스트의 **ABI 호환성** 확인        |
| `packbox-export`   | **적응형 압축** 과 선택적 `--sign`으로 `.pbox`로 내보내기 |
| `packbox-import`   | `.pbox` 가져오기 (tar-slip, traversal 및 서명 방지)             |
| `packbox-update`   | 청크를 재사용하여 앱 업데이트 + 델타 보고서 (`--no-gc`)   |
| `packbox-module`   | 모듈/셀: `list`, `create`, `cell <lib>...`                  |
| `packbox-sign`     | ed25519 키 및 서명: `keygen`, `sign`, `verify`, `trust`       |
| `packbox-fetch`    | HTTP 원격: `publish <id> <dir>` 및 `fetch <id> --from <url>`      |
| `packbox-debug`    | 설치된 앱의 디버그 심볼(별도 셀)을 연결  |
| `packbox-diagnose` | 버그 보고용 환경 보고서                          |

---

## 파일 구조

```
~/.packbox/                              # 설치
├── bin/                                 # 컴파일된 15개의 Go 바이너리
└── src/                                 # Go 소스 코드

~/.local/share/packbox/                  # 사용자 데이터
├── store/                               # CAS: BLAKE3 해시별 청크
│   └── <ab>/<hash-completo>             # + 청크별 .refs 파일
├── apps/                                # 설치된 앱
│   └── <app-id>/
│       ├── manifest.json
│       ├── tree/                        # CAS에 대한 하드링크 (레이어 A)
│       └── home/                        # 전용 HOME (첫 실행 시 생성)
├── mods/                                # 셀 (org.lib.*, org.debug.*)
├── exports/                             # .pbox 파일 (+ .sig)
└── tmp/                                 # 임시 파일

~/.config/packbox/
├── lang/                                # 9개의 언어 파일
├── signing.key / signing.pub            # 서명 키
└── trusted/                             # 신뢰하는 공개 키
```

---

## 아키텍처

### 패키징 흐름

```
┌──────────────┐   pack    ┌──────────────┐  install  ┌──────────────┐
│  소스 디렉터리  │ ────────► │     CAS      │ ─────────► │  앱 트리 │
│  (fs 트리)  │           │  (chunks)    │           │ (hardlinks)  │
└──────────────┘           └──────────────┘           └──────┬───────┘
                                  │                          │ + 셀 (레이어 C)
                                  │ run                      ▼
                         ┌──────────────────────────────────────────┐
                         │  bwrap 샌드박스: /app = A를 C 위에 오버레이  │
                         │  전용 HOME · seccomp · 필터링된 D-Bus  │
                         └──────────────────────────────────────────┘
```

### 내부 구성 요소

- **CAS + chunker** — **BLAKE3** 해시별로 청크를 저장합니다. 큰 파일은
  **CDC**(기어형 롤링 해시)로 분할하고, 작은 파일은 단일 청크로
  저장합니다(공유를 위해 하드링크 가능). **원자적** 쓰기(temp+rename).
- **매니페스트** (`schema_version: "1.6"`) — 경로를 청크에 매핑하고,
  **셀**(`mods`), `host_contract`(delegate + required_symbols), X11
  심볼, 그리고 해당되는 경우 **debug** 셀을 나열합니다.
- **셀** — 라이브러리 하나 = `mods/`의 `org.lib.<soname>@<hash>` 셀 하나.
  앱 간에 공유됩니다. `packbox-gc`가 참조되지 않은 셀을 삭제합니다.
- **샌드박스** — `bwrap --unshare-all --cap-drop ALL --clearenv`, **seccomp**
  (ptrace/bpf/keyring/io_uring/모듈 차단…), `xdg-dbus-proxy`를 사용한
  **필터링된 D-Bus**(포털 + dconf), **전용 HOME**(`apps/<id>/home`),
  **옵트인** 네트워크, **옵트인 X11**(기본적으로 Wayland + 포털이며,
  매니페스트가 요구하거나 세션이 X11 전용일 때만 활성화됨).
- **레이어 오버레이** — `/app`은 `--overlay-src`(C가 아래, A가
  위)로 구성되며, S(호스트)는 `/usr`를 통해 제공됩니다. 각 트리에 셀을 복사하는 것을 피합니다.
- **Host contract** — `packbox-verify`가 호스트가 요구된 심볼(ABI)을
  제공하는지 확인합니다.
- **서명 및 원격** — `packbox-sign`(ed25519)이 `.pbox`에 서명하고,
  `packbox-fetch`가 델타(청크 + 셀)만 게시하고 내려받습니다.

### 중복 제거의 작동 방식

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

## 보안

### 구현된 완화책

- **앱별 데이터 격리** — 각 앱은 **전용 HOME**(`apps/<id>/home`)으로
  실행되며, 폰트/테마는 **읽기 전용** 으로만 노출됩니다. 실제 설정을
  보거나 건드리지 않습니다.
- **필터링된 D-Bus** — 허용 목록이 있는 `xdg-dbus-proxy`(기본적으로 포털과
  `dconf`, 시스템 버스에는 아무것도 허용하지 않음). 앱은 실제 버스와
  통신하지 않습니다.
- **seccomp** — 위험한 커널 표면(ptrace, bpf, keyring, io_uring,
  userfaultfd, 모듈, reboot/swap…)을 차단하는 기본 필터.
- **옵트인 X11** — 기본적으로 Wayland + `xdg-desktop-portal`(포털의
  문서 마운트를 노출). X11은 매니페스트의 `x11` 플래그로 활성화하거나
  호스트 세션이 X11 전용이면 자동으로 활성화됩니다.
- **Anti tar-slip / traversal** — `.pbox` 추출 시 각 항목을 검증
  (`safeJoin` + `O_NOFOLLOW` + 심볼릭 링크 대상)하고 앱 디렉터리를
  벗어나는 `name`/경로를 거부합니다.
- **환경 정리** — `--clearenv` + 명시적 허용 목록: 호스트에서 주입된
  `LD_PRELOAD`/`LD_LIBRARY_PATH`를 차단합니다.
- **setuid 없음, root 없음** — 모든 것이 사용자 권한으로 실행되며,
  `sudo`는 설치 시 시스템 의존성에만 사용됩니다.
- **Reference counting + GC** — 각 청크에는 `.refs`가 있으며,
  `packbox-gc`는 참조되지 않은 것(청크 **및 셀**)만 삭제합니다.
- **서명** — **ed25519** 로 서명 가능한 `.pbox`이며, `import`는 변조되었거나
  신뢰할 수 없는 서명자의 패키지를 검증하고 **거부** 합니다.
- **CAS 무결성** — 해시는 경로로 사용되기 전에 검증되며,
  쓰기는 원자적입니다.

### 알려진 한계 (v0.1.1 Alpha)

> [!WARNING]
> 가장 피드백을 환영하는 영역입니다.

- ⚠️ **부분적 포털.** 포털과 통신하는 것은 허용되고 문서 마운트가
  노출되지만, 아직 모든 것(카메라, 클립보드 등)에 포털을 사용하지는
  않습니다.
- ⚠️ **`packbox-module remove`/`info`** 는 아직 구현되지 않았습니다
  (`cell`은 존재합니다).
- ⚠️ **적응형 압축** 은 항목별이 아니라 패키지 수준입니다(형식은
  tar + 압축기).
- ⚠️ **카탈로그 없음.** HTTP 원격 저장소는 데이터를 제공할 뿐 신뢰나
  공개 색인을 제공하지 않습니다.

---

## 로드맵

### v0.1.x — 안정화

- [x] `.pbox` 서명 검증 (ed25519 + 키 관리)
- [x] 강화된 샌드박스: 전용 HOME, 필터링된 D-Bus, seccomp
- [x] 자동 셀 + 레이어 오버레이 (A/C/S)
- [x] 청크 델타 + 자동 GC를 사용하는 `packbox-update`
- [x] 델타 다운로드를 지원하는 HTTP 원격 저장소 (`publish`/`fetch`)
- [x] 별도 디버그 심볼 (`cell-debug`)
- [x] `export`의 적응형 압축
- [x] 엔드투엔드 통합 테스트 (`tests/integration.sh`)
- [ ] 애플리케이션별 네트워크 정책
- [ ] 완전한 포털 (파일, 카메라, 클립보드)
- [ ] CI/CD: 모든 PR에서 `shellcheck`, `gofmt`, `go vet`
- [ ] 테스트 매트릭스: Debian 12, Fedora 40, Arch, openSUSE Tumbleweed

### v0.2 — 범위

- [ ] 사전 컴파일된 x86_64 및 aarch64 바이너리 (releases 페이지)
- [ ] 서명된 중앙 인덱스/저장소 (원격에서의 `search`/`install`)
- [ ] 선택적 GUI 프런트엔드 (GTK4)

### 향후

- [ ] Flatpak 런타임 임포터 (best-effort)
- [ ] 신뢰할 수 없는 플러그인을 위한 WASM 샌드박스

---

## 기여

기여를 환영합니다! 특히 도움이 되는 영역:

- **번역** — `i18n/`의 기존 블록을 복사하여 각 `L_*` 키를 번역해
  로케일을 추가하십시오.
- **포털** — 파일 접근을 위해 `xdg-desktop-portal`을 통합하십시오.
- **청킹 / dedup** — CDC와 임계값 정책을 개선하십시오.
- **버그 보고** — 항상 `packbox-diagnose`의 출력을 포함하십시오.

### 시작하는 방법

```bash
git clone https://github.com/El-Ave-Azul/packbox.git
cd packbox
cd src && go test ./...     # unit tests
bash tests/integration.sh   # end-to-end (pack → export → import → run)
```

- 🐛 [이슈 열기](https://github.com/El-Ave-Azul/packbox/issues)
- 💬 [토론 시작](https://github.com/El-Ave-Azul/packbox/discussions)

> [!TIP]
> PR을 보내기 전에 bash 스크립트에는 `shellcheck`를, Go에는 `gofmt` + `go vet`을 실행하십시오.

---

## 라이선스

**Apache License 2.0** 에 따라 배포됩니다. [LICENSE](../../LICENSE)를 참조하십시오.

Apache 2.0은 **명시적 특허 허여 조항** 을 제공하여 사용자와 기여자를 중복 제거 및 샌드박싱 기술에 대한 소송으로부터 보호하며, GPLv3와 호환됩니다.

---

## 감사의 글

- **[bubblewrap](https://github.com/containers/bubblewrap)** — `packbox-run`을
  가능하게 하는 Linux 샌드박스 기본 요소.
- **[BLAKE3](https://github.com/BLAKE3-team/BLAKE3)** — 빠르고
  암호학적으로 안전한 콘텐츠 해싱.
- **[xdg-desktop-portal](https://flatpak.github.io/xdg-desktop-portal/)** 및
  **xdg-dbus-proxy** — 중재된 파일 접근과 D-Bus 필터링.
- **[Flatpak](https://flatpak.org/)** — 샌드박스된 Linux 앱이 대규모로
  동작함을 입증했습니다. 우리가 다른 방향을 택한 곳에서도 Flatpak의 많은
  결정이 우리에게 영감을 주었습니다.
- **전 세계 Linux 커뮤니티** — 9개 언어 i18n 레이어는 여러분의 검토와
  기여 덕분에 존재합니다.
