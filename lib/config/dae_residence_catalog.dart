/// Country-of-residence catalog mirroring the DOT ET DAE-1B workbook
/// (`AE DAE-1B by Country (Sum)` sheet). Register rows store one of the
/// [DaeResidenceCatalog.pickerOptions] labels in `residence`.
library;

enum DaeResidenceBucket {
  /// Philippine resident (Filipino or foreign nationality) — DAE "Domestic".
  philippineResident,
  /// Non-Philippine resident — DAE "Foreign / International".
  foreign,
  /// Philippine passport holder permanently residing abroad.
  overseasFilipino,
  unspecified,
}

class DaeCountry {
  const DaeCountry(this.label, this.key, [this.aliases = const []]);

  /// Upper-case row label as printed on the DAE-1B sheet.
  final String label;

  /// Canonical register value (matches the workbook's SUMIFS key where one exists).
  final String key;

  /// Other spellings that map to this row (signup country names, etc.).
  final List<String> aliases;
}

class DaeCountryGroup {
  const DaeCountryGroup({
    required this.region,
    required this.title,
    required this.countries,
  });

  /// Top-level header (ASIA, AMERICA, EUROPE, ...).
  final String region;

  /// Sub-region header; equal to [region] when the sheet has no sub-header.
  final String title;
  final List<DaeCountry> countries;
}

abstract final class DaeResidenceCatalog {
  static const phFilipino = 'Philippines (Filipino)';
  static const phForeignNational = 'Philippines (Foreign Nationality)';
  static const overseasFilipinos = 'Overseas Filipinos';
  static const unspecified = 'Unspecified';

