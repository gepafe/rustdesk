#!/usr/bin/env bash
# =============================================================================
# actualizar.sh - CLIENTE RUSTDESK PERSONALIZADO EN UN SOLO PASO
# -----------------------------------------------------------------------------
# Cuando RustDesk oficial saque una versión nueva, ejecuta:
#     ./actualizar.sh
# y este script hace TODO automáticamente:
#   1. Baja la última versión del repositorio oficial (upstream).
#   2. Le aplica/actualiza las personalizaciones (CM oculta, sin actualizaciones
#      automáticas e importador masivo de equipos en Favoritos). Se mantiene el
#      nombre y logo originales de RustDesk.
#   3. Compila en GitHub Actions (gratis, en la nube).
#   4. Espera a que termine.
#   5. Descarga el .exe de Windows a tu PC.
#
# Único requisito: gh autenticado con permisos de repo y workflow.
# =============================================================================
set -euo pipefail

# -----------------------------------------------------------------------------
# Configuración (cámbiala si hace falta)
# -----------------------------------------------------------------------------
FORK="gepafe/rustdesk"          # tu fork
UPSTREAM="rustdesk/rustdesk"    # repo oficial (no tocar)
BRANCH="master"
WORKDIR="${WORKDIR:-rustdesk}"
DEST="${DEST:-$(pwd)}"          # carpeta donde dejar el .exe (por defecto: actual)
TAG="v1.5.0-custom-$(date +%Y%m%d%H%M)"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
say(){ echo -e "${GREEN}[actualizar]${NC} $1"; }
warn(){ echo -e "${YELLOW}[aviso]${NC} $1"; }
die(){ echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

[ -x "$(command -v gh)" ] || die "gh no está instalado/autenticado."
[ -x "$(command -v git)" ] || die "git no está instalado."

# Construye la URL de push con credenciales. Prioriza GH_TOKEN; si no, usa el
# helper de credenciales de git (gh auth setup-git). Recomendado:
#     gh auth login --web --scopes "repo, workflow"
#     gh auth setup-git
TOKEN="${GH_TOKEN:-}"
if [ -n "$TOKEN" ]; then
  PUSH_URL="https://gepafe:${TOKEN}@github.com/${FORK}.git"
else
  PUSH_URL="https://github.com/${FORK}.git"
fi

# -----------------------------------------------------------------------------
# 1. Asegurar el clone local limpio
# -----------------------------------------------------------------------------
if [ ! -d "${WORKDIR}/.git" ]; then
  say "Clonando el fork..."
  git clone "https://github.com/${FORK}.git" "${WORKDIR}"
fi
cd "${WORKDIR}"
git remote remove upstream 2>/dev/null || true
git remote add upstream "https://github.com/${UPSTREAM}.git"

say "Descargando la última versión oficial (upstream)..."
git fetch upstream --tags --prune || die "Fallo al descargar upstream (revisa conexión)."

# Sincronizar SIN perder las personalizaciones: el master del fork ya las
# contiene como commits, así que FUSIONAMOS upstream. (Antes se hacía
# `reset --hard upstream/master`, que borraba los commits propios, incluido el
# importador masivo de equipos.)
git checkout "$BRANCH" 2>/dev/null || git checkout -b "$BRANCH" "origin/$BRANCH"
if git merge upstream/"${BRANCH}" --no-edit; then
  say "Sincronizado con la última versión oficial (personalizaciones conservadas)."
else
  git merge --abort 2>/dev/null || true
  die "Conflicto al fusionar upstream. Resuélvelo a mano en $WORKDIR y vuelve a ejecutar."
fi

# -----------------------------------------------------------------------------
# 2. Aplicar las personalizaciones (idempotente: solo si faltan)
# -----------------------------------------------------------------------------
say "Aplicando personalizaciones..."

F_MODELS="flutter/lib/models/server_model.dart"
F_MAIN="flutter/lib/main.dart"
F_SETTING="flutter/lib/desktop/pages/desktop_setting_page.dart"
F_UPDATER="src/updater.rs"

# --- 2.1 server_model.dart: hideCm = true por defecto ---
if grep -q 'bool hideCm = false;' "$F_MODELS"; then
  perl -0pi -e 's/bool hideCm = false;/bool _hideCm = true;\nbool get hideCm => _hideCm;\nset hideCm(bool value) {\n  if (_hideCm != value) {\n    _hideCm = value;\n    notifyListeners();\n  }\n}/' "$F_MODELS"
  say "  server_model.dart: hideCm activado."
else
  grep -q 'bool _hideCm = true;' "$F_MODELS" && say "  server_model.dart: ya activado." || warn "  server_model.dart: patrón inesperado, revísalo."
fi

# --- 2.2 main.dart: forzar ocultar la ventana CM ---
if ! grep -q 'forzar ocultar la ventana de gestión de conexiones' "$F_MAIN"; then
  perl -0pi -e 's/final hide = await bind\.cmGetConfig\(name: "hide_cm"\) == '\''true'\'';.*?}\n  setResizable\(false\);/\/\/ Cliente personalizado: forzar ocultar la ventana de gestión de conexiones.\n  gFFI.serverModel.hideCm = true;\n  await hideCmWindow(isStartup: true);\n  setResizable(false);/s' "$F_MAIN"
  grep -q 'forzar ocultar la ventana de gestión de conexiones' "$F_MAIN" && say "  main.dart: ventana CM forzada a oculta." || warn "  main.dart: no se pudo parchear, revisa runConnectionManagerScreen."
else
  say "  main.dart: ya modificado."
fi

