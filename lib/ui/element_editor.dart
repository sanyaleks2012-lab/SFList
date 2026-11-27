import 'package:flutter/material.dart';
import 'package:xml/xml.dart';

import '../core/field_specs.dart';
import '../core/game_doc.dart';
import 'common.dart';

/// Универсальный редактор атрибутов любого элемента.
class ElementEditorPage extends StatefulWidget {
  const ElementEditorPage({
    super.key,
    required this.title,
    required this.attributes,
    required this.fields,
    required this.onSave,
    this.onRaw,
    this.onDelete,
    this.extras = const [],
    this.requireName = false,
    this.validator,
  });

  final String title;
  final Map<String, String> attributes;
  final List<FieldSpec> fields;
  final void Function(Map<String, String> values) onSave;
  final VoidCallback? onRaw;
  final VoidCallback? onDelete;
  final List<Widget> extras;

  /// Не даёт сохранить запись без атрибута Name.
  final bool requireName;

  /// Доп. проверка перед сохранением: вернуть текст ошибки или null.
  final String? Function(Map<String, String> values)? validator;

  @override
  State<ElementEditorPage> createState() => _ElementEditorPageState();
}

class _ElementEditorPageState extends State<ElementEditorPage> {
  final _c = <String, TextEditingController>{};
  // Удалённые из формы контроллеры освобождаем только в dispose(): поле ещё
  // может быть на экране до следующей перерисовки.
  final _trash = <TextEditingController>[];
  static final _attrNameRe = RegExp(r'^[A-Za-z_][A-Za-z0-9_.\-]*$');
  final _newKey = TextEditingController();
  final _newVal = TextEditingController();

  @override
  void initState() {
    super.initState();
    for (final f in widget.fields) {
      _c[f.key] = TextEditingController(text: widget.attributes[f.key] ?? '');
    }
    widget.attributes.forEach((k, v) {
      _c.putIfAbsent(k, () => TextEditingController(text: v));
    });
  }

  @override
  void dispose() {
    for (final c in [..._c.values, ..._trash]) {
      c.dispose();
    }
    _newKey.dispose();
    _newVal.dispose();
    super.dispose();
  }

  Set<String> get _fieldKeys => widget.fields.map((f) => f.key).toSet();

  void _addAttr() {
    final k = _newKey.text.trim();
    if (k.isEmpty) return;
    if (!_attrNameRe.hasMatch(k)) {
      snack(context, 'Недопустимое имя атрибута: «$k». Только латиница, цифры, _ . -');
      return;
    }
    final v = _newVal.text.trim();
    setState(() {
      final existing = _c[k];
      if (existing != null) {
        existing.text = v; // атрибут уже есть: просто обновляем значение
      } else {
        _c[k] = TextEditingController(text: v);
      }
      _newKey.clear();
      _newVal.clear();
    });
  }

  /// Собирает значения формы и передаёт в [ElementEditorPage.onSave].
  /// Возвращает false, если данные некорректны (причина показана в snackbar).
  bool _commit() {
    final out = <String, String>{};
    for (final f in widget.fields) {
      final v = _c[f.key]!.text.trim();
      // поля с '@' всегда передаются (нужно уметь очистить шаблон)
      if (v.isEmpty && !f.key.startsWith('@')) continue;
      if (f.numeric && v.isNotEmpty && num.tryParse(v) == null) {
        snack(context, '«${f.label}»: нужно число');
        return false;
      }
      out[f.key] = v;
    }
    for (final e in _c.entries) {
      if (_fieldKeys.contains(e.key)) continue;
      final v = e.value.text.trim();
      if (v.isNotEmpty) out[e.key] = v;
    }
    if (widget.requireName && (out['Name'] ?? '').isEmpty) {
      snack(context, 'Name не может быть пустым');
      return false;
    }
    final err = widget.validator?.call(out);
    if (err != null) {
      snack(context, err);
      return false;
    }
    widget.onSave(out);
    return true;
  }

