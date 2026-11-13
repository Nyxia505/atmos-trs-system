import 'package:flutter/material.dart';

/// Full-width choice field. Tapping it opens one scrollable list in a bottom
/// sheet, so the signup form itself is never drawn a second time.
class AnchoredOptionField extends StatefulWidget {
  const AnchoredOptionField({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    required this.decoration,
    this.style,
    this.enabled = true,
    this.validator,
    this.hintText = 'Type to search',
    this.noResultsText = 'No matches',
  });

  final List<String> options;
  final String? value;
  final ValueChanged<String?> onChanged;
  final InputDecoration decoration;
  final TextStyle? style;
  final bool enabled;
  final FormFieldValidator<String>? validator;
  final String hintText;
  final String noResultsText;

  @override
  State<AnchoredOptionField> createState() => _AnchoredOptionFieldState();
}

class _AnchoredOptionFieldState extends State<AnchoredOptionField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value ?? '');
  }

  @override
  void didUpdateWidget(covariant AnchoredOptionField oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.value ?? '';
    if (_controller.text != next) _controller.text = next;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _openSheet() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        return _OptionSheet(
          options: widget.options,
          noResultsText: widget.noResultsText,
        );
      },
    );
    if (!mounted || picked == null) return;
    _controller.text = picked;
    if (picked != widget.value) widget.onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: _controller,
      readOnly: true,
      enabled: widget.enabled,
      style: widget.style,
      onTap: widget.enabled ? _openSheet : null,
      decoration: widget.decoration.copyWith(
        hintText: widget.decoration.hintText ?? widget.hintText,
        suffixIcon: const Icon(Icons.arrow_drop_down_rounded),
      ),
      validator: widget.validator,
    );
  }
}

class _OptionSheet extends StatelessWidget {
  const _OptionSheet({
    required this.options,
    required this.noResultsText,
  });

  final List<String> options;
  final String noResultsText;

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height * 0.72;
    return SizedBox(
      height: height,
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFFE7E5E4),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: options.isEmpty
                ? Center(
                    child: Text(
                      noResultsText,
                      style: const TextStyle(
                        color: Color(0xFF6B7280),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  )
                : ListView.separated(
                    itemCount: options.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final option = options[index];
                      return ListTile(
                        title: Text(
                          option,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1F2937),
                          ),
                        ),
                        onTap: () => Navigator.pop(context, option),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
