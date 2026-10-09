import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:atmos_trs_system/config/ae_register_schema.dart';
import 'package:atmos_trs_system/widgets/establishment_dash_tokens.dart';
import 'package:atmos_trs_system/widgets/establishment_dashboard_components.dart';
import 'package:atmos_trs_system/widgets/establishment_location_capture.dart';

/// Cards for the establishment "Profile" tab.

/// DOT reporting identity: total rooms, AE type, classification code
/// (DAE-2 items 2–4). Saved onto the AE profile + every monthly header.
class EstablishmentReportingProfileCard extends StatefulWidget {
  const EstablishmentReportingProfileCard({
    super.key,
    required this.tracksRooms,
    required this.totalRooms,
    required this.aeType,
    required this.classificationCode,
    required this.hostsMice,
    required this.saving,
    required this.onSave,
  });

  final bool tracksRooms;
  final int totalRooms;
  final String aeType;
  final String classificationCode;
  final bool hostsMice;
  final bool saving;
  final void Function({
    required int totalRooms,
    required String aeType,
    required String classificationCode,
    required bool hostsMice,
  }) onSave;

  @override
  State<EstablishmentReportingProfileCard> createState() => _EstablishmentReportingProfileCardState();
}

class _EstablishmentReportingProfileCardState extends State<EstablishmentReportingProfileCard> {
  late final TextEditingController _rooms;
  late final TextEditingController _code;
  late String _type;
  late bool _hostsMice;

  @override
  void initState() {
    super.initState();
    _hostsMice = widget.hostsMice;
    _rooms = TextEditingController(text: '${widget.totalRooms}');
    _type = AeTypeCatalog.types.containsKey(widget.aeType) ? widget.aeType : 'Others';
    _code = TextEditingController(
      text: widget.classificationCode.isNotEmpty ? widget.classificationCode : AeTypeCatalog.codeFor(_type),
    );
  }

  @override
  void didUpdateWidget(covariant EstablishmentReportingProfileCard old) {
    super.didUpdateWidget(old);
    if (old.totalRooms != widget.totalRooms) _rooms.text = '${widget.totalRooms}';
    if (old.aeType != widget.aeType && AeTypeCatalog.types.containsKey(widget.aeType)) _type = widget.aeType;
    if (old.classificationCode != widget.classificationCode && widget.classificationCode.isNotEmpty) {
      _code.text = widget.classificationCode;
    }
    if (old.hostsMice != widget.hostsMice) _hostsMice = widget.hostsMice;
  }

  @override
  void dispose() {
    _rooms.dispose();
    _code.dispose();
    super.dispose();
  }

