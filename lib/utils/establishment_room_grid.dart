import 'package:atmos_trs_system/services/establishment_stay_service.dart';

/// Visual / ops state for a fixed Room 1…N slot.
enum EstablishmentRoomStatus {
  free,
  occupied,
  disabled,
}

/// Catalog details for a room slot (editable in Rooms tab).
class EstablishmentRoomInfo {
  const EstablishmentRoomInfo({
    this.type = '',
    this.capacityMin = 0,
    this.capacityMax = 0,
    this.pricePerNight = 0,
    this.inclusions = const [],
    this.notes = '',
  });

  final String type;
  final int capacityMin;
  final int capacityMax;
  final double pricePerNight;
  final List<String> inclusions;
  final String notes;

  static const empty = EstablishmentRoomInfo();

  bool get hasDetails =>
      type.trim().isNotEmpty ||
      capacityMin > 0 ||
      capacityMax > 0 ||
      pricePerNight > 0 ||
      inclusions.isNotEmpty ||
      notes.trim().isNotEmpty;

  String get capacityLabel {
    if (capacityMin <= 0 && capacityMax <= 0) return 'Not set';
    if (capacityMin > 0 && capacityMax > 0) {
      if (capacityMin == capacityMax) return 'Good for $capacityMin';
      return 'Good for $capacityMin–$capacityMax';
    }
    if (capacityMin > 0) return 'Good for $capacityMin+';
    return 'Good for up to $capacityMax';
  }

  String get priceLabel {
    if (pricePerNight <= 0) return 'Price not set';
    final whole = pricePerNight == pricePerNight.roundToDouble();
    final n = whole
        ? pricePerNight.toStringAsFixed(0)
        : pricePerNight.toStringAsFixed(2);
    return '₱$n / night';
  }

  Map<String, dynamic> toMap() => {
        'type': type.trim(),
        'capacityMin': capacityMin < 0 ? 0 : capacityMin,
        'capacityMax': capacityMax < 0 ? 0 : capacityMax,
        'pricePerNight': pricePerNight < 0 ? 0 : pricePerNight,
        'inclusions': inclusions
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList(),
        'notes': notes.trim(),
      };

  factory EstablishmentRoomInfo.fromMap(dynamic raw) {
    if (raw is! Map) return empty;
    final m = Map<String, dynamic>.from(raw);
    final incl = m['inclusions'];
    return EstablishmentRoomInfo(
      type: (m['type'] ?? '').toString(),
      capacityMin: _asInt(m['capacityMin']),
      capacityMax: _asInt(m['capacityMax']),
      pricePerNight: _asDouble(m['pricePerNight']),
      inclusions: incl is List
          ? incl.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList()
          : const [],
      notes: (m['notes'] ?? '').toString(),
    );
  }

  EstablishmentRoomInfo copyWith({
    String? type,
    int? capacityMin,
    int? capacityMax,
    double? pricePerNight,
    List<String>? inclusions,
    String? notes,
  }) {
    return EstablishmentRoomInfo(
      type: type ?? this.type,
      capacityMin: capacityMin ?? this.capacityMin,
      capacityMax: capacityMax ?? this.capacityMax,
      pricePerNight: pricePerNight ?? this.pricePerNight,
      inclusions: inclusions ?? this.inclusions,
      notes: notes ?? this.notes,
    );
  }

  static int _asInt(dynamic v) {
    if (v is int) return v;
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  static double _asDouble(dynamic v) {
    if (v is double) return v;
    if (v is int) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0;
  }
}

/// Desk preference filters for matching free rooms.
class EstablishmentRoomPreferences {
  const EstablishmentRoomPreferences({
    this.type = '',
    this.capacityMin = 0,
    this.capacityMax = 0,
    this.maxPricePerNight = 0,
    this.requiredInclusions = const [],
  });

  final String type;
  final int capacityMin;
  final int capacityMax;
  final double maxPricePerNight;
  final List<String> requiredInclusions;

  bool get isEmpty =>
      type.trim().isEmpty &&
      capacityMin <= 0 &&
      capacityMax <= 0 &&
      maxPricePerNight <= 0 &&
      requiredInclusions.isEmpty;
}

/// One slot in the lodging room grid.
class EstablishmentRoomSlot {
  const EstablishmentRoomSlot({
    required this.id,
    required this.status,
    this.stay,
    this.info = EstablishmentRoomInfo.empty,
  });

  /// Slot id as `"1"` … `"N"`.
  final String id;

  final EstablishmentRoomStatus status;
  final EstablishmentStayRequest? stay;
  final EstablishmentRoomInfo info;

  int get number => int.tryParse(id) ?? 0;

  String get label => 'Room $id';

  bool get isFree => status == EstablishmentRoomStatus.free;
  bool get isOccupied => status == EstablishmentRoomStatus.occupied;
  bool get isDisabled => status == EstablishmentRoomStatus.disabled;
}

/// Aggregated counts for dashboard KPIs.
class EstablishmentRoomStats {
  const EstablishmentRoomStats({
    required this.total,
    required this.occupied,
    required this.free,
    required this.disabled,
  });

