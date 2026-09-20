import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/models/platform_model.dart';

/// Carpeta (grupo) de equipos creada por el usuario, estilo TeamViewer.
class PeerFolder {
  String name;
  List<String> ids;
  bool expanded;

  PeerFolder({required this.name, List<String>? ids, this.expanded = true})
      : ids = ids ?? <String>[];

  Map<String, dynamic> toJson() =>
      {'name': name, 'ids': ids, 'expanded': expanded};

  factory PeerFolder.fromJson(Map<String, dynamic> json) => PeerFolder(
        name: json['name']?.toString() ?? '',
        ids: (json['ids'] as List?)
                ?.map((e) => e.toString())
                .toList(growable: true) ??
            <String>[],
        expanded: json['expanded'] as bool? ?? true,
      );
}

/// Almacen local de carpetas de equipos (persistido en una opcion local).
class PeerFolderModel extends ChangeNotifier {
  static const String _kOption = 'device-folders';
  static const String _kFlagsOption = 'peer-flags';
  final List<PeerFolder> folders = <PeerFolder>[];
  bool ungroupedExpanded = true;

  PeerFolderModel() {
    load();
    _loadFlags();
  }

  void load() {
    try {
      final raw = bind.getLocalFlutterOption(k: _kOption);
      if (raw.isEmpty) return;
      final list = jsonDecode(raw) as List;
      folders
        ..clear()
        ..addAll(list.map((e) => PeerFolder.fromJson(e as Map<String, dynamic>)));
    } catch (e) {
      debugPrint('failed to load device folders: $e');
    }
  }

  void save() {
    try {
      bind.setLocalFlutterOption(
          k: _kOption, v: jsonEncode(folders.map((e) => e.toJson()).toList()));
    } catch (e) {
      debugPrint('failed to save device folders: $e');
    }
  }

  PeerFolder? folderByName(String name) {
    for (final f in folders) {
      if (f.name == name) return f;
    }
    return null;
  }

  PeerFolder? folderOf(String id) {
    for (final f in folders) {
      if (f.ids.contains(id)) return f;
    }
    return null;
  }

  bool addFolder(String name, {bool notify = true}) {
    name = name.trim();
    if (name.isEmpty || folderByName(name) != null) return false;
    folders.add(PeerFolder(name: name));
    save();
    if (notify) notifyListeners();
    return true;
  }

  void removeFolder(String name) {
    folders.removeWhere((f) => f.name == name);
    save();
    notifyListeners();
  }

  void renameFolder(String oldName, String newName) {
    newName = newName.trim();
    if (newName.isEmpty || newName == oldName) return;
    final f = folderByName(oldName);
    if (f == null || folderByName(newName) != null) return;
    f.name = newName;
    save();
    notifyListeners();
  }

  void setPeerFolder(String id, String? folderName) {
    for (final f in folders) {
      f.ids.remove(id);
    }
    if (folderName != null) {
      folderByName(folderName)?.ids.add(id);
    }
    save();
    notifyListeners();
  }

  void toggleExpanded(String name) {
    final f = folderByName(name);
    if (f == null) return;
    f.expanded = !f.expanded;
    save();
    notifyListeners();
  }

  void toggleUngroupedExpanded() {
    ungroupedExpanded = !ungroupedExpanded;
    notifyListeners();
  }

  // Marcas por equipo (vista previa / solo ver), persistidas localmente.
  final Map<String, Map<String, bool>> _flags = <String, Map<String, bool>>{};

  bool isPreview(String id) => _flags[id]?['preview'] == true;
  bool isViewOnly(String id) => _flags[id]?['viewOnly'] == true;

  void setPreview(String id, bool value) {
    _setFlag(id, 'preview', value);
  }

  void setViewOnly(String id, bool value) {
    _setFlag(id, 'viewOnly', value);
  }

  void _setFlag(String id, String key, bool value) {
    (_flags[id] ??= <String, bool>{})[key] = value;
    _saveFlags();
    notifyListeners();
  }

