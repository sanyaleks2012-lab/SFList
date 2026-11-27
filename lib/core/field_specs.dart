class FieldSpec {
  const FieldSpec(
    this.key,
    this.label, {
    this.hint,
    this.suggestions = const [],
    this.numeric = false,
  });

  final String key;
  final String label;
  final String? hint;
  final List<String> suggestions;
  final bool numeric;
}

const itemTypes = [
  'Weapon', 'Armor', 'Helm', 'Ranged', 'Magic', 'Skeleton',
  'Consumable', 'Seal', 'Decorate', 'Decks', 'Energy',
];

const packLabels = [
  'ACT_1', 'ACT_2', 'ACT_3', 'ACT_4', 'ACT_5', 'ACT_6',
  'ACT_7_1', 'ACT_7_2', 'ACT_7_3', 'INTERMISSION', 'GATES_OF_SHADOWS',
  'ACT_2_ASCENSION',
];

List<String> _merge(List<String> base, List<String> extra) =>
    [...base, ...extra.where((e) => !base.contains(e))];

/// Поля предмета. Ключ '@Template' — не атрибут, а дочерний <Upgrades Template="..."/>.
/// [types], [subTypes], [packs] — значения, реально встречающиеся в открытом файле;
/// они дополняют встроенные подсказки.
List<FieldSpec> itemFields(
  List<String> templates, {
  List<String> types = const [],
  List<String> subTypes = const [],
  List<String> packs = const [],
}) =>
    [
      const FieldSpec('Name', 'Имя (Name)', hint: 'Уникальный ID, например WEAPON_MY_SWORD'),
      FieldSpec('Type', 'Тип', suggestions: _merge(itemTypes, types)),
      FieldSpec('SubType', 'Подтип',
          hint: 'Например Katana, Axes, Knives', suggestions: subTypes),
      const FieldSpec('Level', 'Уровень (Level)', numeric: true),
      const FieldSpec('UpgradeLevel', 'Макс. уровень (UpgradeLevel)', numeric: true),
      const FieldSpec('WeaponDamage', 'Урон оружия', numeric: true),
      const FieldSpec('RangedDamage', 'Урон дальнего', numeric: true),
      const FieldSpec('MagicDamage', 'Урон магии', numeric: true),
      const FieldSpec('UnarmedDamage', 'Урон без оружия', numeric: true),
      const FieldSpec('BodyDefense', 'Защита тела', numeric: true),
      const FieldSpec('HeadDefense', 'Защита головы', numeric: true),
      const FieldSpec('Price', 'Цена (монеты)', numeric: true),
      const FieldSpec('BonusPrice', 'Цена (бонусы)', numeric: true),
      FieldSpec('PackLabel', 'Пак (PackLabel)', suggestions: _merge(packLabels, packs)),
      const FieldSpec('Model', 'Модель (Model)'),
      const FieldSpec('Image', 'Иконка (Image)'),
      const FieldSpec('ShopHide', 'Скрыть в магазине',
          hint: '1 = скрыт, 0 = показан', suggestions: ['0', '1'], numeric: true),
      FieldSpec('@Template', 'Шаблон апгрейда',
          hint: 'Имя из UpgradeList. Пусто — без апгрейдов', suggestions: templates),
    ];

const perkFields = [
  FieldSpec('Name', 'Имя перка (Name)'),
  FieldSpec('Template', 'Наследует от (Template)',
      hint: 'Имя другого перка, необязательно'),
  FieldSpec('Image', 'Иконка (Image)'),
  FieldSpec('Description', 'Описание (Description)', hint: 'Ключ локализации'),
  FieldSpec('Alias', 'Alias'),
  FieldSpec('PerkType', 'Тип (PerkType)', suggestions: ['Combo']),
  FieldSpec('ItemSet', 'Набор (ItemSet)', hint: 'Имя сета из list.xml'),
  FieldSpec('Hidden', 'Скрыт (Hidden)', suggestions: ['0', '1']),
];

const perkSetFields = [
  FieldSpec('Chance', 'Шанс срабатывания',
      hint: '0.2 = 20%, 1 = всегда', numeric: true),
  FieldSpec('Frames', 'Длительность (кадры)',
      hint: '60 кадров = 1 секунда', numeric: true),
  FieldSpec('Animation', 'Тип удара',
      suggestions: ['Weapon', 'Unarmed', 'Kick', 'RangedMissilePerk', 'MagicMissile'],
      hint: 'Какие удары запускают эффект'),
  FieldSpec('Defense', 'Защита', suggestions: ['BodyDefense', 'HeadDefense']),
  FieldSpec('DamageFactor', 'Множитель урона (DamageFactor)',
      hint: 'Смотрите похожие перки для ориентира', numeric: true),
  FieldSpec('Base', 'Base', hint: 'Базовое значение эффекта', numeric: true),
  FieldSpec('Aspect', 'Aspect', hint: 'Сила эффекта', numeric: true),
  FieldSpec('Limit', 'Limit', numeric: true),
];