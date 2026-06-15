import 'dart:math' as math;
import '../models/energy_data.dart';

/// Result of an energy prediction run.
class PredictionResult {
  /// Estimated energy consumption for the next 24 h (mWh).
  final double nextDayEnergyMwh;

  /// Predicted cost for the next 24 h (local currency).
  final double nextDayCost;

  /// Predicted total cost by end of current month.
  final double monthEndCost;

  /// Cost already accumulated this month from available meter data.
  final double monthToDateCost;

  /// Whole days remaining in the current month.
  final int daysRemainingInMonth;

  /// Power factor predicted 10 minutes from now.
  final double predictedPf10min;

  /// Whether the predicted PF will fall below [pfThreshold] within 10 minutes.
  final bool pfWillDropBelow;

  /// Minutes until PF is expected to cross [pfThreshold] (null = won't drop).
  final double? minutesUntilPfDrop;

  /// Direction of the PF trend: 'rising', 'stable', 'falling'.
  final String pfTrend;

  /// Confidence 0-1 for cost prediction.
  final double costConfidence;

  /// Confidence 0-1 for PF prediction.
  final double pfConfidence;

  const PredictionResult({
    required this.nextDayEnergyMwh,
    required this.nextDayCost,
    required this.monthEndCost,
    required this.monthToDateCost,
    required this.daysRemainingInMonth,
    required this.predictedPf10min,
    required this.pfWillDropBelow,
    required this.minutesUntilPfDrop,
    required this.pfTrend,
    required this.costConfidence,
    required this.pfConfidence,
  });
}

class EnergyPredictor {
  /// Tariff in MAD/kWh.
  final double tariffRate;

  /// PF threshold below which an alert is triggered.
  final double pfThreshold;

  EnergyPredictor({this.tariffRate = 1.15, this.pfThreshold = 0.8});

  PredictionResult predict(List<EnergyData> data) {
    if (data.isEmpty) return _emptyResult();

    final sorted = List<EnergyData>.from(data)
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    final costResult = _predictCosts(sorted);
    final pfResult = _predictPowerFactor(sorted);

    return PredictionResult(
      nextDayEnergyMwh: costResult.nextDayEnergyMwh,
      nextDayCost: costResult.nextDayCost,
      monthEndCost: costResult.monthEndCost,
      monthToDateCost: costResult.monthToDateCost,
      daysRemainingInMonth: costResult.daysRemainingInMonth,
      predictedPf10min: pfResult.predictedPf10min,
      pfWillDropBelow: pfResult.pfWillDropBelow,
      minutesUntilPfDrop: pfResult.minutesUntilPfDrop,
      pfTrend: pfResult.pfTrend,
      costConfidence: costResult.confidence,
      pfConfidence: pfResult.confidence,
    );
  }

  _CostEstimate _predictCosts(List<EnergyData> sorted) {
    final now = DateTime.now();
    final startOfMonth = DateTime(now.year, now.month);
    final nextMonth = DateTime(now.year, now.month + 1);
    final remainingDaysExact = math.max(
      0.0,
      nextMonth.difference(now).inMinutes / 1440.0,
    );

    final byUnit = <String, List<EnergyData>>{};
    for (final d in sorted) {
      byUnit.putIfAbsent(d.unitId, () => <EnergyData>[]).add(d);
    }

    double nextDayEnergy = 0.0;
    double monthToDateEnergy = 0.0;
    double confidenceSum = 0.0;
    int unitsWithForecast = 0;

    for (final unitData in byUnit.values) {
      final clean = _dedupeBySecond(unitData);
      if (clean.length < 2) continue;

      final recent = _meterWindow(
        clean,
        from: now.subtract(const Duration(hours: 24)),
        to: now,
      );
      final fallback = _meterWindow(clean);
      final window = recent.isUseful ? recent : fallback;

      if (window.isUseful) {
        nextDayEnergy += window.energyPerDayMwh;
        confidenceSum += _costConfidence(window, clean.length);
        unitsWithForecast++;
      }

      final monthWindow = _meterWindow(clean, from: startOfMonth, to: now);
      monthToDateEnergy += monthWindow.energyMwh;
    }

    if (unitsWithForecast == 0) {
      final avgPower =
          sorted.fold(0.0, (s, d) => s + math.max(0.0, d.power)) /
          sorted.length;
      nextDayEnergy = avgPower * 24.0 * 1000.0;
      confidenceSum = 0.25;
      unitsWithForecast = 1;
    }

    final confidence = (confidenceSum / unitsWithForecast).clamp(0.0, 1.0);
    final nextDayCost = nextDayEnergy * tariffRate / 1000000.0;
    final monthToDateCost = monthToDateEnergy * tariffRate / 1000000.0;
    final monthEndEnergy =
        monthToDateEnergy + nextDayEnergy * remainingDaysExact;
    final monthEndCost = monthEndEnergy * tariffRate / 1000000.0;

    return _CostEstimate(
      nextDayEnergyMwh: nextDayEnergy,
      nextDayCost: nextDayCost,
      monthEndCost: monthEndCost,
      monthToDateCost: monthToDateCost,
      daysRemainingInMonth: remainingDaysExact.ceil(),
      confidence: confidence.toDouble(),
    );
  }

