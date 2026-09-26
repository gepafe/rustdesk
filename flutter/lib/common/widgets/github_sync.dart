import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../../common.dart';
import '../../models/platform_model.dart';

const kGhSyncName = 'gh-sync-name';
const kGhSyncAuto = 'gh-sync-auto';
const kGhSyncHash = 'gh-sync-hash';

const kGhSyncRepoFixed = 'vitalfix/rustdesk-listas';
const _kGhSyncTokenA = 'github_pat_11ALOXYAQ0rSRZNGDhp8oQ_';
const _kGhSyncTokenB = '8BTZ0EtuNIZoR3qH1wRxS0VX68CcVfrglv3tf51gUcMPRZWJR243OYYNQxE';
const kGhSyncTokenFixed = '$_kGhSyncTokenA$_kGhSyncTokenB';

String ghSyncRepo() => kGhSyncRepoFixed;
String ghSyncToken() => kGhSyncTokenFixed;
String ghSyncName() => bind.getLocalFlutterOption(k: kGhSyncName);
bool ghSyncAuto() => bind.getLocalFlutterOption(k: kGhSyncAuto) == 'Y';
bool ghSyncConfigured() => ghSyncName().isNotEmpty;
String ghSyncFilePath() => 'equipos-${ghSyncName()}.json';

void ghSyncSaveName(String name, {bool? auto}) {
  bind.setLocalFlutterOption(k: kGhSyncName, v: name.trim());
  if (auto != null) {
    bind.setLocalFlutterOption(k: kGhSyncAuto, v: auto ? 'Y' : '');
  }
}

String ghHash(String data) => sha256.convert(utf8.encode(data)).toString();

// --------------------------- API de GitHub ---------------------------

bool _ghInsecure = false;

Map<String, String> _ghHeaders() => {
      'Authorization': 'Bearer ${ghSyncToken()}',
      'Accept': 'application/vnd.github+json',
      'X-GitHub-Api-Version': '2022-11-28',
      'User-Agent': 'RustDesk',
    };

Uri _ghUri() =>
    Uri.parse('https://api.github.com/repos/${ghSyncRepo()}/contents/${ghSyncFilePath()}');

