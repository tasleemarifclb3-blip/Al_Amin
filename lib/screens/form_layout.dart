import 'package:flutter/material.dart';

import 'brand.dart';

const Color _boxBorder = Color(0xFFB8B8B8);

/// Input look used by the receipt forms: white box, thin grey border, small
/// corner radius, green border when focused.
InputDecoration boxedDecoration({
  String? hint,
  String? prefixText,
  Widget? suffixIcon,
}) {
  OutlineInputBorder border(Color color, double width) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: BorderSide(color: color, width: width),
      );
  return InputDecoration(
    isDense: true,
    filled: true,
    fillColor: Colors.white,
    hintText: hint,
    prefixText: prefixText,
    suffixIcon: suffixIcon,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
    border: border(_boxBorder, 1),
    enabledBorder: border(_boxBorder, 1),
    disabledBorder: border(_boxBorder.withValues(alpha: .6), 1),
    focusedBorder: border(kBrandGreen, 1.6),
  );
}

/// Numbered, collapsible section header: "1.  Donor Details  ^" with a rule
/// underneath. Tap the header to fold the section away.
class NumberedSection extends StatefulWidget {
  final int number;
  final String title;
  final List<Widget> children;
  final bool initiallyExpanded;

  const NumberedSection({
    super.key,
    required this.number,
    required this.title,
    required this.children,
    this.initiallyExpanded = true,
  });

  @override
  State<NumberedSection> createState() => _NumberedSectionState();
}

class _NumberedSectionState extends State<NumberedSection> {
  late bool _open = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => setState(() => _open = !_open),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              children: [
                Text('${widget.number}.', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(widget.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ),
                Icon(_open ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down),
              ],
            ),
          ),
        ),
        const Divider(height: 1, thickness: 1.2, color: Colors.black38),
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          alignment: Alignment.topCenter,
          child: _open
              ? Padding(
                  padding: const EdgeInsets.only(top: 14, bottom: 6),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: widget.children),
                )
              : const SizedBox(width: double.infinity),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

/// Label above a field. A leading "* " marks required fields. [widthFactor]
/// makes the box narrower than the page (like the date field).
class LabeledField extends StatelessWidget {
  final String label;
  final bool required;
  final Widget child;
  final double? widthFactor;

  const LabeledField({
    super.key,
    required this.label,
    required this.child,
    this.required = false,
    this.widthFactor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(
            TextSpan(
              children: [
                if (required)
                  const TextSpan(text: '* ', style: TextStyle(color: Color(0xFFB71C1C), fontWeight: FontWeight.w700)),
                TextSpan(text: label),
              ],
            ),
            style: const TextStyle(fontSize: 15, color: Colors.black87),
          ),
          const SizedBox(height: 6),
          if (widthFactor == null)
            child
          else
            FractionallySizedBox(widthFactor: widthFactor, alignment: Alignment.centerLeft, child: child),
        ],
      ),
    );
  }
}

/// Options in one bordered box with round radio marks, none selected until the
/// user taps one.
class BoxedChoice extends StatelessWidget {
  final List<String> options;
  final String? value;
  final ValueChanged<String>? onChanged;

  const BoxedChoice({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: _boxBorder),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Wrap(
        children: [
          for (final option in options)
            InkWell(
              onTap: onChanged == null ? null : () => onChanged!(option),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      option == value ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                      color: option == value ? kBrandGreen : Colors.black54,
                      size: 22,
                    ),
                    const SizedBox(width: 6),
                    Text(option, style: const TextStyle(fontSize: 15)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
