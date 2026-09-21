#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
# EN: Packbox i18n — Shared translations.
# ES: Packbox i18n — Traducciones compartidas.
#
# EN: Sourced by: packbox-installer-v0.1.0.sh + packbox-packager-v0.1.0.sh
# ES: Cargado por: packbox-installer-v0.1.0.sh + packbox-packager-v0.1.0.sh
#
# EN: This file provides:
#       - select_language()    → 9-language selector
#       - install_lang_files() → writes the 9 files to ~/.config/packbox/lang/
#       - load_lang()          → loads chosen language (with fallbacks)
#       - t()                  → translator: t KEY → value
# ES: Este archivo provee:
#       - select_language()    → selector de 9 idiomas
#       - install_lang_files() → escribe los 9 archivos a ~/.config/packbox/lang/
#       - load_lang()          → carga el idioma elegido (con fallbacks)
#       - t()                  → traductor: t CLAVE → valor
# ═══════════════════════════════════════════════════════════════

# ───────────────────────────────────────────────────────────────
# EN: Guard against double sourcing.
# ES: Guard contra doble source.
# ───────────────────────────────────────────────────────────────
[[ -n "${PACKBOX_I18N_LOADED:-}" ]] && return 0
PACKBOX_I18N_LOADED=1

# EN: Language directory and current language code.
# ES: Directorio de idiomas y código de idioma actual.
PACKBOX_LANG_DIR="${PACKBOX_LANG_DIR:-$HOME/.config/packbox/lang}"
L_LANG_CODE=""

# EN: Generation marker. Bump it whenever a key is added or
#     changed, to force install_lang_files() to rewrite the
#     per-language files on the next run.
# ES: Marca de generación. Súbela cuando se añada o cambie una
#     clave, para forzar que install_lang_files() reescriba los
#     archivos de idioma en la próxima ejecución.
PACKBOX_I18N_GEN="1"

# ═══════════════════════════════════════════════════════════════
# EN: Language selector.
# ES: Selector de idioma.
# ═══════════════════════════════════════════════════════════════

# ═══════════════════════════════════════════════════════════════
# EN: Language selector.
# ES: Selector de idioma.
#
# EN: Priority: PACKBOX_LANG env var > saved choice > prompt.
#     The chosen code is persisted to $PACKBOX_LANG_DIR/current,
#     so subsequent runs skip the prompt.
# ES: Prioridad: variable PACKBOX_LANG > elección guardada >
#     prompt. El código elegido se persiste en
#     $PACKBOX_LANG_DIR/current, así las siguientes ejecuciones
#     se saltan el prompt.
# ═══════════════════════════════════════════════════════════════
select_language() {
    # EN: Highest priority: explicit env var.
    # ES: Prioridad máxima: variable de entorno explícita.
    if [[ -n "${PACKBOX_LANG:-}" ]]; then
        L_LANG_CODE="$PACKBOX_LANG"
        return
    fi

    # EN: Ensure the dir exists before reading/writing the marker.
    # ES: Asegura que el dir exista antes de leer/escribir el marcador.
    mkdir -p "$PACKBOX_LANG_DIR" 2>/dev/null

    # EN: Reuse a saved choice, if valid.
    # ES: Reutiliza la elección guardada, si es válida.
    local saved="$PACKBOX_LANG_DIR/current"
    if [[ -f "$saved" ]]; then
        local code
        code=$(tr -d '[:space:]' < "$saved" 2>/dev/null)
        case "$code" in
            en|es|fr|de|it|zh-CN|zh-TW|ja|ko)
                L_LANG_CODE="$code"
                return
                ;;
        esac
    fi

    # EN: No saved choice: show the interactive menu.
    # ES: Sin elección guardada: muestra el menú interactivo.
    clear
    echo -e "${BD:-}${C:-}"
    echo "  ═══════════════════════════════════════════════════════════════"
    echo "   PACKBOX v0.1.0 Alpha — Language / Idioma / Langue / Sprache"
    echo "  ═══════════════════════════════════════════════════════════════"
    echo -e "${N:-}"
    echo ""
    echo -e "      ${C:-}1${N:-}) English                    ${C:-}6${N:-}) 简体中文"
    echo -e "      ${C:-}2${N:-}) Español                    ${C:-}7${N:-}) 繁體中文"
    echo -e "      ${C:-}3${N:-}) Français                   ${C:-}8${N:-}) 日本語"
    echo -e "      ${C:-}4${N:-}) Deutsch                    ${C:-}9${N:-}) 한국어"
    echo -e "      ${C:-}5${N:-}) Italiano"
    echo ""
    echo -en "  ${BD:-}> [1-9, Enter=English]: ${N:-}"

    # EN: Read choice; default to English.
    # ES: Lee elección; por defecto inglés.
    local sel
    read -r sel
    case "${sel:-1}" in
        1) L_LANG_CODE="en" ;;
        2) L_LANG_CODE="es" ;;
        3) L_LANG_CODE="fr" ;;
        4) L_LANG_CODE="de" ;;
        5) L_LANG_CODE="it" ;;
        6) L_LANG_CODE="zh-CN" ;;
        7) L_LANG_CODE="zh-TW" ;;
        8) L_LANG_CODE="ja" ;;
        9) L_LANG_CODE="ko" ;;
        *) L_LANG_CODE="en" ;;
    esac

    # EN: Persist for next runs. Silent failure is acceptable.
    # ES: Persiste para próximas ejecuciones. Fallo silencioso OK.
    echo "$L_LANG_CODE" > "$saved" 2>/dev/null || true

    # EN: Hint for users who want to change it later.
    # ES: Pista para quien quiera cambiarlo después.
    echo ""
    echo -e "  ${DM:-}(change later: rm '$saved' or set PACKBOX_LANG)${N:-}"
    sleep 1
}
    # EN: Respect a pre-set language (env var).
    # ES: Respeta un idioma preconfigurado (variable de entorno).
    if [[ -n "${PACKBOX_LANG:-}" ]]; then
        L_LANG_CODE="$PACKBOX_LANG"
        return
    fi

    # EN: Render the interactive menu.
    # ES: Renderiza el menú interactivo.
    clear
    echo -e "${BD:-}${C:-}"
    echo "  ═══════════════════════════════════════════════════════════════"
    echo "   PACKBOX v0.1.0 Alpha — Language / Idioma / Langue / Sprache"
    echo "  ═══════════════════════════════════════════════════════════════"
    echo -e "${N:-}"
    echo ""
    echo -e "      ${C:-}1${N:-}) English                    ${C:-}6${N:-}) 简体中文"
    echo -e "      ${C:-}2${N:-}) Español                    ${C:-}7${N:-}) 繁體中文"
    echo -e "      ${C:-}3${N:-}) Français                   ${C:-}8${N:-}) 日本語"
    echo -e "      ${C:-}4${N:-}) Deutsch                    ${C:-}9${N:-}) 한국어"
    echo -e "      ${C:-}5${N:-}) Italiano"
    echo ""
    echo -en "  ${BD:-}> [1-9, Enter=English]: ${N:-}"

    # EN: Read choice; default to English.
    # ES: Lee elección; por defecto inglés.
    local sel
    read -r sel
    case "${sel:-1}" in
        1) L_LANG_CODE="en" ;;
        2) L_LANG_CODE="es" ;;
        3) L_LANG_CODE="fr" ;;
        4) L_LANG_CODE="de" ;;
        5) L_LANG_CODE="it" ;;
        6) L_LANG_CODE="zh-CN" ;;
        7) L_LANG_CODE="zh-TW" ;;
        8) L_LANG_CODE="ja" ;;
        9) L_LANG_CODE="ko" ;;
        *) L_LANG_CODE="en" ;;
    esac
}

