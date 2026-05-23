import 'dart:async';
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import '../models/energy_data.dart';
import '../services/energy_repository.dart';
import '../l10n/app_strings.dart';
import '../main.dart' show kTeal, kOrange;

class ComparisonScreen extends StatefulWidget {
  const ComparisonScreen({super.key});

  @override
  State<ComparisonScreen> createState() => _ComparisonScreenState();
}

class _ComparisonScreenState extends State<ComparisonScreen> {
  AppColors get _c => AppColors.of(context);
  static const _units = ['KOFERT_Unit_1', 'KOFERT_Unit_2', 'KOFERT_Unit_3'];
  static const _labels = ['Lampe', 'Ventilateur 5V', 'Pompe réservoir 5V'];
  static const _colors = [kTeal, kOrange, Color(0xFFFF6B8A)];
  static const _icons = [
    Icons.lightbulb_outline,
    Icons.air,
    Icons.water_outlined,
  ];

  final Map<String, EnergyData?> _data = {
    'KOFERT_Unit_1': null,
    'KOFERT_Unit_2': null,
    'KOFERT_Unit_3': null,
  };

  final Map<String, List<_ChartPoint>> _powerHistory = {
    'KOFERT_Unit_1': [],
    'KOFERT_Unit_2': [],
    'KOFERT_Unit_3': [],
  };

  final List<StreamSubscription<EnergyData?>> _subs = [];
  int _tick = 0;