  static const groups = <DaeCountryGroup>[
    DaeCountryGroup(region: 'ASIA', title: 'ASEAN', countries: [
      DaeCountry('BRUNEI', 'Brunei'),
      DaeCountry('CAMBODIA', 'Cambodia'),
      DaeCountry('INDONESIA', 'Indonesia'),
      DaeCountry('LAOS', 'Laos'),
      DaeCountry('MALAYSIA', 'Malaysia'),
      DaeCountry('MYANMAR', 'Myanmar'),
      DaeCountry('SINGAPORE', 'Singapore'),
      DaeCountry('THAILAND', 'Thailand'),
      DaeCountry('VIETNAM', 'Vietnam'),
    ]),
    DaeCountryGroup(region: 'ASIA', title: 'EAST ASIA', countries: [
      DaeCountry('CHINA', 'China'),
      DaeCountry('HONGKONG', 'Hongkong', ['Hong Kong']),
      DaeCountry('JAPAN', 'Japan'),
      DaeCountry('KOREA', 'Korea (South)', ['South Korea', 'Korea']),
      DaeCountry('TAIWAN', 'Taiwan'),
    ]),
    DaeCountryGroup(region: 'ASIA', title: 'SOUTH ASIA', countries: [
      DaeCountry('BANGLADESH', 'Bangladesh'),
      DaeCountry('INDIA', 'India'),
      DaeCountry('IRAN', 'Iran'),
      DaeCountry('NEPAL', 'Nepal'),
      DaeCountry('PAKISTAN', 'Pakistan'),
      DaeCountry('SRI LANKA', 'Sri Lanka'),
    ]),
    DaeCountryGroup(region: 'ASIA', title: 'MIDDLE EAST', countries: [
      DaeCountry('BAHRAIN', 'Bahrain'),
      DaeCountry('EGYPT', 'Egypt'),
      DaeCountry('ISRAEL', 'Israel'),
      DaeCountry('JORDAN', 'Jordan'),
      DaeCountry('KUWAIT', 'Kuwait'),
      DaeCountry('SAUDI ARABIA', 'Saudi Arabia'),
      DaeCountry('UNITED ARAB EMIRATES', 'United Arab Emirates', ['UAE']),
    ]),
    DaeCountryGroup(region: 'AMERICA', title: 'NORTH AMERICA', countries: [
      DaeCountry('CANADA', 'Canada'),
      DaeCountry('MEXICO', 'Mexico'),
      DaeCountry(
        'USA',
        'U.S.A.',
        ['United States', 'USA', 'United States of America'],
      ),
    ]),
    DaeCountryGroup(region: 'AMERICA', title: 'SOUTH AMERICA', countries: [
      DaeCountry('ARGENTINA', 'Argentina'),
      DaeCountry('BRAZIL', 'Brazil'),
      DaeCountry('COLOMBIA', 'Colombia'),
      DaeCountry('PERU', 'Peru'),
      DaeCountry('VENEZUELA', 'Venezuela'),
    ]),
    DaeCountryGroup(region: 'EUROPE', title: 'WESTERN EUROPE', countries: [
      DaeCountry('AUSTRIA', 'Austria'),
      DaeCountry('BELGIUM', 'Belgium'),
      DaeCountry('FRANCE', 'France'),
      DaeCountry('GERMANY', 'Germany'),
      DaeCountry('LUXEMBOURG', 'Luxembourg'),
      DaeCountry('NETHERLANDS', 'Netherlands'),
      DaeCountry('SWITZERLAND', 'Switzerland'),
    ]),
    DaeCountryGroup(region: 'EUROPE', title: 'NORTHERN EUROPE', countries: [
      DaeCountry('DENMARK', 'Denmark'),
      DaeCountry('FINLAND', 'Finland'),
      DaeCountry('IRELAND', 'Ireland, Republic of', ['Ireland']),
      DaeCountry('NORWAY', 'Norway'),
      DaeCountry('SWEDEN', 'Sweden'),
      DaeCountry('UNITED KINGDOM', 'United Kingdom', ['UK']),
    ]),
    DaeCountryGroup(region: 'EUROPE', title: 'SOUTHERN EUROPE', countries: [
      DaeCountry('GREECE', 'Greece'),
      DaeCountry('ITALY', 'Italy'),
      DaeCountry('PORTUGAL', 'Portugal'),
      DaeCountry('SPAIN', 'Spain'),
      DaeCountry(
        'UNION OF SERBIA AND MONTENEGRO',
        'Montenegro, Rep',
        ['Montenegro', 'Serbia'],
      ),
    ]),
    DaeCountryGroup(region: 'EUROPE', title: 'EASTERN EUROPE', countries: [
      DaeCountry(
        'COMMONWEALTH OF INDEPENDENT STATES',
        'Commonwealth of I. S.',
        [
          'Armenia',
          'Azerbaijan',
          'Belarus',
          'Kazakhstan',
          'Kyrgyzstan',
          'Moldova',
          'Tajikistan',
          'Turkmenistan',
          'Uzbekistan',
        ],
      ),
      DaeCountry('POLAND', 'Poland'),
      DaeCountry('RUSSIA', 'Russian Federation', ['Russia']),
    ]),
    DaeCountryGroup(
      region: 'AUSTRALASIA/PACIFIC',
      title: 'AUSTRALASIA/PACIFIC',
      countries: [
        DaeCountry('AUSTRALIA', 'Australia'),
        DaeCountry('GUAM', 'Guam'),
        DaeCountry('NAURU', 'Nauru'),
        DaeCountry('NEW ZEALAND', 'New Zealand'),
        DaeCountry('PAPUA NEW GUINEA', 'Papua New Guinea'),
      ],
    ),
    DaeCountryGroup(region: 'AFRICA', title: 'AFRICA', countries: [
      DaeCountry('NIGERIA', 'Nigeria'),
      DaeCountry('SOUTH AFRICA', 'South Africa'),
    ]),
  ];

