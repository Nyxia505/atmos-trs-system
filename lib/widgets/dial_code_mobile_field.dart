import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:atmos_trs_system/utils/signup_field_validation.dart';

/// Shared dial-code + local mobile input used across tourist / LGU / establishment signup.
class DialCodeMobileField extends StatelessWidget {
  const DialCodeMobileField({
    super.key,
    required this.controller,
    required this.dialCode,
    required this.onDialCodeChanged,
    required this.numberDecoration,
    required this.dialDecoration,
    this.textStyle,
    this.dialTextStyle,
    this.dropdownColor = Colors.white,
    this.menuItemTextStyle,
    this.enabled = true,
    this.textInputAction,
    this.onFieldSubmitted,
    this.onEditingComplete,
    this.focusNode,
  });

  final TextEditingController controller;
  final String dialCode;
  final ValueChanged<String> onDialCodeChanged;
  final InputDecoration numberDecoration;
  final InputDecoration dialDecoration;
  final TextStyle? textStyle;
  final TextStyle? dialTextStyle;
  final Color? dropdownColor;
  final TextStyle? menuItemTextStyle;
  final bool enabled;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onFieldSubmitted;
  final VoidCallback? onEditingComplete;
  final FocusNode? focusNode;

  List<String> get _options => dialCodeOptionsFor(dialCode);

  @override
  Widget build(BuildContext context) {
    final code = _options.contains(dialCode) ? dialCode : _options.first;
    final valueStyle = dialTextStyle ??
        textStyle?.copyWith(fontWeight: FontWeight.w700) ??
        const TextStyle(fontWeight: FontWeight.w700, fontSize: 15);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 92,
          child: DropdownButtonFormField<String>(
            value: code,
            dropdownColor: dropdownColor,
            isExpanded: true,
            isDense: true,
            iconSize: 18,
            style: valueStyle,
            selectedItemBuilder: (context) => _options
                .map(
                  (c) => Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      c,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.clip,
                      style: valueStyle,
                    ),
                  ),
                )
                .toList(),
            decoration: dialDecoration.copyWith(
              isDense: true,
              contentPadding: dialDecoration.contentPadding ??
                  const EdgeInsets.fromLTRB(12, 16, 4, 16),
              prefixIcon: null,
              prefixIconConstraints: const BoxConstraints(
                minWidth: 0,
                minHeight: 0,
              ),
            ),
            items: _options
                .map(
                  (c) => DropdownMenuItem<String>(
                    value: c,
                    child: Text(
                      c,
                      overflow: TextOverflow.ellipsis,
                      style: menuItemTextStyle ??
                          const TextStyle(fontSize: 14, color: Colors.black87),
                    ),
                  ),
                )
                .toList(),
            onChanged: enabled
                ? (v) {
                    if (v == null) return;
                    onDialCodeChanged(v);
                  }
                : null,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: TextFormField(
            controller: controller,
            focusNode: focusNode,
            enabled: enabled,
            keyboardType: TextInputType.phone,
            textInputAction: textInputAction,
            onFieldSubmitted: onFieldSubmitted,
            onEditingComplete: onEditingComplete,
            style: textStyle,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              if (code == '+63')
                TextInputFormatter.withFunction((oldValue, newValue) {
                  var t = newValue.text;
                  if (t.startsWith('0')) {
                    t = t.replaceFirst(RegExp(r'^0+'), '');
                    return TextEditingValue(
                      text: t,
                      selection: TextSelection.collapsed(offset: t.length),
                    );
                  }
                  return newValue;
                }),
              LengthLimitingTextInputFormatter(code == '+63' ? 10 : 15),
            ],
            decoration: numberDecoration.copyWith(
              hintText: numberDecoration.hintText ??
                  (code == '+63' ? '9XXXXXXXXX' : 'Enter your number'),
            ),
            validator: (v) => validateMobileForDialCode(v, code),
          ),
        ),
      ],
    );
  }
}
