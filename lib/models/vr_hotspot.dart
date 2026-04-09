import 'package:flutter/material.dart';

/// Simple model representing a clickable hotspot inside a 360° VR scene.
///
/// Positions are expressed as relative values in the \[0, 1\] range where:
/// - 0 = left or top edge of the visible area
/// - 1 = right or bottom edge of the visible area
class VRHotspot {
  const VRHotspot({
    required this.id,
    required this.title,
    required this.description,
    required this.position,
    this.icon,
  });

  /// Stable id so we can track or log interactions later.
  final String id;

  /// Short label shown in the popup/info card.
  final String title;

  /// Richer description text for the hotspot.
  final String description;

  /// Relative position within the viewport (left/top as 0–1).
  final Offset position;

  /// Optional icon for the hotspot button.
  final IconData? icon;
}

