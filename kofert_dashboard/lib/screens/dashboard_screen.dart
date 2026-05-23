import 'dart:async';
// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'package:syncfusion_flutter_gauges/gauges.dart' as sfg;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/energy_data.dart';
import '../models/alert_entry.dart';
import '../services/energy_repository.dart';
import '../main.dart'
    show
        kTeal,
        kOrange,
        alertLogNotifier,
        selectedUnitNotifier,
        roleNotifier,
        browserNotifNotifier;
import '../l10n/app_strings.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  AppColors get _c => AppColors.of(context);
  StreamSubscription? _sub;
  Timer? _noDataTimer;        // fallback: show no-data if Firebase never responds
  Timer? _clockTimer;         // ticks every second for live clock
  DateTime _now = DateTime.now();
  EnergyData? _current;
  EnergyData? _cachedFallback;  // shown when Firebase is unreachable
  final List<EnergyData> _history = [];
  bool _alertsEnabled = true;
  int _activeAlertsCount = 0;
  double _tariffRate = 1.15;
  String _selectedUnit = 'KOFERT_Unit_1';
  bool _noData = false;  // true when Firebase path exists but has no readings
  bool _autoRefresh = true;
  int _refreshInterval = 1;          // seconds — throttle UI updates (1 s for live history)
  DateTime _lastUiUpdate = DateTime(2000);

  double _fanSpeedPercent = 0.0;
  Timer? _fanControlDebounce;
  StreamSubscription? _fanControlSub;

  String _pumpStatus = 'OFF'; // 'ON' or 'OFF'
  StreamSubscription? _pumpControlSub;

  static const _units = ['KOFERT_Unit_1', 'KOFERT_Unit_2', 'KOFERT_Unit_3'];

  static String _labelFor(String unit) {
    switch (unit) {
      case 'KOFERT_Unit_1': return AppStrings.t('device_lamp');
      case 'KOFERT_Unit_2': return AppStrings.t('device_fan_5v');
      case 'KOFERT_Unit_3': return AppStrings.t('device_pump_5v');
      default: return unit;
    }
  }

  static const _deviceIcon = {
    'KOFERT_Unit_1': Icons.lightbulb_outline,
    'KOFERT_Unit_2': Icons.air,
    'KOFERT_Unit_3': Icons.water_outlined,
  };

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _alertsEnabled   = prefs.getBool('alertsEnabled') ?? true;
      _tariffRate      = prefs.getDouble('tariffRate') ?? 1.15;
      _selectedUnit    = prefs.getString('selectedUnit') ?? 'KOFERT_Unit_1';
      _autoRefresh     = prefs.getBool('autoRefresh') ?? true;
      _refreshInterval = prefs.getInt('refreshInterval') ?? 5;
    });
    selectedUnitNotifier.value = _selectedUnit;
    _resubscribe();
  }

  void _resubscribe() {
    _sub?.cancel();
    _noDataTimer?.cancel();

    if (!_autoRefresh) {
      // When auto-refresh is disabled, stop streaming but keep last data visible.
      return;
    }

    // If Firebase doesn't respond within 8 s, stop spinning and try cache.
    _noDataTimer = Timer(const Duration(seconds: 8), () async {
      if (mounted && _current == null) {
        final cached = await EnergyRepository.instance.getCachedReading(_selectedUnit);
        if (mounted) {
          setState(() {
            _cachedFallback = cached;
            _noData = true;
          });
        }
      }
    });
    _sub = FirebaseDatabase.instance
        .ref('$_selectedUnit/current_metrics')
        .onValue
        .listen(_onData);

    // Sync fan control slider with Firebase (Unit 2 only)
    _fanControlSub?.cancel();
    if (_selectedUnit == 'KOFERT_Unit_2') {
      _fanControlSub = FirebaseDatabase.instance
          .ref('KOFERT_Unit_2/fan_control/speed_percent')
          .onValue
          .listen((event) {
        final v = event.snapshot.value;
        if (v != null && mounted) {
          setState(() =>
              _fanSpeedPercent = (v as num).toDouble().clamp(0.0, 100.0));
        }
      });
    }

    // Sync pump status from Firebase (Unit 3 only)
    _pumpControlSub?.cancel();
    if (_selectedUnit == 'KOFERT_Unit_3') {
      _pumpControlSub = FirebaseDatabase.instance
          .ref('KOFERT_Unit_3/current_metrics/pump_status')
          .onValue
          .listen((event) {
        final v = event.snapshot.value;
        if (v != null && mounted) {
          setState(() => _pumpStatus = v.toString());
        }
      });
    }
  }

  Future<void> _switchUnit(String unit) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selectedUnit', unit);
    setState(() {
      _selectedUnit = unit;
      _current = null;
      _noData = false;
      _history.clear();
      _cachedFallback = null;
    });
    selectedUnitNotifier.value = unit;
    _resubscribe();
  }

  void _onData(DatabaseEvent event) {
    _noDataTimer?.cancel();
    if (event.snapshot.value == null) {
      if (mounted) setState(() => _noData = true);
      return;
    }
    // Throttle UI updates to the configured refresh interval.
    final now = DateTime.now();
    if (now.difference(_lastUiUpdate).inSeconds < _refreshInterval) return;
    _lastUiUpdate = now;

    setState(() => _noData = false);
    try {
      final e = EnergyData.fromJson(
          event.snapshot.value as Map<dynamic, dynamic>, _selectedUnit);
      if (!mounted) return;
      setState(() {
        _noData = false;
        _current = e;
        _history.add(e);
        if (_history.length > 60) _history.removeAt(0);
        _updateAlerts(e);
      });
    } catch (_) {
      // Parsing failed — treat as no data so we don't spin forever
      if (mounted) setState(() => _noData = true);
    }  }

  void _updateAlerts(EnergyData data) {
    if (!_alertsEnabled) { _activeAlertsCount = 0; return; }
    SharedPreferences.getInstance().then((prefs) {
      int count = 0;
      final vHigh = prefs.getDouble('voltageThresholdHigh') ?? 250.0;
      final vLow  = prefs.getDouble('voltageThresholdLow') ?? 200.0;
      final iMax  = prefs.getDouble('currentThreshold') ?? 50.0;
      final pfMin = prefs.getDouble('powerFactorThreshold') ?? 0.8;

      // Voltage alerts only apply to Unit 1 (AC 220V) — Unit 2/3 are 5V DC
      if (_selectedUnit == 'KOFERT_Unit_1') {
        if (data.voltage > vHigh || data.voltage < vLow) {
          count++;
          _logAlert(data.hasHighVoltage ? 'Surtension' : 'Sous-tension',
              '${data.voltage.toStringAsFixed(1)} V', const Color(0xFFE74C3C));
        }
      }
      if (data.current > iMax) {
        count++;
        _logAlert('Surcharge courant', '${data.current.toStringAsFixed(2)} A',
            const Color(0xFFE74C3C));
      }
      // Power factor & reactive power alerts only apply to Unit 1 (AC) — INA219 units are DC
      if (_selectedUnit == 'KOFERT_Unit_1') {
        if (data.powerFactor < pfMin && data.powerFactor > 0) {
          count++;
          _logAlert('Facteur de puissance bas',
              'FP = ${data.powerFactor.toStringAsFixed(3)}', kOrange);
        }
        if (data.hasHighReactivePower) {
          count++;
          _logAlert('Puissance réactive élevée',
              '${data.reactivePower.toStringAsFixed(0)} VAR', kOrange);
        }
      }
      if (mounted && count != _activeAlertsCount) {
        final prev = _activeAlertsCount;
        setState(() => _activeAlertsCount = count);
        if (count > prev) _fireBrowserNotification(count);
      }
    });
  }

  void _fireBrowserNotification(int count) {
    if (!browserNotifNotifier.value) return;
    try {
      if (html.Notification.supported &&
          html.Notification.permission == 'granted') {
        html.Notification(
          'KOFERT – $count ${AppStrings.t('alerts_count')}',
          body: '${_labelFor(_selectedUnit)}: alerte détectée',
        );
      } else if (html.Notification.supported &&
          html.Notification.permission != 'denied') {
        html.Notification.requestPermission();
      }
    } catch (_) {}
  }

  void _logAlert(String title, String detail, Color color) {
    final log = alertLogNotifier.value;
    if (log.isNotEmpty &&
        log.last.title == title &&
        DateTime.now().difference(log.last.time).inSeconds < 30) {
      return;
    }
    final entry = AlertEntry(
        title: title,
        detail: detail,
        color: color,
        time: DateTime.now(),
        unitId: _selectedUnit);
    // Update global notifier (creates a new list so listeners fire).
    alertLogNotifier.value = [...log, entry];
  }

  void _setFanSpeed(double pct) {
    setState(() => _fanSpeedPercent = pct);
    _fanControlDebounce?.cancel();
    _fanControlDebounce = Timer(const Duration(milliseconds: 400), () {
      final pwmValue = (pct / 100.0 * 255).round();
      FirebaseDatabase.instance
          .ref('KOFERT_Unit_2/fan_control')
          .update({'speed_percent': pct.round(), 'pwm_value': pwmValue});
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _fanControlSub?.cancel();
    _pumpControlSub?.cancel();
    _noDataTimer?.cancel();
    _clockTimer?.cancel();
    _fanControlDebounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _c.bg,
      body: _noData
          ? _buildNoData()
          : _current == null
              ? _buildLoading()
              : _buildContent(),
    );
  }

  Widget _buildLoading() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(color: kTeal),
          const SizedBox(height: 16),
          Text('${AppStrings.t('connecting_to')} $_selectedUnit (${_labelFor(_selectedUnit)})…',
              style: TextStyle(color: _c.textSec)),
        ],
      ),
    );
  }

  Widget _buildNoData() {
    // If we have a cached reading, show it with a banner instead of blank state.
    if (_cachedFallback != null) {
      return Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            color: kOrange.withValues(alpha: 0.15),
            child: Row(children: [
              const Icon(Icons.wifi_off_rounded,
                  color: kOrange, size: 16),
              const SizedBox(width: 8),
              Text(
                'Hors ligne — données en cache du '
                '${_cachedFallback!.timestamp.day.toString().padLeft(2, '0')}/'
                '${_cachedFallback!.timestamp.month.toString().padLeft(2, '0')} '
                '${_cachedFallback!.timestamp.hour.toString().padLeft(2, '0')}:'
                '${_cachedFallback!.timestamp.minute.toString().padLeft(2, '0')}',
                style:
                    const TextStyle(color: kOrange, fontSize: 12),
              ),
            ]),
          ),
          Expanded(
            child: LayoutBuilder(builder: (context, constraints) {
              final m = constraints.maxWidth < 600;
              return SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(m ? 14 : 28, m ? 16 : 28, m ? 14 : 28, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildPageHeader(m),
                    const SizedBox(height: 20),
                    _buildStatRow1(_cachedFallback!, m),
                    const SizedBox(height: 14),
                    _buildStatRow2(_cachedFallback!, m),
                    const SizedBox(height: 24),
                    _buildBottomRow(_cachedFallback!, m),
                  ],
                ),
              );
            }),
          ),
        ],
      );
    }
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.sensors_off_rounded, color: _c.textSec, size: 52),
          const SizedBox(height: 16),
          Text(
            AppStrings.t('no_data'),
            style: TextStyle(
                color: _c.textPri, fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 8),
          Text(
            'Aucune donnée disponible pour cette unité.\nVérifiez que le dispositif est allumé et connecté.',
            style: TextStyle(color: _c.textSec, fontSize: 13),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: () {
              setState(() => _noData = false);
              _resubscribe();
            },
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Réessayer'),
            style: OutlinedButton.styleFrom(
              foregroundColor: kTeal,
              side: BorderSide(color: kTeal.withValues(alpha: 0.5)),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    final d = _current!;
    final log = alertLogNotifier.value;
    return LayoutBuilder(builder: (context, constraints) {
      final m = constraints.maxWidth < 600;
      return SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(m ? 14 : 28, m ? 16 : 28, m ? 14 : 28, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildPageHeader(m),
            const SizedBox(height: 20),
            if (_alertsEnabled && _activeAlertsCount > 0) ...[
              _buildAlertBanner(d),
              const SizedBox(height: 20),
            ],
            _buildStatRow1(d, m),
            const SizedBox(height: 14),
            _buildStatRow2(d, m),
            if (_selectedUnit == 'KOFERT_Unit_2') ...[
              const SizedBox(height: 14),
              _buildFanRow(d, m),
              if (roleNotifier.value != 'viewer' && roleNotifier.value != 'observer') ...[
                const SizedBox(height: 14),
                _buildFanSpeedControl(),
              ],
            ],
            if (_selectedUnit == 'KOFERT_Unit_3') ...[
              const SizedBox(height: 14),
              _buildPumpControl(d, editable: roleNotifier.value != 'viewer' && roleNotifier.value != 'observer', isMobile: m),
            ],
            const SizedBox(height: 24),
            _buildPowerOverview(m),
            const SizedBox(height: 20),
            _buildBottomRow(d, m),
            if (log.isNotEmpty) ...[
              const SizedBox(height: 24),
              _buildAlertLog(log),
            ],
          ],
        ),
      );
    });
  }

  // ── Page header ────────────────────────────────────────────────────────────
  Widget _buildPageHeader(bool m) {
    if (m) {
      return Row(children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(color: _c.card, borderRadius: BorderRadius.circular(12)),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedUnit,
                isExpanded: true,
                dropdownColor: _c.card,
                style: TextStyle(color: _c.textPri, fontSize: 13),
                icon: Icon(Icons.expand_more, color: _c.textSec, size: 16),
                items: _units.map((u) => DropdownMenuItem(
                  value: u,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(_deviceIcon[u]!, color: kTeal, size: 14),
                    const SizedBox(width: 6),
                    Flexible(child: Text(_labelFor(u), overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: _c.textPri, fontSize: 13))),
                  ]),
                )).toList(),
                onChanged: (v) { if (v != null) _switchUnit(v); },
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: _showAlertDialog,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: (_activeAlertsCount > 0 ? const Color(0xFFE74C3C) : kTeal).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _activeAlertsCount > 0 ? const Color(0xFFE74C3C) : kTeal),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(_activeAlertsCount > 0 ? Icons.warning_rounded : Icons.check_circle_outline_rounded,
                  size: 14, color: _activeAlertsCount > 0 ? const Color(0xFFE74C3C) : kTeal),
              const SizedBox(width: 4),
              Text('$_activeAlertsCount',
                  style: TextStyle(
                      color: _activeAlertsCount > 0 ? const Color(0xFFE74C3C) : kTeal,
                      fontWeight: FontWeight.w600, fontSize: 12)),
            ]),
          ),
        ),
        const SizedBox(width: 8),
        _buildConnectivityBadge(),
      ]);
    }
    // ── Desktop header ─────────────────────────────────────────────────────
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(color: _c.card, borderRadius: BorderRadius.circular(12)),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _selectedUnit,
              dropdownColor: _c.card,
              style: TextStyle(color: _c.textPri, fontSize: 14),
              icon: Icon(Icons.expand_more, color: _c.textSec, size: 18),
              items: _units.map((u) {
                final icon = _deviceIcon[u]!;
                final label = _labelFor(u);
                return DropdownMenuItem(
                  value: u,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(icon, color: kTeal, size: 16),
                    const SizedBox(width: 8),
                    Text('$u  —  $label', style: TextStyle(color: _c.textPri)),
                  ]),
                );
              }).toList(),
              onChanged: (v) { if (v != null) _switchUnit(v); },
            ),
          ),
        ),
        const SizedBox(width: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(color: _c.card, borderRadius: BorderRadius.circular(12)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(_deviceIcon[_selectedUnit]!, color: kTeal, size: 16),
            const SizedBox(width: 8),
            Text(_labelFor(_selectedUnit),
                style: TextStyle(color: _c.textPri, fontSize: 13, fontWeight: FontWeight.w600)),
          ]),
        ),
        const SizedBox(width: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(color: _c.card, borderRadius: BorderRadius.circular(12)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.payments_outlined, color: kOrange, size: 16),
            const SizedBox(width: 6),
            Text('${_tariffRate.toStringAsFixed(2)} MAD/mWh',
                style: const TextStyle(color: kOrange, fontSize: 13)),
          ]),
        ),
        const Spacer(),
        // ── Live clock ──────────────────────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
              color: _c.card, borderRadius: BorderRadius.circular(12)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.access_time_rounded, color: _c.textSec, size: 15),
            const SizedBox(width: 7),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${_now.hour.toString().padLeft(2, '0')}:${_now.minute.toString().padLeft(2, '0')}:${_now.second.toString().padLeft(2, '0')}',
                  style: TextStyle(
                      color: _c.textPri,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      fontFeatures: [FontFeature.tabularFigures()]),
                ),
                Text(
                  '${_now.day.toString().padLeft(2, '0')}/${_now.month.toString().padLeft(2, '0')}/${_now.year}',
                  style: TextStyle(color: _c.textSec, fontSize: 10),
                ),
              ],
            ),
          ]),
        ),
        const SizedBox(width: 12),
          GestureDetector(
            onTap: _showAlertDialog,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: (_activeAlertsCount > 0
                        ? const Color(0xFFE74C3C)
                        : kTeal)
                    .withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: _activeAlertsCount > 0
                      ? const Color(0xFFE74C3C)
                      : kTeal,
                  width: 1,
                ),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(
                  _activeAlertsCount > 0
                      ? Icons.warning_rounded
                      : Icons.check_circle_outline_rounded,
                  size: 16,
                  color: _activeAlertsCount > 0
                      ? const Color(0xFFE74C3C)
                      : kTeal,
                ),
                const SizedBox(width: 6),
                Text('$_activeAlertsCount ${AppStrings.t('alerts_count')}',
                    style: TextStyle(
                        color: _activeAlertsCount > 0
                            ? const Color(0xFFE74C3C)
                            : kTeal,
                        fontWeight: FontWeight.w600,
                        fontSize: 13)),
              ]),
            ),
          ),
        const SizedBox(width: 12),
        _buildConnectivityBadge(),
      ],
    );
  }

  Widget _buildConnectivityBadge() {
    if (_current == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.grey.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                  color: Colors.grey, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(AppStrings.t('sensor_offline'),
              style: const TextStyle(color: Colors.grey, fontSize: 12)),
        ]),
      );
    }
    final age = DateTime.now().difference(_current!.timestamp);
    if (age.inSeconds > 90) {
      final label =
          age.inMinutes >= 1 ? '${age.inMinutes}m' : '${age.inSeconds}s';
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: kOrange.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: kOrange.withValues(alpha: 0.4)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.sensors_off_rounded, color: kOrange, size: 13),
          const SizedBox(width: 5),
          Text('${AppStrings.t('data_stale')} · $label',
              style: const TextStyle(color: kOrange, fontSize: 12)),
        ]),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
          color: kTeal.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
            width: 8,
            height: 8,
            decoration:
                const BoxDecoration(color: kTeal, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(AppStrings.t('online'),
            style: const TextStyle(color: kTeal, fontSize: 12)),
      ]),
    );
  }

  // ── Stat rows ──────────────────────────────────────────────────────────────
  Widget _buildStatRow1(EnergyData d, bool m) {
    final c1 = _StatCard(icon: '⚡', iconBg: kOrange,
        value: d.power.toStringAsFixed(1), unit: 'W', label: AppStrings.t('active_power'));
    final c2 = _StatCard(icon: '🔋', iconBg: kTeal,
        value: d.energy.toStringAsFixed(2), unit: 'mWh', label: AppStrings.t('energy_consumed'));
    final c3 = _StatCard(icon: '🔌', iconBg: const Color(0xFFFF6B8A),
        value: d.voltage.toStringAsFixed(1), unit: 'V', label: AppStrings.t('voltage'),
        alert: d.hasHighVoltage || d.hasLowVoltage);
    final c4 = _StatCard(icon: '〰', iconBg: const Color(0xFF4FC3F7),
        value: d.current.toStringAsFixed(2), unit: 'A', label: AppStrings.t('current'),
        alert: d.hasHighCurrent);
    if (m) {
      return Column(children: [
        Row(children: [Expanded(child: c1), const SizedBox(width: 10), Expanded(child: c2)]),
        const SizedBox(height: 10),
        Row(children: [Expanded(child: c3), const SizedBox(width: 10), Expanded(child: c4)]),
      ]);
    }
    return Row(children: [
      Expanded(child: c1), const SizedBox(width: 14),
      Expanded(child: c2), const SizedBox(width: 14),
      Expanded(child: c3), const SizedBox(width: 14),
      Expanded(child: c4),
    ]);
  }

  Widget _buildStatRow2(EnergyData d, bool m) {
    final cost = d.energy * _tariffRate;
    // INA219 units (Unit 2 fan 5 V DC, Unit 3 pump 5 V DC) — no AC metrics.
    if (d.isINA219) {
      final powerMw = d.power * 1000; // W → mW for display clarity at low wattage
      final i1 = _StatCard(icon: '🔬', iconBg: const Color(0xFF9B59B6),
          value: 'INA219', unit: 'DC', label: AppStrings.t('dc_sensor'));
      final i2 = _StatCard(icon: '⚡', iconBg: const Color(0xFF1ABC9C),
          value: powerMw.toStringAsFixed(1), unit: 'mW', label: AppStrings.t('dc_power'));
      final i3 = _StatCard(icon: '🌊', iconBg: const Color(0xFF3498DB),
          value: (d.current * 1000).toStringAsFixed(1), unit: 'mA', label: AppStrings.t('dc_current'));
      final i4 = _StatCard(icon: '💰', iconBg: kOrange,
          value: cost.toStringAsFixed(4), unit: 'MAD', label: AppStrings.t('estimated_cost'));
      if (m) {
        return Column(children: [
          Row(children: [Expanded(child: i1), const SizedBox(width: 10), Expanded(child: i2)]),
          const SizedBox(height: 10),
          Row(children: [Expanded(child: i3), const SizedBox(width: 10), Expanded(child: i4)]),
        ]);
      }
      return Row(children: [
        Expanded(child: i1), const SizedBox(width: 14),
        Expanded(child: i2), const SizedBox(width: 14),
        Expanded(child: i3), const SizedBox(width: 14),
        Expanded(child: i4),
      ]);
    }
    // AC unit (Unit 1) — full metrics
    final a1 = _StatCard(icon: '📐', iconBg: const Color(0xFF9B59B6),
        value: d.apparentPower.toStringAsFixed(1), unit: 'VA', label: AppStrings.t('apparent_power'));
    final a2 = _StatCard(icon: '🌀', iconBg: const Color(0xFF1ABC9C),
        value: d.reactivePower.toStringAsFixed(1), unit: 'VAR', label: AppStrings.t('reactive_power'),
        alert: d.hasHighReactivePower);
    final a3 = _StatCard(icon: '🎵', iconBg: const Color(0xFF3498DB),
        value: d.frequency.toStringAsFixed(2), unit: 'Hz', label: AppStrings.t('frequency'));
    final a4 = _StatCard(icon: '💰', iconBg: kOrange,
        value: cost.toStringAsFixed(2), unit: 'MAD', label: AppStrings.t('estimated_cost'));
    if (m) {
      return Column(children: [
        Row(children: [Expanded(child: a1), const SizedBox(width: 10), Expanded(child: a2)]),
        const SizedBox(height: 10),
        Row(children: [Expanded(child: a3), const SizedBox(width: 10), Expanded(child: a4)]),
      ]);
    }
    return Row(children: [
      Expanded(child: a1), const SizedBox(width: 14),
      Expanded(child: a2), const SizedBox(width: 14),
      Expanded(child: a3), const SizedBox(width: 14),
      Expanded(child: a4),
    ]);
  }

  // ── Pump control + water level (only for KOFERT_Unit_3) ──────────────────
  void _setPumpStatus(String status) {
    setState(() => _pumpStatus = status);
    FirebaseDatabase.instance
        .ref('KOFERT_Unit_3/current_metrics/pump_status')
        .set(status);
  }

  Widget _buildPumpControl(EnergyData d, {bool editable = true, bool isMobile = false}) {
    final bool isOn = _pumpStatus == 'ON';
    final Color pumpColor = isOn ? kTeal : _c.textSec;
    final int water = d.waterLevel.clamp(0, 100);
    final Color waterColor = water < 20
        ? const Color(0xFFE74C3C)
        : water < 50
            ? kOrange
            : kTeal;

    final pumpCard = Container(
      decoration: BoxDecoration(
          color: _c.card, borderRadius: BorderRadius.circular(16)),
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: pumpColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.water_outlined, color: pumpColor, size: 22),
            ),
            const SizedBox(width: 12),
            Flexible(child: Text('Contrôle Pompe',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: _c.textPri, fontWeight: FontWeight.bold, fontSize: 15))),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: pumpColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: pumpColor.withValues(alpha: 0.5)),
              ),
              child: Text(isOn ? 'EN MARCHE' : 'ARRÊTÉE',
                  style: TextStyle(color: pumpColor, fontWeight: FontWeight.bold, fontSize: 13)),
            ),
          ]),
          const SizedBox(height: 20),
          Row(children: [
            Expanded(
              child: GestureDetector(
                onTap: (isOn || !editable) ? null : () => _setPumpStatus('ON'),
                child: Opacity(
                  opacity: editable ? 1.0 : 0.5,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: isOn ? kTeal.withValues(alpha: 0.18) : Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: isOn ? kTeal : Colors.white.withValues(alpha: 0.1)),
                    ),
                    child: Column(children: [
                      Icon(Icons.power_settings_new, color: isOn ? kTeal : _c.textSec, size: 28),
                      const SizedBox(height: 6),
                      Text(AppStrings.t('running'), style: TextStyle(
                          color: isOn ? kTeal : _c.textSec, fontWeight: FontWeight.bold, fontSize: 13)),
                    ]),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: GestureDetector(
                onTap: (!isOn || !editable) ? null : () => _setPumpStatus('OFF'),
                child: Opacity(
                  opacity: editable ? 1.0 : 0.5,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: !isOn ? const Color(0xFFE74C3C).withValues(alpha: 0.18) : Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: !isOn ? const Color(0xFFE74C3C) : Colors.white.withValues(alpha: 0.1)),
                    ),
                    child: Column(children: [
                      Icon(Icons.stop_circle_outlined,
                          color: !isOn ? const Color(0xFFE74C3C) : _c.textSec, size: 28),
                      const SizedBox(height: 6),
                      Text(AppStrings.t('stopped'), style: TextStyle(
                          color: !isOn ? const Color(0xFFE74C3C) : _c.textSec,
                          fontWeight: FontWeight.bold, fontSize: 13)),
                    ]),
                  ),
                ),
              ),
            ),
          ]),
        ],
      ),
    );

    final waterCard = Container(
      decoration: BoxDecoration(
          color: _c.card, borderRadius: BorderRadius.circular(16)),
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: waterColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.water_drop_outlined, color: waterColor, size: 22),
            ),
            const SizedBox(width: 12),
            Flexible(child: Text('Niveau Réservoir',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: _c.textPri, fontWeight: FontWeight.bold, fontSize: 15))),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: waterColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: waterColor.withValues(alpha: 0.5)),
              ),
              child: Text('$water %',
                  style: TextStyle(color: waterColor, fontWeight: FontWeight.bold, fontSize: 16)),
            ),
          ]),
          const SizedBox(height: 20),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: water / 100.0,
              minHeight: 18,
              backgroundColor: Colors.white.withValues(alpha: 0.07),
              valueColor: AlwaysStoppedAnimation<Color>(waterColor),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('0 %', style: TextStyle(color: _c.textSec, fontSize: 11)),
              Text(
                water < 20 ? 'Niveau critique !' : water < 50 ? 'Niveau bas'
                    : water < 80 ? 'Niveau correct' : 'Niveau élevé',
                style: TextStyle(color: waterColor, fontSize: 12, fontWeight: FontWeight.w600),
              ),
              Text('100 %', style: TextStyle(color: _c.textSec, fontSize: 11)),
            ],
          ),
          if (water < 20) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFE74C3C).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFE74C3C).withValues(alpha: 0.4)),
              ),
              child: Row(children: [
                const Icon(Icons.warning_amber_rounded, color: Color(0xFFE74C3C), size: 16),
                const SizedBox(width: 8),
                Text(AppStrings.t('refill_tank'),
                    style: const TextStyle(color: Color(0xFFE74C3C), fontSize: 12, fontWeight: FontWeight.w600)),
              ]),
            ),
          ],
        ],
      ),
    );

    if (isMobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [pumpCard, const SizedBox(height: 14), waterCard],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: pumpCard),
        const SizedBox(width: 14),
        Expanded(child: waterCard),
      ],
    );
  }

  // ── Fan speed control card (only for KOFERT_Unit_2) ────────────────────────
  Widget _buildFanSpeedControl() {
    final pct = _fanSpeedPercent;
    final Color speedColor = pct == 0
        ? _c.textSec
        : pct < 40
            ? kTeal
            : pct < 75
                ? kOrange
                : const Color(0xFFE74C3C);

    return Container(
      decoration:
          BoxDecoration(color: _c.card, borderRadius: BorderRadius.circular(16)),
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFF5DADE2).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.air, color: Color(0xFF5DADE2), size: 22),
              ),
              const SizedBox(width: 12),
              Text(
                'Contrôle Vitesse Ventilateur',
                style: TextStyle(
                    color: _c.textPri,
                    fontWeight: FontWeight.bold,
                    fontSize: 15),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: speedColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border:
                      Border.all(color: speedColor.withValues(alpha: 0.5)),
                ),
                child: Text(
                  '${pct.round()} %',
                  style: TextStyle(
                      color: speedColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 16),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 8,
              activeTrackColor: speedColor,
              inactiveTrackColor: Colors.white.withValues(alpha: 0.08),
              thumbColor: speedColor,
              thumbShape:
                  const RoundSliderThumbShape(enabledThumbRadius: 10),
              overlayColor: speedColor.withValues(alpha: 0.2),
              overlayShape:
                  const RoundSliderOverlayShape(overlayRadius: 20),
            ),
            child: Slider(
              value: pct,
              min: 0,
              max: 100,
              divisions: 100,
              onChanged: _setFanSpeed,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('0 %', style: TextStyle(color: _c.textSec, fontSize: 11)),
              Text('25 %', style: TextStyle(color: _c.textSec, fontSize: 11)),
              Text('50 %', style: TextStyle(color: _c.textSec, fontSize: 11)),
              Text('75 %', style: TextStyle(color: _c.textSec, fontSize: 11)),
              Text('100 %', style: TextStyle(color: _c.textSec, fontSize: 11)),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _PresetBtn(label: 'Arrêt',  value: 0,   current: pct, onTap: _setFanSpeed),
              const SizedBox(width: 8),
              _PresetBtn(label: 'Faible', value: 25,  current: pct, onTap: _setFanSpeed),
              const SizedBox(width: 8),
              _PresetBtn(label: 'Moyen',  value: 50,  current: pct, onTap: _setFanSpeed),
              const SizedBox(width: 8),
              _PresetBtn(label: 'Rapide', value: 75,  current: pct, onTap: _setFanSpeed),
              const SizedBox(width: 8),
              _PresetBtn(label: 'Max',    value: 100, current: pct, onTap: _setFanSpeed),
            ],
          ),
        ],
      ),
    );
  }

  // ── Fan-specific metrics (only for KOFERT_Unit_2) ─────────────────────────
  Widget _buildFanRow(EnergyData d, bool m) {
    final card = _StatCard(
      icon: '💨',
      iconBg: const Color(0xFF5DADE2),
      value: d.windSpeed.toStringAsFixed(0),
      unit: '%',
      label: 'Vitesse actuelle (ESP32)',
    );
    if (m) return card;
    return Row(children: [
      Expanded(flex: 1, child: card),
      const SizedBox(width: 14),
      // Spacer cards to keep the row visually balanced (3 empty spaces)
      const Expanded(flex: 1, child: SizedBox()),
      const SizedBox(width: 14),
      const Expanded(flex: 1, child: SizedBox()),
      const SizedBox(width: 14),
      const Expanded(flex: 1, child: SizedBox()),
    ]);
  }

  // ── Alert banner ───────────────────────────────────────────────────────────
  Widget _buildAlertBanner(EnergyData d) {
    final parts = <String>[];
    if (d.hasHighVoltage) parts.add('Surtension (${d.voltage.toStringAsFixed(0)} V)');
    if (d.hasLowVoltage) parts.add('Sous-tension (${d.voltage.toStringAsFixed(0)} V)');
    if (d.hasHighCurrent) parts.add('Surcharge (${d.current.toStringAsFixed(1)} A)');
    if (d.hasLowPowerFactor) parts.add('FP bas (${d.powerFactor.toStringAsFixed(2)})');
    if (d.hasHighReactivePower) parts.add('Q élevée (${d.reactivePower.toStringAsFixed(0)} VAR)');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFE74C3C).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE74C3C).withValues(alpha: 0.4), width: 1),
      ),
      child: Row(children: [
        const Icon(Icons.warning_amber_rounded, color: Color(0xFFE74C3C), size: 22),
        const SizedBox(width: 12),
        Expanded(child: Text(parts.join('  •  '),
            style: const TextStyle(color: Color(0xFFE74C3C), fontSize: 13))),
        TextButton(
          onPressed: _showAlertDialog,
          child: Text(AppStrings.t('details'), style: const TextStyle(color: Color(0xFFE74C3C))),
        ),
      ]),
    );
  }

  // ── Power overview chart ──────────────────────────────────────────────────
  Widget _buildPowerOverview([bool m = false]) {
    final points = _history.asMap().entries
        .map((e) => _ChartPoint(e.key.toDouble(), e.value.power))
        .toList();
    final appPoints = _history.asMap().entries
        .map((e) => _ChartPoint(e.key.toDouble(), e.value.apparentPower))
        .toList();

    final legend = Row(children: [
      _LegendDot(color: kTeal, label: 'Active (W)'),
      const SizedBox(width: 14),
      _LegendDot(color: kOrange, label: 'Apparente (VA)'),
      const SizedBox(width: 14),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
            color: kTeal.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(20)),
        child: Text(AppStrings.t('live'),
            style: TextStyle(color: kTeal, fontSize: 11, fontWeight: FontWeight.w600)),
      ),
    ]);

    return Container(
      decoration: BoxDecoration(color: _c.card, borderRadius: BorderRadius.circular(16)),
      padding: const EdgeInsets.fromLTRB(20, 20, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (m) ...[  // On mobile: stack title and legend vertically to avoid overflow
            Text(AppStrings.t('power_overview'),
                style: TextStyle(color: _c.textPri, fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            legend,
          ] else
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(AppStrings.t('power_overview'),
                    style: TextStyle(color: _c.textPri, fontWeight: FontWeight.bold, fontSize: 16)),
                legend,
              ],
            ),
          const SizedBox(height: 16),
          SizedBox(
            height: 240,
            child: points.length < 2
                ? Center(child: Text(AppStrings.t('waiting_data'), style: TextStyle(color: _c.textSec)))
                : SfCartesianChart(
                    backgroundColor: _c.card,
                    plotAreaBorderWidth: 0,
                    margin: EdgeInsets.zero,
                    primaryXAxis: const NumericAxis(isVisible: false, borderColor: Colors.transparent),
                    primaryYAxis: NumericAxis(
                      labelStyle: TextStyle(color: _c.textSec, fontSize: 11),
                      axisLine: const AxisLine(color: Colors.transparent),
                      majorGridLines: MajorGridLines(
                          color: Colors.white.withValues(alpha: 0.06), width: 1),
                      majorTickLines: const MajorTickLines(size: 0),
                    ),
                    tooltipBehavior: TooltipBehavior(enable: true),
                    series: <CartesianSeries>[
                      SplineAreaSeries<_ChartPoint, double>(
                        dataSource: points,
                        xValueMapper: (p, _) => p.x,
                        yValueMapper: (p, _) => p.y,
                        name: 'Active (W)',
                        color: kTeal.withValues(alpha: 0.25),
                        borderColor: kTeal,
                        borderWidth: 2.5,
                        gradient: LinearGradient(
                          begin: Alignment.topCenter, end: Alignment.bottomCenter,
                          colors: [kTeal.withValues(alpha: 0.4), kTeal.withValues(alpha: 0.0)],
                        ),
                      ),
                      SplineSeries<_ChartPoint, double>(
                        dataSource: appPoints,
                        xValueMapper: (p, _) => p.x,
                        yValueMapper: (p, _) => p.y,
                        name: 'Apparente (VA)',
                        color: kOrange,
                        width: 1.8,
                        dashArray: const [6, 3],
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  // ── Bottom row: PF radial gauge + bar charts ──────────────────────────────
  Widget _buildBottomRow(EnergyData d, bool m) {
    final last7 = _history.length >= 7 ? _history.sublist(_history.length - 7) : _history;
    final labels = List.generate(last7.length, (i) => '${i + 1}');

    final pfChild = _buildPFGauge(d.powerFactor);
    final tChild = _MiniBarChart(
      title: 'Tension (V)', color: kOrange,
      data: last7.asMap().entries.map((e) => _BarItem(labels[e.key], e.value.voltage)).toList(),
    );
    final curChild = _MiniBarChart(
      title: 'Courant (A)', color: const Color(0xFFFF6B8A),
      data: last7.asMap().entries.map((e) => _BarItem(labels[e.key], e.value.current)).toList(),
    );
    final rChild = _MiniBarChart(
      title: 'Réactive (VAR)', color: const Color(0xFF9B59B6),
      data: last7.asMap().entries.map((e) => _BarItem(labels[e.key], e.value.reactivePower)).toList(),
    );

    if (m) {
      // On mobile, use intrinsic-height children directly — Expanded in an
      // unbounded Column (inside SingleChildScrollView) collapses to zero height.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          pfChild, const SizedBox(height: 10),
          tChild, const SizedBox(height: 10),
          curChild, const SizedBox(height: 10),
          rChild,
        ],
      );
    }
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(flex: 2, child: pfChild), const SizedBox(width: 14),
      Expanded(child: tChild), const SizedBox(width: 14),
      Expanded(child: curChild), const SizedBox(width: 14),
      Expanded(child: rChild),
    ]);
  }

  // ── Radial PF gauge ────────────────────────────────────────────────────────
  Widget _buildPFGauge(double pf) {
    final pfColor = pf >= 0.95 ? kTeal : pf >= 0.8 ? kOrange : const Color(0xFFE74C3C);
    return Container(
      decoration: BoxDecoration(color: _c.card, borderRadius: BorderRadius.circular(16)),
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        Text(AppStrings.t('power_factor'),
            style: TextStyle(color: _c.textPri, fontWeight: FontWeight.w600, fontSize: 13)),
        const SizedBox(height: 8),
        SizedBox(
          height: 190,
          child: sfg.SfRadialGauge(
            backgroundColor: _c.card,
            axes: [
              sfg.RadialAxis(
                minimum: 0, maximum: 1,
                startAngle: 150, endAngle: 30,
                radiusFactor: 0.9,
                axisLineStyle: const sfg.AxisLineStyle(thickness: 12, color: Color(0xFF2E2E40)),
                majorTickStyle: sfg.MajorTickStyle(length: 8, color: _c.textSec),
                minorTickStyle: sfg.MinorTickStyle(length: 4, color: _c.textSec),
                axisLabelStyle: sfg.GaugeTextStyle(color: _c.textSec, fontSize: 10),
                ranges: [
                  sfg.GaugeRange(startValue: 0, endValue: 0.7,
                      color: const Color(0xFFE74C3C).withValues(alpha: 0.4)),
                  sfg.GaugeRange(startValue: 0.7, endValue: 0.9,
                      color: kOrange.withValues(alpha: 0.4)),
                  sfg.GaugeRange(startValue: 0.9, endValue: 1.0,
                      color: kTeal.withValues(alpha: 0.4)),
                ],
                pointers: [
                  sfg.NeedlePointer(
                    value: pf.clamp(0.0, 1.0),
                    enableAnimation: true,
                    animationType: sfg.AnimationType.ease,
                    needleStartWidth: 1, needleEndWidth: 5, needleLength: 0.7,
                    needleColor: pfColor,
                    knobStyle: sfg.KnobStyle(knobRadius: 0.06, color: pfColor),
                  ),
                ],
                annotations: [
                  sfg.GaugeAnnotation(
                    widget: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(pf.toStringAsFixed(3),
                          style: TextStyle(color: pfColor, fontWeight: FontWeight.bold, fontSize: 20)),
                      const SizedBox(height: 2),
                      Text(
                        pf >= 0.95 ? 'Excellent' : pf >= 0.8 ? 'Correct' : 'Mauvais',
                        style: TextStyle(color: pfColor, fontSize: 11),
                      ),
                    ]),
                    angle: 90, positionFactor: 0.5,
                  ),
                ],
              ),
            ],
          ),
        ),
      ]),
    );
  }

  // ── Alert log ──────────────────────────────────────────────────────────────
  Widget _buildAlertLog(List<AlertEntry> log) {
    return Container(
      decoration: BoxDecoration(color: _c.card, borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          child: Row(children: [
            Icon(Icons.history, color: _c.textSec, size: 18),
            const SizedBox(width: 8),
            Text(AppStrings.t('alert_history'),
                style: TextStyle(color: _c.textPri, fontWeight: FontWeight.bold, fontSize: 15)),
            const Spacer(),
            TextButton(
              onPressed: () => setState(() => alertLogNotifier.value = []),
              child: Text(AppStrings.t('clear'), style: TextStyle(color: _c.textSec, fontSize: 12)),
            ),
          ]),
        ),
        const Divider(color: Colors.white12, height: 1),
        ...log.reversed.take(10).map((a) => _AlertRow(entry: a)),
      ]),
    );
  }

  // ── Alert dialog ───────────────────────────────────────────────────────────
  void _showAlertDialog() {
    final d = _current;
    if (d == null) return;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _c.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          const Icon(Icons.warning_amber_rounded, color: Color(0xFFE74C3C)),
          const SizedBox(width: 10),
          Text(AppStrings.t('active_alerts'), style: TextStyle(color: _c.textPri)),
        ]),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (d.hasHighVoltage) _alertDialogRow(AppStrings.t('alert_high_voltage'), '${d.voltage.toStringAsFixed(d.isINA219 ? 2 : 0)} V > ${d.isINA219 ? '5.5' : '250'} V', const Color(0xFFE74C3C)),
              if (d.hasLowVoltage) _alertDialogRow(AppStrings.t('alert_low_voltage'), '${d.voltage.toStringAsFixed(d.isINA219 ? 2 : 0)} V < ${d.isINA219 ? '4.0' : '200'} V', const Color(0xFFE74C3C)),
              if (d.hasHighCurrent) _alertDialogRow(AppStrings.t('alert_high_current'), '${d.current.toStringAsFixed(2)} A', const Color(0xFFE74C3C)),
              if (d.hasLowPowerFactor) _alertDialogRow(AppStrings.t('alert_low_pf'), 'FP = ${d.powerFactor.toStringAsFixed(3)}', kOrange),
              if (d.hasHighReactivePower) _alertDialogRow(AppStrings.t('alert_high_reactive'), '${d.reactivePower.toStringAsFixed(0)} VAR', kOrange),
              if (!d.hasAlerts) Text(AppStrings.t('no_active_alerts'), style: TextStyle(color: _c.textSec)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppStrings.t('close'), style: const TextStyle(color: kTeal)),
          ),
        ],
      ),
    );
  }

  Widget _alertDialogRow(String title, String detail, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Icon(Icons.circle, color: color, size: 10),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 13)),
          Text(detail, style: TextStyle(color: _c.textSec, fontSize: 12)),
        ])),
      ]),
    );
  }
}

