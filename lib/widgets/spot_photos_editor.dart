import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'package:atmos_trs_system/config/supabase_storage_config.dart';
import 'package:atmos_trs_system/config/supabase_upload_config.dart';
import 'package:atmos_trs_system/models/tourist_spot.dart';
import 'package:atmos_trs_system/services/supabase_storage_upload.dart';

/// Tourist-spot photo list for the LGU edit dialog. The first photo is the
/// cover (`image_url`); all photos are saved as `gallery` by the caller.
class SpotPhotosEditor extends StatefulWidget {
  const SpotPhotosEditor({
    super.key,
    required this.spotId,
    required this.initialUrls,
    required this.onChanged,
    this.accentColor = const Color(0xFFF97316),
  });

  final String spotId;
  final List<String> initialUrls;
  final ValueChanged<List<String>> onChanged;
  final Color accentColor;

  @override
  State<SpotPhotosEditor> createState() => _SpotPhotosEditorState();
}

class _SpotPhotosEditorState extends State<SpotPhotosEditor> {
  late List<String> _urls = List<String>.from(widget.initialUrls);
  bool _uploading = false;

  void _emit() => widget.onChanged(List<String>.unmodifiable(_urls));

  Future<void> _addPhoto() async {
    final messenger = ScaffoldMessenger.of(context);
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
    setState(() => _uploading = true);
    try {
      final bytes = await picked.readAsBytes();
      if (bytes.isEmpty) throw StateError('Could not read that image.');
      final name = picked.name.toLowerCase();
      final ext = name.endsWith('.png')
          ? 'png'
          : name.endsWith('.webp')
              ? 'webp'
              : 'jpg';
      final contentType = ext == 'png'
          ? 'image/png'
          : ext == 'webp'
              ? 'image/webp'
              : 'image/jpeg';
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final url = await SupabaseStorageUpload.uploadBytes(
        objectKey: 'spots/${widget.spotId}/photo_$stamp.$ext',
        bytes: bytes,
        contentType: contentType,
      );
      if (!mounted) return;
      setState(() => _urls = [..._urls, url]);
      _emit();
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Photo upload failed: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  void _removeAt(int i) {
    setState(() => _urls = List<String>.from(_urls)..removeAt(i));
    _emit();
  }

  void _makeCover(int i) {
    if (i == 0) return;
    setState(() {
      final next = List<String>.from(_urls);
      final url = next.removeAt(i);
      _urls = [url, ...next];
    });
    _emit();
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
                        onTap: () => _makeCover(i),
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
                    ],
                  ),
                ),
              ),
            if (_urls.length < TouristSpot.maxImages)
              SizedBox(
                width: 96,
                height: 96,
                child: OutlinedButton(
                  onPressed: canAdd ? _addPhoto : null,
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
            'Tap a photo to make it the cover.',
            style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 11),
          ),
        ],
      ],
    );
  }
}
