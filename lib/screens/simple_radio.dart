import 'package:flutter/material.dart';

import 'brand.dart';

/// A radio-style choice row (round mark + label) with the same call shape as
/// the old `RadioListTile`: [value], [groupValue], [onChanged], [title].
///
/// It draws the mark itself, so it does not depend on the radio widgets that
/// newer Flutter versions deprecate. Pass `onChanged: null` to disable it.
class SimpleRadioTile<T> extends StatelessWidget {
  final T value;
  final T? groupValue;
  final ValueChanged<T?>? onChanged;
  final Widget title;
  final EdgeInsetsGeometry contentPadding;
  final bool dense;

  const SimpleRadioTile({
    super.key,
    required this.value,
    required this.groupValue,
    required this.onChanged,
    required this.title,
    this.contentPadding = const EdgeInsets.symmetric(horizontal: 16),
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    final selected = value == groupValue;
    final enabled = onChanged != null;
    final color = !enabled ? Colors.black26 : (selected ? kBrandGreen : Colors.black54);
    return InkWell(
      onTap: enabled ? () => onChanged!(value) : null,
      child: Padding(
        padding: contentPadding.add(EdgeInsets.symmetric(vertical: dense ? 6 : 10)),
        child: Row(
          children: [
            Icon(selected ? Icons.radio_button_checked : Icons.radio_button_unchecked, color: color, size: 22),
            const SizedBox(width: 10),
            Flexible(child: title),
          ],
        ),
      ),
    );
  }
}