  void _save() {
    if (_commit()) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final extraKeys = _c.keys.where((k) => !_fieldKeys.contains(k)).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, overflow: TextOverflow.ellipsis),
        actions: [
          if (widget.onRaw != null)
            IconButton(
              tooltip: 'Открыть XML',
              icon: const Icon(Icons.code),
              onPressed: () {
                // Сначала применяем правки формы, чтобы они не потерялись.
                if (!_commit()) return;
                Navigator.of(context).pop();
                widget.onRaw!();
              },
            ),
          IconButton(tooltip: 'Сохранить', icon: const Icon(Icons.check), onPressed: _save),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final f in widget.fields) ...[
            TextField(
              controller: _c[f.key],
              keyboardType: f.numeric
                  ? const TextInputType.numberWithOptions(decimal: true, signed: true)
                  : null,
              decoration: InputDecoration(
                labelText: f.label,
                helperText: f.hint,
                border: const OutlineInputBorder(),
              ),
            ),
            if (f.suggestions.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6, bottom: 4),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final s in f.suggestions)
                      ActionChip(
                        label: Text(s),
                        onPressed: () => setState(() => _c[f.key]!.text = s),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 14),
          ],
          ...widget.extras,
          ExpansionTile(
            title: Text('Все остальные атрибуты (${extraKeys.length})'),
            initiallyExpanded: true,
            childrenPadding: const EdgeInsets.only(top: 8),
            children: [
              for (final k in extraKeys)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _c[k],
                          decoration: InputDecoration(
                            labelText: k,
                            border: const OutlineInputBorder(),
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Удалить атрибут',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => setState(() {
                          final removed = _c.remove(k);
                          if (removed != null) _trash.add(removed);
                        }),
                      ),
                    ],
                  ),
                ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _newKey,
                      decoration: const InputDecoration(labelText: 'Имя', isDense: true),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _newVal,
                      decoration: const InputDecoration(labelText: 'Значение', isDense: true),
                    ),
                  ),
                  IconButton(icon: const Icon(Icons.add), onPressed: _addAttr),
                ],
              ),
              const SizedBox(height: 12),
            ],
          ),
          if (widget.onDelete != null) ...[
            const SizedBox(height: 24),
            FilledButton.tonalIcon(
              style: FilledButton.styleFrom(foregroundColor: theme.colorScheme.error),
              icon: const Icon(Icons.delete),
              label: const Text('Удалить'),
              onPressed: () async {
                final ok = await confirmDialog(context, 'Удалить?', widget.title);
                if (!ok || !context.mounted) return;
                widget.onDelete!();
                Navigator.of(context).pop();
              },
            ),
          ],
        ],
      ),
    );
  }
}

/// Редактор сырого XML (элемент или весь файл).
class RawEditorPage extends StatefulWidget {
  const RawEditorPage({
    super.key,
    required this.title,
    required this.text,
    required this.onApply,
    this.hint,
  });

  final String title;
  final String text;
  final String? hint;
  /// Возвращает null при успехе, иначе текст ошибки.
  final String? Function(String text) onApply;

  @override
  State<RawEditorPage> createState() => _RawEditorPageState();
}

class _RawEditorPageState extends State<RawEditorPage> {
  late final _c = TextEditingController(text: widget.text);
  String? _error;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _apply() {
    final err = widget.onApply(_c.text);
    if (err == null) {
      if (mounted) Navigator.of(context).pop();
    } else {
      setState(() => _error = err);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(tooltip: 'Применить', icon: const Icon(Icons.check), onPressed: _apply),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            if (_error != null)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: cs.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(_error!, style: TextStyle(color: cs.onErrorContainer)),
              ),
            Expanded(
              child: TextField(
                controller: _c,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  hintText: widget.hint,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void openRawElement(
  BuildContext context,
  GameDoc doc,
  XmlElement el,
  VoidCallback onChanged,
) {
  Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => RawEditorPage(
      title: el.getAttribute('Name') ?? el.name.local,
      text: doc.elementText(el),
      hint: 'XML элемента целиком. Структура должна остаться валидной.',
      onApply: (t) {
        try {
          doc.replaceElement(el, t);
          onChanged();
          return null;
        } catch (e) {
          return 'Ошибка XML: $e';
        }
      },
    ),
  ));
}