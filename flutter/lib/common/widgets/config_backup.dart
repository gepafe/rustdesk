import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../common.dart';
import '../../models/platform_model.dart';

Future<void> showExportConfigBackupDialog(BuildContext context) async {
  final data = await bind.mainExportConfigBackup();
  if (data.isEmpty) {
    showToast('No se pudo generar la copia de seguridad');
    return;
  }
  if (!context.mounted) return;
  final controller = TextEditingController(text: data);
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Exportar copia de seguridad'),
      content: SizedBox(
          width: 560,
          height: 340,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                  'Copiá este texto y guardalo donde quieras (Google Drive, Notas, un mensaje a vos mismo). Con esto se recuperan los equipos, carpetas y toda la configuración.',
                  style: TextStyle(fontSize: 12)),
              const SizedBox(height: 8),
              Expanded(
                  child: TextField(
                      controller: controller,
                      readOnly: true,
                      maxLines: null,
                      expands: true,
                      style: const TextStyle(fontSize: 10))),
            ],
          )),
      actions: [
        TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: data));
              showToast('Copiado al portapapeles');
            },
            child: const Text('Copiar')),
        TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(translate('Close'))),
      ],
    ),
  );
}

Future<void> showImportConfigBackupDialog(BuildContext context) async {
  final controller = TextEditingController();
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Importar copia de seguridad'),
      content: SizedBox(
          width: 560,
          height: 340,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                  'Pegá el texto que guardaste. La app se va a cerrar sola para aplicar los datos: después abrila de nuevo.',
                  style: TextStyle(fontSize: 12)),
              const SizedBox(height: 8),
              Expanded(
                  child: TextField(
                      controller: controller,
                      maxLines: null,
                      expands: true,
                      decoration: const InputDecoration(
                          hintText: 'Pegá acá el texto de la copia...'),
                      style: const TextStyle(fontSize: 10))),
            ],
          )),
      actions: [
        TextButton(
            onPressed: () async {
              final clip = await Clipboard.getData(Clipboard.kTextPlain);
              final text = clip?.text ?? '';
              if (text.isNotEmpty) {
                controller.text = text;
              }
            },
            child: const Text('Pegar')),
        TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(translate('Close'))),
        TextButton(
            onPressed: () async {
              final text = controller.text.trim();
              if (text.isEmpty) {
                return;
              }
              final n = await bind.mainImportConfigBackup(data: text);
              if (ctx.mounted) {
                Navigator.pop(ctx);
              }
              if (n > 0) {
                showToast('Listo: $n archivos restaurados. La app se va a cerrar.');
              } else {
                showToast('No se pudo importar: el texto no es una copia válida');
              }
            },
            child: const Text('Importar')),
      ],
    ),
  );
}
