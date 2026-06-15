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
import '../services/firestore_log_service.dart';
import '../services/alert_notification_service.dart';
import '../services/user_log_service.dart';
import '../main.dart'
    show
        kTeal,
        kOrange,
        alertLogNotifier,
        selectedUnitNotifier,
        roleNotifier,
        browserNotifNotifier;
import '../l10n/app_strings.dart';
import '../utils/energy_format.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  AppColors get _c => AppColors.of(context);
  StreamSubscription? _sub;
  Timer? _noDataTimer; // fallback: show no-data if Firebase never responds
  Timer? _clockTimer; // ticks every second for live clock
  DateTime _now = DateTime.now();
  EnergyData? _current;
  EnergyData? _cachedFallback; // shown when Firebase is unreachable
  final List<EnergyData> _history = [];
  bool _alertsEnabled = true;
  int _activeAlertsCount = 0;
  // Cached alert thresholds — kept in sync with SharedPreferences by
  // _loadSettings() and updated on each _updateAlerts() call.
  double _pfThreshold = 0.8;
  double _vHighThreshold = 250.0;
  double _vLowThreshold = 200.0;
  double _iMaxThreshold = 50.0;
  double _tariffRate = 1.15;
  String _currentPrefUnit = 'A'; // 'mA' | 'A'
  String _voltagePrefUnit = 'V'; // 'mV' | 'V'
  String _powerPrefUnit = 'W'; // 'mW' | 'W' | 'kW'
  String _energyPrefUnit = 'kWh'; // 'mWh' | 'Wh' | 'kWh'
  String _selectedUnit = 'KOFERT_Unit_1';
  bool _noData = false; // true when Firebase path exists but has no readings
  bool _autoRefresh = true;
  int _refreshInterval =
      1; // seconds — throttle UI updates (1 s for live history)
  DateTime _lastUiUpdate = DateTime(2000);
  double? _monthEnergyHistoryMWh;
  double? _monthEnergyLastMeterMWh;
  int _monthEnergyHistoryCount = 0;
  int? _monthEnergyKey;
  String? _monthEnergyUnit;
  bool _monthEnergyLoading = false;
  double? _dayEnergyHistoryMWh;
  double? _dayEnergyLastMeterMWh;
  int _dayEnergyHistoryCount = 0;
  int? _dayEnergyKey;
  String? _dayEnergyUnit;
  bool _dayEnergyLoading = false;
  final Map<String, DateTime> _lastPeriodSummaryPublish = {};

  double _fanSpeedPercent = 0.0;
  Timer? _fanControlDebounce;
  StreamSubscription? _fanControlSub;

  String _pumpStatus = 'OFF'; // 'ON' or 'OFF'
  StreamSubscription? _pumpControlSub;
  String _dashChartMetric =
      'power'; // 'power'|'voltage'|'current'|'energy'|'pf'

  static const _units = ['KOFERT_Unit_1', 'KOFERT_Unit_2', 'KOFERT_Unit_3'];

  static String _labelFor(String unit) {
    switch (unit) {
      case 'KOFERT_Unit_1':
        return AppStrings.t('device_lamp');
      case 'KOFERT_Unit_2':
        return AppStrings.t('device_fan_5v');
      case 'KOFERT_Unit_3':
        return AppStrings.t('device_pump_5v');
      default:
        return unit;
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
      if (!mounted) return;
      final previousDayKey = _dayKey(_now);
      final previousMonthKey = _monthKey(_now);
      final next = DateTime.now();
      setState(() => _now = next);
      if (_current != null &&
          (previousDayKey != _dayKey(next) ||
              previousMonthKey != _monthKey(next))) {
        _resetEnergySummaries();
        _ensureEnergySummaries(_current!);
      }
    });
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _alertsEnabled = prefs.getBool('alertsEnabled') ?? true;
      _pfThreshold = prefs.getDouble('powerFactorThreshold') ?? 0.8;
      _vHighThreshold = prefs.getDouble('voltageThresholdHigh') ?? 250.0;
      _vLowThreshold = prefs.getDouble('voltageThresholdLow') ?? 200.0;
      _iMaxThreshold = prefs.getDouble('currentThreshold') ?? 50.0;
      _tariffRate = prefs.getDouble('tariffRate') ?? 1.15;
      _selectedUnit = prefs.getString('selectedUnit') ?? 'KOFERT_Unit_1';
      _autoRefresh = prefs.getBool('autoRefresh') ?? true;
      _refreshInterval = prefs.getInt('refreshInterval') ?? 5;
      _currentPrefUnit = prefs.getString('unitCurrent') ?? 'A';
      _voltagePrefUnit = prefs.getString('unitVoltage') ?? 'V';
      _powerPrefUnit = prefs.getString('unitPower') ?? 'W';
      _energyPrefUnit = prefs.getString('unitEnergy') ?? 'kWh';
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
        final cached = await EnergyRepository.instance.getCachedReading(
          _selectedUnit,
        );
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
              setState(
                () =>
                    _fanSpeedPercent = (v as num).toDouble().clamp(0.0, 100.0),
              );
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
      _resetEnergySummaries();
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
        event.snapshot.value as Map<dynamic, dynamic>,
        _selectedUnit,
      );
      if (!mounted) return;
      _ensureEnergySummaries(e);
      setState(() {
        _noData = false;
        _current = e;
        _history.add(e);
        if (_history.length > 60) _history.removeAt(0);
        _updateAlerts(e);
      });
      _publishRealtimePeriodSummaries(e);
    } catch (_) {
      // Parsing failed — treat as no data so we don't spin forever
      if (mounted) setState(() => _noData = true);
    }
  }

  int _monthKey(DateTime date) => date.year * 100 + date.month;
  int _dayKey(DateTime date) => date.year * 10000 + date.month * 100 + date.day;

  void _resetEnergySummaries() {
    _monthEnergyHistoryMWh = null;
    _monthEnergyLastMeterMWh = null;
    _monthEnergyHistoryCount = 0;
    _monthEnergyKey = null;
    _monthEnergyUnit = null;
    _monthEnergyLoading = false;
    _dayEnergyHistoryMWh = null;
    _dayEnergyLastMeterMWh = null;
    _dayEnergyHistoryCount = 0;
    _dayEnergyKey = null;
    _dayEnergyUnit = null;
    _dayEnergyLoading = false;
  }

  void _ensureEnergySummaries(EnergyData data) {
    _ensureDayEnergySummary(data);
    _ensureMonthEnergySummary(data);
  }

  void _ensureMonthEnergySummary(EnergyData data) {
    final monthKey = _monthKey(_now);
    final sameTarget =
        _monthEnergyUnit == data.unitId && _monthEnergyKey == monthKey;
    if (sameTarget && !_monthEnergyLoading) {
      return;
    }
    if (sameTarget && _monthEnergyLoading) return;

    _monthEnergyLoading = true;
    _monthEnergyHistoryMWh = null;
    _monthEnergyLastMeterMWh = null;
    _monthEnergyHistoryCount = 0;
    _monthEnergyUnit = data.unitId;
    _monthEnergyKey = monthKey;

    final requestedUnit = data.unitId;
    final requestedMonth = DateTime(_now.year, _now.month);
    FirestoreLogService.instance
        .getMonthEnergy(requestedUnit, requestedMonth)
        .then((summary) {
          if (!mounted) return;
          if (_monthEnergyUnit != requestedUnit ||
              _monthEnergyKey != _monthKey(requestedMonth)) {
            return;
          }
          setState(() {
            _monthEnergyHistoryMWh = summary.totalEnergy;
            _monthEnergyLastMeterMWh = summary.lastEnergy;
            _monthEnergyHistoryCount = summary.count;
            _monthEnergyLoading = false;
          });
          final current = _current;
          if (current != null && current.unitId == requestedUnit) {
            _publishRealtimePeriodSummaries(current);
          }
        });
  }

  void _ensureDayEnergySummary(EnergyData data) {
    final dayKey = _dayKey(_now);
    final sameTarget = _dayEnergyUnit == data.unitId && _dayEnergyKey == dayKey;
    if (sameTarget && !_dayEnergyLoading) {
      return;
    }
    if (sameTarget && _dayEnergyLoading) return;

    _dayEnergyLoading = true;
    _dayEnergyHistoryMWh = null;
    _dayEnergyLastMeterMWh = null;
    _dayEnergyHistoryCount = 0;
    _dayEnergyUnit = data.unitId;
    _dayEnergyKey = dayKey;

    final requestedUnit = data.unitId;
    final requestedDay = DateTime(_now.year, _now.month, _now.day);

    FirestoreLogService.instance
        .getDailyEnergy(requestedUnit, requestedDay)
        .then((summary) {
          if (!mounted) return;
          if (_dayEnergyUnit != requestedUnit ||
              _dayEnergyKey != _dayKey(requestedDay)) {
            return;
          }
          setState(() {
            _dayEnergyHistoryMWh = summary.totalEnergy;
            _dayEnergyLastMeterMWh = summary.lastEnergy;
            _dayEnergyHistoryCount = summary.count;
            _dayEnergyLoading = false;
          });
          final current = _current;
          if (current != null && current.unitId == requestedUnit) {
            _publishRealtimePeriodSummaries(current);
          }
        });
  }

  double _displayMonthEnergyMWh(EnergyData data) {
    final monthKey = _monthKey(_now);
    final sameTarget =
        _monthEnergyUnit == data.unitId && _monthEnergyKey == monthKey;
    if (!sameTarget) return data.energy;

    final month = periodConsumptionWithLiveMwh(
      historyMwh: _monthEnergyHistoryMWh ?? 0.0,
      currentMeterMwh: data.energy,
      lastLoggedMeterMwh: _monthEnergyLastMeterMWh,
      historyReadings: _monthEnergyHistoryCount,
      preferLiveWhenSparse: data.isINA219,
    );
    return monthAtLeastDayMwh(month, _displayDayEnergyMWh(data));
  }

  double _displayDayEnergyMWh(EnergyData data) {
    final dayKey = _dayKey(_now);
    final sameTarget = _dayEnergyUnit == data.unitId && _dayEnergyKey == dayKey;
    if (!sameTarget) return data.isINA219 ? data.energy : 0.0;

    return periodConsumptionWithLiveMwh(
      historyMwh: _dayEnergyHistoryMWh ?? 0.0,
      currentMeterMwh: data.energy,
      lastLoggedMeterMwh: _dayEnergyLastMeterMWh,
      historyReadings: _dayEnergyHistoryCount,
      preferLiveWhenSparse: data.isINA219,
    );
  }

  String _dayKeyText(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  String _monthKeyText(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}';
  }

  bool _hasCurrentPeriodSummaries(EnergyData data) {
    return _dayEnergyUnit == data.unitId &&
        _dayEnergyKey == _dayKey(_now) &&
        !_dayEnergyLoading &&
        _monthEnergyUnit == data.unitId &&
        _monthEnergyKey == _monthKey(_now) &&
        !_monthEnergyLoading;
  }

  void _publishRealtimePeriodSummaries(EnergyData data) {
    if (!_hasCurrentPeriodSummaries(data)) return;
    final now = DateTime.now();
    final last = _lastPeriodSummaryPublish[data.unitId];
    if (last != null && now.difference(last).inSeconds < 20) return;
    _lastPeriodSummaryPublish[data.unitId] = now;

    final dayEnergy = _displayDayEnergyMWh(data);
    final monthEnergy = _displayMonthEnergyMWh(data);
    FirebaseDatabase.instance
        .ref('${data.unitId}/energy_periods/current')
        .set({
          'unit_id': data.unitId,
          'daily_energy_mwh': dayEnergy,
          'daily_energy_kwh': dayEnergy / 1000000.0,
          'daily_date': _dayKeyText(_now),
          'monthly_energy_mwh': monthEnergy,
          'monthly_energy_kwh': monthEnergy / 1000000.0,
          'month': _monthKeyText(_now),
          'updated_at': ServerValue.timestamp,
          'source': 'dashboard_firestore_rtdb',
        })
        .catchError((_) {});
  }

  void _updateAlerts(EnergyData data) {
    if (!_alertsEnabled) {
      if (_activeAlertsCount != 0) setState(() => _activeAlertsCount = 0);
      return;
    }
    SharedPreferences.getInstance().then((prefs) {
      // Refresh cached thresholds so banner/dialog stay in sync with settings.
      _vHighThreshold = prefs.getDouble('voltageThresholdHigh') ?? 250.0;
      _vLowThreshold = prefs.getDouble('voltageThresholdLow') ?? 200.0;
      _iMaxThreshold = prefs.getDouble('currentThreshold') ?? 50.0;
      _pfThreshold = prefs.getDouble('powerFactorThreshold') ?? 0.8;

      int count = 0;
      // Voltage alerts only apply to Unit 1 (AC 220V) — Unit 2/3 are 5V DC
      if (_selectedUnit == 'KOFERT_Unit_1') {
        if (data.voltage > _vHighThreshold || data.voltage < _vLowThreshold) {
          count++;
          _logAlert(
            data.voltage > _vHighThreshold ? 'Surtension' : 'Sous-tension',
            '${data.voltage.toStringAsFixed(1)} V',
            const Color(0xFFE74C3C),
          );
        }
      }
      if (data.current > _iMaxThreshold) {
        count++;
        _logAlert(
          'Surcharge courant',
          '${data.current.toStringAsFixed(2)} A',
          const Color(0xFFE74C3C),
        );
      }
      // Power factor & reactive power alerts only apply to Unit 1 (AC) — INA219 units are DC
      if (_selectedUnit == 'KOFERT_Unit_1') {
        if (data.powerFactor < _pfThreshold && data.powerFactor > 0) {
          count++;
          _logAlert(
            'Facteur de puissance bas',
            'FP = ${data.powerFactor.toStringAsFixed(3)}',
            kOrange,
          );
        }
        if (data.hasHighReactivePower) {
          count++;
          _logAlert(
            'Puissance réactive élevée',
            '${data.reactivePower.toStringAsFixed(0)} VAR',
            kOrange,
          );
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
      unitId: _selectedUnit,
    );
    // Update global notifier (creates a new list so listeners fire).
    alertLogNotifier.value = [...log, entry];
    // Persist to Firestore for cross-session history (GetAlertHistory).
    FirestoreLogService.instance.logAlert(
      unitId: _selectedUnit,
      title: title,
      detail: detail,
      colorValue: color.value,
    );
    // Broadcast email to all users (throttled — once per 5 min per type).
    AlertNotificationService.instance.sendAlertToAllUsers(
      title: title,
      detail: detail,
      unitId: _selectedUnit,
    );
  }

  void _setFanSpeed(double pct) {
    setState(() => _fanSpeedPercent = pct);
    _fanControlDebounce?.cancel();
    _fanControlDebounce = Timer(const Duration(milliseconds: 400), () {
      final pwmValue = (pct / 100.0 * 255).round();
      FirebaseDatabase.instance
          .ref('KOFERT_Unit_2/fan_control')
          .update({'speed_percent': pct.round(), 'pwm_value': pwmValue})
          .catchError((e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Erreur ventilateur: $e'),
                  backgroundColor: Colors.red,
                  duration: const Duration(seconds: 4),
                ),
              );
            }
          });
      UserLogService.instance.log(
        action: 'other',
        detail: 'Fan speed set to ${pct.round()}% (PWM $pwmValue)',
      );
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
          Text(
            '${AppStrings.t('connecting_to')} $_selectedUnit (${_labelFor(_selectedUnit)})…',
            style: TextStyle(color: _c.textSec),
          ),
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
            child: Row(
              children: [
                const Icon(Icons.wifi_off_rounded, color: kOrange, size: 16),
                const SizedBox(width: 8),
                Text(
                  'Hors ligne — données en cache du '
                  '${_cachedFallback!.timestamp.day.toString().padLeft(2, '0')}/'
                  '${_cachedFallback!.timestamp.month.toString().padLeft(2, '0')} '
                  '${_cachedFallback!.timestamp.hour.toString().padLeft(2, '0')}:'
                  '${_cachedFallback!.timestamp.minute.toString().padLeft(2, '0')}',
                  style: const TextStyle(color: kOrange, fontSize: 12),
                ),
              ],
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final m = constraints.maxWidth < 600;
                return SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    m ? 14 : 28,
                    m ? 16 : 28,
                    m ? 14 : 28,
                    32,
                  ),
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
              },
            ),
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
              color: _c.textPri,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
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
            label: Text(AppStrings.t('retry')),
            style: OutlinedButton.styleFrom(
              foregroundColor: kTeal,
              side: BorderSide(color: kTeal.withValues(alpha: 0.5)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    final d = _current!;
    final double displayVoltage = d.voltage;
    final double displayCurrent = d.current;
    final double displayDayEnergyMWh = _displayDayEnergyMWh(d);
    final double displayMonthEnergyMWh = monthAtLeastDayMwh(
      _displayMonthEnergyMWh(d),
      displayDayEnergyMWh,
    );
    final double displayPower = d.power;
    return LayoutBuilder(
      builder: (context, constraints) {
        final m = constraints.maxWidth < 600;
        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            m ? 14 : 28,
            m ? 16 : 28,
            m ? 14 : 28,
            32,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildPageHeader(m),
              const SizedBox(height: 20),
              if (_alertsEnabled && _activeAlertsCount > 0) ...[
                _buildAlertBanner(d),
                const SizedBox(height: 20),
              ],
              _buildStatRow1(
                d,
                m,
                displayVoltage: displayVoltage,
                displayCurrent: displayCurrent,
                displayPower: displayPower,
                displayDayEnergyMWh: displayDayEnergyMWh,
              ),
              const SizedBox(height: 14),
              _buildEnergySummaryRow(
                m,
                displayMonthEnergyMWh: displayMonthEnergyMWh,
              ),
              const SizedBox(height: 14),
              _buildStatRow2(
                d,
                m,
                displayVoltage: displayVoltage,
                displayCurrent: displayCurrent,
                displayPower: displayPower,
                displayMonthEnergyMWh: displayMonthEnergyMWh,
              ),
              ValueListenableBuilder<String>(
                valueListenable: roleNotifier,
                builder: (_, role, __) {
                  final canControl =
                      role == 'admin' ||
                      role == 'moderator' ||
                      role == 'operator';
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_selectedUnit == 'KOFERT_Unit_2') ...[
                        const SizedBox(height: 14),
                        _buildFanRow(d, m),
                        if (canControl) ...[
                          const SizedBox(height: 14),
                          _buildFanSpeedControl(),
                        ],
                      ],
                      if (_selectedUnit == 'KOFERT_Unit_3') ...[
                        const SizedBox(height: 14),
                        _buildPumpControl(d, editable: canControl, isMobile: m),
                      ],
                    ],
                  );
                },
              ),
              const SizedBox(height: 24),
              _buildPowerOverview(m),
              const SizedBox(height: 20),
              _buildBottomRow(d, m),
              ValueListenableBuilder<List<AlertEntry>>(
                valueListenable: alertLogNotifier,
                builder: (_, log, __) {
                  if (log.isEmpty) return const SizedBox.shrink();
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [const SizedBox(height: 24), _buildAlertLog(log)],
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Page header ────────────────────────────────────────────────────────────
  Widget _buildPageHeader(bool m) {
    if (m) {
      return Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: _c.card,
                borderRadius: BorderRadius.circular(12),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedUnit,
                  isExpanded: true,
                  dropdownColor: _c.card,
                  style: TextStyle(color: _c.textPri, fontSize: 13),
                  icon: Icon(Icons.expand_more, color: _c.textSec, size: 16),
                  items: _units
                      .map(
                        (u) => DropdownMenuItem(
                          value: u,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(_deviceIcon[u]!, color: kTeal, size: 14),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  _labelFor(u),
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: _c.textPri,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    if (v != null) _switchUnit(v);
                  },
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _showUnitPrefsDialog,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: _c.card,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.straighten_outlined,
                color: _c.textSec,
                size: 18,
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _showAlertDialog,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color:
                    (_activeAlertsCount > 0 ? const Color(0xFFE74C3C) : kTeal)
                        .withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: _activeAlertsCount > 0
                      ? const Color(0xFFE74C3C)
                      : kTeal,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _activeAlertsCount > 0
                        ? Icons.warning_rounded
                        : Icons.check_circle_outline_rounded,
                    size: 14,
                    color: _activeAlertsCount > 0
                        ? const Color(0xFFE74C3C)
                        : kTeal,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '$_activeAlertsCount',
                    style: TextStyle(
                      color: _activeAlertsCount > 0
                          ? const Color(0xFFE74C3C)
                          : kTeal,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          _buildConnectivityBadge(),
        ],
      );
    }
    // ── Desktop header ─────────────────────────────────────────────────────
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: _c.card,
            borderRadius: BorderRadius.circular(12),
          ),
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
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, color: kTeal, size: 16),
                      const SizedBox(width: 8),
                      Text(
                        '$u  —  $label',
                        style: TextStyle(color: _c.textPri),
                      ),
                    ],
                  ),
                );
              }).toList(),
              onChanged: (v) {
                if (v != null) _switchUnit(v);
              },
            ),
          ),
        ),
        const SizedBox(width: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: _c.card,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_deviceIcon[_selectedUnit]!, color: kTeal, size: 16),
              const SizedBox(width: 8),
              Text(
                _labelFor(_selectedUnit),
                style: TextStyle(
                  color: _c.textPri,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: _c.card,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.payments_outlined, color: kOrange, size: 16),
              const SizedBox(width: 6),
              Text(
                '${_tariffRate.toStringAsFixed(2)} MAD/kWh',
                style: const TextStyle(color: kOrange, fontSize: 13),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        // ── Unit preferences ────────────────────────────────────
        Tooltip(
          message: 'Préférences d\'unités',
          child: GestureDetector(
            onTap: _showUnitPrefsDialog,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: _c.card,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.straighten_outlined, color: _c.textSec, size: 16),
                  const SizedBox(width: 5),
                  Text(
                    '$_currentPrefUnit · $_voltagePrefUnit · $_powerPrefUnit · $_energyPrefUnit',
                    style: TextStyle(color: _c.textSec, fontSize: 11),
                  ),
                ],
              ),
            ),
          ),
        ),
        const Spacer(),
        // ── Live clock ──────────────────────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: _c.card,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
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
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                  Text(
                    '${_now.day.toString().padLeft(2, '0')}/${_now.month.toString().padLeft(2, '0')}/${_now.year}',
                    style: TextStyle(color: _c.textSec, fontSize: 10),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        GestureDetector(
          onTap: _showAlertDialog,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: (_activeAlertsCount > 0 ? const Color(0xFFE74C3C) : kTeal)
                  .withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: _activeAlertsCount > 0 ? const Color(0xFFE74C3C) : kTeal,
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
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
                Text(
                  '$_activeAlertsCount ${AppStrings.t('alerts_count')}',
                  style: TextStyle(
                    color: _activeAlertsCount > 0
                        ? const Color(0xFFE74C3C)
                        : kTeal,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
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
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: Colors.grey,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              AppStrings.t('sensor_offline'),
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ),
      );
    }
    final age = DateTime.now().difference(_current!.timestamp);
    if (age.inSeconds > 90) {
      final label = age.inMinutes >= 1
          ? '${age.inMinutes}m'
          : '${age.inSeconds}s';
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: kOrange.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: kOrange.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.sensors_off_rounded, color: kOrange, size: 13),
            const SizedBox(width: 5),
            Text(
              '${AppStrings.t('data_stale')} · $label',
              style: const TextStyle(color: kOrange, fontSize: 12),
            ),
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: kTeal.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: kTeal,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            AppStrings.t('online'),
            style: const TextStyle(color: kTeal, fontSize: 12),
          ),
        ],
      ),
    );
  }

  // ── Stat rows ──────────────────────────────────────────────────────────────
  // Unit-preference converters
  /// Returns the SfChart labelFormat string for the given dashboard metric.
  String _chartUnitLabel(String metric) {
    switch (metric) {
      case 'power':
        return '{value} $_powerPrefUnit';
      case 'voltage':
        return '{value} $_voltagePrefUnit';
      case 'current':
        return '{value} $_currentPrefUnit';
      case 'energy':
        return '{value} $_energyPrefUnit';
      case 'pf':
        return '{value}';
      default:
        return '{value}';
    }
  }

  (String val, String unit) _cvtCurrent(double a) {
    if (_currentPrefUnit == 'mA')
      return ('${(a * 1000).toStringAsFixed(1)}', 'mA');
    return (a.toStringAsFixed(3), 'A');
  }

  (String val, String unit) _cvtVoltage(double v) {
    if (_voltagePrefUnit == 'mV')
      return ('${(v * 1000).toStringAsFixed(0)}', 'mV');
    return (v.toStringAsFixed(1), 'V');
  }

  (String val, String unit) _cvtPower(double w) {
    if (_powerPrefUnit == 'mW')
      return ('${(w * 1000).toStringAsFixed(1)}', 'mW');
    if (_powerPrefUnit == 'kW')
      return ('${(w / 1000).toStringAsFixed(4)}', 'kW');
    return (w.toStringAsFixed(1), 'W');
  }

  (String val, String unit) _cvtEnergy(double mwh) {
    if (_energyPrefUnit == 'mWh') return ('${mwh.toStringAsFixed(0)}', 'mWh');
    if (_energyPrefUnit == 'Wh')
      return ('${(mwh / 1000).toStringAsFixed(2)}', 'Wh');
    final kwh = mwh / 1000000;
    if (kwh >= 1.0) return (kwh.toStringAsFixed(2), 'kWh');
    if (kwh >= 0.001) return (kwh.toStringAsFixed(4), 'kWh');
    return ('0.00', 'kWh'); // near-zero — still show kWh unit
  }

  Widget _buildStatRow1(
    EnergyData d,
    bool m, {
    double? displayVoltage,
    double? displayCurrent,
    double? displayPower,
    double? displayDayEnergyMWh,
  }) {
    final (pVal, pUnit) = _cvtPower((displayPower ?? d.power));
    final energyForDisplay = displayDayEnergyMWh ?? d.energy;
    final (eVal, eUnit) = _cvtEnergy(energyForDisplay); // mWh
    final (vVal, vUnit) = _cvtVoltage(displayVoltage ?? d.voltage);
    final (iVal, iUnit) = _cvtCurrent(displayCurrent ?? d.current);
    final c1 = _StatCard(
      icon: '⚡',
      iconBg: kOrange,
      value: pVal,
      unit: pUnit,
      label: AppStrings.t('active_power'),
    );
    final c2 = _StatCard(
      icon: '🔋',
      iconBg: kTeal,
      value: eVal,
      unit: eUnit,
      label: 'Consommation du jour',
    );
    final c3 = _StatCard(
      icon: '🔌',
      iconBg: const Color(0xFFFF6B8A),
      value: vVal,
      unit: vUnit,
      label: AppStrings.t('voltage'),
      alert: d.hasHighVoltage || d.hasLowVoltage,
    );
    final c4 = _StatCard(
      icon: '〰',
      iconBg: const Color(0xFF4FC3F7),
      value: iVal,
      unit: iUnit,
      label: AppStrings.t('current'),
      alert: d.hasHighCurrent,
    );
    if (m) {
      return Column(
        children: [
          Row(
            children: [
              Expanded(child: c1),
              const SizedBox(width: 10),
              Expanded(child: c2),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: c3),
              const SizedBox(width: 10),
              Expanded(child: c4),
            ],
          ),
        ],
      );
    }
    return Row(
      children: [
        Expanded(child: c1),
        const SizedBox(width: 14),
        Expanded(child: c2),
        const SizedBox(width: 14),
        Expanded(child: c3),
        const SizedBox(width: 14),
        Expanded(child: c4),
      ],
    );
  }

  Widget _buildEnergySummaryRow(
    bool m, {
    required double displayMonthEnergyMWh,
  }) {
    final (monthVal, monthUnit) = _cvtEnergy(displayMonthEnergyMWh);
    final monthly = _StatCard(
      icon: 'M',
      iconBg: const Color(0xFF2ECC71),
      value: monthVal,
      unit: monthUnit,
      label: 'Consommation du mois',
    );
    return Row(children: [Expanded(child: monthly)]);
  }

  Widget _buildStatRow2(
    EnergyData d,
    bool m, {
    double? displayVoltage,
    double? displayCurrent,
    double? displayPower,
    double? displayMonthEnergyMWh,
  }) {
    final energyForDisplay = displayMonthEnergyMWh ?? d.energy;
    final cost =
        (energyForDisplay / 1000000) *
        _tariffRate; // mWh ÷ 1M → kWh × MAD/kWh = MAD
    // INA219 units (Unit 2 fan 5 V DC, Unit 3 pump 5 V DC) — no AC metrics.
    if (d.isINA219) {
      final powerMw =
          (displayPower ?? d.power) *
          1000; // W → mW for display clarity at low wattage
      final i1 = _StatCard(
        icon: '🔬',
        iconBg: const Color(0xFF9B59B6),
        value: 'INA219',
        unit: 'DC',
        label: AppStrings.t('dc_sensor'),
      );
      final i2 = _StatCard(
        icon: '⚡',
        iconBg: const Color(0xFF1ABC9C),
        value: powerMw.toStringAsFixed(1),
        unit: 'mW',
        label: AppStrings.t('dc_power'),
      );
      final i3 = _StatCard(
        icon: '🌊',
        iconBg: const Color(0xFF3498DB),
        value: ((displayCurrent ?? d.current) * 1000).toStringAsFixed(1),
        unit: 'mA',
        label: AppStrings.t('dc_current'),
      );
      final i4 = _StatCard(
        icon: '💰',
        iconBg: kOrange,
        value: cost.toStringAsFixed(4),
        unit: 'MAD',
        label: AppStrings.t('estimated_cost'),
      );
      if (m) {
        return Column(
          children: [
            Row(
              children: [
                Expanded(child: i1),
                const SizedBox(width: 10),
                Expanded(child: i2),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: i3),
                const SizedBox(width: 10),
                Expanded(child: i4),
              ],
            ),
          ],
        );
      }
      return Row(
        children: [
          Expanded(child: i1),
          const SizedBox(width: 14),
          Expanded(child: i2),
          const SizedBox(width: 14),
          Expanded(child: i3),
          const SizedBox(width: 14),
          Expanded(child: i4),
        ],
      );
    }
    // AC unit (Unit 1) — full metrics
    final double vFor = displayVoltage ?? d.voltage;
    final double iFor = displayCurrent ?? d.current;
    final apparentFor = (vFor * iFor).toStringAsFixed(1);
    final a1 = _StatCard(
      icon: '📐',
      iconBg: const Color(0xFF9B59B6),
      value: apparentFor,
      unit: 'VA',
      label: AppStrings.t('apparent_power'),
    );
    final a2 = _StatCard(
      icon: '🌀',
      iconBg: const Color(0xFF1ABC9C),
      value: d.reactivePower.toStringAsFixed(1),
      unit: 'VAR',
      label: AppStrings.t('reactive_power'),
      alert: d.hasHighReactivePower,
    );
    final a3 = _StatCard(
      icon: '🎵',
      iconBg: const Color(0xFF3498DB),
      value: d.frequency.toStringAsFixed(2),
      unit: 'Hz',
      label: AppStrings.t('frequency'),
    );
    final a4 = _StatCard(
      icon: '💰',
      iconBg: kOrange,
      value: cost.toStringAsFixed(2),
      unit: 'MAD',
      label: AppStrings.t('estimated_cost'),
    );
    if (m) {
      return Column(
        children: [
          Row(
            children: [
              Expanded(child: a1),
              const SizedBox(width: 10),
              Expanded(child: a2),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: a3),
              const SizedBox(width: 10),
              Expanded(child: a4),
            ],
          ),
        ],
      );
    }
    return Row(
      children: [
        Expanded(child: a1),
        const SizedBox(width: 14),
        Expanded(child: a2),
        const SizedBox(width: 14),
        Expanded(child: a3),
        const SizedBox(width: 14),
        Expanded(child: a4),
      ],
    );
  }

  // ── Pump control + water level (only for KOFERT_Unit_3) ──────────────────
  void _setPumpStatus(String status) {
    final previous = _pumpStatus;
    setState(() => _pumpStatus = status);
    FirebaseDatabase.instance
        .ref('KOFERT_Unit_3/current_metrics/pump_status')
        .set(status)
        .catchError((e) {
          if (mounted) {
            setState(() => _pumpStatus = previous); // revert on failure
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Erreur pompe: $e'),
                backgroundColor: Colors.red,
                duration: const Duration(seconds: 4),
              ),
            );
          }
        });
    UserLogService.instance.log(action: 'other', detail: 'Pump turned $status');
  }

  Widget _buildPumpControl(
    EnergyData d, {
    bool editable = true,
    bool isMobile = false,
  }) {
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
        color: _c.card,
        borderRadius: BorderRadius.circular(16),
      ),
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
                  color: pumpColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.water_outlined, color: pumpColor, size: 22),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  AppStrings.t('pump_control'),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _c.textPri,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: pumpColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: pumpColor.withValues(alpha: 0.5)),
                ),
                child: Text(
                  isOn ? AppStrings.t('running') : AppStrings.t('stopped'),
                  style: TextStyle(
                    color: pumpColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: (isOn || !editable)
                      ? null
                      : () => _setPumpStatus('ON'),
                  child: Opacity(
                    opacity: editable ? 1.0 : 0.5,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: isOn
                            ? kTeal.withValues(alpha: 0.18)
                            : Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isOn
                              ? kTeal
                              : Colors.white.withValues(alpha: 0.1),
                        ),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            Icons.power_settings_new,
                            color: isOn ? kTeal : _c.textSec,
                            size: 28,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            AppStrings.t('running'),
                            style: TextStyle(
                              color: isOn ? kTeal : _c.textSec,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GestureDetector(
                  onTap: (!isOn || !editable)
                      ? null
                      : () => _setPumpStatus('OFF'),
                  child: Opacity(
                    opacity: editable ? 1.0 : 0.5,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: !isOn
                            ? const Color(0xFFE74C3C).withValues(alpha: 0.18)
                            : Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: !isOn
                              ? const Color(0xFFE74C3C)
                              : Colors.white.withValues(alpha: 0.1),
                        ),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            Icons.stop_circle_outlined,
                            color: !isOn ? const Color(0xFFE74C3C) : _c.textSec,
                            size: 28,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            AppStrings.t('stopped'),
                            style: TextStyle(
                              color: !isOn
                                  ? const Color(0xFFE74C3C)
                                  : _c.textSec,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    final waterCard = Container(
      decoration: BoxDecoration(
        color: _c.card,
        borderRadius: BorderRadius.circular(16),
      ),
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
                  color: waterColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.water_drop_outlined,
                  color: waterColor,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  AppStrings.t('tank_level'),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _c.textPri,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: waterColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: waterColor.withValues(alpha: 0.5)),
                ),
                child: Text(
                  '$water %',
                  style: TextStyle(
                    color: waterColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
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
                water < 20
                    ? AppStrings.t('water_critical')
                    : water < 50
                    ? AppStrings.t('water_low')
                    : water < 80
                    ? AppStrings.t('water_ok')
                    : AppStrings.t('water_high'),
                style: TextStyle(
                  color: waterColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
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
                border: Border.all(
                  color: const Color(0xFFE74C3C).withValues(alpha: 0.4),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    color: Color(0xFFE74C3C),
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    AppStrings.t('refill_tank'),
                    style: const TextStyle(
                      color: Color(0xFFE74C3C),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
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
      decoration: BoxDecoration(
        color: _c.card,
        borderRadius: BorderRadius.circular(16),
      ),
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
                child: const Icon(
                  Icons.air,
                  color: Color(0xFF5DADE2),
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                AppStrings.t('fan_speed_control'),
                style: TextStyle(
                  color: _c.textPri,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: speedColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: speedColor.withValues(alpha: 0.5)),
                ),
                child: Text(
                  '${pct.round()} %',
                  style: TextStyle(
                    color: speedColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
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
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
              overlayColor: speedColor.withValues(alpha: 0.2),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 20),
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
              _PresetBtn(
                label: AppStrings.t('fan_off'),
                value: 0,
                current: pct,
                onTap: _setFanSpeed,
              ),
              const SizedBox(width: 8),
              _PresetBtn(
                label: AppStrings.t('fan_low'),
                value: 25,
                current: pct,
                onTap: _setFanSpeed,
              ),
              const SizedBox(width: 8),
              _PresetBtn(
                label: AppStrings.t('fan_medium'),
                value: 50,
                current: pct,
                onTap: _setFanSpeed,
              ),
              const SizedBox(width: 8),
              _PresetBtn(
                label: AppStrings.t('fan_fast'),
                value: 75,
                current: pct,
                onTap: _setFanSpeed,
              ),
              const SizedBox(width: 8),
              _PresetBtn(
                label: AppStrings.t('fan_max'),
                value: 100,
                current: pct,
                onTap: _setFanSpeed,
              ),
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
    return Row(
      children: [
        Expanded(flex: 1, child: card),
        const SizedBox(width: 14),
        // Spacer cards to keep the row visually balanced (3 empty spaces)
        const Expanded(flex: 1, child: SizedBox()),
        const SizedBox(width: 14),
        const Expanded(flex: 1, child: SizedBox()),
        const SizedBox(width: 14),
        const Expanded(flex: 1, child: SizedBox()),
      ],
    );
  }

  // ── Alert banner ───────────────────────────────────────────────────────────
  Widget _buildAlertBanner(EnergyData d) {
    // Use cached configurable thresholds (same as badge counter and dialog).
    final isUnit1 = _selectedUnit == 'KOFERT_Unit_1';
    final parts = <String>[];
    if (isUnit1 && d.voltage > _vHighThreshold)
      parts.add('Surtension (${d.voltage.toStringAsFixed(0)} V)');
    if (isUnit1 && d.voltage < _vLowThreshold)
      parts.add('Sous-tension (${d.voltage.toStringAsFixed(0)} V)');
    if (d.current > _iMaxThreshold)
      parts.add('Surcharge (${d.current.toStringAsFixed(1)} A)');
    if (isUnit1 && d.powerFactor < _pfThreshold && d.powerFactor > 0)
      parts.add('FP bas (${d.powerFactor.toStringAsFixed(2)})');
    if (isUnit1 && d.hasHighReactivePower)
      parts.add('Q élevée (${d.reactivePower.toStringAsFixed(0)} VAR)');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFE74C3C).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFE74C3C).withValues(alpha: 0.4),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            color: Color(0xFFE74C3C),
            size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              parts.join('  •  '),
              style: const TextStyle(color: Color(0xFFE74C3C), fontSize: 13),
            ),
          ),
          TextButton(
            onPressed: _showAlertDialog,
            child: Text(
              AppStrings.t('details'),
              style: const TextStyle(color: Color(0xFFE74C3C)),
            ),
          ),
        ],
      ),
    );
  }

  // ── Power overview chart ──────────────────────────────────────────────────
  Widget _buildPowerOverview([bool m = false]) {
    // Build chart points for the selected metric
    List<_ChartPoint> _buildPoints(String metric) {
      return _history.asMap().entries.map((e) {
        final v = e.value;
        double y;
        switch (metric) {
          case 'voltage':
            y = _voltagePrefUnit == 'mV' ? v.voltage * 1000 : v.voltage;
            break;
          case 'current':
            y = _currentPrefUnit == 'mA' ? v.current * 1000 : v.current;
            break;
          case 'energy':
            y = mwhToUnit(_displayMonthEnergyMWh(v), _energyPrefUnit);
            break;
          case 'pf':
            y = v.powerFactor;
            break;
          case 'apparent':
            y = v.apparentPower;
            break;
          default: // power
            if (_powerPrefUnit == 'mW')
              y = v.power * 1000;
            else if (_powerPrefUnit == 'kW')
              y = v.power / 1000;
            else
              y = v.power;
        }
        return _ChartPoint(e.key.toDouble(), y);
      }).toList();
    }

    // Metric chip definitions: (key, label, color)
    const chips = [
      ('power', 'metric_power', kTeal),
      ('voltage', 'metric_voltage', kOrange),
      ('current', 'metric_current', Color(0xFFFF6B8A)),
      ('energy', 'metric_energy', Color(0xFF4FC3F7)),
      ('pf', 'metric_pf', Color(0xFF9B59B6)),
    ];

    final chipsRow = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: chips.map((chip) {
          final sel = _dashChartMetric == chip.$1;
          final color = chip.$3;
          return Padding(
            padding: const EdgeInsets.only(right: 6),
            child: GestureDetector(
              onTap: () => setState(() => _dashChartMetric = chip.$1),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: sel ? color.withValues(alpha: 0.2) : _c.bg,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: sel ? color : _c.divider),
                ),
                child: Text(
                  AppStrings.t(chip.$2),
                  style: TextStyle(
                    color: sel ? color : _c.textSec,
                    fontSize: 12,
                    fontWeight: sel ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );

    // Chart color / label based on selection
    Color chartColor = kTeal;
    String chartName = AppStrings.t('metric_power');
    switch (_dashChartMetric) {
      case 'voltage':
        chartColor = kOrange;
        chartName = AppStrings.t('metric_voltage');
        break;
      case 'current':
        chartColor = const Color(0xFFFF6B8A);
        chartName = AppStrings.t('metric_current');
        break;
      case 'energy':
        chartColor = const Color(0xFF4FC3F7);
        chartName = AppStrings.t('metric_energy');
        break;
      case 'pf':
        chartColor = const Color(0xFF9B59B6);
        chartName = AppStrings.t('metric_pf');
        break;
    }

    final points = _buildPoints(_dashChartMetric);
    final showApparent = _dashChartMetric == 'power';
    final appPoints = showApparent ? _buildPoints('apparent') : null;

    return Container(
      decoration: BoxDecoration(
        color: _c.card,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.fromLTRB(20, 20, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppStrings.t('power_overview'),
            style: TextStyle(
              color: _c.textPri,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 10),
          chipsRow,
          const SizedBox(height: 16),
          SizedBox(
            height: 240,
            child: points.length < 2
                ? Center(
                    child: Text(
                      AppStrings.t('waiting_data'),
                      style: TextStyle(color: _c.textSec),
                    ),
                  )
                : SfCartesianChart(
                    backgroundColor: _c.card,
                    plotAreaBorderWidth: 0,
                    margin: EdgeInsets.zero,
                    primaryXAxis: const NumericAxis(
                      isVisible: false,
                      borderColor: Colors.transparent,
                    ),
                    primaryYAxis: NumericAxis(
                      labelStyle: TextStyle(color: _c.textSec, fontSize: 11),
                      axisLine: const AxisLine(color: Colors.transparent),
                      majorGridLines: MajorGridLines(
                        color: Colors.white.withValues(alpha: 0.06),
                        width: 1,
                      ),
                      majorTickLines: const MajorTickLines(size: 0),
                      labelFormat: _chartUnitLabel(_dashChartMetric),
                    ),
                    tooltipBehavior: TooltipBehavior(enable: true),
                    legend: showApparent
                        ? const Legend(
                            isVisible: true,
                            position: LegendPosition.top,
                          )
                        : const Legend(isVisible: false),
                    series: <CartesianSeries>[
                      SplineAreaSeries<_ChartPoint, double>(
                        dataSource: points,
                        xValueMapper: (p, _) => p.x,
                        yValueMapper: (p, _) => p.y,
                        name: chartName,
                        color: chartColor.withValues(alpha: 0.25),
                        borderColor: chartColor,
                        borderWidth: 2.5,
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            chartColor.withValues(alpha: 0.4),
                            chartColor.withValues(alpha: 0.0),
                          ],
                        ),
                      ),
                      if (appPoints != null)
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
    final last7 = _history.length >= 7
        ? _history.sublist(_history.length - 7)
        : _history;
    final labels = List.generate(last7.length, (i) => '${i + 1}');

    final pfChild = _buildPFGauge(d.powerFactor);
    final tChild = _MiniBarChart(
      title: 'Tension ($_voltagePrefUnit)',
      color: kOrange,
      data: last7
          .asMap()
          .entries
          .map(
            (e) => _BarItem(
              labels[e.key],
              _voltagePrefUnit == 'mV'
                  ? e.value.voltage * 1000
                  : e.value.voltage,
            ),
          )
          .toList(),
    );
    final curChild = _MiniBarChart(
      title: 'Courant ($_currentPrefUnit)',
      color: const Color(0xFFFF6B8A),
      data: last7
          .asMap()
          .entries
          .map(
            (e) => _BarItem(
              labels[e.key],
              _currentPrefUnit == 'mA'
                  ? e.value.current * 1000
                  : e.value.current,
            ),
          )
          .toList(),
    );
    final rChild = _MiniBarChart(
      title: 'Réactive (VAR)',
      color: const Color(0xFF9B59B6),
      data: last7
          .asMap()
          .entries
          .map((e) => _BarItem(labels[e.key], e.value.reactivePower))
          .toList(),
    );

    if (m) {
      // On mobile, use intrinsic-height children directly — Expanded in an
      // unbounded Column (inside SingleChildScrollView) collapses to zero height.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          pfChild,
          const SizedBox(height: 10),
          tChild,
          const SizedBox(height: 10),
          curChild,
          const SizedBox(height: 10),
          rChild,
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 2, child: pfChild),
        const SizedBox(width: 14),
        Expanded(child: tChild),
        const SizedBox(width: 14),
        Expanded(child: curChild),
        const SizedBox(width: 14),
        Expanded(child: rChild),
      ],
    );
  }

  // ── Radial PF gauge ────────────────────────────────────────────────────────
  Widget _buildPFGauge(double pf) {
    final pfColor = pf >= 0.95
        ? kTeal
        : pf >= 0.8
        ? kOrange
        : const Color(0xFFE74C3C);
    return Container(
      decoration: BoxDecoration(
        color: _c.card,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Text(
            AppStrings.t('power_factor'),
            style: TextStyle(
              color: _c.textPri,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 190,
            child: sfg.SfRadialGauge(
              backgroundColor: _c.card,
              axes: [
                sfg.RadialAxis(
                  minimum: 0,
                  maximum: 1,
                  startAngle: 150,
                  endAngle: 30,
                  radiusFactor: 0.9,
                  axisLineStyle: const sfg.AxisLineStyle(
                    thickness: 12,
                    color: Color(0xFF2E2E40),
                  ),
                  majorTickStyle: sfg.MajorTickStyle(
                    length: 8,
                    color: _c.textSec,
                  ),
                  minorTickStyle: sfg.MinorTickStyle(
                    length: 4,
                    color: _c.textSec,
                  ),
                  axisLabelStyle: sfg.GaugeTextStyle(
                    color: _c.textSec,
                    fontSize: 10,
                  ),
                  ranges: [
                    sfg.GaugeRange(
                      startValue: 0,
                      endValue: 0.7,
                      color: const Color(0xFFE74C3C).withValues(alpha: 0.4),
                    ),
                    sfg.GaugeRange(
                      startValue: 0.7,
                      endValue: 0.9,
                      color: kOrange.withValues(alpha: 0.4),
                    ),
                    sfg.GaugeRange(
                      startValue: 0.9,
                      endValue: 1.0,
                      color: kTeal.withValues(alpha: 0.4),
                    ),
                  ],
                  pointers: [
                    sfg.NeedlePointer(
                      value: pf.clamp(0.0, 1.0),
                      enableAnimation: true,
                      animationType: sfg.AnimationType.ease,
                      needleStartWidth: 1,
                      needleEndWidth: 5,
                      needleLength: 0.7,
                      needleColor: pfColor,
                      knobStyle: sfg.KnobStyle(
                        knobRadius: 0.06,
                        color: pfColor,
                      ),
                    ),
                  ],
                  annotations: [
                    sfg.GaugeAnnotation(
                      widget: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            pf.toStringAsFixed(3),
                            style: TextStyle(
                              color: pfColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 20,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            pf >= 0.95
                                ? 'Excellent'
                                : pf >= 0.8
                                ? 'Correct'
                                : 'Mauvais',
                            style: TextStyle(color: pfColor, fontSize: 11),
                          ),
                        ],
                      ),
                      angle: 90,
                      positionFactor: 0.5,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Alert log ──────────────────────────────────────────────────────────────
  Widget _buildAlertLog(List<AlertEntry> log) {
    return Container(
      decoration: BoxDecoration(
        color: _c.card,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            child: Row(
              children: [
                Icon(Icons.history, color: _c.textSec, size: 18),
                const SizedBox(width: 8),
                Text(
                  AppStrings.t('alert_history'),
                  style: TextStyle(
                    color: _c.textPri,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => setState(() => alertLogNotifier.value = []),
                  child: Text(
                    AppStrings.t('clear'),
                    style: TextStyle(color: _c.textSec, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          const Divider(color: Colors.white12, height: 1),
          ...log.reversed.take(10).map((a) => _AlertRow(entry: a)),
        ],
      ),
    );
  }

  // ── Alert dialog ───────────────────────────────────────────────────────────
  void _showAlertDialog() async {
    final d = _current;
    if (d == null) return;
    // Use the same configurable thresholds as _updateAlerts() so badge and
    // popup are always in sync (EnergyData getters use hardcoded values).
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final vHigh = prefs.getDouble('voltageThresholdHigh') ?? 250.0;
    final vLow = prefs.getDouble('voltageThresholdLow') ?? 200.0;
    final iMax = prefs.getDouble('currentThreshold') ?? 50.0;
    final pfMin = prefs.getDouble('powerFactorThreshold') ?? 0.8;
    final isUnit1 = _selectedUnit == 'KOFERT_Unit_1';
    final alertHighV = isUnit1 && d.voltage > vHigh;
    final alertLowV = isUnit1 && d.voltage < vLow;
    final alertHighI = d.current > iMax;
    final alertLowPF = isUnit1 && d.powerFactor < pfMin && d.powerFactor > 0;
    final alertHighQ = isUnit1 && d.hasHighReactivePower;
    final hasAny =
        alertHighV || alertLowV || alertHighI || alertLowPF || alertHighQ;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _c.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Color(0xFFE74C3C)),
            const SizedBox(width: 10),
            Text(
              AppStrings.t('active_alerts'),
              style: TextStyle(color: _c.textPri),
            ),
          ],
        ),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (alertHighV)
                _alertDialogRow(
                  AppStrings.t('alert_high_voltage'),
                  '${d.voltage.toStringAsFixed(0)} V > ${vHigh.toStringAsFixed(0)} V',
                  const Color(0xFFE74C3C),
                ),
              if (alertLowV)
                _alertDialogRow(
                  AppStrings.t('alert_low_voltage'),
                  '${d.voltage.toStringAsFixed(0)} V < ${vLow.toStringAsFixed(0)} V',
                  const Color(0xFFE74C3C),
                ),
              if (alertHighI)
                _alertDialogRow(
                  AppStrings.t('alert_high_current'),
                  '${d.current.toStringAsFixed(2)} A > ${iMax.toStringAsFixed(0)} A',
                  const Color(0xFFE74C3C),
                ),
              if (alertLowPF)
                _alertDialogRow(
                  AppStrings.t('alert_low_pf'),
                  'FP = ${d.powerFactor.toStringAsFixed(3)} < ${pfMin.toStringAsFixed(2)}',
                  kOrange,
                ),
              if (alertHighQ)
                _alertDialogRow(
                  AppStrings.t('alert_high_reactive'),
                  '${d.reactivePower.toStringAsFixed(0)} VAR',
                  kOrange,
                ),
              if (!hasAny)
                Text(
                  AppStrings.t('no_active_alerts'),
                  style: TextStyle(color: _c.textSec),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              AppStrings.t('close'),
              style: const TextStyle(color: kTeal),
            ),
          ),
        ],
      ),
    );
  }

  Widget _alertDialogRow(String title, String detail, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(Icons.circle, color: color, size: 10),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                Text(detail, style: TextStyle(color: _c.textSec, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Unit preferences dialog ───────────────────────────────────────────────
  Future<void> _showUnitPrefsDialog() async {
    String cu = _currentPrefUnit;
    String vu = _voltagePrefUnit;
    String pu = _powerPrefUnit;
    String eu = _energyPrefUnit;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          backgroundColor: _c.card,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 24,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              const Icon(Icons.straighten_outlined, color: kTeal),
              const SizedBox(width: 8),
              Text(
                'Unités d\'affichage',
                style: TextStyle(
                  color: _c.textPri,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _unitPickerRow(
                  setDlg,
                  AppStrings.t('current'),
                  ['mA', 'A'],
                  cu,
                  (v) => cu = v,
                ),
                const SizedBox(height: 18),
                _unitPickerRow(
                  setDlg,
                  AppStrings.t('voltage'),
                  ['mV', 'V'],
                  vu,
                  (v) => vu = v,
                ),
                const SizedBox(height: 18),
                _unitPickerRow(
                  setDlg,
                  AppStrings.t('active_power'),
                  ['mW', 'W', 'kW'],
                  pu,
                  (v) => pu = v,
                ),
                const SizedBox(height: 18),
                _unitPickerRow(
                  setDlg,
                  AppStrings.t('energy_consumed'),
                  ['mWh', 'Wh', 'kWh'],
                  eu,
                  (v) => eu = v,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(
                AppStrings.t('close'),
                style: TextStyle(color: _c.textSec),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setString('unitCurrent', cu);
                await prefs.setString('unitVoltage', vu);
                await prefs.setString('unitPower', pu);
                await prefs.setString('unitEnergy', eu);
                if (mounted)
                  setState(() {
                    _currentPrefUnit = cu;
                    _voltagePrefUnit = vu;
                    _powerPrefUnit = pu;
                    _energyPrefUnit = eu;
                  });
                if (ctx.mounted) Navigator.pop(ctx);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: kTeal,
                foregroundColor: Colors.black87,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: Text(AppStrings.t('save')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _unitPickerRow(
    StateSetter setDlg,
    String label,
    List<String> options,
    String current,
    void Function(String) onChanged,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: _c.textSec,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: options.map((opt) {
            final sel = opt == current;
            return GestureDetector(
              onTap: () => setDlg(() => onChanged(opt)),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: sel
                      ? kTeal.withValues(alpha: 0.18)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: sel ? kTeal : _c.divider.withValues(alpha: 0.3),
                  ),
                ),
                child: Text(
                  opt,
                  style: TextStyle(
                    color: sel ? kTeal : _c.textSec,
                    fontSize: 13,
                    fontWeight: sel ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
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
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final compact = constraints.maxWidth < 160;
        return Container(
          decoration: BoxDecoration(
            color: c.card,
            borderRadius: BorderRadius.circular(16),
            border: alert
                ? Border.all(
                    color: const Color(0xFFE74C3C).withValues(alpha: 0.5),
                    width: 1,
                  )
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
                  child: Text(
                    icon,
                    style: TextStyle(fontSize: compact ? 18 : 22),
                  ),
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
              Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: c.textSec, fontSize: 12),
              ),
            ],
          ),
        );
      },
    );
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
              color: c.textSec,
              fontWeight: FontWeight.w500,
              fontSize: 12,
            ),
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
                    primaryYAxis: const NumericAxis(isVisible: false),
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
      child: Row(
        children: [
          Icon(Icons.circle, color: entry.color, size: 8),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.title,
                  style: TextStyle(
                    color: entry.color,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
                Text(
                  entry.detail,
                  style: TextStyle(color: c.textSec, fontSize: 11),
                ),
              ],
            ),
          ),
          Text(timeStr, style: TextStyle(color: c.textSec, fontSize: 11)),
        ],
      ),
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
              color: active ? kTeal : Colors.white.withValues(alpha: 0.08),
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
                  fontWeight: active ? FontWeight.bold : FontWeight.normal,
                  fontSize: 12,
                ),
                textAlign: TextAlign.center,
              ),
              Text(
                '${value.round()} %',
                style: TextStyle(
                  color: active ? kTeal : c.textSec,
                  fontSize: 10,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
