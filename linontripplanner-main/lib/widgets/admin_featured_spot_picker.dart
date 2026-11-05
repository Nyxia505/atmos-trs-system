import 'package:flutter/material.dart';

import '../data.dart';
import 'municipality_image.dart';

/// Modern searchable tourist-spot selector for Add / Edit Featured Spot.
class AdminFeaturedSpotPicker extends FormField<String> {
  AdminFeaturedSpotPicker({
    super.key,
    required List<TouristSpot> spots,
    super.initialValue,
    super.onSaved,
    FormFieldValidator<String>? validator,
    ValueChanged<String?>? onChanged,
    super.autovalidateMode = AutovalidateMode.onUserInteraction,
  }) : super(
          validator: validator ??
              (v) => (v == null || v.isEmpty) ? 'Please choose a spot' : null,
          builder: (state) {
            return _AdminFeaturedSpotPickerBody(
              spots: spots,
              selectedName: state.value,
              errorText: state.errorText,
              onChanged: (name) {
                state.didChange(name);
                onChanged?.call(name);
              },
            );
          },
        );
}

class _AdminFeaturedSpotPickerBody extends StatelessWidget {
  const _AdminFeaturedSpotPickerBody({
    required this.spots,
    required this.selectedName,
    required this.onChanged,
    this.errorText,
  });

  final List<TouristSpot> spots;
  final String? selectedName;
  final ValueChanged<String?> onChanged;
  final String? errorText;

  TouristSpot? get _selected {
    final name = selectedName;
    if (name == null || name.isEmpty) return null;
    for (final s in spots) {
      if (s.name == name) return s;
    }
    return null;
  }

