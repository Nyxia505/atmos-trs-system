import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../data.dart';
import '../firestore_loader.dart';
import '../services/profile_photo_service.dart';
import 'municipality_image.dart';

/// Profile avatar: Firestore URL → Auth photo → Storage — same pipeline as catalog images.
class ProfileHeaderPhoto extends StatefulWidget {
  final String? uid;
  final String? initialPhotoPath;
  final String? authPhotoUrl;
  final double size;
  final Color? fallbackIconColor;
  final bool allowUpload;
  final VoidCallback? onPhotoChanged;

  const ProfileHeaderPhoto({
    super.key,
    required this.uid,
    this.initialPhotoPath,
    this.authPhotoUrl,
    this.size = 88,
    this.fallbackIconColor,
    this.allowUpload = false,
    this.onPhotoChanged,
  });

  @override
  State<ProfileHeaderPhoto> createState() => _ProfileHeaderPhotoState();
}

class _ProfileHeaderPhotoState extends State<ProfileHeaderPhoto> {
  String? _resolvedPath;
  Uint8List? _bytes;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _resolvePhoto();
  }

  @override
  void didUpdateWidget(ProfileHeaderPhoto oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uid != widget.uid ||
        oldWidget.initialPhotoPath != widget.initialPhotoPath ||
        oldWidget.authPhotoUrl != widget.authPhotoUrl) {
      _resolvedPath = null;
      _bytes = null;
      _loading = true;
      _resolvePhoto();
    }
  }

  String? _pathFromProps() {
    final fromUser = widget.initialPhotoPath?.trim() ?? '';
    if (fromUser.isNotEmpty && fromUser != 'firestore-base64-profile') {
      return fromUser;
    }
    final fromAuth = widget.authPhotoUrl?.trim() ?? '';
    if (fromAuth.isNotEmpty) return fromAuth;
    return null;
  }

  Future<void> _resolvePhoto() async {
    final id = widget.uid?.trim() ?? '';
    final immediate = _pathFromProps();
    if (immediate != null && immediate.isNotEmpty) {
      if (mounted) {
        setState(() {
          _resolvedPath = immediate;
          _loading = false;
        });
      }
      await _tryLoadBytes(immediate);
    }

    if (id.isEmpty) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    try {
      final firestoreBytes = await fetchProfilePhotoBytesForUid(id);
      if (!mounted) return;
      if (firestoreBytes != null && firestoreBytes.isNotEmpty) {
        setState(() {
          _bytes = firestoreBytes;
          _loading = false;
        });
        return;
      }

      await syncProfilePhotoUrlForUid(id);
      final url = await fetchBestProfilePhotoUrl(id);
      if (!mounted) return;
      if (url != null && url.isNotEmpty) {
        setState(() {
          _resolvedPath = url;
          _loading = false;
        });
        await _tryLoadBytes(url);
      } else if (_resolvedPath == null || _resolvedPath!.isEmpty) {
        setState(() => _loading = false);
      }
    } catch (e) {
      debugPrint('ProfileHeaderPhoto resolve $id: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _tryLoadBytes(String pathOrUrl) async {
    final id = widget.uid?.trim() ?? '';
    if (id.isEmpty) return;
    final trimmed = pathOrUrl.trim();
    if (trimmed.isEmpty) return;

    final needsBytes = trimmed.contains('firebasestorage') ||
        trimmed.startsWith('gs://') ||
        (trimmed.contains('/') && !trimmed.startsWith('http'));
    if (!needsBytes && !trimmed.startsWith('http')) return;

    final bytes = await loadProfilePhotoBytesFromStorage(
      id,
      downloadUrl: trimmed.startsWith('http') ? trimmed : null,
    );
    if (!mounted || bytes == null || bytes.isEmpty) return;
    setState(() => _bytes = bytes);
  }

  Widget _fallback() => _FallbackDisk(
        size: widget.size,
        iconColor: widget.fallbackIconColor,
      );

  Widget _face() {
    final bytes = _bytes;
    if (bytes != null && bytes.isNotEmpty) {
      return Image.memory(
        bytes,
        width: widget.size,
        height: widget.size,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (context, error, stack) => _fallback(),
      );
    }

    final path = _resolvedPath?.trim() ?? '';
    if (path.isNotEmpty) {
      final px = (widget.size * 3).round().clamp(96, 320);
      return buildMunicipalityImage(
        path,
        fallback: _fallback(),
        memCacheWidth: px,
        memCacheHeight: px,
      );
    }

    if (_loading) {
      return _LoadingDisk(
        size: widget.size,
        iconColor: widget.fallbackIconColor,
      );
    }
    return _fallback();
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.uid?.trim() ?? '';
    Widget avatar = ClipOval(
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: _face(),
      ),
    );

    if (id.isNotEmpty) {
      avatar = _FirestorePhotoListener(
        uid: id,
        onUrl: (url) {
          if (url.isEmpty) return;
          if (_resolvedPath == url) return;
          setState(() => _resolvedPath = url);
          _tryLoadBytes(url);
        },
        onBytes: (bytes) {
          if (bytes.isEmpty) return;
          setState(() {
            _bytes = bytes;
            _loading = false;
          });
        },
        child: avatar,
      );
    }

    if (!widget.allowUpload) return avatar;

    return GestureDetector(
      onTap: () => _pickAndUpload(context, id),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          avatar,
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.camera_alt,
                size: widget.size * 0.22,
                color: AppColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickAndUpload(BuildContext context, String uid) async {
    if (uid.isEmpty) return;
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1200,
      imageQuality: 85,
    );
    if (picked == null) return;

    final bytes = await picked.readAsBytes();
    final url = await uploadAndSaveProfilePhoto(uid: uid, bytes: bytes);
    if (url == null || url.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not upload photo. Try again.')),
        );
      }
      return;
    }
    await loadUsersFromFirestore();
    if (!mounted) return;
    setState(() {
      _resolvedPath = url;
      _bytes = bytes;
      _loading = false;
    });
    widget.onPhotoChanged?.call();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile photo updated')),
      );
    }
  }
}

