import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'package:atmos_trs_system/config/session_storage.dart';
import 'package:atmos_trs_system/config/supabase_storage_config.dart';
import 'package:atmos_trs_system/config/supabase_upload_config.dart';
import 'package:atmos_trs_system/models/tourist_spot.dart';
import 'package:atmos_trs_system/services/supabase_storage_upload.dart';
import 'package:atmos_trs_system/utils/municipality_helper.dart';

/// Tourist-spot photo list for the LGU edit dialog. The first photo is the
/// cover (`image_url`); all photos are saved as `gallery` by the caller.
class SpotPhotosEditor extends StatefulWidget {
  const SpotPhotosEditor({
    super.key,
    required this.spotId,
    required this.municipalityId,
    required this.initialUrls,
    required this.onChanged,
    this.accentColor = const Color(0xFFF97316),
  });

  final String spotId;
  final String municipalityId;
  final List<String> initialUrls;
  final ValueChanged<List<String>> onChanged;
  final Color accentColor;

  @override
  State<SpotPhotosEditor> createState() => _SpotPhotosEditorState();
}

class _SpotPhotosEditorState extends State<SpotPhotosEditor> {
  late List<String> _urls = List<String>.from(widget.initialUrls);
  bool _uploading = false;
  double _progress = 0;
  final Set<int> _fingerprints = <int>{};

  void _emit() => widget.onChanged(List<String>.unmodifiable(_urls));

  int _fingerprint(Uint8List bytes) {
    var hash = bytes.length;
    final head = bytes.length < 48 ? bytes.length : 48;
    for (var i = 0; i < head; i++) {
      hash = (hash * 31 + bytes[i]) & 0x7fffffff;
    }
    if (bytes.length > head) {
      final start = bytes.length - 16;
      for (var i = start; i < bytes.length; i++) {
        hash = (hash * 31 + bytes[i]) & 0x7fffffff;
      }
    }
    return hash;
  }

