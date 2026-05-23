import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/energy_data.dart';

/// Persists sensor readings from the Realtime Database into Firestore.
///
/// Collections written:
///  • `sensor_readings/{auto-id}` — append-only time-series (1 doc/min per unit)
///  • `unit_status/{unitId}`      — always-current latest snapshot per unit
///
/// The service throttles writes to **one Firestore write per unit per 60 s**
/// so it doesn't fan out into expensive writes every second.
class FirestoreLogService {
  FirestoreLogService._();
  static final instance = FirestoreLogService._();

  static const _throttleSeconds = 60;

  final _lastWrite = <String, DateTime>{};

  final _db = FirebaseFirestore.instance;

  /// Log [data] for [unitId].  Returns without doing anything if the previous
  /// write for this unit was less than [_throttleSeconds] ago.
  Future<void> logReading(EnergyData data) async {
    final unitId = data.unitId;
    final now = DateTime.now();

    final last = _lastWrite[unitId];
    if (last != null &&
        now.difference(last).inSeconds < _throttleSeconds) {
      return; // throttled
    }
    _lastWrite[unitId] = now;

    final payload = _toFirestore(data);

    try {
      final batch = _db.batch();

      // ── 1. Append to time-series collection ───────────────────────────────
      final readingRef = _db.collection('sensor_readings').doc();
      batch.set(readingRef, {
        ...payload,
        'loggedAt': FieldValue.serverTimestamp(),
      });

      // ── 2. Upsert latest-status document ─────────────────────────────────
      final statusRef = _db.collection('unit_status').doc(unitId);
      batch.set(statusRef, {
        ...payload,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      await batch.commit();
    } catch (_) {
      // Firestore writes are best-effort — never crash the UI
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  Map<String, dynamic> _toFirestore(EnergyData d) {
    final base = <String, dynamic>{
      'unitId': d.unitId,
      'timestamp': Timestamp.fromDate(d.timestamp),
      'voltage': d.voltage,
      'current': d.current,
      'powerFactor': d.powerFactor,
      'apparentPower': d.apparentPower,
      'reactivePower': d.reactivePower,
    };

    // AC-only fields (KOFERT_Unit_1 / PZEM)
    if (!d.isINA219) {
      base['power'] = d.power;
      base['energy'] = d.energy;
      base['frequency'] = d.frequency;
    }

    // DC units
    if (d.isINA219) {
      if (d.unitId == 'KOFERT_Unit_2') {
        base['fanSpeed'] = d.windSpeed;
      }
      if (d.unitId == 'KOFERT_Unit_3') {
        base['waterLevel'] = d.waterLevel;
      }
    }

    return base;
  }

  // ── Query helpers (used by SummaryScreen / HistoricalScreen) ───────────────

  /// Returns the last [limit] readings for [unitId], newest first.
  Future<List<Map<String, dynamic>>> getReadings(
    String unitId, {
    int limit = 100,
    DateTime? from,
    DateTime? to,
  }) async {
    Query query = _db
        .collection('sensor_readings')
        .where('unitId', isEqualTo: unitId)
        .orderBy('timestamp', descending: true);

    if (from != null) {
      query = query.where('timestamp',
          isGreaterThanOrEqualTo: Timestamp.fromDate(from));
    }
    if (to != null) {
      query =
          query.where('timestamp', isLessThanOrEqualTo: Timestamp.fromDate(to));
    }

    query = query.limit(limit);

    final snap = await query.get();
    return snap.docs
        .map((d) => {'id': d.id, ...d.data() as Map<String, dynamic>})
        .toList();
  }

  /// Returns the latest snapshot for every unit, keyed by unitId.
  Future<Map<String, Map<String, dynamic>>> getAllUnitStatuses() async {
    final snap = await _db.collection('unit_status').get();
    return {
      for (final doc in snap.docs)
        doc.id: {'id': doc.id, ...doc.data()},
    };
  }

  /// Aggregate daily energy for [unitId] on [day] (UTC date).
  /// Returns total energy (kWh sum of `energy` field) and reading count.
  Future<({double totalEnergy, int count})> getDailyEnergy(
      String unitId, DateTime day) async {
    // Use local midnight boundaries so "a day" matches Morocco clock (GMT+1).
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));

    final snap = await _db
        .collection('sensor_readings')
        .where('unitId', isEqualTo: unitId)
        .where('timestamp',
            isGreaterThanOrEqualTo: Timestamp.fromDate(start),
            isLessThan: Timestamp.fromDate(end))
        .get();

    double total = 0;
    for (final doc in snap.docs) {
      total += (doc.data()['energy'] as num?)?.toDouble() ?? 0;
    }
    return (totalEnergy: total, count: snap.size);
  }
}
