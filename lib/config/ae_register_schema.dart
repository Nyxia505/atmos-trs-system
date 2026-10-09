import 'package:atmos_trs_system/utils/establishment_capability.dart';

/// Columns of the establishment register (DAE-1B DailyRecord sheet).
enum AeRegisterColumn {
  date,
  room,
  residence,
  phRegion,
  guests,
  female,
  male,
  checkedInDay,
  rate,
  chargesA,
  chargesB,
}

/// DOT accommodation type → classification code (DAE-1B `AEType` sheet).
abstract final class AeTypeCatalog {
  static const types = <String, String>{
    'Hotel': 'HTL',
    'Condotel': 'CON',
    'Serviced Residence': 'SER',
    'Resort': 'RES',
    'Apartelle': 'APA',
    'Motel': 'MOT',
    'Pension House': 'PEN',
    'Home Stay Site': 'HSS',
    'Tourist Inn': 'TIN',
    'Others': 'OTH',
  };

  static String codeFor(String? type) {
    final t = (type ?? '').trim().toLowerCase();
    for (final e in types.entries) {
      if (e.key.toLowerCase() == t) return e.value;
    }
    return t.isEmpty ? '' : 'OTH';
  }

  /// Best-effort DOT type from the signup category.
  static String typeForCategory(String? category) {
    final c = (category ?? '').trim().toLowerCase();
    for (final k in types.keys) {
      if (k.toLowerCase() == c) return k;
    }
    if (c == 'glamping' || c == 'camping') return 'Others';
    return c.isEmpty ? '' : 'Others';
  }
}

/// Per-establishment-type register layout. Add columns/labels here as the
/// client extends the forms for dining and venue packs.
class AeRegisterSchema {
  const AeRegisterSchema({
    required this.pack,
    required this.columns,
    required this.rowNoun,
    required this.guestsLabel,
    required this.rateLabel,
    required this.tracksRooms,
    required this.tracksNights,
  });

  final EstablishmentPack pack;
  final List<AeRegisterColumn> columns;

  /// What one register row represents (shown in hints).
  final String rowNoun;
  final String guestsLabel;
  final String rateLabel;

  /// Room No. column + occupancy KPIs.
  final bool tracksRooms;

  /// Guest-nights / ALOS / check-in day flag.
  final bool tracksNights;

  bool has(AeRegisterColumn c) => columns.contains(c);

  static AeRegisterSchema forCategory(String? category) =>
      forPack(EstablishmentCapability.packFor(category));

  static AeRegisterSchema forPack(EstablishmentPack pack) {
    switch (pack) {
      case EstablishmentPack.lodging:
        return const AeRegisterSchema(
          pack: EstablishmentPack.lodging,
          columns: [
            AeRegisterColumn.date,
            AeRegisterColumn.room,
            AeRegisterColumn.residence,
            AeRegisterColumn.phRegion,
            AeRegisterColumn.guests,
            AeRegisterColumn.female,
            AeRegisterColumn.male,
            AeRegisterColumn.checkedInDay,
            AeRegisterColumn.rate,
            AeRegisterColumn.chargesA,
            AeRegisterColumn.chargesB,
          ],
          rowNoun: 'one occupied room for one night',
          guestsLabel: 'No. of guests',
          rateLabel: 'Daily rate',
          tracksRooms: true,
          tracksNights: true,
        );
      case EstablishmentPack.dining:
        return const AeRegisterSchema(
          pack: EstablishmentPack.dining,
          columns: [
            AeRegisterColumn.date,
            AeRegisterColumn.residence,
            AeRegisterColumn.phRegion,
            AeRegisterColumn.guests,
            AeRegisterColumn.female,
            AeRegisterColumn.male,
            AeRegisterColumn.rate,
          ],
          rowNoun: 'one guest party',
          guestsLabel: 'No. of guests',
          rateLabel: 'Bill amount',
          tracksRooms: false,
          tracksNights: false,
        );
      case EstablishmentPack.venue:
        return const AeRegisterSchema(
          pack: EstablishmentPack.venue,
          columns: [
            AeRegisterColumn.date,
            AeRegisterColumn.residence,
            AeRegisterColumn.phRegion,
            AeRegisterColumn.guests,
            AeRegisterColumn.female,
            AeRegisterColumn.male,
            AeRegisterColumn.rate,
          ],
          rowNoun: 'one visitor group',
          guestsLabel: 'No. of visitors',
          rateLabel: 'Fees collected',
          tracksRooms: false,
          tracksNights: false,
        );
    }
  }

  static String columnLabel(AeRegisterColumn c, AeRegisterSchema s) {
    switch (c) {
      case AeRegisterColumn.date:
        return 'Date';
      case AeRegisterColumn.room:
        return 'Room';
      case AeRegisterColumn.residence:
        return 'Residence / Nationality';
      case AeRegisterColumn.phRegion:
        return 'PH origin';
      case AeRegisterColumn.guests:
        return s.guestsLabel;
      case AeRegisterColumn.female:
        return 'Female';
      case AeRegisterColumn.male:
        return 'Male';
      case AeRegisterColumn.checkedInDay:
        return 'Checked-in day';
      case AeRegisterColumn.rate:
        return s.rateLabel;
      case AeRegisterColumn.chargesA:
        return 'Charges (A)';
      case AeRegisterColumn.chargesB:
        return 'Charges (B)';
    }
  }
}
