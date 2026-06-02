import 'dart:math' as math;
import '../models/energy_data.dart';

/// Result of an AI prediction run.
class PredictionResult {
  /// Estimated energy consumption for the next 24 h (mWh).
  final double nextDayEnergyMwh;

  /// Predicted cost for the next 24 h (local currency).
  final double nextDayCost;

  /// Predicted total cost by end of current month.
  final double monthEndCost;

  /// Cost already accumulated this month (estimate).
  final double monthToDateCost;

  /// Days remaining in the current month.
  final int daysRemainingInMonth;

  /// Power factor predicted 10 minutes from now.
  final double predictedPf10min;

  /// Whether the predicted PF will fall below [pfThreshold] within 10 minutes.
  final bool pfWillDropBelow;

  /// Minutes until PF is expected to cross [pfThreshold] (null = won't drop).
  final double? minutesUntilPfDrop;

  /// Direction of the PF trend: 'rising', 'stable', 'falling'.
  final String pfTrend;

  /// Confidence 0–1 for cost prediction (based on data density).
  final double costConfidence;

  /// Confidence 0–1 for PF prediction.
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
  /// Tariff in MAD/mWh.
  final double tariffRate;

  /// PF threshold below which an alert is triggered.
  final double pfThreshold;

  /// Assumed sampling interval in seconds when timestamps are unreliable.
  static const double _assumedIntervalSeconds = 30.0;

  EnergyPredictor({this.tariffRate = 1.15, this.pfThreshold = 0.8});

  // ── Public entry point ─────────────────────────────────────────────────────

  PredictionResult predict(List<EnergyData> data) {
    if (data.isEmpty) return _emptyResult();

    // Sort by timestamp (ascending).
    final sorted = List<EnergyData>.from(data)
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    // ── 1. Cost predictions ──────────────────────────────────────────────────
    final costResult = _predictCosts(sorted);

    // ── 2. Power factor prediction ───────────────────────────────────────────
    final pfResult = _predictPowerFactor(sorted);

    return PredictionResult(
      nextDayEnergyMwh: costResult['nextDayEnergy'] as double,
      nextDayCost: costResult['nextDayCost'] as double,
      monthEndCost: costResult['monthEndCost'] as double,
      monthToDateCost: costResult['monthToDateCost'] as double,
      daysRemainingInMonth: costResult['daysRemaining'] as int,
      predictedPf10min: pfResult['predicted'] as double,
      pfWillDropBelow: pfResult['willDrop'] as bool,
      minutesUntilPfDrop: pfResult['minutesUntilDrop'] as double?,
      pfTrend: pfResult['trend'] as String,
      costConfidence: costResult['confidence'] as double,
      pfConfidence: pfResult['confidence'] as double,
    );
  }

  // ── Cost prediction ────────────────────────────────────────────────────────

