/// Firestore history should store energy in mWh, but some older/live clients
/// wrote the raw ESP32 kWh value directly. Normalize those mixed records here.
double normalizeStoredEnergyMwh(double value, String unitId) {
  if (!value.isFinite || value <= 0) return 0.0;

  // Unit 1's PZEM meter reports kWh; its correct mWh values are normally
  // much larger than 1000 once the system has been running. Unit 2/3 are tiny
  // 5V loads, so use a tighter threshold to avoid changing valid mWh values.
  final looksLikeRawKwh =
      value < 10.0 || (unitId == 'KOFERT_Unit_1' && value < 1000.0);
  return looksLikeRawKwh ? value * 1000000.0 : value;
}

/// Returns a positive consumption delta from a cumulative meter.
///
/// Both values are mWh. A null/missing baseline or a meter reset returns 0 so
/// dashboards do not show old cumulative totals as current-period consumption.
double consumptionSinceBaselineMwh(double currentMwh, double? baselineMwh) {
  if (!currentMwh.isFinite || currentMwh <= 0) return 0.0;
  if (baselineMwh == null || !baselineMwh.isFinite || baselineMwh < 0) {
    return 0.0;
  }
  final delta = currentMwh - baselineMwh;
  return delta > 0 ? delta : 0.0;
}

/// Sums positive deltas from cumulative meter readings in chronological order.
///
/// Negative deltas are treated as meter/device resets and ignored. Very large
/// jumps are ignored as sensor spikes.
double sumPositiveEnergyDeltasMwh(
  Iterable<double> readings, {
  double maxDeltaMwh = 1e9,
}) {
  double total = 0.0;
  double? previous;
  for (final current in readings) {
    if (!current.isFinite) continue;
    if (previous != null) {
      final delta = current - previous;
      if (delta > 0 && delta < maxDeltaMwh) total += delta;
    }
    previous = current;
  }
  return total;
}

/// Combines persisted period consumption with the latest live meter.
///
/// [historyMwh] is already a consumption total for the requested period.
/// [lastLoggedMeterMwh] is the last cumulative meter value included in that
/// history. For session-like meters (Unit 2/3), [preferLiveWhenSparse] keeps
/// the UI from showing 0 after a refresh when Firestore has not yet collected
/// enough readings for the period.
double periodConsumptionWithLiveMwh({
  required double historyMwh,
  required double currentMeterMwh,
  double? lastLoggedMeterMwh,
  int historyReadings = 0,
  bool preferLiveWhenSparse = false,
}) {
  final safeHistory = historyMwh.isFinite && historyMwh > 0 ? historyMwh : 0.0;
  final liveDelta = consumptionSinceBaselineMwh(
    currentMeterMwh,
    lastLoggedMeterMwh,
  );
  final total = safeHistory + liveDelta;
  if (preferLiveWhenSparse &&
      historyReadings <= 1 &&
      total <= 0 &&
      currentMeterMwh.isFinite &&
      currentMeterMwh > 0) {
    return currentMeterMwh;
  }
  return total > 0 ? total : 0.0;
}

double monthAtLeastDayMwh(double monthMwh, double dayMwh) {
  final safeMonth = monthMwh.isFinite && monthMwh > 0 ? monthMwh : 0.0;
  final safeDay = dayMwh.isFinite && dayMwh > 0 ? dayMwh : 0.0;
  return safeMonth >= safeDay ? safeMonth : safeDay;
}

/// Backwards-compatible month helper used by dashboard code and tests.
double monthConsumptionWithLiveMwh({
  required double historyMwh,
  required double currentMeterMwh,
  double? lastLoggedMeterMwh,
  int historyReadings = 0,
  bool preferLiveWhenSparse = false,
}) {
  return periodConsumptionWithLiveMwh(
    historyMwh: historyMwh,
    currentMeterMwh: currentMeterMwh,
    lastLoggedMeterMwh: lastLoggedMeterMwh,
    historyReadings: historyReadings,
    preferLiveWhenSparse: preferLiveWhenSparse,
  );
}

/// Formats an energy value (stored in mWh) always as kWh.
///
/// Uses 2 decimals for values ≥ 1 kWh, 3 for ≥ 0.01, 4 for smaller values.
String fmtEnergy(double mwh) {
  final kwh = mwh / 1000000;
  if (kwh.abs() >= 1.0) return '${kwh.toStringAsFixed(2)} kWh';
  if (kwh.abs() >= 0.01) return '${kwh.toStringAsFixed(3)} kWh';
  if (kwh.abs() >= 0.001) return '${kwh.toStringAsFixed(4)} kWh';
  // Very small: show in mWh as fallback
  return '${mwh.toStringAsFixed(2)} mWh';
}

/// Same but with configurable decimal places.
String fmtEnergyN(double mwh, {int decimals = 3}) {
  final kwh = mwh / 1000000;
  if (kwh.abs() >= 0.001) return '${kwh.toStringAsFixed(decimals)} kWh';
  return '${mwh.toStringAsFixed(decimals)} mWh';
}

/// Convert mWh to display value in the given unit ('mWh', 'Wh', or 'kWh').
double mwhToUnit(double mwh, String unit) {
  switch (unit) {
    case 'mWh':
      return mwh;
    case 'Wh':
      return mwh / 1000.0;
    default:
      return mwh / 1000000.0; // kWh
  }
}

/// Format energy with the user's preferred unit. [mwh] is always in mWh.
String fmtEnergyUnit(double mwh, String unit) {
  switch (unit) {
    case 'mWh':
      return '${mwh.toStringAsFixed(0)} mWh';
    case 'Wh':
      {
        final wh = mwh / 1000.0;
        if (wh.abs() >= 100) return '${wh.toStringAsFixed(1)} Wh';
        if (wh.abs() >= 1) return '${wh.toStringAsFixed(2)} Wh';
        return '${wh.toStringAsFixed(3)} Wh';
      }
    default:
      {
        final kwh = mwh / 1000000.0;
        if (kwh.abs() >= 1.0) return '${kwh.toStringAsFixed(2)} kWh';
        if (kwh.abs() >= 0.01) return '${kwh.toStringAsFixed(3)} kWh';
        if (kwh.abs() >= 0.001) return '${kwh.toStringAsFixed(4)} kWh';
        return '${kwh.toStringAsFixed(6)} kWh'; // very small, always stay in kWh
      }
  }
}
