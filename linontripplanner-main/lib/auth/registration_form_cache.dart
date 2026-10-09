import 'package:flutter/material.dart';

/// Pre-built dropdown lists so registration opens without UI jank.
abstract class RegistrationFormCache {
  static bool _warmed = false;

  static late final List<DropdownMenuItem<int>> monthItems = _buildMonthItems();
  static late final List<DropdownMenuItem<int>> dayItems = _buildDayItems();
  static late final List<DropdownMenuItem<int>> yearItems = _buildYearItems();

  static final List<DropdownMenuItem<String>> sexItems =
      _buildStringItems(RegistrationFormLists.sexes);
  static final List<DropdownMenuItem<String>> civilItems =
      _buildStringItems(RegistrationFormLists.civilStatuses);
  static final List<DropdownMenuItem<String>> nationItems =
      _buildStringItems(RegistrationFormLists.nations);
  static final List<DropdownMenuItem<String>> transportItems =
      _buildStringItems(RegistrationFormLists.transportOpts);
  static final List<DropdownMenuItem<String>> visitorItems =
      _buildStringItems(RegistrationFormLists.visitorKinds);
  static final List<DropdownMenuItem<String>> suffixItems =
      _buildStringItems(
    RegistrationFormLists.suffixes.where((s) => s.isNotEmpty),
  );

  static void warmUp() {
    if (_warmed) return;
    _warmed = true;
    // Touch lazy lists so first navigation does not pay build cost on tap.
    monthItems.length;
    dayItems.length;
    yearItems.length;
    sexItems.length;
  }

  static List<DropdownMenuItem<int>> _buildMonthItems() {
    const names = [
      '',
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return List.generate(12, (i) {
      final m = i + 1;
      return DropdownMenuItem<int>(
        value: m,
        child: Text(names[m], overflow: TextOverflow.ellipsis),
      );
    });
  }

  static List<DropdownMenuItem<int>> _buildDayItems() {
    return List.generate(
      31,
      (i) => DropdownMenuItem<int>(
        value: i + 1,
        child: Text('${i + 1}'),
      ),
    );
  }

  static List<DropdownMenuItem<int>> _buildYearItems() {
    final y0 = DateTime.now().year - 13;
    return List.generate(
      90,
      (i) {
        final y = y0 - i;
        return DropdownMenuItem<int>(value: y, child: Text('$y'));
      },
    );
  }

  static List<DropdownMenuItem<String>> _buildStringItems(
    Iterable<String> values,
  ) {
    return values
        .map(
          (s) => DropdownMenuItem<String>(
            value: s,
            child: Text(s, overflow: TextOverflow.ellipsis),
          ),
        )
        .toList();
  }
}

/// Shared option lists for registration dropdowns.
abstract class RegistrationFormLists {
  static const sexes = [
    'Male',
    'Female',
    'Other',
    'Prefer not to say',
  ];
  static const civilStatuses = [
    'Single',
    'Married',
    'Widowed',
    'Separated',
    'Divorced',
  ];
  static const nations = [
    'Filipino',
    'United States',
    'Canada',
    'Australia',
    'Japan',
    'South Korea',
    'China',
    'United Kingdom',
    'Other',
  ];
  static const transportOpts = [
    'Air',
    'Sea',
    'Land — private vehicle',
    'Land — public transport',
    'Other',
  ];
  static const visitorKinds = ['Local', 'Foreign'];
  static const suffixes = ['', 'Jr.', 'Sr.', 'II', 'III', 'IV'];
}
