import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import 'package:flutter/services.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'package:intl/intl.dart';
import 'package:excel/excel.dart' as xl;
import 'package:shared_preferences/shared_preferences.dart';
// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http_client;
import '../models/energy_data.dart';
import '../services/energy_predictor.dart';
import '../services/energy_repository.dart';
import '../services/firestore_log_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import '../theme/app_theme.dart';
import '../main.dart' show kTeal, kOrange;
import '../l10n/app_strings.dart';
import '../utils/energy_format.dart';

class HistoricalScreen extends StatefulWidget {
  const HistoricalScreen({super.key});

  @override
  State<HistoricalScreen> createState() => _HistoricalScreenState();
}

class _HistoricalScreenState extends State<HistoricalScreen> {
  AppColors get _c => AppColors.of(context);

  // ── EmailJS configuration ────────────────────────────────────────────
  // Replace these with your actual EmailJS credentials.
  // Sign up at https://www.emailjs.com and create a service + template.
  static const _emailjsServiceId = 'service_1tovyp1';
  static const _emailjsTemplateId = 'template_9cy6uou';
  static const _emailjsPublicKey = 'mD7lZMFFUPuDZlNRf';
  static const _emailIntro =
      'Veuillez trouver ci-dessous les données et la Prévision Énergétique de votre installation.';

  bool _isSendingEmail = false;
  List<EnergyData> _historicalData = [];
  List<EnergyData> _filteredData = [];
  Map<String, List<EnergyData>> _allUnitsData = {};
  Map<String, List<EnergyData>> _allUnitsFiltered = {};
  bool _isLoading = true;
  DateTime _lastRefreshed = DateTime.now();
  String _selectedMetric = 'power';
  DateTime _startDate = DateTime(2020, 1, 1);
  DateTime _endDate = DateTime.now();
  bool _startDateLocked = false; // true when user explicitly picks a start date
  bool _endDateLocked = false; // true when user explicitly picks an end date
  PredictionResult? _predictions;
  double _tariffRate = 1.15;
  String _energyUnit = 'kWh';
  String _powerUnit = 'W';
  String _voltageUnit = 'V';
  String _currentUnit = 'A';
  String _selectedUnit = 'KOFERT_Unit_1';
  bool _filtersVisible = false; // collapsible date/unit filters panel

  /// True when the selected unit uses milli-scale (mW / mA) for power & current.
  bool get _useMiliUnits =>
      _selectedUnit == 'KOFERT_Unit_2' || _selectedUnit == 'KOFERT_Unit_3';

  // Real-time listener & 5-second auto-refresh timer
  StreamSubscription? _rtSubscription;
  Timer? _refreshTimer;
  final Set<String> _seenKeys = {};

  static const _allUnitsKey = 'ALL_UNITS';
  static const _allUnitsList = [
    'KOFERT_Unit_1',
    'KOFERT_Unit_2',
    'KOFERT_Unit_3',
  ];
  static const _units = [
    'ALL_UNITS',
    'KOFERT_Unit_1',
    'KOFERT_Unit_2',
    'KOFERT_Unit_3',
  ];
  static final Map<String, Color> _unitColors = {
    'KOFERT_Unit_1': kTeal,
    'KOFERT_Unit_2': AppTheme.secondaryOrange,
    'KOFERT_Unit_3': AppTheme.successGreen,
  };

