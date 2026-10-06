import 'package:flutter/material.dart';

import 'security.dart';

/// The three "Verified by" selectors used on the Qarz and Zakaat expenditure
/// forms. On a phone they stack one above the other (so nothing overflows);
/// on a wide screen they sit side by side.
class VerifierRow extends StatelessWidget {
  final List<TextEditingController> controllers;
  final bool enabled;
  final VoidCallback onChanged;
  final InputDecoration Function(String label) decorationFor;

  const VerifierRow({
    super.key,
    required this.controllers,
    required this.enabled,
    required this.onChanged,
    required this.decorationFor,
  });

  Widget _dropdown(int index) {
    final controller = controllers[index];
    final current = kUserPasswords.containsKey(controller.text) ? controller.text : null;
    return DropdownButtonFormField<String>(
      initialValue: current,
      isExpanded: true,
      decoration: decorationFor('Verified by ${index + 1} *'),
      items: [
        for (final name in kUserPasswords.keys)
          DropdownMenuItem<String>(
            value: name,
            child: Text(name, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: enabled
          ? (value) {
              controller.text = value ?? '';
              onChanged();
            }
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final count = controllers.length;
        if (constraints.maxWidth < 560) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < count; i++) ...[
                if (i > 0) const SizedBox(height: 10),
                _dropdown(i),
              ],
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < count; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(child: _dropdown(i)),
            ],
          ],
        );
      },
    );
  }
}
