import 'package:flutter/material.dart';

import '../core/game_doc.dart';
import '../core/storage.dart';
import 'common.dart';
import 'element_editor.dart';
import 'items_tab.dart';
import 'perks_tab.dart';
import 'validation_tab.dart';

class EditorPage extends StatefulWidget {
  const EditorPage({super.key, required this.docs});

  final List<GameDoc> docs;

  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> {
  int _tab = 0;

  /// Документ, который правили последним: на вкладках «Проверка» и «XML»
  /// undo/redo относятся к нему.
  GameDoc? _lastDoc;

  GameDoc? _doc(DocKind k) {
    for (final d in widget.docs) {
      if (d.kind == k) return d;
    }
    return null;
  }

  GameDoc? get _current => switch (_tab) {
        0 => _doc(DocKind.list),
        1 => _doc(DocKind.perks),
        _ => _lastDoc,
      };

  bool get _anyDirty => widget.docs.any((d) => d.dirty);

  int get _errorCount => widget.docs
      .fold(0, (n, d) => n + d.validate().where((i) => i.isError).length);

  void _changed([GameDoc? doc]) {
    if (doc != null) _lastDoc = doc;
    setState(() {});
  }

  void _undo() {
    _current?.undo();
    _changed();
  }

  void _redo() {
    _current?.redo();
    _changed();
  }

  String get _undoTarget {
    final d = _current;
    return d == null ? '' : ' (${d.kind.fileName})';
  }

  Future<void> _save() async {
    if (_errorCount > 0) {
      final ok = await confirmDialog(
        context,
        'Есть ошибки',
        'В файлах $_errorCount ошибок. Всё равно сохранить?',
      );
      if (!ok || !mounted) return;
    }
    try {
      var n = 0;
      for (final d in widget.docs.where((d) => d.dirty)) {
        await Storage.write(d.path, d.toText(), viaShizuku: d.viaShizuku);
        d.markSaved();
        n++;
      }
      if (mounted) {
        snack(context,
            n == 0 ? 'Нечего сохранять' : 'Сохранено файлов: $n (оригинал — в *.bak)');
      }
    } catch (e) {
      if (mounted) await showErrorDialog(context, 'Не удалось сохранить:\n$e');
    }
    _changed();
  }

  Future<void> _openWhole(GameDoc d) async {
    final text = d.toText();
    if (text.length > 150000) {
      final ok = await confirmDialog(
        context,
        'Большой файл',
        '${d.kind.fileName} занимает ${(text.length / 1024).round()} КБ. '
            'Редактор целого файла может заметно тормозить. Для правки одного '
            'предмета или перка лучше открыть его XML из вкладок «Предметы»/«Перки». '
            'Открыть весь файл?',
      );
      if (!ok || !mounted) return;
    }
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => RawEditorPage(
        title: d.kind.fileName,
        text: text,
        hint: 'Полный XML файла',
        onApply: (t) {
          try {
            d.replaceAll(t);
            _changed(d);
            return null;
          } catch (e) {
            return 'Ошибка XML: $e';
          }
        },
      ),
    ));
  }

  Widget _missing(DocKind k) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Файл ${k.fileName} не загружен.\nВернитесь на главный экран и откройте его.',
            textAlign: TextAlign.center,
          ),
        ),
      );

  Widget _xmlTab() {
    final loaded = widget.docs;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Полный XML файла: удобно для массовых правок. Если структура сломана, '
          'приложение покажет строку с ошибкой.',
        ),
        const SizedBox(height: 12),
        for (final d in loaded)
          Card(
            child: ListTile(
              leading: const Icon(Icons.description_outlined),
              title: Text(d.kind.fileName),
              subtitle: Text(d.path, maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _openWhole(d),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final list = _doc(DocKind.list);
    final perks = _doc(DocKind.perks);
    final errors = _errorCount;

    return PopScope(
      canPop: !_anyDirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        final leave = await confirmDialog(
          context,
          'Несохранённые изменения',
          'Выйти без сохранения?',
        );
        if (leave) navigator.pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.docs.map((d) => d.kind.fileName).join(' + ')),
          actions: [
            IconButton(
              tooltip: 'Отменить$_undoTarget',
              onPressed: (_current?.canUndo ?? false) ? _undo : null,
              icon: const Icon(Icons.undo),
            ),
            IconButton(
              tooltip: 'Повторить$_undoTarget',
              onPressed: (_current?.canRedo ?? false) ? _redo : null,
              icon: const Icon(Icons.redo),
            ),
            IconButton(
              tooltip: 'Сохранить',
              onPressed: _anyDirty ? _save : null,
              icon: Badge(
                isLabelVisible: _anyDirty,
                smallSize: 8,
                child: const Icon(Icons.save),
              ),
            ),
          ],
        ),
        body: switch (_tab) {
          0 => list == null
              ? _missing(DocKind.list)
              : ItemsTab(doc: list, onChanged: () => _changed(list)),
          1 => perks == null
              ? _missing(DocKind.perks)
              : PerksTab(doc: perks, onChanged: () => _changed(perks)),
          2 => ValidationTab(docs: widget.docs, onChanged: _changed),
          _ => _xmlTab(),
        },
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (i) => setState(() => _tab = i),
          destinations: [
            const NavigationDestination(
                icon: Icon(Icons.inventory_2_outlined), label: 'Предметы'),
            const NavigationDestination(
                icon: Icon(Icons.auto_awesome_outlined), label: 'Перки'),
            NavigationDestination(
              icon: Badge(
                isLabelVisible: errors > 0,
                label: Text('$errors'),
                child: const Icon(Icons.fact_check_outlined),
              ),
              label: 'Проверка',
            ),
            const NavigationDestination(icon: Icon(Icons.code), label: 'XML'),
          ],
        ),
      ),
    );
  }
}