import 'dart:convert';

import 'package:atmos_trs_system/config/app_theme.dart';
import 'package:atmos_trs_system/config/supabase_storage_config.dart';
import 'package:atmos_trs_system/data/tourist_spot_image_catalog.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Reliable spot/municipality image loader (fixes Flutter web space-encoding 404s).
///
/// Network images use [CachedNetworkImage] with mem-cache sizing so cards do not
/// decode full-resolution photos on every cold start.
class SpotImage extends StatefulWidget {
  const SpotImage({
    super.key,
    this.imageUrl,
    this.spotId,
    this.municipalityId,
    this.spotName,
    this.category,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.placeholderIcon = Icons.landscape_rounded,
  });

  final String? imageUrl;
  final String? spotId;
  final String? municipalityId;
  final String? spotName;
  final String? category;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final IconData placeholderIcon;

  @override
  State<SpotImage> createState() => _SpotImageState();
}

class _SpotImageState extends State<SpotImage> {
  static final Map<String, Uint8List> _webCache = {};

  Uint8List? _bytes;
  bool _failed = false;
  bool _preferLocalFallback = false;
  String? _loadedKey;

  @override
  void initState() {
    super.initState();
    _loadAsset();
  }

  @override
  void didUpdateWidget(covariant SpotImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl ||
        oldWidget.spotId != widget.spotId ||
        oldWidget.municipalityId != widget.municipalityId ||
        oldWidget.spotName != widget.spotName ||
        oldWidget.category != widget.category) {
      _bytes = null;
      _failed = false;
      _preferLocalFallback = false;
      _loadedKey = null;
      _loadAsset();
    }
  }

  String get _resolved {
    final raw = (widget.imageUrl ?? '').trim();
    if (raw.startsWith('data:image')) return raw;
    // Keep Storage/network URLs intact — do not run through asset path decoding.
    if (raw.startsWith('http://') || raw.startsWith('https://')) {
      return SupabaseStorageConfig.resolve(raw);
    }
    if (raw.startsWith('assets/')) {
      return SupabaseStorageConfig.resolve(
        TouristSpotImageCatalog.normalizeAssetPath(raw),
      );
    }
    if (raw.isNotEmpty) {
      return TouristSpotImageCatalog.displayUrl(
        preferred: raw,
        spotId: widget.spotId,
        municipalityId: widget.municipalityId,
        spotName: widget.spotName,
        category: widget.category,
      );
    }
    return TouristSpotImageCatalog.displayUrl(
      spotId: widget.spotId,
      municipalityId: widget.municipalityId,
      spotName: widget.spotName,
      category: widget.category,
    );
  }

  String? get _localAssetFallback {
    final url = _resolved;
    final fromRemote = SupabaseStorageConfig.assetPathFromPublicUrl(url);
    if (fromRemote != null) {
      return TouristSpotImageCatalog.normalizeAssetPath(fromRemote);
    }
    if (url.startsWith('assets/')) {
      return TouristSpotImageCatalog.normalizeAssetPath(url);
    }
    final raw = (widget.imageUrl ?? '').trim();
    if (raw.startsWith('assets/')) {
      return TouristSpotImageCatalog.normalizeAssetPath(raw);
    }
    return null;
  }

  Uint8List? _decodeDataUri(String url) {
    try {
      final comma = url.indexOf(',');
      if (comma < 0) return null;
      final meta = url.substring(0, comma).toLowerCase();
      final payload = url.substring(comma + 1);
      if (!meta.contains(';base64')) return null;
      return base64Decode(payload);
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadAsset() async {
    final url = _resolved;
    if (url.isEmpty) {
      if (mounted) setState(() => _failed = true);
      return;
    }
    if (url.startsWith('data:image')) {
      final decoded = _decodeDataUri(url);
      if (!mounted) return;
      setState(() {
        _bytes = decoded;
        _loadedKey = url;
        _failed = decoded == null;
      });
      return;
    }
    if (!kIsWeb || url.startsWith('http')) return;

    final assetPath = TouristSpotImageCatalog.normalizeAssetPath(url);
    final cached = _webCache[assetPath];
    if (cached != null) {
      if (!mounted) return;
      setState(() {
        _bytes = cached;
        _loadedKey = assetPath;
        _failed = false;
      });
      return;
    }

    try {
      final data = await rootBundle.load(assetPath);
      final bytes = data.buffer.asUint8List();
      _webCache[assetPath] = bytes;
      if (!mounted) return;
      setState(() {
        _bytes = bytes;
        _loadedKey = assetPath;
        _failed = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _bytes = null;
        _loadedKey = assetPath;
        _failed = true;
      });
    }
  }

  Widget _placeholder() {
    return Container(
      width: widget.width?.isFinite == true ? widget.width : null,
      height: widget.height?.isFinite == true ? widget.height : null,
      color: AppTheme.unselectedMuted.withValues(alpha: 0.15),
      alignment: Alignment.center,
      child: Icon(
        widget.placeholderIcon,
        color: AppTheme.unselectedMuted.withValues(alpha: 0.7),
        size: 32,
      ),
    );
  }

  Widget _wrap(Widget child) {
    if (widget.borderRadius == null) return child;
    return ClipRRect(borderRadius: widget.borderRadius!, child: child);
  }

  Widget _assetImage(String assetPath, {int? cacheWidth}) {
    return Image.asset(
      assetPath,
      width: widget.width?.isFinite == true ? widget.width : null,
      height: widget.height?.isFinite == true ? widget.height : null,
      fit: widget.fit,
      gaplessPlayback: true,
      cacheWidth: cacheWidth,
      errorBuilder: (_, __, ___) => _placeholder(),
    );
  }

  (int?, int?) _memCacheSize(BoxConstraints constraints, double dpr) {
    final w = (widget.width != null && widget.width!.isFinite)
        ? widget.width!
        : (constraints.maxWidth.isFinite ? constraints.maxWidth : null);
    final h = (widget.height != null && widget.height!.isFinite)
        ? widget.height!
        : (constraints.maxHeight.isFinite ? constraints.maxHeight : null);

    if (w != null && w > 0) {
      return ((w * dpr).round().clamp(64, 1400), null);
    }
    if (h != null && h > 0) {
      return (null, (h * dpr).round().clamp(64, 1400));
    }
    return ((420 * dpr).round().clamp(64, 1200), null);
  }

  Widget _networkImage(String url) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final dpr = MediaQuery.devicePixelRatioOf(context);
        final (memW, memH) = _memCacheSize(constraints, dpr);
        final localFallback = _localAssetFallback;

        return CachedNetworkImage(
          imageUrl: url,
          width: widget.width?.isFinite == true ? widget.width : null,
          height: widget.height?.isFinite == true ? widget.height : null,
          fit: widget.fit,
          fadeInDuration: const Duration(milliseconds: 160),
          fadeOutDuration: const Duration(milliseconds: 80),
          memCacheWidth: memW,
          memCacheHeight: memH,
          placeholder: (_, __) => _placeholder(),
          errorWidget: (_, __, ___) {
            if (localFallback != null &&
                !_preferLocalFallback &&
                SupabaseStorageConfig.keepLocalAsset(localFallback)) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) setState(() => _preferLocalFallback = true);
              });
              return _assetImage(localFallback, cacheWidth: memW);
            }
            return _placeholder();
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final url = _resolved;
    if (url.isEmpty || _failed) return _wrap(_placeholder());

    if (url.startsWith('data:image')) {
      if (_bytes != null && _loadedKey == url) {
        return _wrap(
          Image.memory(
            _bytes!,
            width: widget.width?.isFinite == true ? widget.width : null,
            height: widget.height?.isFinite == true ? widget.height : null,
            fit: widget.fit,
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) => _placeholder(),
          ),
        );
      }
      return _wrap(
        SizedBox(
          width: widget.width?.isFinite == true ? widget.width : null,
          height: widget.height?.isFinite == true ? widget.height : null,
          child: _placeholder(),
        ),
      );
    }

    final localFallback = _localAssetFallback;

    // Prefer remote URL; skip local asset fallback when photo is not bundled.
    if (_preferLocalFallback &&
        localFallback != null &&
        SupabaseStorageConfig.keepLocalAsset(localFallback)) {
      return _wrap(_assetImage(localFallback));
    }

    if (url.startsWith('http://') || url.startsWith('https://')) {
      return _wrap(_networkImage(url));
    }

    final assetPath = TouristSpotImageCatalog.normalizeAssetPath(url);

    if (kIsWeb) {
      if (_bytes != null && _loadedKey == assetPath) {
        return _wrap(
          Image.memory(
            _bytes!,
            width: widget.width?.isFinite == true ? widget.width : null,
            height: widget.height?.isFinite == true ? widget.height : null,
            fit: widget.fit,
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) => _placeholder(),
          ),
        );
      }
      return _wrap(
        SizedBox(
          width: widget.width?.isFinite == true ? widget.width : null,
          height: widget.height?.isFinite == true ? widget.height : null,
          child: _placeholder(),
        ),
      );
    }

    return _wrap(_assetImage(assetPath));
  }
}