// ── Stat card ─────────────────────────────────────────────────────────────────
class _StatCard extends StatelessWidget {
  final String icon;
  final Color iconBg;
  final String value;
  final String unit;
  final String label;
  final bool alert;

  const _StatCard({
    required this.icon,
    required this.iconBg,
    required this.value,
    required this.unit,
    required this.label,
    this.alert = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return LayoutBuilder(builder: (ctx, constraints) {
      final compact = constraints.maxWidth < 160;
      return Container(
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(16),
          border: alert
              ? Border.all(
                  color: const Color(0xFFE74C3C).withValues(alpha: 0.5),
                  width: 1)
              : null,
        ),
        padding: EdgeInsets.all(compact ? 12 : 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: compact ? 36 : 44,
              height: compact ? 36 : 44,
              decoration: BoxDecoration(
                color: iconBg.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(icon, style: TextStyle(fontSize: compact ? 18 : 22)),
              ),
            ),
            SizedBox(height: compact ? 10 : 16),
            Text(
              '$value $unit',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: c.textPri,
                fontWeight: FontWeight.bold,
                fontSize: compact ? 15 : 22,
              ),
            ),
            const SizedBox(height: 4),
            Text(label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: c.textSec, fontSize: 12)),
          ],
        ),
      );
    });
  }
}