  void _save() {
    final rooms = int.tryParse(_rooms.text.trim());
    if (widget.tracksRooms && (rooms == null || rooms < 0)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid number of rooms.'), behavior: SnackBarBehavior.floating),
      );
      return;
    }
    widget.onSave(
      totalRooms: rooms ?? 0,
      aeType: _type,
      classificationCode: _code.text.trim().isEmpty ? AeTypeCatalog.codeFor(_type) : _code.text.trim().toUpperCase(),
      hostsMice: _hostsMice,
    );
  }

  @override
  Widget build(BuildContext context) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: AeDashTokens.border),
    );
    InputDecoration dec(String label, IconData icon) => InputDecoration(
          labelText: label,
          labelStyle: AeDashTokens.body(size: 13),
          prefixIcon: Icon(icon, color: AeDashTokens.accent, size: 20),
          filled: true,
          fillColor: Colors.white,
          isDense: true,
          border: border,
          enabledBorder: border,
          focusedBorder: border.copyWith(borderSide: const BorderSide(color: AeDashTokens.accent, width: 1.4)),
        );
    final fields = <Widget>[
      if (widget.tracksRooms)
        TextField(
          controller: _rooms,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: dec('Total available rooms', Icons.bed_rounded),
        ),
      DropdownButtonFormField<String>(
        initialValue: _type,
        isExpanded: true,
        decoration: dec('Type of accommodation', Icons.apartment_rounded),
        items: [for (final t in AeTypeCatalog.types.keys) DropdownMenuItem(value: t, child: Text(t))],
        onChanged: (v) {
          if (v == null) return;
          setState(() {
            _type = v;
            _code.text = AeTypeCatalog.codeFor(v);
          });
        },
      ),
      TextField(
        controller: _code,
        textCapitalization: TextCapitalization.characters,
        decoration: dec('Classification code', Icons.tag_rounded),
      ),
    ];
    return AePanelCard(
      title: 'DOT reporting profile',
      subtitle: 'Used on your DAE-2 / DAE-1B reports (items 2–4). '
          'Rooms drive the Room No. list and occupancy rate.',
      icon: Icons.assignment_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(builder: (context, c) {
            if (c.maxWidth < 640) {
              return Column(children: [
                for (final f in fields) Padding(padding: const EdgeInsets.only(bottom: 10), child: f),
              ]);
            }
            return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (var i = 0; i < fields.length; i++) ...[
                if (i > 0) const SizedBox(width: 12),
                Expanded(child: fields[i]),
              ],
            ]);
          }),
          const SizedBox(height: 6),
          Container(
            decoration: BoxDecoration(
              color: AeDashTokens.mutedSurface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: SwitchListTile(
              value: _hostsMice,
              onChanged: widget.saving ? null : (v) => setState(() => _hostsMice = v),
              activeThumbColor: AeDashTokens.accent,
              secondary: const Icon(Icons.groups_rounded, color: AeDashTokens.accent),
              title: Text('We host events (MICE)', style: AeDashTokens.body(size: 14, color: AeDashTokens.text)),
              subtitle: Text(
                'Meetings, conventions, exhibitions, weddings, parties… '
                'Turns on the Events log and the CUS MICE survey report.',
                style: AeDashTokens.body(size: 12),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: widget.saving ? null : _save,
              style: FilledButton.styleFrom(backgroundColor: AeDashTokens.accent),
              icon: widget.saving
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.save_rounded, size: 18),
              label: const Text('Save profile'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Map pin card wrapping [EstablishmentLocationCapture] in dashboard style.
class EstablishmentMapPinCard extends StatelessWidget {
  const EstablishmentMapPinCard({
    super.key,
    required this.latitude,
    required this.longitude,
    required this.locating,
    required this.saving,
    required this.onBusyChanged,
    required this.onChanged,
  });

  final double? latitude;
  final double? longitude;
  final bool locating;
  final bool saving;
  final ValueChanged<bool> onBusyChanged;
  final ValueChanged<({double latitude, double longitude})> onChanged;

  @override
  Widget build(BuildContext context) {
    return AePanelCard(
      title: 'Map pin',
      subtitle:
          'Tourists see your establishment on Explore after OPTACA approval. '
          'Stand at the entrance, then tap Get location.',
      icon: Icons.location_on_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          EstablishmentLocationCapture(
            latitude: latitude,
            longitude: longitude,
            busy: locating,
            required: false,
            dashboardStyle: true,
            accentColor: AeDashTokens.accent,
            onBusyChanged: onBusyChanged,
            onChanged: onChanged,
          ),
          if (saving) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(minHeight: 2),
          ],
        ],
      ),
    );
  }
}

/// Profile photo gallery: dashed upload tile, real previews, empty collage.
class EstablishmentPhotosCard extends StatelessWidget {
  const EstablishmentPhotosCard({
    super.key,
    required this.urls,
    required this.maxImages,
    required this.busy,
    required this.onAdd,
    required this.onRemove,
  });

  static const String collageAsset = 'assets/images/ae_photos_collage.png';

  final List<String> urls;
  final int maxImages;
  final bool busy;
  final VoidCallback onAdd;
  final ValueChanged<int> onRemove;

  bool get _canAdd => urls.length < maxImages;

  @override
  Widget build(BuildContext context) {
    return AePanelCard(
      title: 'Profile photos',
      subtitle: 'Shown when tourists open your pin on Explore. '
          'Up to $maxImages photos.',
      icon: Icons.photo_library_rounded,
      child: LayoutBuilder(
        builder: (context, c) {
          if (urls.isEmpty) {
            final helper = Text(
              'No photos yet? Add your entrance, rooms, or amenities.',
              style: AeDashTokens.body(size: 13, color: AeDashTokens.subtitle),
            );
            if (c.maxWidth < 720) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [helper, const SizedBox(height: 12), _uploadTile()],
              );
            }
            return Row(
              children: [
                Expanded(
                  flex: 5,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      helper,
                      const SizedBox(height: 12),
                      _uploadTile(),
                    ],
                  ),
                ),
                const SizedBox(width: 24),
                Expanded(
                  flex: 4,
                  child: IgnorePointer(
                    child: Image.asset(
                      collageAsset,
                      height: 180,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  ),
                ),
              ],
            );
          }
          final tile = c.maxWidth < 420 ? (c.maxWidth - 12) / 2 : 150.0;
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (var i = 0; i < urls.length; i++) _thumb(i, tile),
              if (_canAdd || busy) _uploadTile(width: tile, height: tile),
            ],
          );
        },
      ),
    );
  }

  Widget _uploadTile({double? width, double height = 150}) {
    final canAdd = _canAdd;
    return SizedBox(
      width: width,
      height: height,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: (!canAdd || busy) ? null : onAdd,
          borderRadius: BorderRadius.circular(14),
          child: AeDashedBox(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: AeDashTokens.accent.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: busy
                        ? const Padding(
                            padding: EdgeInsets.all(13),
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AeDashTokens.accent,
                            ),
                          )
                        : const Icon(
                            Icons.add_photo_alternate_outlined,
                            color: AeDashTokens.accent,
                            size: 23,
                          ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    busy
                        ? 'Uploading…'
                        : canAdd
                            ? 'Add photo'
                            : 'Photo limit reached',
                    style: AeDashTokens.section(
                      size: 14,
                      color: canAdd ? AeDashTokens.accent : AeDashTokens.muted,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'PNG, JPG up to $maxImages photos',
                    textAlign: TextAlign.center,
                    style: AeDashTokens.body(size: 11.5),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _thumb(int i, double size) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Image.network(
              urls[i],
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                width: size,
                height: size,
                color: const Color(0xFFE2E8F0),
                child: const Icon(Icons.broken_image_outlined),
              ),
            ),
          ),
          Positioned(
            top: 6,
            right: 6,
            child: Material(
              color: Colors.black.withValues(alpha: 0.55),
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: busy ? null : () => onRemove(i),
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.close_rounded, size: 16, color: Colors.white),
                ),
              ),
            ),
          ),
          if (i == 0)
            Positioned(
              left: 8,
              bottom: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AeDashTokens.accent,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text(
                  'Cover',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Check-in / check-out time pickers as dropdown-style fields.
class EstablishmentHoursCard extends StatelessWidget {
  const EstablishmentHoursCard({
    super.key,
    required this.checkInLabel,
    required this.checkOutLabel,
    required this.saving,
    required this.onPickCheckIn,
    required this.onPickCheckOut,
  });

  /// e.g. "2:00 PM"; null when unset.
  final String? checkInLabel;
  final String? checkOutLabel;
  final bool saving;
  final VoidCallback onPickCheckIn;
  final VoidCallback onPickCheckOut;

  @override
  Widget build(BuildContext context) {
    final checkIn = AeSelectField(
      icon: Icons.login_rounded,
      label: 'Check-in time',
      value: checkInLabel == null ? 'Not set' : 'In $checkInLabel',
      onTap: saving ? null : onPickCheckIn,
    );
    final checkOut = AeSelectField(
      icon: Icons.logout_rounded,
      label: 'Check-out time',
      value: checkOutLabel == null ? 'Not set' : 'Out $checkOutLabel',
      onTap: saving ? null : onPickCheckOut,
      iconColor: AeDashTokens.chartSecondary,
    );
    return AePanelCard(
      title: 'Check-in / check-out times',
      subtitle: 'Shown to tourists on your map profile.',
      icon: Icons.schedule_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, c) {
              if (c.maxWidth < 440) {
                return Column(
                  children: [checkIn, const SizedBox(height: 10), checkOut],
                );
              }
              return Row(
                children: [
                  Expanded(child: checkIn),
                  const SizedBox(width: 12),
                  Expanded(child: checkOut),
                ],
              );
            },
          ),
          if (saving) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(minHeight: 2),
          ],
        ],
      ),
    );
  }
}
