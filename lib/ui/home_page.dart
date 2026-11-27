import 'dart:io';

import 'package:flutter/material.dart';

import '../core/game_doc.dart';
import '../core/shizuku_bridge.dart';
import '../core/storage.dart';
import 'common.dart';
import 'editor_page.dart';
import 'folder_picker.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  static const _defaultDir = '/storage/emulated/0';

  bool _shizuku = false;
  final _dir = TextEditingController(text: _defaultDir);
  final _pkg = TextEditingController(text: 'com.onerdna.sfml');
  ShizukuStatus? _status;
  Set<String> _found = {};
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _restorePrefs();
    _refreshStatus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _dir.dispose();
    _pkg.dispose();
    super.dispose();
  }

  /// Вернулись из Shizuku / настроек: обновляем статус, чтобы не жать «обновить» вручную.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _shizuku) _refreshStatus();
  }

  Future<void> _restorePrefs() async {
    final pkg = await Prefs.lastPackage();
    final dir = await Prefs.lastDir();
    final shizuku = await Prefs.lastModeShizuku();
    if (!mounted) return;
    setState(() {
      if (pkg != null && pkg.isNotEmpty) _pkg.text = pkg;
      if (dir != null && dir.isNotEmpty) _dir.text = dir;
      _shizuku = shizuku;
    });
  }

  Future<void> _refreshStatus() async {
    ShizukuStatus st;
    try {
      st = await ShizukuBridge.status();
    } catch (_) {
      st = const ShizukuStatus(false, false);
    }
    if (mounted) setState(() => _status = st);
  }

  Future<void> _requestShizuku() async {
    try {
      final ok = await ShizukuBridge.request();
      if (!ok && mounted) {
        snack(context,
            'Доступ не выдан. Откройте Shizuku → «Авторизованные приложения» и включите SFList');
      }
    } catch (e) {
      if (mounted) await showErrorDialog(context, '$e');
    }
    await _refreshStatus();
  }

  /// Папка из поля «Файлы»: можно вставить и путь к самому файлу .xml.
  String _normalizedDir() {
    var p = _dir.text.trim();
    if (p.toLowerCase().endsWith('.xml')) {
      final i = p.lastIndexOf('/');
      if (i > 0) p = p.substring(0, i);
    }
    while (p.length > 1 && p.endsWith('/')) {
      p = p.substring(0, p.length - 1);
    }
    return p;
  }

  Future<void> _scan() async {
    try {
      final names = DocKind.values.map((k) => k.fileName);
      Set<String> found;
      if (_shizuku) {
        final pkg = _pkg.text.trim();
        if (!ShizukuBridge.isValidPackage(pkg)) {
          throw 'Некорректное имя пакета: «$pkg»';
        }
        final files = await ShizukuBridge.list(ShizukuBridge.gameDataDir(pkg));
        found = files.where(names.contains).toSet();
      } else {
        if (!await Storage.ensureAllFiles()) {
          throw 'Нет доступа ко всем файлам';
        }
        found = await Storage.existing(_normalizedDir(), names);
      }
      if (mounted) setState(() => _found = found);
    } catch (e) {
      if (mounted) {
        setState(() => _found = {});
        snack(context, 'Не удалось прочитать папку: $e');
      }
    }
  }

  Future<void> _browse() async {
    if (!await Storage.ensureAllFiles()) {
      if (mounted) snack(context, 'Нужен доступ «Ко всем файлам»');
      return;
    }
    if (!mounted) return;
    final picked = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => FolderPickerPage(initial: _normalizedDir())),
    );
    if (picked == null || !mounted) return;
    _dir.text = picked;
    await _scan();
  }

  Future<GameDoc> _loadDoc(DocKind kind, String path, {required bool viaShizuku}) async {
    final text = await Storage.read(path, viaShizuku: viaShizuku);
    try {
      return GameDoc.parse(kind, path, text, viaShizuku: viaShizuku);
    } on DocFormatException {
      rethrow;
    } catch (e) {
      throw '${kind.fileName}: ошибка XML.\n$e\n\n'
          'Исправьте файл в текстовом редакторе и откройте снова.';
    }
  }

  Future<void> _open() async {
    setState(() => _busy = true);
    try {
      final docs = <GameDoc>[];

      if (_shizuku) {
        final pkg = _pkg.text.trim();
        if (!ShizukuBridge.isValidPackage(pkg)) {
          throw 'Укажите имя пакета игры, например com.onerdna.sfml';
        }
        final st = await ShizukuBridge.status();
        if (!st.running) throw 'Shizuku не запущен. Запустите его и повторите';
        if (!st.granted) {
          final ok = await ShizukuBridge.request();
          if (!ok) {
            throw 'Доступ Shizuku не выдан. Откройте Shizuku → «Авторизованные '
                'приложения» и включите SFList';
          }
        }
        final dir = ShizukuBridge.gameDataDir(pkg);
        final files = await ShizukuBridge.list(dir);
        for (final kind in DocKind.values) {
          if (!files.contains(kind.fileName)) continue;
          docs.add(await _loadDoc(kind, '$dir/${kind.fileName}', viaShizuku: true));
        }
        await Prefs.setLastPackage(pkg);
      } else {
        if (!await Storage.ensureAllFiles()) {
          throw 'Нужен доступ «Все файлы» (Настройки → Приложения → SFList)';
        }
        final dir = _normalizedDir();
        if (dir.isEmpty || !await Directory(dir).exists()) {
          throw 'Папка не найдена: $dir';
        }
        for (final kind in DocKind.values) {
          final path = '$dir/${kind.fileName}';
          if (!await File(path).exists()) continue;
          docs.add(await _loadDoc(kind, path, viaShizuku: false));
        }
        await Prefs.setLastDir(dir);
      }
      await Prefs.setLastModeShizuku(_shizuku);

      if (docs.isEmpty) throw 'В папке нет ни list.xml, ни perks.xml';
      if (!mounted) return;
      await Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => EditorPage(docs: docs)));
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
              setState(() {
                _shizuku = s.first;
                _found = {};
              });
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

  Widget _foundChips() => Wrap(
        spacing: 8,
        children: [
          for (final k in DocKind.values)
            Chip(
              avatar: Icon(_found.contains(k.fileName) ? Icons.check : Icons.close, size: 18),
              label: Text(k.fileName),
            ),
        ],
      );

  List<Widget> _fileSection() => [
        TextField(
          controller: _dir,
          decoration: InputDecoration(
            labelText: 'Папка с list.xml и perks.xml',
            hintText: _defaultDir,
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              tooltip: 'Выбрать папку',
              icon: const Icon(Icons.folder_open),
              onPressed: _browse,
            ),
          ),
          onSubmitted: (_) => _scan(),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: () async {
                await Storage.ensureAllFiles();
                await _scan();
              },
              icon: const Icon(Icons.lock_open),
              label: const Text('Доступ ко всем файлам'),
            ),
            OutlinedButton.icon(
              onPressed: _scan,
              icon: const Icon(Icons.search),
              label: const Text('Найти файлы'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _foundChips(),
        const SizedBox(height: 10),
        const Text(
          'Откроются те из list.xml и perks.xml, что лежат в папке. '
          'Папки Android/data с Android 11 недоступны напрямую, для них используйте Shizuku.',
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
        // Обновляем строку с путём под полем при каждом символе.
        onChanged: (_) => setState(() => _found = {}),
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
      _foundChips(),
    ];
  }
}
