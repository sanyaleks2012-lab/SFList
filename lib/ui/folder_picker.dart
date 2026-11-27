import 'dart:io';

import 'package:flutter/material.dart';

import '../core/game_doc.dart';

/// Простой выбор папки без плагинов.
///
/// Зачем не file_picker: на Android он копирует выбранный файл в кэш приложения,
/// и сохранение изменило бы копию, а не оригинал. Здесь возвращается настоящий путь.
/// Нужен доступ «Ко всем файлам». Папки Android/data с Android 11 доступны только через Shizuku.
class FolderPickerPage extends StatefulWidget {
  const FolderPickerPage({super.key, required this.initial});

  final String initial;

  @override
  State<FolderPickerPage> createState() => _FolderPickerPageState();
}

class _FolderPickerPageState extends State<FolderPickerPage> {
  static const _root = '/storage/emulated/0';

  late Directory _dir;
  List<Directory> _subs = [];
  Set<String> _found = {};
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    final start = Directory(widget.initial.trim());
    _dir = start.existsSync() ? start : Directory(_root);
    _load();
  }

  static String _name(String path) {
    final parts = path.split('/').where((s) => s.isNotEmpty).toList();
    return parts.isEmpty ? '/' : parts.last;
  }

  Future<void> _load() async {
    final subs = <Directory>[];
    final found = <String>{};
    String? error;
    try {
      await for (final e in _dir.list(followLinks: false)) {
        final name = _name(e.path);
        if (e is Directory) {
          if (!name.startsWith('.')) subs.add(e);
        } else if (e is File) {
          for (final k in DocKind.values) {
            if (name == k.fileName) found.add(name);
          }
        }
      }
      subs.sort((a, b) => _name(a.path).toLowerCase().compareTo(_name(b.path).toLowerCase()));
    } catch (e) {
      error = 'Нет доступа к папке.\n'
          'Нужен доступ «Ко всем файлам»; папки Android/data открываются только через Shizuku.\n\n$e';
    }
    if (!mounted) return;
    setState(() {
      _subs = subs;
      _found = found;
      _error = error;
      _loading = false;
    });
  }

  void _go(Directory d) {
    setState(() {
      _dir = d;
      _loading = true;
    });
    _load();
  }

  bool get _canGoUp => _dir.path != '/' && _dir.parent.path != _dir.path;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Выбор папки')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: SelectableText(
                _dir.path,
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Wrap(
              spacing: 8,
              children: [
                ActionChip(
                  label: const Text('Память'),
                  onPressed: () => _go(Directory(_root)),
                ),
                ActionChip(
                  label: const Text('Download'),
                  onPressed: () => _go(Directory('$_root/Download')),
                ),
                for (final k in DocKind.values)
                  Chip(
                    avatar: Icon(_found.contains(k.fileName) ? Icons.check : Icons.close, size: 18),
                    label: Text(k.fileName),
                  ),
              ],
            ),
          ),
          const Divider(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(_error!, textAlign: TextAlign.center),
                        ),
                      )
                    : ListView(
                        children: [
                          if (_canGoUp)
                            ListTile(
                              leading: const Icon(Icons.arrow_upward),
                              title: const Text('..'),
                              onTap: () => _go(_dir.parent),
                            ),
                          for (final d in _subs)
                            ListTile(
                              leading: const Icon(Icons.folder_outlined),
                              title: Text(_name(d.path)),
                              onTap: () => _go(d),
                            ),
                        ],
                      ),
          ),
          SafeArea(
            minimum: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => Navigator.of(context).pop(_dir.path),
                icon: const Icon(Icons.check),
                label: const Text('Выбрать эту папку'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
