import 'package:flutter/material.dart';

/// Renders an event description, including Markdown bold (`**text**`).
/// The stored text is not rewritten. Unsupported markup stays visible as text.
class EventDescriptionText extends StatelessWidget {
  const EventDescriptionText({
    super.key,
    required this.text,
    required this.style,
    this.maxLines,
    this.overflow,
    this.selectable = false,
  });

  final String text;
  final TextStyle style;
  final int? maxLines;
  final TextOverflow? overflow;
  final bool selectable;

  static List<InlineSpan> spans(String text, TextStyle style) {
    final bold = style.copyWith(fontWeight: FontWeight.w700);
    final spans = <InlineSpan>[];
    final pattern = RegExp(r'\*\*(.+?)\*\*');
    var start = 0;
    for (final match in pattern.allMatches(text)) {
      if (match.start > start) {
        spans.add(TextSpan(text: text.substring(start, match.start), style: style));
      }
      final inner = match.group(1) ?? '';
      if (inner.isNotEmpty) {
        spans.add(TextSpan(text: inner, style: bold));
      }
      start = match.end;
    }
    if (start < text.length) {
      spans.add(TextSpan(text: text.substring(start), style: style));
    }
    if (spans.isEmpty) {
      spans.add(TextSpan(text: text, style: style));
    }
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    final rich = TextSpan(style: style, children: spans(text, style));
    if (selectable) {
      return SelectableText.rich(rich);
    }
    return Text.rich(
      rich,
      maxLines: maxLines,
      overflow: overflow ??
          (maxLines == null ? TextOverflow.clip : TextOverflow.ellipsis),
    );
  }
}
