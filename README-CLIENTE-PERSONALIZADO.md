# Cliente personalizado (fork gepafe/rustdesk)

Fork de RustDesk 1.5 adaptado para uso propio. Todo lo personalizado vive en
`flutter/lib` y `src/`; `libs/hbb_common` es submódulo oficial y NO se toca.

## Personalizaciones

- **Ventana CM no se abre sola**: al llegar una conexión no aparece la ventana
  principal (`flutter/lib/models/server_model.dart`, `addConnection`/`_addTab`).
- **Sin icono de bandeja en Windows**: no hay botón derecho → "Detener servicio"
  (`src/tray.rs`, `start_tray` retorna en Windows).
- **PIN de app unificado** (`flutter/lib/common/widgets/pin_lock.dart`): bloquea
  la UI al abrir, al desbloquear Windows, al iniciar/cerrar sesión y al volver
  de suspensión (eventos de Windows, sin polling: `src/platform/windows.rs`,
  `spawn_resume_watcher`). Guardado como hash `v1:salt:sha256` en la opción
  local `app-lock-pin`; el PIN queda en memoria para cifrar la sync. Las
  pestañas Seguridad/Red de Ajustes piden ese mismo PIN.
- **PIN 777 por equipo**: casilla `USUARIO PRIVADO` en Ajustes → Seguridad
  (opción del servicio `private-user`); viaja en el evento
  `set_multiple_windows_session` (`src/flutter.rs`) y el diálogo
  (`flutter/lib/common/widgets/dialog.dart`) pide la clave 777 **solo según la
  casilla**: viene tildada por defecto (sin tocar = pide la clave; `option2bool`
  trata `""` como true) y un `N` explícito (casilla quitada) hace que **nunca**
  pida. La regla vieja por nombre (`PC*`/`P<n>` sin clave) fue eliminada — era
  la causa de que PCs con sesión `FARMACIA`/`PAOLA`/`CAJA` siguieran pidiendo
  777 con el tilde quitado. Clave: `kOptionPrivateUser` en
  `flutter/lib/consts.dart`. La bandera
  la publica la PC REMOTA en `platform_additions` (`src/server/connection.rs`,
  `on_remote_authorized`), el controlador la guarda en
  `crate::ui_interface::REMOTE_PRIVATE_USER` (`src/ui_session_interface.rs`,
  `handle_peer_info`) y `flutter.rs` la usa al armar el evento (antes leía la
  opción local del controlador = nunca se pedía 777; el static NO puede vivir en
  `flutter.rs` porque el job i686 compila sin la feature `flutter`). Requiere
  "Compartir sesiones RDP" activo en la PC remota.
- **Modo vista por acción**: doble clic/clic siempre controla (limpia
  `view_only`); `VER SOLAMENTE` siempre abre en vista; el botón de la barra de
  sesión no se guarda (`peer_card.dart` `_connectControl`, `model.dart`
  `setViewOnly(peerId, false)`).
- **Sin clics fantasma**: mientras se elige sesión de Windows, el input se
  bloquea en el FFI de la sesión (`inputBlocked`; gates en
  `flutter/lib/models/input_model.dart`: `inputKey`, `scroll`, `sendMouse`,
  `handleMouse`).