# ═══════════════════════════════════════════════════════════════
# EN: install_lang_files — write the 9 language files.
# ES: install_lang_files — escribe los 9 archivos de idioma.
# ═══════════════════════════════════════════════════════════════
install_lang_files() {
    mkdir -p "$PACKBOX_LANG_DIR"
    # EN: Remove legacy single-file Chinese variant if present.
    # ES: Elimina la variante china antigua de archivo único si existe.
    rm -f "$PACKBOX_LANG_DIR/zh.sh" 2>/dev/null

    # ───────────────────────────────────────────────────────────
    # EN: _w — helper to write one language file.
    # ES: _w — helper para escribir un archivo de idioma.
    # ───────────────────────────────────────────────────────────
   
  
    # EN: _w — write one language file, unless an up-to-date one
    #     already exists (matched by generation marker). Bump
    #     PACKBOX_I18N_GEN to force a rewrite.
    # ES: _w — escribe un archivo de idioma, salvo que ya exista
    #     uno actualizado (según la marca de generación). Sube
    #     PACKBOX_I18N_GEN para forzar reescritura.
    _w() {
        local code="${1:-en}" name="${2:-English}"
        shift 2
        local file="$PACKBOX_LANG_DIR/${code}.sh"

        # EN: Skip if the file is current.
        # ES: Omite si el archivo está actualizado.
        if [[ -f "$file" ]] && grep -q "^L_LANG_GEN=\"$PACKBOX_I18N_GEN\"$" "$file" 2>/dev/null; then
            return 0
        fi

        {
            echo "# Packbox i18n — $name"
            echo "L_LANG_GEN=\"$PACKBOX_I18N_GEN\""
            echo "L_LANG_NAME=\"$name\""
            for line in "$@"; do
                echo "$line"
            done
        } > "$file"
    } 
   
    # ─── EN — English ─────────────────────────────────────────
    # EN: English strings (reference language).
    # ES: Cadenas en inglés (idioma de referencia).
    _w en "English" \
        'L_WELCOME="Packbox installer"' \
        'L_MENU_INSTALL="Install Packbox"' \
        'L_MENU_UNINSTALL="Uninstall Packbox"' \
        'L_MENU_EXIT="Exit"' \
        'L_MENU_PROMPT="Select option"' \
        'L_INSTALLER_TITLE="PACKBOX v0.1.0 Alpha — Installer"' \
        'L_PACKAGER_TITLE="PACKBOX Packager v0.1.0 Alpha"' \
        'L_STEP1="Detecting distribution"' \
        'L_STEP2="Installing Go 1.22+"' \
        'L_STEP3="Creating directory structure"' \
        'L_STEP4="Generating Go project"' \
        'L_STEP5="Compiling binaries"' \
        'L_STEP6="Running tests"' \
        'L_STEP7="Configuring PATH"' \
        'L_STEP8="Final verification"' \
        'L_CONTINUE="Continue? [Y/n] "' \
        'L_CANCEL="Cancelled"' \
        'L_INSTALL_DEPS="Will install: "' \
        'L_INSTALLED_OK="PACKBOX v0.1.0 Alpha INSTALLED SUCCESSFULLY"' \
        'L_NEXT_STEPS="Next steps"' \
        'L_RELOAD_SHELL="Reload your shell"' \
        'L_VERIFY="Verify"' \
        'L_USE_DETECTOR="Use the packager"' \
        'L_BINARIES_OK="All binaries verified"' \
        'L_COMPRESS_OK="Compression: zstd -19 / xz -9e / gzip"' \
        'L_DESKTOP_OK="Desktop menu: ~/.local/share/applications"' \
        'L_DNS_OK="DNS sandbox fix applied"' \
        'L_LANG_SAVED="Language files installed"' \
        'L_MIGRATE_DONE="Old directory found"' \
        'L_MIGRATE_MSG="Old ~/packbox found. Remove: rm -rf ~/packbox"' \
        'L_UNINSTALL_TITLE="Uninstall Packbox"' \
        'L_UNINSTALL_SCAN="Scanning what will be removed..."' \
        'L_UNINSTALL_WILL="Will remove the following:"' \
        'L_UNINSTALL_CONFIRM="Proceed with uninstall? [s/N] "' \
        'L_UNINSTALL_TYPE="Type DELETE in caps to confirm: "' \
        'L_UNINSTALL_MISMATCH="Cancelled (input did not match DELETE)"' \
        'L_UNINSTALL_MODE="Mode: [s]=full, [k]=binaries only, [q]=cancel: "' \
        'L_UNINSTALL_BIN_ONLY="Removing binaries and scripts only"' \
        'L_UNINSTALL_FULL="Full removal"' \
        'L_UNINSTALL_REMOVING="Removing"' \
        'L_UNINSTALL_REMOVED="Removed"' \
        'L_UNINSTALL_DONE="PACKBOX UNINSTALLED"' \
        'L_UNINSTALL_FREED="Space freed"' \
        'L_UNINSTALL_OLD_PACKBOX="Also remove old ~/packbox? [s/N] "' \
        'L_UNINSTALL_BASHRC="Cleaning ~/.bashrc (backup: ~/.bashrc.packbox-uninstall.bak)"' \
        'L_UNINSTALL_DESKTOP="Removing menu entries"' \
        'L_UNINSTALL_ICONS="Removing icons"' \
        'L_UNINSTALL_SYMLINKS="Removing ~/.local/bin symlinks"' \
        'L_UNINSTALL_NOTHING="Nothing to uninstall"' \
        'L_ABORT="Aborted"' \
        'L_YES="y"' \
        'L_NO="n"' \
        'L_TOTAL="Total"' \
        'L_WHAT_DO="What do you want to do?"' \
        'L_1_PACK="Pack system application"' \
        'L_2_LIST="List installed apps"' \
        'L_3_GC="Garbage collection"' \
        'L_4_EXPORT="Export app to file"' \
        'L_5_IMPORT="Import app from file"' \
        'L_6_UNINSTALL="Uninstall application"' \
        'L_0_EXIT="Exit"' \
        'L_OPTION="Option"' \
        'L_SELECT="Selection"' \
        'L_TOP="Top apps by size"' \
        'L_SEARCHING="Scanning"' \
        'L_DETECTED="Detected"' \
        'L_BUNDLE="Bundle"' \
        'L_PORTABLE="Portable"' \
        'L_MODE="Mode"' \
        'L_NORMAL="Normal"' \
        'L_MODULE="Module"' \
        'L_APP_ID="App ID"' \
        'L_VERSION="Version"' \
        'L_DESCRIPTION="Description"' \
        'L_PACKING="Packaging"' \
        'L_CONFIRM="Confirm? [Y/n] "' \
        'L_EXEC_NOW="Run now? [y/N] "' \
        'L_CLEANUP="Cleaning up"' \
        'L_INSTALLED="Installed"' \
        'L_REMOVED="Removed"' \
        'L_FAILED="Failed"' \
        'L_CREATE_DESKTOP="Create menu entry? [Y/n] "' \
        'L_SEARCH_PROMPT="Search: "' \
        'L_FILTER_MB="Minimum size in MB: "' \
        'L_NO_RESULTS="No results"' \
        'L_ALL="todos"' \
        'L_ANOTHER="Another? [s/N] "' \
        'L_RUN_INSTALLER_NOW="Run installer now? [S/n] "' \
        'L_DOES_NOT_EXIST="Does not exist"' \
        'L_NO_SELECTION="No selection"' \
        'L_INVALID="Invalid"'

    # ─── ES — Español ─────────────────────────────────────────
    # EN: Spanish strings.
    # ES: Cadenas en español.
    _w es "Español" \
        'L_WELCOME="Instalador de Packbox"' \
        'L_MENU_INSTALL="Instalar Packbox"' \
        'L_MENU_UNINSTALL="Desinstalar Packbox"' \
        'L_MENU_EXIT="Salir"' \
        'L_MENU_PROMPT="Selecciona opción"' \
        'L_INSTALLER_TITLE="PACKBOX v0.1.0 Alpha — Instalador"' \
        'L_PACKAGER_TITLE="PACKBOX Packager v0.1.0 Alpha"' \
        'L_STEP1="Detectando distribución"' \
        'L_STEP2="Instalando Go 1.22+"' \
        'L_STEP3="Creando estructura de carpetas"' \
        'L_STEP4="Generando proyecto Go"' \
        'L_STEP5="Compilando binarios"' \
        'L_STEP6="Ejecutando tests"' \
        'L_STEP7="Configurando PATH"' \
        'L_STEP8="Verificación final"' \
        'L_CONTINUE="¿Continuar? [S/n] "' \
        'L_CANCEL="Cancelado"' \
        'L_INSTALL_DEPS="Se instalarán: "' \
        'L_INSTALLED_OK="PACKBOX v0.1.0 Alpha INSTALADO EXITOSAMENTE"' \
        'L_NEXT_STEPS="Próximos pasos"' \
        'L_RELOAD_SHELL="Recarga tu shell"' \
        'L_VERIFY="Verifica"' \
        'L_USE_DETECTOR="Usa el packager"' \
        'L_BINARIES_OK="Todos los binarios verificados"' \
        'L_COMPRESS_OK="Compresión: zstd -19 / xz -9e / gzip"' \
        'L_DESKTOP_OK="Menú: ~/.local/share/applications"' \
        'L_DNS_OK="Fix DNS del sandbox aplicado"' \
        'L_LANG_SAVED="Archivos de idioma instalados"' \
        'L_MIGRATE_DONE="Directorio antiguo encontrado"' \
        'L_MIGRATE_MSG="Tienes un ~/packbox antiguo. Bórralo: rm -rf ~/packbox"' \
        'L_UNINSTALL_TITLE="Desinstalar Packbox"' \
        'L_UNINSTALL_SCAN="Analizando qué se va a eliminar..."' \
        'L_UNINSTALL_WILL="Se eliminará lo siguiente:"' \
        'L_UNINSTALL_CONFIRM="¿Proceder con la desinstalación? [s/N] "' \
        'L_UNINSTALL_TYPE="Escribe DELETE en mayúsculas para confirmar: "' \
        'L_UNINSTALL_MISMATCH="Cancelado (no coincide con DELETE)"' \
        'L_UNINSTALL_MODE="Modo: [s]=completo, [k]=solo binarios, [q]=cancelar: "' \
        'L_UNINSTALL_BIN_ONLY="Eliminando solo binarios y scripts"' \
        'L_UNINSTALL_FULL="Eliminación completa"' \
        'L_UNINSTALL_REMOVING="Eliminando"' \
        'L_UNINSTALL_REMOVED="Eliminado"' \
        'L_UNINSTALL_DONE="PACKBOX DESINSTALADO"' \
        'L_UNINSTALL_FREED="Espacio liberado"' \
        'L_UNINSTALL_OLD_PACKBOX="¿También borrar ~/packbox antiguo? [s/N] "' \
        'L_UNINSTALL_BASHRC="Limpiando ~/.bashrc (backup: ~/.bashrc.packbox-uninstall.bak)"' \
        'L_UNINSTALL_DESKTOP="Eliminando entradas de menú"' \
        'L_UNINSTALL_ICONS="Eliminando iconos"' \
        'L_UNINSTALL_SYMLINKS="Eliminando symlinks de ~/.local/bin"' \
        'L_UNINSTALL_NOTHING="Nada que desinstalar"' \
        'L_ABORT="Abortado"' \
        'L_YES="s"' \
        'L_NO="n"' \
        'L_TOTAL="Total"' \
        'L_WHAT_DO="¿Qué deseas hacer?"' \
        'L_1_PACK="Empaquetar aplicación del sistema"' \
        'L_2_LIST="Listar apps instaladas"' \
        'L_3_GC="Recolección de basura"' \
        'L_4_EXPORT="Exportar app a archivo"' \
        'L_5_IMPORT="Importar app desde archivo"' \
        'L_6_UNINSTALL="Desinstalar aplicación"' \
        'L_0_EXIT="Salir"' \
        'L_OPTION="Opción"' \
        'L_SELECT="Selección"' \
        'L_TOP="Apps más grandes por tamaño"' \
        'L_SEARCHING="Escaneando"' \
        'L_DETECTED="Detectadas"' \
        'L_BUNDLE="Bundle"' \
        'L_PORTABLE="Portable"' \
        'L_MODE="Modo"' \
        'L_NORMAL="Normal"' \
        'L_MODULE="Módulo"' \
        'L_APP_ID="App ID"' \
        'L_VERSION="Versión"' \
        'L_DESCRIPTION="Descripción"' \
        'L_PACKING="Empaquetando"' \
        'L_CONFIRM="¿Confirmar? [S/n] "' \
        'L_EXEC_NOW="¿Ejecutar ahora? [s/N] "' \
        'L_CLEANUP="Limpiando"' \
        'L_INSTALLED="Instalado"' \
        'L_REMOVED="Eliminado"' \
        'L_FAILED="Falló"' \
        'L_CREATE_DESKTOP="¿Crear entrada en el menú? [S/n] "' \
        'L_SEARCH_PROMPT="Buscar: "' \
        'L_FILTER_MB="Tamaño mínimo en MB: "' \
        'L_NO_RESULTS="Sin resultados"' \
        'L_ALL="all"' \
        'L_ANOTHER="¿Otra? [s/N] "' \
        'L_RUN_INSTALLER_NOW="¿Ejecutar instalador ahora? [S/n] "' \
        'L_DOES_NOT_EXIST="No existe"' \
        'L_NO_SELECTION="Sin selección"' \
        'L_INVALID="Inválido"'

    # ─── FR — Français ────────────────────────────────────────
    # EN: French strings.
    # ES: Cadenas en francés.
    _w fr "Français" \
        "L_WELCOME=\"Programme d'installation Packbox\"" \
        'L_MENU_INSTALL="Installer Packbox"' \
        'L_MENU_UNINSTALL="Désinstaller Packbox"' \
        'L_MENU_EXIT="Quitter"' \
        'L_MENU_PROMPT="Sélectionnez une option"' \
        'L_INSTALLER_TITLE="PACKBOX v0.1.0 Alpha — Installateur"' \
        'L_PACKAGER_TITLE="PACKBOX Packager v0.1.0 Alpha"' \
        'L_STEP1="Détection de la distribution"' \
        'L_STEP2="Installation de Go 1.22+"' \
        "L_STEP3=\"Création de l'arborescence\"" \
        'L_STEP4="Génération du projet Go"' \
        'L_STEP5="Compilation des binaires"' \
        'L_STEP6="Exécution des tests"' \
        'L_STEP7="Configuration du PATH"' \
        'L_STEP8="Vérification finale"' \
        'L_CONTINUE="Continuer ? [O/n] "' \
        'L_CANCEL="Annulé"' \
        'L_INSTALL_DEPS="Sera installé : "' \
        'L_INSTALLED_OK="PACKBOX v0.1.0 Alpha INSTALLÉ AVEC SUCCÈS"' \
        'L_NEXT_STEPS="Prochaines étapes"' \
        'L_RELOAD_SHELL="Rechargez votre shell"' \
        'L_VERIFY="Vérifier"' \
        'L_USE_DETECTOR="Utiliser le packager"' \
        'L_BINARIES_OK="Tous les binaires vérifiés"' \
        'L_COMPRESS_OK="Compression : zstd -19 / xz -9e / gzip"' \
        'L_DESKTOP_OK="Menu : ~/.local/share/applications"' \
        'L_DNS_OK="Correctif DNS sandbox appliqué"' \
        'L_LANG_SAVED="Fichiers de langue installés"' \
        'L_MIGRATE_DONE="Ancien répertoire trouvé"' \
        'L_MIGRATE_MSG="Ancien ~/packbox trouvé. Supprimez-le : rm -rf ~/packbox"' \
        'L_UNINSTALL_TITLE="Désinstaller Packbox"' \
        'L_UNINSTALL_SCAN="Analyse de ce qui sera supprimé..."' \
        'L_UNINSTALL_WILL="Sera supprimé :"' \
        'L_UNINSTALL_CONFIRM="Procéder à la désinstallation ? [o/N] "' \
        'L_UNINSTALL_TYPE="Tapez DELETE en majuscules pour confirmer : "' \
        'L_UNINSTALL_MISMATCH="Annulé (ne correspond pas à DELETE)"' \
        'L_UNINSTALL_MODE="Mode : [s]=complet, [k]=binaires seuls, [q]=annuler : "' \
        'L_UNINSTALL_BIN_ONLY="Suppression des binaires et scripts seulement"' \
        'L_UNINSTALL_FULL="Suppression complète"' \
        'L_UNINSTALL_REMOVING="Suppression"' \
        'L_UNINSTALL_REMOVED="Supprimé"' \
        'L_UNINSTALL_DONE="PACKBOX DÉSINSTALLÉ"' \
        'L_UNINSTALL_FREED="Espace libéré"' \
        'L_UNINSTALL_OLD_PACKBOX="Supprimer aussi l'\''ancien ~/packbox ? [o/N] "' \
        'L_UNINSTALL_BASHRC="Nettoyage de ~/.bashrc (sauvegarde : ~/.bashrc.packbox-uninstall.bak)"' \
        'L_UNINSTALL_DESKTOP="Suppression des entrées de menu"' \
        'L_UNINSTALL_ICONS="Suppression des icônes"' \
        'L_UNINSTALL_SYMLINKS="Suppression des liens ~/.local/bin"' \
        'L_UNINSTALL_NOTHING="Rien à désinstaller"' \
        'L_ABORT="Annulé"' \
        'L_YES="o"' \
        'L_NO="n"' \
        'L_TOTAL="Total"' \
        'L_WHAT_DO="Que voulez-vous faire ?"' \
        'L_1_PACK="Empaqueter une application système"' \
        'L_2_LIST="Lister les applications installées"' \
        'L_3_GC="Ramasse-miettes"' \
        'L_4_EXPORT="Exporter l'\''application vers un fichier"' \
        'L_5_IMPORT="Importer depuis un fichier"' \
        'L_6_UNINSTALL="Désinstaller une application"' \
        'L_0_EXIT="Quitter"' \
        'L_OPTION="Option"' \
        'L_SELECT="Sélection"' \
        'L_TOP="Applications les plus volumineuses"' \
        'L_SEARCHING="Analyse"' \
        'L_DETECTED="Détectées"' \
        'L_BUNDLE="Bundle"' \
        'L_PORTABLE="Portable"' \
        'L_MODE="Mode"' \
        'L_NORMAL="Normal"' \
        'L_MODULE="Module"' \
        'L_APP_ID="ID de l'\''application"' \
        'L_VERSION="Version"' \
        'L_DESCRIPTION="Description"' \
        'L_PACKING="Empaquetage"' \
        'L_CONFIRM="Confirmer ? [O/n] "' \
        'L_EXEC_NOW="Exécuter maintenant ? [o/N] "' \
        'L_CLEANUP="Nettoyage"' \
        'L_INSTALLED="Installé"' \
        'L_REMOVED="Supprimé"' \
        'L_FAILED="Échec"' \
        'L_CREATE_DESKTOP="Créer une entrée de menu ? [O/n] "' \
        'L_SEARCH_PROMPT="Rechercher : "' \
        'L_FILTER_MB="Taille minimale en Mo : "' \
        'L_NO_RESULTS="Aucun résultat"' \
        'L_ALL="tous"' \
        'L_ANOTHER="Une autre ? [o/N] "' \
        'L_RUN_INSTALLER_NOW="Exécuter l'\''installateur maintenant ? [O/n] "' \
        'L_DOES_NOT_EXIST="N'\''existe pas"' \
        'L_NO_SELECTION="Aucune sélection"' \
        'L_INVALID="Invalide"'

    # ─── DE — Deutsch ─────────────────────────────────────────
    # EN: German strings.
    # ES: Cadenas en alemán.
    _w de "Deutsch" \
        'L_WELCOME="Packbox-Installationsprogramm"' \
        'L_MENU_INSTALL="Packbox installieren"' \
        'L_MENU_UNINSTALL="Packbox deinstallieren"' \
        'L_MENU_EXIT="Beenden"' \
        'L_MENU_PROMPT="Option auswählen"' \
        'L_INSTALLER_TITLE="PACKBOX v0.1.0 Alpha — Installer"' \
        'L_PACKAGER_TITLE="PACKBOX Packager v0.1.0 Alpha"' \
        'L_STEP1="Erkennung der Distribution"' \
        'L_STEP2="Installation von Go 1.22+"' \
        'L_STEP3="Verzeichnisstruktur erstellen"' \
        'L_STEP4="Go-Projekt generieren"' \
        'L_STEP5="Binärdateien kompilieren"' \
        'L_STEP6="Tests ausführen"' \
        'L_STEP7="PATH konfigurieren"' \
        'L_STEP8="Abschließende Überprüfung"' \
        'L_CONTINUE="Fortfahren? [J/n] "' \
        'L_CANCEL="Abgebrochen"' \
        'L_INSTALL_DEPS="Wird installiert: "' \
        'L_INSTALLED_OK="PACKBOX v0.1.0 Alpha ERFOLGREICH INSTALLIERT"' \
        'L_NEXT_STEPS="Nächste Schritte"' \
        'L_RELOAD_SHELL="Shell neu laden"' \
        'L_VERIFY="Überprüfen"' \
        'L_USE_DETECTOR="Packager verwenden"' \
        'L_BINARIES_OK="Alle Binärdateien überprüft"' \
        'L_COMPRESS_OK="Komprimierung: zstd -19 / xz -9e / gzip"' \
        'L_DESKTOP_OK="Menü: ~/.local/share/applications"' \
        'L_DNS_OK="DNS-Sandbox-Fix angewendet"' \
        'L_LANG_SAVED="Sprachdateien installiert"' \
        'L_MIGRATE_DONE="Altes Verzeichnis gefunden"' \
        'L_MIGRATE_MSG="Altes ~/packbox gefunden. Löschen: rm -rf ~/packbox"' \
        'L_UNINSTALL_TITLE="Packbox deinstallieren"' \
        'L_UNINSTALL_SCAN="Prüfe, was entfernt wird..."' \
        'L_UNINSTALL_WILL="Folgendes wird entfernt:"' \
        'L_UNINSTALL_CONFIRM="Deinstallation fortsetzen? [j/N] "' \
        'L_UNINSTALL_TYPE="Zum Bestätigen DELETE in Großbuchstaben eingeben: "' \
        'L_UNINSTALL_MISMATCH="Abgebrochen (stimmt nicht mit DELETE überein)"' \
        'L_UNINSTALL_MODE="Modus: [s]=vollständig, [k]=nur Binärdateien, [q]=abbrechen: "' \
        'L_UNINSTALL_BIN_ONLY="Nur Binärdateien und Skripte werden entfernt"' \
        'L_UNINSTALL_FULL="Vollständige Entfernung"' \
        'L_UNINSTALL_REMOVING="Entferne"' \
        'L_UNINSTALL_REMOVED="Entfernt"' \
        'L_UNINSTALL_DONE="PACKBOX DEINSTALLIERT"' \
        'L_UNINSTALL_FREED="Speicher freigegeben"' \
        'L_UNINSTALL_OLD_PACKBOX="Auch altes ~/packbox entfernen? [j/N] "' \
        'L_UNINSTALL_BASHRC="Bereinige ~/.bashrc (Backup: ~/.bashrc.packbox-uninstall.bak)"' \
        'L_UNINSTALL_DESKTOP="Menüeinträge entfernen"' \
        'L_UNINSTALL_ICONS="Symbole entfernen"' \
        'L_UNINSTALL_SYMLINKS="Entferne Symlinks aus ~/.local/bin"' \
        'L_UNINSTALL_NOTHING="Nichts zu deinstallieren"' \
        'L_ABORT="Abgebrochen"' \
        'L_YES="j"' \
        'L_NO="n"' \
        'L_TOTAL="Gesamt"' \
        'L_WHAT_DO="Was möchten Sie tun?"' \
        'L_1_PACK="Systemanwendung paketieren"' \
        'L_2_LIST="Installierte Apps auflisten"' \
        'L_3_GC="Speicherbereinigung"' \
        'L_4_EXPORT="App in Datei exportieren"' \
        'L_5_IMPORT="App aus Datei importieren"' \
        'L_6_UNINSTALL="Anwendung deinstallieren"' \
        'L_0_EXIT="Beenden"' \
        'L_OPTION="Option"' \
        'L_SELECT="Auswahl"' \
        'L_TOP="Größte Apps nach Größe"' \
        'L_SEARCHING="Scannen"' \
        'L_DETECTED="Erkannt"' \
        'L_BUNDLE="Bundle"' \
        'L_PORTABLE="Portabel"' \
        'L_MODE="Modus"' \
        'L_NORMAL="Normal"' \
        'L_MODULE="Modul"' \
        'L_APP_ID="App-ID"' \
        'L_VERSION="Version"' \
        'L_DESCRIPTION="Beschreibung"' \
        'L_PACKING="Paketierung"' \
        'L_CONFIRM="Bestätigen? [J/n] "' \
        'L_EXEC_NOW="Jetzt ausführen? [j/N] "' \
        'L_CLEANUP="Aufräumen"' \
        'L_INSTALLED="Installiert"' \
        'L_REMOVED="Entfernt"' \
        'L_FAILED="Fehlgeschlagen"' \
        'L_CREATE_DESKTOP="Menüeintrag erstellen? [J/n] "' \
        'L_SEARCH_PROMPT="Suchen: "' \
        'L_FILTER_MB="Mindestgröße in MB: "' \
        'L_NO_RESULTS="Keine Ergebnisse"' \
        'L_ALL="alle"' \
        'L_ANOTHER="Noch eine? [j/N] "' \
        'L_RUN_INSTALLER_NOW="Installer jetzt ausführen? [J/n] "' \
        'L_DOES_NOT_EXIST="Existiert nicht"' \
        'L_NO_SELECTION="Keine Auswahl"' \
        'L_INVALID="Ungültig"'

    # ─── IT — Italiano ────────────────────────────────────────
    # EN: Italian strings.
    # ES: Cadenas en italiano.
    _w it "Italiano" \
        'L_WELCOME="Programma di installazione Packbox"' \
        'L_MENU_INSTALL="Installa Packbox"' \
        'L_MENU_UNINSTALL="Disinstalla Packbox"' \
        'L_MENU_EXIT="Esci"' \
        'L_MENU_PROMPT="Seleziona opzione"' \
        'L_INSTALLER_TITLE="PACKBOX v0.1.0 Alpha — Installer"' \
        'L_PACKAGER_TITLE="PACKBOX Packager v0.1.0 Alpha"' \
        'L_STEP1="Rilevamento distribuzione"' \
        'L_STEP2="Installazione di Go 1.22+"' \
        'L_STEP3="Creazione struttura directory"' \
        'L_STEP4="Generazione progetto Go"' \
        'L_STEP5="Compilazione binari"' \
        'L_STEP6="Esecuzione test"' \
        'L_STEP7="Configurazione PATH"' \
        'L_STEP8="Verifica finale"' \
        'L_CONTINUE="Continuare? [S/n] "' \
        'L_CANCEL="Annullato"' \
        'L_INSTALL_DEPS="Verrà installato: "' \
        'L_INSTALLED_OK="PACKBOX v0.1.0 Alpha INSTALLATO CON SUCCESSO"' \
        'L_NEXT_STEPS="Prossimi passi"' \
        'L_RELOAD_SHELL="Ricarica la shell"' \
        'L_VERIFY="Verifica"' \
        'L_USE_DETECTOR="Usa il packager"' \
        'L_BINARIES_OK="Tutti i binari verificati"' \
        'L_COMPRESS_OK="Compressione: zstd -19 / xz -9e / gzip"' \
        'L_DESKTOP_OK="Menu: ~/.local/share/applications"' \
        'L_DNS_OK="Fix DNS sandbox applicato"' \
        'L_LANG_SAVED="File di lingua installati"' \
        'L_MIGRATE_DONE="Vecchia directory trovata"' \
        'L_MIGRATE_MSG="Vecchio ~/packbox trovato. Elimina: rm -rf ~/packbox"' \
        'L_UNINSTALL_TITLE="Disinstalla Packbox"' \
        'L_UNINSTALL_SCAN="Analisi di ciò che verrà rimosso..."' \
        'L_UNINSTALL_WILL="Verrà rimosso:"' \
        'L_UNINSTALL_CONFIRM="Procedere con la disinstallazione? [s/N] "' \
        'L_UNINSTALL_TYPE="Digita DELETE in maiuscolo per confermare: "' \
        'L_UNINSTALL_MISMATCH="Annullato (non corrisponde a DELETE)"' \
        'L_UNINSTALL_MODE="Modalità: [s]=completa, [k]=solo binari, [q]=annulla: "' \
        'L_UNINSTALL_BIN_ONLY="Rimozione solo binari e script"' \
        'L_UNINSTALL_FULL="Rimozione completa"' \
        'L_UNINSTALL_REMOVING="Rimozione"' \
        'L_UNINSTALL_REMOVED="Rimosso"' \
        'L_UNINSTALL_DONE="PACKBOX DISINSTALLATO"' \
        'L_UNINSTALL_FREED="Spazio liberato"' \
        'L_UNINSTALL_OLD_PACKBOX="Rimuovere anche il vecchio ~/packbox? [s/N] "' \
        'L_UNINSTALL_BASHRC="Pulizia di ~/.bashrc (backup: ~/.bashrc.packbox-uninstall.bak)"' \
        'L_UNINSTALL_DESKTOP="Rimozione voci di menu"' \
        'L_UNINSTALL_ICONS="Rimozione icone"' \
        'L_UNINSTALL_SYMLINKS="Rimozione symlink ~/.local/bin"' \
        'L_UNINSTALL_NOTHING="Niente da disinstallare"' \
        'L_ABORT="Annullato"' \
        'L_YES="s"' \
        'L_NO="n"' \
        'L_TOTAL="Totale"' \
        'L_WHAT_DO="Cosa vuoi fare?"' \
        'L_1_PACK="Impacchetta applicazione di sistema"' \
        'L_2_LIST="Elenca app installate"' \
        'L_3_GC="Garbage collection"' \
        'L_4_EXPORT="Esporta app su file"' \
        'L_5_IMPORT="Importa app da file"' \
        'L_6_UNINSTALL="Disinstalla applicazione"' \
        'L_0_EXIT="Esci"' \
        'L_OPTION="Opzione"' \
        'L_SELECT="Selezione"' \
        'L_TOP="App più grandi per dimensione"' \
        'L_SEARCHING="Scansione"' \
        'L_DETECTED="Rilevate"' \
        'L_BUNDLE="Bundle"' \
        'L_PORTABLE="Portabile"' \
        'L_MODE="Modalità"' \
        'L_NORMAL="Normale"' \
        'L_MODULE="Modulo"' \
        'L_APP_ID="App ID"' \
        'L_VERSION="Versione"' \
        'L_DESCRIPTION="Descrizione"' \
        'L_PACKING="Impacchettamento"' \
        'L_CONFIRM="Confermare? [S/n] "' \
        'L_EXEC_NOW="Eseguire ora? [s/N] "' \
        'L_CLEANUP="Pulizia"' \
        'L_INSTALLED="Installato"' \
        'L_REMOVED="Rimosso"' \
        'L_FAILED="Fallito"' \
        'L_CREATE_DESKTOP="Creare voce di menu? [S/n] "' \
        'L_SEARCH_PROMPT="Cerca: "' \
        'L_FILTER_MB="Dimensione minima in MB: "' \
        'L_NO_RESULTS="Nessun risultato"' \
        'L_ALL="tutti"' \
        'L_ANOTHER="Un'\''altra? [s/N] "' \
        'L_RUN_INSTALLER_NOW="Eseguire l'\''installer ora? [S/n] "' \
        'L_DOES_NOT_EXIST="Non esiste"' \
        'L_NO_SELECTION="Nessuna selezione"' \
        'L_INVALID="Non valido"'

    # ─── ZH-CN — 简体中文 ────────────────────────────────────
    # EN: Simplified Chinese strings.
    # ES: Cadenas en chino simplificado.
    _w zh-CN "简体中文" \
        'L_WELCOME="Packbox 安装程序"' \
        'L_MENU_INSTALL="安装 Packbox"' \
        'L_MENU_UNINSTALL="卸载 Packbox"' \
        'L_MENU_EXIT="退出"' \
        'L_MENU_PROMPT="选择选项"' \
        'L_INSTALLER_TITLE="PACKBOX v0.1.0 Alpha — 安装程序"' \
        'L_PACKAGER_TITLE="PACKBOX Packager v0.1.0 Alpha"' \
        'L_STEP1="检测发行版"' \
        'L_STEP2="安装 Go 1.22+"' \
        'L_STEP3="创建目录结构"' \
        'L_STEP4="生成 Go 项目"' \
        'L_STEP5="编译二进制文件"' \
        'L_STEP6="运行测试"' \
        'L_STEP7="配置 PATH"' \
        'L_STEP8="最终验证"' \
        'L_CONTINUE="继续? [Y/n] "' \
        'L_CANCEL="已取消"' \
        'L_INSTALL_DEPS="将安装: "' \
        'L_INSTALLED_OK="PACKBOX v0.1.0 Alpha 安装成功"' \
        'L_NEXT_STEPS="下一步"' \
        'L_RELOAD_SHELL="重新加载 shell"' \
        'L_VERIFY="验证"' \
        'L_USE_DETECTOR="使用 packager"' \
        'L_BINARIES_OK="所有二进制文件已验证"' \
        'L_COMPRESS_OK="压缩: zstd -19 / xz -9e / gzip"' \
        'L_DESKTOP_OK="菜单: ~/.local/share/applications"' \
        'L_DNS_OK="已应用 DNS 沙箱修复"' \
        'L_LANG_SAVED="语言文件已安装"' \
        'L_MIGRATE_DONE="找到旧目录"' \
        'L_MIGRATE_MSG="你有旧的 ~/packbox。删除: rm -rf ~/packbox"' \
        'L_UNINSTALL_TITLE="卸载 Packbox"' \
        'L_UNINSTALL_SCAN="正在分析将要删除的内容..."' \
        'L_UNINSTALL_WILL="将删除以下内容:"' \
        'L_UNINSTALL_CONFIRM="继续卸载? [y/N] "' \
        'L_UNINSTALL_TYPE="输入大写 DELETE 以确认: "' \
        'L_UNINSTALL_MISMATCH="已取消 (与 DELETE 不匹配)"' \
        'L_UNINSTALL_MODE="模式: [s]=完整, [k]=仅二进制, [q]=取消: "' \
        'L_UNINSTALL_BIN_ONLY="仅删除二进制文件和脚本"' \
        'L_UNINSTALL_FULL="完整删除"' \
        'L_UNINSTALL_REMOVING="正在删除"' \
        'L_UNINSTALL_REMOVED="已删除"' \
        'L_UNINSTALL_DONE="PACKBOX 已卸载"' \
        'L_UNINSTALL_FREED="释放空间"' \
        'L_UNINSTALL_OLD_PACKBOX="也删除旧的 ~/packbox? [y/N] "' \
        'L_UNINSTALL_BASHRC="正在清理 ~/.bashrc (备份: ~/.bashrc.packbox-uninstall.bak)"' \
        'L_UNINSTALL_DESKTOP="正在删除菜单项"' \
        'L_UNINSTALL_ICONS="正在删除图标"' \
        'L_UNINSTALL_SYMLINKS="正在删除 ~/.local/bin 符号链接"' \
        'L_UNINSTALL_NOTHING="没有可卸载的内容"' \
        'L_ABORT="已中止"' \
        'L_YES="y"' \
        'L_NO="n"' \
        'L_TOTAL="总计"' \
        'L_WHAT_DO="你想做什么?"' \
        'L_1_PACK="打包系统应用程序"' \
        'L_2_LIST="列出已安装应用"' \
        'L_3_GC="垃圾回收"' \
        'L_4_EXPORT="导出应用到文件"' \
        'L_5_IMPORT="从文件导入应用"' \
        'L_6_UNINSTALL="卸载应用程序"' \
        'L_0_EXIT="退出"' \
        'L_OPTION="选项"' \
        'L_SELECT="选择"' \
        'L_TOP="最大的应用"' \
        'L_SEARCHING="扫描中"' \
        'L_DETECTED="已检测"' \
        'L_BUNDLE="捆绑"' \
        'L_PORTABLE="便携"' \
        'L_MODE="模式"' \
        'L_NORMAL="普通"' \
        'L_MODULE="模块"' \
        'L_APP_ID="应用 ID"' \
        'L_VERSION="版本"' \
        'L_DESCRIPTION="描述"' \
        'L_PACKING="打包中"' \
        'L_CONFIRM="确认? [Y/n] "' \
        'L_EXEC_NOW="现在运行? [y/N] "' \
        'L_CLEANUP="清理中"' \
        'L_INSTALLED="已安装"' \
        'L_REMOVED="已移除"' \
        'L_FAILED="失败"' \
        'L_CREATE_DESKTOP="创建菜单项? [Y/n] "' \
        'L_SEARCH_PROMPT="搜索: "' \
        'L_FILTER_MB="最小大小 (MB): "' \
        'L_NO_RESULTS="无结果"' \
        'L_ALL="全部"' \
        'L_ANOTHER="再来一个? [y/N] "' \
        'L_RUN_INSTALLER_NOW="现在运行安装程序? [Y/n] "' \
        'L_DOES_NOT_EXIST="不存在"' \
        'L_NO_SELECTION="未选择"' \
        'L_INVALID="无效"'

    # ─── ZH-TW — 繁體中文 ────────────────────────────────────
    # EN: Traditional Chinese strings.
    # ES: Cadenas en chino tradicional.
    _w zh-TW "繁體中文" \
        'L_WELCOME="Packbox 安裝程式"' \
        'L_MENU_INSTALL="安裝 Packbox"' \
        'L_MENU_UNINSTALL="解除安裝 Packbox"' \
        'L_MENU_EXIT="結束"' \
        'L_MENU_PROMPT="選擇選項"' \
        'L_INSTALLER_TITLE="PACKBOX v0.1.0 Alpha — 安裝程式"' \
        'L_PACKAGER_TITLE="PACKBOX Packager v0.1.0 Alpha"' \
        'L_STEP1="偵測發行版"' \
        'L_STEP2="安裝 Go 1.22+"' \
        'L_STEP3="建立目錄結構"' \
        'L_STEP4="產生 Go 專案"' \
        'L_STEP5="編譯二進位檔"' \
        'L_STEP6="執行測試"' \
        'L_STEP7="設定 PATH"' \
        'L_STEP8="最終驗證"' \
        'L_CONTINUE="繼續? [Y/n] "' \
        'L_CANCEL="已取消"' \
        'L_INSTALL_DEPS="將安裝: "' \
        'L_INSTALLED_OK="PACKBOX v0.1.0 Alpha 安裝成功"' \
        'L_NEXT_STEPS="下一步"' \
        'L_RELOAD_SHELL="重新載入 shell"' \
        'L_VERIFY="驗證"' \
        'L_USE_DETECTOR="使用 packager"' \
        'L_BINARIES_OK="所有二進位檔已驗證"' \
        'L_COMPRESS_OK="壓縮: zstd -19 / xz -9e / gzip"' \
        'L_DESKTOP_OK="選單: ~/.local/share/applications"' \
        'L_DNS_OK="已套用 DNS 沙盒修正"' \
        'L_LANG_SAVED="語言檔已安裝"' \
        'L_MIGRATE_DONE="找到舊目錄"' \
        'L_MIGRATE_MSG="你有舊的 ~/packbox。刪除它: rm -rf ~/packbox"' \
        'L_UNINSTALL_TITLE="解除安裝 Packbox"' \
        'L_UNINSTALL_SCAN="正在分析將要刪除的內容..."' \
        'L_UNINSTALL_WILL="將刪除以下內容:"' \
        'L_UNINSTALL_CONFIRM="繼續解除安裝? [y/N] "' \
        'L_UNINSTALL_TYPE="輸入大寫 DELETE 以確認: "' \
        'L_UNINSTALL_MISMATCH="已取消 (與 DELETE 不符)"' \
        'L_UNINSTALL_MODE="模式: [s]=完整, [k]=僅二進位檔, [q]=取消: "' \
        'L_UNINSTALL_BIN_ONLY="僅刪除二進位檔和指令碼"' \
        'L_UNINSTALL_FULL="完整刪除"' \
        'L_UNINSTALL_REMOVING="正在刪除"' \
        'L_UNINSTALL_REMOVED="已刪除"' \
        'L_UNINSTALL_DONE="PACKBOX 已解除安裝"' \
        'L_UNINSTALL_FREED="釋放空間"' \
        'L_UNINSTALL_OLD_PACKBOX="也刪除舊的 ~/packbox? [y/N] "' \
        'L_UNINSTALL_BASHRC="正在清理 ~/.bashrc (備份: ~/.bashrc.packbox-uninstall.bak)"' \
        'L_UNINSTALL_DESKTOP="正在刪除選單項目"' \
        'L_UNINSTALL_ICONS="正在刪除圖示"' \
        'L_UNINSTALL_SYMLINKS="正在刪除 ~/.local/bin 符號連結"' \
        'L_UNINSTALL_NOTHING="沒有可解除安裝的內容"' \
        'L_ABORT="已中止"' \
        'L_YES="y"' \
        'L_NO="n"' \
        'L_TOTAL="總計"' \
        'L_WHAT_DO="你想做什麼?"' \
        'L_1_PACK="打包系統應用程式"' \
        'L_2_LIST="列出已安裝應用"' \
        'L_3_GC="垃圾回收"' \
        'L_4_EXPORT="匯出應用到檔案"' \
        'L_5_IMPORT="從檔案匯入應用"' \
        'L_6_UNINSTALL="解除安裝應用程式"' \
        'L_0_EXIT="結束"' \
        'L_OPTION="選項"' \
        'L_SELECT="選擇"' \
        'L_TOP="最大的應用"' \
        'L_SEARCHING="掃描中"' \
        'L_DETECTED="已偵測"' \
        'L_BUNDLE="綑綁"' \
        'L_PORTABLE="可攜"' \
        'L_MODE="模式"' \
        'L_NORMAL="一般"' \
        'L_MODULE="模組"' \
        'L_APP_ID="應用 ID"' \
        'L_VERSION="版本"' \
        'L_DESCRIPTION="描述"' \
        'L_PACKING="打包中"' \
        'L_CONFIRM="確認? [Y/n] "' \
        'L_EXEC_NOW="現在執行? [y/N] "' \
        'L_CLEANUP="清理中"' \
        'L_INSTALLED="已安裝"' \
        'L_REMOVED="已移除"' \
        'L_FAILED="失敗"' \
        'L_CREATE_DESKTOP="建立選單項目? [Y/n] "' \
        'L_SEARCH_PROMPT="搜尋: "' \
        'L_FILTER_MB="最小大小 (MB): "' \
        'L_NO_RESULTS="無結果"' \
        'L_ALL="全部"' \
        'L_ANOTHER="再來一個? [y/N] "' \
        'L_RUN_INSTALLER_NOW="現在執行安裝程式? [Y/n] "' \
        'L_DOES_NOT_EXIST="不存在"' \
        'L_NO_SELECTION="未選擇"' \
        'L_INVALID="無效"'

    # ─── JA — 日本語 ─────────────────────────────────────────
    # EN: Japanese strings.
    # ES: Cadenas en japonés.
    _w ja "日本語" \
        'L_WELCOME="Packbox インストーラー"' \
        'L_MENU_INSTALL="Packbox をインストール"' \
        'L_MENU_UNINSTALL="Packbox をアンインストール"' \
        'L_MENU_EXIT="終了"' \
        'L_MENU_PROMPT="オプションを選択"' \
        'L_INSTALLER_TITLE="PACKBOX v0.1.0 Alpha — インストーラー"' \
        'L_PACKAGER_TITLE="PACKBOX Packager v0.1.0 Alpha"' \
        'L_STEP1="ディストリビューションを検出中"' \
        'L_STEP2="Go 1.22+ をインストール中"' \
        'L_STEP3="ディレクトリ構造を作成中"' \
        'L_STEP4="Go プロジェクトを生成中"' \
        'L_STEP5="バイナリをコンパイル中"' \
        'L_STEP6="テストを実行中"' \
        'L_STEP7="PATH を設定中"' \
        'L_STEP8="最終検証"' \
        'L_CONTINUE="続行しますか? [Y/n] "' \
        'L_CANCEL="キャンセルされました"' \
        'L_INSTALL_DEPS="インストール予定: "' \
        'L_INSTALLED_OK="PACKBOX v0.1.0 Alpha インストール成功"' \
        'L_NEXT_STEPS="次のステップ"' \
        'L_RELOAD_SHELL="シェルを再読み込み"' \
        'L_VERIFY="確認"' \
        'L_USE_DETECTOR="packager を使用"' \
        'L_BINARIES_OK="すべてのバイナリを検証しました"' \
        'L_COMPRESS_OK="圧縮: zstd -19 / xz -9e / gzip"' \
        'L_DESKTOP_OK="メニュー: ~/.local/share/applications"' \
        'L_DNS_OK="DNS サンドボックス修正を適用"' \
        'L_LANG_SAVED="言語ファイルをインストールしました"' \
        'L_MIGRATE_DONE="古いディレクトリを検出"' \
        'L_MIGRATE_MSG="古い ~/packbox があります。削除: rm -rf ~/packbox"' \
        'L_UNINSTALL_TITLE="Packbox をアンインストール"' \
        'L_UNINSTALL_SCAN="削除されるものを分析中..."' \
        'L_UNINSTALL_WILL="以下が削除されます:"' \
        'L_UNINSTALL_CONFIRM="アンインストールを続行しますか? [y/N] "' \
        'L_UNINSTALL_TYPE="確認のため大文字で DELETE と入力: "' \
        'L_UNINSTALL_MISMATCH="キャンセル (DELETE と一致しません)"' \
        'L_UNINSTALL_MODE="モード: [s]=完全, [k]=バイナリのみ, [q]=キャンセル: "' \
        'L_UNINSTALL_BIN_ONLY="バイナリとスクリプトのみ削除"' \
        'L_UNINSTALL_FULL="完全削除"' \
        'L_UNINSTALL_REMOVING="削除中"' \
        'L_UNINSTALL_REMOVED="削除済み"' \
        'L_UNINSTALL_DONE="PACKBOX をアンインストールしました"' \
        'L_UNINSTALL_FREED="解放された容量"' \
        'L_UNINSTALL_OLD_PACKBOX="古い ~/packbox も削除しますか? [y/N] "' \
        'L_UNINSTALL_BASHRC="~/.bashrc をクリーンアップ中 (バックアップ: ~/.bashrc.packbox-uninstall.bak)"' \
        'L_UNINSTALL_DESKTOP="メニュー項目を削除中"' \
        'L_UNINSTALL_ICONS="アイコンを削除中"' \
        'L_UNINSTALL_SYMLINKS="~/.local/bin のシンボリックリンクを削除中"' \
        'L_UNINSTALL_NOTHING="アンインストールするものがありません"' \
        'L_ABORT="中止されました"' \
        'L_YES="y"' \
        'L_NO="n"' \
        'L_TOTAL="合計"' \
        'L_WHAT_DO="何をしますか?"' \
        'L_1_PACK="システムアプリをパッケージ化"' \
        'L_2_LIST="インストール済みアプリを一覧表示"' \
        'L_3_GC="ガベージコレクション"' \
        'L_4_EXPORT="アプリをファイルにエクスポート"' \
        'L_5_IMPORT="ファイルからアプリをインポート"' \
        'L_6_UNINSTALL="アプリケーションをアンインストール"' \
        'L_0_EXIT="終了"' \
        'L_OPTION="オプション"' \
        'L_SELECT="選択"' \
        'L_TOP="サイズの大きいアプリ"' \
        'L_SEARCHING="スキャン中"' \
        'L_DETECTED="検出"' \
        'L_BUNDLE="バンドル"' \
        'L_PORTABLE="ポータブル"' \
        'L_MODE="モード"' \
        'L_NORMAL="通常"' \
        'L_MODULE="モジュール"' \
        'L_APP_ID="アプリ ID"' \
        'L_VERSION="バージョン"' \
        'L_DESCRIPTION="説明"' \
        'L_PACKING="パッケージ化中"' \
        'L_CONFIRM="確認しますか? [Y/n] "' \
        'L_EXEC_NOW="今すぐ実行? [y/N] "' \
        'L_CLEANUP="クリーンアップ中"' \
        'L_INSTALLED="インストール済み"' \
        'L_REMOVED="削除済み"' \
        'L_FAILED="失敗"' \
        'L_CREATE_DESKTOP="メニュー項目を作成しますか? [Y/n] "' \
        'L_SEARCH_PROMPT="検索: "' \
        'L_FILTER_MB="最小サイズ (MB): "' \
        'L_NO_RESULTS="結果なし"' \
        'L_ALL="すべて"' \
        'L_ANOTHER="もう一つ? [y/N] "' \
        'L_RUN_INSTALLER_NOW="今すぐインストーラーを実行しますか? [Y/n] "' \
        'L_DOES_NOT_EXIST="存在しません"' \
        'L_NO_SELECTION="選択なし"' \
        'L_INVALID="無効"'

    # ─── KO — 한국어 ─────────────────────────────────────────
    # EN: Korean strings.
    # ES: Cadenas en coreano.
    _w ko "한국어" \
        'L_WELCOME="Packbox 설치 프로그램"' \
        'L_MENU_INSTALL="Packbox 설치"' \
        'L_MENU_UNINSTALL="Packbox 제거"' \
        'L_MENU_EXIT="종료"' \
        'L_MENU_PROMPT="옵션 선택"' \
        'L_INSTALLER_TITLE="PACKBOX v0.1.0 Alpha — 설치 프로그램"' \
        'L_PACKAGER_TITLE="PACKBOX Packager v0.1.0 Alpha"' \
        'L_STEP1="배포판 감지 중"' \
        'L_STEP2="Go 1.22+ 설치 중"' \
        'L_STEP3="디렉터리 구조 생성 중"' \
        'L_STEP4="Go 프로젝트 생성 중"' \
        'L_STEP5="바이너리 컴파일 중"' \
        'L_STEP6="테스트 실행 중"' \
        'L_STEP7="PATH 구성 중"' \
        'L_STEP8="최종 검증"' \
        'L_CONTINUE="계속하시겠습니까? [Y/n] "' \
        'L_CANCEL="취소됨"' \
        'L_INSTALL_DEPS="설치 예정: "' \
        'L_INSTALLED_OK="PACKBOX v0.1.0 Alpha 설치 성공"' \
        'L_NEXT_STEPS="다음 단계"' \
        'L_RELOAD_SHELL="셸 다시 로드"' \
        'L_VERIFY="확인"' \
        'L_USE_DETECTOR="packager 사용"' \
        'L_BINARIES_OK="모든 바이너리 확인됨"' \
        'L_COMPRESS_OK="압축: zstd -19 / xz -9e / gzip"' \
        'L_DESKTOP_OK="메뉴: ~/.local/share/applications"' \
        'L_DNS_OK="DNS 샌드박스 수정 적용됨"' \
        'L_LANG_SAVED="언어 파일 설치됨"' \
        'L_MIGRATE_DONE="이전 디렉터리 발견"' \
        'L_MIGRATE_MSG="이전 ~/packbox가 있습니다. 삭제: rm -rf ~/packbox"' \
        'L_UNINSTALL_TITLE="Packbox 제거"' \
        'L_UNINSTALL_SCAN="삭제될 항목 분석 중..."' \
        'L_UNINSTALL_WILL="다음이 삭제됩니다:"' \
        'L_UNINSTALL_CONFIRM="제거를 진행하시겠습니까? [y/N] "' \
        'L_UNINSTALL_TYPE="확인을 위해 대문자로 DELETE 입력: "' \
        'L_UNINSTALL_MISMATCH="취소됨 (DELETE와 일치하지 않음)"' \
        'L_UNINSTALL_MODE="모드: [s]=전체, [k]=바이너리만, [q]=취소: "' \
        'L_UNINSTALL_BIN_ONLY="바이너리와 스크립트만 제거"' \
        'L_UNINSTALL_FULL="전체 제거"' \
        'L_UNINSTALL_REMOVING="제거 중"' \
        'L_UNINSTALL_REMOVED="제거됨"' \
        'L_UNINSTALL_DONE="PACKBOX 제거됨"' \
        'L_UNINSTALL_FREED="해제된 공간"' \
        'L_UNINSTALL_OLD_PACKBOX="이전 ~/packbox도 제거하시겠습니까? [y/N] "' \
        'L_UNINSTALL_BASHRC="~/.bashrc 정리 중 (백업: ~/.bashrc.packbox-uninstall.bak)"' \
        'L_UNINSTALL_DESKTOP="메뉴 항목 제거 중"' \
        'L_UNINSTALL_ICONS="아이콘 제거 중"' \
        'L_UNINSTALL_SYMLINKS="~/.local/bin 심볼릭 링크 제거 중"' \
        'L_UNINSTALL_NOTHING="제거할 항목이 없습니다"' \
        'L_ABORT="중단됨"' \
        'L_YES="y"' \
        'L_NO="n"' \
        'L_TOTAL="합계"' \
        'L_WHAT_DO="무엇을 하시겠습니까?"' \
        'L_1_PACK="시스템 앱 패키징"' \
        'L_2_LIST="설치된 앱 나열"' \
        'L_3_GC="가비지 컬렉션"' \
        'L_4_EXPORT="앱을 파일로 내보내기"' \
        'L_5_IMPORT="파일에서 앱 가져오기"' \
        'L_6_UNINSTALL="애플리케이션 제거"' \
        'L_0_EXIT="종료"' \
        'L_OPTION="옵션"' \
        'L_SELECT="선택"' \
        'L_TOP="크기 순 상위 앱"' \
        'L_SEARCHING="스캔 중"' \
        'L_DETECTED="감지됨"' \
        'L_BUNDLE="번들"' \
        'L_PORTABLE="포터블"' \
        'L_MODE="모드"' \
        'L_NORMAL="일반"' \
        'L_MODULE="모듈"' \
        'L_APP_ID="앱 ID"' \
        'L_VERSION="버전"' \
        'L_DESCRIPTION="설명"' \
        'L_PACKING="패키징 중"' \
        'L_CONFIRM="확인? [Y/n] "' \
        'L_EXEC_NOW="지금 실행? [y/N] "' \
        'L_CLEANUP="정리 중"' \
        'L_INSTALLED="설치됨"' \
        'L_REMOVED="제거됨"' \
        'L_FAILED="실패"' \
        'L_CREATE_DESKTOP="메뉴 항목을 만드시겠습니까? [Y/n] "' \
        'L_SEARCH_PROMPT="검색: "' \
        'L_FILTER_MB="최소 크기 (MB): "' \
        'L_NO_RESULTS="결과 없음"' \
        'L_ALL="전체"' \
        'L_ANOTHER="하나 더? [y/N] "' \
        'L_RUN_INSTALLER_NOW="지금 설치 프로그램을 실행하시겠습니까? [Y/n] "' \
        'L_DOES_NOT_EXIST="존재하지 않음"' \
        'L_NO_SELECTION="선택 없음"' \
        'L_INVALID="잘못됨"'
}

