import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:xml/xml.dart';

import '../core/game_doc.dart';
import '../core/shizuku_bridge.dart';
import '../core/storage.dart';
import 'common.dart';
import 'editor_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _shizuku = false;
  String? _listPath;
  String? _perksPath;
  final _pkg = TextEditingController(text: 'com.onerdna.sfml');
  ShizukuStatus? _status;
  Set<String> _found = {};
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    Prefs.lastPackage().then((p) {
      if (p != null && mounted) _pkg.text = p;
    });
    _refreshStatus();
  }

  @override
  void dispose() {
    _pkg.dispose();
    super.dispose();
  }

  Future<void> _refreshStatus() async {
    try {
      _status = await ShizukuBridge.status();
    } catch (_) {
      _status = const ShizukuStatus(false, false);
    }
    if (mounted) setState(() {});
  }

  Future<void> _requestShizuku() async {
    try {
      await ShizukuBridge.request();
    } catch (e) {
      if (mounted) await showErrorDialog(context, '$e');
    }
    await _refreshStatus();
  }

  Future<void> _scan() async {
    try {
      final files = await ShizukuBridge.list(ShizukuBridge.gameDataDir(_pkg.text.trim()));
      setState(() => _found = files.toSet());
    } catch (e) {
      if (mounted) snack(context, 'Не удалось прочитать папку: $e');
    }
  }

  Future<void> _pick(DocKind kind) async {
    final r = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['xml'],
      dialogTitle: kind.fileName,
    );
    final path = r?.files.single.path;
    if (path == null) return;
    setState(() {
      if (kind == DocKind.list) {
        _listPath = path;
      } else {
        _perksPath = path;
      }
    });
  }

  Future<void> _open() async {
    setState(() => _busy = true);
    try {
      final docs = <GameDoc>[];

      if (_shizuku) {
        final pkg = _pkg.text.trim();
        if (pkg.isEmpty) throw 'Укажите пакет игры';
        final st = await ShizukuBridge.status();
        if (!st.running) throw 'Shizuku не запущен. Запустите его и повторите';
        if (!st.granted) {
          await ShizukuBridge.request();
          throw 'Выдайте доступ Shizuku SFList и нажмите «Открыть» снова';
        }
        await Prefs.setLastPackage(pkg);
        final dir = ShizukuBridge.gameDataDir(pkg);
        final files = await ShizukuBridge.list(dir);
        for (final kind in DocKind.values) {
          if (!files.contains(kind.fileName)) continue;
          final path = '$dir/${kind.fileName}';
          final text = await Storage.read(path, viaShizuku: true);
          docs.add(GameDoc.parse(kind, path, text, viaShizuku: true));
        }
      } else {
        if (!await Storage.ensureAllFiles()) {
          throw 'Нужен доступ «Все файлы» (Настройки → Приложения → SFList)';
        }
        final picked = {DocKind.list: _listPath, DocKind.perks: _perksPath};
        for (final entry in picked.entries) {
          final path = entry.value;
          if (path == null) continue;
          final text = await Storage.read(path, viaShizuku: false);
          docs.add(GameDoc.parse(entry.key, path, text));
        }
      }

      if (docs.isEmpty) throw 'Не найдено ни list.xml, ни perks.xml';
      if (!mounted) return;
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => EditorPage(docs: docs)));
    } on XmlParserException catch (e) {
      if (mounted) {
        await showErrorDialog(
          context,
          'Ошибка XML: строка ${e.line}, колонка ${e.column}\n${e.message}\n\n'
          'Откройте файл в редакторе XML или исправьте строку вручную.',
        );
      }
    } catch (e) {
      if (mounted) await showErrorDialog(context, '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('SFList')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, icon: Icon(Icons.folder_outlined), label: Text('Файлы')),
              ButtonSegment(value: true, icon: Icon(Icons.adb), label: Text('Shizuku')),
            ],
            selected: {_shizuku},
            onSelectionChanged: (s) {
              setState(() => _shizuku = s.first);
              if (_shizuku) _refreshStatus();
            },
          ),
          const SizedBox(height: 20),
          if (_shizuku) ..._shizukuSection() else ..._fileSection(),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _busy ? null : _open,
            icon: const Icon(Icons.edit_note),
            label: const Text('Открыть'),
          ),
        ],
      ),
    );
  }

  List<Widget> _fileSection() => [
        _FileRow(
          label: 'list.xml',
          path: _listPath,
          onPick: () => _pick(DocKind.list),
        ),
        const SizedBox(height: 10),
        _FileRow(
          label: 'perks.xml',
          path: _perksPath,
          onPick: () => _pick(DocKind.perks),
        ),
        const SizedBox(height: 10),
        const Text(
          'Можно выбрать один или оба файла. Для папки Android/data используйте Shizuku.',
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: Storage.ensureAllFiles,
          icon: const Icon(Icons.lock_open),
          label: const Text('Доступ ко всем файлам'),
        ),
      ];

  List<Widget> _shizukuSection() {
    final st = _status;
    final ok = st?.granted ?? false;
    return [
      Card(
        child: ListTile(
          leading: Icon(
            ok ? Icons.check_circle : Icons.warning_amber,
            color: ok ? Colors.green : Colors.amber,
          ),
          title: Text(
            st == null
                ? 'Проверка…'
                : !st.running
                    ? 'Shizuku не запущен'
                    : ok
                        ? 'Доступ выдан'
                        : 'Нужно разрешение Shizuku',
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (st?.running == true && !ok)
                TextButton(onPressed: _requestShizuku, child: const Text('Выдать')),
              IconButton(icon: const Icon(Icons.refresh), onPressed: _refreshStatus),
            ],
          ),
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _pkg,
        decoration: const InputDecoration(
          labelText: 'Пакет игры',
          hintText: 'com.onerdna.sfml',
          border: OutlineInputBorder(),
        ),
        onSubmitted: (_) => _scan(),
      ),
      const SizedBox(height: 8),
      Text(
        ShizukuBridge.gameDataDir(_pkg.text.trim()),
        style: TextStyle(
          fontSize: 12,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: 10),
      OutlinedButton.icon(
        onPressed: _scan,
        icon: const Icon(Icons.search),
        label: const Text('Найти файлы'),
      ),
      const SizedBox(height: 10),
      Wrap(
        spacing: 8,
        children: [
          for (final k in DocKind.values)
            Chip(
              avatar: Icon(_found.contains(k.fileName) ? Icons.check : Icons.close, size: 18),
              label: Text(k.fileName),
            ),
        ],
      ),
    ];
  }
}

class _FileRow extends StatelessWidget {
  const _FileRow({required this.label, required this.path, required this.onPick});

  final String label;
  final String? path;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.insert_drive_file_outlined),
        title: Text(label),
        subtitle: Text(
          path ?? 'Не выбран',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: IconButton(
          tooltip: 'Выбрать файл',
          icon: const Icon(Icons.folder_open),
          onPressed: onPick,
        ),
      ),
    );
  }
}