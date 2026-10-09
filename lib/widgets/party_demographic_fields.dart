import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:atmos_trs_system/utils/party_count_complements.dart';

/// Semi-automatic party + Male/Female + Filipino/Foreign fields.
///
/// Editing one side of a pair fills the complement from [partySize].
class PartyDemographicFields extends StatefulWidget {
  const PartyDemographicFields({
    super.key,
    required this.initialPartySize,
    required this.initialMale,
    required this.initialFemale,
    required this.initialFilipino,
    required this.initialForeign,
    this.onChanged,
    this.showResidency = true,
    this.partyLabel = 'Party size',
    this.maleLabel = 'Male',
    this.femaleLabel = 'Female',
    this.filipinoLabel = 'Filipino',
    this.foreignLabel = 'Foreign',
    this.partyHelperText = 'Total guests in this stay / visit',
    this.minPartySize = 1,
  });

  final int initialPartySize;
  final int initialMale;
  final int initialFemale;
  final int initialFilipino;
  final int initialForeign;
  final void Function(PartyDemographicValue value)? onChanged;
  /// When false, Filipino/Foreign fields are hidden and treated as valid.
  final bool showResidency;
  final String partyLabel;
  final String maleLabel;
  final String femaleLabel;
  final String filipinoLabel;
  final String foreignLabel;
  final String partyHelperText;

  /// 0 allows "no companions" (Laag with Friends group check-in).
  final int minPartySize;

  @override
  State<PartyDemographicFields> createState() => PartyDemographicFieldsState();
}

class PartyDemographicValue {
  const PartyDemographicValue({
    required this.partySize,
    required this.maleCount,
    required this.femaleCount,
    required this.filipinoCount,
    required this.foreignCount,
    this.minPartySize = 1,
  });

  final int partySize;
  final int maleCount;
  final int femaleCount;
  final int filipinoCount;
  final int foreignCount;
  final int minPartySize;

  bool get sexValid => partySize == 0
      ? maleCount == 0 && femaleCount == 0
      : PartyCountComplements.sumsToTotal(partySize, maleCount, femaleCount);

  bool get residencyValid => partySize == 0
      ? filipinoCount == 0 && foreignCount == 0
      : PartyCountComplements.sumsToTotal(
          partySize,
          filipinoCount,
          foreignCount,
        );

  bool get isValid => sexValid && residencyValid && partySize >= minPartySize;

  String? get validationMessage {
    if (partySize < minPartySize) {
      return 'Party size must be at least $minPartySize.';
    }
    if (!sexValid) {
      return 'Male + Female must equal party size ($partySize).';
    }
    if (!residencyValid) {
      return 'Filipino + Foreign must equal party size ($partySize).';
    }
    return null;
  }
}

class PartyDemographicFieldsState extends State<PartyDemographicFields> {
  late final TextEditingController _partyCtrl;
  late final TextEditingController _maleCtrl;
  late final TextEditingController _femaleCtrl;
  late final TextEditingController _filipinoCtrl;
  late final TextEditingController _foreignCtrl;

  /// Last edited side of each pair so party-size changes keep that side.
  bool _sexLastWasMale = true;
  bool _residencyLastWasFilipino = true;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    final party = widget.initialPartySize < widget.minPartySize
        ? widget.minPartySize
        : widget.initialPartySize;
    var male = PartyCountComplements.clampKnown(party, widget.initialMale);
    var female = PartyCountComplements.clampKnown(party, widget.initialFemale);
    if (!PartyCountComplements.sumsToTotal(party, male, female)) {
      if (widget.initialMale > 0 || widget.initialFemale == 0) {
        female = PartyCountComplements.complement(party, male);
        _sexLastWasMale = true;
      } else {
        male = PartyCountComplements.complement(party, female);
        _sexLastWasMale = false;
      }
    }
    var fil = PartyCountComplements.clampKnown(party, widget.initialFilipino);
    var for_ = PartyCountComplements.clampKnown(party, widget.initialForeign);
    if (!PartyCountComplements.sumsToTotal(party, fil, for_)) {
      if (widget.initialFilipino > 0 || widget.initialForeign == 0) {
        for_ = PartyCountComplements.complement(party, fil);
        _residencyLastWasFilipino = true;
      } else {
        fil = PartyCountComplements.complement(party, for_);
        _residencyLastWasFilipino = false;
      }
    }

