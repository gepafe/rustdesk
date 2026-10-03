import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';

import 'github_sync.dart';

// El monitoreo (consulta cada 10 s) y los avisos por Telegram los hace la
// VPS; aca solo se consulta y edita la configuracion que vive alla, asi el
// estado no depende de que esta PC tenga internet o este encendida.
Map<String, String> _watched = {};
String _token = '';
String _chatId = '';
bool _loaded = false;
bool _started = false;

bool isTelegramMonitored(String id) => _watched.containsKey(id);

Future<bool> _loadMonitors() async {
  if (_loaded) return true;
  final cfg = await tgGetConfig();
  if (cfg == null) return false;
  _token = (cfg['token'] ?? '') as String;
  _chatId = (cfg['chat_id'] ?? '') as String;
  _watched = {};
  final w = cfg['watched'];
  if (w is Map) {
    for (final e in w.entries) {
      _watched['${e.key}'] = '${e.value}';
    }
  }
  _loaded = true;
  return true;
}

Future<void> _save() async {
  final ok = await tgPutConfig({
    'token': _token,
    'chat_id': _chatId,
    'watched': _watched,
  });
  if (!ok) {
    // la proxima lectura vuelve a traer lo que quedo guardado en el servidor
    _loaded = false;
  }
}

Future<void> toggleTelegramMonitor(String id, bool on,
    {String label = ''}) async {
  if (!await _loadMonitors()) return;
  if (on) {
    _watched[id] = label.isEmpty ? id : label;
  } else {
    _watched.remove(id);
  }
  await _save();
}

void initTelegramMonitor() {
  if (_started) return;
  _started = true;
  _loadMonitors();
}

void showTelegramConfigDialog() async {
  await _loadMonitors();
  final tokenController = TextEditingController(text: _token);
  final chatController = TextEditingController(text: _chatId);

  gFFI.dialogManager.show((setState, close, context) {
    Future<void> guardar() async {
      _token = tokenController.text.trim();
      _chatId = chatController.text.trim();
      await _save();
    }

    submit() async {
      await guardar();
      showToast(translate('Successful'));
      close();
    }

    return CustomAlertDialog(
      title: Text('Alertas Telegram'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 500),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'La vigilancia y los avisos los hace el servidor, no esta PC. '
                'Crea un bot con @BotFather, pega acá el token y tu chat ID. '
                'Después tildá "Monitoreo Telegram" en los equipos que quieras vigilar.',
              ),
            ),
            TextField(
              controller: tokenController,
              decoration: const InputDecoration(labelText: 'Bot Token'),
            ),
            TextField(
              controller: chatController,
              decoration: const InputDecoration(labelText: 'Chat ID'),
            ),
          ],
        ),
      ),
      actions: [
        dialogButton('Probar', isOutline: true, onPressed: () async {
          await guardar();
          final ok = await tgTest();
          showToast(ok
              ? 'Mensaje de prueba enviado'
              : 'No se pudo enviar; revisá el guardado');
        }),
        dialogButton("Cancel", onPressed: close, isOutline: true),
        dialogButton("OK", onPressed: submit),
      ],
      onSubmit: submit,
      onCancel: close,
    );
  });
}