# ═══════════════════════════════════════════════════════════════
# EN: load_lang — load chosen language with English fallbacks.
# ES: load_lang — carga el idioma elegido con fallbacks a inglés.
#
# EN: Every key is defaulted to its English value so that a missing
#     string in a translation file never breaks the UI.
# ES: Cada clave se define con su valor en inglés, de modo que una
#     cadena faltante en un archivo de traducción nunca rompa la UI.
# ═══════════════════════════════════════════════════════════════
load_lang() {
    # EN: Source the language file if it exists.
    # ES: Carga el archivo de idioma si existe.
    local file="$PACKBOX_LANG_DIR/${L_LANG_CODE}.sh"
    [[ -f "$file" ]] && source "$file"

    : "${L_LANG_NAME:=English}"
    : "${L_WELCOME:=Packbox installer}"
    : "${L_MENU_INSTALL:=Install Packbox}"
    : "${L_MENU_UNINSTALL:=Uninstall Packbox}"
    : "${L_MENU_EXIT:=Exit}"
    : "${L_MENU_PROMPT:=Select option}"
    : "${L_INSTALLER_TITLE:=PACKBOX v0.1.0 Alpha — Installer}"
    : "${L_PACKAGER_TITLE:=PACKBOX Packager v0.1.0 Alpha}"
    : "${L_STEP1:=Detecting distribution}"
    : "${L_STEP2:=Installing Go 1.22+}"
    : "${L_STEP3:=Creating directory structure}"
    : "${L_STEP4:=Generating Go project}"
    : "${L_STEP5:=Compiling binaries}"
    : "${L_STEP6:=Running tests}"
    : "${L_STEP7:=Configuring PATH}"
    : "${L_STEP8:=Final verification}"
    : "${L_CONTINUE:=Continue? [Y/n] }"
    : "${L_CANCEL:=Cancelled}"
    : "${L_INSTALL_DEPS:=Will install: }"
    : "${L_INSTALLED_OK:=PACKBOX v0.1.0 Alpha INSTALLED SUCCESSFULLY}"
    : "${L_NEXT_STEPS:=Next steps}"
    : "${L_RELOAD_SHELL:=Reload your shell}"
    : "${L_VERIFY:=Verify}"
    : "${L_USE_DETECTOR:=Use the packager}"
    : "${L_BINARIES_OK:=All binaries verified}"
    : "${L_COMPRESS_OK:=Compression: zstd -19 / xz -9e / gzip}"
    : "${L_DESKTOP_OK:=Desktop menu: ~/.local/share/applications}"
    : "${L_DNS_OK:=DNS sandbox fix applied}"
    : "${L_LANG_SAVED:=Language files installed}"
    : "${L_MIGRATE_DONE:=Old directory found}"
    : "${L_MIGRATE_MSG:=Old ~/packbox found. Remove: rm -rf ~/packbox}"
    : "${L_UNINSTALL_TITLE:=Uninstall Packbox}"
    : "${L_UNINSTALL_SCAN:=Scanning what will be removed...}"
    : "${L_UNINSTALL_WILL:=Will remove the following:}"
    : "${L_UNINSTALL_CONFIRM:=Proceed with uninstall? [s/N] }"
    : "${L_UNINSTALL_TYPE:=Type DELETE in caps to confirm: }"
    : "${L_UNINSTALL_MISMATCH:=Cancelled (input did not match DELETE)}"
    : "${L_UNINSTALL_MODE:=Mode: [s]=full, [k]=binaries only, [q]=cancel: }"
    : "${L_UNINSTALL_BIN_ONLY:=Removing binaries and scripts only}"
    : "${L_UNINSTALL_FULL:=Full removal}"
    : "${L_UNINSTALL_REMOVING:=Removing}"
    : "${L_UNINSTALL_REMOVED:=Removed}"
    : "${L_UNINSTALL_DONE:=PACKBOX UNINSTALLED}"
    : "${L_UNINSTALL_FREED:=Space freed}"
    : "${L_UNINSTALL_OLD_PACKBOX:=Also remove old ~/packbox? [s/N] }"
    : "${L_UNINSTALL_BASHRC:=Cleaning ~/.bashrc (backup: ~/.bashrc.packbox-uninstall.bak)}"
    : "${L_UNINSTALL_DESKTOP:=Removing menu entries}"
    : "${L_UNINSTALL_ICONS:=Removing icons}"
    : "${L_UNINSTALL_SYMLINKS:=Removing ~/.local/bin symlinks}"
    : "${L_UNINSTALL_NOTHING:=Nothing to uninstall}"
    : "${L_ABORT:=Aborted}"
    : "${L_YES:=y}"
    : "${L_NO:=n}"
    : "${L_TOTAL:=Total}"
    : "${L_WHAT_DO:=What do you want to do?}"
    : "${L_1_PACK:=Pack system application}"
    : "${L_2_LIST:=List installed apps}"
    : "${L_3_GC:=Garbage collection}"
    : "${L_4_EXPORT:=Export app to file}"
    : "${L_5_IMPORT:=Import app from file}"
    : "${L_6_UNINSTALL:=Uninstall application}"
    : "${L_0_EXIT:=Exit}"
    : "${L_OPTION:=Option}"
    : "${L_SELECT:=Selection}"
    : "${L_TOP:=Top apps by size}"
    : "${L_SEARCHING:=Scanning}"
    : "${L_DETECTED:=Detected}"
    : "${L_BUNDLE:=Bundle}"
    : "${L_PORTABLE:=Portable}"
    : "${L_MODE:=Mode}"
    : "${L_NORMAL:=Normal}"
    : "${L_MODULE:=Module}"
    : "${L_APP_ID:=App ID}"
    : "${L_VERSION:=Version}"
    : "${L_DESCRIPTION:=Description}"
    : "${L_PACKING:=Packaging}"
    : "${L_CONFIRM:=Confirm? [Y/n] }"
    : "${L_EXEC_NOW:=Run now? [y/N] }"
    : "${L_CLEANUP:=Cleaning up}"
    : "${L_INSTALLED:=Installed}"
    : "${L_REMOVED:=Removed}"
    : "${L_FAILED:=Failed}"
    : "${L_CREATE_DESKTOP:=Create menu entry? [Y/n] }"
    : "${L_SEARCH_PROMPT:=Search: }"
    : "${L_FILTER_MB:=Minimum size in MB: }"
    : "${L_NO_RESULTS:=No results}"
    : "${L_ALL:=all}"
    : "${L_ANOTHER:=Another? [s/N] }"
    : "${L_RUN_INSTALLER_NOW:=Run installer now? [S/n] }"
    : "${L_DOES_NOT_EXIST:=Does not exist}"
    : "${L_NO_SELECTION:=No selection}"
    : "${L_INVALID:=Invalid}"
}

# ═══════════════════════════════════════════════════════════════
# EN: t — translator.
# ES: t — traductor.
#
# EN: Usage: t L_SOME_KEY → prints the localized value, or the key
#     name itself if the variable is unset (indirect expansion).
# ES: Uso: t L_ALGUNA_CLAVE → imprime el valor localizado, o el
#     nombre de la clave si la variable no está definida.
# ═══════════════════════════════════════════════════════════════
t() {
    local k="${1:-}"
    local v="${!k:-}"
    echo "${v:-$k}"
}
