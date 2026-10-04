# Packbox

**[Español](../../README.md)** · [English](../en/README.md) · [Français](../fr/README.md) · [Deutsch](../de/README.md) · [Italiano](../it/README.md) · [Português](../pt/README.md) · [中文](../zh/README.md) · [日本語](../ja/README.md) · **[한국어](README.md)**

---

![CI](https://github.com/El-Ave-Azul/packbox/actions/workflows/ci.yml/badge.svg)
![라이선스](https://img.shields.io/badge/Licencia-Apache_2.0-blue.svg)
![버전](https://img.shields.io/badge/Versión-0.3.0-orange.svg)
![플랫폼](https://img.shields.io/badge/Plataforma-Linux-blue.svg)
![Go](https://img.shields.io/badge/Go-1.22+-00ADD8.svg?logo=go&logoColor=white)
![i18n](https://img.shields.io/badge/i18n-9_languages-green.svg)
![상태](https://img.shields.io/badge/Estado-Beta-blue.svg)

**청크 단위 바이너리 중복 제거와 Zstd로 압축된 `.pbox` 내보내기를 지원하는 Linux 애플리케이션 패키저.**
Flatpak에서 영감을 받았지만 재사용 모델은 다릅니다. 앱마다 모놀리식 런타임을
두는 대신, Packbox는 콘텐츠 주소 지정 저장소(BLAKE3 CAS)에 콘텐츠를
보관하며, 최적화된 **콘텐츠 정의 청킹(CDC)** 과 재사용 가능한 **셀** 을 사용합니다.
라이브러리의 90 %를 공유하는 두 앱은 서로 다른 10 %만 저장합니다.

> [!IMPORTANT]
> **베타 상태 (v0.3.0).** 코어 안정성이 향상되었으며, LRU 가비지 컬렉션, 내보내기 시의 Zstd 압축이 구현되었습니다.

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

Packbox는 **BLAKE3** 해싱과 최적화된 **콘텐츠 기반 청킹** 을 사용하는 **Content-Addressable Storage (CAS)** 로 Linux 애플리케이션을 패키징하여, 앱 간에 실제 바이너리 중복 제거를 달성합니다.

애플리케이션당 ~1 GB의 런타임(Flatpak)을 두는 대신, Packbox는 각 파일을 청크(내용 기준으로 중복 제거)로 저장하고 모든 앱 간에 공유합니다. **Zstd** 압축은 `.pbox` 를 내보낼 때 적용됩니다. 또한 각 라이브러리를 여러 앱이 공유하는 **셀**(버전이 지정된 재사용 단위)로 변환하고, 범용 라이브러리(`libc`, `libm`, …)는 호스트에 남겨둡니다.

### 설계 원칙

- **청크 수준 중복 제거.** 같은 바이트 = 같은 해시 = 한 번만 저장(ELF 바이너리에 최적화된 CDC; 작은 파일은 단일 청크로 저장).
- **원본 저장, 압축 내보내기.** CAS는 청크를 압축하지 않고 유지하여 설치 시 **하드링크**할 수 있게 합니다(디스크 상의 실제 중복 제거). **Zstd** 압축은 `.pbox` 를 빌드할 때 적용됩니다.
- **셀 (원자적 조각화).** 범용이 아닌 각 라이브러리는 하나의 셀이며,
  앱이 이를 선언하고 설치 프로그램이 해석합니다.
- **교차 공유.** 모든 앱이 동일한 전역 CAS와 동일한 셀을 공유합니다.
- **Host contract v1.** 범용 라이브러리의 선택적 위임과 필수 심볼에 대한
  **ABI 검사**.
- **강화된 샌드박스 (bubblewrap).** `--unshare-all`, `--cap-drop ALL`,
  **seccomp**, **필터링된 D-Bus**(`xdg-dbus-proxy`), **앱별 전용 HOME**,
  세분화된 네트워크 정책 (none/limited/full) 및 **자동 감지가 포함된 옵트인 X11**.
- **오버레이 기반 레이어.** `/app`은 A(앱)를 C(셀) 위에 올린 오버레이로
  구성되며, S(호스트)는 `/usr`를 통해 제공됩니다.
- **서명 및 배포.** 서명 가능한 `.pbox`(ed25519)와 병렬 델타 다운로드를 지원하는
  HTTP 원격 저장소.
- **4가지 패키징 모드.** Normal, Portable, Bundle, Module.

---

## Flatpak과의 비교

| 항목                 | Flatpak (현재)              | Packbox v0.3.0                       |
|----------------------|-----------------------------|--------------------------------------|
| 재사용 단위          | 전체 런타임 (~1 GB)         | 라이브러리별 **셀** (런타임 없음)    |
| 중복 제거            | 파일 수준 (OSTree)          | **청크** 수준 (BLAKE3 + CDC)         |
| 저장소               | 런타임별 압축               | **원본 청크 + 하드링크** (중복 제거)  |
| 라이브러리 공유      | 동일 런타임 내              | 모든 앱 간 교차 공유                 |
| 호스트 라이브러리 사용 | 없음                      | 선택적 (host contract + ABI)         |
| 업데이트             | OSTree 객체 델타             | `packbox-update` (델타 + LRU GC)    |
| 배포                 | Flathub + OSTree remotes    | 병렬 HTTP 원격 저장소              |
| 서명                 | GPG                         | ed25519 (`.pbox.sig`)                |
| 샌드박스             | bwrap + seccomp + 포털      | bwrap + seccomp + dbus-proxy + 포털  |
| 인터페이스           | GNOME Software / CLI        | **TUI** + CLI                          |
| 앱당 오버헤드        | 런타임이 다르면 ~100 %      | 공유 앱 기준 **~5–15 %**             |

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

---

## 빠른 시작

### 1. 대화형 패키저 (TUI)

```bash
./packbox-packager.sh
```

옵션 **1 (패키징)** 은 **이미 설치된** 앱을 검색하고
`~/.local/share/packbox/exports/` 에 `.pbox` 를 **생성**합니다. 완료 후, 이를
**이 머신에 설치**할지 묻습니다(기본값은 **아니오**이며, 시스템을 더럽히지 않기 위함입니다). `.pbox` 를 설치하려면 옵션 **5 (가져오기)** 를 사용하십시오.

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

---

## 사용 가능한 명령어

Packbox v0.3.0은 `~/.packbox/bin/`에 **15개의 Go 바이너리** 를 포함합니다:

| 명령어             | 용도                                                          |
|--------------------|--------------------------------------------------------------------|
| `packbox-pack`     | 디렉터리를 CAS 청크로 해싱하고 `manifest.json`을 생성        |
| `packbox-install`  | 매니페스트에서 앱 설치 (+ `--desktop`/`--remove-desktop`) |
| `packbox-run`      | `bwrap` 샌드박스에서 앱 실행 (A/C 오버레이, 전용 HOME)   |
| `packbox-list`     | **실제 크기** 와 공유로 인한 절감과 함께 앱 나열 (`--tsv`)   |
| `packbox-remove`   | 앱을 제거하고 해당 CAS 참조를 해제 (`--all` = 모두, `--dry-run`) |
| `packbox-gc`       | 참조되지 않는 청크 **및 셀** 을 수집 (LRU 지원)                      |
| `packbox-verify`   | 해석 가능한 라이브러리 + 호스트의 **ABI 호환성** 확인        |
| `packbox-export`   | **적응형 압축** 과 선택적 `--sign`으로 `.pbox`로 내보내기 |
| `packbox-import`   | `.pbox` 가져오기 (tar-slip, traversal 및 서명 방지)             |
| `packbox-update`   | 청크를 재사용하여 앱 업데이트 + 델타 보고서 (`--no-gc`)   |
| `packbox-module`   | 모듈/셀: `list`, `create`, `cell <lib>...`                  |
| `packbox-sign`     | ed25519 키 및 서명: `keygen`, `sign`, `verify`, `trust`       |
| `packbox-fetch`    | 병렬 HTTP 원격: `publish <id> <dir>` 및 `fetch <id> --from <url>`      |
| `packbox-debug`    | 설치된 앱의 디버그 심볼(별도 셀)을 연결  |
| `packbox-diagnose` | 버그 보고용 환경 보고서                          |

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

- **CAS + 청커** — 원본 청크(재압축하지 않아 하드링크할 수 있음)를 **BLAKE3** 해시별로 저장합니다. 큰 파일은 **최적화된 CDC** 로 분할되고, 작은 파일은 단일 청크로 저장됩니다. 쓰기는 **원자적**입니다.
- **매니페스트** (`schema_version: \"1.7\"`) — 경로를 청크에 매핑하고, 네트워크 정책 (`none`, `limited`, `full`), host contract 및 X11 심볼을 정의합니다.
- **셀** — 라이브러리 하나 = `mods/` 내의 `org.lib.<soname>@<hash>` 셀 하나. 앱 간에 공유됩니다. `packbox-gc` 는 참조되지 않았거나 오래된 셀 (LRU) 을 삭제합니다.
- **샌드박스** — `bwrap --unshare-all --cap-drop ALL --clearenv`, **seccomp**, `xdg-dbus-proxy`를 사용한 **필터링된 D-Bus**, **전용 HOME**, 세분화된 네트워크 및 **멀티미디어 지원** (PipeWire/PulseAudio).
- **오버레이 기반 레이어** — `/app`은 `--overlay-src` (C가 아래, A가 위)로 구성되며, S (호스트)는 `/usr`를 통해 제공됩니다.
- **Host contract** — `packbox-verify` 가 호스트가 요구된 심볼 (ABI) 을 제공하는지 확인합니다.
- **서명 및 원격** — `packbox-sign` (ed25519) 이 `.pbox` 에 서명하고, `packbox-fetch` 가 **병렬 다운로드**를 통해 델타를 게시하고 다운로드합니다.

---

## 보안

### 구현된 완화책

- **앱별 데이터 격리** — 각 앱은 **전용 HOME** 으로 실행되며, 폰트/테마만 **읽기 전용** 으로 노출됩니다.
- **필터링된 D-Bus** — `xdg-dbus-proxy` 와 화이트리스트 (포털 + `dconf`).
- **seccomp** — 위험한 커널 표면을 차단하는 기본 필터.
- **세분화된 네트워크** — 내부 프록시를 통해 로컬 네트워크 액세스 (RFC 1918) 를 차단하는 `limited` 모드를 지원합니다.
- **안전한 멀티미디어 지원** — 포털을 통해 오디오 및 카메라에 대한 중재된 액세스를 제공합니다.
- **Anti tar-slip / traversal** — `.pbox` 내의 엄격한 경로 검증.
- **환경 정리** — `--clearenv` + 명시적 화이트리스트.
- **Reference counting + LRU GC** — 액세스 시간 기반의 지능형 청크 정리.
- **서명** — `.pbox` 는 **ed25519** 로 서명 가능합니다.

---

## 로드맵

### v0.1.x — 안정화
- [x] `.pbox` 서명 검증
- [x] 강화된 샌드박스: 전용 HOME, 필터링된 D-Bus, seccomp
- [x] 자동 셀 + 레이어 오버레이 (A/C/S)
- [x] 청크 델타 + 자동 GC를 사용하는 `packbox-update`
- [x] 병렬 델타 다운로드를 지원하는 HTTP 원격 저장소
- [x] `.pbox` 내보내기의 Zstd 압축
- [x] ELF 바이너리용 CDC 튜닝
- [x] LRU 가비지 컬렉션

### v0.2 — 범위
- [ ] GTK4 GUI 프런트엔드 (보류)
- [ ] 사전 컴파일된 x86_64 및 aarch64 바이너리
- [ ] 서명된 중앙 인덱스/저장소

### 향후
- [ ] Flatpak 런타임 임포터 (best-effort)
- [ ] 신뢰할 수 없는 플러그인용 WASM 샌드박스

---

## 라이선스

**Apache License 2.0** 에 따라 배포됩니다. [LICENSE](../../LICENSE)를 참조하십시오.