- **Botón derecho fantasma (fix de raíz)**: la PC remota no debe recibir ninguna
  acción de mouse o teclado que el usuario no haya hecho. El cliente lo cumplía
  casi siempre, pero no al conectar: al llegar la primera imagen se dispara
  `updateViewStyle()`/`updateScrollStyle()` → `setDisplay()` →
  `inputModel.refreshMousePos()`, que le mandaba un movimiento del mouse con la
  posición del puntero que estaba sobre la lista, no sobre el equipo. Además el
  estado interno de botones (`_lastButtons`) se actualizaba en `_getMouseEvent()`
  aunque el evento se descartara después (`isInputBlocked` con el 777 abierto, o
  antes de que el cursor remoto tome control), con lo cual el cliente quedaba
  creyendo que tenía un botón apretado que el remoto nunca recibió. Y la máscara
  de botones se restaba como si fuera un número (`evt.buttons - _lastButtons`), de
  modo que una transición que no era un solo botón (`3 - 1 = 2`, o sea derecho)
  mandaba un `down` del botón equivocado. El fix está entero en
  `flutter/lib/models/input_model.dart` y aplica una sola regla:
  (1) bandera `_inputStarted` por sesión: hasta que el usuario no hace un gesto
  real sobre la imagen (o escribe, o gira la rueda) no sale NADA hacia el
  remoto, ni al conectar ni al aceptar el 777; (2) `isInputBlocked` se chequea
  antes de tocar `_lastButtons`, para que el estado del cliente solo avance si el
  evento se mandó de verdad; (3) la máscara se compara bit a bit con
  `_firstMouseButton` y un movimiento nunca inventa un botón apretado. No hace
  falta red de seguridad en la PC remota: con la regla anterior el remoto solo
  puede tener apretado lo que el usuario apretó. Además el pulsón largo y el
  doble toque fino ya **no** mandan clic derecho (`flutter/lib/common/widgets/
  remote_input.dart`): para el menú contextual se usa el botón derecho del mouse.
- **Cursor remoto visible por defecto** (user-default `show_remote_cursor=Y`
  en `applyCustomClientDefaults`, `flutter/lib/common.dart`).
- **Sin WebRTC por defecto** (`enable-webrtc=N` local; casilla en
  Ajustes → Red para redes raras).
- **RDP**: botón `RDP` en la fila si hay usuario/contraseña guardados; item RDP
  solo en Windows; ventana del túnel ("Escuchando") arranca y se mantiene
  minimizada; la pestaña se cierra sola al cerrar mstsc (watchdog de PID);
  atajo `.lnk` normal y `.lnk` RDP con el nombre del equipo; tilde de recordar
  credenciales re-habilitado.
- **Diseño compacto**: columna izquierda 250px, iconos al fondo de esa columna,
  sin barra "Listo", sin barra de pestaña única, sin subtítulos "Sesiones".
- **Copia de seguridad** (Ajustes → About / final de Ajustes en móvil):
  exporta/importa todo el config dir como texto (incluye `peers/`).
- **Sync de listas con servidor propio** (Ajustes → Sincronizar listas): ya NO
  usa GitHub. Todo pasa por la VPS propia `https://147.15.111.14:21121`
  (API compatible con el subconjunto de GitHub Contents, servicio Python en
  `/opt/rustdesk-listas/servidor.py`, systemd `rustdesk-listas.service`).
  Un campo Nombre (`equipos-<nombre>.json`), botón Vincular (crea o combina
  por fecha y aplica), Desvincular, auto-sync cada 20 s en ambas direcciones.
  El archivo se **cifra con el PIN de la app** (sin PIN configurado va en
  claro). Seguridad del canal (decisión del dueño): **HTTPS con certificado
  autofirmado fijado por huella (pinning)** — en Dart,
  `_kSyncCertPin` (sha256 del DER) en `github_sync.dart`; en Rust,
  `CERT_PEM` como única raíz de confianza en `src/presence.rs`. Un cert
  distinto ⇒ rechazo, nunca se manda el token. El token
  (`SYNC_TOKEN`) **no está en el código**: lo inyecta CI en el build
  (ver "Secretos" abajo).
- **Presencia**: cada PC publica cada 2 min sus sesiones en `presencia.json`
  del mismo servidor (servicio, `src/presence.rs`); las entradas con más de
  5 min se ignoran. En la fila (vistas lista y tarjeta) todo va **en una sola línea**:
  `EQUIPO  usuario@host  P1;P2;P5` (alias, equipo y sesiones en verde) más la
  nota si existe, con tooltip al pasar el mouse (`presenceSessionsOf` en
  `github_sync.dart`, render en `peer_card.dart`). La PC publica **todas** las
  sesiones de Windows con usuario cargado —activas, conectadas o
  desconectadas—, no solo las conectadas en ese momento: función nativa
  `get_logged_in_session_ids` (`src/platform/windows.cc`) + wrapper
  `get_logged_in_session_names` (`src/platform/windows.rs`).
