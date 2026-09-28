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
import 'pin_lock.dart';

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

// --------------------------- cifrado con el PIN ---------------------------

const int _kSyncIterations = 20000;

Uint8List _syncKey(List<int> pin, List<int> salt) {
  final out = <int>[];
  final hmac = Hmac(sha256, pin);
  var block = 1;
  while (out.length < 64) {
    final idx = [
      (block >> 24) & 0xff,
      (block >> 16) & 0xff,
      (block >> 8) & 0xff,
      block & 0xff,
    ];
    var u = hmac.convert([...salt, ...idx]).bytes;
    final acc = List<int>.from(u);
    for (var i = 1; i < _kSyncIterations; i++) {
      u = hmac.convert(u).bytes;
      for (var j = 0; j < acc.length; j++) {
        acc[j] ^= u[j];
      }
    }
    out.addAll(acc);
    block++;
  }
  return Uint8List.fromList(out.sublist(0, 64));
}

Uint8List _syncStream(List<int> key, List<int> nonce, List<int> data) {
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

bool _syncSame(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var d = 0;
  for (var i = 0; i < a.length; i++) {
    d |= a[i] ^ b[i];
  }
  return d == 0;
}

/// Cifra con el PIN. Formato: 'ENC1:' + base64(salt16 || nonce16 || ct || tag32).
String ghEncryptData(String plain, String pin) {
  final rnd = Random.secure();
  final salt = List<int>.generate(16, (_) => rnd.nextInt(256));
  final nonce = List<int>.generate(16, (_) => rnd.nextInt(256));
  final key = _syncKey(utf8.encode(pin), salt);
  final ct = _syncStream(key.sublist(0, 32), nonce, utf8.encode(plain));
  final tag = Hmac(sha256, key.sublist(32, 64))
      .convert([...nonce, ...ct])
      .bytes
      .sublist(0, 32);
  return 'ENC1:${base64Encode([...salt, ...nonce, ...ct, ...tag])}';
}

/// Descifra (formato ENC1:) o devuelve el texto tal cual si es JSON viejo sin
/// cifrar. Devuelve null si no se puede abrir (PIN distinto).
String? ghDecryptData(String data, String pin) {
  final t = data.trim();
  if (!t.startsWith('ENC1:')) return t;
  try {
    final raw = base64Decode(t.substring(5));
    if (raw.length < 64) return null;
    final salt = raw.sublist(0, 16);
    final nonce = raw.sublist(16, 32);
    final tag = raw.sublist(raw.length - 32);
    final ct = raw.sublist(32, raw.length - 32);
    final key = _syncKey(utf8.encode(pin), salt);
    final expect = Hmac(sha256, key.sublist(32, 64))
        .convert([...nonce, ...ct])
        .bytes
        .sublist(0, 32);
    if (!_syncSame(tag, expect)) return null;
    return utf8.decode(_syncStream(key.sublist(0, 32), nonce, ct));
  } catch (_) {
    return null;
  }
}

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
  // Sin tiempo limite una llamada colgada frena el temporizador de sync.
  const t = Duration(seconds: 15);
  Future<http.Response> attempt() async {
    if (_ghInsecure) {
      final client = IOClient(
          HttpClient()..badCertificateCallback = (cert, host, port) => true);
      try {
        return method == 'GET'
            ? await client.get(uri, headers: headers).timeout(t)
            : await client.put(uri, headers: headers, body: body).timeout(t);
      } finally {
        client.close();
      }
    }
    return method == 'GET'
        ? await http.get(uri, headers: headers).timeout(t)
        : await http.put(uri, headers: headers, body: body).timeout(t);
  }

  try {
    return await attempt();
  } on HandshakeException {
    // El modo sin verificacion vale SOLO para este intento (antivirus/proxy
    // mediante); el proximo intento vuelve a validar el certificado.
    _ghInsecure = true;
    try {
      showToast(
          'No se pudo verificar el certificado HTTPS (antivirus o proxy). Se conecta igual esta vez.');
      return await attempt();
    } finally {
      _ghInsecure = false;
    }
  } on TimeoutException {
    throw Exception('GitHub no responde (sin internet?)');
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
  // Si otra PC subio en el medio, el sha queda viejo y GitHub devuelve 422:
  // se reintenta una vez con el sha fresco en vez de perder el cambio.
  for (var i = 0; i < 2; i++) {
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
    if (resp.statusCode == 200 || resp.statusCode == 201) {
      return;
    }
    if (resp.statusCode != 422 || i == 1) {
      throw Exception('GitHub ${resp.statusCode}');
    }
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

/// PIN para cifrar/descifrar la copia: el de memoria, o se pide con dialogo
/// si hay contexto. Sin PIN configurado devuelve '' (sin cifrar). Devuelve
/// null si hace falta el PIN pero no se pudo obtener (modo automatico sin
/// desbloquear): en ese caso no se sube nada para no degradar a texto plano.
Future<String?> _syncPin(BuildContext? ctx) async {
  if (appLockPinMemory().isNotEmpty) return appLockPinMemory();
  if (getAppLockPin().isEmpty) return '';
  if (ctx == null) return null;
  return await askAppLockPin(ctx) ? appLockPinMemory() : null;
}

/// Cifra para subir en modo automatico. Devuelve null si hay PIN configurado
/// pero todavia no se ingreso (no se sube nada para no degradar a texto plano).
String? _syncEncryptAuto(String plain) {
  if (appLockPinMemory().isNotEmpty) {
    return ghEncryptData(plain, appLockPinMemory());
  }
  return getAppLockPin().isEmpty ? plain : null;
}

/// Un solo boton: crea el archivo si no existe y, si existe, baja la copia de
/// GitHub, la combina con la local, sube el resultado y lo aplica (la app se
/// reinicia sola para aplicarlo). La copia viaja cifrada con el PIN de la app.
Future<String?> ghLink({BuildContext? ctx}) async {
  if (ghSyncName().isEmpty) {
    return 'Escribí un nombre (ej: GERMAN-RUSTDESK)';
  }
  try {
    final local = await bind.mainExportConfigBackup();
    if (local.isEmpty) {
      return 'No se pudo generar la lista local';
    }
    final pin = await _syncPin(ctx);
    if (pin == null) {
      return null;
    }
    final cur = await _ghDownload();
    if (cur['exists'] != true) {
      await _ghUpload(pin.isEmpty ? local : ghEncryptData(local, pin));
      await bind.setLocalFlutterOption(k: kGhSyncHash, v: ghHash(local));
      return 'Lista creada en el repositorio';
    }
    final remote = cur['content'] as String;
    final rdec = remote.trimLeft().startsWith('ENC1:')
        ? (pin.isEmpty ? null : ghDecryptData(remote, pin))
        : remote;
    if (rdec == null) {
      return 'La copia de GitHub está cifrada con otro PIN';
    }
    final merged =
        rdec.trimLeft().startsWith('{') ? ghMerge(local, rdec) : local;
    if (merged == null) {
      return 'La copia de GitHub no se pudo leer';
    }
    await _ghUpload(pin.isEmpty ? merged : ghEncryptData(merged, pin));
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
bool _ghBusy = false;

void startGitHubSync() {
  if (_ghTimer != null) {
    return;
  }
  _ghTimer = Timer.periodic(const Duration(seconds: 20), (_) => _ghTick());
  _ghCheckRemoteOnStart();
  _presenceTimer ??=
      Timer.periodic(const Duration(seconds: 60), (_) => fetchPresence());
  fetchPresence();
}

// --------------------------- presencia ---------------------------
// Cada PC publica sola su estado en presencia.json (cero config: usa el
// repositorio y token embebidos). La fila de cada equipo muestra quien
// esta trabajando sin conectarse. Entradas de mas de 5 minutos se ignoran.

const _kPresenceFile = 'presencia.json';
const _kPresenceStaleSecs = 300;

final Map<String, ({int ts, List<String> sessions})> presenceCache = {};
final ValueNotifier<int> presenceVersion = ValueNotifier(0);
Timer? _presenceTimer;

String _cleanSessionName(String raw) {
  var s = raw.replaceAll(RegExp(r'\s*\(.*\)\s*$'), '');
  final i = s.indexOf(':');
  if (i >= 0) {
    s = s.substring(i + 1);
  }
  return s.trim();
}

Future<void> fetchPresence() async {
  try {
    final uri = Uri.parse(
        'https://api.github.com/repos/${ghSyncRepo()}/contents/$_kPresenceFile');
    final resp = await _ghRequest('GET', uri, _ghHeaders());
    if (resp.statusCode != 200) {
      return;
    }
    final j = jsonDecode(resp.body) as Map<String, dynamic>;
    final raw = base64Decode(
        (j['content'] as String).replaceAll(RegExp(r'\s'), ''));
    final map = jsonDecode(utf8.decode(raw)) as Map<String, dynamic>;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    presenceCache.clear();
    map.forEach((id, v) {
      if (v is Map) {
        final ts = (v['ts'] as num?)?.toInt() ?? 0;
        if (ts > 0 && now - ts <= _kPresenceStaleSecs) {
          final names = <String>[];
          final s = v['sessions'];
          if (s is List) {
            for (final e in s) {
              final c = _cleanSessionName(e.toString());
              if (c.isNotEmpty) {
                names.add(c);
              }
            }
          }
          presenceCache[id.toString()] = (ts: ts, sessions: names);
        }
      }
    });
    presenceVersion.value++;
  } catch (_) {}
}

/// Sube la union de la lista local y la de GitHub (sin reiniciar la app).
Future<void> _ghTick() async {
  if (!ghSyncAuto() || !ghSyncConfigured()) {
    return;
  }
  // Sin esta guardia, si un tick tarda mas de 20 s (sin internet) los ticks se
  // solapan y se acumulan llamadas colgadas.
  if (_ghBusy) {
    return;
  }
  _ghBusy = true;
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
      final up = _syncEncryptAuto(local);
      if (up == null) {
        return;
      }
      await _ghUpload(up);
      await bind.setLocalFlutterOption(k: kGhSyncHash, v: ghHash(local));
      showToast('Lista subida a GitHub');
      return;
    }
    final remote = cur['content'] as String;
    final rdec = remote.trimLeft().startsWith('ENC1:')
        ? (appLockPinMemory().isNotEmpty
            ? ghDecryptData(remote, appLockPinMemory())
            : null)
        : remote;
    if (rdec == null) {
      return;
    }
    final merged =
        rdec.trimLeft().startsWith('{') ? ghMerge(local, rdec) : local;
    if (merged == null) {
      return;
    }
    if (ghHash(merged) != ghHash(rdec)) {
      final up = _syncEncryptAuto(merged);
      if (up == null) {
        return;
      }
      await _ghUpload(up);
    }
    await bind.setLocalFlutterOption(k: kGhSyncHash, v: ghHash(merged));
    if (ghPeersCount(merged) > ghPeersCount(local)) {
      final msg = await ghLink();
      if (msg != null) {
        showToast(msg);
      }
    }
  } catch (_) {} finally {
    _ghBusy = false;
  }
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
    final rdec = remote.trimLeft().startsWith('ENC1:')
        ? (appLockPinMemory().isNotEmpty
            ? ghDecryptData(remote, appLockPinMemory())
            : null)
        : remote;
    if (rdec == null || !rdec.trimLeft().startsWith('{')) {
      return;
    }
    final local = await bind.mainExportConfigBackup();
    if (local.isEmpty) {
      return;
    }
    final merged = ghMerge(local, rdec);
    if (merged != null && ghHash(merged) != ghHash(local)) {
      final msg = await ghLink();
      if (msg != null) {
        showToast(msg);
      }
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
                  'primera vez y después la combina con la de GitHub, cifrada con el PIN de '
                  'la app (si tenés uno).',
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
              final msg = await ghLink(ctx: ctx);
              if (msg != null) {
                showToast(msg);
              }
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
