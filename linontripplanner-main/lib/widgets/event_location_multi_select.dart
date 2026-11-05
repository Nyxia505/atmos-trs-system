import 'package:flutter/material.dart';

import '../data.dart';
import '../event_schedule.dart';

/// Searchable multi-select for Misamis Occidental municipalities and cities.
class EventLocationMultiSelect extends StatelessWidget {
  const EventLocationMultiSelect({
    super.key,
    required this.selectedNames,
    required this.onChanged,
    this.errorText,
  });

  final Set<String> selectedNames;
  final ValueChanged<Set<String>> onChanged;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final catalog = eventLocationCatalog();
    final summary = selectedNames.isEmpty
        ? 'Select a municipality'
        : formatEventLocationSummary(selectedNames.toList());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InputDecorator(
          decoration: InputDecoration(
            labelText: 'Location (municipality)',
            hintText: 'Select a municipality',
            errorText: errorText,
            suffixIcon: const Icon(Icons.arrow_drop_down),
          ),
          child: InkWell(
            onTap: catalog.isEmpty
                ? null
                : () async {
                    final next = await showDialog<Set<String>>(
                      context: context,
                      builder: (ctx) => _LocationPickerDialog(
                        initial: Set<String>.from(selectedNames),
                      ),
                    );
                    if (next != null) onChanged(next);
                  },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                summary,
                style: TextStyle(
                  fontSize: 15,
                  color: selectedNames.isEmpty
                      ? AppColors.textGrey
                      : AppColors.textDark,
                ),
              ),
            ),
          ),
        ),
        if (selectedNames.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final name in selectedNames.take(6))
                InputChip(
                  label: Text(name, overflow: TextOverflow.ellipsis),
                  visualDensity: VisualDensity.compact,
                  onDeleted: () {
                    final next = Set<String>.from(selectedNames)..remove(name);
                    onChanged(next);
                  },
                ),
              if (selectedNames.length > 6)
                Chip(
                  label: Text('+${selectedNames.length - 6}'),
                  visualDensity: VisualDensity.compact,
                ),
              ActionChip(
                label: const Text('Clear selection'),
                visualDensity: VisualDensity.compact,
                onPressed: () => onChanged(<String>{}),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            selectedNames.length == catalog.length && catalog.isNotEmpty
                ? 'All Municipalities and Cities (${catalog.length} locations)'
                : '${selectedNames.length} location${selectedNames.length == 1 ? '' : 's'} selected',
            style: const TextStyle(fontSize: 12, color: AppColors.textGrey),
          ),
        ],
      ],
    );
  }
}

class _LocationPickerDialog extends StatefulWidget {
  const _LocationPickerDialog({required this.initial});

  final Set<String> initial;

  @override
  State<_LocationPickerDialog> createState() => _LocationPickerDialogState();
}

class _LocationPickerDialogState extends State<_LocationPickerDialog> {
  late Set<String> _selected;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _selected = Set<String>.from(widget.initial);
  }

  bool _matches(Municipality m) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return m.name.toLowerCase().contains(q) ||
        m.shortName.toLowerCase().contains(q);
  }

  bool? _groupValue(Iterable<String> names) {
    if (names.isEmpty) return false;
    final selectedCount = names.where(_selected.contains).length;
    if (selectedCount == 0) return false;
    if (selectedCount == names.length) return true;
    return null;
  }

  void _setGroup(Iterable<String> names, bool select) {
    setState(() {
      if (select) {
        _selected.addAll(names);
      } else {
        _selected.removeAll(names);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final catalog = eventLocationCatalog();
    final cities = eventCityLocations(catalog);
    final munis = eventMunicipalityLocations(catalog);
    final allNames = [for (final m in catalog) m.name];
    final cityNames = [for (final m in cities) m.name];
    final muniNames = [for (final m in munis) m.name];
    final visibleCities = cities.where(_matches).toList();
    final visibleMunis = munis.where(_matches).toList();

    return AlertDialog(
      title: const Text('Select locations'),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      content: SizedBox(
        width: 420,
        height: 460,
        child: Column(
          children: [
            TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search municipality or city',
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${_selected.length} of ${catalog.length} selected',
                style: const TextStyle(fontSize: 12, color: AppColors.textGrey),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                shrinkWrap: true,
                children: [
                  CheckboxListTile(
                    tristate: true,
                    value: _groupValue(allNames),
                    onChanged: (_) => _setGroup(
                      allNames,
                      _groupValue(allNames) != true,
                    ),
                    title: Text(
                      'Select All Municipalities and Cities (${catalog.length})',
                    ),
                    controlAffinity: ListTileControlAffinity.leading,
                    dense: true,
                  ),
                  CheckboxListTile(
                    tristate: true,
                    value: _groupValue(muniNames),
                    onChanged: (_) => _setGroup(
                      muniNames,
                      _groupValue(muniNames) != true,
                    ),
                    title: Text('Select All Municipalities (${muniNames.length})'),
                    controlAffinity: ListTileControlAffinity.leading,
                    dense: true,
                  ),
                  CheckboxListTile(
                    tristate: true,
                    value: _groupValue(cityNames),
                    onChanged: (_) => _setGroup(
                      cityNames,
                      _groupValue(cityNames) != true,
                    ),
                    title: Text('Select All Cities (${cityNames.length})'),
                    controlAffinity: ListTileControlAffinity.leading,
                    dense: true,
                  ),
                  const Divider(),
                  if (visibleCities.isNotEmpty)
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
                      child: Text(
                        'Cities',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  for (final m in visibleCities)
                    CheckboxListTile(
                      value: _selected.contains(m.name),
                      onChanged: (v) {
                        setState(() {
                          if (v == true) {
                            _selected.add(m.name);
                          } else {
                            _selected.remove(m.name);
                          }
                        });
                      },
                      title: Text(m.name),
                      controlAffinity: ListTileControlAffinity.leading,
                      dense: true,
                    ),
                  if (visibleMunis.isNotEmpty)
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
                      child: Text(
                        'Municipalities',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  for (final m in visibleMunis)
                    CheckboxListTile(
                      value: _selected.contains(m.name),
                      onChanged: (v) {
                        setState(() {
                          if (v == true) {
                            _selected.add(m.name);
                          } else {
                            _selected.remove(m.name);
                          }
                        });
                      },
                      title: Text(m.name),
                      controlAffinity: ListTileControlAffinity.leading,
                      dense: true,
                    ),
                  if (visibleCities.isEmpty && visibleMunis.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('No matching locations.'),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => setState(() => _selected.clear()),
          child: const Text('Clear selection'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _selected),
          child: const Text('Done'),
        ),
      ],
    );
  }
}