    _partyCtrl = TextEditingController(text: '$party');
    _maleCtrl = TextEditingController(text: '$male');
    _femaleCtrl = TextEditingController(text: '$female');
    _filipinoCtrl = TextEditingController(text: '$fil');
    _foreignCtrl = TextEditingController(text: '$for_');

    WidgetsBinding.instance.addPostFrameCallback((_) => _emit());
  }

  @override
  void dispose() {
    _partyCtrl.dispose();
    _maleCtrl.dispose();
    _femaleCtrl.dispose();
    _filipinoCtrl.dispose();
    _foreignCtrl.dispose();
    super.dispose();
  }

  PartyDemographicValue get value {
    final min = widget.minPartySize;
    final party = _parse(_partyCtrl, fallback: min);
    final p = party < min ? min : party;
    if (!widget.showResidency) {
      return PartyDemographicValue(
        partySize: p,
        maleCount: _parse(_maleCtrl),
        femaleCount: _parse(_femaleCtrl),
        filipinoCount: p,
        foreignCount: 0,
        minPartySize: min,
      );
    }
    return PartyDemographicValue(
      partySize: p,
      maleCount: _parse(_maleCtrl),
      femaleCount: _parse(_femaleCtrl),
      filipinoCount: _parse(_filipinoCtrl),
      foreignCount: _parse(_foreignCtrl),
      minPartySize: min,
    );
  }

  int _parse(TextEditingController c, {int fallback = 0}) {
    return int.tryParse(c.text.trim()) ?? fallback;
  }

  void _setText(TextEditingController c, int n) {
    final next = '$n';
    if (c.text == next) return;
    c.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
  }

  void _rebalance() {
    if (_syncing) return;
    _syncing = true;
    try {
      final min = widget.minPartySize;
      final partyRaw = _parse(_partyCtrl, fallback: min);
      final party = partyRaw < min ? min : partyRaw;
      if (partyRaw < min) _setText(_partyCtrl, min);

      if (_sexLastWasMale) {
        final m = PartyCountComplements.clampKnown(party, _parse(_maleCtrl));
        _setText(_maleCtrl, m);
        _setText(_femaleCtrl, PartyCountComplements.complement(party, m));
      } else {
        final f = PartyCountComplements.clampKnown(party, _parse(_femaleCtrl));
        _setText(_femaleCtrl, f);
        _setText(_maleCtrl, PartyCountComplements.complement(party, f));
      }

      if (widget.showResidency) {
        if (_residencyLastWasFilipino) {
          final fi =
              PartyCountComplements.clampKnown(party, _parse(_filipinoCtrl));
          _setText(_filipinoCtrl, fi);
          _setText(_foreignCtrl, PartyCountComplements.complement(party, fi));
        } else {
          final fo =
              PartyCountComplements.clampKnown(party, _parse(_foreignCtrl));
          _setText(_foreignCtrl, fo);
          _setText(_filipinoCtrl, PartyCountComplements.complement(party, fo));
        }
      }
    } finally {
      _syncing = false;
    }
    _emit();
    setState(() {});
  }

  void _emit() => widget.onChanged?.call(value);

  InputDecoration _box(String label) => InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
      );

  @override
  Widget build(BuildContext context) {
    final v = value;
    final err = v.validationMessage;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _partyCtrl,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: _box(widget.partyLabel).copyWith(
            helperText: widget.partyHelperText,
          ),
          onChanged: (_) => _rebalance(),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _maleCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: _box(widget.maleLabel),
                onChanged: (_) {
                  _sexLastWasMale = true;
                  _rebalance();
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _femaleCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: _box(widget.femaleLabel),
                onChanged: (_) {
                  _sexLastWasMale = false;
                  _rebalance();
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          '${widget.maleLabel} + ${widget.femaleLabel} auto-balance to party (${v.partySize})',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
        if (widget.showResidency) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _filipinoCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: _box(widget.filipinoLabel),
                  onChanged: (_) {
                    _residencyLastWasFilipino = true;
                    _rebalance();
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _foreignCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: _box(widget.foreignLabel),
                  onChanged: (_) {
                    _residencyLastWasFilipino = false;
                    _rebalance();
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${widget.filipinoLabel} + ${widget.foreignLabel} auto-balance to party (${v.partySize})',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
        ],
        if (err != null) ...[
          const SizedBox(height: 8),
          Text(
            err,
            style: TextStyle(fontSize: 12, color: Colors.red.shade700),
          ),
        ],
      ],
    );
  }
}
