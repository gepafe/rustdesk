#!/usr/bin/env bash
# =============================================================================
# rebuild.sh - Regenera el cliente RustDesk personalizado con la ventana CM
# oculta por defecto, tomando como base el fork existente.
#
# Prerrequisitos:
#   - git, gh (GitHub CLI autenticado con permisos repo y workflow)
#   - Fork existente en GitHub (por defecto: gepafe/rustdesk)
#
# Uso:
#   ./rebuild.sh                 # usa el fork por defecto y un tag con timestamp
#   FORK=otro/usuario ./rebuild.sh
#   TAG=v1.4.0-1 ./rebuild.sh    # usa un tag fijo
# =============================================================================
set -euo pipefail

# -----------------------------------------------------------------------------
# Configuración
# -----------------------------------------------------------------------------
FORK="${FORK:-gepafe/rustdesk}"
UPSTREAM="rustdesk/rustdesk"
BRANCH="master"
WORKDIR="${WORKDIR:-rustdesk}"

# Si no se indica un tag, se genera uno con marca de tiempo (el sufijo debe ser
# numérico para que GitHub Actions lo reconozca, p. ej. v1.4.0-202609181015).
TAG="${TAG:-v1.4.0-custom-$(date +%Y%m%d%H%M)}"

FORK_URL="https://github.com/${FORK}.git"
UPSTREAM_URL="https://github.com/${UPSTREAM}.git"

# -----------------------------------------------------------------------------
# Colores
# -----------------------------------------------------------------------------
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}[rebuild] Fork: ${FORK}${NC}"
echo -e "${GREEN}[rebuild] Tag:  ${TAG}${NC}"

# -----------------------------------------------------------------------------
# 1. Asegurar la existencia del clone local
# -----------------------------------------------------------------------------
if [ ! -d "${WORKDIR}/.git" ]; then
    echo -e "${YELLOW}[rebuild] Clonando fork...${NC}"
    git clone "${FORK_URL}" "${WORKDIR}"
fi
cd "${WORKDIR}"

# Asegurar el remote upstream
if ! git remote | grep -q '^upstream$'; then
    git remote add upstream "${UPSTREAM_URL}"
fi

# -----------------------------------------------------------------------------
# 2. Sincronizar con upstream (repositorio oficial)
# -----------------------------------------------------------------------------
echo -e "${YELLOW}[rebuild] Sincronizando con upstream...${NC}"
git fetch upstream
git checkout "${BRANCH}" 2>/dev/null || git checkout -b "${BRANCH}" upstream/"${BRANCH}"
git merge upstream/"${BRANCH}" --no-edit || true
git push origin "${BRANCH}"

# -----------------------------------------------------------------------------
# 3. Re-aplicar los parches
# -----------------------------------------------------------------------------
echo -e "${YELLOW}[rebuild] Aplicando modificaciones al código...${NC}"

# --- Parche 1: server_model.dart ---
# Valor por defecto de hideCm = true (ya con getter/setter)
SERVER_MODEL="flutter/lib/models/server_model.dart"
if grep -q 'bool hideCm = false;' "${SERVER_MODEL}"; then
    perl -0pi -e 's/bool hideCm = false;/bool _hideCm = true;\nbool get hideCm => _hideCm;\nset hideCm(bool value) {\n  if (_hideCm != value) {\n    _hideCm = value;\n    notifyListeners();\n  }\n}/' "${SERVER_MODEL}"
    echo -e "${GREEN}[rebuild] server_model.dart: hideCm por defecto true aplicado.${NC}"
elif grep -q 'bool _hideCm = true;' "${SERVER_MODEL}"; then
    echo -e "${GREEN}[rebuild] server_model.dart: ya modificado, sin cambios.${NC}"
else
    echo -e "${RED}[rebuild] ATENCIÓN: server_model.dart no tiene el patrón esperado. Revisa manualmente.${NC}"
fi

# --- Parche 2: main.dart ---
# Forzar ocultar la ventana CM al iniciar la sesión de conexión
MAIN_DART="flutter/lib/main.dart"
if grep -q 'runConnectionManagerScreen' "${MAIN_DART}" && ! grep -q 'forzar ocultar la ventana de gestión de conexiones' "${MAIN_DART}"; then
    echo -e "${RED}[rebuild] ATENCIÓN: main.dart no tiene la modificación de la ventana CM. Revisa manualmente runConnectionManagerScreen.${NC}"
else
    echo -e "${GREEN}[rebuild] main.dart: verificado.${NC}"
fi

# --- Parche 3: desktop_setting_page.dart ---
# Descomentar y bloquear el checkbox "Ocultar ventana de gestión de conexiones"
SETTINGS_PAGE="flutter/lib/desktop/pages/desktop_setting_page.dart"
if grep -q 'IgnorePointer' "${SETTINGS_PAGE}" && grep -q 'hide_cm(false)' "${SETTINGS_PAGE}"; then
    echo -e "${GREEN}[rebuild] desktop_setting_page.dart: checkbox ya descomentado y bloqueado.${NC}"
else
    echo -e "${RED}[rebuild] ATENCIÓN: desktop_setting_page.dart no tiene el checkbox bloqueado. Revisa manualmente.${NC}"
fi

# -----------------------------------------------------------------------------
# 4. Commit y push
# -----------------------------------------------------------------------------
if ! git diff --quiet; then
    echo -e "${YELLOW}[rebuild] Realizando commit...${NC}"
    git add -A
    git commit -m "feat: forzar ocultar ventana CM por defecto en cliente personalizado"
    git push origin "${BRANCH}"
else
    echo -e "${GREEN}[rebuild] Sin cambios pendientes de commit.${NC}"
fi

# -----------------------------------------------------------------------------
# 5. Crear tag y disparar la compilación
# -----------------------------------------------------------------------------
echo -e "${YELLOW}[rebuild] Creando y subiendo el tag ${TAG}...${NC}"
git tag -a "${TAG}" -m "Cliente personalizado con ventana CM oculta por defecto"
git push origin "${TAG}" || {
    echo -e "${RED}[rebuild] El tag ya existe. Intenta de nuevo con TAG=... nuevo.${NC}"
    exit 1
}

# -----------------------------------------------------------------------------
# 6. Monitorear
# -----------------------------------------------------------------------------
echo -e "${GREEN}[rebuild] Tag subido. La compilación se ejecuta en GitHub Actions.${NC}"
echo -e "${GREEN}[rebuild] Para monitorear:${NC}"
echo -e "  gh run list --repo ${FORK} --limit 5"
echo -e "  gh run watch --repo ${FORK}"
echo -e "${GREEN}[rebuild] Para descargar el ejecutable cuando termine:${NC}"
echo -e "  gh release download ${TAG} --repo ${FORK} --pattern \"*.exe\""

echo -e "${GREEN}[rebuild] ¡Proceso completado! Tag ${TAG} en https://github.com/${FORK}/releases${NC}"