// ── Mini bar chart ────────────────────────────────────────────────────────────
class _MiniBarChart extends StatelessWidget {
  final String title;
  final Color color;
  final List<_BarItem> data;

  const _MiniBarChart({
    required this.title,
    required this.color,
    required this.data,
  });

  String _fmt(double v) {
    if (v.abs() >= 1000) return v.toStringAsFixed(0);
    if (v.abs() >= 10) return v.toStringAsFixed(1);
    return v.toStringAsFixed(2);
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final currentValue = data.isNotEmpty ? data.last.value : null;
    return Container(
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
                color: c.textSec, fontWeight: FontWeight.w500, fontSize: 12),
          ),
          const SizedBox(height: 6),
          Text(
            currentValue != null ? _fmt(currentValue) : '–',
            style: TextStyle(
              color: color,
              fontSize: 28,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 80,
            child: data.length < 2
                ? Center(
                    child: Text(
                      'En attente\nde données…',
                      style: TextStyle(color: c.textSec, fontSize: 10),
                      textAlign: TextAlign.center,
                    ),
                  )
                : SfCartesianChart(
                    backgroundColor: c.card,
                    plotAreaBorderWidth: 0,
                    margin: EdgeInsets.zero,
                    primaryXAxis: CategoryAxis(
                      isVisible: false,
                      majorGridLines: const MajorGridLines(width: 0),
                    ),
                    primaryYAxis: const NumericAxis(
                      isVisible: false,
                    ),
                    series: <CartesianSeries>[
                      ColumnSeries<_BarItem, String>(
                        dataSource: data,
                        xValueMapper: (d, _) => d.label,
                        yValueMapper: (d, _) => d.value,
                        color: color,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(3),
                          topRight: Radius.circular(3),
                        ),
                        width: 0.6,
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [color, color.withValues(alpha: 0.4)],
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

// ── Chart data models ─────────────────────────────────────────────────────────
class _ChartPoint {
  final double x;
  final double y;
  const _ChartPoint(this.x, this.y);
}

class _BarItem {
  final String label;
  final double value;
  const _BarItem(this.label, this.value);
}

// ── Legend dot ────────────────────────────────────────────────────────────────
class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 10, height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 5),
      Text(label, style: TextStyle(color: c.textSec, fontSize: 11)),
    ]);
  }
}

