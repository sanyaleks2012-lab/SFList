import 'package:flutter/material.dart';

Future<bool> confirmDialog(BuildContext context, String title, String body) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Отмена')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Да')),
      ],
    ),
  );
  return r ?? false;
}

/// Диалог ввода строки. Контроллер живёт внутри диалога: если освобождать его сразу
/// после `await showDialog`, он ещё используется анимацией закрытия.
Future<String?> promptText(BuildContext context, String title, String label,
    {String? hint, String initial = ''}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _PromptDialog(title: title, label: label, hint: hint, initial: initial),
  );
}

class _PromptDialog extends StatefulWidget {
  const _PromptDialog({
    required this.title,
    required this.label,
    required this.initial,
    this.hint,
  });

  final String title;
  final String label;
  final String? hint;
  final String initial;

  @override
  State<_PromptDialog> createState() => _PromptDialogState();
}

class _PromptDialogState extends State<_PromptDialog> {
  late final _ctrl = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _ctrl,
        autofocus: true,
        decoration: InputDecoration(labelText: widget.label, hintText: widget.hint),
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
        FilledButton(
          onPressed: () => Navigator.pop(context, _ctrl.text),
          child: const Text('OK'),
        ),
      ],
    );
  }
}

void snack(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));
}

Future<void> showErrorDialog(BuildContext context, String msg) {
  return showDialog(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Ошибка'),
      content: SingleChildScrollView(child: SelectableText(msg)),
      actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('OK'))],
    ),
  );
}
