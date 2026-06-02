/// Formats an energy value (stored in mWh) always as kWh.
///
/// Uses 2 decimals for values ≥ 1 kWh, 3 for ≥ 0.01, 4 for smaller values.
String fmtEnergy(double mwh) {
  final kwh = mwh / 1000000;
  if (kwh.abs() >= 1.0)    return '${kwh.toStringAsFixed(2)} kWh';
  if (kwh.abs() >= 0.01)   return '${kwh.toStringAsFixed(3)} kWh';
  if (kwh.abs() >= 0.001)  return '${kwh.toStringAsFixed(4)} kWh';
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
    case 'mWh': return mwh;
    case 'Wh':  return mwh / 1000.0;
    default:    return mwh / 1000000.0; // kWh
  }
}

/// Format energy with the user's preferred unit. [mwh] is always in mWh.
String fmtEnergyUnit(double mwh, String unit) {
  switch (unit) {
    case 'mWh':
      return '${mwh.toStringAsFixed(0)} mWh';
    case 'Wh': {
      final wh = mwh / 1000.0;
      if (wh.abs() >= 100) return '${wh.toStringAsFixed(1)} Wh';
      if (wh.abs() >= 1)   return '${wh.toStringAsFixed(2)} Wh';
      return '${wh.toStringAsFixed(3)} Wh';
    }
    default: {
      final kwh = mwh / 1000000.0;
      if (kwh.abs() >= 1.0)    return '${kwh.toStringAsFixed(2)} kWh';
      if (kwh.abs() >= 0.01)   return '${kwh.toStringAsFixed(3)} kWh';
      if (kwh.abs() >= 0.001)  return '${kwh.toStringAsFixed(4)} kWh';
      return '${kwh.toStringAsFixed(6)} kWh'; // very small, always stay in kWh
    }
  }
}
