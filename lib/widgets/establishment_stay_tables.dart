import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:atmos_trs_system/services/establishment_stay_service.dart';
import 'package:atmos_trs_system/utils/establishment_room_grid.dart';
import 'package:atmos_trs_system/widgets/establishment_dash_tokens.dart';
import 'package:atmos_trs_system/widgets/establishment_dashboard_components.dart';

typedef StayAction = void Function(EstablishmentStayRequest stay);

enum StayRequestFilter { all, pending, confirmed, checkedOut, rejected }

String _two(int v) => v.toString().padLeft(2, '0');

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String formatStayDateTime(DateTime? d) {
  if (d == null) return '—';
  final h12 = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final ampm = d.hour < 12 ? 'AM' : 'PM';
  return '${_months[d.month - 1]} ${d.day}, ${d.year}\n$h12:${_two(d.minute)} $ampm';
}

String _guestName(EstablishmentStayRequest s) =>
    s.touristName.trim().isNotEmpty ? s.touristName.trim() : 'Tourist';

String _nationality(EstablishmentStayRequest s) {
  for (final v in [
    s.touristNationality,
    s.touristCountry,
    s.touristLocalOrForeign,
  ]) {
    if (v.trim().isNotEmpty) return v.trim();
  }
  return '—';
}

String _count(int v, {required bool pending}) =>
    pending && v == 0 ? '—' : '$v';

String _optCount(int? v) => v == null ? '—' : '$v';

({String label, Color color}) stayStatusStyle(EstablishmentStayRequest s) {
  if (s.isPending) return (label: 'Pending', color: AeDashTokens.warning);
  if (s.isRejected) return (label: 'Rejected', color: AeDashTokens.danger);
  if (s.isCheckedOut) return (label: 'Checked out', color: AeDashTokens.slate);
  if (EstablishmentRoomGrid.isInHouse(s)) {
    return (label: 'In house', color: AeDashTokens.blue);
  }
  return (label: 'Confirmed', color: AeDashTokens.success);
}

class _StatusChip extends StatelessWidget {
  const _StatusChip(this.stay);
  final EstablishmentStayRequest stay;

  @override
  Widget build(BuildContext context) {
    final st = stayStatusStyle(stay);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: st.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        st.label,
        style: AeDashTokens.body(
          size: 11,
          color: st.color,
          weight: FontWeight.w700,
        ),
      ),
    );
  }
}

class GuestInitialsAvatar extends StatelessWidget {
  const GuestInitialsAvatar({
    super.key,
    required this.name,
    required this.color,
    this.size = 38,
  });

  final String name;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    final initials = parts.isEmpty
        ? 'T'
        : (parts.first[0] + (parts.length > 1 ? parts.last[0] : ''))
            .toUpperCase();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        shape: BoxShape.circle,
      ),
      child: Text(
        initials,
        style: AeDashTokens.body(
          size: size * 0.34,
          color: color,
          weight: FontWeight.w800,
        ),
      ),
    );
  }
}

/// Stay requests card with status filter and a horizontally scrollable table.
class EstablishmentStayRequestTable extends StatefulWidget {
  const EstablishmentStayRequestTable({
    super.key,
    required this.title,
    required this.description,
    required this.emptyTitle,
    required this.stays,
    required this.onConfirm,
    required this.onReject,
    required this.onCheckOut,
    this.emptyHint = 'Print your QR and ask a tourist to scan it.',
  });

  final String title;
  final String description;
  final String emptyTitle;
  final String emptyHint;
  final List<EstablishmentStayRequest> stays;
  final StayAction onConfirm;
  final StayAction onReject;
  final StayAction onCheckOut;

  @override
  State<EstablishmentStayRequestTable> createState() =>
      _EstablishmentStayRequestTableState();
}

