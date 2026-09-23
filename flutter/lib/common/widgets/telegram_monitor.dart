import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:http/http.dart' as http;

const _kIdsKey = 'telegram-monitor-ids';
const _kTokenKey = 'telegram-bot-token';
const _kChatIdKey = 'telegram-chat-id';
const _cbQueryOnlines = 'callback_query_onlines';

final Set<String> _monitored = {};
final Map<String, bool> _lastOnline = {};
bool _loaded = false;
bool _started = false;

bool isTelegramMonitored(String id) => _monitored.contains(id);

String _labelKey(String id) => 'telegram-monitor-label-$id';

String _now() {
  final d = DateTime.now();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(d.day)}/${two(d.month)} ${two(d.hour)}:${two(d.minute)}';
}

Future<void> _loadMonitors() async {
  if (_loaded) return;
  _loaded = true;
  final v = await bind.mainGetLocalOption(key: _kIdsKey);
  for (final e in v.split(',')) {
    if (e.isNotEmpty) {
      _monitored.add(e);
    }
  }
}

Future<void> toggleTelegramMonitor(String id, bool on,
    {String label = ''}) async {
  await _loadMonitors();
  if (on) {
    _monitored.add(id);
    if (label.isNotEmpty) {
      await bind.mainSetLocalOption(key: _labelKey(id), value: label);
    }
  } else {
    _monitored.remove(id);
    _lastOnline.remove(id);
  }
  await bind.mainSetLocalOption(key: _kIdsKey, value: _monitored.join(','));
}

Future<String> _label(String id) async {
  final l = await bind.mainGetLocalOption(key: _labelKey(id));
  return l.isEmpty ? id : l;
}

Future<void> sendTelegramMessage(String text) async {
  final token = await bind.mainGetLocalOption(key: _kTokenKey);
  final chatId = await bind.mainGetLocalOption(key: _kChatIdKey);
  if (token.isEmpty || chatId.isEmpty) return;
  try {
    await http.post(
      Uri.parse('https://api.telegram.org/bot$token/sendMessage'),
      body: {'chat_id': chatId, 'text': text},
    );
  } catch (e) {
    debugPrint('telegram: $e');
  }
}

Future<void> _notify(String id, bool online) async {
  final label = await _label(id);
  final t = _now();
  await sendTelegramMessage(online
      ? '🟢 $label ($id) volvió a estar online ($t)'
      : '🔴 $label ($id) se desconectó ($t)');
}

void _onQueryOnlines(Map<String, dynamic> evt) {
  if (_monitored.isEmpty) return;
  final onlines = (evt['onlines'] ?? '').toString().split(',').toSet();
  final offlines = (evt['offlines'] ?? '').toString().split(',').toSet();
  for (final id in _monitored.toList()) {
    bool? now;
    if (onlines.contains(id)) {
      now = true;
    } else if (offlines.contains(id)) {
      now = false;
    } else {
      continue;
    }
    final prev = _lastOnline[id];
    if (prev != null && prev != now) {
      _notify(id, now);
    }
    _lastOnline[id] = now;
  }
}

void startTelegramMonitor() {
  if (!isWindows || _started) return;
  _started = true;
  _loadMonitors();
  platformFFI.registerEventHandler(_cbQueryOnlines, 'telegram_monitor',
      (evt) async {
    _onQueryOnlines(evt);
  });
  Timer.periodic(const Duration(seconds: 60), (_) {
    if (_monitored.isEmpty) return;
    bind.queryOnlines(ids: _monitored.toList());
  });
}

void showTelegramConfigDialog() async {
  final token = await bind.mainGetLocalOption(key: _kTokenKey);
  final chatId = await bind.mainGetLocalOption(key: _kChatIdKey);
  final tokenController = TextEditingController(text: token);
  final chatController = TextEditingController(text: chatId);

  gFFI.dialogManager.show((setState, close, context) {
    submit() async {
      await bind.mainSetLocalOption(
          key: _kTokenKey, value: tokenController.text.trim());
      await bind.mainSetLocalOption(
          key: _kChatIdKey, value: chatController.text.trim());
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
          await bind.mainSetLocalOption(
              key: _kTokenKey, value: tokenController.text.trim());
          await bind.mainSetLocalOption(
              key: _kChatIdKey, value: chatController.text.trim());
          await sendTelegramMessage('✅ Prueba de alertas de RustDesk');
        }),
        dialogButton("Cancel", onPressed: close, isOutline: true),
        dialogButton("OK", onPressed: submit),
      ],
      onSubmit: submit,
      onCancel: close,
    );
  });
}
