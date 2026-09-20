# Plan: galería de "Vista previa" (capturas en memoria)

Objetivo: marcar equipos (ya implementado con "Vista previa" en el menú de
cada equipo de Recent) y, al pulsar el botón "Vista previa" de la barra
superior, capturar UN frame de cada equipo marcado, de a uno, y mostrarlos en
una cuadrícula. Clic en una miniatura -> esa captura en grande (estática). Para
conectarse, se usa la vía tradicional.

## Decisiones del usuario
- Capturas EN MEMORIA (no en disco).
- Clic = captura estática en grande (no abre sesión).
- La captura requiere la contraseña guardada del equipo.

## APIs confirmadas
- Abrir sesión en escritorio:
  `rustDeskWinManager.newRemoteDesktop(id, password: ..., isSharedPassword: ..., forceRelay: false)`
  (import `package:flutter_hbb/utils/multi_window_manager.dart`; ver `connectMainDesktop` en `flutter/lib/common.dart`).
- Pedir captura: `bind.sessionTakeScreenshot(sessionId: <windowId>, display: 0)`.
- Guardar/descartar la captura: `bind.sessionHandleScreenshot(sessionId:, action: '0:<ruta>')`
  (Rust escribe el PNG en la ruta; `action: '2'` cancela). No hay API que
  devuelva bytes directos a Dart.
- El evento de sesión llega como `'screenshot'` y se maneja en
  `FFI._handleScreenshot` (`flutter/lib/models/model.dart:488`).

## Flujo propuesto
1. Botón "Vista previa" en `_landscapeRightActions` (`flutter/lib/common/widgets/peer_tab_page.dart`).
2. Para cada equipo marcado (secuencial):
   a. `newRemoteDesktop(...)` para abrir la sesión.
   b. Esperar a que conecte (unos segundos / hasta `is_screenshot_supported`).
   c. Pedir la captura a un fichero temporal.
   d. Leer los bytes del temporal, guardarlos en un mapa en memoria
      (`id -> Uint8List`) y borrar el temporal.
   e. Cerrar la ventana de sesión.
3. Mostrar cuadrícula (nombre + online). Clic -> `Image.memory` en grande.

## Archivo nuevo previsto
`flutter/lib/common/widgets/preview_gallery.dart`:
- `final Map<String, Uint8List> previewFrames = {};`
- `List<Peer> previewPeers()` leyendo `peerFolderModel.isPreview(id)`.
- `showPreviewGalleryDialog()`, `showPreviewFrameDialog(peer, frame)`.
- `startPreviewCaptures()`.

## Riesgos / a verificar
- ¿La ventana principal recibe el evento `'screenshot'` de la sesión remota, o
  solo la ventana de sesión? Si es solo la de sesión, hay que enrutar por
  `rustDeskWinManager.call` (patrón: `kWindowConnect` en
  `desktop_home_page.dart:792` con `setMethodCallHandler`).
- Cerrar la ventana de sesión de forma programática (buscar el método del
  `rustDeskWinManager`).
- Multiusuario de Windows: la captura corresponde a la sesión activa del
  equipo remoto. Seleccionar otra sesión de usuario queda para fase 2.