# --- 2.3 desktop_setting_page.dart: descomentar y bloquear el checkbox ---
if grep -q '^            // if (usePassword)$' "$F_SETTING" || grep -q '//   hide_cm(!locked)' "$F_SETTING"; then
  perl -0pi -e 's#// if \(usePassword\)\n//   hide_cm\(!locked\)\.marginOnly\(left: _kContentHSubMargin - 6\),#if (usePassword)\n              IgnorePointer(\n                  ignoring: true,\n                  child: hide_cm(false)\n                      .marginOnly(left: _kContentHSubMargin - 6)),#' "$F_SETTING"
  grep -q 'IgnorePointer' "$F_SETTING" && say "  desktop_setting_page.dart: checkbox descomentado y bloqueado." || warn "  desktop_setting_page.dart: no se pudo parchear."
else
  grep -q 'IgnorePointer' "$F_SETTING" && say "  desktop_setting_page.dart: ya bloqueado." || warn "  desktop_setting_page.dart: patrón inesperado, revísalo."
fi

# --- 2.4 updater.rs: desactivar actualizaciones automáticas ---
if grep -q 'if !(manually || config::Config::get_bool_option(keys::OPTION_ALLOW_AUTO_UPDATE))' "$F_UPDATER"; then
  perl -0pi -e 's/if !\(manually \|\| config::Config::get_bool_option\(keys::OPTION_ALLOW_AUTO_UPDATE\)\) \{/\/\/ Cliente personalizado: deshabilitar las actualizaciones automáticas.\n    if !manually {\n        return Ok(());\n    }\n    if !config::Config::get_bool_option(keys::OPTION_ALLOW_AUTO_UPDATE) {/' "$F_UPDATER"
  grep -q 'if !manually {' "$F_UPDATER" && say "  updater.rs: actualizaciones automáticas desactivadas." || warn "  updater.rs: no se pudo parchear."
else
  grep -q 'Cliente personalizado: deshabilitar' "$F_UPDATER" && say "  updater.rs: ya desactivado." || warn "  updater.rs: patrón inesperado, revísalo."
fi

# --- 2.5 verificar que el importador masivo de equipos sigue presente ---
if grep -q 'showImportPeersBulkDialog' flutter/lib/common/widgets/peer_tab_page.dart 2>/dev/null; then
  say "  importador masivo de equipos: presente."
else
  warn "  importador masivo: NO encontrado en la barra. Una versión nueva de RustDesk pudo cambiar el archivo; revísalo."
fi

# --- 2.6 verificar el binding que crea la ficha del equipo importado ---
if grep -q 'main_set_peer_info' src/flutter_ffi.rs 2>/dev/null \
   && grep -q 'pub fn set_peer_info' src/ui_interface.rs 2>/dev/null; then
  say "  ficha de equipo importado (main_set_peer_info): presente."
else
  warn "  main_set_peer_info: NO encontrado. Revisa src/flutter_ffi.rs y src/ui_interface.rs."
fi

# --- 2.7 verificar la pantalla de bloqueo con PIN al abrir la app ---
if grep -q 'PinLockGate' flutter/lib/main.dart 2>/dev/null \
   && [ -f flutter/lib/common/widgets/pin_lock.dart ]; then
  say "  bloqueo con PIN al abrir: presente."
else
  warn "  bloqueo con PIN: NO encontrado. Revisa flutter/lib/common/widgets/pin_lock.dart y main.dart."
fi

# -----------------------------------------------------------------------------
# 3. Commit, tag y push
# -----------------------------------------------------------------------------
git add -A
if git diff --cached --quiet; then
  say "Sin cambios de código nuevos (ya estaba personalizado)."
else
  git commit -m "feat: personalizar cliente (CM oculta y sin actualizaciones automáticas)" >/dev/null
  say "Cambios confirmados."
fi
git push "$PUSH_URL" "$BRANCH" >/dev/null 2>&1 || warn "No se pudo subir master (revisa token)."
git tag -a "$TAG" -m "Cliente personalizado" >/dev/null 2>&1 || die "El tag $TAG ya existe. Borra el tag local o cambia TAG."
git push "$PUSH_URL" "$TAG" >/dev/null 2>&1 || die "No se pudo subir el tag (revisa token)."
say "Subido tag $TAG."

# -----------------------------------------------------------------------------
# 4. Disparar el build en GitHub Actions
# -----------------------------------------------------------------------------
say "Lanzando la compilación en GitHub Actions (puede tardar 40-90 min)..."
RUN_URL=$(gh workflow run flutter-tag.yml --repo "$FORK" --ref "$TAG")
RUN_ID=$(gh run list --repo "$FORK" --limit 1 --json databaseId --jq '.[0].databaseId')
say "Build lanzado: run #$RUN_ID"

# -----------------------------------------------------------------------------
# 5. Esperar a que termine
# -----------------------------------------------------------------------------
say "Esperando a que termine la compilación..."
gh run watch "$RUN_ID" --repo "$FORK" --exit-status >/dev/null 2>&1 || die "La compilación falló. Revisa: gh run view $RUN_ID --repo $FORK"

# -----------------------------------------------------------------------------
# 6. Descargar el .exe de Windows
# -----------------------------------------------------------------------------
mkdir -p "$DEST"
say "Descargando el instalador de Windows x64..."
cd "$DEST"
gh release download "$TAG" --repo "$FORK" --pattern "*.x86_64.exe" --clobber 2>/dev/null \
  || gh release download "$TAG" --repo "$FORK" --pattern "*.exe" --clobber 2>/dev/null \
  || die "No se pudo descargar el .exe."

EXE=$(ls -1 ./*.exe 2>/dev/null | grep -i x86_64 | head -1 || ls -1 ./*.exe 2>/dev/null | head -1)
say "¡LISTO! Tu cliente personalizado está en: $DEST/$EXE"
say "Distribúyelo a los 20 equipos. Proceso completado."