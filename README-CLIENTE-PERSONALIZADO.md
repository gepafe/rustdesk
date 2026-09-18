# Cliente RustDesk Personalizado - Ventana CM Oculta

Cliente personalizado de RustDesk para Windows que oculta la **ventana de Gestión
de Conexiones (CM)** por defecto, para que nunca aparezca en el equipo remoto al
prestar soporte.

## ¿Qué hace este cliente?

En las versiones recientes de RustDesk (1.2.3+) la opción "Ocultar ventana de
gestión de conexiones" se eliminó de la interfaz. Este cliente la restaura y la
**fuerza activada por defecto** de forma que la ventana CM no aparece en el equipo
remoto durante una sesión de soporte.

Modificaciones aplicadas sobre el código fuente:

1. **`flutter/lib/models/server_model.dart`** - el valor por defecto de `hideCm`
   pasa a `true` y se notifica a la UI cuando cambia.
2. **`flutter/lib/main.dart`** - al iniciar la sesión de conexión se fuerza siempre
   `hideCm = true` y se oculta la ventana CM.
3. **`flutter/lib/desktop/pages/desktop_setting_page.dart`** - se descomenta el
   checkbox "Ocultar ventana de gestión de conexiones" y se bloquea con
   `IgnorePointer` para que no pueda desactivarse desde la interfaz.

## Instalación en los equipos del equipo (20 equipos)

1. Descarga el instalador `.exe` desde el release del fork:
   - Ve a **Releases** en el repositorio del fork
     `https://github.com/gepafe/rustdesk/releases`
   - Descarga el instalador de Windows correspondiente a tu arquitectura
     (`x86_64` para la mayoría).
2. Ejecuta el instalador en cada equipo con permisos de administrador.
3. Al terminar, RustDesk queda instalado con la ventana CM oculta por defecto.

### Desactivar las actualizaciones automáticas

Es crítico que los clientes **no se actualicen solos**, porque una actualización
eliminaría la personalización. Para desactivarlas:

1. Abre RustDesk en el equipo.
2. Ve a **Configuración (⚙)**.
3. En la pestaña **General**, desmarca la opción
   **"Actualizaciones automáticas"** (o "Automatically check update on start").
4. Confirma el cambio.

Otra alternativa es bloquear el dominio de actualización en el firewall/DNS del
equipo (puede ser necesario si los usuarios no tienen acceso a la configuración).

## Regenerar el cliente cuando salga una nueva versión de RustDesk

Cuando el repositorio oficial publique una nueva versión, repite el proceso con el
script automatizado:

1. Clona tu fork (o usa el existente).
2. Ejecuta el script de reconstrucción:

   ```bash
   ./rebuild.sh
   ```

3. El script:
   - Sincroniza el fork con `upstream` (el repo oficial).
   - Re-aplica los parches (las 3 modificaciones al código).
   - Confirma los cambios y los sube.
   - Crea un tag con marca de tiempo (`vX.Y.Z-custom-<fecha>`).
   - Dispara la compilación automática en GitHub Actions.
4. Cuando termine, descarga el nuevo `.exe` desde el release y distribúyelo.

> Nota: si la estructura del código cambió en una versión nueva de RustDesk, el
> script puede no aplicar los parches de forma limpia. En ese caso revisa los
> archivos modificados y adapta los cambios manualmente según las secciones de
> arriba.

## Proceso manual (referencia)

Para regenerar a mano sin el script:

```bash
gh repo fork rustdesk/rustdesk --clone=false --remote=false
git clone https://github.com/gepafe/rustdesk.git
cd rustdesk
git remote add upstream https://github.com/rustdesk/rustdesk.git
git fetch upstream
git checkout master
git merge upstream/master
# aplicar las 3 modificaciones al código (ver sección "¿Qué hace este cliente?")
git add -A
git commit -m "feat: forzar ocultar ventana CM por defecto en cliente personalizado"
git push origin master
git tag -a v1.4.0-custom-$(date +%Y%m%d%H%M) -m "Cliente personalizado con ventana CM oculta"
git push origin v1.4.0-custom-$(date +%Y%m%d%H%M)
# monitorear con: gh run list --repo gepafe/rustdesk
```

## Repositorio del fork

- **URL del fork:** https://github.com/gepafe/rustdesk
- **Repositorio oficial (upstream):** https://github.com/rustdesk/rustdesk