import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:atmos_trs_system/config/ae_register_schema.dart';
import 'package:atmos_trs_system/services/ae_type_suggestion_service.dart';
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
    this.customAeTypes = const [],
    required this.hostsMice,
    required this.saving,
    required this.onSave,
    this.establishmentId = '',
    this.businessName = '',
  });

  final bool tracksRooms;
  final int totalRooms;
  final String aeType;
  final String classificationCode;
  final List<String> customAeTypes;
  final bool hostsMice;
  final bool saving;
  final String establishmentId;
  final String businessName;
  final void Function({
    required int totalRooms,
    required String aeType,
    required String classificationCode,
    required bool hostsMice,
    List<String> customAeTypes,
  }) onSave;

  @override
  State<EstablishmentReportingProfileCard> createState() => _EstablishmentReportingProfileCardState();
}

class _EstablishmentReportingProfileCardState extends State<EstablishmentReportingProfileCard> {
  late final TextEditingController _rooms;
  late final TextEditingController _code;
  late String _type;
  late List<String> _customTypes;
  late bool _hostsMice;
  List<String> _approvedExtras = const [];
  AeTypeSuggestion? _suggestion;

  List<String> get _typeOptions => AeTypeCatalog.dropdownOptions(
        current: _type,
        extras: [..._approvedExtras, ..._customTypes],
      );

  @override
  void initState() {
    super.initState();
    _hostsMice = widget.hostsMice;
    _rooms = TextEditingController(text: '${widget.totalRooms}');
    _customTypes = List<String>.from(widget.customAeTypes);
    final saved = widget.aeType.trim();
    _type = saved.isNotEmpty
        ? (AeTypeCatalog.officialName(saved) ?? saved)
        : AeTypeCatalog.others;
    _code = TextEditingController(
      text: widget.classificationCode.isNotEmpty
          ? widget.classificationCode
          : AeTypeCatalog.codeFor(_type),
    );
    _loadTypeMeta();
  }

  Future<void> _loadTypeMeta() async {
    final extras = await AeTypeSuggestionService.loadApprovedExtras();
    AeTypeSuggestion? suggestion;
    final id = widget.establishmentId.trim();
    if (id.isNotEmpty) {
      suggestion = await AeTypeSuggestionService.latestForEstablishment(id);
    }
    if (!mounted) return;
    setState(() {
      _approvedExtras = extras;
      _suggestion = suggestion;
    });
  }

