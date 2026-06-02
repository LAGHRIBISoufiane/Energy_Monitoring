import 'dart:async';
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/energy_data.dart';
import '../services/energy_repository.dart';
import '../l10n/app_strings.dart';
import '../main.dart' show kTeal, kOrange;
import '../utils/energy_format.dart';

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

  final Map<String, List<_ChartPoint>> _voltageHistory = {
    'KOFERT_Unit_1': [],
    'KOFERT_Unit_2': [],
    'KOFERT_Unit_3': [],
  };

  final Map<String, List<_ChartPoint>> _currentHistory = {
    'KOFERT_Unit_1': [],
    'KOFERT_Unit_2': [],
    'KOFERT_Unit_3': [],
  };

  final List<StreamSubscription<EnergyData?>> _subs = [];
  int _tick = 0;

  // Unit preferences
  String _powerUnit   = 'W';
  String _voltageUnit = 'V';
  String _currentUnit = 'A';
  String _energyUnit  = 'kWh';

  // Format helpers
  String _fmtP(double w) {
    if (_powerUnit == 'mW') return '${(w * 1000).toStringAsFixed(1)} mW';
    if (_powerUnit == 'kW') return '${(w / 1000).toStringAsFixed(4)} kW';
    return '${w.toStringAsFixed(1)} W';
  }
  String _fmtV(double v) =>
      _voltageUnit == 'mV' ? '${(v * 1000).toStringAsFixed(0)} mV' : '${v.toStringAsFixed(1)} V';
  String _fmtI(double a) =>
      _currentUnit == 'mA' ? '${(a * 1000).toStringAsFixed(1)} mA' : '${a.toStringAsFixed(2)} A';
  String _fmtE(double mwh) => fmtEnergyUnit(mwh, _energyUnit);

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _powerUnit   = prefs.getString('unitPower')   ?? 'W';
      _voltageUnit = prefs.getString('unitVoltage') ?? 'V';
      _currentUnit = prefs.getString('unitCurrent') ?? 'A';
      _energyUnit  = prefs.getString('unitEnergy')  ?? 'kWh';
    });
  }

  @override
  void initState() {
    super.initState();
    _loadPrefs();
    for (final unit in _units) {
      final sub =
          EnergyRepository.instance.currentMetrics(unit).listen((d) {
        if (!mounted) return;
        setState(() {
          _data[unit] = d;
          if (d != null) {
            final t = _tick.toDouble();
            final ph = _powerHistory[unit]!;
            ph.add(_ChartPoint(t, d.power));
            if (ph.length > 60) ph.removeAt(0);

            final vh = _voltageHistory[unit]!;
            vh.add(_ChartPoint(t, d.voltage));
            if (vh.length > 60) vh.removeAt(0);

            final ch = _currentHistory[unit]!;
            ch.add(_ChartPoint(t, d.current));
            if (ch.length > 60) ch.removeAt(0);

            _tick++;
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
      body: LayoutBuilder(
        builder: (context, bc) {
          final p = bc.maxWidth < 600 ? 14.0 : 28.0;
          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(p, p, p, 32),
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
                _buildVoltageChart(),
                const SizedBox(height: 24),
                _buildCurrentChart(),
                const SizedBox(height: 24),
                _buildComparisonTable(),
              ],
            ),
          );
        },
      ),
    );
  }

  // ── Per-unit metric cards ──────────────────────────────────────────────────
  Widget _buildUnitCards() {
    Widget card(int i) {
      final unit = _units[i];
      final d = _data[unit];
      final color = _colors[i];
      return Container(
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
                    ? _fmtP(d.power)
                    : '–'),
            _MetricRow(
                label: 'Tension',
                value: d != null
                    ? _fmtV(d.voltage)
                    : '–'),
            _MetricRow(
                label: 'Courant',
                value: d != null
                    ? _fmtI(d.current)
                    : '–'),
            _MetricRow(
                label: 'Fréquence',
                value: d != null
                    ? '${d.frequency.toStringAsFixed(1)} Hz'
                    : '–'),
            _MetricRow(
                label: 'Énergie',
                value: d != null
                    ? _fmtE(d.energy)
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
      );
    }

    return LayoutBuilder(builder: (context, bc) {
      if (bc.maxWidth < 600) {
        return Column(
          children: List.generate(_units.length, (i) => Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : 12),
            child: card(i),
          )),
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: List.generate(_units.length, (i) => Expanded(
          child: Padding(
            padding: EdgeInsets.only(left: i == 0 ? 0 : 12),
            child: card(i),
          ),
        )),
      );
    });
  }

  // ── Live power chart (all 3 units) ─────────────────────────────────────────
  Widget _buildPowerChart() {
    final hasData =
        _powerHistory.values.any((h) => h.length >= 2);

    final series = List.generate(_units.length, (i) {
      final double pScale = _powerUnit == 'mW' ? 1000.0 : _powerUnit == 'kW' ? 0.001 : 1.0;
      return SplineSeries<_ChartPoint, double>(
        dataSource: List.from(_powerHistory[_units[i]]!),
        xValueMapper: (p, _) => p.x,
        yValueMapper: (p, _) => p.y * pScale,
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
          Text('Puissance active en temps réel ($_powerUnit)',
              style: TextStyle(
                  color: _c.textPri,
                  fontWeight: FontWeight.bold,
                  fontSize: 15)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: List.generate(_units.length, (i) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                    width: 10, height: 10,
                    decoration: BoxDecoration(
                        color: _colors[i], shape: BoxShape.circle)),
                const SizedBox(width: 4),
                Text(_labels[i],
                    style: TextStyle(color: _c.textSec, fontSize: 11)),
              ],
            )),
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
                      labelFormat: '{value} $_powerUnit',
                    ),
                    tooltipBehavior: TooltipBehavior(enable: true),
                    series: series,
                  ),
          ),
        ],
      ),
    );
  }

  // ── Live voltage chart (all 3 units) ─────────────────────────────────────
  Widget _buildVoltageChart() {
    final hasData = _voltageHistory.values.any((h) => h.length >= 2);
    final vScale = _voltageUnit == 'mV' ? 1000.0 : 1.0;
    final series = List.generate(_units.length, (i) {
      return SplineSeries<_ChartPoint, double>(
        dataSource: List.from(_voltageHistory[_units[i]]!),
        xValueMapper: (p, _) => p.x,
        yValueMapper: (p, _) => p.y * vScale,
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
          Text('Tension en temps réel ($_voltageUnit)',
              style: TextStyle(
                  color: _c.textPri,
                  fontWeight: FontWeight.bold,
                  fontSize: 15)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: List.generate(_units.length, (i) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                    width: 10, height: 10,
                    decoration: BoxDecoration(
                        color: _colors[i], shape: BoxShape.circle)),
                const SizedBox(width: 4),
                Text(_labels[i],
                    style: TextStyle(color: _c.textSec, fontSize: 11)),
              ],
            )),
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
                          color: Colors.white.withValues(alpha: 0.06),
                          width: 1),
                      majorTickLines: const MajorTickLines(size: 0),
                      numberFormat: null,
                      labelFormat: '{value} $_voltageUnit',
                    ),
                    tooltipBehavior: TooltipBehavior(enable: true),
                    series: series,
                  ),
          ),
        ],
      ),
    );
  }

  // ── Live current chart (all 3 units) ─────────────────────────────────────
  Widget _buildCurrentChart() {
    final hasData = _currentHistory.values.any((h) => h.length >= 2);
    final cScale = _currentUnit == 'mA' ? 1000.0 : 1.0;
    final series = List.generate(_units.length, (i) {
      return SplineSeries<_ChartPoint, double>(
        dataSource: List.from(_currentHistory[_units[i]]!),
        xValueMapper: (p, _) => p.x,
        yValueMapper: (p, _) => p.y * cScale,
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
          Text('Courant en temps réel ($_currentUnit)',
              style: TextStyle(
                  color: _c.textPri,
                  fontWeight: FontWeight.bold,
                  fontSize: 15)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: List.generate(_units.length, (i) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                    width: 10, height: 10,
                    decoration: BoxDecoration(
                        color: _colors[i], shape: BoxShape.circle)),
                const SizedBox(width: 4),
                Text(_labels[i],
                    style: TextStyle(color: _c.textSec, fontSize: 11)),
              ],
            )),
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
                          color: Colors.white.withValues(alpha: 0.06),
                          width: 1),
                      majorTickLines: const MajorTickLines(size: 0),
                      labelFormat: '{value} $_currentUnit',
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
    final metrics = [
      'Puissance ($_powerUnit)',
      'Tension ($_voltageUnit)',
      'Courant ($_currentUnit)',
      'Énergie ($_energyUnit)',
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
        case 0: return _fmtP(d.power);
        case 1: return _fmtV(d.voltage);
        case 2: return _fmtI(d.current);
        case 3: return _fmtE(d.energy);
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
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 400),
              child: Table(
                columnWidths: const {0: FixedColumnWidth(160)},
                defaultColumnWidth: const FixedColumnWidth(110),
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
            ),
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