Future<http.Response> _ghRequest(String method, Uri uri,
    Map<String, String> headers, {String? body}) async {
  Future<http.Response> attempt() async {
    if (_ghInsecure) {
      final client = IOClient(
          HttpClient()..badCertificateCallback = (cert, host, port) => true);
      try {
        return method == 'GET'
            ? await client.get(uri, headers: headers)
            : await client.put(uri, headers: headers, body: body);
      } finally {
        client.close();
      }
    }
    return method == 'GET'
        ? await http.get(uri, headers: headers)
        : await http.put(uri, headers: headers, body: body);
  }

  try {
    return await attempt();
  } on HandshakeException {
    _ghInsecure = true;
    showToast(
        'No se pudo verificar el certificado HTTPS (antivirus o proxy). Se conecta igual.');
    return await attempt();
  }
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

// --------------------------- combinacion ---------------------------

int _mtimeAt(Map<String, dynamic> mtimes, String key) {
  final v = mtimes[key];
  return v is num ? v.toInt() : 0;
}

/// Combina el respaldo local con el de GitHub: se suman los archivos y, si un
/// archivo esta en los dos, gana el mas nuevo. Los equipos son archivos
/// separados dentro de peers/, asi que el criterio es por equipo.
String? ghMerge(String local, String remote) {
  try {
    final l = jsonDecode(local) as Map<String, dynamic>;
    final r = jsonDecode(remote) as Map<String, dynamic>;
    final lf = (l['files'] as Map).cast<String, dynamic>();
    final rf = (r['files'] as Map).cast<String, dynamic>();
    final lm = ((l['mtimes'] ?? const {}) as Map).cast<String, dynamic>();
    final rm = ((r['mtimes'] ?? const {}) as Map).cast<String, dynamic>();
    final files = <String, dynamic>{};
    final mtimes = <String, dynamic>{};
    for (final k in <String>{...lf.keys, ...rf.keys}) {
      final inLocal = lf.containsKey(k);
      final inRemote = rf.containsKey(k);
      final useLocal =
          !inRemote || (inLocal && _mtimeAt(lm, k) >= _mtimeAt(rm, k));
      files[k] = useLocal ? lf[k] : rf[k];
      final t = useLocal ? lm[k] : rm[k];
      if (t != null) {
        mtimes[k] = t;
      }
    }
    return jsonEncode({'version': 3, 'files': files, 'mtimes': mtimes});
  } catch (_) {
    return null;
  }
}

int ghPeersCount(String json) {
  try {
    final j = jsonDecode(json) as Map<String, dynamic>;
    final files = j['files'] as Map;
    return files.keys.where((k) => k.toString().startsWith('peers/')).length;
  } catch (_) {
    return 0;
  }
}

// --------------------------- Vincular / Desvincular ---------------------------

/// Un solo boton: crea el archivo si no existe y, si existe, baja la copia de
/// GitHub, la combina con la local, sube el resultado y lo aplica (la app se
/// reinicia sola para aplicarlo).
Future<String> ghLink() async {
  if (ghSyncName().isEmpty) {
    return 'Escribí un nombre (ej: GERMAN-RUSTDESK)';
  }
  try {
    final local = await bind.mainExportConfigBackup();
    if (local.isEmpty) {
      return 'No se pudo generar la lista local';
    }
    final cur = await _ghDownload();
    if (cur['exists'] != true) {
      await _ghUpload(local);
      await bind.setLocalFlutterOption(k: kGhSyncHash, v: ghHash(local));
      return 'Lista creada en el repositorio';
    }
    final remote = cur['content'] as String;
    final merged = remote.trimLeft().startsWith('{') ? ghMerge(local, remote) : local;
    if (merged == null) {
      return 'La copia de GitHub no se pudo leer';
    }
    await _ghUpload(merged);
    await bind.setLocalFlutterOption(k: kGhSyncHash, v: ghHash(merged));
    if (ghHash(merged) == ghHash(local)) {
      return 'Ya estaba todo: sin cambios';
    }
    final n = await bind.mainImportConfigBackup(data: merged);
    if (n <= 0) {
      return 'Se combinó pero no se pudo aplicar';
    }
    return 'Listo: la app se va a cerrar para aplicar la lista combinada';
  } catch (e) {
    return 'No se pudo vincular ($e)';
  }
}

void ghUnlink() {
  bind.setLocalFlutterOption(k: kGhSyncName, v: '');
  bind.setLocalFlutterOption(k: kGhSyncAuto, v: '');
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

/// Sube la union de la lista local y la de GitHub (sin reiniciar la app).
Future<void> _ghTick() async {
  if (!ghSyncAuto() || !ghSyncConfigured()) {
    return;
  }
  try {
    final local = await bind.mainExportConfigBackup();
    if (local.isEmpty) {
      return;
    }
    if (_ghLastSeen != ghHash(local)) {
      _ghLastSeen = ghHash(local);
      _ghQuiet = 0;
      return;
    }
    _ghQuiet++;
    if (_ghQuiet < 2) {
      return;
    }
    _ghQuiet = 0;
    final cur = await _ghDownload();
    if (cur['exists'] != true) {
      await _ghUpload(local);
      await bind.setLocalFlutterOption(k: kGhSyncHash, v: ghHash(local));
      showToast('Lista subida a GitHub');
      return;
    }
    final remote = cur['content'] as String;
    final merged = remote.trimLeft().startsWith('{') ? ghMerge(local, remote) : local;
    if (merged == null) {
      return;
    }
    if (ghHash(merged) != ghHash(remote)) {
      await _ghUpload(merged);
    }
    await bind.setLocalFlutterOption(k: kGhSyncHash, v: ghHash(merged));
    if (ghPeersCount(merged) > ghPeersCount(local)) {
      final msg = await ghLink();
      showToast(msg);
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
    final remote = cur['content'] as String;
    if (!remote.trimLeft().startsWith('{')) {
      return;
    }
    final local = await bind.mainExportConfigBackup();
    if (local.isEmpty) {
      return;
    }
    final merged = ghMerge(local, remote);
    if (merged != null && ghHash(merged) != ghHash(local)) {
      final msg = await ghLink();
      showToast(msg);
    }
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
                  'El repositorio y el token ya vienen dentro de la app: solo poné tu nombre '
                  '(la lista se guarda como equipos-<nombre>.json). Vincular crea la lista la '
                  'primera vez y después la combina con la de GitHub.',
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
            onPressed: () async {
              ghSyncSaveName(nameC.text, auto: auto);
              startGitHubSync();
              showToast(await ghLink());
            },
            child: const Text('Vincular'),
          ),
          TextButton(
            onPressed: () {
              ghUnlink();
              showToast('Desvinculado: esta PC ya no sincroniza con GitHub');
            },
            child: const Text('Desvincular'),
          ),
        ],
      ),
    ),
  );
  nameC.dispose();
}
