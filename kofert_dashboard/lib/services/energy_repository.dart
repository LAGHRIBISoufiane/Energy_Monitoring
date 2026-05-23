import 'dart:convert';
import 'package:firebase_database/firebase_database.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/energy_data.dart';

/// Singleton repository — wraps Firebase Realtime DB with a SharedPreferences
/// cache so the app can display the last known reading when offline.
class EnergyRepository {
  EnergyRepository._();
  static final instance = EnergyRepository._();

  static const _cachePrefix = 'cache_last_reading_';

  // ── Real-time stream ────────────────────────────────────────────────────────

  /// Returns a broadcast stream of live metrics for [unitId].
  /// Every successful emission is also persisted to the local cache.
  Stream<EnergyData?> currentMetrics(String unitId) {
    return FirebaseDatabase.instance
        .ref('$unitId/current_metrics')
        .onValue
        .map((event) {
      if (event.snapshot.value == null) return null;
      try {
        final data = EnergyData.fromJson(
          event.snapshot.value as Map<dynamic, dynamic>,
          unitId,
        );
        _saveCache(unitId, data); // fire-and-forget
        return data;
      } catch (_) {
        return null;
      }
    });
  }

  // ── Historical fetch ────────────────────────────────────────────────────────

  /// Fetches up to [limit] historical records for [unitId], sorted ascending.
  Future<List<EnergyData>> getHistoricalData(
    String unitId, {
    int limit = 500,
  }) async {
    final snapshot = await FirebaseDatabase.instance
        .ref('$unitId/historical_data')
        .limitToLast(limit)
        .get();

    if (!snapshot.exists) return [];

    final raw = snapshot.value as Map<dynamic, dynamic>;
    final list = <EnergyData>[];
    raw.forEach((key, value) {
      if (value is Map<dynamic, dynamic>) {
        try {
          list.add(EnergyData.fromJson(value, unitId));
        } catch (_) {}
      }
    });
    list.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return list;
  }

  // ── Cache ───────────────────────────────────────────────────────────────────

  Future<void> _saveCache(String unitId, EnergyData data) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _cachePrefix + unitId,
        jsonEncode(data.toJson()),
      );
    } catch (_) {}
  }

  /// Returns the last cached [EnergyData] for [unitId], or null if none exists.
  Future<EnergyData?> getCachedReading(String unitId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cachePrefix + unitId);
      if (raw == null) return null;
      final map = (jsonDecode(raw) as Map).cast<String, dynamic>();
      return EnergyData.fromJson(map, unitId);
    } catch (_) {
      return null;
    }
  }
}