  @override
  void didUpdateWidget(covariant EstablishmentReportingProfileCard old) {
    super.didUpdateWidget(old);
    if (old.totalRooms != widget.totalRooms) _rooms.text = '${widget.totalRooms}';
    if (old.aeType != widget.aeType && widget.aeType.trim().isNotEmpty) {
      _type = AeTypeCatalog.officialName(widget.aeType) ?? widget.aeType.trim();
    }
    if (old.classificationCode != widget.classificationCode && widget.classificationCode.isNotEmpty) {
      _code.text = widget.classificationCode;
    }
    if (old.customAeTypes != widget.customAeTypes) {
      _customTypes = List<String>.from(widget.customAeTypes);
    }
    if (old.hostsMice != widget.hostsMice) _hostsMice = widget.hostsMice;
    if (old.establishmentId != widget.establishmentId) _loadTypeMeta();
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
      classificationCode: _code.text.trim().isEmpty
          ? AeTypeCatalog.codeFor(_type)
          : _code.text.trim().toUpperCase(),
      hostsMice: _hostsMice,
      customAeTypes: AeTypeCatalog.parseExtras([
        ..._customTypes,
        if (!AeTypeCatalog.isOfficial(_type) &&
            !_approvedExtras.any((e) => e.toLowerCase() == _type.toLowerCase()))
          _type,
      ]),
    );
  }

  Future<void> _addType() async {
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
    final result = await showDialog<({String name, bool submitted})>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (ctx) => _AddAeTypeDialog(
        official: [
          ...AeTypeCatalog.types.keys,
          ..._approvedExtras,
        ],
        alreadyPending: _suggestion?.isPending == true ? _suggestion!.name : null,
        establishmentId: widget.establishmentId,
        businessName: widget.businessName,
      ),
    );
    if (result == null || !mounted) return;
    final cleaned = result.name.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (cleaned.isEmpty) return;

    // Existing official / already-approved types: select immediately (no suggestion).
    if (!result.submitted) {
      final official = AeTypeCatalog.officialName(cleaned);
      if (official != null) {
        setState(() {
          _type = official;
          _code.text = AeTypeCatalog.codeFor(official);
        });
        return;
      }
      for (final e in _approvedExtras) {
        if (e.toLowerCase() == cleaned.toLowerCase()) {
          setState(() {
            _type = e;
            _code.text = AeTypeCatalog.codeFor(e);
          });
          return;
        }
      }
      return;
    }

    await _loadTypeMeta();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '"$cleaned" submitted for OPTACA review. '
          'Your current type is unchanged until it is approved.',
        ),
        behavior: SnackBarBehavior.floating,
      ),
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
      InputDecorator(
        decoration: dec('Type of accommodation', Icons.apartment_rounded).copyWith(
          suffixIcon: IconButton(
            tooltip: '+ Add New Type',
            onPressed: widget.saving ? null : _addType,
            icon: const Icon(Icons.add_circle_outline_rounded, color: AeDashTokens.accent),
          ),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: _typeOptions.contains(_type) ? _type : AeTypeCatalog.others,
            isExpanded: true,
            isDense: true,
            items: [
              for (final t in _typeOptions)
                DropdownMenuItem(
                  value: t,
                  child: Text(t, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: widget.saving
                ? null
                : (v) {
                    if (v == null) return;
                    setState(() {
                      _type = v;
                      _code.text = AeTypeCatalog.codeFor(v);
                    });
                  },
          ),
        ),
      ),
      TextField(
        controller: _code,
        textCapitalization: TextCapitalization.characters,
        decoration: dec('Classification code', Icons.tag_rounded),
      ),
    ];
    final suggestion = _suggestion;
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
          if (suggestion != null) ...[
            const SizedBox(height: 4),
            _AeTypeSuggestionStatusBanner(suggestion: suggestion),
          ],
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

class _AeTypeSuggestionStatusBanner extends StatelessWidget {
  const _AeTypeSuggestionStatusBanner({required this.suggestion});

  final AeTypeSuggestion suggestion;

  @override
  Widget build(BuildContext context) {
    final Color color;
    final String label;
    if (suggestion.isPending) {
      color = AeDashTokens.warning;
      label = 'Pending OPTACA review: "${suggestion.name}"';
    } else if (suggestion.isApproved) {
      color = AeDashTokens.success;
      label = 'Approved: "${suggestion.name}" is now in the shared type list.';
    } else if (suggestion.isRejected) {
      color = AeDashTokens.danger;
      label =
          'Rejected: "${suggestion.name}". Your current classification is unchanged.';
    } else {
      return const SizedBox.shrink();
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: AeDashTokens.body(size: 12.5, color: color, weight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _AddAeTypeDialog extends StatefulWidget {
  const _AddAeTypeDialog({
    required this.official,
    required this.establishmentId,
    this.businessName = '',
    this.alreadyPending,
  });

  final List<String> official;
  final String establishmentId;
  final String businessName;
  final String? alreadyPending;

  @override
  State<_AddAeTypeDialog> createState() => _AddAeTypeDialogState();
}

class _AddAeTypeDialogState extends State<_AddAeTypeDialog> {
  late final TextEditingController _name;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController();
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final raw = _name.text;
    final officialHit = AeTypeCatalog.officialName(raw.trim());
    if (officialHit != null) {
      Navigator.pop(context, (name: officialHit, submitted: false));
      return;
    }
    for (final e in widget.official) {
      if (e.toLowerCase() == raw.trim().toLowerCase()) {
        Navigator.pop(context, (name: e, submitted: false));
        return;
      }
    }

    final err = AeTypeSuggestionService.validateSuggestion(
      raw: raw,
      official: widget.official,
      alreadyPending: widget.alreadyPending,
    );
    if (err != null) {
      setState(() => _error = err);
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AeTypeSuggestionService.submitPending(
        name: raw,
        establishmentId: widget.establishmentId,
        businessName: widget.businessName,
      );
      if (!mounted) return;
      Navigator.pop(context, (name: raw.trim(), submitted: true));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.toString().replaceFirst(RegExp(r'^StateError:\s*'), '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return AlertDialog(
      title: const Text('Suggest Accommodation Type'),
      content: SizedBox(
        width: width < 480 ? width * 0.9 : 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'New accommodation types require OPTACA approval.',
              style: AeDashTokens.body(size: 12.5, weight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              'Your current classification stays until OPTACA approves the suggestion.',
              style: AeDashTokens.body(size: 12.5),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _name,
              autofocus: true,
              enabled: !_busy,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: 'Accommodation Type Name',
                hintText: 'e.g. Homestay, Guesthouse, Hostel',
                errorText: _error,
                errorMaxLines: 4,
                filled: true,
                fillColor: const Color(0xFFFFF7ED),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AeDashTokens.accent, width: 1.4),
                ),
              ),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              onSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AeDashTokens.accent),
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('Submit Suggestion'),
        ),
      ],
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
    this.municipalityId,
  });

  final double? latitude;
  final double? longitude;
  final bool locating;
  final bool saving;
  final ValueChanged<bool> onBusyChanged;
  final ValueChanged<({double latitude, double longitude})> onChanged;
  final String? municipalityId;

  @override
  Widget build(BuildContext context) {
    return AePanelCard(
      title: 'Map pin',
      subtitle:
          'Tourists see your establishment on Explore after OPTACA approval. '
          'Search your hotel, use Get location, or adjust the pin on the map.',
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
            municipalityId: municipalityId,
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
                  child: _collageCta(),
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

  Widget _collageCta() {
    final canAdd = _canAdd && !busy;
    return MouseRegion(
      cursor: canAdd ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: canAdd ? onAdd : null,
        child: Semantics(
          button: true,
          label: 'Add profile photo',
          child: Stack(
            alignment: Alignment.center,
            children: [
              Image.asset(
                collageAsset,
                height: 180,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const SizedBox(height: 180),
              ),
              if (busy)
                const SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: AeDashTokens.accent,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _uploadTile({double? width, double height = 150}) {
    final canAdd = _canAdd;
    return SizedBox(
      width: width,
      height: height,
      child: MouseRegion(
        cursor: canAdd && !busy
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
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
            child: _photo(urls[i], size),
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

  Widget _photo(String url, double size) {
    Widget broken() => Container(
          width: size,
          height: size,
          color: const Color(0xFFE2E8F0),
          child: const Icon(Icons.broken_image_outlined),
        );
    if (url.startsWith('data:image')) {
      try {
        final bytes = base64Decode(url.split(',').last);
        return Image.memory(
          bytes,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => broken(),
        );
      } catch (_) {
        return broken();
      }
    }
    return Image.network(
      url,
      width: size,
      height: size,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => broken(),
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