  Future<void> _openPicker(BuildContext context) async {
    final picked = await showDialog<TouristSpot>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => _SpotSearchDialog(
        spots: spots,
        selectedName: selectedName,
      ),
    );
    if (picked != null) {
      onChanged(picked.name);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selected;
    final hasError = errorText != null && errorText!.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: spots.isEmpty ? null : () => _openPicker(context),
            borderRadius: BorderRadius.circular(14),
            child: Ink(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: hasError
                      ? const Color(0xFFDC2626)
                      : selected != null
                          ? AppColors.primary.withValues(alpha: 0.45)
                          : const Color(0xFFE2E8F0),
                  width: selected != null || hasError ? 1.4 : 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: selected == null
                          ? const Row(
                              children: [
                                _SpotThumbPlaceholder(size: 56),
                                SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    'Choose a tourist spot',
                                    style: TextStyle(
                                      color: AppColors.textGrey,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            )
                          : _SpotOptionRow(
                              spot: selected,
                              selected: true,
                              compact: true,
                            ),
                    ),
                    Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: spots.isEmpty
                          ? AppColors.textGrey.withValues(alpha: 0.5)
                          : AppColors.primary,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (hasError) ...[
          const SizedBox(height: 6),
          Text(
            errorText!,
            style: const TextStyle(
              color: Color(0xFFDC2626),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }
}

class _SpotSearchDialog extends StatefulWidget {
  const _SpotSearchDialog({
    required this.spots,
    this.selectedName,
  });

  final List<TouristSpot> spots;
  final String? selectedName;

  @override
  State<_SpotSearchDialog> createState() => _SpotSearchDialogState();
}

class _SpotSearchDialogState extends State<_SpotSearchDialog> {
  final _search = TextEditingController();
  late List<TouristSpot> _filtered;

  @override
  void initState() {
    super.initState();
    _filtered = List<TouristSpot>.from(widget.spots)
      ..sort((a, b) => a.displayName.toLowerCase().compareTo(
            b.displayName.toLowerCase(),
          ));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _applyFilter(String raw) {
    final q = raw.trim().toLowerCase();
    setState(() {
      if (q.isEmpty) {
        _filtered = List<TouristSpot>.from(widget.spots)
          ..sort((a, b) => a.displayName.toLowerCase().compareTo(
                b.displayName.toLowerCase(),
              ));
        return;
      }
      _filtered = widget.spots.where((s) {
        final hay = [
          s.name,
          s.displayName,
          s.location,
          s.category,
          s.type,
        ].join(' ').toLowerCase();
        return hay.contains(q);
      }).toList()
        ..sort((a, b) => a.displayName.toLowerCase().compareTo(
              b.displayName.toLowerCase(),
            ));
    });
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final width = size.width < 640 ? size.width - 32.0 : 520.0;
    final height = (size.height * 0.72).clamp(360.0, 640.0);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: width,
        height: height,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Choose a tourist spot',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textDark,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: TextField(
                controller: _search,
                autofocus: true,
                onChanged: _applyFilter,
                decoration: InputDecoration(
                  hintText: 'Search by name or municipality',
                  prefixIcon: const Icon(Icons.search_rounded),
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                      color: AppColors.primary,
                      width: 1.4,
                    ),
                  ),
                ),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _filtered.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'No tourist spots found',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppColors.textGrey,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 10,
                      ),
                      itemCount: _filtered.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 6),
                      itemBuilder: (context, index) {
                        final spot = _filtered[index];
                        final isSelected = spot.name == widget.selectedName;
                        return Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => Navigator.pop(context, spot),
                            child: Ink(
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? AppColors.primary.withValues(alpha: 0.08)
                                    : Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isSelected
                                      ? AppColors.primary
                                      : const Color(0xFFE8EEF4),
                                  width: isSelected ? 1.4 : 1,
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  10,
                                  10,
                                  12,
                                  10,
                                ),
                                child: _SpotOptionRow(
                                  spot: spot,
                                  selected: isSelected,
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SpotOptionRow extends StatelessWidget {
  const _SpotOptionRow({
    required this.spot,
    this.selected = false,
    this.compact = false,
  });

  final TouristSpot spot;
  final bool selected;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final thumb = compact ? 56.0 : 56.0;
    final municipality = spot.location.trim().isEmpty
        ? 'Misamis Occidental'
        : spot.location.trim();
    final rated = spot.rating > 0;

    return Row(
      children: [
        _SpotThumb(spot: spot, size: thumb),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                spot.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textDark,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Flexible(
                    child: Text(
                      municipality,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.textGrey,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const Text(
                    ' · ',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: AppColors.textGrey,
                    ),
                  ),
                  Icon(
                    Icons.star_rounded,
                    size: 15,
                    color: rated
                        ? const Color(0xFFF5B301)
                        : AppColors.textGrey.withValues(alpha: 0.55),
                  ),
                  const SizedBox(width: 3),
                  Text(
                    rated ? spot.rating.toStringAsFixed(1) : 'Not yet rated',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: rated
                          ? const Color(0xFFB45309)
                          : AppColors.textGrey,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (selected) ...[
          const SizedBox(width: 8),
          const Icon(
            Icons.check_circle_rounded,
            color: AppColors.primary,
            size: 22,
          ),
        ],
      ],
    );
  }
}

class _SpotThumb extends StatelessWidget {
  const _SpotThumb({required this.spot, required this.size});

  final TouristSpot spot;
  final double size;

  @override
  Widget build(BuildContext context) {
    final cache = (size * MediaQuery.devicePixelRatioOf(context))
        .round()
        .clamp(56, 160);
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: size,
        height: size,
        child: buildTouristSpotProfileImage(
          spot,
          memCacheWidth: cache,
          memCacheHeight: cache,
          fallback: _SpotThumbPlaceholder(size: size),
        ),
      ),
    );
  }
}

class _SpotThumbPlaceholder extends StatelessWidget {
  const _SpotThumbPlaceholder({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(
          Icons.image_outlined,
          color: AppColors.primary,
          size: 26,
        ),
      ),
    );
  }
}
