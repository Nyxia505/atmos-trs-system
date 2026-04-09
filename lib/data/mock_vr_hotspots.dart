import 'package:flutter/material.dart';
import 'package:atmos_trs_system/models/vr_hotspot.dart';

/// Mock VR hotspots for prototype VR tours.
///
/// Keys correspond to VR-enabled tourist spot ids. Oroquieta City Capitol uses `oro-2`.
final Map<String, List<VRHotspot>> kMockVRHotspots = {
  // Oroquieta City Capitol – prototype with 3 clickable hotspot points.
  'oro-2': [
    VRHotspot(
      id: 'oro2-center-gazebo',
      title: 'Central Gazebo',
      description:
          'The heart of the capitol grounds, often used for community events, ceremonies, and weekend performances.',
      position: const Offset(0.52, 0.55),
      icon: Icons.park,
    ),
    VRHotspot(
      id: 'oro2-play-area',
      title: 'Family Play Area',
      description:
          'Playground and open green space where families gather in the late afternoon. A favorite spot for kids.',
      position: const Offset(0.28, 0.62),
      icon: Icons.family_restroom,
    ),
    VRHotspot(
      id: 'oro2-bay-view',
      title: 'Bay View Side',
      description:
          'Walk towards this side to enjoy the cool breeze and sunset views over Panguil Bay from the capitol grounds.',
      position: const Offset(0.72, 0.50),
      icon: Icons.waves,
    ),
  ],
};

