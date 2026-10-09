import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:atmos_trs_system/config/dae_residence_catalog.dart';
import 'package:atmos_trs_system/config/mice_event_types.dart';
import 'package:atmos_trs_system/models/mice_register.dart';
import 'package:atmos_trs_system/utils/mice_register_calculator.dart';
import 'package:atmos_trs_system/widgets/ae_register/ae_sheet_kit.dart';
import 'package:atmos_trs_system/widgets/establishment_dash_tokens.dart';

/// Result of the event dialog: the event plus a custom type to remember.
class MiceEventDialogResult {
  const MiceEventDialogResult(this.event, {this.newType});

  final MiceEvent event;

  /// Set when the venue typed a type that is not in its suggestions yet.
  final MiceEventType? newType;
}

/// Entry form for one CUS MICE event row. Totals are computed; the sex split
/// auto-completes so Male + Female always matches the attendee total.
class MiceEventDialog extends StatefulWidget {
  const MiceEventDialog({
    super.key,
    required this.year,
    required this.month,
    required this.types,
    this.initial,
    this.duplicate = false,
  });

  final int year;
  final int month;
  final List<MiceEventType> types;
  final MiceEvent? initial;

  /// Pre-fill from [initial] but save as a new event.
  final bool duplicate;

  static Future<MiceEventDialogResult?> show(
    BuildContext context, {
    required int year,
    required int month,
    required List<MiceEventType> types,
    MiceEvent? initial,
    bool duplicate = false,
  }) =>
      showDialog<MiceEventDialogResult>(
        context: context,
        builder: (_) => MiceEventDialog(
          year: year,
          month: month,
          types: types,
          initial: initial,
          duplicate: duplicate,
        ),
      );

  @override
  State<MiceEventDialog> createState() => _MiceEventDialogState();
}

class _MiceEventDialogState extends State<MiceEventDialog> {
  static final _foreignCountries = DaeResidenceCatalog.pickerOptions
      .where((o) => DaeResidenceCatalog.bucketFor(o) == DaeResidenceBucket.foreign)
      .toList();

  late DateTime _start;
  DateTime? _end;
  late bool _multiDay;
  late bool _hasExhibit;
  late String _typeText;
  MiceEventType? _type;
  late MiceCategory _newCategory;
  late Map<String, int> _countries;
  bool _showCountries = false;
  bool _showOrganizer = true;
  String? _error;

  final _name = TextEditingController();
  final _hours = TextEditingController();
  final _local = TextEditingController();
  final _foreign = TextEditingController();
  final _male = TextEditingController();
  final _female = TextEditingController();
  final _exhibitors = TextEditingController();
  final _visitors = TextEditingController();
  final _orgName = TextEditingController();
  final _orgAddress = TextEditingController();
  final _contactPerson = TextEditingController();
  final _contactNo = TextEditingController();
  final _remarks = TextEditingController();

