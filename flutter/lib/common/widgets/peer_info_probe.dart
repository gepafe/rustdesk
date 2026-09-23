import 'dart:async';

import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:uuid/uuid.dart';

bool _probing = false;
bool _probedOnStart = false;

List<String> _onlinePeerIds() => gFFI.peerTabModel.currentTabCachedPeers
    .where((peer) => peer.online && peer.id.isNotEmpty)
    .map((peer) => peer.id)
    .toList();

/// Primer chequeo automatico al abrir RustDesk: una sola vez por ejecucion, y
/// solo cuando ya hay equipos online para consultar.
void probePeersInfoOnStart() {
  if (_probedOnStart) return;
  final ids = _onlinePeerIds();
  if (ids.isEmpty) return;
  _probedOnStart = true;
  _probePeersInfo(ids);
}

/// Chequeo a demanda, desde el boton Actualizar.
void probeCurrentTabPeersInfo() {
  final ids = _onlinePeerIds();
  if (ids.isEmpty) return;
  _probePeersInfo(ids);
}

Future<void> _probePeersInfo(List<String> ids) async {
  if (_probing) return;
  _probing = true;
  try {
    for (final id in ids) {
      await _probePeerInfo(id);
    }
    await gFFI.groupModel.pull();
  } finally {
    _probing = false;
  }
}

/// Login silencioso (sin abrir ventana) para que el equipo reporte su nombre y
/// sus sesiones. El password vacio deja que Rust use el guardado del equipo.
Future<void> _probePeerInfo(String id) async {
  final sessionId = Uuid().v4obj();
  final err = bind.sessionAddSync(
    sessionId: sessionId,
    id: id,
    isFileTransfer: false,
    isViewCamera: false,
    isPortForward: false,
    isRdp: false,
    isTerminal: false,
    switchUuid: '',
    forceRelay: false,
    password: '',
    isSharedPassword: false,
    connToken: null,
  );
  if (err != '') return;
  StreamSubscription? sub;
  try {
    sub = bind.sessionStart(sessionId: sessionId, id: id).listen((_) {});
    await Future.delayed(const Duration(seconds: 7));
  } finally {
    await sub?.cancel();
    await bind.sessionClose(sessionId: sessionId);
  }
}
