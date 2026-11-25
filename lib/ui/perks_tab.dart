import 'package:flutter/material.dart';
import 'package:xml/xml.dart';

import '../core/field_specs.dart';
import '../core/game_doc.dart';
import 'common.dart';
import 'element_editor.dart';

class PerksTab extends StatefulWidget {
  const PerksTab({super.key, required this.doc, required this.onChanged});

  final GameDoc doc;
  final VoidCallback onChanged;

  @override
  State<PerksTab> createState() => _PerksTabState();
}

class _PerksTabState extends State<PerksTab> {
  String _query = '';

  void _changed() {
    setState(() {});
    widget.onChanged();
  }

  void _edit(XmlElement p) {
    final attrs = {for (final a in p.attributes) a.name.local: a.value};
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ElementEditorPage(
        title: p.getAttribute('Name') ?? 'Перк',
        attributes: attrs,
        fields: perkFields,
        extras: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.tune),
              title: const Text('Параметры эффекта (Set)'),
              subtitle: const Text('Шанс, длительность, тип удара, множители'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _editSet(p),
            ),
          ),
          const SizedBox(height: 16),
        ],
        onSave: (v) {
          widget.doc.applyAttributes(p, v);
          _changed();
        },
        onRaw: () => openRawElement(context, widget.doc, p, _changed),
        onDelete: () {
          widget.doc.remove(p);
          _changed();
        },
      ),
    ));
  }

  void _editSet(XmlElement p) {
    final s = widget.doc.ensureChild(p, 'Set');
    final attrs = {for (final a in s.attributes) a.name.local: a.value};
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ElementEditorPage(
        title: 'Set • ${p.getAttribute('Name') ?? ''}',
        attributes: attrs,
        fields: perkSetFields,
        onSave: (v) {
          widget.doc.applyAttributes(s, v);
          _changed();
        },
        onRaw: () => openRawElement(context, widget.doc, s, _changed),
      ),
    ));
  }

  Future<void> _add() async {
    final name = await promptText(context, 'Новый перк', 'Name', hint: 'PERK_MY_EFFECT');
    if (name == null || name.trim().isEmpty) return;
    final el = widget.doc.addRecord(name.trim());
    _changed();
    _edit(el);
  }

  Future<void> _action(String action, XmlElement p) async {
    switch (action) {
      case 'raw':
        openRawElement(context, widget.doc, p, _changed);
      case 'dup':
        widget.doc.duplicate(p);
        _changed();
      case 'del':
        if (await confirmDialog(context, 'Удалить перк?', p.getAttribute('Name') ?? '')) {
          widget.doc.remove(p);
          _changed();
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final all = widget.doc.records;
    final q = _query.toLowerCase();
    final shown = all
        .where((p) => q.isEmpty || (p.getAttribute('Name') ?? '').toLowerCase().contains(q))
        .toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Поиск перка',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              IconButton(
                tooltip: 'Добавить перк',
                icon: const Icon(Icons.add_circle),
                onPressed: _add,
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text('Перков: ${shown.length} из ${all.length}',
              style: Theme.of(context).textTheme.bodySmall),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: shown.length,
            itemBuilder: (_, i) {
              final p = shown[i];
              final tpl = p.getAttribute('Template');
              return ListTile(
                leading: const CircleAvatar(child: Icon(Icons.auto_awesome, size: 18)),
                title: Text(p.getAttribute('Name') ?? '(без имени)',
                    overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  [
                    if (tpl != null && tpl.isNotEmpty) 'наследует: $tpl',
                    if (p.getAttribute('ItemSet') != null) 'набор: ${p.getAttribute('ItemSet')}',
                  ].join(' • '),
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: PopupMenuButton<String>(
                  onSelected: (v) => _action(v, p),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'raw', child: Text('XML (с триггерами)')),
                    PopupMenuItem(value: 'dup', child: Text('Дублировать')),
                    PopupMenuItem(value: 'del', child: Text('Удалить')),
                  ],
                ),
                onTap: () => _edit(p),
              );
            },
          ),
        ),
      ],
    );
  }
}