  Future<void> _assertCanEdit() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('Sign in with your LGU account to change photos.');
    }
    final role = await SessionStorage.getStoredRole();
    if (role != UserRole.tourism && role != UserRole.provincialTourism) {
      throw StateError('Only an LGU tourism account can change spot photos.');
    }
    if (role == UserRole.provincialTourism) return;
    final staffMun = normalizeMunicipalityId(
      await SessionStorage.getStoredMunicipalityId(),
    );
    final spotMun = normalizeMunicipalityId(widget.municipalityId);
    if (staffMun.isEmpty || spotMun.isEmpty || staffMun != spotMun) {
      throw StateError(
        'You can only change photos for tourist spots in your municipality.',
      );
    }
  }

  Future<void> _pick({int? replaceIndex}) async {
    final messenger = ScaffoldMessenger.of(context);
    if (_uploading) return;
    if (replaceIndex == null && _urls.length >= TouristSpot.maxImages) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('This spot already has 8 photos.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }
    if (!SupabaseUploadConfig.hasUploadCredentials) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Supabase is not configured for uploads. '
            'Run tools/gen_dart_defines.ps1 once, then hot restart.',
          ),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 72,
      maxWidth: 1280,
    );
    if (picked == null) return;
    setState(() {
      _uploading = true;
      _progress = 0;
    });
    try {
      await _assertCanEdit();
      final bytes = await picked.readAsBytes();
      final contentType = SupabaseStorageUpload.contentTypeForImageBytes(bytes);
      if (contentType == null) {
        throw StateError('Use a JPG, PNG, or WEBP photo.');
      }
      final fingerprint = _fingerprint(bytes);
      if (_fingerprints.contains(fingerprint)) {
        throw StateError('That photo is already in this spot.');
      }
      final url = await SupabaseStorageUpload.uploadSpotPhoto(
        spotId: widget.spotId,
        bytes: bytes,
        onProgress: (value) {
          if (!mounted) return;
          setState(() => _progress = value);
        },
      );
      if (!mounted) return;
      setState(() {
        final next = List<String>.from(_urls);
        if (replaceIndex != null &&
            replaceIndex >= 0 &&
            replaceIndex < next.length) {
          next[replaceIndex] = url;
        } else {
          next.add(url);
        }
        _urls = next;
        _fingerprints.add(fingerprint);
      });
      _emit();
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('$e'.replaceFirst('Bad state: ', '')),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _uploading = false;
          _progress = 0;
        });
      }
    }
  }

  void _removeAt(int i) {
    setState(() => _urls = List<String>.from(_urls)..removeAt(i));
    _emit();
  }

  void _move(int index, int delta) {
    final target = index + delta;
    if (target < 0 || target >= _urls.length) return;
    setState(() {
      final next = List<String>.from(_urls);
      final url = next.removeAt(index);
      next.insert(target, url);
      _urls = next;
    });
    _emit();
  }

  Widget _thumbAction({required IconData icon, required VoidCallback? onTap}) {
    return Material(
      color: Colors.black54,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Icon(icon, size: 16, color: Colors.white),
        ),
      ),
    );
  }

  Widget _thumb(String raw) {
    final src = SupabaseStorageConfig.resolve(raw);
    Widget broken(BuildContext _, Object __, StackTrace? ___) => Container(
          color: const Color(0xFFF3F4F6),
          alignment: Alignment.center,
          child: const Icon(Icons.broken_image_outlined, color: Colors.grey),
        );
    if (src.startsWith('http') || src.startsWith('data:image')) {
      return Image.network(src, fit: BoxFit.cover, errorBuilder: broken);
    }
    return Image.asset(src, fit: BoxFit.cover, errorBuilder: broken);
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.accentColor;
    final canAdd = !_uploading && _urls.length < TouristSpot.maxImages;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Photos (${_urls.length}/${TouristSpot.maxImages}) — first is the cover',
          style: const TextStyle(
            color: Color(0xFF6B7280),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (_uploading) ...[
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: _progress <= 0 ? null : _progress,
              minHeight: 4,
              color: accent,
              backgroundColor: accent.withValues(alpha: 0.15),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Uploading photo ${(_progress * 100).round()}%',
            style: const TextStyle(color: Color(0xFF6B7280), fontSize: 11),
          ),
        ],
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var i = 0; i < _urls.length; i++)
              SizedBox(
                width: 96,
                height: 96,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      GestureDetector(
                        onTap: _uploading || i == 0 ? null : () => _move(i, -i),
                        child: _thumb(_urls[i]),
                      ),
                      if (i == 0)
                        Positioned(
                          left: 4,
                          bottom: 4,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: accent,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'Cover',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      Positioned(
                        right: 2,
                        top: 2,
                        child: Material(
                          color: Colors.black54,
                          shape: const CircleBorder(),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: _uploading ? null : () => _removeAt(i),
                            child: const Padding(
                              padding: EdgeInsets.all(3),
                              child: Icon(
                                Icons.close_rounded,
                                size: 16,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (i > 0)
                        Positioned(
                          left: 2,
                          top: 34,
                          child: _thumbAction(
                            icon: Icons.chevron_left_rounded,
                            onTap: _uploading ? null : () => _move(i, -1),
                          ),
                        ),
                      if (i < _urls.length - 1)
                        Positioned(
                          right: 2,
                          top: 34,
                          child: _thumbAction(
                            icon: Icons.chevron_right_rounded,
                            onTap: _uploading ? null : () => _move(i, 1),
                          ),
                        ),
                      Positioned(
                        right: 2,
                        bottom: 2,
                        child: _thumbAction(
                          icon: Icons.swap_horiz_rounded,
                          onTap: _uploading ? null : () => _pick(replaceIndex: i),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (_urls.length < TouristSpot.maxImages)
              SizedBox(
                width: 96,
                height: 96,
                child: OutlinedButton(
                  onPressed: canAdd ? () => _pick() : null,
                  style: OutlinedButton.styleFrom(
                    padding: EdgeInsets.zero,
                    side: BorderSide(color: accent.withValues(alpha: 0.5)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: _uploading
                      ? SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: accent,
                          ),
                        )
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.add_a_photo_outlined, color: accent),
                            const SizedBox(height: 4),
                            Text(
                              'Add photo',
                              style: TextStyle(
                                color: accent,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
          ],
        ),
        if (_urls.length > 1) ...[
          const SizedBox(height: 6),
          const Text(
            'Tap a photo to make it the cover. Arrows reorder. The swap icon replaces a photo.',
            style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 11),
          ),
        ],
      ],
    );
  }
}
