import 'package:xml/xml.dart';

enum DocKind { list, perks }

extension DocKindX on DocKind {
  String get fileName => this == DocKind.list ? 'list.xml' : 'perks.xml';

  /// Корневой элемент файла в игре.
  String get rootName => this == DocKind.list ? 'List' : 'Perks';
}

/// Файл не похож на list.xml / perks.xml (читаемый текст для пользователя).
class DocFormatException implements Exception {
  const DocFormatException(this.message);
  final String message;

  @override
  String toString() => message;
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
///
/// Файл не переформатируется целиком: пробелы и отступы исходного XML сохраняются,
/// меняются только правленые элементы. Новые элементы вставляются с отступом соседей.
/// Все правки идут через [mutate], поэтому неизвестные атрибуты и триггеры не теряются.
class GameDoc {
  GameDoc._(this.kind, this.path, this.viaShizuku, this.doc);

  final DocKind kind;
  final String path;
  final bool viaShizuku;
  XmlDocument doc;

  String _savedSnap = '';
  bool _dirty = false;
  final _undo = <String>[];
  final _redo = <String>[];
  static const _maxUndo = 30;

  static GameDoc parse(DocKind kind, String path, String text, {bool viaShizuku = false}) {
    final doc = XmlDocument.parse(text);
    _checkRoot(kind, doc);
    final g = GameDoc._(kind, path, viaShizuku, doc);
    g._savedSnap = g._snap();
    return g;
  }

  static void _checkRoot(DocKind kind, XmlDocument doc) {
    final found = doc.rootElement.name.local;
    if (found != kind.rootName) {
      throw DocFormatException(
        '${kind.fileName}: ожидался корневой элемент <${kind.rootName}>, '
        'а в файле <$found>. Это точно тот файл?',
      );
    }
  }

  bool get dirty => _dirty;
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
  XmlElement get root => doc.rootElement;

  /// Компактный снимок для undo и сравнения «изменён / не изменён».
  String _snap() => doc.toXmlString();

  /// Текст для записи в файл: объявление `<?xml?>` на отдельной строке и перевод строки в конце.
  String toText() {
    var s = doc.toXmlString();
    if (s.startsWith('<?xml')) {
      final end = s.indexOf('?>');
      if (end > 0 && end + 2 < s.length && s[end + 2] != '\n') {
        s = '${s.substring(0, end + 2)}\n${s.substring(end + 2)}';
      }
    }
    return s.endsWith('\n') ? s : '$s\n';
  }

  String elementText(XmlElement e) => e.toXmlString();

  void markSaved() {
    _savedSnap = _snap();
    _dirty = false;
  }

  // ---------- история ----------
  void mutate(void Function() change) {
    _undo.add(_snap());
    if (_undo.length > _maxUndo) _undo.removeAt(0);
    _redo.clear();
    try {
      change();
    } catch (_) {
      _undo.removeLast();
      rethrow;
    }
    _dirty = true;
  }

  void undo() {
    if (_undo.isEmpty) return;
    _redo.add(_snap());
    _restore(_undo.removeLast());
  }

  void redo() {
    if (_redo.isEmpty) return;
    _undo.add(_snap());
    _restore(_redo.removeLast());
  }

  void _restore(String text) {
    doc = XmlDocument.parse(text);
    _dirty = _snap() != _savedSnap;
  }

  // ---------- доступ к данным ----------
  XmlElement? _section(String name) {
    for (final e in root.findElements(name)) {
      return e;
    }
    return null;
  }