- **Monitoreo Telegram** por equipo + chequeo cada 10 s.
- **Android**: APK firmado con clave fija (actualiza encima); `hasFragileUserData`
  para conservar datos al desinstalar.
- **macOS**: dmg con firma ad-hoc (sin cuenta Apple Developer: abrir con
  clic derecho → Abrir la primera vez).

## Compilar y bajar

```sh
git tag v1.4.0-XX && git push <url-con-token> master v1.4.0-XX
gh workflow run flutter-tag.yml --repo gepafe/rustdesk --ref v1.4.0-XX \
  -f platforms=windows,android,macos
gh release download v1.4.0-XX --repo gepafe/rustdesk \
  --dir C:/PROYECTOS/RUSTDESK/distribucion --clobber \
  --pattern rustdesk-1.5.0-x86_64.exe \
  --pattern "rustdesk-1.5.0-universal-signed.apk" \
  --pattern rustdesk-1.5.0-aarch64-aarch64.dmg
```

Verificar tamaños locales contra `gh release view v1.4.0-XX --json assets`.

## Secretos y archivos sensibles (NO van al repo)

- Keystore Android: `C:\PROYECTOS\RUSTDESK\distribucion\firma-android\key.p12`
  (alias `rustdesk`); sus 4 valores están como secrets del repo
  (`ANDROID_SIGNING_KEY`, `ANDROID_ALIAS`, `ANDROID_KEY_STORE_PASSWORD`,
  `ANDROID_KEY_PASSWORD`). **Si se pierde, los APK dejan de actualizar encima.**
- `SYNC_TOKEN` (acceso al servidor de listas/presencia): **solo** como secret
  del repo en GitHub Actions; en el código NO aparece. CI lo inyecta en el
  build: en Rust vía la variable de entorno del workflow global
  (`flutter-build.yml` → `option_env!("SYNC_TOKEN")` en `presence.rs`) y en
  Dart sobreescribiendo `flutter/lib/common/widgets/sync_token.dart` en cada
  job (el archivo commiteado tiene `''` = sync apagada). El mismo valor vive
  en `C:\Users\VITALFIX\.rustdesk-secrets\token-vps-sync.txt` y en
  `/opt/rustdesk-listas/token` en la VPS (se lee por petición: se puede
  rotar editando ese archivo, sin reiniciar). **Si alguien se va en malos
  términos: rotar el token en la VPS + cambiar el secret y sacar versión
  nueva.** No commitear nunca un token en claro (GitHub bloquea el push por
  secret scanning y revoca el token encontrado).
- Certificado TLS de la VPS (pinning): `C:\Users\VITALFIX\.rustdesk-secrets\
  vps-tls\` (cert.pem, key.pem, fingerprint). Válido 2026→2036 con
  SAN=IP:147.15.111.14. **Si se regenera, hay que actualizar `_kSyncCertPin`
  y `CERT_PEM` y sacar versión nueva.**
- `flutter/pubspec.lock` lo reescribe el SDK local: revertirlo siempre antes
  de commitear (`git checkout -- flutter/pubspec.lock`).

## Notas operativas

- Sin PIN de app, la sync sube en claro; con PIN, cifrada con ese PIN.
- El PIN (aunque sea hash) no protege un disco robado sin cifrar: usar
  BitLocker en las PCs.
- Servidor/relay: se usa la red pública de RustDesk (sin `custom-server`).
  Proyecto pendiente si se quiere independizar: relay propio.
- `flutter analyze` local usa un SDK más nuevo que el CI: ignorar los issues
  preexistentes (DialogTheme/TabBarTheme, `dialog.dart:1448`,
  `generated_bridge` en `model.dart`); el Rust solo lo valida el CI.
