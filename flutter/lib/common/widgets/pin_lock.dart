import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/widgets/dialog.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:window_manager/window_manager.dart';

/// Cliente personalizado: bloqueo con PIN al abrir la aplicación.
///
/// Usa un PIN PROPIO (local option [kOptionAppLockPin]), separado del PIN de la
/// sesión de Seguridad. Si no hay PIN configurado, no bloquea la app.
/// Aplica a escritorio, móvil y Linux (no en la versión web).
/// Solo afecta a la interfaz; las conexiones entrantes las atiende el
/// servicio, por lo que siguen funcionando con normalidad.

/// Evento que manda Rust cuando la maquina vuelve de suspension.
const String _kResumeEvent = 'callback_device_resumed';

/// PIN de la app en memoria (solo vive mientras la app corre): sirve para
/// cifrar la sincronizacion sin pedirlo a cada rato.
String _appLockPinMemory = '';

/// PIN en memoria ('' si todavia no se ingreso en esta corrida).
String appLockPinMemory() => _appLockPinMemory;

bool _isPinHash(String stored) => stored.startsWith('v1:');

String _hashPin(String pin, String salt) =>
    sha256.convert(utf8.encode('$salt:$pin')).toString();

String _randomHex(int bytes) {
  final r = Random.secure();
  final b = List<int>.generate(bytes, (_) => r.nextInt(256));
  return b.map((e) => e.toRadixString(16).padLeft(2, '0')).join();
}

/// Lee el PIN de bloqueo de la app (guardado en una local option).
/// Devuelve '' si no hay PIN. OJO: si hay PIN devuelve el valor guardado
/// (hash), no el PIN; para comprobar un PIN usar verifyAppLockPin().
String getAppLockPin() {
  return bind.mainGetLocalOption(key: kOptionAppLockPin);
}

/// True si el PIN ingresado abre. Acepta el formato nuevo (hash con salt) y
/// el formato viejo (base64), que se migra solo al verificar.
bool verifyAppLockPin(String pin) {
  final stored = bind.mainGetLocalOption(key: kOptionAppLockPin);
  if (stored.isEmpty) return false;
  if (_isPinHash(stored)) {
    final parts = stored.split(':');
    if (parts.length != 3) return false;
    return _hashPin(pin, parts[1]) == parts[2];
  }
  try {
    if (utf8.decode(base64.decode(stored)) == pin) {
      setAppLockPin(pin);
      return true;
    }
  } catch (_) {}
  return false;
}

/// Guarda (o borra, si se pasa vacío) el PIN de bloqueo de la app.
Future<void> setAppLockPin(String pin) async {
  if (pin.isEmpty) {
    await bind.mainSetLocalOption(key: kOptionAppLockPin, value: '');
  } else {
    final salt = _randomHex(16);
    await bind.mainSetLocalOption(
        key: kOptionAppLockPin, value: 'v1:$salt:${_hashPin(pin, salt)}');
  }
  _appLockPinMemory = pin;
  markAppLockAsked();
}

/// True si hay un PIN de bloqueo de la app configurado.
bool isAppLockEnabled() => getAppLockPin().isNotEmpty;

/// Reanudaciones de Windows detectadas por Rust (vuelta de suspension).
int getAppLockResumeCount() =>
    int.tryParse(bind.mainGetLocalOption(key: kOptionAppLockResumeCount)) ?? 0;

void bumpAppLockResumeCount() {
  bind.mainSetLocalOption(
      key: kOptionAppLockResumeCount,
      value: (getAppLockResumeCount() + 1).toString());
}

/// Valor de la cuenta de reanudaciones cuando se ingreso el PIN por ultima vez;
/// -1 si nunca se ingreso.
int getAppLockAskedCount() =>
    int.tryParse(bind.mainGetLocalOption(key: kOptionAppLockAskedCount)) ?? -1;

void markAppLockAsked() {
  bind.mainSetLocalOption(
      key: kOptionAppLockAskedCount, value: getAppLockResumeCount().toString());
}

/// True si el PIN ya se ingreso desde el ultimo inicio de Windows o vuelta de
/// suspension, para no pedirlo todo el tiempo en el uso diario.
bool appLockPinAlreadyAsked() =>
    getAppLockAskedCount() == getAppLockResumeCount();

/// Diálogo para definir/cambiar/quitar el PIN de bloqueo de la app.
/// Dejar el campo vacío elimina el bloqueo.
void changeAppLockPinDialog(String oldPin, Function() callback) {
  final pinController = TextEditingController(text: oldPin);
  final confirmController = TextEditingController(text: oldPin);
  String? pinErrorText;
  String? confirmationErrorText;
  final maxLength = bind.mainMaxEncryptLen();
  gFFI.dialogManager.show((setState, close, context) {
    submit() async {
      pinErrorText = null;
      confirmationErrorText = null;
      final pin = pinController.text.trim();
      final confirm = confirmController.text.trim();
      if (pin != confirm) {
        setState(() {
          confirmationErrorText =
              translate('The confirmation is not identical.');
        });
        return;
      }
      await setAppLockPin(pin);
      callback.call();
      close();
    }

    return CustomAlertDialog(
      title: Text(translate("Set app PIN")),
      content: Column(
        children: [
          DialogTextField(
            title: 'PIN',
            controller: pinController,
            obscureText: true,
            errorText: pinErrorText,
            maxLength: maxLength,
          ),
          DialogTextField(
            title: translate('Confirmation'),
            controller: confirmController,
            obscureText: true,
            errorText: confirmationErrorText,
            maxLength: maxLength,
          )
        ],
      ),
      actions: [
        dialogButton(translate("Cancel"), onPressed: close, isOutline: true),
        dialogButton(translate("OK"), onPressed: submit),
      ],
      onSubmit: submit,
      onCancel: close,
    );
  });
}