  /// Первый дочерний элемент [parent] с именем [name].
  XmlElement? child(XmlElement parent, String name) {
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

  String? itemTemplate(XmlElement e) => child(e, 'Upgrades')?.getAttribute('Template');

  /// Значения атрибута [attr] у всех записей, от частых к редким (для подсказок).
  List<String> frequentValues(String attr, {int limit = 20}) {
    final counts = <String, int>{};
    for (final r in records) {
      final v = r.getAttribute(attr);
      if (v != null && v.isNotEmpty) counts[v] = (counts[v] ?? 0) + 1;
    }
    final keys = counts.keys.toList()
      ..sort((a, b) {
        final c = counts[b]!.compareTo(counts[a]!);
        return c != 0 ? c : a.compareTo(b);
      });
    return keys.length > limit ? keys.sublist(0, limit) : keys;
  }

  bool nameTaken(String name, {XmlElement? except}) =>
      records.any((r) => !identical(r, except) && r.getAttribute('Name') == name);

  String uniqueName(String base) {
    if (!nameTaken(base)) return base;
    var i = 2;
    while (nameTaken('${base}_$i')) {
      i++;
    }
    return '${base}_$i';
  }

  // ---------- вставка и удаление с сохранением отступов ----------
  String? _blank(XmlNode n) => n is XmlText && n.value.trim().isEmpty ? n.value : null;

  /// Пробельный текст перед [e] (например, "\n    ") — по нему вставляем соседей.
  String _indentBefore(XmlElement e) {
    final siblings = e.parent?.children;
    if (siblings != null) {
      final i = siblings.indexOf(e);
      if (i > 0) {
        final ws = _blank(siblings[i - 1]);
        if (ws != null) return ws;
      }
    }
    return '\n';
  }

  String _indentOf(XmlElement e) => e.parent is XmlElement ? _indentBefore(e) : '\n';

  XmlElement? _firstElement(XmlElement p) {
    for (final c in p.children) {
      if (c is XmlElement) return c;
    }
    return null;
  }

  XmlElement? _lastElement(XmlElement p) {
    XmlElement? last;
    for (final c in p.children) {
      if (c is XmlElement) last = c;
    }
    return last;
  }

  void _insertAfter(XmlElement anchor, XmlElement node) {
    final indent = _indentBefore(anchor);
    final siblings = anchor.parent!.children;
    final i = siblings.indexOf(anchor);
    siblings.insert(i + 1, XmlText(indent));
    siblings.insert(i + 2, node);
  }

  /// Добавляет [node] в конец [parent] (или в начало при [first]) с правильным отступом.
  void _appendChild(XmlElement parent, XmlElement node, {bool first = false}) {
    final anchor = first ? _firstElement(parent) : _lastElement(parent);
    if (anchor == null) {
      // В родителе ещё нет элементов (в том числе `<Perk Name="X" />`).
      final outer = _indentOf(parent);
      final children = parent.children;
      for (final c in children.toList()) {
        if (_blank(c) != null) children.remove(c);
      }
      children.add(XmlText('$outer  '));
      children.add(node);
      children.add(XmlText(outer));
    } else if (first) {
      final indent = _indentBefore(anchor);
      final siblings = parent.children;
      final i = siblings.indexOf(anchor);
      siblings.insert(i, node);
      siblings.insert(i + 1, XmlText(indent));
    } else {
      _insertAfter(anchor, node);
    }
  }

  /// Удаляет элемент вместе с пробелом перед ним, чтобы не оставалось пустых строк.
  void _detach(XmlElement e) {
    XmlNode? ws;
    final siblings = e.parent?.children;
    if (siblings != null) {
      final i = siblings.indexOf(e);
      if (i > 0 && _blank(siblings[i - 1]) != null) ws = siblings[i - 1];
    }
    e.remove();
    ws?.remove();
  }

  // ---------- правки ----------
  XmlElement addRecord(String name, {String type = 'Weapon'}) {
    final el = kind == DocKind.list
        ? XmlElement(XmlName('Item'), [
            XmlAttribute(XmlName('Name'), name),
            XmlAttribute(XmlName('Type'), type),
          ])
        : XmlElement(XmlName('Perk'), [XmlAttribute(XmlName('Name'), name)]);
    final parent = kind == DocKind.list ? (_section('Items') ?? root) : root;
    mutate(() => _appendChild(parent, el));
    return el;
  }

  XmlElement duplicate(XmlElement e) {
    final copy = e.copy();
    copy.setAttribute('Name', uniqueName('${e.getAttribute('Name') ?? 'Item'}_COPY'));
    mutate(() => _insertAfter(e, copy));
    return copy;
  }

  void remove(XmlElement e) => mutate(() => _detach(e));

  bool _sameAttrs(XmlElement e, Map<String, String> values) =>
      e.attributes.length == values.length &&
      values.entries.every((en) => e.getAttribute(en.key) == en.value);

  void _writeAttrs(XmlElement e, Map<String, String> values) {
    for (final name in e.attributes.map((a) => a.name.local).toList()) {
      if (!values.containsKey(name)) e.removeAttribute(name);
    }
    values.forEach((k, v) => e.setAttribute(k, v));
  }

  /// Применяет значения из формы. Атрибуты, которых нет в [values], удаляются.
  /// Если ничего не изменилось, документ не помечается изменённым.
  void applyAttributes(XmlElement e, Map<String, String> values) {
    final v = Map<String, String>.from(values);
    final tpl = v.remove('@Template');
    final sameTpl = tpl == null || (itemTemplate(e) ?? '') == tpl;
    if (sameTpl && _sameAttrs(e, v)) return;
    mutate(() {
      _writeAttrs(e, v);
      if (tpl != null) _setTemplate(e, tpl);
    });
  }

  void _setTemplate(XmlElement e, String tpl) {
    final u = child(e, 'Upgrades');
    if (tpl.isEmpty) {
      if (u != null) _detach(u);
    } else if (u == null) {
      // В игровых файлах <Upgrades> всегда идёт первым дочерним элементом предмета.
      _appendChild(
        e,
        XmlElement(XmlName('Upgrades'), [XmlAttribute(XmlName('Template'), tpl)]),
        first: true,
      );
    } else {
      u.setAttribute('Template', tpl);
    }
  }

  /// Меняет атрибуты дочернего элемента [name] у [parent] (например, `<Set>` у перка).
  /// Элемент создаётся только если есть что записать, поэтому «открыл и закрыл»
  /// не оставляет пустых `<Set />` и не помечает файл изменённым.
  void applyChild(
    XmlElement parent,
    String name,
    Map<String, String> values, {
    bool first = false,
  }) {
    final existing = child(parent, name);
    if (existing == null && values.isEmpty) return;
    if (existing != null && _sameAttrs(existing, values)) return;
    mutate(() {
      var el = existing;
      if (el == null) {
        el = XmlElement(XmlName(name));
        _appendChild(parent, el, first: first);
      }
      _writeAttrs(el, values);
    });
  }

  void replaceElement(XmlElement old, String text) {
    final node = XmlDocument.parse(text).rootElement.copy();
    mutate(() => old.replace(node));
  }

  void replaceAll(String text) {
    final nd = XmlDocument.parse(text);
    _checkRoot(kind, nd);
    mutate(() => doc = nd);
  }

  // ---------- проверка ----------
  String _short(String s) {
    final t = s.trim().replaceAll(RegExp(r'\s+'), ' ');
    return t.length > 60 ? '${t.substring(0, 60)}…' : t;
  }

  List<Issue> validate() {
    final out = <Issue>[];
    final recs = records;
    final names = recs.map((e) => e.getAttribute('Name') ?? '').toSet();
    final templates = kind == DocKind.list ? templateNames.toSet() : <String>{};
    final seen = <String>{};

    for (final r in recs) {
      final name = r.getAttribute('Name') ?? '';
      if (name.isEmpty) {
        out.add(Issue('Запись без Name', doc: this, element: r));
        continue;
      }
      if (!seen.add(name)) {
        out.add(Issue('Дубликат Name: $name', doc: this, element: r));
      }

      // Текст прямо внутри <Perk>/<Item>: обычно это атрибут, который случайно
      // оказался за тегом (например, Image="..." после <Perk Name="...">).
      for (final c in r.children) {
        if (c is XmlText && c.value.trim().isNotEmpty) {
          out.add(Issue(
            '$name: лишний текст внутри <${r.name.local}>: «${_short(c.value)}». '
            'Похоже на атрибут, оказавшийся за тегом',
            isError: false,
            doc: this,
            element: r,
          ));
          break;
        }
      }

      if (kind == DocKind.list) {
        for (final k in _numericKeys) {
          final v = r.getAttribute(k);
          if (v != null && num.tryParse(v) == null) {
            out.add(Issue('$name: $k должен быть числом, сейчас "$v"', doc: this, element: r));
          }
        }
        final tpl = itemTemplate(r);
        if (tpl != null && tpl.isNotEmpty && !templates.contains(tpl)) {
          out.add(Issue('$name: шаблон "$tpl" не найден в UpgradeList', doc: this, element: r));
        }
      } else {
        final set = child(r, 'Set');
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
