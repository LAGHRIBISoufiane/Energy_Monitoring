import 'dart:async';
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import '../models/energy_data.dart';
import '../main.dart' show kTeal, kOrange;

// ─────────────────────────────────────────────────────────────────────────────
// Summary Screen — daily / monthly energy consumption & cost breakdown
// ─────────────────────────────────────────────────────────────────────────────
class SummaryScreen extends StatefulWidget {
  const SummaryScreen({super.key});

  @override
  State<SummaryScreen> createState() => _SummaryScreenState();
}

class _SummaryScreenState extends State<SummaryScreen>
    with SingleTickerProviderStateMixin {
  AppColors get _c => AppColors.of(context);
  late final TabController _tab;
  List<EnergyData> _allData = [];
  List<_DaySummary> _dailySummaries = [];
  List<_MonthSummary> _monthlySummaries = [];
  bool _loading = true;
  double _tariffRate = 1.15;
  static const _deviceLabel = {
    'KOFERT_Unit_1': 'Lampe',
    'KOFERT_Unit_2': 'Ventilateur 5V',
    'KOFERT_Unit_3': 'Pompe réservoir 5V',
  };

  static const _deviceIcon = {
    'KOFERT_Unit_1': Icons.lightbulb_outline,
    'KOFERT_Unit_2': Icons.air,
    'KOFERT_Unit_3': Icons.water_outlined,
  };

  String _selectedUnit = 'KOFERT_Unit_1';

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _loadPrefs().then((_) => _loadData());
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _tariffRate = prefs.getDouble('tariffRate') ?? 1.15;
        _selectedUnit = prefs.getString('selectedUnit') ?? 'KOFERT_Unit_1';
      });
    }
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final snapshot = await FirebaseDatabase.instance
          .ref('$_selectedUnit/historical_data')
          .limitToLast(1000)
          .get();

      if (!snapshot.exists) {
        setState(() => _loading = false);
        return;
      }

      final raw = snapshot.value as Map<dynamic, dynamic>;
      final list = <EnergyData>[];
      raw.forEach((key, value) {
        if (value is Map<dynamic, dynamic>) {
          try {
            list.add(EnergyData.fromJson(value, _selectedUnit));
          } catch (_) {}
        }
      });
      list.sort((a, b) => a.timestamp.compareTo(b.timestamp));

      setState(() {
        _allData = list;
        _dailySummaries = _buildDailySummaries(list);
        _monthlySummaries = _buildMonthlySummaries(list);
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  List<_DaySummary> _buildDailySummaries(List<EnergyData> data) {
    final map = <String, List<EnergyData>>{};
    for (final d in data) {
      final key = DateFormat('yyyy-MM-dd').format(d.timestamp);
      map.putIfAbsent(key, () => []).add(d);
    }
    return map.entries.map((e) {
      final pts = e.value;
      final totalEnergy = pts.isNotEmpty ? pts.last.energy - pts.first.energy : 0.0;
      final peakPower = pts.fold(0.0, (m, p) => p.power > m ? p.power : m);
      final avgPF = pts.isEmpty ? 0.0 : pts.fold(0.0, (s, p) => s + p.powerFactor) / pts.length;
      return _DaySummary(
        date: e.key,
        energyMwh: totalEnergy.clamp(0, double.infinity).toDouble(),
        peakPowerW: peakPower,
        avgPowerFactor: avgPF,
        cost: totalEnergy.clamp(0, double.infinity) * _tariffRate,
        samples: pts.length,
      );
    }).toList()
      ..sort((a, b) => a.date.compareTo(b.date));
  }

  List<_MonthSummary> _buildMonthlySummaries(List<EnergyData> data) {
    final map = <String, List<_DaySummary>>{};
    for (final d in _buildDailySummaries(data)) {
      final key = d.date.substring(0, 7); // yyyy-MM
      map.putIfAbsent(key, () => []).add(d);
    }
    return map.entries.map((e) {
      final days = e.value;
      final totalEnergy = days.fold(0.0, (s, d) => s + d.energyMwh);
      final peakPower  = days.fold(0.0, (m, d) => d.peakPowerW > m ? d.peakPowerW : m);
      final avgPF = days.isEmpty ? 0.0 : days.fold(0.0, (s, d) => s + d.avgPowerFactor) / days.length;
      return _MonthSummary(
        month: e.key,
        energyMwh: totalEnergy,
        peakPowerW: peakPower,
        avgPowerFactor: avgPF,
        cost: totalEnergy * _tariffRate,
        activeDays: days.length,
      );
    }).toList()
      ..sort((a, b) => a.month.compareTo(b.month));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _c.bg,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          _buildTabBar(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: kTeal))
                : _allData.isEmpty
                    ? _buildEmpty()
                    : TabBarView(
                        controller: _tab,
                        children: [
                          _buildDailyTab(),
                          _buildMonthlyTab(),
                        ],
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(28, 28, 28, 0),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Résumé de consommation',
                    style: TextStyle(
                        color: _c.textPri,
                        fontWeight: FontWeight.bold,
                        fontSize: 22)),
                const SizedBox(height: 6),
                Row(children: [
                  Icon(_deviceIcon[_selectedUnit]!, color: kTeal, size: 15),
                  const SizedBox(width: 6),
                  Text('$_selectedUnit · ${_deviceLabel[_selectedUnit]} · Tarif: ${_tariffRate.toStringAsFixed(2)} MAD/mWh',
                      style: TextStyle(color: _c.textSec, fontSize: 13)),
                ]),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: kTeal),
            tooltip: 'Actualiser',
            onPressed: () => _loadPrefs().then((_) => _loadData()),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      child: Container(
        decoration: BoxDecoration(
          color: _c.card,
          borderRadius: BorderRadius.circular(12),
        ),
        child: TabBar(
          controller: _tab,
          indicator: BoxDecoration(
            color: kTeal.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: kTeal, width: 1),
          ),
          indicatorSize: TabBarIndicatorSize.tab,
          labelColor: kTeal,
          unselectedLabelColor: _c.textSec,
          dividerColor: Colors.transparent,
          tabs: const [
            Tab(text: 'Journalier'),
            Tab(text: 'Mensuel'),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.inbox_outlined, color: _c.textSec, size: 48),
          const SizedBox(height: 12),
          Text('Aucune donnée historique disponible',
              style: TextStyle(color: _c.textSec)),
        ],
      ),
    );
  }

  // ── Daily tab ──────────────────────────────────────────────────────────────
  Widget _buildDailyTab() {
    if (_dailySummaries.isEmpty) return _buildEmpty();
    final totalEnergy = _dailySummaries.fold(0.0, (s, d) => s + d.energyMwh);
    final totalCost   = _dailySummaries.fold(0.0, (s, d) => s + d.cost);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 20, 28, 32),
      child: Column(
        children: [
          // KPI row
          _buildKpiRow([
            _KpiData('Énergie totale', '${totalEnergy.toStringAsFixed(1)} mWh', kTeal, Icons.bolt),
            _KpiData('Coût total', '${totalCost.toStringAsFixed(2)} MAD', kOrange, Icons.payments),
            _KpiData('Jours enregistrés', '${_dailySummaries.length}', const Color(0xFF4FC3F7), Icons.calendar_today),
            _KpiData('Moy. journalière', '${(totalEnergy / _dailySummaries.length).toStringAsFixed(1)} mWh', const Color(0xFFFF6B8A), Icons.trending_up),
          ]),
          const SizedBox(height: 24),
          _buildDailyChart(),
          const SizedBox(height: 24),
          _buildDailyTable(),
        ],
      ),
    );
  }

  Widget _buildDailyChart() {
    final last14 = _dailySummaries.length > 14
        ? _dailySummaries.sublist(_dailySummaries.length - 14)
        : _dailySummaries;

    return Container(
      decoration: BoxDecoration(
        color: _c.card,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Consommation journalière (14 derniers jours)',
              style: TextStyle(color: _c.textPri, fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 16),
          SizedBox(
            height: 220,
            child: SfCartesianChart(
              backgroundColor: _c.card,
              plotAreaBorderWidth: 0,
              margin: EdgeInsets.zero,
              primaryXAxis: CategoryAxis(
                labelStyle: TextStyle(color: _c.textSec, fontSize: 10),
                axisLine: const AxisLine(color: Colors.transparent),
                majorGridLines: const MajorGridLines(width: 0),
                majorTickLines: const MajorTickLines(size: 0),
                labelRotation: -30,
              ),
              primaryYAxis: NumericAxis(
                labelStyle: TextStyle(color: _c.textSec, fontSize: 11),
                axisLine: const AxisLine(color: Colors.transparent),
                majorGridLines: MajorGridLines(
                    color: Colors.white.withValues(alpha: 0.06), width: 1),
                majorTickLines: const MajorTickLines(size: 0),
                labelFormat: '{value} mWh',
              ),
              tooltipBehavior: TooltipBehavior(enable: true),
              series: <CartesianSeries>[
                ColumnSeries<_DaySummary, String>(
                  dataSource: last14,
                  xValueMapper: (d, _) => d.date.substring(5),
                  yValueMapper: (d, _) => d.energyMwh,
                  name: 'Énergie (mWh)',
                  color: kTeal,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(4),
                    topRight: Radius.circular(4),
                  ),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [kTeal, kTeal.withValues(alpha: 0.5)],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDailyTable() {
    return Container(
      decoration: BoxDecoration(
        color: _c.card,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Text('Détail journalier',
                style: TextStyle(color: _c.textPri, fontWeight: FontWeight.bold, fontSize: 15)),
          ),
          const Divider(color: Colors.white12, height: 1),
          // Header
          _tableRow('Date', 'Énergie', 'Puissance max', 'FP moy.', 'Coût', isHeader: true),
          const Divider(color: Colors.white12, height: 1),
          ...List.generate(_dailySummaries.length, (i) {
            final d = _dailySummaries[_dailySummaries.length - 1 - i];
            return Column(children: [
              _tableRow(
                d.date,
                '${d.energyMwh.toStringAsFixed(2)} mWh',
                '${d.peakPowerW.toStringAsFixed(0)} W',
                d.avgPowerFactor.toStringAsFixed(2),
                '${d.cost.toStringAsFixed(2)} MAD',
              ),
              if (i < _dailySummaries.length - 1)
                const Divider(color: Colors.white12, height: 1),
            ]);
          }),
        ],
      ),
    );
  }

  // ── Monthly tab ────────────────────────────────────────────────────────────
  Widget _buildMonthlyTab() {
    if (_monthlySummaries.isEmpty) return _buildEmpty();
    final totalEnergy = _monthlySummaries.fold(0.0, (s, m) => s + m.energyMwh);
    final totalCost   = _monthlySummaries.fold(0.0, (s, m) => s + m.cost);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 20, 28, 32),
      child: Column(
        children: [
          _buildKpiRow([
            _KpiData('Énergie totale', '${totalEnergy.toStringAsFixed(1)} mWh', kTeal, Icons.bolt),
            _KpiData('Coût total', '${totalCost.toStringAsFixed(2)} MAD', kOrange, Icons.payments),
            _KpiData('Mois enregistrés', '${_monthlySummaries.length}', const Color(0xFF4FC3F7), Icons.calendar_month),
            _KpiData('Moy. mensuelle', '${(totalEnergy / _monthlySummaries.length).toStringAsFixed(1)} mWh', const Color(0xFFFF6B8A), Icons.trending_up),
          ]),
          const SizedBox(height: 24),
          _buildMonthlyChart(),
          const SizedBox(height: 24),
          _buildMonthlyTable(),
        ],
      ),
    );
  }

  Widget _buildMonthlyChart() {
    return Container(
      decoration: BoxDecoration(color: _c.card, borderRadius: BorderRadius.circular(16)),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Consommation mensuelle',
              style: TextStyle(color: _c.textPri, fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 16),
          SizedBox(
            height: 220,
            child: SfCartesianChart(
              backgroundColor: _c.card,
              plotAreaBorderWidth: 0,
              margin: EdgeInsets.zero,
              primaryXAxis: CategoryAxis(
                labelStyle: TextStyle(color: _c.textSec, fontSize: 10),
                axisLine: const AxisLine(color: Colors.transparent),
                majorGridLines: const MajorGridLines(width: 0),
                majorTickLines: const MajorTickLines(size: 0),
              ),
              primaryYAxis: NumericAxis(
                labelStyle: TextStyle(color: _c.textSec, fontSize: 11),
                axisLine: const AxisLine(color: Colors.transparent),
                majorGridLines: MajorGridLines(
                    color: Colors.white.withValues(alpha: 0.06), width: 1),
                majorTickLines: const MajorTickLines(size: 0),
                labelFormat: '{value} mWh',
              ),
              tooltipBehavior: TooltipBehavior(enable: true),
              series: <CartesianSeries>[
                ColumnSeries<_MonthSummary, String>(
                  dataSource: _monthlySummaries,
                  xValueMapper: (m, _) => m.month,
                  yValueMapper: (m, _) => m.energyMwh,
                  name: 'Énergie (mWh)',
                  color: kOrange,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(4),
                    topRight: Radius.circular(4),
                  ),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [kOrange, kOrange.withValues(alpha: 0.5)],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMonthlyTable() {
    return Container(
      decoration: BoxDecoration(color: _c.card, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Text('Détail mensuel',
                style: TextStyle(color: _c.textPri, fontWeight: FontWeight.bold, fontSize: 15)),
          ),
          const Divider(color: Colors.white12, height: 1),
          _tableRow('Mois', 'Énergie', 'Puissance max', 'FP moy.', 'Coût', isHeader: true),
          const Divider(color: Colors.white12, height: 1),
          ...List.generate(_monthlySummaries.length, (i) {
            final m = _monthlySummaries[_monthlySummaries.length - 1 - i];
            return Column(children: [
              _tableRow(
                m.month,
                '${m.energyMwh.toStringAsFixed(1)} mWh',
                '${m.peakPowerW.toStringAsFixed(0)} W',
                m.avgPowerFactor.toStringAsFixed(2),
                '${m.cost.toStringAsFixed(2)} MAD',
              ),
              if (i < _monthlySummaries.length - 1)
                const Divider(color: Colors.white12, height: 1),
            ]);
          }),
        ],
      ),
    );
  }

  // ── Shared helpers ─────────────────────────────────────────────────────────
  Widget _buildKpiRow(List<_KpiData> items) {
    return Row(
      children: items.asMap().entries.map((e) {
        final kpi = e.value;
        return Expanded(
          child: Container(
            margin: EdgeInsets.only(left: e.key == 0 ? 0 : 12),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: _c.card,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: kpi.color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(kpi.icon, color: kpi.color, size: 20),
                ),
                const SizedBox(height: 12),
                Text(kpi.value,
                    style: TextStyle(
                        color: kpi.color,
                        fontWeight: FontWeight.bold,
                        fontSize: 18)),
                const SizedBox(height: 4),
                Text(kpi.label,
                    style: TextStyle(color: _c.textSec, fontSize: 11)),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _tableRow(String c1, String c2, String c3, String c4, String c5,
      {bool isHeader = false}) {
    final style = isHeader
        ? TextStyle(color: _c.textSec, fontSize: 11, fontWeight: FontWeight.w600)
        : TextStyle(color: _c.textPri, fontSize: 12);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        children: [
          Expanded(flex: 3, child: Text(c1, style: style)),
          Expanded(flex: 2, child: Text(c2, style: style, textAlign: TextAlign.right)),
          Expanded(flex: 2, child: Text(c3, style: style, textAlign: TextAlign.right)),
          Expanded(flex: 1, child: Text(c4, style: style, textAlign: TextAlign.right)),
          Expanded(flex: 2, child: Text(c5, style: style, textAlign: TextAlign.right)),
        ],
      ),
    );
  }
}

// ── Data models ───────────────────────────────────────────────────────────────
class _DaySummary {
  final String date;
  final double energyMwh;
  final double peakPowerW;
  final double avgPowerFactor;
  final double cost;
  final int samples;
  const _DaySummary({
    required this.date,
    required this.energyMwh,
    required this.peakPowerW,
    required this.avgPowerFactor,
    required this.cost,
    required this.samples,
  });
}

class _MonthSummary {
  final String month;
  final double energyMwh;
  final double peakPowerW;
  final double avgPowerFactor;
  final double cost;
  final int activeDays;
  const _MonthSummary({
    required this.month,
    required this.energyMwh,
    required this.peakPowerW,
    required this.avgPowerFactor,
    required this.cost,
    required this.activeDays,
  });
}

class _KpiData {
  final String label;
  final String value;
  final Color color;
  final IconData icon;
  const _KpiData(this.label, this.value, this.color, this.icon);
}