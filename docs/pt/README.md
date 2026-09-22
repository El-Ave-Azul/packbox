# Packbox

[Español](../../README.md) · [English](../en/README.md) · [Français](../fr/README.md) · [Deutsch](../de/README.md) · [Italiano](../it/README.md) · **[Português](README.md)** · [中文](../zh/README.md) · [日本語](../ja/README.md) · [한국어](../ko/README.md)

---

![Licença](https://img.shields.io/badge/Licencia-Apache_2.0-blue.svg)
![Versão](https://img.shields.io/badge/Versión-0.2.0-orange.svg)
![Plataforma](https://img.shields.io/badge/Plataforma-Linux-blue.svg)
![Go](https://img.shields.io/badge/Go-1.22+-00ADD8.svg?logo=go&logoColor=white)
![i18n](https://img.shields.io/badge/i18n-9_idiomas-green.svg)
![Estado](https://img.shields.io/badge/Estado-Alpha-red.svg)

**Empacotador de aplicativos Linux com deduplicação binária por chunk.**
Inspirado no Flatpak, mas com um modelo de reuso diferente: em vez de um
runtime monolítico por app, o Packbox guarda o conteúdo em um armazém
endereçado por conteúdo (BLAKE3 CAS), com **chunking definido por conteúdo
(CDC)** e **células** reutilizáveis. Dois apps que compartilham 90 % de suas
bibliotecas armazenam apenas os 10 % que diferem.

> [!WARNING]
> **Estado Alpha (v0.2.0).** Os fluxos principais funcionam e já existem
> assinaturas, sandbox reforçado (seccomp, D-Bus filtrado, HOME privado) e
> remoto HTTP, mas o projeto é jovem e não tem o ecossistema nem a maturidade
> do Flatpak. Use-o primeiro em sistemas não críticos.

---

## Índice

- [O que é o Packbox?](#o-que-é-o-packbox)
- [Comparação com o Flatpak](#comparação-com-o-flatpak)
- [Requisitos](#requisitos)
- [Instalação](#instalação)
- [Uso rápido](#uso-rápido)
- [Comandos disponíveis](#comandos-disponíveis)
- [Estrutura de arquivos](#estrutura-de-arquivos)
- [Arquitetura](#arquitetura)
- [Segurança](#segurança)
- [Roteiro](#roteiro)
- [Contribuir](#contribuir)
- [Licença](#licença)
- [Agradecimentos](#agradecimentos)

---

## O que é o Packbox?

O Packbox empacota aplicativos Linux usando **Content-Addressable Storage (CAS)**
com hashing **BLAKE3** e **chunking por conteúdo**, para obter deduplicação
binária real entre apps.

Em vez de um runtime de ~1 GB por aplicação (Flatpak), o Packbox guarda cada
arquivo como chunks endereçados por conteúdo e o compartilha entre todos os
apps. Além disso, converte cada biblioteca em uma **célula** (uma unidade de
reuso versionada) que vários apps compartilham, e deixa as bibliotecas
universais (`libc`, `libm`, …) para o host.

### Princípios de design

- **Deduplicação em nível de chunk.** Mesmos bytes = mesmo hash = armazenado uma
  vez (CDC em arquivos grandes; arquivo único nos pequenos, para poder
  fazer hardlink e compartilhar).
- **Células (fragmentação atômica).** Cada lib não universal é uma célula;
  o app a declara e o instalador a resolve.
- **Compartilhamento cruzado.** Todos os apps compartilham o mesmo CAS global e as
  mesmas células.
- **Host contract v1.** Delegação seletiva de bibliotecas universais, com
  **verificação ABI** dos símbolos requeridos.
- **Sandbox reforçado (bubblewrap).** `--unshare-all`, `--cap-drop ALL`,
  **seccomp**, **D-Bus filtrado** (`xdg-dbus-proxy`), **HOME privado por app**,
  rede opt-in e **X11 opt-in com autodetecção**.
- **Camada por overlay.** `/app` é composto como overlay de A (app) sobre C
  (células), com S (host) via `/usr`.
- **Assinaturas e distribuição.** `.pbox` assináveis (ed25519) e remoto HTTP com
  download delta.
- **4 modos de empacotamento.** Normal, Portable, Bundle, Module.

---

## Comparação com o Flatpak

| Característica        | Flatpak (atual)             | Packbox v0.2.0                       |
|----------------------|-----------------------------|--------------------------------------|
| Unidade de reuso      | Runtime completo (~1 GB)    | **Células** por lib (sem runtimes)   |
| Deduplicação          | Em nível de arquivo (OSTree) | Em nível de **chunk** (BLAKE3 + CDC) |
| Compartilhamento de libs | Dentro do mesmo runtime  | Cruzado entre todos os apps          |
| Uso de libs do host   | Nenhum                      | Seletivo (host contract + ABI)       |
| Atualizações          | Delta de objetos OSTree     | `packbox-update` (delta de chunks + GC) |
| Distribuição          | Flathub + remotes OSTree    | Remoto HTTP com `publish`/`fetch`    |
| Assinaturas           | GPG                         | ed25519 (`.pbox.sig`)                |
| Sandbox               | bwrap + seccomp + portais   | bwrap + seccomp + dbus-proxy + portais |
| Overhead por app      | ~100 % se runtime distinto  | **~5–15 %** com apps que compartilham |

**Economia medida** (esta base de código): dois apps GTK4 médios que compartilham
seu stack somam ~264 MB separados e ocupam **~141 MB reais (−46 %)**; com 10
apps mistos a economia sobe para **~69 %**. Quanto maior a sobreposição de
bibliotecas, maior a economia — mas convém medi-la por caso, e não assumir os
90–99 % de um runtime compartilhado.

---

## Requisitos

- **Sistema operacional**: Linux (Debian 12+, Ubuntu 22.04+, Fedora 40+, Arch,
  openSUSE Tumbleweed)
- **Kernel**: 5.15+ com user namespaces habilitados
- **Shell**: Bash 4.0+
- **Go**: 1.22+ (o instalador baixa sua própria cópia se faltar)
- **Espaço**: ~500 MB livres para a compilação inicial
- **Internet**: apenas para a primeira instalação

### Dependências do sistema

Instaladas pelo instalador quando possível; úteis também manualmente:

`bubblewrap` · `binutils` (`ldd`/`readelf`) · `jq` · `bc` · `curl` · `tar` ·
`xdg-dbus-proxy` (filtragem de D-Bus) · `zstd` ou `xz` (export mais compacto)

---

## Instalação

### Passo 1 — Clonar e executar

```bash
git clone https://github.com/El-Ave-Azul/packbox.git
cd packbox
./packbox-install.sh
```

O instalador abre um menu; escolha a opção **1** (Instalar).

### Passo 2 — Recarregar o shell

```bash
source ~/.bashrc
```

### Passo 3 — Verificar

```bash
packbox-diagnose
```

### O que o instalador faz

1. Permite selecionar um dos 9 idiomas.
2. Detecta sua distribuição Linux e gerenciador de pacotes.
3. Pede confirmação antes de instalar dependências.
4. Baixa e verifica o Go (por padrão 1.27.1) em `~/.packbox/go` se for preciso.
5. Cria a estrutura de diretórios (`~/.packbox/` e `~/.local/share/packbox/`).
6. Copia as fontes e compila os **15 binários** Go (~1–2 minutos).
7. Configura seu `PATH` em `~/.bashrc` e cria symlinks em `~/.local/bin`.
8. Instala os arquivos de idioma em `~/.config/packbox/lang/`.
9. Verifica que todos os binários estejam presentes e funcionais.

### Desinstalação

Execute o mesmo script e escolha a opção **2**:

```bash
./packbox-install.sh --uninstall
```

| Modo | Descrição |
|------|-------------|
| `s`  | Completo: binários + apps + store CAS + células + menus + ícones + config |
| `k`  | Apenas binários: `~/.packbox/` e symlinks (conserva apps e store CAS) |
| `q`  | Cancelar |

---

## Uso rápido

### 1. Empacotador interativo (recomendado)

```bash
./packbox-packager.sh
```

Menu: empacotar, listar, garbage collection, exportar, importar, desinstalar,
idioma. Detecta apps a partir de `.desktop` em `/usr/share/applications/`, bundles em
`/opt/*` e binários comuns (`htop`, `btop`, `firefox`, `gimp`, …).

Nos modos **Normal** e **Portable** cada lib não universal do fechamento `ldd`
se torna automaticamente uma **célula**.

### 2. Linha de comando

```bash
# Empacotar um diretório
packbox-pack ./mi-app --name org.ejemplo.miapp --version 1.0.0

# Instalar a partir do manifesto gerado
packbox-install ./mi-app/manifest.json

# Executar em sandbox (overlay A sobre C; HOME privado)
packbox-run org.ejemplo.miapp

# Listar apps (tamanho real e economia por sharing) e liberar espaço
packbox-list
packbox-remove org.ejemplo.miapp
packbox-gc

# Atualizar um app instalado reusando chunks do store
packbox-update org.ejemplo.miapp ./nuevo/manifest.json
```

### 3. Exportar, assinar, importar e distribuir

```bash
# Exportar e assinar
packbox-sign keygen                       # cria sua chave (e a confia)
packbox-export --sign app org.ejemplo.miapp
packbox-sign verify ~/.local/share/packbox/exports/org.ejemplo.miapp.pbox

# Publicar um remoto HTTP e usá-lo a partir de outra máquina
packbox-fetch publish org.ejemplo.miapp /srv/packbox
(cd /srv/packbox && python3 -m http.server 8000)
packbox-fetch fetch org.ejemplo.miapp --from http://host:8000

# Importar (verifica a assinatura se existir)
packbox-import app org.ejemplo.miapp.pbox
```

---

## Comandos disponíveis

O Packbox v0.2.0 inclui **15 binários Go** em `~/.packbox/bin/`:

| Comando            | Propósito                                                          |
|--------------------|--------------------------------------------------------------------|
| `packbox-pack`     | Faz o hash de um diretório em chunks CAS e gera `manifest.json`    |
| `packbox-install`  | Instala um app a partir do manifesto (+ `--desktop`/`--remove-desktop`) |
| `packbox-run`      | Executa o app no sandbox `bwrap` (overlay A/C, HOME privado)       |
| `packbox-list`     | Lista apps com seu **tamanho real** e economia por sharing (`--tsv`) |
| `packbox-remove`   | Desinstala um app e libera suas referências CAS                    |
| `packbox-gc`       | Coleta chunks **e células** sem referências                        |
| `packbox-verify`   | Verifica libs resolvíveis + **compatibilidade ABI** do host        |
| `packbox-export`   | Exporta para `.pbox` com **compressão adaptativa** e `--sign` opcional |
| `packbox-import`   | Importa um `.pbox` (anti tar-slip, traversal e assinaturas)        |
| `packbox-update`   | Atualiza um app reusando chunks + relatório de delta (`--no-gc`)   |
| `packbox-module`   | Módulos/células: `list`, `create`, `cell <lib>...`                 |
| `packbox-sign`     | Chaves e assinaturas ed25519: `keygen`, `sign`, `verify`, `trust`  |
| `packbox-fetch`    | Remoto HTTP: `publish <id> <dir>` e `fetch <id> --from <url>`      |
| `packbox-debug`    | Anexa os símbolos de debug (célula separada) de um app instalado   |
| `packbox-diagnose` | Relatório do ambiente para relatos de bugs                         |

---

## Estrutura de arquivos

```
~/.packbox/                              # Instalação
├── bin/                                 # 15 binários Go compilados
└── src/                                 # Código-fonte Go

~/.local/share/packbox/                  # Dados do usuário
├── store/                               # CAS: chunks por hash BLAKE3
│   └── <ab>/<hash-completo>             # + arquivo .refs por chunk
├── apps/                                # Apps instalados
│   └── <app-id>/
│       ├── manifest.json
│       ├── tree/                        # Hardlinks para o CAS (camada A)
│       └── home/                        # HOME privado (criado no primeiro run)
├── mods/                                # Células (org.lib.*, org.debug.*)
├── exports/                             # Arquivos .pbox (+ .sig)
└── tmp/                                 # Temporários

~/.config/packbox/
├── lang/                                # 9 arquivos de idioma
├── signing.key / signing.pub            # sua chave de assinatura
└── trusted/                             # chaves públicas de confiança
```

---

## Arquitetura

### Fluxo de empacotamento

```
┌──────────────┐   pack    ┌──────────────┐  install  ┌──────────────┐
│  Dir fonte   │ ────────► │     CAS      │ ─────────► │  Tree de app │
│  (árvore fs) │           │  (chunks)    │           │ (hardlinks)  │
└──────────────┘           └──────────────┘           └──────┬───────┘
                                  │                          │ + células (camada C)
                                  │ run                      ▼
                         ┌──────────────────────────────────────────┐
                         │  Sandbox bwrap: /app = overlay A sobre C  │
                         │  HOME privado · seccomp · D-Bus filtrado  │
                         └──────────────────────────────────────────┘
```

### Componentes internos

- **CAS + chunker** — Guarda chunks por hash **BLAKE3**. Os arquivos grandes são
  divididos com **CDC** (hash rolante tipo *gear*); os pequenos vão como um único
  chunk (hardlinkáveis, para compartilhar). Escritas **atômicas** (temp+rename).
- **Manifesto** (`schema_version: "1.6"`) — Mapeia rotas para chunks, lista as
  **células** (`mods`), o `host_contract` (delegate + required_symbols), o
  símbolo X11 e, se aplicável, a célula de **debug**.
- **Células** — Uma lib = uma célula `org.lib.<soname>@<hash>` em `mods/`.
  Compartilhadas entre apps. `packbox-gc` apaga as não referenciadas.
- **Sandbox** — `bwrap --unshare-all --cap-drop ALL --clearenv`, **seccomp**
  (bloqueia ptrace/bpf/keyring/io_uring/módulos…), **D-Bus filtrado** com
  `xdg-dbus-proxy` (portais + dconf), **HOME privado** (`apps/<id>/home`), rede
  **opt-in** e **X11 opt-in** (por padrão Wayland + portais; é ativado somente se
  o manifesto o pedir ou se a sessão for apenas X11).
- **Overlay de camadas** — `/app` é composto com `--overlay-src` (C embaixo, A
  em cima); S (host) chega via `/usr`. Evita copiar as células em cada árvore.
- **Host contract** — `packbox-verify` verifica que o host fornece os símbolos
  requeridos (ABI).
- **Assinaturas e remoto** — `packbox-sign` (ed25519) assina o `.pbox`;
  `packbox-fetch` publica e baixa apenas o delta (chunks + células).

### Como funciona a deduplicação

```
App 1: htop     → chunks: [A, B, C]
App 2: neofetch → chunks: [A, D, E]
App 3: btop     → chunks: [A, B, F]

CAS Store:
  A → referências: htop, neofetch, btop      (3 apps)
  B → referências: htop, btop                (2 apps)
  C → htop · D → neofetch · E → neofetch · F → btop

Total: 6 chunks únicos em vez de 9.
```

---

## Segurança

### Mitigações implementadas

- **Isolamento de dados por app** — Cada app roda com seu **HOME privado**
  (`apps/<id>/home`); apenas fontes/temas são expostos em **somente leitura**.
  Não vê nem toca sua configuração real.
- **D-Bus filtrado** — `xdg-dbus-proxy` com lista de permissões (por padrão, portais
  e `dconf`; o barramento de sistema, nada). O app não fala com o barramento real.
- **seccomp** — Filtro padrão que bloqueia superfície perigosa do kernel
  (ptrace, bpf, keyring, io_uring, userfaultfd, módulos, reboot/swap…).
- **X11 opt-in** — Por padrão Wayland + `xdg-desktop-portal` (expondo a
  montagem de documentos do portal); X11 é habilitado com a flag `x11` do
  manifesto ou automaticamente se a sessão do host for apenas X11.
- **Anti tar-slip / traversal** — A extração `.pbox` valida cada entrada
  (`safeJoin` + `O_NOFOLLOW` + destinos de symlink) e rejeita `name`/rotas que
  escapem do diretório do app.
- **Limpeza de ambiente** — `--clearenv` + whitelist explícita: bloqueia
  `LD_PRELOAD`/`LD_LIBRARY_PATH` injetados a partir do host.
- **Sem setuid, sem root** — Tudo roda como seu usuário; `sudo` apenas para as
  dependências do sistema ao instalar.
- **Reference counting + GC** — Cada chunk tem um `.refs`; `packbox-gc` só
  apaga o não referenciado (chunks **e células**).
- **Assinaturas** — `.pbox` assináveis com **ed25519**; `import` verifica e **rejeita**
  pacotes alterados ou de signatários não confiáveis.
- **Integridade do CAS** — Hashes validados antes de serem usados como rota;
  escritas atômicas.

### Limitações conhecidas (v0.2.0 Alpha)

> [!WARNING]
> Áreas onde mais feedback é bem-vindo.

- ⚠️ **Portais parciais.** É permitido falar com os portais e a
  montagem de documentos é exposta, mas ainda não se usam portais para tudo (câmera,
  área de transferência, etc.).
- ⚠️ **`packbox-module remove`/`info`** seguem não implementados (porém existe
  `cell`).
- ⚠️ **Compressão adaptativa** em nível de pacote, não por entrada (o formato é
  tar + um compressor).
- ⚠️ **Sem catálogo.** O remoto HTTP serve dados, não confiança nem um índice
  público.

---

## Roteiro

### v0.1.x — Estabilização

- [x] Verificação de assinaturas para `.pbox` (ed25519 + gestão de chaves)
- [x] Sandbox reforçado: HOME privado, D-Bus filtrado, seccomp
- [x] Células automáticas + overlay de camadas (A/C/S)
- [x] `packbox-update` com delta de chunks + GC automático
- [x] Remoto HTTP (`publish`/`fetch`) com download delta
- [x] Símbolos de debug separados (`cell-debug`)
- [x] Compressão adaptativa em `export`
- [x] Testes de integração end-to-end (`tests/integration.sh`)
- [ ] Política de rede por aplicação
- [ ] Portais completos (arquivos, câmera, área de transferência)
- [ ] CI/CD: `shellcheck`, `gofmt`, `go vet` em cada PR
- [ ] Matriz de testes: Debian 12, Fedora 40, Arch, openSUSE Tumbleweed

### v0.2 — Alcance

- [ ] Binários pré-compilados x86_64 e aarch64 (página de releases)
- [ ] Índice/repositório central assinado (`search`/`install` a partir de remoto)
- [ ] Frontend GUI opcional (GTK4)

### Futuro

- [ ] Importador de runtimes Flatpak (best-effort)
- [ ] Sandbox WASM para plugins não confiáveis

---

## Contribuir

Contribuições são bem-vindas! Áreas onde a ajuda é especialmente útil:

- **Traduções** — Adicione um locale copiando um bloco existente em
  `i18n/` e traduzindo cada chave `L_*`.
- **Portais** — Integrar `xdg-desktop-portal` para acesso a arquivos.
- **Chunking / dedup** — Melhorar o CDC e a política de limiar.
- **Relatos de bugs** — Inclua sempre a saída de `packbox-diagnose`.

### Como começar

```bash
git clone https://github.com/El-Ave-Azul/packbox.git
cd packbox
cd src && go test ./...     # testes unitários
bash tests/integration.sh   # end-to-end (pack → export → import → run)
```

- 🐛 [Abrir uma issue](https://github.com/El-Ave-Azul/packbox/issues)
- 💬 [Iniciar uma discussão](https://github.com/El-Ave-Azul/packbox/discussions)

> [!TIP]
> Rode `shellcheck` nos scripts bash e `gofmt` + `go vet` no Go antes de
> enviar um PR.

---

## Licença

Distribuído sob a **Apache License 2.0**. Ver [LICENSE](../../LICENSE).

A Apache 2.0 traz uma **cláusula explícita de concessão de patentes**, que
protege usuários e contribuintes contra litígios sobre as técnicas de
deduplicação e sandboxing, e é compatível com GPLv3.

---

## Agradecimentos

- **[bubblewrap](https://github.com/containers/bubblewrap)** — Primitiva de
  sandbox Linux que torna possível o `packbox-run`.
- **[BLAKE3](https://github.com/BLAKE3-team/BLAKE3)** — Hashing de conteúdo
  rápido e criptograficamente seguro.
- **[xdg-desktop-portal](https://flatpak.github.io/xdg-desktop-portal/)** e
  **xdg-dbus-proxy** — Acesso mediado a arquivos e filtragem de D-Bus.
- **[Flatpak](https://flatpak.org/)** — Demonstrou que os apps Linux
  em sandbox funcionam em escala; muitas de suas decisões informaram as
  nossas, inclusive onde divergimos.
- **Comunidade Linux global** — A camada i18n de 9 idiomas existe graças às suas
  revisões e contribuições.
