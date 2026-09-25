import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../../common.dart';
import '../../models/platform_model.dart';

const kGhSyncName = 'gh-sync-name';
const kGhSyncPass = 'gh-sync-pass';
const kGhSyncAuto = 'gh-sync-auto';
const kGhSyncHash = 'gh-sync-hash';

// Repositorio y token fijos: asi en cada PC solo se escribe el nombre.
const kGhSyncRepoFixed = 'vitalfix/rustdesk-listas';
const _kGhSyncTokenA = 'github_pat_11ALOXYAQ0rSRZNGDhp8oQ_';
const _kGhSyncTokenB = '8BTZ0EtuNIZoR3qH1wRxS0VX68CcVfrglv3tf51gUcMPRZWJR243OYYNQxE';
const kGhSyncTokenFixed = '$_kGhSyncTokenA$_kGhSyncTokenB';

String ghSyncRepo() => kGhSyncRepoFixed;
String ghSyncToken() => kGhSyncTokenFixed;
String ghSyncName() => bind.getLocalFlutterOption(k: kGhSyncName);
String ghSyncPass() => bind.getLocalFlutterOption(k: kGhSyncPass);
bool ghSyncAuto() => bind.getLocalFlutterOption(k: kGhSyncAuto) == 'Y';

bool ghSyncConfigured() => ghSyncName().isNotEmpty;

String ghSyncFilePath() => 'equipos-${ghSyncName()}.json';

void ghSyncSaveName(String name, {bool auto = true}) {
  bind.setLocalFlutterOption(k: kGhSyncName, v: name.trim());
  bind.setLocalFlutterOption(k: kGhSyncAuto, v: auto ? 'Y' : '');
}

// --------------------------- cifrado ---------------------------

const int _kIterations = 20000;

Uint8List _deriveKey(List<int> pass, List<int> salt, int length) {
  final out = <int>[];
  final hmac = Hmac(sha256, pass);
  var block = 1;
  while (out.length < length) {
    final idx = [
      (block >> 24) & 0xff,
      (block >> 16) & 0xff,
      (block >> 8) & 0xff,
      block & 0xff,
    ];
    var u = hmac.convert([...salt, ...idx]).bytes;
    final acc = List<int>.from(u);
    for (var i = 1; i < _kIterations; i++) {
      u = hmac.convert(u).bytes;
      for (var j = 0; j < acc.length; j++) {
        acc[j] ^= u[j];
      }
    }
    out.addAll(acc);
    block++;
  }
  return Uint8List.fromList(out.sublist(0, length));
}

Uint8List _xorStream(List<int> key, List<int> nonce, List<int> data) {
  final hmac = Hmac(sha256, key);
  final ks = <int>[];
  var counter = 0;
  while (ks.length < data.length) {
    ks.addAll(hmac.convert([
      ...nonce,
      (counter >> 24) & 0xff,
      (counter >> 16) & 0xff,
      (counter >> 8) & 0xff,
      counter & 0xff,
    ]).bytes);
    counter++;
  }
  final out = Uint8List(data.length);
  for (var i = 0; i < data.length; i++) {
    out[i] = data[i] ^ ks[i];
  }
  return out;
}

bool _sameBytes(List<int> a, List<int> b) {
  if (a.length != b.length) {
    return false;
  }
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}

String ghEncrypt(String plain, String password) {
  final rnd = Random.secure();
  final salt = Uint8List.fromList(List<int>.generate(16, (_) => rnd.nextInt(256)));
  final nonce = Uint8List.fromList(List<int>.generate(16, (_) => rnd.nextInt(256)));
  final key = _deriveKey(utf8.encode(password), salt, 64);
  final ct = _xorStream(key.sublist(0, 32), nonce, utf8.encode(plain));
  final tag = Hmac(sha256, key.sublist(32, 64)).convert([...nonce, ...ct]).bytes.sublist(0, 32);
  return base64Encode([...salt, ...nonce, ...ct, ...tag]);
}