  static String _labelFor(String unit) {
    switch (unit) {
      case 'ALL_UNITS':
        return AppStrings.t('all_units');
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
    'ALL_UNITS': Icons.grid_view,
    'KOFERT_Unit_1': Icons.lightbulb_outline,
    'KOFERT_Unit_2': Icons.air,
    'KOFERT_Unit_3': Icons.water_outlined,
  };

  @override
  void initState() {
    super.initState();
    _loadPrefsAndData();
  }

  void _startRealTimeListener() {
    if (_selectedUnit == _allUnitsKey) return; // timer handles all-units mode
    _rtSubscription?.cancel();
    _seenKeys.clear();
    // Pre-populate seenKeys so we only process NEW entries after initial load
    for (final d in _historicalData) {
      _seenKeys.add(d.timestamp.toIso8601String());
    }
    final ref = FirebaseDatabase.instance.ref('$_selectedUnit/historical_data');
    _rtSubscription = ref.onChildAdded.listen((event) {
      final snap = event.snapshot;
      if (snap.value == null) return;
      try {
        final data = EnergyData.fromJson(
          Map<String, dynamic>.from(snap.value as Map),
          _selectedUnit,
        );
        final key = data.timestamp.toIso8601String();
        if (_seenKeys.contains(key)) return; // already loaded
        _seenKeys.add(key);
        if (!mounted) return;
        setState(() {
          if (!_endDateLocked) _endDate = DateTime.now();
          _historicalData = [..._historicalData, data]
            ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
          _applyDateFilter();
        });
      } catch (_) {
        // Ignore malformed entries
      }
    });
  }

  Future<void> _loadPrefsAndData() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _selectedUnit = prefs.getString('selectedUnit') ?? 'KOFERT_Unit_1';
      _tariffRate = prefs.getDouble('tariffRate') ?? 1.15;
      _energyUnit = prefs.getString('unitEnergy') ?? 'kWh';
      _powerUnit = prefs.getString('unitPower') ?? 'W';
      _voltageUnit = prefs.getString('unitVoltage') ?? 'V';
      _currentUnit = prefs.getString('unitCurrent') ?? 'A';
    });
    await _loadHistoricalData();
    _startRealTimeListener();
    _startRefreshTimer();
  }

  Future<void> _switchUnit(String unit) async {
    _rtSubscription?.cancel();
    _refreshTimer?.cancel();
    // Only persist real unit IDs to prefs, not ALL_UNITS
    if (unit != _allUnitsKey) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('selectedUnit', unit);
    }
    setState(() {
      _selectedUnit = unit;
      _historicalData.clear();
      _filteredData.clear();
      _allUnitsData.clear();
      _allUnitsFiltered.clear();
      _predictions = null;
    });
    await _loadHistoricalData();
    _startRealTimeListener();
    _startRefreshTimer();
  }

  @override
  void dispose() {
    _rtSubscription?.cancel();
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _startRefreshTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) _refreshData();
    });
  }

  /// Fetch Firestore sensor_readings for [unitId] as primary history source.
  /// Falls back to Realtime DB if Firestore returns nothing.
  Future<List<EnergyData>> _fetchForUnit(String unitId) async {
    final from = _startDateLocked ? _startDate : null;
    final to = _endDateLocked ? _endDate : null;
    final raw = await FirestoreLogService.instance.getReadings(
      unitId,
      from: from,
      to: to,
      limit: 1000,
    );
    if (raw.isNotEmpty) {
      final list = raw.map((m) => _fromFirestoreReading(m, unitId)).toList()
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
      return list;
    }
    // Firestore empty — fall back to Realtime DB.
    return EnergyRepository.instance.getHistoricalData(unitId, limit: 2000);
  }

  Future<void> _refreshData() async {
    // Quiet refresh — no loading spinner
    if (!_endDateLocked) _endDate = DateTime.now();
    try {
      if (_selectedUnit == _allUnitsKey) {
        final results = await Future.wait(
          _allUnitsList.map((u) => _fetchForUnit(u)),
        );
        if (!mounted) return;
        final newAllData = <String, List<EnergyData>>{};
        for (int i = 0; i < _allUnitsList.length; i++) {
          newAllData[_allUnitsList[i]] = results[i];
        }
        setState(() {
          _allUnitsData = newAllData;
          _historicalData = [for (final l in newAllData.values) ...l]
            ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
          if (!_startDateLocked && _historicalData.isNotEmpty) {
            _startDate = _historicalData.first.timestamp;
          }
          _applyDateFilter();
          _lastRefreshed = DateTime.now();
        });
        _runPredictions();
      } else {
        final dataList = await _fetchForUnit(_selectedUnit);
        if (!mounted) return;
        setState(() {
          _historicalData = dataList;
          if (!_startDateLocked && _historicalData.isNotEmpty) {
            _startDate = _historicalData.first.timestamp;
          }
          _applyDateFilter();
          _lastRefreshed = DateTime.now();
        });
        _runPredictions();
      }
    } catch (_) {
      // Silent fail — existing data remains visible
    }
  }

  Future<void> _loadHistoricalData() async {
    if (!mounted) return;
    if (!_endDateLocked) _endDate = DateTime.now();
    setState(() => _isLoading = true);
    try {
      if (_selectedUnit == _allUnitsKey) {
        final results = await Future.wait(
          _allUnitsList.map((u) => _fetchForUnit(u)),
        );
        if (!mounted) return;
        final newAllData = <String, List<EnergyData>>{};
        for (int i = 0; i < _allUnitsList.length; i++) {
          newAllData[_allUnitsList[i]] = results[i];
        }
        setState(() {
          _allUnitsData = newAllData;
          _historicalData = [for (final l in newAllData.values) ...l]
            ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
          if (!_startDateLocked && _historicalData.isNotEmpty) {
            _startDate = _historicalData.first.timestamp;
          }
          _applyDateFilter();
          _isLoading = false;
          _lastRefreshed = DateTime.now();
        });
        _runPredictions();
      } else {
        final dataList = await _fetchForUnit(_selectedUnit);
        if (!mounted) return;
        setState(() {
          _historicalData = dataList;
          _allUnitsData = {};
          if (!_startDateLocked && _historicalData.isNotEmpty) {
            _startDate = _historicalData.first.timestamp;
          }
          _applyDateFilter();
          _isLoading = false;
          _lastRefreshed = DateTime.now();
        });
        _runPredictions();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erreur de chargement: $e')));
    }
  }

  /// Convert a Firestore `sensor_readings` doc map to an [EnergyData] object.
  /// Used when supplementing Realtime DB data with Firestore date-range results.
  EnergyData _fromFirestoreReading(Map<String, dynamic> m, String unitId) {
    double n(dynamic v, [double fallback = 0.0]) =>
        (v as num?)?.toDouble() ?? fallback;
    final ts =
        (m['timestamp'] as Timestamp?)?.toDate().toLocal() ?? DateTime.now();
    return EnergyData(
      unitId: unitId,
      timestamp: ts,
      voltage: n(m['voltage']),
      current: n(m['current']),
      powerFactor: n(m['powerFactor']),
      power: n(m['power']),
      energy: normalizeEnergyFieldMwh(
        n(m['energy']),
        unitId,
        unit: (m['energyUnit'] ?? m['energy_unit'])?.toString(),
      ),
      frequency: n(m['frequency'], 50.0),
      windSpeed: n(m['fanSpeed']),
      waterLevel: (m['waterLevel'] as num?)?.toInt() ?? 0,
    );
  }

  void _applyDateFilter() {
    if (_selectedUnit == _allUnitsKey) {
      _allUnitsFiltered = {};
      for (final entry in _allUnitsData.entries) {
        _allUnitsFiltered[entry.key] = entry.value
            .where(
              (d) =>
                  !d.timestamp.isBefore(_startDate) &&
                  !d.timestamp.isAfter(_endDate),
            )
            .toList();
      }
      _filteredData = [for (final l in _allUnitsFiltered.values) ...l]
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    } else {
      _filteredData = _historicalData
          .where(
            (data) =>
                !data.timestamp.isBefore(_startDate) &&
                !data.timestamp.isAfter(_endDate),
          )
          .toList();
    }
  }

  void _runPredictions() {
    final data = _filteredData.isNotEmpty ? _filteredData : _historicalData;
    if (data.isEmpty) {
      if (mounted) setState(() => _predictions = null);
      return;
    }
    final predictor = EnergyPredictor(
      tariffRate: _tariffRate,
      pfThreshold: 0.8,
    );
    final result = predictor.predict(data);
    if (mounted) setState(() => _predictions = result);
  }

  void _showSendEmailDialog() {
    final currentUser = FirebaseAuth.instance.currentUser;
    final myEmail = currentUser?.email ?? '';
    bool sendToSelf = myEmail.isNotEmpty;
    final emailController = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            title: const Row(
              children: [
                Icon(Icons.email_outlined, color: kTeal),
                SizedBox(width: 10),
                Text('Envoyer par email'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_filteredData.length} enregistrements · '
                  '${DateFormat('dd/MM/yyyy').format(_startDate)} → '
                  '${DateFormat('dd/MM/yyyy').format(_endDate)}',
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
                const SizedBox(height: 16),
                if (myEmail.isNotEmpty) ...[
                  // Option 1: send to own email
                  InkWell(
                    onTap: () => setLocal(() => sendToSelf = true),
                    borderRadius: BorderRadius.circular(8),
                    child: Row(
                      children: [
                        Radio<bool>(
                          value: true,
                          groupValue: sendToSelf,
                          activeColor: kTeal,
                          onChanged: (v) => setLocal(() => sendToSelf = v!),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Mon email',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                myEmail,
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  // Option 2: another email
                  InkWell(
                    onTap: () => setLocal(() => sendToSelf = false),
                    borderRadius: BorderRadius.circular(8),
                    child: Row(
                      children: [
                        Radio<bool>(
                          value: false,
                          groupValue: sendToSelf,
                          activeColor: kTeal,
                          onChanged: (v) => setLocal(() => sendToSelf = v!),
                        ),
                        const Text(
                          'Autre adresse email',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!sendToSelf) ...[
                    const SizedBox(height: 10),
                    TextField(
                      controller: emailController,
                      keyboardType: TextInputType.emailAddress,
                      autofocus: true,
                      decoration: InputDecoration(
                        labelText: 'Adresse email du destinataire',
                        prefixIcon: const Icon(Icons.alternate_email, size: 18),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                      ),
                    ),
                  ],
                ] else ...[
                  TextField(
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      labelText: 'Adresse email du destinataire',
                      prefixIcon: const Icon(Icons.alternate_email, size: 18),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Annuler'),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: kTeal,
                  foregroundColor: Colors.black87,
                ),
                onPressed: _isSendingEmail
                    ? null
                    : () async {
                        final email = sendToSelf
                            ? myEmail
                            : emailController.text.trim();
                        if (email.isEmpty || !email.contains('@')) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Adresse email invalide'),
                            ),
                          );
                          return;
                        }
                        setLocal(() {});
                        Navigator.pop(ctx);
                        await _sendByEmail(email);
                      },
                icon: const Icon(Icons.send, size: 16),
                label: const Text('Envoyer'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _sendByEmail(String toEmail) async {
    if (_filteredData.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Aucune donnée à envoyer')));
      return;
    }

    setState(() => _isSendingEmail = true);

    // Auto-download the full Excel file alongside sending the email.
    _exportToExcel();

    try {
      final emailPUnit = _useMiliUnits ? 'mW' : 'W';
      final emailCUnit = _useMiliUnits ? 'mA' : 'A';
      final emailScaleP = _useMiliUnits ? 1000.0 : 1.0;
      final emailScaleC = _useMiliUnits ? 1000.0 : 1.0;

      final avgPower =
          _filteredData
              .map((e) => e.power * emailScaleP)
              .reduce((a, b) => a + b) /
          _filteredData.length;
      final avgPf =
          _filteredData.map((e) => e.powerFactor).reduce((a, b) => a + b) /
          _filteredData.length;
      // Energy is a cumulative counter (odometer). Correct total = sum of
      // (max − min) per unit, NOT the sum of all readings.
      final totalEnergy = () {
        final Map<String, List<EnergyData>> byUnit = {};
        for (final e in _filteredData) {
          byUnit.putIfAbsent(e.unitId, () => []).add(e);
        }
        double total = 0.0;
        for (final vals in byUnit.values) {
          vals.sort((a, b) => a.timestamp.compareTo(b.timestamp));
          total += periodConsumptionFromSeriesMwh(
            meterReadingsMwh: vals.map((p) => p.energy).toList(),
            timestamps: vals.map((p) => p.timestamp).toList(),
            powersW: vals.map((p) => p.power).toList(),
          );
        }
        return total;
      }();
      final avgVoltage =
          _filteredData.map((e) => e.voltage).reduce((a, b) => a + b) /
          _filteredData.length;
      final avgCurrent =
          _filteredData
              .map((e) => e.current * emailScaleC)
              .reduce((a, b) => a + b) /
          _filteredData.length;

      final fmt = DateFormat('dd/MM/yyyy');
      final timeFmt = DateFormat('dd/MM/yyyy HH:mm');
      final dtsFmt = DateFormat('dd/MM HH:mm');
      final unitLabel = '$_selectedUnit — ${_labelFor(_selectedUnit)}';
      final subject =
          'Rapport Énergétique — $_selectedUnit '
          '(${fmt.format(_startDate)} → ${fmt.format(_endDate)})';

      // ── Facture (cost breakdown) ──────────────────────────────────────────
      final periodHours = _endDate
          .difference(_startDate)
          .inHours
          .toDouble()
          .clamp(1.0, double.infinity);
      final periodDays = periodHours / 24.0;
      // totalEnergy in mWh; tariff in MAD/kWh; 1 kWh = 1 000 000 mWh
      final periodCost = totalEnergy * _tariffRate / 1000000.0;
      final dailyCost = periodCost / periodDays;

      // ── Predictions ───────────────────────────────────────────────────────
      final pred = _predictions;
      final wkEnergyMwh = (pred?.nextDayEnergyMwh ?? 0) * 7;
      final wkCostMad = (pred?.nextDayCost ?? 0) * 7;
      final moEnergyMwh = (pred?.nextDayEnergyMwh ?? 0) * 30;
      final moCostMad = (pred?.nextDayCost ?? 0) * 30;

      // ── Sample rows (first 10 + last 10 if > 20 rows) ─────────────────────
      final sample = <EnergyData>[];
      if (_filteredData.length <= 20) {
        sample.addAll(_filteredData);
      } else {
        sample.addAll(_filteredData.take(10));
        sample.addAll(_filteredData.skip(_filteredData.length - 10));
      }
      final isAllUnits = _selectedUnit == _allUnitsKey;
      final sampleHtml = sample
          .map((e) {
            // Per-row scaling: in all-units mode use the unit's own scale, else use emailScaleP/C
            final rowIsMili =
                e.unitId == 'KOFERT_Unit_2' || e.unitId == 'KOFERT_Unit_3';
            final rowScaleP = isAllUnits
                ? (rowIsMili ? 1000.0 : 1.0)
                : emailScaleP;
            final rowScaleC = isAllUnits
                ? (rowIsMili ? 1000.0 : 1.0)
                : emailScaleC;
            final rowPUnit = isAllUnits ? (rowIsMili ? 'mW' : 'W') : emailPUnit;
            final rowCUnit = isAllUnits ? (rowIsMili ? 'mA' : 'A') : emailCUnit;
            final pv = (e.power * rowScaleP).toStringAsFixed(2);
            final cv = (e.current * rowScaleC).toStringAsFixed(3);
            final unitCell = isAllUnits
                ? '<td style="padding:5px 9px;border:1px solid #e0e0e0;font-size:11px;color:#1a3a5c;font-weight:600">${_labelFor(e.unitId)}</td>'
                : '';
            return '<tr>'
                '$unitCell'
                '<td style="padding:5px 9px;border:1px solid #e0e0e0;font-size:11px">${dtsFmt.format(e.timestamp)}</td>'
                '<td style="padding:5px 9px;border:1px solid #e0e0e0;font-size:11px">$pv $rowPUnit</td>'
                '<td style="padding:5px 9px;border:1px solid #e0e0e0;font-size:11px">${e.voltage.toStringAsFixed(2)} V</td>'
                '<td style="padding:5px 9px;border:1px solid #e0e0e0;font-size:11px">$cv $rowCUnit</td>'
                '<td style="padding:5px 9px;border:1px solid #e0e0e0;font-size:11px">${fmtEnergy(e.energy)}</td>'
                '<td style="padding:5px 9px;border:1px solid #e0e0e0;font-size:11px">${e.powerFactor.toStringAsFixed(3)}</td>'
                '</tr>';
          })
          .join('\n');

      // ── Predictions HTML ──────────────────────────────────────────────────
      final predHtml = pred == null
          ? '<p style="color:#888;font-style:italic">Données insuffisantes pour les prévisions.</p>'
          : '''
<table style="width:100%;border-collapse:collapse;font-size:13px;margin-top:8px">
  <tr style="background:#1a3a5c">
    <td style="padding:8px 12px;border:1px solid #2a4a6c;color:#a8d1ff;font-weight:600;font-size:11px">HORIZON</td>
    <td style="padding:8px 12px;border:1px solid #2a4a6c;color:#a8d1ff;font-weight:600;font-size:11px">ÉNERGIE ESTIMÉE</td>
    <td style="padding:8px 12px;border:1px solid #2a4a6c;color:#a8d1ff;font-weight:600;font-size:11px">COÛT ESTIMÉ</td>
  </tr>
  <tr>
    <td style="padding:8px 12px;border:1px solid #e0e0e0">Prochain jour</td>
    <td style="padding:8px 12px;border:1px solid #e0e0e0;color:#1a73e8;font-weight:600">${fmtEnergyUnit(pred.nextDayEnergyMwh, _energyUnit)}</td>
    <td style="padding:8px 12px;border:1px solid #e0e0e0;color:#e67e22;font-weight:600">${pred.nextDayCost.toStringAsFixed(4)} MAD</td>
  </tr>
  <tr style="background:#f8f9fa">
    <td style="padding:8px 12px;border:1px solid #e0e0e0">Prochaine semaine (7 j)</td>
    <td style="padding:8px 12px;border:1px solid #e0e0e0;color:#1a73e8;font-weight:600">${fmtEnergyUnit(wkEnergyMwh, _energyUnit)}</td>
    <td style="padding:8px 12px;border:1px solid #e0e0e0;color:#e67e22;font-weight:600">${wkCostMad.toStringAsFixed(4)} MAD</td>
  </tr>
  <tr>
    <td style="padding:8px 12px;border:1px solid #e0e0e0">Prochain mois (30 j)</td>
    <td style="padding:8px 12px;border:1px solid #e0e0e0;color:#1a73e8;font-weight:600">${fmtEnergyUnit(moEnergyMwh, _energyUnit)}</td>
    <td style="padding:8px 12px;border:1px solid #e0e0e0;color:#e67e22;font-weight:600">${moCostMad.toStringAsFixed(4)} MAD</td>
  </tr>
  <tr style="background:#f8f9fa">
    <td style="padding:8px 12px;border:1px solid #e0e0e0">Fin du mois en cours</td>
    <td style="padding:8px 12px;border:1px solid #e0e0e0;color:#888">—</td>
    <td style="padding:8px 12px;border:1px solid #e0e0e0;color:#27ae60;font-weight:600">${pred.monthEndCost.toStringAsFixed(4)} MAD</td>
  </tr>
</table>
<p style="color:#888;font-size:11px;margin-top:6px">Modèle : compteur énergie + tendance temporelle — confiance ${(pred.costConfidence * 100).toStringAsFixed(0)}%</p>''';

      // ── Build the full HTML message ────────────────────────────────────────
      final invoicePredHtml = pred == null
          ? ''
          : '''
  <tr>
    <td style="padding:10px 14px;border:1px solid #e0e0e0;color:#888">Coût cumulé ce mois</td>
    <td style="padding:10px 14px;border:1px solid #e0e0e0;color:#e67e22">${pred.monthToDateCost.toStringAsFixed(4)} MAD</td>
  </tr>
  <tr style="background:#f8f9fa">
    <td style="padding:10px 14px;border:1px solid #e0e0e0;color:#888">Projection fin du mois</td>
    <td style="padding:10px 14px;border:1px solid #e0e0e0;font-weight:700;color:#e74c3c">${pred.monthEndCost.toStringAsFixed(4)} MAD</td>
  </tr>''';

      final sampleLabel = _filteredData.length > 20
          ? 'premières &amp; dernières 10 mesures sur ${_filteredData.length}'
          : '${_filteredData.length} mesures';

      final message =
          '''
<div style="font-family:Arial,Helvetica,sans-serif;max-width:660px">
  <!-- Header -->
  <table cellpadding="0" cellspacing="0" width="100%" style="background:#0D47A1;border-radius:8px 8px 0 0">
    <tr>
      <td style="padding:18px 20px;vertical-align:middle;width:44px">
        <span style="font-size:22px;line-height:1">&#128202;</span>
      </td>
      <td style="padding:18px 4px 18px 0;vertical-align:middle">
        <div style="color:#fff;font-size:17px;font-weight:700;letter-spacing:0.2px">Rapport Énergétique KOFERT</div>
        <div style="color:rgba(255,255,255,.75);font-size:11px;margin-top:3px">Système de surveillance énergétique · KOFERT JFC3</div>
      </td>
      <td align="right" style="padding:18px 20px 18px 0;vertical-align:middle">
        <div style="color:rgba(255,255,255,.5);font-size:10px;white-space:nowrap">&#9889; KOFERT JFC3</div>
      </td>
    </tr>
  </table>
  <!-- Body -->
  <div style="border:1px solid #c5d9f5;border-top:none;padding:20px 16px">
<h3 style="color:#1a3a5c;margin:0 0 12px">&#128202; Résumé de la période</h3>
<table style="width:100%;border-collapse:collapse;font-size:13px">
  <tr style="background:#f8f9fa">
    <td style="padding:10px 14px;border:1px solid #e0e0e0;color:#888;width:44%">Unité</td>
    <td style="padding:10px 14px;border:1px solid #e0e0e0;font-weight:600">$unitLabel</td>
  </tr>
  <tr>
    <td style="padding:10px 14px;border:1px solid #e0e0e0;color:#888">Période</td>
    <td style="padding:10px 14px;border:1px solid #e0e0e0">${fmt.format(_startDate)} → ${fmt.format(_endDate)} (${periodDays.toStringAsFixed(1)} jours)</td>
  </tr>
  <tr style="background:#f8f9fa">
    <td style="padding:10px 14px;border:1px solid #e0e0e0;color:#888">Nombre de mesures</td>
    <td style="padding:10px 14px;border:1px solid #e0e0e0">${_filteredData.length}</td>
  </tr>
  <tr>
    <td style="padding:10px 14px;border:1px solid #e0e0e0;color:#888">Tension moyenne</td>
    <td style="padding:10px 14px;border:1px solid #e0e0e0">${avgVoltage.toStringAsFixed(2)} V</td>
  </tr>
  <tr style="background:#f8f9fa">
    <td style="padding:10px 14px;border:1px solid #e0e0e0;color:#888">Courant moyen</td>
    <td style="padding:10px 14px;border:1px solid #e0e0e0">${avgCurrent.toStringAsFixed(3)} $emailCUnit</td>
  </tr>
  <tr>
    <td style="padding:10px 14px;border:1px solid #e0e0e0;color:#888">Puissance moyenne</td>
    <td style="padding:10px 14px;border:1px solid #e0e0e0;font-weight:600;color:#1a73e8">${avgPower.toStringAsFixed(2)} $emailPUnit</td>
  </tr>
  <tr style="background:#f8f9fa">
    <td style="padding:10px 14px;border:1px solid #e0e0e0;color:#888">Facteur de puissance moyen</td>
    <td style="padding:10px 14px;border:1px solid #e0e0e0">${avgPf.toStringAsFixed(3)}</td>
  </tr>
  <tr>
    <td style="padding:10px 14px;border:1px solid #e0e0e0;color:#888">Énergie totale</td>
    <td style="padding:10px 14px;border:1px solid #e0e0e0;font-weight:600;color:#27ae60">${fmtEnergy(totalEnergy)}</td>
  </tr>
</table>

<h3 style="color:#1a3a5c;margin:20px 0 12px">&#129534; Facture estimée</h3>
<table style="width:100%;border-collapse:collapse;font-size:13px">
  <tr style="background:#f8f9fa">
    <td style="padding:10px 14px;border:1px solid #e0e0e0;color:#888;width:44%">Énergie consommée (période)</td>
    <td style="padding:10px 14px;border:1px solid #e0e0e0">${fmtEnergy(totalEnergy)}</td>
  </tr>
  <tr>
    <td style="padding:10px 14px;border:1px solid #e0e0e0;color:#888">Tarif appliqué</td>
    <td style="padding:10px 14px;border:1px solid #e0e0e0">${_tariffRate.toStringAsFixed(2)} MAD / kWh</td>
  </tr>
  <tr style="background:#f8f9fa">
    <td style="padding:10px 14px;border:1px solid #e0e0e0;color:#888">Coût total période</td>
    <td style="padding:10px 14px;border:1px solid #e0e0e0;font-weight:700;color:#e67e22">${periodCost.toStringAsFixed(4)} MAD</td>
  </tr>
  <tr>
    <td style="padding:10px 14px;border:1px solid #e0e0e0;color:#888">Coût moyen / jour</td>
    <td style="padding:10px 14px;border:1px solid #e0e0e0">${dailyCost.toStringAsFixed(4)} MAD / j</td>
  </tr>
  $invoicePredHtml
</table>

<h3 style="color:#1a3a5c;margin:20px 0 12px">&#129302; Prévision Énergétique — Compteur + tendance</h3>
$predHtml

<h3 style="color:#1a3a5c;margin:20px 0 12px">&#128203; Échantillon des données ($sampleLabel)</h3>
<div style="overflow-x:auto">
<table style="width:100%;border-collapse:collapse;font-size:12px">
  <tr style="background:#1a3a5c">
    ${isAllUnits ? '<td style="padding:6px 9px;border:1px solid #2a4a6c;color:#a8d1ff;font-weight:600">Unité</td>' : ''}
    <td style="padding:6px 9px;border:1px solid #2a4a6c;color:#a8d1ff;font-weight:600">Horodatage</td>
    <td style="padding:6px 9px;border:1px solid #2a4a6c;color:#a8d1ff;font-weight:600">Puiss.</td>
    <td style="padding:6px 9px;border:1px solid #2a4a6c;color:#a8d1ff;font-weight:600">Tension (V)</td>
    <td style="padding:6px 9px;border:1px solid #2a4a6c;color:#a8d1ff;font-weight:600">Courant</td>
    <td style="padding:6px 9px;border:1px solid #2a4a6c;color:#a8d1ff;font-weight:600">Énergie ($_energyUnit)</td>
    <td style="padding:6px 9px;border:1px solid #2a4a6c;color:#a8d1ff;font-weight:600">FP</td>
  </tr>
  $sampleHtml
</table>
</div>

<div style="background:#e8f4e8;border-left:4px solid #27ae60;padding:12px 16px;margin-top:16px;border-radius:4px;font-size:12px">
  &#128229; Le fichier Excel complet (${_filteredData.length} mesures, tous les champs) a été automatiquement téléchargé dans votre navigateur au moment de l'envoi.
</div>
  </div><!-- /Body -->
  <!-- Footer -->
  <div style="background:#e8f0fe;border:1px solid #c5d9f5;border-top:none;border-radius:0 0 8px 8px;padding:12px 16px;font-size:11px;color:#444;text-align:center">
    Ce rapport a été généré automatiquement. Consultez le tableau de bord pour plus de détails.<br>
    <a href="https://ocp-energy-monitor.web.app" style="color:#0D47A1">ocp-energy-monitor.web.app</a>
  </div>
</div>''';

      final response = await http_client.post(
        Uri.parse('https://api.emailjs.com/api/v1.0/email/send'),
        headers: {
          'Content-Type': 'application/json',
          'origin': html.window.location.href,
        },
        body: jsonEncode({
          'service_id': _emailjsServiceId,
          'template_id': _emailjsTemplateId,
          'user_id': _emailjsPublicKey,
          'template_params': {
            'name': unitLabel,
            'time': timeFmt.format(DateTime.now()),
            'to_email': toEmail,
            'subject': subject,
            'intro': _emailIntro,
            'message': message,
          },
        }),
      );

      if (!mounted) return;
      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Email envoyé à $toEmail ✓  —  Excel téléchargé dans votre navigateur',
            ),
            backgroundColor: const Color(0xFF2ECC71),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Échec EmailJS (${response.statusCode}): ${response.body}',
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erreur envoi email: $e')));
    } finally {
      if (mounted) setState(() => _isSendingEmail = false);
    }
  }

  void _exportToExcel() {
    if (_filteredData.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Aucune donnée à exporter')));
      return;
    }
    try {
      final excel = xl.Excel.createExcel();
      final sheet = excel['KOFERT Energy'];
      excel.delete('Sheet1');

      // Header row
      final pUnit = _useMiliUnits ? 'mW' : 'W';
      final cUnit = _useMiliUnits ? 'mA' : 'A';
      final headers = [
        'Timestamp',
        'Puissance ($pUnit)',
        'Tension (V)',
        'Courant ($cUnit)',
        'Energie (mWh)',
        'Facteur de Puissance',
        'Fréquence (Hz)',
        'Puissance Apparente (VA)',
        'Puissance Réactive (VAR)',
      ];
      sheet.appendRow(headers.map((h) => xl.TextCellValue(h)).toList());

      // Style header
      for (int c = 0; c < headers.length; c++) {
        final cell = sheet.cell(
          xl.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0),
        );
        cell.cellStyle = xl.CellStyle(
          bold: true,
          backgroundColorHex: xl.ExcelColor.fromHexString('#1A2E4A'),
          fontColorHex: xl.ExcelColor.fromHexString('#FFFFFF'),
        );
      }

      // Data rows
      final scaleP = _useMiliUnits ? 1000.0 : 1.0;
      final scaleC = _useMiliUnits ? 1000.0 : 1.0;
      for (final d in _filteredData) {
        sheet.appendRow([
          xl.TextCellValue(
            DateFormat('yyyy-MM-dd HH:mm:ss').format(d.timestamp),
          ),
          xl.DoubleCellValue(d.power * scaleP),
          xl.DoubleCellValue(d.voltage),
          xl.DoubleCellValue(d.current * scaleC),
          xl.DoubleCellValue(d.energy),
          xl.DoubleCellValue(d.powerFactor),
          xl.DoubleCellValue(d.frequency),
          xl.DoubleCellValue(d.apparentPower),
          xl.DoubleCellValue(d.reactivePower),
        ]);
      }

      // Predictions sheet
      if (_predictions != null) {
        final pSheet = excel['Prévision Énergétique'];
        pSheet.appendRow([
          xl.TextCellValue('Indicateur'),
          xl.TextCellValue('Valeur'),
        ]);
        pSheet.appendRow([
          xl.TextCellValue('Coût prochain jour (MAD)'),
          xl.DoubleCellValue(_predictions!.nextDayCost),
        ]);
        pSheet.appendRow([
          xl.TextCellValue('Energie prochain jour (mWh)'),
          xl.DoubleCellValue(_predictions!.nextDayEnergyMwh),
        ]);
        pSheet.appendRow([
          xl.TextCellValue('Coût fin du mois (MAD)'),
          xl.DoubleCellValue(_predictions!.monthEndCost),
        ]);
        pSheet.appendRow([
          xl.TextCellValue('Coût cumulé ce mois (MAD)'),
          xl.DoubleCellValue(_predictions!.monthToDateCost),
        ]);
        pSheet.appendRow([
          xl.TextCellValue('FP prédit (10 min)'),
          xl.DoubleCellValue(_predictions!.predictedPf10min),
        ]);
        pSheet.appendRow([
          xl.TextCellValue('Tendance FP'),
          xl.TextCellValue(_predictions!.pfTrend),
        ]);
        pSheet.appendRow([
          xl.TextCellValue('Alerte FP'),
          xl.TextCellValue(_predictions!.pfWillDropBelow ? 'OUI' : 'NON'),
        ]);
      }

      final bytes = excel.save()!;
      final ts = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final blob = html.Blob([
        Uint8List.fromList(bytes),
      ], 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
      final url = html.Url.createObjectUrlFromBlob(blob);
      html.AnchorElement(href: url)
        ..setAttribute('download', 'KOFERT_Energy_$ts.xlsx')
        ..click();
      html.Url.revokeObjectUrl(url);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Fichier Excel téléchargé ✓'),
          backgroundColor: Color(0xFF2ECC71),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erreur export Excel: $e')));
    }
  }

  void _exportToCSV() {
    if (_filteredData.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Aucune donnée à exporter')));
      return;
    }

    final csvPUnit = _useMiliUnits ? 'mW' : 'W';
    final csvCUnit = _useMiliUnits ? 'mA' : 'A';
    final scaleP2 = _useMiliUnits ? 1000.0 : 1.0;
    final scaleC2 = _useMiliUnits ? 1000.0 : 1.0;
    final headers =
        'Timestamp,Power ($csvPUnit),Voltage (V),Current ($csvCUnit),Energy (mWh),Power Factor,Frequency (Hz)\n';
    final rows = _filteredData
        .map(
          (data) =>
              '${DateFormat('yyyy-MM-dd HH:mm:ss').format(data.timestamp)},'
              '${data.power * scaleP2},${data.voltage},${data.current * scaleC2},${data.energy},'
              '${data.powerFactor},${data.frequency}',
        )
        .join('\n');

    final csv = headers + rows;
    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final filename = 'KOFERT_Energy_$timestamp.csv';

    _showExportDialog(csv, filename);
  }

  void _exportToJSON() {
    if (_filteredData.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Aucune donnée à exporter')));
      return;
    }

    final data = _filteredData
        .map(
          (e) => {
            'timestamp': DateFormat('yyyy-MM-dd HH:mm:ss').format(e.timestamp),
            'power_w': e.power,
            'voltage_v': e.voltage,
            'current_a': e.current,
            'energy_mwh': e.energy,
            'power_factor': e.powerFactor,
            'frequency_hz': e.frequency,
          },
        )
        .toList();

    final json = jsonEncode({
      'unit': _selectedUnit,
      'date_range': {
        'start': DateFormat('yyyy-MM-dd').format(_startDate),
        'end': DateFormat('yyyy-MM-dd').format(_endDate),
      },
      'total_records': _filteredData.length,
      'data': data,
    });

    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final filename = 'KOFERT_Energy_$timestamp.json';

    _showExportDialog(json, filename);
  }

  void _showExportDialog(String content, String filename) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          title: Row(
            children: [
              Icon(Icons.download, color: AppTheme.primaryNavy),
              const SizedBox(width: 12),
              const Text('Données Exportées'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                decoration: BoxDecoration(
                  color: AppTheme.primaryNavy.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Fichier',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppTheme.darkGray,
                      ),
                    ),
                    const SizedBox(height: 6),
                    SelectableText(
                      filename,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AppTheme.primaryNavy,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Entrées',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                  Container(
                    decoration: BoxDecoration(
                      color: AppTheme.secondaryOrange.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    child: Text(
                      '${_filteredData.length}',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppTheme.secondaryOrange,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'Aperçu du contenu',
                style: Theme.of(
                  context,
                ).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey[300]!, width: 1),
                ),
                child: SizedBox(
                  height: 120,
                  width: double.maxFinite,
                  child: SingleChildScrollView(
                    child: SelectableText(
                      content.substring(
                        0,
                        (content.length > 500 ? 500 : content.length),
                      ),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontSize: 10,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Fermer'),
            ),
            ElevatedButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: content));
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('Copié dans le presse-papiers'),
                    backgroundColor: AppTheme.successGreen,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
              icon: const Icon(Icons.copy),
              label: const Text('Copier'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _c.bg,
      body: Column(
        children: [
          // ── Page header ────────────────────────────────────────────────
          LayoutBuilder(
            builder: (context, bc) {
              final isMobile = bc.maxWidth < 700;
              // Shared action buttons
              final actions = Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _isSendingEmail
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: kTeal,
                          ),
                        )
                      : IconButton(
                          icon: Icon(Icons.email_outlined, color: _c.textPri),
                          tooltip: 'Envoyer par email',
                          padding: const EdgeInsets.all(6),
                          constraints: const BoxConstraints(),
                          onPressed: _filteredData.isEmpty
                              ? null
                              : _showSendEmailDialog,
                        ),
                  PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'csv') _exportToCSV();
                      if (value == 'json') _exportToJSON();
                      if (value == 'excel') _exportToExcel();
                    },
                    itemBuilder: (BuildContext context) => [
                      PopupMenuItem(
                        value: 'excel',
                        child: Row(
                          children: [
                            Icon(Icons.table_view_rounded, color: kTeal),
                            const SizedBox(width: 10),
                            const Text('Exporter Excel (.xlsx)'),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'csv',
                        child: Row(
                          children: [
                            Icon(Icons.table_chart, color: kTeal),
                            const SizedBox(width: 10),
                            const Text('Exporter CSV'),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'json',
                        child: Row(
                          children: [
                            Icon(Icons.code, color: kTeal),
                            const SizedBox(width: 10),
                            const Text('Exporter JSON'),
                          ],
                        ),
                      ),
                    ],
                    icon: Icon(Icons.download, color: _c.textPri),
                  ),
                ],
              );
              // Shared unit dropdown
              final unitDropdown = DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedUnit,
                  dropdownColor: _c.card,
                  isExpanded: isMobile,
                  style: TextStyle(color: _c.textPri, fontSize: 13),
                  icon: Icon(Icons.expand_more, color: _c.textSec, size: 18),
                  items: _units
                      .map(
                        (u) => DropdownMenuItem(
                          value: u,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(_deviceIcon[u]!, color: kTeal, size: 15),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  isMobile
                                      ? _labelFor(u)
                                      : (u == 'ALL_UNITS'
                                            ? _labelFor(u)
                                            : '$u  —  ${_labelFor(u)}'),
                                  style: TextStyle(
                                    color: _c.textPri,
                                    fontSize: 13,
                                  ),
                                  overflow: TextOverflow.ellipsis,
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
              );

              return Container(
                color: _c.card,
                padding: EdgeInsets.fromLTRB(
                  16,
                  isMobile ? 12 : 20,
                  8,
                  isMobile ? 10 : 16,
                ),
                child: isMobile
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Row 1: title + action buttons
                          Row(
                            children: [
                              Text(
                                'Historique',
                                style: TextStyle(
                                  color: _c.textPri,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 17,
                                ),
                              ),
                              const Spacer(),
                              actions,
                            ],
                          ),
                          const SizedBox(height: 8),
                          // Row 2: full-width unit dropdown
                          Container(
                            decoration: BoxDecoration(
                              color: _c.bg,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.white12),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            child: unitDropdown,
                          ),
                        ],
                      )
                    : Row(
                        children: [
                          unitDropdown,
                          const SizedBox(width: 12),
                          Text(
                            'Données Historiques',
                            style: TextStyle(
                              color: _c.textPri,
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                          const Spacer(),
                          actions,
                        ],
                      ),
              );
            },
          ),
          // ── Auto-refresh status bar ──────────────────────────────────────────
          Container(
            color: _c.card,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: AppTheme.successGreen,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '${AppStrings.t('autorefresh_info')}  •  ${AppStrings.t('updated_at')}: ${DateFormat('HH:mm:ss').format(_lastRefreshed)}',
                  style: TextStyle(color: _c.textSec, fontSize: 11),
                ),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: kTeal))
                : _historicalData.isEmpty
                ? _buildEmptyState()
                : _buildContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              decoration: BoxDecoration(
                color: AppTheme.primaryNavy.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16),
              ),
              padding: const EdgeInsets.all(20),
              child: Icon(
                Icons.history,
                size: 64,
                color: AppTheme.primaryNavy.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Aucune Donnée Historique',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: AppTheme.primaryNavy,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Les données historiques apparaîtront ici',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: AppTheme.darkGray),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    return Column(
      children: [
        _buildFiltersToggle(),
        if (_filtersVisible) ...[
          _buildDateRangeFilter(),
          _buildMetricSelector(),
          _buildUnitSelector(),
        ],
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                if (_predictions != null) ...[
                  _buildAIPredictions(_predictions!),
                  const SizedBox(height: 24),
                ],
                _buildChart(),
                const SizedBox(height: 24),
                _buildStatistics(),
                const SizedBox(height: 24),
                _buildDataTable(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── Filters toggle bar (always visible) ────────────────────────────────────
  Widget _buildFiltersToggle() {
    return Container(
      decoration: BoxDecoration(
        color: _c.card,
        border: const Border(bottom: BorderSide(color: Colors.white12)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
      child: Row(
        children: [
          // Current metric pill
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: _getMetricColor().withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _getMetricColor().withValues(alpha: 0.4),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(_getMetricIcon(), color: _getMetricColor(), size: 13),
                const SizedBox(width: 5),
                Text(
                  _getMetricLabel(),
                  style: TextStyle(
                    color: _getMetricColor(),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${_filteredData.length} ${AppStrings.t('entries_shown')}',
            style: TextStyle(color: _c.textSec, fontSize: 11),
          ),
          const Spacer(),
          TextButton.icon(
            onPressed: () => setState(() => _filtersVisible = !_filtersVisible),
            icon: Icon(
              _filtersVisible ? Icons.expand_less : Icons.tune_rounded,
              size: 16,
            ),
            label: Text(
              _filtersVisible
                  ? AppStrings.t('filters_hide')
                  : AppStrings.t('filters_show'),
              style: const TextStyle(fontSize: 12),
            ),
            style: TextButton.styleFrom(
              foregroundColor: kTeal,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateRangeFilter() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        color: _c.card,
        border: Border(bottom: BorderSide(color: Colors.white12, width: 1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppStrings.t('date_range'),
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: AppTheme.darkGray,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildDateButton(
                  _startDate,
                  () => _selectStartDate(context),
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  AppStrings.t('date_to'),
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildDateButton(
                  _endDate,
                  () => _selectEndDate(context),
                ),
              ),
              const SizedBox(width: 8),
              Tooltip(
                message: AppStrings.t('reset_dates'),
                child: IconButton(
                  icon: const Icon(Icons.refresh),
                  color: AppTheme.primaryNavy,
                  onPressed: () {
                    setState(() {
                      _startDateLocked = false;
                      _endDateLocked = false;
                      _startDate = _historicalData.isNotEmpty
                          ? _historicalData.first.timestamp
                          : DateTime(2020, 1, 1);
                      _endDate = DateTime.now();
                      _applyDateFilter();
                    });
                    _runPredictions();
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDateButton(DateTime date, VoidCallback onPressed) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.calendar_today, size: 18),
      label: Text(
        DateFormat('dd/MM/yyyy').format(date),
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500),
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppTheme.primaryNavy,
        side: const BorderSide(color: AppTheme.primaryNavy, width: 1),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  Future<void> _selectStartDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime(2020),
      lastDate: _endDate,
    );
    if (picked != null && picked != _startDate) {
      setState(() {
        _startDateLocked = true;
        _startDate = picked;
        _applyDateFilter();
      });
      _runPredictions();
    }
  }

  Future<void> _selectEndDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate,
      firstDate: _startDate,
      lastDate: DateTime.now(),
    );
    if (picked != null && picked != _endDate) {
      setState(() {
        _endDateLocked = true;
        _endDate = picked;
        _applyDateFilter();
      });
      _runPredictions();
    }
  }

  Widget _buildMetricSelector() {
    const metrics = [
      ('power', 'metric_power', Icons.bolt_rounded),
      ('voltage', 'metric_voltage', Icons.flash_on),
      ('current', 'metric_current', Icons.electrical_services),
      ('energy', 'metric_energy', Icons.battery_charging_full),
      ('powerFactor', 'metric_pf', Icons.speed),
      ('frequency', 'metric_freq', Icons.waves),
    ];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: _c.bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppStrings.t('metric_label'),
            style: TextStyle(
              color: _c.textSec,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: metrics.map((m) {
                final sel = _selectedMetric == m.$1;
                final color = _getMetricColor();
                final activeColor = sel ? color : _c.textSec;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () => setState(() => _selectedMetric = m.$1),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: sel ? color.withValues(alpha: 0.15) : _c.card,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: sel ? color : _c.divider,
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(m.$3, color: activeColor, size: 13),
                          const SizedBox(width: 5),
                          Text(
                            AppStrings.t(m.$2),
                            style: TextStyle(
                              color: activeColor,
                              fontSize: 12,
                              fontWeight: sel
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  // ── AI Predictions panel ──────────────────────────────────────────────────
  Widget _buildAIPredictions(PredictionResult p) {
    const teal = kTeal;
    const orange = Color(0xFFE67E22);
    const red = Color(0xFFE74C3C);
    const green = Color(0xFF2ECC71);
    final cardColor = const Color(0xFF1A2538);

    Widget predCard({
      required IconData icon,
      required Color iconColor,
      required String title,
      required String value,
      String? subtitle,
      Color? valueColor,
    }) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: iconColor.withValues(alpha: 0.25),
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: iconColor, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      color: Color(0xFF8899AA),
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              value,
              style: TextStyle(
                color: valueColor ?? Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(color: Color(0xFF8899AA), fontSize: 11),
              ),
            ],
          ],
        ),
      );
    }

    final pfColor = p.pfWillDropBelow
        ? red
        : p.pfTrend == 'falling'
        ? orange
        : green;

    final pfIcon = p.pfWillDropBelow
        ? Icons.warning_amber_rounded
        : p.pfTrend == 'rising'
        ? Icons.trending_up_rounded
        : p.pfTrend == 'falling'
        ? Icons.trending_down_rounded
        : Icons.trending_flat_rounded;

    final confPct = (p.costConfidence * 100).round();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF111C2D),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: teal.withValues(alpha: 0.3), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title row
          LayoutBuilder(
            builder: (context, bc) {
              final narrow = bc.maxWidth < 380;
              final titleCol = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppStrings.t('ai_predictions'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  Text(
                    AppStrings.t('ai_model_subtitle'),
                    style: const TextStyle(
                      color: Color(0xFF8899AA),
                      fontSize: 11,
                    ),
                  ),
                ],
              );
              final confidenceChip = Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: teal.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${AppStrings.t('confidence')} $confPct%',
                  style: const TextStyle(color: kTeal, fontSize: 11),
                ),
              );
              final iconBox = Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: teal.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  color: kTeal,
                  size: 20,
                ),
              );
              if (narrow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        iconBox,
                        const SizedBox(width: 12),
                        Expanded(child: titleCol),
                      ],
                    ),
                    const SizedBox(height: 6),
                    confidenceChip,
                  ],
                );
              }
              return Row(
                children: [
                  iconBox,
                  const SizedBox(width: 12),
                  Expanded(child: titleCol),
                  confidenceChip,
                ],
              );
            },
          ),
          const SizedBox(height: 20),

          // Cost row
          LayoutBuilder(
            builder: (context, bc) {
              final narrow = bc.maxWidth < 500;
              final c1 = predCard(
                icon: Icons.bolt_rounded,
                iconColor: orange,
                title: AppStrings.t('next_day_cost'),
                value: '${p.nextDayCost.toStringAsFixed(2)} MAD',
                subtitle: '≈ ${fmtEnergyUnit(p.nextDayEnergyMwh, _energyUnit)}',
                valueColor: orange,
              );
              final c2 = predCard(
                icon: Icons.calendar_month_rounded,
                iconColor: teal,
                title: AppStrings.t('month_end_cost'),
                value: '${p.monthEndCost.toStringAsFixed(2)} MAD',
                subtitle: narrow
                    ? '${p.monthToDateCost.toStringAsFixed(2)} MAD · ${p.daysRemainingInMonth}j restants'
                    : '${p.monthToDateCost.toStringAsFixed(2)} MAD déjà · ${p.daysRemainingInMonth}j restants',
                valueColor: teal,
              );
              if (narrow) {
                return Column(children: [c1, const SizedBox(height: 12), c2]);
              }
              return Row(
                children: [
                  Expanded(child: c1),
                  const SizedBox(width: 14),
                  Expanded(child: c2),
                ],
              );
            },
          ),
          const SizedBox(height: 14),

          // Power factor row
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: pfColor.withValues(alpha: 0.4),
                width: 1.2,
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: pfColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(pfIcon, color: pfColor, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p.pfWillDropBelow
                            ? '⚠  ${AppStrings.t('pf_alert_drop')} ${p.minutesUntilPfDrop?.toStringAsFixed(1) ?? '<1'} min'
                            : AppStrings.t('pf_stable'),
                        style: TextStyle(
                          color: pfColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'FP dans 10 min: ${p.predictedPf10min.toStringAsFixed(3)}'
                        '   ·   Tendance: ${p.pfTrend}',
                        style: const TextStyle(
                          color: Color(0xFF8899AA),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  p.predictedPf10min.toStringAsFixed(3),
                  style: TextStyle(
                    color: pfColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 26,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChart() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${AppStrings.t('chart_evolution')} ${_getMetricLabel()}',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 300,
              child: _filteredData.isEmpty
                  ? Center(
                      child: Text(
                        AppStrings.t('no_data_range'),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppTheme.darkGray,
                        ),
                      ),
                    )
                  : SfCartesianChart(
                      primaryXAxis: DateTimeAxis(
                        dateFormat: DateFormat.Hm(),
                        intervalType: DateTimeIntervalType.hours,
                        labelStyle: Theme.of(context).textTheme.labelSmall,
                      ),
                      primaryYAxis: NumericAxis(
                        labelFormat: _getYAxisFormat(),
                        labelStyle: Theme.of(context).textTheme.labelSmall,
                      ),
                      legend: _selectedUnit == _allUnitsKey
                          ? const Legend(
                              isVisible: true,
                              position: LegendPosition.bottom,
                            )
                          : const Legend(isVisible: false),
                      series: _selectedUnit == _allUnitsKey
                          ? <CartesianSeries>[
                              for (final u in _allUnitsList)
                                LineSeries<EnergyData, DateTime>(
                                  name: _labelFor(u),
                                  dataSource: _allUnitsFiltered[u] ?? [],
                                  xValueMapper: (data, _) => data.timestamp,
                                  yValueMapper: (data, _) =>
                                      _getMetricValue(data),
                                  color: _unitColors[u]!,
                                  width: 2,
                                ),
                            ]
                          : <CartesianSeries>[
                              LineSeries<EnergyData, DateTime>(
                                dataSource: _filteredData,
                                xValueMapper: (data, _) => data.timestamp,
                                yValueMapper: (data, _) =>
                                    _getMetricValue(data),
                                color: _getMetricColor(),
                                width: 2.5,
                              ),
                            ],
                      tooltipBehavior: TooltipBehavior(
                        enable: true,
                        borderColor: AppTheme.primaryNavy,
                        color: AppTheme.primaryNavy.withValues(alpha: 0.9),
                        textStyle: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatistics() {
    if (_filteredData.isEmpty) return const SizedBox.shrink();
    if (_selectedUnit == _allUnitsKey) return _buildAllUnitsStatistics();

    final values = _filteredData.map((data) => _getMetricValue(data)).toList();
    final min = values.reduce((a, b) => a < b ? a : b);
    final max = values.reduce((a, b) => a > b ? a : b);
    final avg = values.reduce((a, b) => a + b) / values.length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppStrings.t('statistics'),
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: _buildStatItem(
                    AppStrings.t('stat_min_full'),
                    min.toStringAsFixed(2),
                    _getMetricUnit(),
                    _getMetricColor(),
                  ),
                ),
                Container(width: 1, height: 60, color: Colors.grey[200]),
                Expanded(
                  child: _buildStatItem(
                    AppStrings.t('stat_max_full'),
                    max.toStringAsFixed(2),
                    _getMetricUnit(),
                    _getMetricColor(),
                  ),
                ),
                Container(width: 1, height: 60, color: Colors.grey[200]),
                Expanded(
                  child: _buildStatItem(
                    AppStrings.t('stat_avg_full'),
                    avg.toStringAsFixed(2),
                    _getMetricUnit(),
                    _getMetricColor(),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value, String unit, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AppTheme.darkGray.withValues(alpha: 0.7),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  value,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (unit.isNotEmpty) ...[
                  const SizedBox(width: 4),
                  Text(
                    unit,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: color.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDataTable() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppStrings.t('last_readings'),
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 300,
              child: _filteredData.isEmpty
                  ? Center(
                      child: Text(
                        AppStrings.t('no_data_range'),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppTheme.darkGray,
                        ),
                      ),
                    )
                  : ListView.separated(
                      itemCount: _filteredData.length,
                      separatorBuilder: (context, index) =>
                          Divider(color: Colors.grey[200], height: 1),
                      itemBuilder: (context, index) {
                        final data =
                            _filteredData[_filteredData.length - 1 - index];
                        final rowColor = _selectedUnit == _allUnitsKey
                            ? (_unitColors[data.unitId] ?? kTeal)
                            : _getMetricColor();
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 8,
                            horizontal: 0,
                          ),
                          leading: Container(
                            decoration: BoxDecoration(
                              color: rowColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            padding: const EdgeInsets.all(8),
                            child: Icon(
                              _selectedUnit == _allUnitsKey
                                  ? (_deviceIcon[data.unitId] ?? Icons.power)
                                  : _getMetricIcon(),
                              color: rowColor,
                              size: 20,
                            ),
                          ),
                          title: Text(
                            _formatTimestamp(data.timestamp),
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            '${_getMetricLabel()}: ${_getMetricValue(data).toStringAsFixed(2)} ${_getMetricUnit()}'
                            '${_selectedUnit == _allUnitsKey ? "  \u2022  ${_labelFor(data.unitId)}" : ""}',
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                          trailing: Container(
                            decoration: BoxDecoration(
                              color: rowColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            child: Text(
                              _getMetricValue(data).toStringAsFixed(1),
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: rowColor,
                                  ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUnitSelector() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
      color: _c.bg,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SizedBox(
                  width: 74,
                  child: Text(
                    '${AppStrings.t('metric_energy')}:',
                    style: TextStyle(color: _c.textSec, fontSize: 12),
                  ),
                ),
                const SizedBox(width: 4),
                ...['mWh', 'Wh', 'kWh'].map(
                  (u) => Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: _histUnitChip(
                      u,
                      _energyUnit,
                      kTeal,
                      'unitEnergy',
                      (v) => setState(() => _energyUnit = v),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                SizedBox(
                  width: 74,
                  child: Text(
                    '${AppStrings.t('metric_power')}:',
                    style: TextStyle(color: _c.textSec, fontSize: 12),
                  ),
                ),
                const SizedBox(width: 4),
                ...['mW', 'W', 'kW'].map(
                  (u) => Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: _histUnitChip(
                      u,
                      _powerUnit,
                      kOrange,
                      'unitPower',
                      (v) => setState(() => _powerUnit = v),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                SizedBox(
                  width: 74,
                  child: Text(
                    '${AppStrings.t('metric_voltage')}:',
                    style: TextStyle(color: _c.textSec, fontSize: 12),
                  ),
                ),
                const SizedBox(width: 4),
                ...['mV', 'V'].map(
                  (u) => Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: _histUnitChip(
                      u,
                      _voltageUnit,
                      const Color(0xFF4FC3F7),
                      'unitVoltage',
                      (v) => setState(() => _voltageUnit = v),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Text(
                  '${AppStrings.t('metric_current')}:',
                  style: TextStyle(color: _c.textSec, fontSize: 12),
                ),
                const SizedBox(width: 4),
                ...['mA', 'A'].map(
                  (u) => Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: _histUnitChip(
                      u,
                      _currentUnit,
                      const Color(0xFFFF6B8A),
                      'unitCurrent',
                      (v) => setState(() => _currentUnit = v),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _histUnitChip(
    String unit,
    String selected,
    Color accent,
    String prefKey,
    void Function(String) onSelect,
  ) {
    final sel = selected == unit;
    return GestureDetector(
      onTap: () async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(prefKey, unit);
        if (mounted) onSelect(unit);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: sel ? accent.withValues(alpha: 0.15) : _c.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: sel ? accent : _c.divider),
        ),
        child: Text(
          unit,
          style: TextStyle(
            color: sel ? accent : _c.textSec,
            fontSize: 11,
            fontWeight: sel ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  double _getMetricValue(EnergyData data) {
    switch (_selectedMetric) {
      case 'power':
        if (_powerUnit == 'mW') return data.power * 1000;
        if (_powerUnit == 'kW') return data.power / 1000;
        return data.power;
      case 'voltage':
        return _voltageUnit == 'mV' ? data.voltage * 1000 : data.voltage;
      case 'current':
        return _currentUnit == 'mA' ? data.current * 1000 : data.current;
      case 'energy':
        return mwhToUnit(data.energy, _energyUnit);
      case 'powerFactor':
        return data.powerFactor;
      case 'frequency':
        return data.frequency;
      default:
        if (_powerUnit == 'mW') return data.power * 1000;
        if (_powerUnit == 'kW') return data.power / 1000;
        return data.power;
    }
  }

  String _getMetricLabel() {
    switch (_selectedMetric) {
      case 'power':
        return AppStrings.t('metric_power');
      case 'voltage':
        return AppStrings.t('metric_voltage');
      case 'current':
        return AppStrings.t('metric_current');
      case 'energy':
        return AppStrings.t('metric_energy');
      case 'powerFactor':
        return AppStrings.t('metric_pf');
      case 'frequency':
        return AppStrings.t('metric_freq');
      default:
        return AppStrings.t('metric_power');
    }
  }

  String _getMetricUnit() {
    switch (_selectedMetric) {
      case 'power':
        return _powerUnit;
      case 'voltage':
        return _voltageUnit;
      case 'current':
        return _currentUnit;
      case 'energy':
        return _energyUnit;
      case 'powerFactor':
        return '';
      case 'frequency':
        return 'Hz';
      default:
        return _powerUnit;
    }
  }

  String _getYAxisFormat() {
    switch (_selectedMetric) {
      case 'powerFactor':
        return '{value}';
      case 'power':
        return '{value} $_powerUnit';
      case 'voltage':
        return '{value} $_voltageUnit';
      case 'current':
        return '{value} $_currentUnit';
      case 'energy':
        return '{value} $_energyUnit';
      case 'frequency':
        return '{value} Hz';
      default:
        return '{value}';
    }
  }

  Color _getMetricColor() {
    switch (_selectedMetric) {
      case 'power':
        return AppTheme.primaryNavy;
      case 'voltage':
        return AppTheme.successGreen;
      case 'current':
        return AppTheme.secondaryOrange;
      case 'energy':
        return AppTheme.warningYellow;
      case 'powerFactor':
        return AppTheme.errorRed;
      case 'frequency':
        return AppTheme.infoBlue;
      default:
        return AppTheme.primaryNavy;
    }
  }

  IconData _getMetricIcon() {
    switch (_selectedMetric) {
      case 'power':
        return Icons.power;
      case 'voltage':
        return Icons.flash_on;
      case 'current':
        return Icons.electrical_services;
      case 'energy':
        return Icons.battery_charging_full;
      case 'powerFactor':
        return Icons.speed;
      case 'frequency':
        return Icons.waves;
      default:
        return Icons.power;
    }
  }

  String _formatTimestamp(DateTime timestamp) {
    return '${timestamp.day.toString().padLeft(2, '0')}/${timestamp.month.toString().padLeft(2, '0')} ${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
  }

  Widget _buildAllUnitsStatistics() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${AppStrings.t('per_unit_stats')} — ${_getMetricLabel()}',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            ..._allUnitsList.map(_buildUnitStatRow),
          ],
        ),
      ),
    );
  }

  Widget _buildUnitStatRow(String unit) {
    final data = _allUnitsFiltered[unit] ?? [];
    if (data.isEmpty) return const SizedBox.shrink();
    final values = data.map(_getMetricValue).toList();
    final minVal = values.reduce((a, b) => a < b ? a : b);
    final maxVal = values.reduce((a, b) => a > b ? a : b);
    final avg = values.reduce((a, b) => a + b) / values.length;
    final color = _unitColors[unit] ?? kTeal;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(_deviceIcon[unit]!, color: color, size: 16),
            const SizedBox(width: 6),
            Text(
              _labelFor(unit),
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '(${data.length} pts)',
              style: TextStyle(color: _c.textSec, fontSize: 11),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _buildStatItem(
                AppStrings.t('stat_min'),
                minVal.toStringAsFixed(2),
                _getMetricUnit(),
                color,
              ),
            ),
            Container(width: 1, height: 60, color: Colors.grey[200]),
            Expanded(
              child: _buildStatItem(
                AppStrings.t('stat_max'),
                maxVal.toStringAsFixed(2),
                _getMetricUnit(),
                color,
              ),
            ),
            Container(width: 1, height: 60, color: Colors.grey[200]),
            Expanded(
              child: _buildStatItem(
                AppStrings.t('stat_avg'),
                avg.toStringAsFixed(2),
                _getMetricUnit(),
                color,
              ),
            ),
          ],
        ),
        if (unit != _allUnitsList.last)
          Divider(color: Colors.grey[200], height: 24),
      ],
    );
  }
}
