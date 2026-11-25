import 'package:xml/xml.dart';

enum DocKind { list, perks }

extension DocKindX on DocKind {
  String get fileName => this == DocKind.list ? 'list.xml' : 'perks.xml';
}

class Issue {
  const Issue(this.message, {this.isError = true, this.doc, this.element});
  final String message;
  final bool isError;
  final GameDoc? doc;
  final XmlElement? element;
}

const _numericKeys = [
  'Level', 'UpgradeLevel', 'Price', 'BonusPrice', 'WeaponDamage', 'RangedDamage',
  'MagicDamage', 'UnarmedDamage', 'BodyDefense', 'HeadDefense',
];

/// Обёртка над XML-документом с историей undo/redo и проверками.
/// Все правки идут через [mutate], поэтому сохраняют неизвестные атрибуты и триггеры.
class GameDoc {
  GameDoc._(this.kind, this.path, this.viaShizuku, this.doc);

  final DocKind kind;
  final String path;
  final bool viaShizuku;
  XmlDocument doc;
  String saved = '';
  bool _dirty = false;
  final _undo = <String>[];
  final _redo = <String>[];

  static GameDoc parse(DocKind kind, String path, String text, {bool viaShizuku = false}) {
    final g = GameDoc._(kind, path, viaShizuku, XmlDocument.parse(text));
    g.saved = g.toText();
    return g;
  }

  bool get dirty => _dirty;
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
  XmlElement get root => doc.rootElement;

  String toText() => doc.toXmlString(pretty: true, indent: '  ');
  String elementText(XmlElement e) => e.toXmlString(pretty: true, indent: '  ');

  void markSaved() {
    saved = toText();
    _dirty = false;
  }

  // ---------- история ----------
  void mutate(void Function() change) {
    _undo.add(toText());
    if (_undo.length > 60) _undo.removeAt(0);
    _redo.clear();
    change();
    _dirty = true;
  }

  void undo() {
    if (_undo.isEmpty) return;
    _redo.add(toText());
    _restore(_undo.removeLast());
  }

  void redo() {
    if (_redo.isEmpty) return;
    _undo.add(toText());
    _restore(_redo.removeLast());
  }

  void _restore(String text) {
    doc = XmlDocument.parse(text);
    _dirty = toText() != saved;
  }

  // ---------- доступ к данным ----------
  XmlElement? _section(String name) {
    for (final e in root.findElements(name)) {
      return e;
    }
    return null;
  }

  XmlElement? _child(XmlElement parent, String name) {
    for (final e in parent.findElements(name)) {
      return e;
    }
    return null;
  }

  /// Items (list.xml) или Perks (perks.xml)
  List<XmlElement> get records => kind == DocKind.list
      ? (_section('Items')?.findElements('Item').toList() ?? <XmlElement>[])
      : root.findElements('Perk').toList();

  List<String> get templateNames => (_section('UpgradeList')
              ?.findElements('Upgrades')
              .map((e) => e.getAttribute('Name') ?? '')
              .where((s) => s.isNotEmpty)
              .toList()) ??
      <String>[];

  String? itemTemplate(XmlElement e) => _child(e, 'Upgrades')?.getAttribute('Template');

  // ---------- правки ----------
  XmlElement addRecord(String name, {String type = 'Weapon'}) {
    final el = kind == DocKind.list
        ? XmlElement(XmlName('Item'), [
            XmlAttribute(XmlName('Name'), name),
            XmlAttribute(XmlName('Type'), type),
          ])
        : XmlElement(XmlName('Perk'), [XmlAttribute(XmlName('Name'), name)]);
    final parent = kind == DocKind.list ? (_section('Items') ?? root) : root;
    mutate(() => parent.children.add(el));
    return el;
  }

  XmlElement duplicate(XmlElement e) {
    final copy = e.copy();
    copy.setAttribute('Name', '${e.getAttribute('Name') ?? 'Item'}_COPY');
    final p = e.parent!;
    mutate(() => p.children.insert(p.children.indexOf(e) + 1, copy));
    return copy;
  }

  void remove(XmlElement e) => mutate(() => e.remove());

  /// Применяет значения из формы. Атрибуты, которых нет в [values], удаляются.
  void applyAttributes(XmlElement e, Map<String, String> values) {
    final v = Map<String, String>.from(values);
    final tpl = v.remove('@Template');
    mutate(() {
      e.attributes.removeWhere((a) => !v.containsKey(a.name.local));
      v.forEach((k, val) => e.setAttribute(k, val));
      if (tpl != null) _setTemplate(e, tpl);
    });
  }

  void _setTemplate(XmlElement e, String tpl) {
    final u = _child(e, 'Upgrades');
    if (tpl.isEmpty) {
      u?.remove();
    } else if (u == null) {
      e.children.add(XmlElement(XmlName('Upgrades'), [XmlAttribute(XmlName('Template'), tpl)]));
    } else {
      u.setAttribute('Template', tpl);
    }
  }

  XmlElement ensureChild(XmlElement e, String name) {
    final existing = _child(e, name);
    if (existing != null) return existing;
    final node = XmlElement(XmlName(name));
    mutate(() => e.children.insert(0, node));
    return node;
  }

  void replaceElement(XmlElement old, String text) {
    final node = XmlDocument.parse(text).rootElement.copy();
    mutate(() => old.replace(node));
  }

  void replaceAll(String text) {
    final nd = XmlDocument.parse(text);
    mutate(() => doc = nd);
  }

  // ---------- проверка ----------
  List<Issue> validate() {
    final out = <Issue>[];
    final names = records.map((e) => e.getAttribute('Name') ?? '').toSet();
    final seen = <String>{};

    for (final r in records) {
      final name = r.getAttribute('Name') ?? '';
      if (name.isEmpty) {
        out.add(Issue('Запись без Name', doc: this, element: r));
        continue;
      }
      if (!seen.add(name)) {
        out.add(Issue('Дубликат Name: $name', doc: this, element: r));
      }

      if (kind == DocKind.list) {
        for (final k in _numericKeys) {
          final v = r.getAttribute(k);
          if (v != null && num.tryParse(v) == null) {
            out.add(Issue('$name: $k должен быть числом, сейчас "$v"', doc: this, element: r));
          }
        }
        final tpl = itemTemplate(r);
        if (tpl != null && tpl.isNotEmpty && !templateNames.contains(tpl)) {
          out.add(Issue('$name: шаблон "$tpl" не найден в UpgradeList', doc: this, element: r));
        }
      } else {
        final set = _child(r, 'Set');
        final chance = num.tryParse(set?.getAttribute('Chance') ?? '');
        if (chance != null && chance > 1) {
          out.add(Issue('$name: Chance $chance больше 1 (это больше 100%)',
              isError: false, doc: this, element: r));
        }
        final tpl = r.getAttribute('Template');
        if (tpl != null && tpl.isNotEmpty && !names.contains(tpl)) {
          out.add(Issue('$name: Template "$tpl" не найден среди перков',
              isError: false, doc: this, element: r));
        }
      }
    }

    if (kind == DocKind.list) {
      final sets = _section('ItemSets')?.findElements('ItemSet') ?? const <XmlElement>[];
      for (final s in sets) {
        for (final it in s.findElements('Item')) {
          final n = it.getAttribute('Name') ?? '';
          if (n.isNotEmpty && !names.contains(n)) {
            out.add(Issue('ItemSet ${s.getAttribute('Name')}: предмет "$n" не найден',
                isError: false, doc: this, element: it));
          }
        }
      }
    }
    return out;
  }
}