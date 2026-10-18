import 'package:atmos_trs_system/data/misamis_occidental_municipalities.dart';
import 'package:atmos_trs_system/models/visit_origin_breakdown.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Male / female counts by residence for people on this scan.
///
/// The spot's municipality decides "This Municipality". Other Misamis
/// Occidental cities are "This Province". The signed-in tourist is prefilled
/// into one bin when [prefillScanner] is true; companions are left blank.
class VisitOriginBreakdownFields extends StatefulWidget {
  const VisitOriginBreakdownFields({
    super.key,
    required this.spotMunicipality,
    required this.partySize,
    required this.maleCount,
    required this.femaleCount,
    this.prefillScanner = true,
  });

  final String spotMunicipality;
  final int partySize;
  final int maleCount;
  final int femaleCount;
  final bool prefillScanner;

  @override
  State<VisitOriginBreakdownFields> createState() =>
      VisitOriginBreakdownFieldsState();
}

class VisitOriginBreakdownFieldsState extends State<VisitOriginBreakdownFields> {
  final _muniMale = TextEditingController(text: '0');
  final _muniFemale = TextEditingController(text: '0');
  final List<_PlaceRow> _province = [];
  final List<_PlaceRow> _other = [];
  final List<_PlaceRow> _foreign = [];
  bool _prefilled = false;

  @override
  void initState() {
    super.initState();
    if (widget.prefillScanner && widget.partySize > 0) {
      _loadPrefill();
    }
  }

  @override
  void dispose() {
    _muniMale.dispose();
    _muniFemale.dispose();
    for (final row in [..._province, ..._other, ..._foreign]) {
      row.dispose();
    }
    super.dispose();
  }