class _EstablishmentStayRequestTableState
    extends State<EstablishmentStayRequestTable> {
  static const _pageSize = 10;
  static const _minTableWidth = 940.0;
  static const _flex = [4, 14, 16, 12, 6, 6, 6, 6, 11, 19];
  static const _headers = [
    '#',
    'Date & Time',
    'Guest Name',
    'Nationality',
    'Male',
    'Female',
    'Nights',
    'Rooms',
    'Status',
    'Action',
  ];

  StayRequestFilter _filter = StayRequestFilter.all;
  int _visible = _pageSize;

  List<EstablishmentStayRequest> get _rows {
    final list = widget.stays.where((s) {
      switch (_filter) {
        case StayRequestFilter.all:
          return true;
        case StayRequestFilter.pending:
          return s.isPending;
        case StayRequestFilter.confirmed:
          return s.isConfirmed;
        case StayRequestFilter.checkedOut:
          return s.isCheckedOut;
        case StayRequestFilter.rejected:
          return s.isRejected;
      }
    }).toList();
    list.sort((a, b) {
      if (a.isPending != b.isPending) return a.isPending ? -1 : 1;
      final da = a.createdAt ?? DateTime(1970);
      final db = b.createdAt ?? DateTime(1970);
      return db.compareTo(da);
    });
    return list;
  }

  String get _emptyTitle => switch (_filter) {
        StayRequestFilter.all || StayRequestFilter.pending => widget.emptyTitle,
        StayRequestFilter.confirmed => 'No confirmed requests.',
        StayRequestFilter.checkedOut => 'No checked-out requests.',
        StayRequestFilter.rejected => 'No rejected requests.',
      };

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    final shown = rows.take(_visible).toList();

    return AePanelCard(
      title: widget.title,
      subtitle: widget.description,
      icon: Icons.notifications_rounded,
      trailing: AeDropdownAction<StayRequestFilter>(
        value: _filter,
        leading: Icons.filter_list_rounded,
        options: const {
          StayRequestFilter.all: 'All requests',
          StayRequestFilter.pending: 'Pending',
          StayRequestFilter.confirmed: 'Confirmed',
          StayRequestFilter.checkedOut: 'Checked out',
          StayRequestFilter.rejected: 'Rejected',
        },
        onChanged: (f) => setState(() {
          _filter = f;
          _visible = _pageSize;
        }),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, c) {
              final width = math.max(c.maxWidth, _minTableWidth);
              final table = SizedBox(
                width: width,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _headerRow(),
                    if (shown.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 22),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: SizedBox(
                            width: c.maxWidth,
                            child: AeIllustratedEmpty(
                              title: _emptyTitle,
                              message: widget.emptyHint,
                            ),
                          ),
                        ),
                      )
                    else
                      for (var i = 0; i < shown.length; i++)
                        _dataRow(i + 1, shown[i], last: i == shown.length - 1),
                  ],
                ),
              );
              if (width <= c.maxWidth) return table;
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: table,
              );
            },
          ),
          if (rows.length > shown.length)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Center(
                child: TextButton(
                  onPressed: () =>
                      setState(() => _visible += _pageSize),
                  style: TextButton.styleFrom(
                    foregroundColor: AeDashTokens.accent,
                  ),
                  child: Text(
                    'Show more (${rows.length - shown.length} left)',
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _cell(int col, Widget child, {Alignment align = Alignment.centerLeft}) {
    return Expanded(
      flex: _flex[col],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Align(alignment: align, child: child),
      ),
    );
  }

  Widget _headerRow() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 11),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          for (var i = 0; i < _headers.length; i++)
            _cell(
              i,
              Text(
                _headers[i],
                style: AeDashTokens.body(
                  size: 11.5,
                  color: AeDashTokens.text,
                  weight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _dataRow(int n, EstablishmentStayRequest s, {required bool last}) {
    final text = AeDashTokens.body(size: 12.5, color: AeDashTokens.text);
    final pending = s.isPending;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        border: last
            ? null
            : const Border(bottom: BorderSide(color: AeDashTokens.softBorder)),
      ),
      child: Row(
        children: [
          _cell(0, Text('$n', style: text)),
          _cell(
            1,
            Text(
              formatStayDateTime(s.createdAt),
              style: AeDashTokens.body(size: 11.5),
            ),
          ),
          _cell(
            2,
            Row(
              children: [
                GuestInitialsAvatar(
                  name: _guestName(s),
                  color: stayStatusStyle(s).color,
                  size: 30,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _guestName(s),
                    style: AeDashTokens.body(
                      size: 12.5,
                      color: AeDashTokens.text,
                      weight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          _cell(
            3,
            Text(
              _nationality(s),
              style: text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          _cell(4, Text(_count(s.maleCount, pending: pending), style: text)),
          _cell(5, Text(_count(s.femaleCount, pending: pending), style: text)),
          _cell(6, Text(_optCount(s.nightsStayed), style: text)),
          _cell(7, Text(_optCount(s.roomsOccupied), style: text)),
          _cell(8, _StatusChip(s)),
          _cell(9, _actions(s)),
        ],
      ),
    );
  }

  Widget _actions(EstablishmentStayRequest s) {
    if (s.isPending) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FilledButton(
            onPressed: () => widget.onConfirm(s),
            style: FilledButton.styleFrom(
              backgroundColor: AeDashTokens.accent,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              minimumSize: const Size(0, 34),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              textStyle: AeDashTokens.body(size: 12, weight: FontWeight.w700),
            ),
            child: const Text('Confirm'),
          ),
          const SizedBox(width: 6),
          OutlinedButton(
            onPressed: () => widget.onReject(s),
            style: OutlinedButton.styleFrom(
              foregroundColor: AeDashTokens.danger,
              side: const BorderSide(color: Color(0xFFFECACA)),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              minimumSize: const Size(0, 34),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              textStyle: AeDashTokens.body(size: 12, weight: FontWeight.w700),
            ),
            child: const Text('Reject'),
          ),
        ],
      );
    }
    if (EstablishmentRoomGrid.isInHouse(s)) {
      return TextButton.icon(
        onPressed: () => widget.onCheckOut(s),
        icon: const Icon(Icons.logout_rounded, size: 15),
        label: const Text('Check out'),
        style: TextButton.styleFrom(
          foregroundColor: AeDashTokens.accent,
          textStyle: AeDashTokens.body(size: 12, weight: FontWeight.w700),
        ),
      );
    }
    return Text('—', style: AeDashTokens.body(size: 12.5));
  }
}
