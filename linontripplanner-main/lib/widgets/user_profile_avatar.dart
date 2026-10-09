import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:flutter/material.dart';

import '../data.dart';
import '../services/profile_photo_service.dart';
import 'municipality_image.dart';

String _lookupId(AppUser user) =>
    user.profilePhotoLookupId.trim().isNotEmpty
        ? user.profilePhotoLookupId.trim()
        : user.id;

Widget _networkAvatar(String url, double size, Widget fallback) {
  final px = (size * 3).round().clamp(96, 320);
  return CachedNetworkImage(
    imageUrl: url,
    width: size,
    height: size,
    fit: BoxFit.cover,
    memCacheWidth: px,
    memCacheHeight: px,
    maxWidthDiskCache: px,
    maxHeightDiskCache: px,
    fadeInDuration: Duration.zero,
    fadeOutDuration: Duration.zero,
    filterQuality: FilterQuality.medium,
    placeholder: (context, url) => fallback,
    errorWidget: (context, url, error) => fallback,
  );
}

/// Avatar for admin user rows: Firestore URL, then Storage lookup folders.
Widget buildUserListAvatar(AppUser user, {double size = 48}) {
  final fallbackInner = Container(
    color: AppColors.primary.withOpacity(0.15),
    alignment: Alignment.center,
    child: Icon(Icons.person, color: AppColors.primary, size: size * 0.45),
  );

  final src = user.profilePhotoPath.trim();
  if (src.isNotEmpty) {
    final px = (size * 3).round().clamp(96, 320);
    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: buildMunicipalityImage(
          src,
          fallback: fallbackInner,
          memCacheWidth: px,
          memCacheHeight: px,
        ),
      ),
    );
  }

  return ClipOval(
    child: SizedBox(
      width: size,
      height: size,
      child: FutureBuilder<String?>(
        future: resolveProfilePhotoUrlForLookupId(_lookupId(user)),
        builder: (context, snap) {
          final url = snap.data;
          if (url == null || url.isEmpty) return fallbackInner;
          return _networkAvatar(url, size, fallbackInner);
        },
      ),
    ),
  );
}

Widget _fallbackAvatar(double size) => Container(
      color: AppColors.primary.withOpacity(0.15),
      alignment: Alignment.center,
      child: Icon(Icons.person, color: AppColors.primary, size: size * 0.45),
    );

/// Profile tab header: Firestore URL → Auth photoURL → Storage folders.
Widget buildProfileHeaderAvatar({
  required firebase_auth.User? authUser,
  AppUser? appUser,
  double size = 88,
}) {
  final firestorePath = appUser?.profilePhotoPath.trim() ?? '';
  if (firestorePath.isNotEmpty) {
    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: buildMunicipalityImage(
          firestorePath,
          fallback: _fallbackAvatar(size),
        ),
      ),
    );
  }

  final authUrl = authUser?.photoURL?.trim() ?? '';
  if (authUrl.isNotEmpty) {
    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: buildMunicipalityImage(authUrl, fallback: _fallbackAvatar(size)),
      ),
    );
  }

  final lookupId = appUser != null
      ? _lookupId(appUser)
      : (authUser?.uid.trim() ?? '');

  if (lookupId.isEmpty) {
    return ClipOval(
      child: SizedBox(width: size, height: size, child: _fallbackAvatar(size)),
    );
  }

  return ClipOval(
    child: SizedBox(
      width: size,
      height: size,
      child: FutureBuilder<String?>(
        future: resolveProfilePhotoUrlForLookupId(lookupId),
        builder: (context, snap) {
          final url = snap.data;
          if (url == null || url.isEmpty) return _fallbackAvatar(size);
          return _networkAvatar(url, size, _fallbackAvatar(size));
        },
      ),
    ),
  );
}

/// Avatar for a spot review row (photo path, then uid Storage lookup).
Widget buildReviewerAvatar({
  required String userId,
  required String profilePhotoPath,
  double size = 44,
}) {
  final path = profilePhotoPath.trim();
  if (path.isNotEmpty) {
    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: buildMunicipalityImage(
          path,
          fallback: _fallbackAvatar(size),
        ),
      ),
    );
  }

  final appUser = findAppUserByFirebaseUid(userId);
  if (appUser != null) {
    return buildUserListAvatar(appUser, size: size);
  }

  final id = userId.trim();
  if (id.isEmpty) {
    return ClipOval(
      child: SizedBox(width: size, height: size, child: _fallbackAvatar(size)),
    );
  }

  return ClipOval(
    child: SizedBox(
      width: size,
      height: size,
      child: FutureBuilder<String?>(
        future: resolveProfilePhotoUrlForLookupId(id),
        builder: (context, snap) {
          final url = snap.data;
          if (url == null || url.isEmpty) return _fallbackAvatar(size);
          return _networkAvatar(url, size, _fallbackAvatar(size));
        },
      ),
    ),
  );
}
