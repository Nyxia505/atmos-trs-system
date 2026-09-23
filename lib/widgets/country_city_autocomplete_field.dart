import 'package:flutter/material.dart';

import 'package:atmos_trs_system/data/signup_cities_by_country.dart';
import 'package:atmos_trs_system/utils/signup_field_validation.dart';

/// Typable city field with country-scoped autocomplete (dropdown + typeahead).
///
/// Users can pick a suggested city or type a custom name not in the list.
class CountryCityAutocompleteField extends StatefulWidget {
  const CountryCityAutocompleteField({
    super.key,
    required this.controller,
    required this.country,
    required this.decoration,
    this.textStyle,
    this.enabled = true,
    this.textInputAction,
    this.onFieldSubmitted,
    this.onEditingComplete,
    this.onChanged,
  });

  final TextEditingController controller;
  final String? country;
  final InputDecoration decoration;
  final TextStyle? textStyle;
  final bool enabled;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onFieldSubmitted;
  final VoidCallback? onEditingComplete;
  final ValueChanged<String>? onChanged;

  @override
  State<CountryCityAutocompleteField> createState() =>
      _CountryCityAutocompleteFieldState();
}

class _CountryCityAutocompleteFieldState
    extends State<CountryCityAutocompleteField> {
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasList = SignupCitiesByCountry.hasCuratedList(widget.country);

    return RawAutocomplete<String>(
      textEditingController: widget.controller,
      focusNode: _focusNode,
      optionsBuilder: (TextEditingValue tev) {
        if (!hasList) return const Iterable<String>.empty();
        return SignupCitiesByCountry.suggest(
          country: widget.country,
          query: tev.text,
        );
      },
      displayStringForOption: (o) => o,
      onSelected: (value) {
        widget.controller.text = value;
        widget.controller.selection =
            TextSelection.collapsed(offset: value.length);
        widget.onChanged?.call(value);
      },
      fieldViewBuilder: (
        context,
        textController,
        focusNode,
        onFieldSubmittedCb,
      ) {
        return TextFormField(
          controller: textController,
          focusNode: focusNode,
          enabled: widget.enabled,
          style: widget.textStyle,
          textCapitalization: TextCapitalization.words,
          textInputAction: widget.textInputAction,
          onChanged: widget.onChanged,
          onFieldSubmitted: (v) {
            onFieldSubmittedCb();
            widget.onFieldSubmitted?.call(v);
          },
          onEditingComplete: widget.onEditingComplete,
          decoration: widget.decoration.copyWith(
            hintText: widget.decoration.hintText ??
                (hasList ? 'Type to search cities' : 'Enter your city'),
            suffixIcon: hasList
                ? const Icon(Icons.arrow_drop_down_rounded)
                : widget.decoration.suffixIcon,
          ),
          validator: (v) => validateInternationalCity(v),
        );
      },
      optionsViewBuilder: (context, onSelectedOpt, options) {
        final opts = options.toList(growable: false);
        if (opts.isEmpty) return const SizedBox.shrink();
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 6,
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220, minWidth: 280),
              child: ListView.separated(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: opts.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final option = opts[index];
                  return ListTile(
                    dense: true,
                    title: Text(
                      option,
                      style: const TextStyle(
                        color: Colors.black87,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    onTap: () => onSelectedOpt(option),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}
