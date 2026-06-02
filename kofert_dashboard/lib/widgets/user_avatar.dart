import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../main.dart' show kTeal;

// ─────────────────────────────────────────────────────────────────────────────
// In-memory cache so each user's Firestore doc is fetched at most once per
// session. Key = uid, value = Firestore data map (null = confirmed not found).
// ─────────────────────────────────────────────────────────────────────────────
class _AvatarCache {
  _AvatarCache._();
  static final _cache = <String, Map<String, dynamic>?>{};

  /// Returns the cached data map (may be null if the user doc doesn't exist).
  /// On first call for a uid it fetches from Firestore then caches the result.
  static Future<Map<String, dynamic>?> fetch(String uid) async {
    if (_cache.containsKey(uid)) return _cache[uid];
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      _cache[uid] = doc.exists ? doc.data() : null;
    } catch (_) {
      _cache[uid] = null;
    }
    return _cache[uid];
  }

  /// Force-refreshes a single uid (call after the current user saves profile).
  static void invalidate(String uid) => _cache.remove(uid);
}

// Same color palette as ProfileScreen so avatars look consistent everywhere.
const _kAvatarColors = [
  Color(0xFF4ECDC4), Color(0xFFF5A623), Color(0xFFE74C3C),
  Color(0xFF9B59B6), Color(0xFF3498DB), Color(0xFF2ECC71),
  Color(0xFFFF6B8A), Color(0xFF1ABC9C),
];

// ─────────────────────────────────────────────────────────────────────────────
// Public widget
// ─────────────────────────────────────────────────────────────────────────────

/// Renders a user's profile picture (or coloured initials as fallback).
/// Fetches data from Firestore once per session and caches it.
///
/// [uid]          – Firestore users document ID.
/// [fallbackName] – Used for initials if the Firestore doc hasn't loaded yet
///                  or has no name.
/// [radius]       – Circle radius (default 18).
class UserAvatar extends StatelessWidget {
  final String uid;
  final String fallbackName;
  final double radius;

  const UserAvatar({
    required this.uid,
    this.fallbackName = '',
    this.radius = 18,
    super.key,
  });

  /// Call this after the current user updates their profile so other widgets
  /// that already rendered will re-fetch the latest avatar on next build.
  static void invalidateCache(String uid) => _AvatarCache.invalidate(uid);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: _AvatarCache.fetch(uid),
      builder: (context, snap) {
        final data = snap.data;

        // ── Resolve avatar image ──────────────────────────────────────────
        Uint8List? imageBytes;
        if (data != null && data['avatarImageBase64'] is String) {
          try {
            imageBytes = base64Decode(data['avatarImageBase64'] as String);
          } catch (_) {}
        }

        // ── Resolve background colour ─────────────────────────────────────
        Color bgColor;
        if (imageBytes != null) {
          bgColor = Colors.transparent;
        } else if (data != null) {
          final idx = (data['avatarColorIdx'] as int?) ?? 0;
          bgColor = _kAvatarColors[idx.clamp(0, _kAvatarColors.length - 1)];
        } else {
          bgColor = kTeal.withValues(alpha: 0.25);
        }

        // ── Resolve initials ─────────────────────────────────────────────
        final String displayName;
        if (data != null) {
          final first = (data['firstName'] as String? ?? '').trim();
          final last  = (data['lastName']  as String? ?? '').trim();
          displayName = '$first $last'.trim().isNotEmpty
              ? '$first $last'.trim()
              : (data['displayName'] as String? ?? fallbackName);
        } else {
          displayName = fallbackName;
        }

        final initials = _initials(displayName);
        final textSize = radius * 0.58;

        return CircleAvatar(
          radius: radius,
          backgroundColor: bgColor,
          backgroundImage:
              imageBytes != null ? MemoryImage(imageBytes) : null,
          child: imageBytes == null
              ? Text(
                  initials,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: textSize,
                  ),
                )
              : null,
        );
      },
    );
  }

  static String _initials(String name) {
    if (name.isEmpty) return '?';
    final parts = name.trim().split(' ');
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return (parts[0][0] + parts.last[0]).toUpperCase();
  }
}