  void _loadFlags() {
    try {
      final raw = bind.getLocalFlutterOption(k: _kFlagsOption);
      if (raw.isEmpty) return;
      final map = jsonDecode(raw) as Map;
      _flags.clear();
      map.forEach((k, v) {
        final m = <String, bool>{};
        (v as Map).forEach((k2, v2) {
          if (v2 is bool) m[k2.toString()] = v2;
        });
        _flags[k.toString()] = m;
      });
    } catch (e) {
      debugPrint('failed to load peer flags: $e');
    }
  }

  void _saveFlags() {
    try {
      bind.setLocalFlutterOption(k: _kFlagsOption, v: jsonEncode(_flags));
    } catch (e) {
      debugPrint('failed to save peer flags: $e');
    }
  }
}

PeerFolderModel? _peerFolderModelInstance;
PeerFolderModel get peerFolderModel =>
    _peerFolderModelInstance ??= PeerFolderModel();

/// Dialogo para crear una nueva carpeta. [onCreated] recibe el nombre creado.
void showNewFolderDialog({ValueChanged<String>? onCreated}) {
  final controller = TextEditingController();
  gFFI.dialogManager.show((setState, close, context) {
    submit() {
      final name = controller.text.trim();
      if (name.isEmpty) return;
      final ok = peerFolderModel.addFolder(name);
      if (!ok) return;
      onCreated?.call(name);
      close();
    }

    return CustomAlertDialog(
      title: Text(translate("Nueva carpeta")),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLength: 30,
        decoration: InputDecoration(hintText: translate("Nombre")),
        onSubmitted: (_) => submit(),
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

/// Dialogo para elegir la carpeta de un equipo.
void showPeerFolderPickerDialog(String peerId) {
  gFFI.dialogManager.show((setState, close, context) {
    Widget entry(IconData icon, String label, VoidCallback onTap) {
      return ListTile(
        dense: true,
        leading: Icon(icon, size: 20),
        title: Text(label),
        onTap: onTap,
      );
    }

    return CustomAlertDialog(
      title: Text(translate("Mover a carpeta")),
      content: SizedBox(
        width: 320,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ...peerFolderModel.folders.map((f) => entry(
                  Icons.folder,
                  f.name,
                  () {
                    peerFolderModel.setPeerFolder(peerId, f.name);
                    close();
                  })),
              entry(Icons.remove_circle_outline, translate("Sin grupo"), () {
                peerFolderModel.setPeerFolder(peerId, null);
                close();
              }),
              entry(Icons.create_new_folder_outlined, translate("Nueva carpeta..."),
                  () {
                close();
                showNewFolderDialog(
                    onCreated: (name) =>
                        peerFolderModel.setPeerFolder(peerId, name));
              }),
            ],
          ),
        ),
      ),
      actions: [
        dialogButton(translate("Cancel"), onPressed: close, isOutline: true),
      ],
      onCancel: close,
    );
  });
}

/// Dialogo para renombrar una carpeta.
void showFolderRenameDialog(String oldName) {
  final controller = TextEditingController(text: oldName);
  gFFI.dialogManager.show((setState, close, context) {
    submit() {
      final name = controller.text.trim();
      if (name.isEmpty || name == oldName) {
        close();
        return;
      }
      peerFolderModel.renameFolder(oldName, name);
      close();
    }

    return CustomAlertDialog(
      title: Text(translate("Renombrar carpeta")),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLength: 30,
        decoration: InputDecoration(hintText: translate("Nombre")),
        onSubmitted: (_) => submit(),
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

/// Dialogo de confirmacion para eliminar una carpeta.
void showFolderDeleteDialog(String name) {
  gFFI.dialogManager.show((setState, close, context) {
    return CustomAlertDialog(
      title: Text(translate("Eliminar carpeta")),
      content: Text(
        '${translate('Eliminar carpeta')} "$name"?',
        style: const TextStyle(fontSize: 15),
      ),
      actions: [
        dialogButton(translate("Cancel"), onPressed: close, isOutline: true),
        dialogButton(translate("OK"), onPressed: () {
          peerFolderModel.removeFolder(name);
          close();
        }),
      ],
      onCancel: close,
    );
  });
}
