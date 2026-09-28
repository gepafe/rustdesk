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
- **PIN 777 por equipo**: casilla `USUARIO PRIVADO` en Ajustes → Seguridad\n  (opción del servicio `private-user`); viaja en el evento\n  `set_multiple_windows_session` (`src/flutter.rs`) y el diálogo\n  (`flutter/lib/common/widgets/dialog.dart`) pide la clave 777 solo si viene\n  marcada. Clave: `kOptionPrivateUser` en `flutter/lib/consts.dart`. La bandera\n  la publica la PC REMOTA en `platform_additions` (`src/server/connection.rs`,\n  `on_remote_authorized`), el controlador la guarda en\n  `crate::flutter::REMOTE_PRIVATE_USER` (`src/ui_session_interface.rs`,\n  `handle_peer_info`) y `flutter.rs` la usa al armar el evento (antes leía la\n  opción local del controlador = nunca se pedía 777). Requiere \"Compartir\n  sesiones RDP\" activo en la PC remota.", "oldString": "- **PIN 777 por equipo**: casilla `USUARIO PRIVADO` en Ajustes → Seguridad\n  (opción del servicio `private-user`); viaja en el evento\n  `set_multiple_windows_session` (`src/flutter.rs`) y el diálogo\n  (`flutter/lib/common/widgets/dialog.dart`) pide la clave 777 solo si viene\n  marcada. Clave: `kOptionPrivateUser` en `flutter/lib/consts.dart`.", "path": "C:\\PROYECTOS\\RUSTDESK\\rustdesk\\README-CLIENTE-PERSONALIZADO.md"
- **Modo vista por acción**: doble clic/clic siempre controla (limpia
  `view_only`); `VER SOLAMENTE` siempre abre en vista; el botón de la barra de
  sesión no se guarda (`peer_card.dart` `_connectControl`, `model.dart`
  `setViewOnly(peerId, false)`).
- **Sin clics fantasma**: mientras se elige sesión de Windows, el input se
  bloquea en el FFI de la sesión (`inputBlocked`; gates en
  `flutter/lib/models/input_model.dart`: `inputKey`, `scroll`, `sendMouse`,
  `handleMouse`).
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
- **Sync con GitHub** (Ajustes → Sincronizar con GitHub): repo fijo
  `vitalfix/rustdesk-listas` + token embebido; un campo Nombre
  (`equipos-<nombre>.json`), botón Vincular (crea o combina por fecha y
  aplica), Desvincular, auto-sync cada 20 s en ambas direcciones. El archivo
  se **cifra con el PIN de la app** (sin PIN configurado va en claro).
- **Presencia**: cada PC publica cada 2 min sus sesiones en `presencia.json`
  del mismo repo (servicio, `src/presence.rs`); la lista muestra por fila
  "N trabajando: nombres" o "libre". El subtítulo de cada fila (vista lista y
  tarjeta) muestra `usuario@host;p1;p2;...` con las sesiones activas de la PC
  remota (`presenceSessionsOf` en `github_sync.dart`).
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
- Token de GitHub embebido (repo privado + `presence.rs`): con permiso de
  escritura. **Si alguien se va en malos términos: revocar el token, poner uno
  nuevo y sacar versión nueva.** No commitear nunca un token en claro (GitHub
  bloquea el push por secret scanning).
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
