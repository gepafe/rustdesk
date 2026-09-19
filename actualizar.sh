#!/usr/bin/env bash
# =============================================================================
# actualizar.sh - CLIENTE VITALFIX EN UN SOLO PASO
# -----------------------------------------------------------------------------
# Cuando RustDesk oficial saque una versión nueva, ejecuta:
#     ./actualizar.sh
# y este script hace TODO automáticamente:
#   1. Baja la última versión del repositorio oficial (upstream).
#   2. Le aplica las personalizaciones VITALFIX (CM oculta, sin actualizaciones,
#      marca VITALFIX).
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

# Reset limpio a la última versión oficial (descarta todo lo anterior).
git reset --hard upstream/"${BRANCH}" || die "Fallo al sincronizar con upstream."

# -----------------------------------------------------------------------------
# 2. Aplicar las personalizaciones VITALFIX (idempotente: solo si faltan)
# -----------------------------------------------------------------------------
say "Aplicando personalizaciones VITALFIX..."

F_MODELS="flutter/lib/models/server_model.dart"
F_MAIN="flutter/lib/main.dart"
F_SETTING="flutter/lib/desktop/pages/desktop_setting_page.dart"
F_UPDATER="src/updater.rs"
F_COMMON="src/common.rs"
F_CARGO="Cargo.toml"

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
  perl -0pi -e 's/if !\(manually \|\| config::Config::get_bool_option\(keys::OPTION_ALLOW_AUTO_UPDATE\)\) \{/\/\/ Cliente personalizado VITALFIX: deshabilitar las actualizaciones automáticas.\n    if !manually {\n        return Ok(());\n    }\n    if !config::Config::get_bool_option(keys::OPTION_ALLOW_AUTO_UPDATE) {/' "$F_UPDATER"
  grep -q 'if !manually {' "$F_UPDATER" && say "  updater.rs: actualizaciones automáticas desactivadas." || warn "  updater.rs: no se pudo parchear."
else
  grep -q 'Cliente personalizado VITALFIX: deshabilitar' "$F_UPDATER" && say "  updater.rs: ya desactivado." || warn "  updater.rs: patrón inesperado, revísalo."
fi

# --- 2.5 common.rs: nombre de la app = VITALFIX ---
if grep -q 'format!(\"{}\", get_custom_client_name())' "$F_COMMON" || grep -q 'get_custom_client_name' "$F_COMMON"; then
  # Caso genérico: reemplaza la llamada que devuelve el nombre por "VITALFIX".
  perl -0pi -e 's/fn get_app_name\(\) -> String \{[^{]*\{.*?\n    \}\n/fn get_app_name() -> String {\n    \/\/ Cliente personalizado VITALFIX: nombre de la aplicación fijo.\n    "VITALFIX".to_owned()\n}\n/s' "$F_COMMON"
  grep -q 'Cliente personalizado VITALFIX: nombre de la aplicación fijo' "$F_COMMON" && say "  common.rs: nombre de la app = VITALFIX." || warn "  common.rs: no se pudo reescribir get_app_name, revísalo."
else
  grep -q 'Cliente personalizado VITALFIX: nombre de la aplicación fijo' "$F_COMMON" && say "  common.rs: ya modificado." || warn "  common.rs: patrón inesperado, revísalo."
fi

# --- 2.6 Cargo.toml: metadatos VITALFIX ---
if grep -q 'ProductName = "RustDesk"' "$F_CARGO"; then
  perl -0pi -e 's/LegalCopyright = "[^"]*"/LegalCopyright = "Copyright © 2026 VITALFIX. Todos los derechos reservados."/; s/ProductName = "RustDesk"/ProductName = "VITALFIX"/; s/FileDescription = "RustDesk Remote Desktop"/FileDescription = "VITALFIX Remote Desktop"/; s/OriginalFilename = "rustdesk\.exe"/OriginalFilename = "vitalfix.exe"/' "$F_CARGO"
  grep -q 'ProductName = "VITALFIX"' "$F_CARGO" && say "  Cargo.toml: metadatos VITALFIX." || warn "  Cargo.toml: no se pudo parchear."
else
  grep -q 'ProductName = "VITALFIX"' "$F_CARGO" && say "  Cargo.toml: ya modificado." || warn "  Cargo.toml: patrón inesperado, revísalo."
fi

# -----------------------------------------------------------------------------
# 3. Commit, tag y push
# -----------------------------------------------------------------------------
git add -A
if git diff --cached --quiet; then
  say "Sin cambios de código nuevos (ya estaba personalizado)."
else
  git commit -m "feat: personalizar cliente con marca VITALFIX y desactivar actualizaciones automáticas" >/dev/null
  say "Cambios confirmados."
fi
git push "$PUSH_URL" "$BRANCH" >/dev/null 2>&1 || warn "No se pudo subir master (revisa token)."
git tag -a "$TAG" -m "Cliente VITALFIX" >/dev/null 2>&1 || die "El tag $TAG ya existe. Borra el tag local o cambia TAG."
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
say "¡LISTO! Tu cliente VITALFIX está en: $DEST/$EXE"
say "Distribúyelo a los 20 equipos. Proceso completado."