// ── Alert row widget ──────────────────────────────────────────────────────────
class _AlertRow extends StatelessWidget {
  final AlertEntry entry;
  const _AlertRow({required this.entry});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final timeStr =
        '${entry.time.hour.toString().padLeft(2, '0')}:${entry.time.minute.toString().padLeft(2, '0')}:${entry.time.second.toString().padLeft(2, '0')}';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(children: [
        Icon(Icons.circle, color: entry.color, size: 8),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(entry.title,
              style: TextStyle(color: entry.color, fontWeight: FontWeight.w600, fontSize: 12)),
          Text(entry.detail, style: TextStyle(color: c.textSec, fontSize: 11)),
        ])),
        Text(timeStr, style: TextStyle(color: c.textSec, fontSize: 11)),
      ]),
    );
  }
}

// ── Fan speed preset button ───────────────────────────────────────────────────
class _PresetBtn extends StatelessWidget {
  final String label;
  final double value;
  final double current;
  final ValueChanged<double> onTap;

  const _PresetBtn({
    required this.label,
    required this.value,
    required this.current,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final bool active = (current - value).abs() < 0.5;
    return Expanded(
      child: GestureDetector(
        onTap: () => onTap(value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: active
                ? kTeal.withValues(alpha: 0.18)
                : Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: active
                  ? kTeal
                  : Colors.white.withValues(alpha: 0.08),
              width: 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                    color: active ? kTeal : c.textSec,
                    fontWeight:
                        active ? FontWeight.bold : FontWeight.normal,
                    fontSize: 12),
                textAlign: TextAlign.center,
              ),
              Text(
                '${value.round()} %',
                style: TextStyle(
                    color: active ? kTeal : c.textSec, fontSize: 10),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