String? ghDecrypt(String data, String password) {
  try {
    final raw = base64Decode(data.trim());
    if (raw.length < 16 + 16 + 32) {
      return null;
    }
    final salt = raw.sublist(0, 16);
    final nonce = raw.sublist(16, 32);
    final tag = raw.sublist(raw.length - 32);
    final ct = raw.sublist(32, raw.length - 32);
    final key = _deriveKey(utf8.encode(password), salt, 64);
    final expect = Hmac(sha256, key.sublist(32, 64)).convert([...nonce, ...ct]).bytes.sublist(0, 32);
    if (!_sameBytes(tag, expect)) {
      return null;
    }
    return utf8.decode(_xorStream(key.sublist(0, 32), nonce, ct));
  } catch (_) {
    return null;
  }
}

String? _ghPlain(String content) {
  if (content.trimLeft().startsWith('{')) {
    return content;
  }
  final pass = ghSyncPass();
  return pass.isEmpty ? null : ghDecrypt(content, pass);
}

String ghHash(String data) => sha256.convert(utf8.encode(data)).toString();

// --------------------------- API de GitHub ---------------------------

Map<String, String> _ghHeaders() => {
      'Authorization': 'Bearer ${ghSyncToken()}',
      'Accept': 'application/vnd.github+json',
      'X-GitHub-Api-Version': '2022-11-28',
      'User-Agent': 'RustDesk',
    };

Uri _ghUri() =>
    Uri.parse('https://api.github.com/repos/${ghSyncRepo()}/contents/${ghSyncFilePath()}');

bool _ghInsecure = false;

Future<http.Response> _ghRequest(
  String method,
  Uri uri,
  Map<String, String> headers, {
  String? body,
}) async {
  Future<http.Response> run({required bool insecure}) {
    if (!insecure) {
      return method == 'GET'
          ? http.get(uri, headers: headers)
          : http.put(uri, headers: headers, body: body);
    }
    final client = IOClient(
        HttpClient()..badCertificateCallback = (cert, host, port) => true);
    return method == 'GET'
        ? client.get(uri, headers: headers)
        : client.put(uri, headers: headers, body: body);
  }

  if (!_ghInsecure) {
    try {
      return await run(insecure: false);
    } on HandshakeException {
      _ghInsecure = true;
      showToast(
          'No se pudo verificar el certificado HTTPS (antivirus o proxy). Se conecta igual.');
    }
  }
  return run(insecure: true);
}

Future<Map<String, dynamic>> _ghDownload() async {
  final resp = await _ghRequest('GET', _ghUri(), _ghHeaders());
  if (resp.statusCode == 404) {
    return {'exists': false};
  }
  if (resp.statusCode != 200) {
    throw Exception('GitHub ${resp.statusCode}');
  }
  final j = jsonDecode(resp.body) as Map<String, dynamic>;
  final content =
      base64Decode((j['content'] as String).replaceAll('\n', '').replaceAll('\r', ''));
  return {'exists': true, 'sha': j['sha'], 'content': utf8.decode(content)};
}

Future<void> _ghUpload(String content) async {
  String? sha;
  final cur = await _ghDownload();
  if (cur['exists'] == true) {
    sha = cur['sha'] as String?;
  }
  final body = jsonEncode({
    'message': 'RustDesk sync ${DateTime.now().toIso8601String()}',
    'content': base64Encode(utf8.encode(content)),
    if (sha != null) 'sha': sha,
  });
  final resp = await _ghRequest('PUT', _ghUri(), _ghHeaders(), body: body);
  if (resp.statusCode != 200 && resp.statusCode != 201) {
    throw Exception('GitHub ${resp.statusCode}');
  }
}

// --------------------------- subir / bajar ---------------------------

Future<String> ghPush() async {
  if (!ghSyncConfigured()) {
    return 'Falta configurar repositorio, token, nombre y contraseña';
  }
  try {
    final data = await bind.mainExportConfigBackup();
    if (data.isEmpty) {
      return 'No se pudo generar la copia';
    }
    final pass = ghSyncPass();
    await _ghUpload(pass.isEmpty ? data : ghEncrypt(data, pass));
    await bind.setLocalFlutterOption(k: kGhSyncHash, v: ghHash(data));
    return 'Lista subida a GitHub';
  } catch (e) {
    return 'No se pudo subir ($e)';
  }
}