  @override
  void initState() {
    super.initState();
    for (final unit in _units) {
      final sub =
          EnergyRepository.instance.currentMetrics(unit).listen((d) {
        if (!mounted) return;
        setState(() {
          _data[unit] = d;
          if (d != null) {
            final hist = _powerHistory[unit]!;
            hist.add(_ChartPoint(_tick.toDouble(), d.power));
            _tick++;
            if (hist.length > 60) hist.removeAt(0);
          }
        });
      });
      _subs.add(sub);
    }
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _c.bg,
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(28, 28, 28, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(AppStrings.t('comparison_title'),
                style: TextStyle(
                    color: _c.textPri,
                    fontWeight: FontWeight.bold,
                    fontSize: 18)),
            const SizedBox(height: 20),
            _buildUnitCards(),
            const SizedBox(height: 24),
            _buildPowerChart(),
            const SizedBox(height: 24),
            _buildComparisonTable(),
          ],
        ),
      ),
    );
  }

  // ── Per-unit metric cards ──────────────────────────────────────────────────
  Widget _buildUnitCards() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: List.generate(_units.length, (i) {
        final unit = _units[i];
        final d = _data[unit];
        final color = _colors[i];
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(left: i == 0 ? 0 : 12),
            child: Container(
              decoration: BoxDecoration(
                color: _c.card,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: color.withValues(alpha: 0.35), width: 1),
              ),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(_icons[i], color: color, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(_labels[i],
                          style: TextStyle(
                              color: color,
                              fontWeight: FontWeight.w600,
                              fontSize: 13),
                          overflow: TextOverflow.ellipsis),
                    ),
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: d != null ? kTeal : Colors.grey,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ]),
                  const SizedBox(height: 14),
                  _MetricRow(
                      label: 'Puissance',
                      value: d != null
                          ? '${d.power.toStringAsFixed(1)} W'
                          : '–'),
                  _MetricRow(
                      label: 'Tension',
                      value: d != null
                          ? '${d.voltage.toStringAsFixed(1)} V'
                          : '–'),
                  _MetricRow(
                      label: 'Courant',
                      value: d != null
                          ? '${d.current.toStringAsFixed(2)} A'
                          : '–'),
                  _MetricRow(
                      label: 'Fréquence',
                      value: d != null
                          ? '${d.frequency.toStringAsFixed(1)} Hz'
                          : '–'),
                  _MetricRow(
                      label: 'Énergie',
                      value: d != null
                          ? '${d.energy.toStringAsFixed(2)} mWh'
                          : '–'),
                  _MetricRow(
                      label: 'Fact. Puis.',
                      value: d != null
                          ? d.powerFactor.toStringAsFixed(3)
                          : '–',
                      alert:
                          d != null && d.hasLowPowerFactor),
                  if (unit == 'KOFERT_Unit_2')
                    _MetricRow(
                        label: 'Rotation',
                        value: d != null
                            ? '${d.windSpeed.toStringAsFixed(1)} m/s'
                            : '–'),
                ],
              ),
            ),
          ),
        );
      }),
    );
  }

  // ── Live power chart (all 3 units) ─────────────────────────────────────────
  Widget _buildPowerChart() {
    final hasData =
        _powerHistory.values.any((h) => h.length >= 2);

    final series = List.generate(_units.length, (i) {
      return SplineSeries<_ChartPoint, double>(
        dataSource: List.from(_powerHistory[_units[i]]!),
        xValueMapper: (p, _) => p.x,
        yValueMapper: (p, _) => p.y,
        name: _labels[i],
        color: _colors[i],
        width: 2,
      );
    });

    return Container(
      decoration: BoxDecoration(
          color: _c.card, borderRadius: BorderRadius.circular(16)),
      padding: const EdgeInsets.fromLTRB(20, 20, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Puissance active en temps réel (W)',
                  style: TextStyle(
                      color: _c.textPri,
                      fontWeight: FontWeight.bold,
                      fontSize: 15)),
              const Spacer(),
              ...List.generate(
                  _units.length,
                  (i) => Padding(
                        padding: const EdgeInsets.only(left: 12),
                        child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                  width: 10,
                                  height: 10,
                                  decoration: BoxDecoration(
                                      color: _colors[i],
                                      shape: BoxShape.circle)),
                              const SizedBox(width: 4),
                              Text(_labels[i],
                                  style: TextStyle(
                                      color: _c.textSec, fontSize: 11)),
                            ]),
                      )),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 220,
            child: !hasData
                ? Center(
                    child: Text('En attente de données…',
                        style: TextStyle(color: _c.textSec)))
                : SfCartesianChart(
                    backgroundColor: _c.card,
                    plotAreaBorderWidth: 0,
                    legend: const Legend(isVisible: false),
                    primaryXAxis: const NumericAxis(
                        isVisible: false,
                        borderColor: Colors.transparent),
                    primaryYAxis: NumericAxis(
                      labelStyle: TextStyle(
                          color: _c.textSec, fontSize: 11),
                      axisLine:
                          const AxisLine(color: Colors.transparent),
                      majorGridLines: MajorGridLines(
                          color:
                              Colors.white.withValues(alpha: 0.06),
                          width: 1),
                      majorTickLines:
                          const MajorTickLines(size: 0),
                    ),
                    tooltipBehavior: TooltipBehavior(enable: true),
                    series: series,
                  ),
          ),
        ],
      ),
    );
  }

  // ── Comparison table ───────────────────────────────────────────────────────
  Widget _buildComparisonTable() {
    const metrics = [
      'Puissance (W)',
      'Tension (V)',
      'Courant (A)',
      'Énergie (mWh)',
      'Facteur de puissance',
      'Fréquence (Hz)',
      'P. Apparente (VA)',
      'P. Réactive (VAR)',
      'Vitesse rotation (m/s)',
    ];

    String val(int unitIdx, int metricIdx) {
      final d = _data[_units[unitIdx]];
      if (d == null) return '–';
      switch (metricIdx) {
        case 0: return d.power.toStringAsFixed(1);
        case 1: return d.voltage.toStringAsFixed(1);
        case 2: return d.current.toStringAsFixed(2);
        case 3: return d.energy.toStringAsFixed(2);
        case 4: return d.powerFactor.toStringAsFixed(3);
        case 5: return d.frequency.toStringAsFixed(2);
        case 6: return d.apparentPower.toStringAsFixed(1);
        case 7: return d.reactivePower.toStringAsFixed(1);
        // Rotation speed is only meaningful for KOFERT_Unit_2 (fan)
        case 8:
          if (_units[unitIdx] == 'KOFERT_Unit_2') {
            return '${d.windSpeed.toStringAsFixed(1)} m/s';
          }
          return '–';
        default: return '–';
      }
    }

    return Container(
      decoration: BoxDecoration(
          color: _c.card, borderRadius: BorderRadius.circular(16)),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Tableau comparatif',
              style: TextStyle(
                  color: _c.textPri,
                  fontWeight: FontWeight.bold,
                  fontSize: 15)),
          const SizedBox(height: 16),
          Table(
            columnWidths: const {0: FlexColumnWidth(2.2)},
            border:
                TableBorder.all(color: Colors.white10, width: 1),
            children: [
              // Header row
              TableRow(
                decoration: BoxDecoration(
                    color:
                        Colors.white.withValues(alpha: 0.06)),
                children: [
                  Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text('Métrique',
                          style: TextStyle(
                              color: _c.textSec,
                              fontWeight: FontWeight.w600,
                              fontSize: 12))),
                  ...List.generate(
                      _units.length,
                      (i) => Padding(
                            padding: const EdgeInsets.all(8),
                            child: Text(_labels[i],
                                style: TextStyle(
                                    color: _colors[i],
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12)),
                          )),
                ],
              ),
              // Data rows
              ...List.generate(
                metrics.length,
                (mi) => TableRow(
                  decoration: mi.isOdd
                      ? BoxDecoration(
                          color: Colors.white
                              .withValues(alpha: 0.025))
                      : null,
                  children: [
                    Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text(metrics[mi],
                            style: TextStyle(
                                color: _c.textSec,
                                fontSize: 12))),
                    ...List.generate(
                        _units.length,
                        (i) => Padding(
                              padding: const EdgeInsets.all(8),
                              child: Text(val(i, mi),
                                  style: TextStyle(
                                      color: _c.textPri,
                                      fontSize: 12)),
                            )),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

class _MetricRow extends StatelessWidget {
  final String label;
  final String value;
  final bool alert;
  const _MetricRow(
      {required this.label, required this.value, this.alert = false});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style:
                  TextStyle(color: c.textSec, fontSize: 12)),
          Text(value,
              style: TextStyle(
                  color: alert
                      ? const Color(0xFFE74C3C)
                      : c.textPri,
                  fontWeight: FontWeight.w600,
                  fontSize: 12)),
        ],
      ),
    );
  }
}

class _ChartPoint {
  final double x;
  final double y;
  const _ChartPoint(this.x, this.y);
}