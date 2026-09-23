import 'dart:convert';

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

/// Lee el PIN de bloqueo de la app (guardado codificado en una local option).
String getAppLockPin() {
  final raw = bind.mainGetLocalOption(key: kOptionAppLockPin);
  if (raw.isEmpty) return '';
  try {
    return utf8.decode(base64.decode(raw));
  } catch (_) {
    return '';
  }
}

/// Guarda (o borra, si se pasa vacío) el PIN de bloqueo de la app.
Future<void> setAppLockPin(String pin) async {
  await bind.mainSetLocalOption(
      key: kOptionAppLockPin,
      value: pin.isEmpty ? '' : base64Encode(utf8.encode(pin)));
}

/// True si hay un PIN de bloqueo de la app configurado.
bool isAppLockEnabled() => getAppLockPin().isNotEmpty;

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

  @override
  void initState() {
    super.initState();
    _correctPin = getAppLockPin();
    // Si no hay PIN configurado, no se bloquea la aplicación.
    _unlocked = _correctPin.isEmpty;
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
        await windowManager.show();
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
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_controller.text.trim() == _correctPin) {
      _releaseForeground();
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