  _PfEstimate _predictPowerFactor(List<EnergyData> sorted) {
    final acData = sorted
        .where((e) => !e.isINA219 && e.powerFactor > 0 && e.powerFactor <= 1)
        .toList();

    if (acData.length < 3) {
      final pf = acData.isEmpty ? 1.0 : acData.last.powerFactor;
      return _PfEstimate(
        predictedPf10min: pf,
        pfWillDropBelow: pf < pfThreshold,
        minutesUntilPfDrop: pf < pfThreshold ? 0.0 : null,
        pfTrend: 'stable',
        confidence: acData.isEmpty ? 0.0 : 0.15,
      );
    }

    final recent = acData.length > 60
        ? acData.sublist(acData.length - 60)
        : acData;
    final start = recent.first.timestamp;
    final xs = recent
        .map((e) => e.timestamp.difference(start).inSeconds / 60.0)
        .toList();
    final ys = recent.map((e) => e.powerFactor).toList();

    if (xs.last <= 0) {
      return _PfEstimate(
        predictedPf10min: ys.last,
        pfWillDropBelow: ys.last < pfThreshold,
        minutesUntilPfDrop: ys.last < pfThreshold ? 0.0 : null,
        pfTrend: 'stable',
        confidence: 0.1,
      );
    }

    final reg = _linearRegression(xs, ys);
    final slope = reg['slope']!;
    final intercept = reg['intercept']!;
    final predicted = (slope * (xs.last + 10.0) + intercept)
        .clamp(0.0, 1.0)
        .toDouble();
    final current = ys.last;

    double? minutesUntilDrop;
    bool willDrop = predicted < pfThreshold || current < pfThreshold;
    if (current < pfThreshold) {
      minutesUntilDrop = 0.0;
    } else if (slope < 0) {
      final minutes = (pfThreshold - current) / slope;
      if (minutes > 0 && minutes <= 10.0) {
        minutesUntilDrop = minutes;
        willDrop = true;
      }
    }

    String trend;
    if (slope > 0.0002) {
      trend = 'rising';
    } else if (slope < -0.0002) {
      trend = 'falling';
    } else {
      trend = 'stable';
    }

    final r2 = _rSquared(xs, ys, slope, intercept).clamp(0.0, 1.0);
    final sampleFactor = math.min(1.0, recent.length / 30.0);

    return _PfEstimate(
      predictedPf10min: predicted,
      pfWillDropBelow: willDrop,
      minutesUntilPfDrop: minutesUntilDrop,
      pfTrend: trend,
      confidence: (r2 * sampleFactor).toDouble(),
    );
  }

  List<EnergyData> _dedupeBySecond(List<EnergyData> data) {
    final bySecond = <int, EnergyData>{};
    for (final d in data) {
      final key = d.timestamp.millisecondsSinceEpoch ~/ 1000;
      final existing = bySecond[key];
      if (existing == null || d.energy >= existing.energy) {
        bySecond[key] = d;
      }
    }
    return bySecond.values.toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  }

  _EnergyWindow _meterWindow(
    List<EnergyData> data, {
    DateTime? from,
    DateTime? to,
  }) {
    final points = data.where((d) {
      if (from != null && d.timestamp.isBefore(from)) return false;
      if (to != null && d.timestamp.isAfter(to)) return false;
      return true;
    }).toList()..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    if (points.length < 2) return const _EnergyWindow.empty();

    double meterDeltaEnergy = 0.0;
    double integratedEnergy = 0.0;
    DateTime? first;
    DateTime? last;

    for (int i = 1; i < points.length; i++) {
      final prev = points[i - 1];
      final curr = points[i];
      final dtHours =
          curr.timestamp.difference(prev.timestamp).inSeconds / 3600.0;
      if (dtHours <= 0) continue;

      first ??= prev.timestamp;
      last = curr.timestamp;

      final delta = curr.energy - prev.energy;
      if (delta > 0 && delta < 1000000000.0) {
        meterDeltaEnergy += delta;
      }

      final avgPower = math.max(0.0, (prev.power + curr.power) / 2.0);
      if (avgPower > 0 && dtHours <= 0.5) {
        integratedEnergy += avgPower * dtHours * 1000.0;
      }
    }

    if (first == null || last == null) return const _EnergyWindow.empty();

    final spanHours = last.difference(first).inSeconds / 3600.0;
    if (spanHours <= 0) return const _EnergyWindow.empty();

    // Prefer the cumulative meter. If it has not advanced yet because the
    // period is short or the sensor rounds energy, use power integration.
    final energy = meterDeltaEnergy > 0 ? meterDeltaEnergy : integratedEnergy;

    return _EnergyWindow(
      energyMwh: energy,
      spanHours: spanHours,
      samples: points.length,
    );
  }

