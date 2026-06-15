import 'dart:math' as math;
import '../utils/energy_format.dart';

class EnergyData {
  final double powerFactor;
  final double voltage;
  final double current;
  final double power;
  final double energy; // Internal unit: mWh.
  final double frequency;
  final double windSpeed; // fan speed % - only for KOFERT_Unit_2
  final int waterLevel; // 0-100 % - only for KOFERT_Unit_3
  final DateTime timestamp;
  final String unitId;

  EnergyData({
    required this.powerFactor,
    required this.voltage,
    required this.current,
    required this.power,
    required this.energy,
    required this.frequency,
    this.windSpeed = 0.0,
    this.waterLevel = 0,
    required this.timestamp,
    required this.unitId,
  });

  factory EnergyData.fromJson(Map<dynamic, dynamic> json, String unitId) {
    double n(dynamic v, [double fallback = 0.0]) {
      if (v == null || v == '') return fallback;
      return (v as num?)?.toDouble() ??
          double.tryParse(v.toString()) ??
          fallback;
    }

    DateTime parseTimestamp(dynamic raw) {
      if (raw == null) return DateTime.now();
      if (raw is int) {
        return (raw > 1000000000000
                ? DateTime.fromMillisecondsSinceEpoch(raw)
                : DateTime.fromMillisecondsSinceEpoch(raw * 1000))
            .toLocal();
      }
      if (raw is double) {
        final ms = raw.toInt();
        return (ms > 1000000000000
                ? DateTime.fromMillisecondsSinceEpoch(ms)
                : DateTime.fromMillisecondsSinceEpoch(ms * 1000))
            .toLocal();
      }
      if (raw is String) {
        final parsed = DateTime.tryParse(raw);
        if (parsed != null) return parsed.toLocal();
        final epoch = int.tryParse(raw);
        if (epoch != null) {
          return (epoch > 1000000000000
                  ? DateTime.fromMillisecondsSinceEpoch(epoch)
                  : DateTime.fromMillisecondsSinceEpoch(epoch * 1000))
              .toLocal();
        }
      }
      return DateTime.now();
    }

    final hasExplicitMwh = json.containsKey('energy_mwh');
    final isLocalCache =
        json.containsKey('unit_id') ||
        json.containsKey('apparent_power') ||
        json.containsKey('reactive_power');
    final rawEnergy = n(json['energy_mwh'] ?? json['energy'], 0.0);
    final energyMwh = hasExplicitMwh || isLocalCache
        ? normalizeStoredEnergyMwh(rawEnergy, unitId)
        : rawEnergy * 1000000.0; // RTDB/ESP32 reports kWh.

    var powerFactor = n(json['power_factor'] ?? json['powerFactor'], 0.0);
    final voltage = n(json['voltage'], 0.0);
    var current = n(json['current'], 0.0);
    var power = n(json['power'], 0.0);

    // On Unit 1, an open lamp switch should mean no load current. Only clamp
    // near-zero sensor noise; values like 4.8 W / 0.027 A are real readings
    // from the PZEM and must stay visible on the dashboard.
    final unit1LooksOff =
        unitId == 'KOFERT_Unit_1' &&
        (!power.isFinite || (power.abs() <= 0.5 && current.abs() <= 0.005));
    if (unit1LooksOff) {
      current = 0.0;
      power = 0.0;
      powerFactor = 0.0;
    }

    return EnergyData(
      powerFactor: powerFactor,
      voltage: voltage,
      current: current,
      power: power,
      energy: energyMwh,
      frequency: n(json['frequency'], 50.0),
      windSpeed: n(
        json['fan_speed'] ?? json['wind_speed'] ?? json['fanSpeed'],
        0.0,
      ),
      waterLevel:
          (json['water_level'] as num?)?.toInt() ??
          (json['waterLevel'] as num?)?.toInt() ??
          0,
      timestamp: parseTimestamp(json['timestamp']),
      unitId: unitId,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'power_factor': powerFactor,
      'voltage': voltage,
      'current': current,
      'power': power,
      'energy': energy / 1000000.0,
      'energy_mwh': energy,
      'frequency': frequency,
      'wind_speed': windSpeed,
      'water_level': waterLevel,
      'apparent_power': apparentPower,
      'reactive_power': reactivePower,
      'timestamp': timestamp.toIso8601String(),
      'unit_id': unitId,
    };
  }

  /// Apparent power in VA (S = V x I).
  double get apparentPower => voltage * current;

  /// True for units using INA219 (DC sensor - Unit 2: fan 5V, Unit 3: pump 5V).
  bool get isINA219 => unitId == 'KOFERT_Unit_2' || unitId == 'KOFERT_Unit_3';

  /// Reactive power in VAR (Q = sqrt(S^2 - P^2)).
  double get reactivePower {
    final s2 = apparentPower * apparentPower;
    final p2 = power * power;
    return s2 > p2 ? math.sqrt(s2 - p2) : 0.0;
  }

  bool get hasLowPowerFactor => powerFactor < 0.7 && powerFactor > 0;

  /// INA219 (5 V DC): alert if > 5.5 V. AC 220 V unit: alert if > 250 V.
  bool get hasHighVoltage => isINA219 ? voltage > 5.5 : voltage > 250;

  /// INA219 (5 V DC): alert if < 4.0 V. AC 220 V unit: alert if < 200 V.
  bool get hasLowVoltage => isINA219 ? voltage < 4.0 : voltage < 200;

  /// INA219 (5 V DC): alert if > 3 A. AC 220 V unit: alert if > 50 A.
  bool get hasHighCurrent => isINA219 ? current > 3.0 : current > 50;

  bool get hasHighReactivePower => reactivePower > 1000;

  bool get hasAlerts =>
      hasLowPowerFactor ||
      hasHighVoltage ||
      hasLowVoltage ||
      hasHighCurrent ||
      hasHighReactivePower;
}
