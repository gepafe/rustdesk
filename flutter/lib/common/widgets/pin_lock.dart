import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/models/platform_model.dart';

/// Cliente personalizado: pantalla de bloqueo al abrir la aplicación.
///
/// Pide el MISMO PIN que se configura en Configuración -> Seguridad.
/// Si no hay PIN configurado (o está deshabilitado), no bloquea la app.
/// Solo afecta a la ventana principal; las conexiones entrantes las atiende
/// el servicio, por lo que siguen funcionando con normalidad.
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
    _correctPin = isUnlockPinDisabled() ? '' : bind.mainGetUnlockPin();
    // Si no hay PIN configurado, no se bloquea la aplicación.
    _unlocked = _correctPin.isEmpty;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_controller.text.trim() == _correctPin) {
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
    return Scaffold(
      body: Center(
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
    );
  }
}
