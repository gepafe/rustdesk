import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/models/peer_folder_model.dart';
import 'package:flutter_hbb/models/peer_model.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/utils/multi_window_manager.dart';

import '../../common.dart';

const String kOptionPreviewCaptureActive = 'preview-capture-active';

/// Capturas de "Vista previa" en memoria (id del equipo -> PNG).
final Map<String, Uint8List> previewFrames = {};
final Set<String> previewCapturing = {};
final ValueNotifier<int> previewRevision = ValueNotifier<int>(0);

String previewTempPath(String peerId) {
  final safe = peerId.replaceAll(RegExp(r'[^A-Za-z0-9]'), '_');
  return '${Directory.systemTemp.path}${Platform.pathSeparator}rdpreview_$safe.png';
}

List<Peer> previewPeers() {
  final peers = <Peer>[];
  try {
    for (final p in gFFI.recentPeersModel.peers) {
      if (peerFolderModel.isPreview(p.id)) {
        peers.add(p);
      }
    }
  } catch (_) {}
  return peers;
}

String previewPeerName(Peer p) => p.alias.isNotEmpty ? p.alias : p.id;

void showPreviewGalleryDialog(BuildContext context) {
  showDialog(
    context: context,
    builder: (ctx) => ValueListenableBuilder<int>(
      valueListenable: previewRevision,
      builder: (ctx, _, __) {
        final peers = previewPeers();
        return AlertDialog(
          title: Text(translate('Vista previa')),
          content: SizedBox(
            width: 780,
            height: 500,
            child: peers.isEmpty
                ? Center(
                    child: Text(translate(
                        'Marca equipos con "Vista previa" desde el menu de cada equipo')))
                : GridView.count(
                    crossAxisCount: 3,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 16 / 10,
                    children:
                        peers.map((p) => _buildPreviewTile(ctx, p)).toList(),
                  ),
          ),
          actions: [
            TextButton(
              onPressed: startPreviewCaptures,
              child: Text(translate('Actualizar')),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(translate('Cerrar')),
            ),
          ],
        );
      },
    ),
  );
}

Widget _buildPreviewTile(BuildContext ctx, Peer p) {
  final frame = previewFrames[p.id];
  final capturing = previewCapturing.contains(p.id);
  return InkWell(
    onTap: frame == null ? null : () => showPreviewFrameDialog(ctx, p, frame),
    child: Column(
      children: [
        Expanded(
          child: frame == null
              ? Container(
                  color: Colors.black12,
                  alignment: Alignment.center,
                  child: capturing
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.image_outlined),
                )
              : ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Image.memory(frame,
                      fit: BoxFit.cover, width: double.infinity),
                ),
        ),
        const SizedBox(height: 4),
        Text(previewPeerName(p),
            style: const TextStyle(fontSize: 12),
            overflow: TextOverflow.ellipsis),
      ],
    ),
  );
}

void showPreviewFrameDialog(BuildContext context, Peer p, Uint8List frame) {
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(previewPeerName(p)),
      content: InteractiveViewer(
        child: Image.memory(frame, fit: BoxFit.contain),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text(translate('Cerrar')),
        ),
      ],
    ),
  );
}

/// Captura de a uno los equipos marcados y guarda los frames en memoria.
Future<void> startPreviewCaptures() async {
  for (final p in previewPeers()) {
    if (previewCapturing.contains(p.id)) continue;
    previewCapturing.add(p.id);
    previewRevision.value++;
    final file = File(previewTempPath(p.id));
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {}
    try {
      await bind.mainSetLocalOption(
          key: kOptionPreviewCaptureActive, value: p.id);
      final windowId =
          await rustDeskWinManager.newRemoteDesktop(p.id, forceRelay: false);
      for (var i = 0; i < 15; i++) {
        await Future.delayed(const Duration(seconds: 2));
        if (await file.exists()) break;
        try {
          await bind.sessionTakeScreenshot(sessionId: windowId, display: 0);
        } catch (_) {}
      }
      if (await file.exists()) {
        previewFrames[p.id] = await file.readAsBytes();
        try {
          await file.delete();
        } catch (_) {}
      }
    } catch (_) {
    } finally {
      try {
        await bind.mainSetLocalOption(
            key: kOptionPreviewCaptureActive, value: '');
      } catch (_) {}
      previewCapturing.remove(p.id);
      previewRevision.value++;
    }
  }
}