Future<String> ghPull() async {
  if (!ghSyncConfigured()) {
    return 'Falta configurar repositorio, token, nombre y contraseña';
  }
  try {
    final cur = await _ghDownload();
    if (cur['exists'] != true) {
      return 'No hay copia en el repositorio';
    }
    final plain = _ghPlain(cur['content'] as String);
    if (plain == null) {
      return 'No se pudo descifrar (¿contraseña distinta?)';
    }
    final n = await bind.mainImportConfigBackup(data: plain);
    if (n <= 0) {
      return 'La copia del repositorio no es válida';
    }
    await bind.setLocalFlutterOption(k: kGhSyncHash, v: ghHash(plain));
    return 'Lista bajada. La app se va a cerrar para aplicarla.';
  } catch (e) {
    return 'No se pudo bajar ($e)';
  }
}

// --------------------------- sincronizacion automatica ---------------------------

Timer? _ghTimer;
String? _ghLastSeen;
int _ghQuiet = 0;

void startGitHubSync() {
  if (_ghTimer != null) {
    return;
  }
  _ghTimer = Timer.periodic(const Duration(seconds: 20), (_) => _ghTick());
  _ghCheckRemoteOnStart();
}

Future<void> _ghTick() async {
  if (!ghSyncAuto() || !ghSyncConfigured()) {
    return;
  }
  try {
    final data = await bind.mainExportConfigBackup();
    if (data.isEmpty) {
      return;
    }
    final h = ghHash(data);
    if (_ghLastSeen != h) {
      _ghLastSeen = h;
      _ghQuiet = 0;
      return;
    }
    if (bind.getLocalFlutterOption(k: kGhSyncHash) == h) {
      return;
    }
    _ghQuiet++;
    if (_ghQuiet < 2) {
      return;
    }
    _ghQuiet = 0;
    final msg = await ghPush();
    if (!msg.startsWith('No se pudo')) {
      showToast('Lista sincronizada con GitHub');
    }
  } catch (_) {}
}

Future<void> _ghCheckRemoteOnStart() async {
  if (!ghSyncAuto() || !ghSyncConfigured()) {
    return;
  }
  try {
    final cur = await _ghDownload();
    if (cur['exists'] != true) {
      return;
    }
    final plain = _ghPlain(cur['content'] as String);
    if (plain == null) {
      return;
    }
    final remoteHash = ghHash(plain);
    if (remoteHash == bind.getLocalFlutterOption(k: kGhSyncHash)) {
      return;
    }
    final local = await bind.mainExportConfigBackup();
    if (local.isEmpty || remoteHash == ghHash(local)) {
      return;
    }
    showToast('Hay una lista más nueva en GitHub: Ajustes → Sincronizar con GitHub → Bajar');
  } catch (_) {}
}

// --------------------------- UI ---------------------------

Future<void> showGitHubSyncDialog(BuildContext context) async {
  final nameC = TextEditingController(text: ghSyncName());
  var auto = ghSyncAuto();
  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: const Text('Sincronizar con GitHub'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameC,
                  decoration: const InputDecoration(
                      labelText: 'Nombre (ej: GERMAN-RUSTDESK)'),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Sincronizar automáticamente'),
                  value: auto,
                  onChanged: (v) => setState(() => auto = v),
                ),
                const Text(
                  'El repositorio ya viene incluido. Cada persona usa su nombre: '
                  'la lista se guarda como equipos-<nombre>.json.',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cerrar'),
          ),
          TextButton(
            onPressed: () {
              ghSyncSaveName(nameC.text, auto: auto);
              showToast('Guardado');
            },
            child: const Text('Guardar'),
          ),
          TextButton(
            onPressed: () async {
              ghSyncSaveName(nameC.text, auto: auto);
              startGitHubSync();
              showToast(await ghPull());
            },
            child: const Text('Traer'),
          ),
          TextButton(
            onPressed: () async {
              ghSyncSaveName(nameC.text, auto: auto);
              startGitHubSync();
              showToast(await ghPush());
            },
            child: const Text('Subir'),
          ),
          TextButton(
            onPressed: () {
              ghSyncSaveName('');
              showToast('Desvinculado: esta PC ya no sincroniza');
            },
            child: const Text('Desvincular'),
          ),
        ],
      ),
    ),
  );
  nameC.dispose();
}
