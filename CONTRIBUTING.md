# Contribuir a Packbox · Contributing to Packbox

¡Gracias por querer ayudar! / Thanks for wanting to help!

---

## Cómo empezar · Getting started

```bash
git clone https://github.com/El-Ave-Azul/packbox.git
cd packbox
./packbox-install.sh          # opción 1: instala deps, Go y compila los 15 binarios
```

Para desarrollar sin instalar, basta con compilar desde `src/`:

```bash
cd src && go build ./... && go test ./...
```

## Tests · Tests

```bash
cd src && go test ./...        # unit tests (Go)
bash tests/integration.sh      # end-to-end: pack → export → import → run
```

El test de integración corre en un **HOME aislado bajo el repo** (mismo FS que el
proyecto, **no** `/tmp`) para cazar bugs *cross-device* y de formato. Si algo
falla, pásale la salida completa.

## Convenciones · Conventions

- **Go**: `gofmt` y `go vet` limpios. Nada sin formatear.
- **Shell**: `shellcheck` sin avisos nuevos (hay un paso *advisory* en la CI).
- **Comentarios bilingües** (ES + EN) en el código, como el resto del proyecto.
- **Commits**: `tipo(área): resumen` (p. ej. `fix(sandbox): …`, `feat(cells): …`).
- **Un cambio, un PR**: explica el *porqué*, no solo el *qué*.

## Traducciones · Translations

- **Idiomas**: copia un archivo de `i18n/` (p. ej. `en.sh`) y traduce cada clave
  `L_*`; añádelo a la lista de `lib/i18n.sh`.
- **READMEs**: `README.md` es el principal (español); las traducciones viven en
  `docs/<lang>/README.md` con su barra de idiomas.

## Reportar bugs · Reporting bugs

Incluye **siempre**:

```bash
packbox-diagnose            # salida completa
bwrap --version
grep -E '^(ID|ID_LIKE|VERSION_ID)=' /etc/os-release
```

y los pasos para reproducirlo. Si es al **empaquetar/ejecutar**, di la app y el
modo (Normal/Portable/Bundle/Módulo).

## Pull requests

Rellena la plantilla, enlaza el issue si lo hay, y asegúrate de que la **CI pasa**
(`gofmt` · `go vet` · `go test` · `tests/integration.sh`).

---

> [!TIP]
> Antes de enviar: `gofmt -w .`, `go vet ./...`, `go test ./...` y
> `bash tests/integration.sh`.
