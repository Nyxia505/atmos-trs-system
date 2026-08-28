import 'package:atmos_trs_system/config/app_theme.dart';
import 'package:atmos_trs_system/data/tourist_spot_image_catalog.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Reliable spot/municipality image loader (fixes Flutter web space-encoding 404s).
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
      _loadedKey = null;
      _loadAsset();
    }
  }

  String get _resolved {
    final raw = (widget.imageUrl ?? '').trim();
    if (raw.startsWith('http://') ||
        raw.startsWith('https://') ||
        raw.startsWith('assets/')) {
      return TouristSpotImageCatalog.normalizeAssetPath(raw);
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

  Future<void> _loadAsset() async {
    final url = _resolved;
    if (url.isEmpty) {
      if (mounted) setState(() => _failed = true);
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
      width: widget.width,
      height: widget.height,
      color: AppTheme.unselectedMuted.withValues(alpha: 0.15),
      alignment: Alignment.center,
      child: Icon(
        widget.placeholderIcon,
        color: AppTheme.unselectedMuted.withValues(alpha: 0.7),
        size: widget.width != null && widget.height != null
            ? (widget.width! < widget.height!
                    ? widget.width!
                    : widget.height!) *
                0.42
            : 32,
      ),
    );
  }

  Widget _wrap(Widget child) {
    if (widget.borderRadius == null) return child;
    return ClipRRect(borderRadius: widget.borderRadius!, child: child);
  }

  @override
  Widget build(BuildContext context) {
    final url = _resolved;
    if (url.isEmpty || _failed) return _wrap(_placeholder());

    if (url.startsWith('http://') || url.startsWith('https://')) {
      return _wrap(
        Image.network(
          url,
          width: widget.width,
          height: widget.height,
          fit: widget.fit,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => _placeholder(),
        ),
      );
    }

    final assetPath = TouristSpotImageCatalog.normalizeAssetPath(url);

    if (kIsWeb) {
      if (_bytes != null && _loadedKey == assetPath) {
        return _wrap(
          Image.memory(
            _bytes!,
            width: widget.width,
            height: widget.height,
            fit: widget.fit,
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) => _placeholder(),
          ),
        );
      }
      return _wrap(
        SizedBox(
          width: widget.width,
          height: widget.height,
          child: _placeholder(),
        ),
      );
    }

    return _wrap(
      Image.asset(
        assetPath,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => _placeholder(),
      ),
    );
  }
}