  /// Foreign countries without their own DAE-1B row
  /// (reported under "Others and unspecified foreign residences").
  static const otherForeignCountries = <String>[
    'Afghanistan', 'Albania', 'Algeria', 'Andorra', 'Angola',
    'Antigua and Barbuda', 'Bahamas', 'Barbados', 'Belize', 'Benin',
    'Bhutan', 'Bolivia', 'Bosnia and Herzegovina', 'Botswana', 'Bulgaria',
    'Burkina Faso', 'Burundi', 'Cameroon', 'Cape Verde',
    'Central African Republic', 'Chad', 'Chile', 'Congo', 'Costa Rica',
    "Cote D'Ivoire", 'Croatia', 'Cuba', 'Cyprus', 'Czech Republic',
    'Djibouti', 'Dominica', 'Dominican Republic', 'Ecuador', 'El Salvador',
    'Equatorial Guinea', 'Eritrea', 'Estonia', 'Ethiopia', 'Fiji', 'Gabon',
    'Gambia', 'Georgia', 'Ghana', 'Grenada', 'Guatemala', 'Guinea',
    'Guinea-Bissau', 'Guyana', 'Haiti', 'Honduras', 'Hungary', 'Iceland',
    'Iraq', 'Jamaica', 'Kenya', 'Kiribati', 'Latvia', 'Lebanon', 'Lesotho',
    'Liberia', 'Libya', 'Liechtenstein', 'Lithuania', 'Macau', 'Madagascar',
    'Malawi', 'Maldives', 'Mali', 'Malta', 'Marshall Islands', 'Mauritania',
    'Mauritius', 'Micronesia', 'Monaco', 'Mongolia', 'Morocco', 'Mozambique',
    'Namibia', 'Nicaragua', 'Niger', 'North Korea', 'North Macedonia', 'Oman',
    'Palau', 'Palestine', 'Panama', 'Paraguay', 'Puerto Rico', 'Qatar',
    'Romania', 'Rwanda', 'Saint Kitts and Nevis', 'Saint Lucia',
    'Saint Vincent', 'Samoa', 'San Marino', 'Senegal', 'Seychelles',
    'Sierra Leone', 'Slovakia', 'Slovenia', 'Solomon Islands', 'Somalia',
    'South Sudan', 'Sudan', 'Suriname', 'Syria', 'Tanzania', 'Timor-Leste',
    'Togo', 'Tonga', 'Trinidad and Tobago', 'Tunisia', 'Turkey', 'Tuvalu',
    'Uganda', 'Ukraine', 'Uruguay', 'Vanuatu', 'Vatican City', 'Yemen',
    'Zambia', 'Zimbabwe',
  ];

  /// Philippine regions for optional domestic origin (DAE 1B.2 / 3B.2 Domestic).
  static const philippineRegions = <String>[
    'NCR',
    'CAR',
    'Region I - Ilocos',
    'Region II - Cagayan Valley',
    'Region III - Central Luzon',
    'Region IV-A - CALABARZON',
    'MIMAROPA',
    'Region V - Bicol',
    'Region VI - Western Visayas',
    'NIR - Negros Island',
    'Region VII - Central Visayas',
    'Region VIII - Eastern Visayas',
    'Region IX - Zamboanga Peninsula',
    'Region X - Northern Mindanao',
    'Region XI - Davao',
    'Region XII - SOCCSKSARGEN',
    'Region XIII - Caraga',
    'BARMM',
  ];

  static final Map<String, DaeCountry> _byNorm = () {
    final map = <String, DaeCountry>{};
    for (final g in groups) {
      for (final c in g.countries) {
        map[_norm(c.key)] = c;
        map[_norm(c.label)] = c;
        for (final a in c.aliases) {
          map[_norm(a)] = c;
        }
      }
    }
    return map;
  }();

  static String _norm(String s) =>
      s.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  /// Dropdown values for the register "Residence" column.
  static List<String> get pickerOptions {
    final listed = <String>[
      for (final g in groups)
        for (final c in g.countries) c.key,
    ];
    final foreign = [...listed, ...otherForeignCountries]
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return [
      phFilipino,
      phForeignNational,
      overseasFilipinos,
      ...foreign,
      unspecified,
    ];
  }

  static DaeResidenceBucket bucketFor(String? residence) {
    final r = (residence ?? '').trim();
    if (r.isEmpty || r == unspecified) return DaeResidenceBucket.unspecified;
    if (r == phFilipino || r == phForeignNational) {
      return DaeResidenceBucket.philippineResident;
    }
    final n = _norm(r);
    if (n == 'philippines' || n == 'filipino' || n == 'local') {
      return DaeResidenceBucket.philippineResident;
    }
    if (r == overseasFilipinos) return DaeResidenceBucket.overseasFilipino;
    return DaeResidenceBucket.foreign;
  }

  /// DAE-1B country row for a foreign residence; null = "Others" row.
  static DaeCountry? countryFor(String? residence) {
    final r = (residence ?? '').trim();
    if (r.isEmpty) return null;
    return _byNorm[_norm(r)];
  }

  static bool isFilipinoNational(String? residence) =>
      (residence ?? '').trim() == phFilipino ||
      (residence ?? '').trim() == overseasFilipinos;
}