  final int total;
  final int occupied;
  final int free;
  final int disabled;

  static const zero = EstablishmentRoomStats(
    total: 0,
    occupied: 0,
    free: 0,
    disabled: 0,
  );
}

/// Common room types / inclusions for desk + Rooms edit UI.
abstract final class EstablishmentRoomCatalog {
  static const roomTypes = <String>[
    'Standard',
    'Deluxe',
    'Suite',
    'Family',
    'Twin',
    'Single',
    'Dorm',
    'Other',
  ];

  static const inclusions = <String>[
    'Kitchen',
    'Fridge',
    'Air conditioning',
    'WiFi',
    'TV',
    'Private bathroom',
    'Balcony',
    'Breakfast',
    'Hot water',
  ];

  /// Preset capacity ranges for preference chips.
  static const capacityPresets = <(int, int, String)>[
    (1, 1, '1'),
    (1, 2, '1–2'),
    (2, 3, '2–3'),
    (2, 4, '2–4'),
    (3, 4, '3–4'),
    (4, 6, '4–6'),
    (6, 8, '6–8'),
  ];
}

/// Helpers for Room 1…N grid derivation from stays + disabled list.
abstract final class EstablishmentRoomGrid {
  static String slotId(int n) => '$n';

  static List<String> parseDisabledRooms(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  /// `roomInventory` map keyed by slot id.
  static Map<String, EstablishmentRoomInfo> parseInventory(dynamic raw) {
    if (raw is! Map) return const {};
    final out = <String, EstablishmentRoomInfo>{};
    raw.forEach((key, value) {
      final id = key.toString().trim();
      if (id.isEmpty) return;
      out[id] = EstablishmentRoomInfo.fromMap(value);
    });
    return out;
  }

  static Map<String, dynamic> inventoryToFirestore(
    Map<String, EstablishmentRoomInfo> inventory,
  ) {
    return {
      for (final e in inventory.entries) e.key: e.value.toMap(),
    };
  }

  /// Effective checkout for in-house check.
  static DateTime? effectiveCheckOut(EstablishmentStayRequest stay) {
    if (stay.checkOutAt != null) return stay.checkOutAt;
    final nights = stay.nightsStayed ?? 0;
    final checkIn = stay.checkInAt ?? stay.confirmedAt;
    if (checkIn == null || nights < 1) return null;
    return checkIn.add(Duration(days: nights));
  }

  /// Confirmed stay still in-house (checkout end of day still ahead or today).
  static bool isInHouse(
    EstablishmentStayRequest stay, {
    DateTime? now,
  }) {
    if (!stay.isConfirmed) return false;
    final clock = now ?? DateTime.now();
    final today = DateTime(clock.year, clock.month, clock.day);
    final checkout = effectiveCheckOut(stay);
    if (checkout == null) {
      final day = stay.checkInAt ?? stay.confirmedAt;
      if (day == null) return true;
      final d = DateTime(day.year, day.month, day.day);
      return !d.isAfter(today);
    }
    final outDay = DateTime(checkout.year, checkout.month, checkout.day);
    return !outDay.isBefore(today);
  }

  /// Whole days until checkout (0 = today). Null if unknown / free.
  static int? daysUntilCheckout(
    EstablishmentStayRequest? stay, {
    DateTime? now,
  }) {
    if (stay == null) return null;
    final checkout = effectiveCheckOut(stay);
    if (checkout == null) return null;
    final clock = now ?? DateTime.now();
    final today = DateTime(clock.year, clock.month, clock.day);
    final outDay = DateTime(checkout.year, checkout.month, checkout.day);
    return outDay.difference(today).inDays;
  }

  static String? normalizeSlotId(String raw, int roomCount) {
    final t = raw.trim();
    if (t.isEmpty || roomCount < 1) return null;
    final n = int.tryParse(t);
    if (n == null || n < 1 || n > roomCount) return null;
    return slotId(n);
  }

  static List<EstablishmentRoomSlot> buildSlots({
    required int roomCount,
    required List<String> disabledRooms,
    required List<EstablishmentStayRequest> stays,
    Map<String, EstablishmentRoomInfo> inventory = const {},
    DateTime? now,
  }) {
    if (roomCount < 1) return const [];

    final disabled = <String>{};
    for (final d in disabledRooms) {
      final id = normalizeSlotId(d, roomCount);
      if (id != null) disabled.add(id);
    }

    final occupancy = <String, EstablishmentStayRequest>{};
    for (final stay in stays) {
      if (!isInHouse(stay, now: now)) continue;
      for (final raw in stay.roomNumbers) {
        final id = normalizeSlotId(raw, roomCount);
        if (id == null) continue;
        if (disabled.contains(id)) continue;
        occupancy.putIfAbsent(id, () => stay);
      }
    }

    return [
      for (var i = 1; i <= roomCount; i++)
        () {
          final id = slotId(i);
          final info = inventory[id] ?? EstablishmentRoomInfo.empty;
          if (disabled.contains(id)) {
            return EstablishmentRoomSlot(
              id: id,
              status: EstablishmentRoomStatus.disabled,
              info: info,
            );
          }
          final stay = occupancy[id];
          if (stay != null) {
            return EstablishmentRoomSlot(
              id: id,
              status: EstablishmentRoomStatus.occupied,
              stay: stay,
              info: info,
            );
          }
          return EstablishmentRoomSlot(
            id: id,
            status: EstablishmentRoomStatus.free,
            info: info,
          );
        }(),
    ];
  }

  static EstablishmentRoomStats statsFor(List<EstablishmentRoomSlot> slots) {
    var occupied = 0;
    var free = 0;
    var disabled = 0;
    for (final s in slots) {
      switch (s.status) {
        case EstablishmentRoomStatus.occupied:
          occupied++;
        case EstablishmentRoomStatus.free:
          free++;
        case EstablishmentRoomStatus.disabled:
          disabled++;
      }
    }
    return EstablishmentRoomStats(
      total: slots.length,
      occupied: occupied,
      free: free,
      disabled: disabled,
    );
  }

  static List<String> availableSlotIds(List<EstablishmentRoomSlot> slots) {
    return [
      for (final s in slots)
        if (s.isFree) s.id,
    ];
  }

  static List<EstablishmentRoomSlot> freeSlots(
    List<EstablishmentRoomSlot> slots,
  ) {
    return [for (final s in slots) if (s.isFree) s];
  }

  /// Match free rooms against desk preferences (rooms with no catalog still pass
  /// empty-preference filters; typed filters skip rooms missing that field).
  static bool matchesPreferences(
    EstablishmentRoomSlot slot,
    EstablishmentRoomPreferences prefs,
  ) {
    if (!slot.isFree) return false;
    if (prefs.isEmpty) return true;
    final info = slot.info;

    final type = prefs.type.trim().toLowerCase();
    if (type.isNotEmpty) {
      if (info.type.trim().toLowerCase() != type) return false;
    }

    if (prefs.capacityMin > 0 || prefs.capacityMax > 0) {
      // Room must cover the requested party range (room capacity overlaps).
      final rMin = info.capacityMin > 0 ? info.capacityMin : 1;
      final rMax = info.capacityMax > 0
          ? info.capacityMax
          : (info.capacityMin > 0 ? info.capacityMin : 99);
      final pMin = prefs.capacityMin > 0 ? prefs.capacityMin : 1;
      final pMax = prefs.capacityMax > 0 ? prefs.capacityMax : pMin;
      // Overlap: room can sleep someone in the preferred range.
      if (rMax < pMin || rMin > pMax) return false;
    }

    if (prefs.maxPricePerNight > 0) {
      if (info.pricePerNight <= 0) return false;
      if (info.pricePerNight > prefs.maxPricePerNight) return false;
    }

    for (final req in prefs.requiredInclusions) {
      final needle = req.trim().toLowerCase();
      if (needle.isEmpty) continue;
      final has = info.inclusions.any((e) => e.trim().toLowerCase() == needle);
      if (!has) return false;
    }
    return true;
  }

  static List<EstablishmentRoomSlot> filterByPreferences(
    List<EstablishmentRoomSlot> slots,
    EstablishmentRoomPreferences prefs,
  ) {
    return [
      for (final s in slots)
        if (matchesPreferences(s, prefs)) s,
    ];
  }

  static List<String> pruneDisabled(List<String> disabled, int newCount) {
    return [
      for (final d in disabled)
        if ((int.tryParse(d.trim()) ?? 0) >= 1 &&
            (int.tryParse(d.trim()) ?? 0) <= newCount)
          slotId(int.parse(d.trim())),
    ];
  }

  static Map<String, EstablishmentRoomInfo> pruneInventory(
    Map<String, EstablishmentRoomInfo> inventory,
    int newCount,
  ) {
    return {
      for (final e in inventory.entries)
        if ((int.tryParse(e.key) ?? 0) >= 1 &&
            (int.tryParse(e.key) ?? 0) <= newCount)
          e.key: e.value,
    };
  }

  static int maxReferencedSlot({
    required int roomCount,
    required List<String> disabledRooms,
    required List<EstablishmentStayRequest> stays,
    DateTime? now,
  }) {
    var max = 0;
    for (final d in disabledRooms) {
      final n = int.tryParse(d.trim()) ?? 0;
      if (n > max) max = n;
    }
    for (final stay in stays) {
      if (!isInHouse(stay, now: now)) continue;
      for (final raw in stay.roomNumbers) {
        final n = int.tryParse(raw.trim()) ?? 0;
        if (n > max) max = n;
      }
    }
    return max;
  }
}
