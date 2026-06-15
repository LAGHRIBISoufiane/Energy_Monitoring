import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/energy_data.dart';
import '../utils/energy_format.dart';

typedef EnergyPeriodSummary = ({
  double totalEnergy,
  double? firstEnergy,
  double? lastEnergy,
  int count,
});

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
    if (last != null && now.difference(last).inSeconds < _throttleSeconds) {
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
    } catch (e) {
      // Firestore writes are best-effort — never crash the UI
      // ignore: avoid_print
      print('[FirestoreLogService] write error for $unitId: $e');
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  Map<String, dynamic> _toFirestore(EnergyData d) {
    final dayKey =
        '${d.timestamp.year.toString().padLeft(4, '0')}-'
        '${d.timestamp.month.toString().padLeft(2, '0')}-'
        '${d.timestamp.day.toString().padLeft(2, '0')}';
    final monthKey =
        '${d.timestamp.year.toString().padLeft(4, '0')}-'
        '${d.timestamp.month.toString().padLeft(2, '0')}';
    final base = <String, dynamic>{
      'unitId': d.unitId,
      'timestamp': Timestamp.fromDate(d.timestamp),
      'dayKey': dayKey,
      'monthKey': monthKey,
      'voltage': d.voltage,
      'current': d.current,
      'powerFactor': d.powerFactor,
      'apparentPower': d.apparentPower,
      'reactivePower': d.reactivePower,
    };

    // Power and energy for all units
    base['power'] = d.power;
    // Store energy as mWh (internal unit) — consistent with all historical records
    base['energy'] = normalizeStoredEnergyMwh(d.energy, d.unitId);

    // AC-only fields (KOFERT_Unit_1 / PZEM)
    if (!d.isINA219) {
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
      query = query.where(
        'timestamp',
        isGreaterThanOrEqualTo: Timestamp.fromDate(from),
      );
    }
    if (to != null) {
      query = query.where(
        'timestamp',
        isLessThanOrEqualTo: Timestamp.fromDate(to),
      );
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
      for (final doc in snap.docs) doc.id: {'id': doc.id, ...doc.data()},
    };
  }

  /// Persist an alert event to the `alerts` Firestore collection.
  /// Called from DashboardScreen whenever a threshold alert fires.
  Future<void> logAlert({
    required String unitId,
    required String title,
    required String detail,
    required int colorValue,
  }) async {
    try {
      await _db.collection('alerts').add({
        'unitId': unitId,
        'title': title,
        'detail': detail,
        'colorValue': colorValue,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  /// Fetch the most recent [limit] alerts ordered by time, newest first.
  /// Optionally filter by [unitId].
  Future<List<Map<String, dynamic>>> getAlerts({
    String? unitId,
    int limit = 100,
  }) async {
    try {
      Query q = _db
          .collection('alerts')
          .orderBy('timestamp', descending: true)
          .limit(limit);
      if (unitId != null) q = q.where('unitId', isEqualTo: unitId);
      final snap = await q.get();
      return snap.docs
          .map((d) => {'id': d.id, ...d.data() as Map<String, dynamic>})
          .toList();
    } catch (_) {
      return [];
    }
  }

  // ── Persistent energy accumulator ─────────────────────────────────────────
  // Collection: energy_accumulators / {unitId}
  // Field:      totalWh  (double)  — accumulated Wh since installation

  final _lastEnergySave = <String, DateTime>{};

  /// Load the accumulated energy (Wh) for [unitId] from Firestore.
  /// Returns 0.0 if no record exists yet.
  Future<double> loadAccumulatedEnergy(String unitId) async {
    try {
      final doc = await _db.collection('energy_accumulators').doc(unitId).get();
      if (!doc.exists) return 0.0;
      return (doc.data()?['totalWh'] as num?)?.toDouble() ?? 0.0;
    } catch (_) {
      return 0.0;
    }
  }

  /// Persist [totalWh] for [unitId].  Throttled to one write every 30 s.
  Future<void> saveAccumulatedEnergy(String unitId, double totalWh) async {
    final now = DateTime.now();
    final last = _lastEnergySave[unitId];
    if (last != null && now.difference(last).inSeconds < 30) return;
    _lastEnergySave[unitId] = now;
    try {
      await _db.collection('energy_accumulators').doc(unitId).set({
        'totalWh': totalWh,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  /// Fetch the latest status snapshot for [unitId] from `unit_status`.
  Future<Map<String, dynamic>?> getUnitStatus(String unitId) async {
    try {
      final doc = await _db.collection('unit_status').doc(unitId).get();
      if (!doc.exists) return null;
      return {'id': doc.id, ...doc.data()!};
    } catch (_) {
      return null;
    }
  }

  /// First cumulative meter reading for the month, in mWh.
  ///
  /// The dashboard subtracts this from the live meter value so the displayed
  /// consumption resets automatically when a new month starts.
  Future<double?> getMonthStartEnergy(String unitId, DateTime month) async {
    final start = DateTime(month.year, month.month);
    final end = DateTime(month.year, month.month + 1);
    try {
      final snap = await _db
          .collection('sensor_readings')
          .where('unitId', isEqualTo: unitId)
          .where(
            'timestamp',
            isGreaterThanOrEqualTo: Timestamp.fromDate(start),
            isLessThan: Timestamp.fromDate(end),
          )
          .orderBy('timestamp', descending: false)
          .limit(1)
          .get();

      if (snap.docs.isEmpty) return null;
      final data = snap.docs.first.data();
      final rawEnergy = (data['energy'] as num?)?.toDouble();
      if (rawEnergy == null) return null;
      return normalizeStoredEnergyMwh(rawEnergy, unitId);
    } catch (_) {
      return null;
    }
  }

  /// Aggregate consumption between [start] and [end] from cumulative meter readings.
  Future<EnergyPeriodSummary> getPeriodEnergy(
    String unitId,
    DateTime start,
    DateTime end,
  ) async {
    try {
      final snap = await _db
          .collection('sensor_readings')
          .where('unitId', isEqualTo: unitId)
          .where(
            'timestamp',
            isGreaterThanOrEqualTo: Timestamp.fromDate(start),
            isLessThan: Timestamp.fromDate(end),
          )
          .orderBy('timestamp', descending: false)
          .get();

      double total = 0.0;
      double? firstEnergy;
      double? prevEnergy;
      double? lastEnergy;

      for (final doc in snap.docs) {
        final data = doc.data();
        final rawEnergy = (data['energy'] as num?)?.toDouble();
        if (rawEnergy == null) continue;

        final energy = normalizeStoredEnergyMwh(rawEnergy, unitId);
        firstEnergy ??= energy;
        if (prevEnergy != null) {
          total += sumPositiveEnergyDeltasMwh([prevEnergy, energy]);
        }
        prevEnergy = energy;
        lastEnergy = energy;
      }

      return (
        totalEnergy: total,
        firstEnergy: firstEnergy,
        lastEnergy: lastEnergy,
        count: snap.size,
      );
    } catch (_) {
      return (totalEnergy: 0.0, firstEnergy: null, lastEnergy: null, count: 0);
    }
  }

  /// Aggregate month-to-date consumption from cumulative meter readings.
  Future<EnergyPeriodSummary> getMonthEnergy(String unitId, DateTime month) {
    final start = DateTime(month.year, month.month);
    final end = DateTime(month.year, month.month + 1);
    return getPeriodEnergy(unitId, start, end);
  }

  /// Aggregate daily consumption for [unitId] on [day].
  Future<EnergyPeriodSummary> getDailyEnergy(String unitId, DateTime day) {
    // Use local midnight boundaries so "a day" matches Morocco clock (GMT+1).
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));
    return getPeriodEnergy(unitId, start, end);
  }
}
