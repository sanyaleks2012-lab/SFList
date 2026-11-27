import 'package:flutter/material.dart';

import '../core/game_doc.dart';
import 'element_editor.dart';

class ValidationTab extends StatelessWidget {
  const ValidationTab({super.key, required this.docs, required this.onChanged});

  final List<GameDoc> docs;
  final void Function(GameDoc doc) onChanged;

  @override
  Widget build(BuildContext context) {
    final issues = [for (final d in docs) ...d.validate()];
    if (issues.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle, size: 56, color: Colors.green),
            SizedBox(height: 8),
            Text('Ошибок не найдено'),
          ],
        ),
      );
    }
    final errors = issues.where((i) => i.isError).length;
    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.fact_check),
          title: Text('Ошибок: $errors, предупреждений: ${issues.length - errors}'),
          subtitle: const Text('Нажмите на строку, чтобы открыть XML элемента'),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.separated(
            itemCount: issues.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final issue = issues[i];
              return ListTile(
                leading: Icon(
                  issue.isError ? Icons.error : Icons.warning_amber,
                  color: issue.isError ? Colors.redAccent : Colors.amber,
                ),
                title: Text(issue.message),
                subtitle: Text(issue.doc?.kind.fileName ?? ''),
                onTap: issue.element == null || issue.doc == null
                    ? null
                    : () => openRawElement(
                          context,
                          issue.doc!,
                          issue.element!,
                          () => onChanged(issue.doc!),
                        ),
              );
            },
          ),
        ),
      ],
    );
  }
}