/// Pide el PIN de la app con un dialogo y lo verifica. Devuelve true si abre
/// (y lo deja en memoria para la sincronizacion). Si no hay PIN, true.
Future<bool> askAppLockPin(BuildContext context) async {
  if (getAppLockPin().isEmpty) return true;
  final c = TextEditingController();
  var ok = false;
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('PIN de la app'),
      content: TextField(
        controller: c,
        obscureText: true,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'PIN'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancelar'),
        ),
        TextButton(
          onPressed: () {
            if (verifyAppLockPin(c.text.trim())) {
              _appLockPinMemory = c.text.trim();
              ok = true;
              Navigator.pop(ctx);
            } else {
              showToast('PIN incorrecto');
            }
          },
          child: const Text('Aceptar'),
        ),
      ],
    ),
  );
  c.dispose();
  return ok;
}

class PinLockGate extends StatefulWidget {
  final Widget child;

  const PinLockGate({Key? key, required this.child}) : super(key: key);

  @override
  State<PinLockGate> createState() => _PinLockGateState();
}

class _PinLockGateState extends State<PinLockGate> {
  final _controller = TextEditingController();
  String _correctPin = '';
  bool _unlocked = true;
  String? _error;
  String? _resumeHandler;

  @override
  void initState() {
    super.initState();
    _correctPin = getAppLockPin();
    // Sin PIN configurado no se bloquea nunca. Con PIN, se pide al iniciar
    // Windows o al volver de suspension, no en cada apertura de la app.
    _unlocked = _correctPin.isEmpty || appLockPinAlreadyAsked();
    _resumeHandler = 'pin_lock_${DateTime.now().microsecondsSinceEpoch}';
    platformFFI.registerEventHandler(
        _kResumeEvent, _resumeHandler!, (evt) async => _onResumed());
    bind.mainStartResumeWatcher();
    if (!_unlocked) {
      _bringToFront();
    }
  }

  // Cliente personalizado: el bloqueo es una pantalla dentro de la ventana, así
  // que si la ventana quedó oculta o detrás el PIN no se ve. La forzamos al
  // frente mientras está bloqueada y la soltamos al desbloquear.
  void _bringToFront() {
    if (!isDesktop) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        // La ventana puede haber quedado oculta (opacity 0 + minimizada + hide).
        await windowManager.restore();
        await windowManager.show();
        await windowManager.setOpacity(1);
        await windowManager.focus();
        await windowManager.setAlwaysOnTop(true);
      } catch (_) {}
    });
  }

  void _releaseForeground() {
    if (!isDesktop) return;
    windowManager.setAlwaysOnTop(false);
  }

  @override
  void dispose() {
    if (_resumeHandler != null) {
      platformFFI.unregisterEventHandler(_kResumeEvent, _resumeHandler!);
    }
    _controller.dispose();
    super.dispose();
  }

  // Vuelta de suspension de Windows: se vuelve a pedir el PIN.
  void _onResumed() {
    bumpAppLockResumeCount();
    if (_correctPin.isEmpty || !_unlocked) return;
    setState(() => _unlocked = false);
    _bringToFront();
  }

  void _submit() {
    if (verifyAppLockPin(_controller.text.trim())) {
      _appLockPinMemory = _controller.text.trim();
      _releaseForeground();
      markAppLockAsked();
      setState(() {
        _unlocked = true;
        _error = null;
      });
    } else {
      setState(() {
        _error = 'PIN incorrecto';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_unlocked) return widget.child;
    // El bloqueo se dibuja ENCIMA de la app (no la reemplaza) para que los
    // pedidos de conexion sigan funcionando con la app bloqueada y aparezcan al
    // desbloquear.
    return Stack(children: [
      Positioned.fill(child: IgnorePointer(child: widget.child)),
      Positioned.fill(
          child: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 300),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.lock_outline, size: 56),
                    const SizedBox(height: 16),
                    Text(
                      'Introduce el PIN para abrir',
                      style: Theme.of(context).textTheme.titleMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _controller,
                      autofocus: true,
                      obscureText: true,
                      maxLength: bind.mainMaxEncryptLen(),
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _submit(),
                      decoration: InputDecoration(
                        labelText: 'PIN',
                        errorText: _error,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _submit,
                        child: const Text('Desbloquear'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      )),
    ]);
  }
}
