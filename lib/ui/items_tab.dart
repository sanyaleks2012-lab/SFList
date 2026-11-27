import 'package:flutter/material.dart';
import 'package:xml/xml.dart';

import '../core/field_specs.dart';
import '../core/game_doc.dart';
import 'common.dart';
import 'element_editor.dart';

class ItemsTab extends StatefulWidget {
  const ItemsTab({super.key, required this.doc, required this.onChanged});

  final GameDoc doc;
  final VoidCallback onChanged;

  @override
  State<ItemsTab> createState() => _ItemsTabState();
}

class _ItemsTabState extends State<ItemsTab> {
  String _query = '';
  String _type = '';

  void _changed() {
    setState(() {});
    widget.onChanged();
  }

  void _edit(XmlElement e) {
    final attrs = {for (final a in e.attributes) a.name.local: a.value};
    attrs['@Template'] = widget.doc.itemTemplate(e) ?? '';
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ElementEditorPage(
        title: e.getAttribute('Name') ?? 'Предмет',
        attributes: attrs,
        requireName: true,
        validator: (v) => widget.doc.nameTaken(v['Name'] ?? '', except: e)
            ? 'Предмет с именем «${v['Name']}» уже есть'
            : null,
        fields: itemFields(
          widget.doc.templateNames,
          types: widget.doc.frequentValues('Type', limit: 40),
          subTypes: widget.doc.frequentValues('SubType', limit: 14),
          packs: widget.doc.frequentValues('PackLabel', limit: 40),
        ),
        onSave: (v) {
          widget.doc.applyAttributes(e, v);
          _changed();
        },
        onRaw: () => openRawElement(context, widget.doc, e, _changed),
        onDelete: () {
          widget.doc.remove(e);
          _changed();
        },
      ),
    ));
  }

  Future<void> _add() async {
    final name = await promptText(context, 'Новый предмет', 'Name',
        hint: 'WEAPON_MY_SWORD');
    if (name == null || name.trim().isEmpty) return;
    if (widget.doc.nameTaken(name.trim())) {
      if (mounted) snack(context, 'Предмет «${name.trim()}» уже существует');
      return;
    }
    final el = widget.doc.addRecord(name.trim(), type: 'Weapon');
    _changed();
    _edit(el);
  }

  Future<void> _action(String action, XmlElement e) async {
    switch (action) {
      case 'raw':
        openRawElement(context, widget.doc, e, _changed);
      case 'dup':
        widget.doc.duplicate(e);
        _changed();
      case 'hide':
        final hidden = e.getAttribute('ShopHide') == '1';
        widget.doc.mutate(() => e.setAttribute('ShopHide', hidden ? '0' : '1'));
        _changed();
      case 'del':
        if (await confirmDialog(context, 'Удалить предмет?', e.getAttribute('Name') ?? '')) {
          widget.doc.remove(e);
          _changed();
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final all = widget.doc.records;
    final types = ({for (final e in all) e.getAttribute('Type') ?? ''}..remove('')).toList()
      ..sort();
    // Если последний предмет выбранного типа переименовали/сменили тип,
    // DropdownButton упал бы на assert «нет пункта со значением».
    final typeFilter = types.contains(_type) ? _type : '';
    final q = _query.toLowerCase();
    final shown = all.where((e) {
      final name = (e.getAttribute('Name') ?? '').toLowerCase();
      final type = e.getAttribute('Type') ?? '';
      return (q.isEmpty || name.contains(q)) && (typeFilter.isEmpty || type == typeFilter);
    }).toList();

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
                    hintText: 'Поиск по Name',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              const SizedBox(width: 8),
              DropdownButton<String>(
                value: typeFilter,
                underline: const SizedBox(),
                items: [
                  const DropdownMenuItem(value: '', child: Text('Все типы')),
                  for (final t in types) DropdownMenuItem(value: t, child: Text(t)),
                ],
                onChanged: (v) => setState(() => _type = v ?? ''),
              ),
              IconButton(
                tooltip: 'Добавить предмет',
                icon: const Icon(Icons.add_circle),
                onPressed: _add,
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text('Показано ${shown.length} из ${all.length}',
              style: Theme.of(context).textTheme.bodySmall),
        ),
        Expanded(
          child: shown.isEmpty
              ? const Center(child: Text('Ничего не найдено'))
              : ListView.builder(
                  itemCount: shown.length,
                  itemBuilder: (_, i) => _tile(shown[i]),
                ),
        ),
      ],
    );
  }

  Widget _tile(XmlElement e) {
    final type = e.getAttribute('Type') ?? '';
    final hidden = e.getAttribute('ShopHide') == '1';
    final lvl = e.getAttribute('Level');
    final price = e.getAttribute('Price');
    return ListTile(
      leading: CircleAvatar(
        child: Text(type.isEmpty ? '?' : type[0]),
      ),
      title: Text(
        e.getAttribute('Name') ?? '(без имени)',
        overflow: TextOverflow.ellipsis,
        style: hidden ? const TextStyle(decoration: TextDecoration.lineThrough) : null,
      ),
      subtitle: Text(
        [
          type,
          e.getAttribute('SubType'),
          if (lvl != null) 'ур. $lvl',
          if (price != null) '$price монет',
        ].whereType<String>().where((s) => s.isNotEmpty).join(' • '),
        overflow: TextOverflow.ellipsis,
      ),
      trailing: PopupMenuButton<String>(
        onSelected: (v) => _action(v, e),
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'raw', child: Text('XML')),
          const PopupMenuItem(value: 'dup', child: Text('Дублировать')),
          PopupMenuItem(
            value: 'hide',
            child: Text(hidden ? 'Показать в магазине' : 'Скрыть в магазине'),
          ),
          const PopupMenuItem(value: 'del', child: Text('Удалить')),
        ],
      ),
      onTap: () => _edit(e),
    );
  }
}