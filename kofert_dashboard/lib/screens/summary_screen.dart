import 'dart:async';
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import '../models/energy_data.dart';
import '../main.dart' show kTeal, kOrange;
import '../services/firestore_log_service.dart';
import '../utils/energy_format.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

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
  // GetEnergyUnit: last-seen timestamp from Firestore unit_status.
  DateTime? _unitLastSeen;
  bool _unitIsActive = false;
  String _energyUnit = 'kWh';
  String _powerUnit   = 'W';
  String _voltageUnit = 'V';
  String _currentUnit = 'A';
  static const _allUnitsKey = 'ALL_UNITS';
  static const _deviceLabel = {
    'ALL_UNITS': 'Toutes les unités',
    'KOFERT_Unit_1': 'Lampe',
    'KOFERT_Unit_2': 'Ventilateur 5V',
    'KOFERT_Unit_3': 'Pompe réservoir 5V',
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
        _tariffRate   = prefs.getDouble('tariffRate')      ?? 1.15;
        _selectedUnit = prefs.getString('selectedUnit')      ?? 'KOFERT_Unit_1';
        _energyUnit   = prefs.getString('unitEnergy')        ?? 'kWh';
        _powerUnit    = prefs.getString('unitPower')         ?? 'W';
        _voltageUnit  = prefs.getString('unitVoltage')       ?? 'V';
        _currentUnit  = prefs.getString('unitCurrent')       ?? 'A';
      });
    }
  }

  String _fmtE(double mwh) => fmtEnergyUnit(mwh, _energyUnit);

  String _fmtP(double w) {
    switch (_powerUnit) {
      case 'mW': final v = w * 1000; return '${v.toStringAsFixed(v >= 100 ? 0 : 1)} mW';
      case 'kW': final v = w / 1000; return '${v.toStringAsFixed(3)} kW';
      default:   return '${w.toStringAsFixed(w >= 100 ? 0 : 1)} W';
    }
  }

  String _fmtV(double v) {
    if (_voltageUnit == 'mV') return '${(v * 1000).toStringAsFixed(0)} mV';
    return '${v.toStringAsFixed(1)} V';
  }

  String _fmtI(double a) {
    if (_currentUnit == 'mA') return '${(a * 1000).toStringAsFixed(1)} mA';
    return '${a.toStringAsFixed(3)} A';
  }

  Future<List<EnergyData>> _fetchUnit(String unitId, DateTime since) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('sensor_readings')
          .where('unitId', isEqualTo: unitId)
          .where('timestamp', isGreaterThan: Timestamp.fromDate(since))
          .orderBy('timestamp')
          .get();
      final list = <EnergyData>[];
      for (final doc in snap.docs) {
        try {
          final d = doc.data();
          final mapped = <String, dynamic>{
            'voltage':      d['voltage'],
            'current':      d['current'],
            'power_factor': d['powerFactor'],
            'power':        d['power'],
            // energy is stored as mWh in Firestore; fromJson expects kWh (multiplies by 1M)
            'energy':       ((d['energy'] as num?)?.toDouble() ?? 0) / 1000000,
            'frequency':    d['frequency'],
            'fan_speed':    (d['fanSpeed'] as num?)?.toInt(),
            'water_level':  (d['waterLevel'] as num?)?.toInt(),
            'timestamp':    (d['timestamp'] as Timestamp?)?.toDate().toIso8601String(),
          };
          list.add(EnergyData.fromJson(mapped, unitId));
        } catch (_) {}
      }
      return list..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    } catch (_) {
      return [];
    }
  }

  List<_DaySummary> _buildCombinedDailySummaries(List<List<EnergyData>> unitsData) {
    final perUnit = unitsData.map(_buildDailySummaries).toList();
    final allDates = <String>{for (final u in perUnit) for (final d in u) d.date};
    return allDates.map((date) {
      double energy = 0, peakPower = 0, pfSum = 0, powerSum = 0, voltageSum = 0, currentSum = 0;
      int count = 0;
      for (final unitDailies in perUnit) {
        final matches = unitDailies.where((d) => d.date == date);
        if (matches.isNotEmpty) {
          final m = matches.first;
          energy      += m.energyMwh;
          peakPower   += m.peakPowerW;
          pfSum       += m.avgPowerFactor;
          powerSum    += m.avgPowerW;
          voltageSum  += m.avgVoltageV;
          currentSum  += m.avgCurrentA;
          count++;
        }
      }
      return _DaySummary(
        date:           date,
        energyMwh:      energy,
        peakPowerW:     peakPower,
        avgPowerW:      count > 0 ? powerSum   / count : 0,
        avgVoltageV:    count > 0 ? voltageSum / count : 0,
        avgCurrentA:    count > 0 ? currentSum / count : 0,
        avgPowerFactor: count > 0 ? pfSum      / count : 0,
        cost:           (energy / 1000000) * _tariffRate,
        samples:        0,
      );
    }).toList()
      ..sort((a, b) => a.date.compareTo(b.date));
  }

  List<_MonthSummary> _buildMonthlySummariesFromDaily(List<_DaySummary> dailies) {
    final map = <String, List<_DaySummary>>{};
    for (final d in dailies) {
      final key = d.date.substring(0, 7);
      map.putIfAbsent(key, () => []).add(d);
    }
    return map.entries.map((e) {
      final days = e.value;
      final totalEnergy = days.fold(0.0, (s, d) => s + d.energyMwh);
      final peakPower   = days.fold(0.0, (m, d) => d.peakPowerW > m ? d.peakPowerW : m);
      final avgPF       = days.isEmpty ? 0.0 : days.fold(0.0, (s, d) => s + d.avgPowerFactor) / days.length;
      final avgPower    = days.isEmpty ? 0.0 : days.fold(0.0, (s, d) => s + d.avgPowerW)      / days.length;
      final avgVoltage  = days.isEmpty ? 0.0 : days.fold(0.0, (s, d) => s + d.avgVoltageV)    / days.length;
      final avgCurrent  = days.isEmpty ? 0.0 : days.fold(0.0, (s, d) => s + d.avgCurrentA)    / days.length;
      return _MonthSummary(
        month:          e.key,
        energyMwh:      totalEnergy,
        peakPowerW:     peakPower,
        avgPowerW:      avgPower,
        avgVoltageV:    avgVoltage,
        avgCurrentA:    avgCurrent,
        avgPowerFactor: avgPF,
        cost:           (totalEnergy / 1000000) * _tariffRate,
        activeDays:     days.length,
      );
    }).toList()
      ..sort((a, b) => a.month.compareTo(b.month));
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final since = DateTime.now().subtract(const Duration(days: 90));
      if (_selectedUnit == _allUnitsKey) {
        const allUnits = ['KOFERT_Unit_1', 'KOFERT_Unit_2', 'KOFERT_Unit_3'];
        final allLists = await Future.wait(allUnits.map((u) => _fetchUnit(u, since)));
        final combined = <EnergyData>[for (final l in allLists) ...l]
          ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
        if (!mounted) return;
        final dailies = _buildCombinedDailySummaries(allLists);
        setState(() {
          _allData = combined;
          _dailySummaries = dailies;
          _monthlySummaries = _buildMonthlySummariesFromDaily(dailies);
          _loading = false;
        });
        return;
      }
      final list = await _fetchUnit(_selectedUnit, since);
      if (!mounted) return;
      setState(() {
        _allData = list;
        _dailySummaries = _buildDailySummaries(list);
        _monthlySummaries = _buildMonthlySummaries(list);
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
    if (_selectedUnit != _allUnitsKey) _loadUnitStatus();
  }

  Future<void> _loadUnitStatus() async {
    final status =
        await FirestoreLogService.instance.getUnitStatus(_selectedUnit);
    if (!mounted || status == null) return;
    final ts = (status['updatedAt'] as Timestamp?)?.toDate().toLocal() ??
        (status['timestamp'] as Timestamp?)?.toDate().toLocal();
    final isActive =
        ts != null && DateTime.now().difference(ts).inMinutes < 10;
    setState(() {
      _unitLastSeen = ts;
      _unitIsActive = isActive;
    });
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
      final peakPower  = pts.fold(0.0, (m, p) => p.power > m ? p.power : m);
      final avgPF      = pts.isEmpty ? 0.0 : pts.fold(0.0, (s, p) => s + p.powerFactor) / pts.length;
      final avgPower   = pts.isEmpty ? 0.0 : pts.fold(0.0, (s, p) => s + p.power)       / pts.length;
      final avgVoltage = pts.isEmpty ? 0.0 : pts.fold(0.0, (s, p) => s + p.voltage)     / pts.length;
      final avgCurrent = pts.isEmpty ? 0.0 : pts.fold(0.0, (s, p) => s + p.current)     / pts.length;
      return _DaySummary(
        date:           e.key,
        energyMwh:      totalEnergy.clamp(0, double.infinity).toDouble(),
        peakPowerW:     peakPower,
        avgPowerW:      avgPower,
        avgVoltageV:    avgVoltage,
        avgCurrentA:    avgCurrent,
        avgPowerFactor: avgPF,
        cost:           (totalEnergy.clamp(0, double.infinity) / 1000000) * _tariffRate,
        samples:        pts.length,
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
      final peakPower   = days.fold(0.0, (m, d) => d.peakPowerW > m ? d.peakPowerW : m);
      final avgPF       = days.isEmpty ? 0.0 : days.fold(0.0, (s, d) => s + d.avgPowerFactor) / days.length;
      final avgPower    = days.isEmpty ? 0.0 : days.fold(0.0, (s, d) => s + d.avgPowerW)       / days.length;
      final avgVoltage  = days.isEmpty ? 0.0 : days.fold(0.0, (s, d) => s + d.avgVoltageV)     / days.length;
      final avgCurrent  = days.isEmpty ? 0.0 : days.fold(0.0, (s, d) => s + d.avgCurrentA)     / days.length;
      return _MonthSummary(
        month:          e.key,
        energyMwh:      totalEnergy,
        peakPowerW:     peakPower,
        avgPowerW:      avgPower,
        avgVoltageV:    avgVoltage,
        avgCurrentA:    avgCurrent,
        avgPowerFactor: avgPF,
        cost:           (totalEnergy / 1000000) * _tariffRate,
        activeDays:     days.length,
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

  String _fmtLastSeen(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 1) return 'à l\'instant';
    if (diff.inMinutes < 60) return 'il y a ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'il y a ${diff.inHours} h';
    return 'il y a ${diff.inDays} j';
  }

  Widget _buildHeader() {
    return LayoutBuilder(builder: (context, bc) {
      final narrow = bc.maxWidth < 500;
      final hp = narrow ? 16.0 : 28.0;
      final isAll = _selectedUnit == _allUnitsKey;
      final deviceLabel = isAll ? 'Toutes les unités' : (_deviceLabel[_selectedUnit] ?? _selectedUnit);
      return Container(
        padding: EdgeInsets.fromLTRB(hp, narrow ? 16 : 24, hp, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        narrow ? 'Résumé' : 'Résumé de consommation',
                        style: TextStyle(
                            color: _c.textPri,
                            fontWeight: FontWeight.bold,
                            fontSize: narrow ? 18 : 22),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$deviceLabel · Tarif: ${_tariffRate.toStringAsFixed(2)} MAD/kWh',
                        style: TextStyle(color: _c.textSec, fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (!isAll && _unitLastSeen != null) ...[
                        const SizedBox(height: 4),
                        Row(children: [
                          Icon(
                            _unitIsActive ? Icons.circle : Icons.circle_outlined,
                            size: 10,
                            color: _unitIsActive
                                ? const Color(0xFF2ECC71)
                                : const Color(0xFFE74C3C),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _unitIsActive
                                ? 'Actif · Dernière activité: ${_fmtLastSeen(_unitLastSeen!)}'
                                : 'Hors ligne · Dernière activité: ${_fmtLastSeen(_unitLastSeen!)}',
                            style: TextStyle(
                                color: _unitIsActive
                                    ? const Color(0xFF2ECC71)
                                    : const Color(0xFFE74C3C),
                                fontSize: 11),
                          ),
                        ]),
                      ],
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
            const SizedBox(height: 12),
            // ── Device selector ──────────────────────────────────────────────
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                _deviceChip('ALL_UNITS', Icons.grid_view, 'Tout'),
                _deviceChip('KOFERT_Unit_1', Icons.lightbulb_outline, 'Lampe'),
                _deviceChip('KOFERT_Unit_2', Icons.air, 'Ventilateur'),
                _deviceChip('KOFERT_Unit_3', Icons.water_outlined, 'Pompe'),
              ]),
            ),
            const SizedBox(height: 8),
            // ── Unit selectors ───────────────────────────────────────────
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    SizedBox(width: 70, child: Text('Énergie:', style: TextStyle(color: _c.textSec, fontSize: 12))),
                    const SizedBox(width: 6),
                    ...['mWh', 'Wh', 'kWh'].map((u) => Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: _unitChip(u),
                    )),
                  ]),
                  const SizedBox(height: 4),
                  Row(children: [
                    SizedBox(width: 70, child: Text('Puissance:', style: TextStyle(color: _c.textSec, fontSize: 12))),
                    const SizedBox(width: 6),
                    ...['mW', 'W', 'kW'].map((u) => Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: _powerUnitChip(u),
                    )),
                  ]),
                  const SizedBox(height: 4),
                  Row(children: [
                    SizedBox(width: 70, child: Text('Tension:', style: TextStyle(color: _c.textSec, fontSize: 12))),
                    const SizedBox(width: 6),
                    ...['mV', 'V'].map((u) => Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: _voltageUnitChip(u),
                    )),
                    const SizedBox(width: 12),
                    Text('Courant:', style: TextStyle(color: _c.textSec, fontSize: 12)),
                    const SizedBox(width: 6),
                    ...['mA', 'A'].map((u) => Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: _currentUnitChip(u),
                    )),
                  ]),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      );
    });
  }

  Widget _deviceChip(String unit, IconData icon, String label) {
    final sel = _selectedUnit == unit;
    return GestureDetector(
      onTap: () { setState(() => _selectedUnit = unit); _loadData(); },
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: sel ? kTeal.withValues(alpha: 0.15) : _c.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: sel ? kTeal : _c.divider),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: sel ? kTeal : _c.textSec),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(
            color: sel ? kTeal : _c.textSec,
            fontSize: 12,
            fontWeight: sel ? FontWeight.w600 : FontWeight.normal,
          )),
        ]),
      ),
    );
  }

  Widget _unitChip(String unit) {
    final sel = _energyUnit == unit;
    return GestureDetector(
      onTap: () async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('unitEnergy', unit);
        if (mounted) setState(() => _energyUnit = unit);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: sel ? kTeal.withValues(alpha: 0.15) : _c.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: sel ? kTeal : _c.divider),
        ),
        child: Text(unit, style: TextStyle(
          color: sel ? kTeal : _c.textSec,
          fontSize: 11,
          fontWeight: sel ? FontWeight.w600 : FontWeight.normal,
        )),
      ),
    );
  }

  Widget _powerUnitChip(String unit) {
    final sel = _powerUnit == unit;
    return GestureDetector(
      onTap: () async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('unitPower', unit);
        if (mounted) setState(() => _powerUnit = unit);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: sel ? kOrange.withValues(alpha: 0.15) : _c.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: sel ? kOrange : _c.divider),
        ),
        child: Text(unit, style: TextStyle(
          color: sel ? kOrange : _c.textSec,
          fontSize: 11,
          fontWeight: sel ? FontWeight.w600 : FontWeight.normal,
        )),
      ),
    );
  }

  Widget _voltageUnitChip(String unit) {
    final sel = _voltageUnit == unit;
    return GestureDetector(
      onTap: () async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('unitVoltage', unit);
        if (mounted) setState(() => _voltageUnit = unit);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: sel ? const Color(0xFF4FC3F7).withValues(alpha: 0.15) : _c.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: sel ? const Color(0xFF4FC3F7) : _c.divider),
        ),
        child: Text(unit, style: TextStyle(
          color: sel ? const Color(0xFF4FC3F7) : _c.textSec,
          fontSize: 11,
          fontWeight: sel ? FontWeight.w600 : FontWeight.normal,
        )),
      ),
    );
  }

  Widget _currentUnitChip(String unit) {
    final sel = _currentUnit == unit;
    return GestureDetector(
      onTap: () async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('unitCurrent', unit);
        if (mounted) setState(() => _currentUnit = unit);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: sel ? const Color(0xFFFF6B8A).withValues(alpha: 0.15) : _c.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: sel ? const Color(0xFFFF6B8A) : _c.divider),
        ),
        child: Text(unit, style: TextStyle(
          color: sel ? const Color(0xFFFF6B8A) : _c.textSec,
          fontSize: 11,
          fontWeight: sel ? FontWeight.w600 : FontWeight.normal,
        )),
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

    return LayoutBuilder(builder: (context, bc) {
      final p = bc.maxWidth < 500 ? 14.0 : 28.0;
      return SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(p, 20, p, 32),
        child: Column(
          children: [
            // KPI row
            _buildKpiRow([
              _KpiData('Énergie totale', _fmtE(totalEnergy), kTeal, Icons.bolt),
              _KpiData('Coût total', '${totalCost.toStringAsFixed(2)} MAD', kOrange, Icons.payments),
              _KpiData('Jours enregistrés', '${_dailySummaries.length}', const Color(0xFF4FC3F7), Icons.calendar_today),
              _KpiData('Moy. journalière', _fmtE(totalEnergy / _dailySummaries.length), const Color(0xFFFF6B8A), Icons.trending_up),
            ]),
            const SizedBox(height: 24),
            _buildDailyChart(),
            const SizedBox(height: 24),
            _buildDailyTable(),
          ],
        ),
      );
    });
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
                labelFormat: '{value} $_energyUnit',
              ),
              tooltipBehavior: TooltipBehavior(enable: true),
              series: <CartesianSeries>[
                ColumnSeries<_DaySummary, String>(
                  dataSource: last14,
                  xValueMapper: (d, _) => d.date.substring(5),
                  yValueMapper: (d, _) => mwhToUnit(d.energyMwh, _energyUnit),
                  name: 'Énergie ($_energyUnit)',
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
          _tableRow('Date', 'Énergie ($_energyUnit)', 'Puiss. max ($_powerUnit)', 'Tension ($_voltageUnit)', 'Courant ($_currentUnit)', 'FP moy.', 'Coût', isHeader: true),
          const Divider(color: Colors.white12, height: 1),
          ...List.generate(_dailySummaries.length, (i) {
            final d = _dailySummaries[_dailySummaries.length - 1 - i];
            return Column(children: [
              _tableRow(
                d.date,
                _fmtE(d.energyMwh),
                _fmtP(d.peakPowerW),
                _fmtV(d.avgVoltageV),
                _fmtI(d.avgCurrentA),
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

    return LayoutBuilder(builder: (context, bc) {
      final p = bc.maxWidth < 500 ? 14.0 : 28.0;
      return SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(p, 20, p, 32),
        child: Column(
          children: [
            _buildKpiRow([
              _KpiData('Énergie totale', _fmtE(totalEnergy), kTeal, Icons.bolt),
              _KpiData('Coût total', '${totalCost.toStringAsFixed(2)} MAD', kOrange, Icons.payments),
              _KpiData('Mois enregistrés', '${_monthlySummaries.length}', const Color(0xFF4FC3F7), Icons.calendar_month),
              _KpiData('Moy. mensuelle', _fmtE(totalEnergy / _monthlySummaries.length), const Color(0xFFFF6B8A), Icons.trending_up),
            ]),
            const SizedBox(height: 24),
            _buildMonthlyChart(),
            const SizedBox(height: 24),
            _buildMonthlyTable(),
          ],
        ),
      );
    });
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
                labelFormat: '{value} $_energyUnit',
              ),
              tooltipBehavior: TooltipBehavior(enable: true),
              series: <CartesianSeries>[
                ColumnSeries<_MonthSummary, String>(
                  dataSource: _monthlySummaries,
                  xValueMapper: (m, _) => m.month,
                  yValueMapper: (m, _) => mwhToUnit(m.energyMwh, _energyUnit),
                  name: 'Énergie ($_energyUnit)',
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
          _tableRow('Mois', 'Énergie ($_energyUnit)', 'Puiss. max ($_powerUnit)', 'Tension ($_voltageUnit)', 'Courant ($_currentUnit)', 'FP moy.', 'Coût', isHeader: true),
          const Divider(color: Colors.white12, height: 1),
          ...List.generate(_monthlySummaries.length, (i) {
            final m = _monthlySummaries[_monthlySummaries.length - 1 - i];
            return Column(children: [
              _tableRow(
                m.month,
                _fmtE(m.energyMwh),
                _fmtP(m.peakPowerW),
                _fmtV(m.avgVoltageV),
                _fmtI(m.avgCurrentA),
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
    Widget card(_KpiData kpi) => Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _c.card,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: kpi.color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(kpi.icon, color: kpi.color, size: 18),
          ),
          const SizedBox(height: 10),
          Text(kpi.value,
              style: TextStyle(
                  color: kpi.color,
                  fontWeight: FontWeight.bold,
                  fontSize: 16),
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 3),
          Text(kpi.label,
              style: TextStyle(color: _c.textSec, fontSize: 10),
              overflow: TextOverflow.ellipsis),
        ],
      ),
    );

    return LayoutBuilder(builder: (context, bc) {
      final narrow = bc.maxWidth < 500;
      if (narrow && items.length == 4) {
        return Column(children: [
          Row(children: [
            Expanded(child: card(items[0])),
            const SizedBox(width: 10),
            Expanded(child: card(items[1])),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: card(items[2])),
            const SizedBox(width: 10),
            Expanded(child: card(items[3])),
          ]),
        ]);
      }
      return Row(
        children: items.asMap().entries.map((e) => Expanded(
          child: Container(
            margin: EdgeInsets.only(left: e.key == 0 ? 0 : 12),
            child: card(e.value),
          ),
        )).toList(),
      );
    });
  }

  Widget _tableRow(String c1, String c2, String c3, String c4, String c5,
      String c6, String c7, {bool isHeader = false}) {
    final style = isHeader
        ? TextStyle(color: _c.textSec, fontSize: 11, fontWeight: FontWeight.w600)
        : TextStyle(color: _c.textPri, fontSize: 12);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: 640,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Row(
            children: [
              SizedBox(width: 100, child: Text(c1, style: style)),
              SizedBox(width: 90,  child: Text(c2, style: style, textAlign: TextAlign.right)),
              SizedBox(width: 85,  child: Text(c3, style: style, textAlign: TextAlign.right)),
              SizedBox(width: 80,  child: Text(c4, style: style, textAlign: TextAlign.right)),
              SizedBox(width: 80,  child: Text(c5, style: style, textAlign: TextAlign.right)),
              SizedBox(width: 60,  child: Text(c6, style: style, textAlign: TextAlign.right)),
              SizedBox(width: 85,  child: Text(c7, style: style, textAlign: TextAlign.right)),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Data models ───────────────────────────────────────────────────────────────
class _DaySummary {
  final String date;
  final double energyMwh;
  final double peakPowerW;
  final double avgPowerW;
  final double avgVoltageV;
  final double avgCurrentA;
  final double avgPowerFactor;
  final double cost;
  final int samples;
  const _DaySummary({
    required this.date,
    required this.energyMwh,
    required this.peakPowerW,
    required this.avgPowerW,
    required this.avgVoltageV,
    required this.avgCurrentA,
    required this.avgPowerFactor,
    required this.cost,
    required this.samples,
  });
}

class _MonthSummary {
  final String month;
  final double energyMwh;
  final double peakPowerW;
  final double avgPowerW;
  final double avgVoltageV;
  final double avgCurrentA;
  final double avgPowerFactor;
  final double cost;
  final int activeDays;
  const _MonthSummary({
    required this.month,
    required this.energyMwh,
    required this.peakPowerW,
    required this.avgPowerW,
    required this.avgVoltageV,
    required this.avgCurrentA,
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