  bool get _isEdit => widget.initial != null && !widget.duplicate;
  bool get _isNewType => _type == null && _typeText.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    final now = DateTime.now();
    final inMonth = now.year == widget.year && now.month == widget.month;
    _start = i?.dateStart ?? DateTime(widget.year, widget.month, inMonth ? now.day : 1);
    _end = i?.isMultiDay == true ? i!.lastDay : null;
    _multiDay = _end != null;
    _hasExhibit = i?.hasExhibit ?? false;
    _typeText = i?.eventType ?? '';
    _type = MiceEventTypes.find(_typeText, widget.types) ??
        (i == null ? null : MiceEventType(i.eventType, i.category));
    _newCategory = i?.category ?? MiceCategory.meeting;
    _countries = Map.of(i?.foreignCountries ?? const {});
    _showCountries = _countries.isNotEmpty;
    _name.text = i?.eventName ?? '';
    _hours.text = i == null ? '' : MiceRegisterCalculator.hoursLabel(i.hours);
    _local.text = i == null ? '' : '${i.local}';
    _foreign.text = i == null ? '0' : '${i.foreign}';
    _male.text = i == null ? '' : '${i.male}';
    _female.text = i == null ? '' : '${i.female}';
    _exhibitors.text = (i?.exhibitors ?? 0) == 0 ? '' : '${i!.exhibitors}';
    _visitors.text = (i?.exhibitVisitors ?? 0) == 0 ? '' : '${i!.exhibitVisitors}';
    _orgName.text = i?.organizerName ?? '';
    _orgAddress.text = i?.organizerAddress ?? '';
    _contactPerson.text = i?.contactPerson ?? '';
    _contactNo.text = i?.contactNo ?? '';
    _remarks.text = i?.remarks ?? '';
  }

  @override
  void dispose() {
    for (final c in [
      _name, _hours, _local, _foreign, _male, _female, _exhibitors, _visitors,
      _orgName, _orgAddress, _contactPerson, _contactNo, _remarks,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  int _int(TextEditingController c) => int.tryParse(c.text.trim()) ?? 0;
  double _dbl(TextEditingController c) => double.tryParse(c.text.trim().replaceAll(',', '.')) ?? 0;
  int get _total => _int(_local) + _int(_foreign);

  void _complement({required bool fromMale}) {
    final t = _total;
    if (fromMale) {
      _female.text = '${(t - _int(_male).clamp(0, t))}';
    } else {
      _male.text = '${(t - _int(_female).clamp(0, t))}';
    }
    setState(() {});
  }

  void _onAttendeesChanged() {
    final t = _total;
    // Keep the split valid as totals change: male stays, female absorbs.
    if (_male.text.trim().isEmpty && _female.text.trim().isEmpty) {
      _female.text = '0';
      _male.text = '$t';
    } else {
      final m = _int(_male).clamp(0, t);
      _male.text = '$m';
      _female.text = '${t - m}';
    }
    setState(() {});
  }

  Future<void> _pickDate({required bool end}) async {
    final now = DateTime.now();
    final first = end ? _start : DateTime(now.year - 5);
    final last = DateTime(now.year + 1, 12, 31);
    final current = end ? (_end ?? _start) : _start;
    final picked = await showDatePicker(
      context: context,
      initialDate: current.isBefore(first) ? first : current,
      firstDate: first,
      lastDate: last,
    );
    if (picked == null) return;
    setState(() {
      if (end) {
        _end = picked;
      } else {
        _start = picked;
        if (_end != null && _end!.isBefore(picked)) _end = picked;
      }
    });
  }

  MiceEvent _build() {
    final category = _type?.category ?? _newCategory;
    final foreign = _int(_foreign);
    return MiceEvent(
      id: _isEdit ? widget.initial!.id : '',
      dateStart: _start,
      dateEnd: _multiDay ? _end : null,
      eventName: _name.text.trim(),
      hours: _dbl(_hours),
      eventType: (_type?.label ?? _typeText).trim(),
      category: category,
      foreign: foreign,
      local: _int(_local),
      male: _int(_male),
      female: _int(_female),
      hasExhibit: _hasExhibit,
      exhibitors: _hasExhibit ? _int(_exhibitors) : 0,
      exhibitVisitors: _hasExhibit ? _int(_visitors) : 0,
      organizerName: _orgName.text.trim(),
      organizerAddress: _orgAddress.text.trim(),
      contactPerson: _contactPerson.text.trim(),
      contactNo: _contactNo.text.trim(),
      remarks: _remarks.text.trim(),
      foreignCountries: foreign > 0 ? Map.of(_countries) : const {},
      isDemo: _isEdit && widget.initial!.isDemo,
    );
  }

  void _submit() {
    final e = _build();
    final issues = MiceRegisterCalculator.validate(e);
    if (issues.isNotEmpty) return setState(() => _error = issues.first);
    Navigator.pop(
      context,
      MiceEventDialogResult(e, newType: _isNewType ? MiceEventType(e.eventType, e.category, custom: true) : null),
    );
  }

  @override
  Widget build(BuildContext context) {
    final digits = [FilteringTextInputFormatter.digitsOnly];
    final preview = _build();
    final warnings = MiceRegisterCalculator.warnings(preview);
    final wide = MediaQuery.sizeOf(context).width >= 640;

    Widget pair(Widget a, Widget b) => wide
        ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: a),
            const SizedBox(width: 10),
            Expanded(child: b),
          ])
        : Column(children: [a, b]);

    return AlertDialog(
      title: Text(
        _isEdit ? 'Edit event' : (widget.duplicate ? 'Duplicate event' : 'Add event'),
        style: AeDashTokens.heading(size: 18),
      ),
      content: SizedBox(
        width: 600,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              _field(
                label: 'Event name',
                child: TextField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  decoration: _dec(hint: 'e.g. Santos–Reyes Wedding, DepEd Division Seminar'),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              _typeField(),
              pair(
                _field(
                  label: _multiDay ? 'Start date' : 'Date',
                  child: _dateBox(_start, () => _pickDate(end: false)),
                ),
                _multiDay
                    ? _field(
                        label: 'End date',
                        child: _dateBox(_end ?? _start, () => _pickDate(end: true)),
                      )
                    : _field(
                        label: 'Number of hours',
                        child: TextField(
                          controller: _hours,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                          decoration: _dec(hint: 'e.g. 4 or 2.5', suffix: const Icon(Icons.schedule_rounded, size: 18)),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
              ),
              Row(children: [
                Checkbox(
                  value: _multiDay,
                  onChanged: (v) => setState(() {
                    _multiDay = v ?? false;
                    if (_multiDay) _end ??= DateTime(_start.year, _start.month, _start.day + 1);
                  }),
                ),
                Expanded(
                  child: Text(
                    'Multi-day event (one row; hours = total for all days)',
                    style: AeDashTokens.body(size: 12.5, color: AeDashTokens.text),
                  ),
                ),
              ]),
              if (_multiDay)
                _field(
                  label: 'Total number of hours (${preview.days} day(s))',
                  child: TextField(
                    controller: _hours,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                    decoration: _dec(hint: 'e.g. 16', suffix: const Icon(Icons.schedule_rounded, size: 18)),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              _sectionLabel('No. of attendees', 'Total = Local + Foreign · Male + Female must equal the total'),
              Row(children: [
                Expanded(child: _numField('Local', _local, digits, onChanged: (_) => _onAttendeesChanged())),
                const SizedBox(width: 10),
                Expanded(child: _numField('Foreign', _foreign, digits, onChanged: (_) => _onAttendeesChanged())),
                const SizedBox(width: 10),
                SizedBox(
                  width: 90,
                  child: _field(
                    label: 'Total',
                    child: InputDecorator(
                      decoration: _dec(),
                      child: Text('$_total', style: AeDashTokens.number(size: 15)),
                    ),
                  ),
                ),
              ]),
              Row(children: [
                Expanded(child: _numField('Male', _male, digits, onChanged: (_) => _complement(fromMale: true))),
                const SizedBox(width: 10),
                Expanded(child: _numField('Female', _female, digits, onChanged: (_) => _complement(fromMale: false))),
              ]),
              if (_int(_foreign) > 0) _countriesSection(),
              SwitchListTile(
                value: _hasExhibit,
                contentPadding: EdgeInsets.zero,
                dense: true,
                activeThumbColor: AeDashTokens.accent,
                title: Text('Has exhibits (booths / trade fair)', style: AeDashTokens.body(size: 13, color: AeDashTokens.text)),
                onChanged: (v) => setState(() => _hasExhibit = v),
              ),
              if (_hasExhibit)
                Row(children: [
                  Expanded(child: _numField('Number of exhibitors', _exhibitors, digits)),
                  const SizedBox(width: 10),
                  Expanded(child: _numField('Number of visitors', _visitors, digits)),
                ]),
              InkWell(
                onTap: () => setState(() => _showOrganizer = !_showOrganizer),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(children: [
                    Icon(_showOrganizer ? Icons.expand_less_rounded : Icons.expand_more_rounded, size: 20),
                    const SizedBox(width: 4),
                    Text('Organizer & contact', style: AeDashTokens.section(size: 13.5)),
                  ]),
                ),
              ),
              if (_showOrganizer) ...[
                pair(
                  _field(label: 'Organizer name', child: TextField(controller: _orgName, decoration: _dec(), onChanged: (_) => setState(() {}))),
                  _field(label: 'Organizer address', child: TextField(controller: _orgAddress, decoration: _dec())),
                ),
                pair(
                  _field(label: 'Contact person', child: TextField(controller: _contactPerson, decoration: _dec(), onChanged: (_) => setState(() {}))),
                  _field(
                    label: 'Tel. / mobile no.',
                    child: TextField(
                      controller: _contactNo,
                      keyboardType: TextInputType.phone,
                      decoration: _dec(),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ),
              ],
              _field(label: 'Remarks (optional)', child: TextField(controller: _remarks, decoration: _dec(), maxLines: 2, minLines: 1)),
              if (warnings.isNotEmpty)
                Text(
                  warnings.join(' · '),
                  style: AeDashTokens.body(size: 11.5, color: AeDashTokens.warning, weight: FontWeight.w600),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_error!, style: AeDashTokens.body(size: 12.5, color: AeDashTokens.danger, weight: FontWeight.w700)),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: AeDashTokens.accent),
          onPressed: _submit,
          icon: const Icon(Icons.check_rounded, size: 18),
          label: Text(_isEdit ? 'Save' : 'Add'),
        ),
      ],
    );
  }

  /// Type of event: suggestions (base + venue custom). Unknown text offers
  /// "Add as new type" with a one-tap category picker.
  Widget _typeField() {
    return _field(
      label: 'Type of event',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Autocomplete<MiceEventType>(
            initialValue: TextEditingValue(text: _typeText),
            displayStringForOption: (t) => t.label,
            optionsBuilder: (v) {
              final q = v.text.trim();
              final hits = MiceEventTypes.search(q, widget.types);
              final exact = MiceEventTypes.find(q, widget.types) != null;
              return [
                ...hits,
                if (q.isNotEmpty && !exact) MiceEventType(q, MiceEventTypes.guessCategory(q), custom: true),
              ];
            },
            optionsViewBuilder: (context, onSelected, options) => Align(
              alignment: Alignment.topLeft,
              child: Material(
                elevation: 6,
                borderRadius: BorderRadius.circular(10),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 280, maxWidth: 520),
                  child: ListView(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    children: [
                      for (final t in options)
                        ListTile(
                          dense: true,
                          leading: Icon(
                            MiceEventTypes.find(t.label, widget.types) == null ? Icons.add_circle_outline_rounded : t.category.icon,
                            size: 18,
                            color: AeDashTokens.accent,
                          ),
                          title: Text(
                            MiceEventTypes.find(t.label, widget.types) == null ? 'Add “${t.label}” as a new type' : t.label,
                          ),
                          subtitle: Text(
                            MiceEventTypes.find(t.label, widget.types) == null
                                ? 'Saved to your venue’s list — pick its category below'
                                : '${t.category.label}${t.custom ? ' · your type' : ''}',
                            style: AeDashTokens.body(size: 11),
                          ),
                          onTap: () => onSelected(t),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            onSelected: (t) => setState(() {
              _typeText = t.label;
              _type = MiceEventTypes.find(t.label, widget.types);
              if (_type == null) _newCategory = t.category;
            }),
            fieldViewBuilder: (ctx, ctrl, focus, onSubmit) => TextField(
              controller: ctrl,
              focusNode: focus,
              textCapitalization: TextCapitalization.sentences,
              decoration: _dec(
                hint: 'Type to search — e.g. seminar, wedding, team building',
                suffix: Icon(_type?.category.icon ?? Icons.category_rounded, size: 18),
              ),
              onChanged: (v) => setState(() {
                _typeText = v;
                _type = MiceEventTypes.find(v, widget.types);
                if (_type == null) _newCategory = MiceEventTypes.guessCategory(v);
              }),
            ),
          ),
          const SizedBox(height: 6),
          if (_isNewType) ...[
            Text('New type — which category is it?', style: AeDashTokens.body(size: 11.5, weight: FontWeight.w700)),
            const SizedBox(height: 4),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final c in MiceCategory.values)
                ChoiceChip(
                  label: Text(c.label),
                  avatar: Icon(c.icon, size: 16),
                  selected: _newCategory == c,
                  selectedColor: AeDashTokens.softAccent,
                  onSelected: (_) => setState(() => _newCategory = c),
                ),
            ]),
          ] else if (_type != null)
            Text('Category: ${_type!.category.label}', style: AeDashTokens.body(size: 11.5)),
        ],
      ),
    );
  }

  Widget _countriesSection() {
    final assigned = _countries.values.fold<int>(0, (a, b) => a + b);
    final foreign = _int(_foreign);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: AeDashTokens.mutedSurface, borderRadius: BorderRadius.circular(10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => _showCountries = !_showCountries),
            child: Row(children: [
              const Icon(Icons.public_rounded, size: 18, color: AeDashTokens.info),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Foreign attendees by country (optional) · $assigned of $foreign assigned',
                  style: AeDashTokens.body(size: 12.5, color: AeDashTokens.text, weight: FontWeight.w700),
                ),
              ),
              Icon(_showCountries ? Icons.expand_less_rounded : Icons.expand_more_rounded),
            ]),
          ),
          if (_showCountries) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final e in _countries.entries)
                InputChip(
                  label: Text('${e.key} · ${e.value}'),
                  onDeleted: () => setState(() => _countries.remove(e.key)),
                ),
            ]),
            const SizedBox(height: 6),
            Autocomplete<String>(
              optionsBuilder: (v) {
                final q = v.text.trim().toLowerCase();
                if (q.isEmpty) return const Iterable<String>.empty();
                return _foreignCountries.where((c) => c.toLowerCase().contains(q)).take(10);
              },
              onSelected: _addCountry,
              fieldViewBuilder: (ctx, ctrl, focus, onSubmit) => TextField(
                controller: ctrl,
                focusNode: focus,
                decoration: _dec(hint: 'Add a country…', suffix: const Icon(Icons.add_rounded, size: 18)),
                onSubmitted: (v) {
                  if (v.trim().isNotEmpty) _addCountry(v.trim());
                  ctrl.clear();
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _addCountry(String country) async {
    final remaining = (_int(_foreign) - _countries.values.fold<int>(0, (a, b) => a + b)).clamp(0, 1 << 30);
    final ctrl = TextEditingController(text: '${_countries[country] ?? (remaining > 0 ? remaining : 1)}');
    final n = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Attendees from $country'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: _dec(),
          onSubmitted: (v) => Navigator.pop(ctx, int.tryParse(v)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, int.tryParse(ctrl.text)), child: const Text('OK')),
        ],
      ),
    );
    ctrl.dispose();
    if (n == null || !mounted) return;
    setState(() {
      if (n <= 0) {
        _countries.remove(country);
      } else {
        _countries[country] = n;
      }
    });
  }

  Widget _dateBox(DateTime d, VoidCallback onTap) => InkWell(
        onTap: onTap,
        child: InputDecorator(
          decoration: _dec(suffix: const Icon(Icons.calendar_month_rounded, size: 18)),
          child: Text(AeSheetKit.shortDate(d)),
        ),
      );

  Widget _numField(
    String label,
    TextEditingController c,
    List<TextInputFormatter> f, {
    ValueChanged<String>? onChanged,
  }) =>
      _field(
        label: label,
        child: TextField(
          controller: c,
          keyboardType: TextInputType.number,
          inputFormatters: f,
          decoration: _dec(),
          onChanged: onChanged ?? (_) => setState(() {}),
        ),
      );

  Widget _sectionLabel(String title, String hint) => Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: AeDashTokens.section(size: 13.5)),
          Text(hint, style: AeDashTokens.body(size: 11.5)),
        ]),
      );

  Widget _field({required String label, required Widget child}) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: AeDashTokens.body(size: 11.5, weight: FontWeight.w700, color: AeDashTokens.text)),
            const SizedBox(height: 4),
            child,
          ],
        ),
      );

  InputDecoration _dec({String? hint, Widget? suffix}) => InputDecoration(
        isDense: true,
        hintText: hint,
        suffixIcon: suffix,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      );
}