  double _costConfidence(_EnergyWindow window, int sampleCount) {
    if (!window.isUseful) return 0.0;
    final coverageFactor = math.min(1.0, window.spanHours / 24.0);
    final sampleFactor = math.min(1.0, sampleCount / 120.0);
    return (0.15 + 0.65 * coverageFactor + 0.20 * sampleFactor)
        .clamp(0.0, 1.0)
        .toDouble();
  }

  Map<String, double> _linearRegression(List<double> xs, List<double> ys) {
    final n = xs.length;
    double sumX = 0, sumY = 0, sumXY = 0, sumX2 = 0;
    for (int i = 0; i < n; i++) {
      sumX += xs[i];
      sumY += ys[i];
      sumXY += xs[i] * ys[i];
      sumX2 += xs[i] * xs[i];
    }
    final denom = n * sumX2 - sumX * sumX;
    if (denom == 0) return {'slope': 0, 'intercept': sumY / n};
    final slope = (n * sumXY - sumX * sumY) / denom;
    final intercept = (sumY - slope * sumX) / n;
    return {'slope': slope, 'intercept': intercept};
  }

  double _rSquared(
    List<double> xs,
    List<double> ys,
    double slope,
    double intercept,
  ) {
    final mean = ys.reduce((a, b) => a + b) / ys.length;
    double ssTot = 0, ssRes = 0;
    for (int i = 0; i < xs.length; i++) {
      final predicted = slope * xs[i] + intercept;
      ssRes += math.pow(ys[i] - predicted, 2);
      ssTot += math.pow(ys[i] - mean, 2);
    }
    return ssTot == 0 ? 0 : 1 - ssRes / ssTot;
  }

  static int _daysInMonth(int year, int month) {
    return DateTime(year, month + 1, 0).day;
  }

  PredictionResult _emptyResult() {
    final now = DateTime.now();
    final remaining = _daysInMonth(now.year, now.month) - now.day;
    return PredictionResult(
      nextDayEnergyMwh: 0,
      nextDayCost: 0,
      monthEndCost: 0,
      monthToDateCost: 0,
      daysRemainingInMonth: remaining,
      predictedPf10min: 0,
      pfWillDropBelow: false,
      minutesUntilPfDrop: null,
      pfTrend: 'stable',
      costConfidence: 0,
      pfConfidence: 0,
    );
  }
}

class _EnergyWindow {
  final double energyMwh;
  final double spanHours;
  final int samples;

  const _EnergyWindow({
    required this.energyMwh,
    required this.spanHours,
    required this.samples,
  });

  const _EnergyWindow.empty() : energyMwh = 0, spanHours = 0, samples = 0;

  bool get isUseful => samples >= 2 && spanHours > 0 && energyMwh >= 0;

  double get energyPerDayMwh =>
      spanHours > 0 ? energyMwh / spanHours * 24.0 : 0.0;
}

class _CostEstimate {
  final double nextDayEnergyMwh;
  final double nextDayCost;
  final double monthEndCost;
  final double monthToDateCost;
  final int daysRemainingInMonth;
  final double confidence;

  const _CostEstimate({
    required this.nextDayEnergyMwh,
    required this.nextDayCost,
    required this.monthEndCost,
    required this.monthToDateCost,
    required this.daysRemainingInMonth,
    required this.confidence,
  });
}

class _PfEstimate {
  final double predictedPf10min;
  final bool pfWillDropBelow;
  final double? minutesUntilPfDrop;
  final String pfTrend;
  final double confidence;

  const _PfEstimate({
    required this.predictedPf10min,
    required this.pfWillDropBelow,
    required this.minutesUntilPfDrop,
    required this.pfTrend,
    required this.confidence,
  });
}