/// Updates avatar when Firestore `profilePhotoUrl` changes.
class _FirestorePhotoListener extends StatefulWidget {
  final String uid;
  final void Function(String url) onUrl;
  final void Function(Uint8List bytes) onBytes;
  final Widget child;

  const _FirestorePhotoListener({
    required this.uid,
    required this.onUrl,
    required this.onBytes,
    required this.child,
  });

  @override
  State<_FirestorePhotoListener> createState() => _FirestorePhotoListenerState();
}

class _FirestorePhotoListenerState extends State<_FirestorePhotoListener> {
  // Subscribed once per uid: creating `.snapshots()` in build re-downloads the
  // (base64-photo) documents on every rebuild and loops via onBytes → setState.
  final List<StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>> _subs =
      [];
  String? _lastEmittedUrl;
  Uint8List? _lastEmittedBytes;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void didUpdateWidget(covariant _FirestorePhotoListener oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uid != widget.uid) {
      _cancel();
      _lastEmittedUrl = null;
      _lastEmittedBytes = null;
      _subscribe();
    }
  }

  @override
  void dispose() {
    _cancel();
    super.dispose();
  }

  void _subscribe() {
    final db = FirebaseFirestore.instance;
    for (final collection in [kUsersCollection, kTouristCollection]) {
      _subs.add(
        db.collection(collection).doc(widget.uid).snapshots().listen(
          (snap) {
            if (mounted && snap.exists) _maybeEmit(snap.data());
          },
          onError: (Object e) =>
              debugPrint('Profile photo listener ($collection): $e'),
        ),
      );
    }
  }

  void _cancel() {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
  }

  void _maybeEmit(Map<String, dynamic>? data) {
    if (data == null) return;
    final bytes = profileImageBytesFromFirestoreMap(data);
    if (bytes != null && bytes.isNotEmpty) {
      if (listEquals(bytes, _lastEmittedBytes)) return;
      _lastEmittedBytes = bytes;
      widget.onBytes(bytes);
      return;
    }
    final url = httpProfilePhotoUrlFromMap(data);
    if (url == null || url.isEmpty || url == _lastEmittedUrl) return;
    _lastEmittedUrl = url;
    widget.onUrl(url);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _FallbackDisk extends StatelessWidget {
  final double size;
  final Color? iconColor;

  const _FallbackDisk({required this.size, this.iconColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      color: Colors.white.withValues(alpha: 0.95),
      alignment: Alignment.center,
      child: Icon(
        Icons.person,
        color: iconColor ?? AppColors.primary,
        size: size * 0.45,
      ),
    );
  }
}

class _LoadingDisk extends StatelessWidget {
  final double size;
  final Color? iconColor;

  const _LoadingDisk({required this.size, this.iconColor});

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        _FallbackDisk(size: size, iconColor: iconColor),
        const SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ],
    );
  }
}