  Map<String, dynamic> _predictCosts(List<EnergyData> sorted) {
    final now = DateTime.now();
    final daysInMonth = _daysInMonth(now.year, now.month);
    final daysRemaining = daysInMonth - now.day;

    // Estimate average power (W) from all readings.
    final avgPower = sorted.map((e) => e.power).reduce((a, b) => a + b) /
        sorted.length;

    // Estimate daily energy using linear regression on power values to
    // capture any daily trend.
    double dailyEnergyMwh;
    double confidence;

    if (sorted.length >= 10) {
      // Use the slope of power over time to refine the estimate.
      final regression = _linearRegression(
        List.generate(sorted.length, (i) => i.toDouble()),
        sorted.map((e) => e.power).toList(),
      );
      // Predicted average power for the next 24 h (24 * 3600 / interval steps ahead).
      final stepsIn24h = (24 * 3600) / _assumedIntervalSeconds;
      final futureMidIndex = sorted.length + stepsIn24h / 2;
      final predictedAvgPower =
          math.max(0, regression['slope']! * futureMidIndex + regression['intercept']!);
      // W × 24 h × 1000 mWh/Wh = mWh
      dailyEnergyMwh = predictedAvgPower * 24 * 1000;
      confidence = math.min(1.0, sorted.length / 200.0);
    } else {
      dailyEnergyMwh = avgPower * 24 * 1000;
      confidence = 0.3;
    }

    // mWh ÷ 1 000 000 × MAD/kWh = MAD
    final nextDayCost = dailyEnergyMwh * tariffRate / 1000000.0;

    // Month-to-date cost estimate.
    final totalHoursCovered =
        (sorted.length * _assumedIntervalSeconds) / 3600.0;
    final avgDailyCoverageHours = totalHoursCovered.clamp(0, 24);
    final mtdDays = now.day.toDouble();
    // W × h × 1000 mWh/Wh = mWh
    final monthToDateEnergy =
        avgPower * avgDailyCoverageHours * mtdDays * 1000;
    final monthToDateCost = monthToDateEnergy * tariffRate / 1000000.0;
    final monthEndCost = monthToDateCost + (dailyEnergyMwh * daysRemaining * tariffRate / 1000000.0);

    return {
      'nextDayEnergy': dailyEnergyMwh,
      'nextDayCost': nextDayCost,
      'monthEndCost': monthEndCost,
      'monthToDateCost': monthToDateCost,
      'daysRemaining': daysRemaining,
      'confidence': confidence,
    };
  }

  // ── Power factor prediction ────────────────────────────────────────────────

  Map<String, dynamic> _predictPowerFactor(List<EnergyData> sorted) {
    // Use up to the last 60 readings for trend detection.
    final recent =
        sorted.length > 60 ? sorted.sublist(sorted.length - 60) : sorted;

    if (recent.length < 3) {
      final pf = recent.isEmpty ? 1.0 : recent.last.powerFactor;
      return {
        'predicted': pf,
        'willDrop': false,
        'minutesUntilDrop': null,
        'trend': 'stable',
        'confidence': 0.1,
      };
    }

    final xs = List.generate(recent.length, (i) => i.toDouble());
    final ys = recent.map((e) => e.powerFactor).toList();

    final reg = _linearRegression(xs, ys);
    final slope = reg['slope']!;
    final intercept = reg['intercept']!;

    // Steps in 10 minutes.
    final stepsIn10min = (10 * 60) / _assumedIntervalSeconds;
    final futureIndex = recent.length + stepsIn10min;
    final predicted10min = (slope * futureIndex + intercept).clamp(0.0, 1.0);

    // Determine when (if ever) PF will cross the threshold.
    double? minutesUntilDrop;
    final bool willDrop;

    if (slope < 0 && recent.last.powerFactor > pfThreshold) {
      // Time for PF to reach threshold: index_cross = (threshold - intercept) / slope
      if (slope != 0) {
        final indexCross = (pfThreshold - intercept) / slope;
        final stepsAhead = indexCross - (recent.length - 1).toDouble();
        if (stepsAhead > 0) {
          minutesUntilDrop =
              (stepsAhead * _assumedIntervalSeconds) / 60.0;
          // Only flag if within 10 minutes.
          willDrop = minutesUntilDrop <= 10.0;
          if (!willDrop) minutesUntilDrop = null;
        } else {
          willDrop = recent.last.powerFactor < pfThreshold;
        }
      } else {
        willDrop = false;
      }
    } else {
      willDrop = predicted10min < pfThreshold;
    }

    String trend;
    if (slope > 0.001) {
      trend = 'rising';
    } else if (slope < -0.001) {
      trend = 'falling';
    } else {
      trend = 'stable';
    }

    // R² as confidence proxy.
    final confidence = _rSquared(xs, ys, slope, intercept).clamp(0.0, 1.0);

    return {
      'predicted': predicted10min,
      'willDrop': willDrop,
      'minutesUntilDrop': minutesUntilDrop,
      'trend': trend,
      'confidence': confidence,
    };
  }

  // ── Math helpers ───────────────────────────────────────────────────────────

  /// Simple ordinary least-squares linear regression.
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
      List<double> xs, List<double> ys, double slope, double intercept) {
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