  Future<void> _loadPrefill() async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty) return;
    try {
      final doc = await FirebaseFirestore.instance.collection('tourists').doc(uid).get();
      if (!mounted || _prefilled || !doc.exists) return;
      final data = doc.data();
      if (data == null) return;
      final filled = VisitOriginBreakdown.prefill(
        spotMunicipality: widget.spotMunicipality,
        profile: data,
      );
      _apply(filled);
      _prefilled = true;
      if (mounted) setState(() {});
    } catch (_) {}
  }

  void _apply(VisitOriginBreakdown filled) {
    _muniMale.text = '${filled.thisMunicipalityMale}';
    _muniFemale.text = '${filled.thisMunicipalityFemale}';
    _replace(_province, filled.thisProvince);
    _replace(_other, filled.otherProvinces);
    _replace(_foreign, filled.foreign);
  }

  void _replace(List<_PlaceRow> target, List<OriginPlaceCount> source) {
    for (final row in target) {
      row.dispose();
    }
    target
      ..clear()
      ..addAll(source.map(_PlaceRow.fromCount));
  }

  VisitOriginBreakdown get value => VisitOriginBreakdown(
        spotMunicipality: widget.spotMunicipality,
        thisMunicipalityMale: _parse(_muniMale),
        thisMunicipalityFemale: _parse(_muniFemale),
        thisProvince: [for (final r in _province) r.value],
        otherProvinces: [for (final r in _other) r.value],
        foreign: [for (final r in _foreign) r.value],
      );

  String? validate() => value.validate(
        partySize: widget.partySize,
        maleCount: widget.maleCount,
        femaleCount: widget.femaleCount,
      );

  int _parse(TextEditingController c) => int.tryParse(c.text.trim()) ?? 0;

  @override
  Widget build(BuildContext context) {
    if (widget.partySize <= 0) {
      return const Text(
        'No companions to classify.',
        style: TextStyle(color: Color(0xFF6B7280), fontSize: 13),
      );
    }
    final current = value;
    final ok = current.total == widget.partySize &&
        current.male == widget.maleCount &&
        current.female == widget.femaleCount;
    final otherTowns = [
      for (final m in getMisamisOccidentalMunicipalities())
        if (!_same(m.name, widget.spotMunicipality)) m.name,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Tourist origin',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          'Split everyone in this party by where they live. '
          'This Municipality is ${widget.spotMunicipality}. '
          'This Province is other cities and towns in Misamis Occidental. '
          'Each person goes in only one group.',
          style: const TextStyle(color: Color(0xFF6B7280), fontSize: 12, height: 1.35),
        ),
        const SizedBox(height: 12),
        _sexCard(
          title: 'This Municipality',
          subtitle: widget.spotMunicipality,
          male: _muniMale,
          female: _muniFemale,
        ),
        const SizedBox(height: 10),
        _placeSection(
          title: 'This Province',
          subtitle: 'Other Misamis Occidental city or town',
          rows: _province,
          choices: otherTowns,
          addLabel: 'Add city or town',
        ),
        const SizedBox(height: 10),
        _placeSection(
          title: 'Other Philippine Provinces',
          subtitle: 'Province outside Misamis Occidental',
          rows: _other,
          addLabel: 'Add province',
          hint: 'e.g. Cebu',
        ),
        const SizedBox(height: 10),
        _placeSection(
          title: 'Foreign Residents',
          subtitle: 'Country of residence',
          rows: _foreign,
          addLabel: 'Add country',
          hint: 'e.g. Japan',
        ),
        const SizedBox(height: 10),
        Text(
          'Origin total ${current.total} of ${widget.partySize} '
          '(${current.male} male, ${current.female} female)',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: ok ? const Color(0xFF15803D) : const Color(0xFFB45309),
          ),
        ),
      ],
    );
  }

  Widget _sexCard({
    required String title,
    required String subtitle,
    required TextEditingController male,
    required TextEditingController female,
  }) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
          Text(subtitle, style: const TextStyle(color: Color(0xFF6B7280), fontSize: 12)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _num('Male', male)),
              const SizedBox(width: 10),
              Expanded(child: _num('Female', female)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _placeSection({
    required String title,
    required String subtitle,
    required List<_PlaceRow> rows,
    required String addLabel,
    List<String>? choices,
    String? hint,
  }) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
          Text(subtitle, style: const TextStyle(color: Color(0xFF6B7280), fontSize: 12)),
          for (var i = 0; i < rows.length; i++) ...[
            const SizedBox(height: 8),
            _placeEditor(
              row: rows[i],
              choices: choices,
              hint: hint,
              onRemove: () => setState(() {
                rows[i].dispose();
                rows.removeAt(i);
              }),
            ),
          ],
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => rows.add(_PlaceRow())),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: Text(addLabel),
            ),
          ),
        ],
      ),
    );
  }

  Widget _placeEditor({
    required _PlaceRow row,
    required VoidCallback onRemove,
    List<String>? choices,
    String? hint,
  }) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: choices == null
                  ? TextField(
                      controller: row.place,
                      decoration: InputDecoration(
                        isDense: true,
                        labelText: 'Place',
                        hintText: hint,
                        border: const OutlineInputBorder(),
                      ),
                      onChanged: (_) => setState(() {}),
                    )
                  : DropdownButtonFormField<String>(
                      initialValue: choices.contains(row.place.text) ? row.place.text : null,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        isDense: true,
                        labelText: 'City or town',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (final name in choices)
                          DropdownMenuItem(value: name, child: Text(name)),
                      ],
                      onChanged: (v) => setState(() => row.place.text = v ?? ''),
                    ),
            ),
            IconButton(
              tooltip: 'Remove',
              onPressed: onRemove,
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: _num('Male', row.male)),
            const SizedBox(width: 10),
            Expanded(child: _num('Female', row.female)),
          ],
        ),
      ],
    );
  }

  Widget _num(String label, TextEditingController controller) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(
        isDense: true,
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      onChanged: (_) => setState(() {}),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: child,
    );
  }
}

class _PlaceRow {
  _PlaceRow()
      : place = TextEditingController(),
        male = TextEditingController(text: '0'),
        female = TextEditingController(text: '0');

  _PlaceRow.fromCount(OriginPlaceCount count)
      : place = TextEditingController(text: count.place),
        male = TextEditingController(text: '${count.male}'),
        female = TextEditingController(text: '${count.female}');

  final TextEditingController place;
  final TextEditingController male;
  final TextEditingController female;

  OriginPlaceCount get value => OriginPlaceCount(
        place: place.text.trim(),
        male: int.tryParse(male.text.trim()) ?? 0,
        female: int.tryParse(female.text.trim()) ?? 0,
      );

  void dispose() {
    place.dispose();
    male.dispose();
    female.dispose();
  }
}

bool _same(String a, String b) {
  String n(String v) => v
      .trim()
      .toLowerCase()
      .replaceAll(' city', '')
      .replaceAll(' municipality', '');
  final x = n(a);
  final y = n(b);
  if (x.isEmpty || y.isEmpty) return false;
  return x == y || x.contains(y) || y.contains(x);
}
