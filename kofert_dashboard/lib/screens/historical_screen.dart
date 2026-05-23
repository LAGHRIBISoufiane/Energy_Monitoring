import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import 'package:flutter/services.dart';
import 'package:firebase_database/firebase_database.dart';
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
import '../theme/app_theme.dart';
import '../main.dart' show kTeal;
import '../l10n/app_strings.dart';

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
  static const _emailjsServiceId  = 'service_1tovyp1';
  static const _emailjsTemplateId = 'template_9cy6uou';
  static const _emailjsPublicKey  = 'Ls3qUruwpCXXayiZB';

  bool _isSendingEmail = false;
  List<EnergyData> _historicalData = [];
  List<EnergyData> _filteredData = [];
  Map<String, List<EnergyData>> _allUnitsData = {};
  Map<String, List<EnergyData>> _allUnitsFiltered = {};
  bool _isLoading = true;
  DateTime _lastRefreshed = DateTime.now();
  String _selectedMetric = 'power';
  DateTime _startDate = DateTime.now().subtract(const Duration(days: 7));
  DateTime _endDate = DateTime.now();
  PredictionResult? _predictions;
  double _tariffRate = 1.15;
  String _selectedUnit = 'KOFERT_Unit_1';

  // Real-time listener & 5-second auto-refresh timer
  StreamSubscription? _rtSubscription;
  Timer? _refreshTimer;
  final Set<String> _seenKeys = {};

  static const _allUnitsKey = 'ALL_UNITS';
  static const _allUnitsList = ['KOFERT_Unit_1', 'KOFERT_Unit_2', 'KOFERT_Unit_3'];
  static const _units = ['ALL_UNITS', 'KOFERT_Unit_1', 'KOFERT_Unit_2', 'KOFERT_Unit_3'];
  static final Map<String, Color> _unitColors = {
    'KOFERT_Unit_1': kTeal,
    'KOFERT_Unit_2': AppTheme.secondaryOrange,
    'KOFERT_Unit_3': AppTheme.successGreen,
  };

  static String _labelFor(String unit) {
    switch (unit) {
      case 'ALL_UNITS': return 'Toutes les unités';
      case 'KOFERT_Unit_1': return AppStrings.t('device_lamp');
      case 'KOFERT_Unit_2': return AppStrings.t('device_fan_5v');
      case 'KOFERT_Unit_3': return AppStrings.t('device_pump_5v');
      default: return unit;
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
    final ref = FirebaseDatabase.instance
        .ref('$_selectedUnit/historical_data');
    _rtSubscription = ref.onChildAdded.listen((event) {
      final snap = event.snapshot;
      if (snap.value == null) return;
      try {
        final data = EnergyData.fromJson(
            Map<String, dynamic>.from(snap.value as Map),
            _selectedUnit);
        final key = data.timestamp.toIso8601String();
        if (_seenKeys.contains(key)) return; // already loaded
        _seenKeys.add(key);
        if (!mounted) return;
        setState(() {
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
      _tariffRate   = prefs.getDouble('tariffRate') ?? 1.15;
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

  Future<void> _refreshData() async {
    // Quiet refresh — no loading spinner
    try {
      if (_selectedUnit == _allUnitsKey) {
        final results = await Future.wait(
          _allUnitsList.map((u) => EnergyRepository.instance.getHistoricalData(u, limit: 500)),
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
          _applyDateFilter();
          _lastRefreshed = DateTime.now();
        });
      } else {
        final dataList = await EnergyRepository.instance
            .getHistoricalData(_selectedUnit, limit: 500);
        if (!mounted) return;
        setState(() {
          _historicalData = dataList;
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
    setState(() => _isLoading = true);
    try {
      if (_selectedUnit == _allUnitsKey) {
        final results = await Future.wait(
          _allUnitsList.map((u) => EnergyRepository.instance.getHistoricalData(u, limit: 500)),
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
          _applyDateFilter();
          _isLoading = false;
          _lastRefreshed = DateTime.now();
        });
      } else {
        final dataList = await EnergyRepository.instance
            .getHistoricalData(_selectedUnit, limit: 500);
        if (!mounted) return;
        setState(() {
          _historicalData = dataList;
          _allUnitsData = {};
          _applyDateFilter();
          _isLoading = false;
          _lastRefreshed = DateTime.now();
        });
        _runPredictions();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur de chargement: $e')),
      );
    }
  }

  void _applyDateFilter() {
    if (_selectedUnit == _allUnitsKey) {
      _allUnitsFiltered = {};
      for (final entry in _allUnitsData.entries) {
        _allUnitsFiltered[entry.key] = entry.value
            .where((d) => !d.timestamp.isBefore(_startDate) && !d.timestamp.isAfter(_endDate))
            .toList();
      }
      _filteredData = [for (final l in _allUnitsFiltered.values) ...l]
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    } else {
      _filteredData = _historicalData
          .where((data) =>
              !data.timestamp.isBefore(_startDate) &&
              !data.timestamp.isAfter(_endDate))
          .toList();
    }
  }

  void _runPredictions() {
    if (_historicalData.isEmpty) return;
    final predictor = EnergyPredictor(
        tariffRate: _tariffRate, pfThreshold: 0.8);
    final result = predictor.predict(_historicalData);
    if (mounted) setState(() => _predictions = result);
  }

  void _showSendEmailDialog() {
    final emailController = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            title: const Row(children: [
              Icon(Icons.email_outlined, color: kTeal),
              SizedBox(width: 10),
              Text('Envoyer par email'),
            ]),
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
                TextField(
                  controller: emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    labelText: 'Adresse email du destinataire',
                    prefixIcon: const Icon(Icons.alternate_email, size: 18),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Annuler'),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: kTeal),
                onPressed: _isSendingEmail
                    ? null
                    : () async {
                        final email = emailController.text.trim();
                        if (email.isEmpty || !email.contains('@')) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Adresse email invalide')),
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aucune donnée à envoyer')),
      );
      return;
    }

    setState(() => _isSendingEmail = true);

    try {
      final avgPower = _filteredData.map((e) => e.power).reduce((a, b) => a + b) / _filteredData.length;
      final avgPf    = _filteredData.map((e) => e.powerFactor).reduce((a, b) => a + b) / _filteredData.length;
      final totalEnergy = _filteredData.fold<double>(0, (s, e) => s + e.energy);

      final response = await http_client.post(
        Uri.parse('https://api.emailjs.com/api/v1.0/email/send'),
        headers: {'Content-Type': 'application/json', 'origin': html.window.location.href},
        body: jsonEncode({
          'service_id':  _emailjsServiceId,
          'template_id': _emailjsTemplateId,
          'user_id':     _emailjsPublicKey,
          'template_params': {
            'to_email':     toEmail,
            'unit_name':    '$_selectedUnit — ${_labelFor(_selectedUnit)}',
            'date_from':    DateFormat('dd/MM/yyyy').format(_startDate),
            'date_to':      DateFormat('dd/MM/yyyy').format(_endDate),
            'total_records': '${_filteredData.length}',
            'avg_power':    '${avgPower.toStringAsFixed(2)} W',
            'avg_pf':       avgPf.toStringAsFixed(3),
            'total_energy': '${totalEnergy.toStringAsFixed(2)} mWh',
          },
        }),
      );

      if (!mounted) return;
      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Email envoyé à $toEmail ✓'),
            backgroundColor: const Color(0xFF2ECC71),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Échec EmailJS (${response.statusCode}): ${response.body}')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur envoi email: $e')),
      );
    } finally {
      if (mounted) setState(() => _isSendingEmail = false);
    }
  }

  void _exportToExcel() {
    if (_filteredData.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aucune donnée à exporter')),
      );
      return;
    }
    try {
      final excel = xl.Excel.createExcel();
      final sheet = excel['KOFERT Energy'];
      excel.delete('Sheet1');

      // Header row
      final headers = [
        'Timestamp', 'Puissance (W)', 'Tension (V)', 'Courant (A)',
        'Energie (mWh)', 'Facteur de Puissance', 'Fréquence (Hz)',
        'Puissance Apparente (VA)', 'Puissance Réactive (VAR)',
      ];
      sheet.appendRow(headers.map((h) => xl.TextCellValue(h)).toList());

      // Style header
      for (int c = 0; c < headers.length; c++) {
        final cell = sheet.cell(
            xl.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0));
        cell.cellStyle = xl.CellStyle(
          bold: true,
          backgroundColorHex: xl.ExcelColor.fromHexString('#1A2E4A'),
          fontColorHex: xl.ExcelColor.fromHexString('#FFFFFF'),
        );
      }

      // Data rows
      for (final d in _filteredData) {
        sheet.appendRow([
          xl.TextCellValue(
              DateFormat('yyyy-MM-dd HH:mm:ss').format(d.timestamp)),
          xl.DoubleCellValue(d.power),
          xl.DoubleCellValue(d.voltage),
          xl.DoubleCellValue(d.current),
          xl.DoubleCellValue(d.energy),
          xl.DoubleCellValue(d.powerFactor),
          xl.DoubleCellValue(d.frequency),
          xl.DoubleCellValue(d.apparentPower),
          xl.DoubleCellValue(d.reactivePower),
        ]);
      }

      // Predictions sheet
      if (_predictions != null) {
        final pSheet = excel['Prédictions IA'];
        pSheet.appendRow([xl.TextCellValue('Indicateur'), xl.TextCellValue('Valeur')]);
        pSheet.appendRow([xl.TextCellValue('Coût prochain jour (MAD)'), xl.DoubleCellValue(_predictions!.nextDayCost)]);
        pSheet.appendRow([xl.TextCellValue('Energie prochain jour (mWh)'), xl.DoubleCellValue(_predictions!.nextDayEnergyMwh)]);
        pSheet.appendRow([xl.TextCellValue('Coût fin du mois (MAD)'), xl.DoubleCellValue(_predictions!.monthEndCost)]);
        pSheet.appendRow([xl.TextCellValue('Coût cumulé ce mois (MAD)'), xl.DoubleCellValue(_predictions!.monthToDateCost)]);
        pSheet.appendRow([xl.TextCellValue('FP prédit (10 min)'), xl.DoubleCellValue(_predictions!.predictedPf10min)]);
        pSheet.appendRow([xl.TextCellValue('Tendance FP'), xl.TextCellValue(_predictions!.pfTrend)]);
        pSheet.appendRow([xl.TextCellValue('Alerte FP'), xl.TextCellValue(_predictions!.pfWillDropBelow ? 'OUI' : 'NON')]);
      }

      final bytes = excel.save()!;
      final ts = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final blob = html.Blob([
        Uint8List.fromList(bytes)
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur export Excel: $e')),
      );
    }
  }

  void _exportToCSV() {
    if (_filteredData.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aucune donnée à exporter')),
      );
      return;
    }

    final headers = 'Timestamp,Power (W),Voltage (V),Current (A),Energy (mWh),Power Factor,Frequency (Hz)\n';
    final rows = _filteredData.map((data) =>
        '${DateFormat('yyyy-MM-dd HH:mm:ss').format(data.timestamp)},'
        '${data.power},${data.voltage},${data.current},${data.energy},'
        '${data.powerFactor},${data.frequency}'
    ).join('\n');

    final csv = headers + rows;
    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final filename = 'KOFERT_Energy_$timestamp.csv';

    _showExportDialog(csv, filename);
  }

  void _exportToJSON() {
    if (_filteredData.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aucune donnée à exporter')),
      );
      return;
    }

    final data = _filteredData.map((e) => {
      'timestamp': DateFormat('yyyy-MM-dd HH:mm:ss').format(e.timestamp),
      'power_w': e.power,
      'voltage_v': e.voltage,
      'current_a': e.current,
      'energy_mwh': e.energy,
      'power_factor': e.powerFactor,
      'frequency_hz': e.frequency,
    }).toList();

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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                  Text('Entrées', style: Theme.of(context).textTheme.labelSmall),
                  Container(
                    decoration: BoxDecoration(
                      color: AppTheme.secondaryOrange.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
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
                      content.substring(0, (content.length > 500 ? 500 : content.length)),
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
          Container(
            color: _c.card,
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            child: Row(
              children: [
                // Unit selector
                DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedUnit,
                    dropdownColor: _c.card,
                    style: TextStyle(color: _c.textPri, fontSize: 14),
                    icon: Icon(Icons.expand_more,
                        color: _c.textSec, size: 18),
                    items: _units.map((u) => DropdownMenuItem(
                          value: u,
                          child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(_deviceIcon[u]!,
                                    color: kTeal, size: 16),
                                const SizedBox(width: 8),
                                Text(
                                    u == 'ALL_UNITS' ? _labelFor(u) : '$u  —  ${_labelFor(u)}',
                                    style: TextStyle(
                                        color: _c.textPri)),
                              ]),
                        )).toList(),
                    onChanged: (v) {
                      if (v != null) _switchUnit(v);
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Text('Données Historiques',
                    style: TextStyle(
                        color: _c.textPri,
                        fontWeight: FontWeight.bold,
                        fontSize: 18)),
                const Spacer(),
                // Email button
                _isSendingEmail
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: kTeal),
                      )
                    : IconButton(
                        icon: Icon(Icons.email_outlined, color: _c.textPri),
                        tooltip: 'Envoyer par email',
                        onPressed: _filteredData.isEmpty ? null : _showSendEmailDialog,
                      ),
                const SizedBox(width: 4),
                PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'csv') _exportToCSV();
                    if (value == 'json') _exportToJSON();
                    if (value == 'excel') _exportToExcel();
                  },
                  itemBuilder: (BuildContext context) => [
                    PopupMenuItem(value: 'excel', child: Row(children: [Icon(Icons.table_view_rounded, color: kTeal), const SizedBox(width: 10), const Text('Exporter Excel (.xlsx)')])),
                    PopupMenuItem(value: 'csv', child: Row(children: [Icon(Icons.table_chart, color: kTeal), const SizedBox(width: 10), const Text('Exporter CSV')])),
                    PopupMenuItem(value: 'json', child: Row(children: [Icon(Icons.code, color: kTeal), const SizedBox(width: 10), const Text('Exporter JSON')])),
                  ],
                  icon: Icon(Icons.download, color: _c.textPri),
                ),
              ],
            ),
          ),
          // ── Auto-refresh status bar ──────────────────────────────────────────
          Container(
            color: _c.card,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
            child: Row(
              children: [
                Container(
                  width: 8, height: 8,
                  decoration: const BoxDecoration(
                    color: AppTheme.successGreen,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  'Actualisation auto toutes les 5s  •  Mise à jour: ${DateFormat('HH:mm:ss').format(_lastRefreshed)}',
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
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppTheme.darkGray,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    return Column(
      children: [
        _buildDateRangeFilter(),
        const SizedBox(height: 4),
        _buildMetricSelector(),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                if (_predictions != null && _selectedUnit != _allUnitsKey) ...[
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

  Widget _buildDateRangeFilter() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        color: _c.card,
        border: Border(
          bottom: BorderSide(color: Colors.white12, width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Plage de Dates',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: AppTheme.darkGray,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildDateButton(_startDate, () => _selectStartDate(context)),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  'à',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildDateButton(_endDate, () => _selectEndDate(context)),
              ),
              const SizedBox(width: 8),
              Tooltip(
                message: 'Réinitialiser les dates',
                child: IconButton(
                  icon: const Icon(Icons.refresh),
                  color: AppTheme.primaryNavy,
                  onPressed: () {
                    setState(() {
                      _startDate = DateTime.now().subtract(const Duration(days: 7));
                      _endDate = DateTime.now();
                      _applyDateFilter();
                    });
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${_filteredData.length} entrées affichées',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AppTheme.darkGray.withValues(alpha: 0.7),
            ),
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
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          fontWeight: FontWeight.w500,
        ),
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
        _startDate = picked;
        _applyDateFilter();
      });
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
        _endDate = picked;
        _applyDateFilter();
      });
    }
  }

  Widget _buildMetricSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: _c.bg,
      child: Row(
        children: [
          Text(
            'Métrique:',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: _c.card,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white12, width: 1),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: DropdownButton<String>(
                  value: _selectedMetric,
                  dropdownColor: _c.card,
                  isExpanded: true,
                  underline: const SizedBox(),
                  icon: Icon(Icons.expand_more, color: AppTheme.primaryNavy),
                  items: [
                    DropdownMenuItem(
                      value: 'power',
                      child: Text('Puissance (W)', style: Theme.of(context).textTheme.bodySmall),
                    ),
                    DropdownMenuItem(
                      value: 'voltage',
                      child: Text('Tension (V)', style: Theme.of(context).textTheme.bodySmall),
                    ),
                    DropdownMenuItem(
                      value: 'current',
                      child: Text('Courant (A)', style: Theme.of(context).textTheme.bodySmall),
                    ),
                    DropdownMenuItem(
                      value: 'energy',
                      child: Text('Énergie (mWh)', style: Theme.of(context).textTheme.bodySmall),
                    ),
                    DropdownMenuItem(
                      value: 'powerFactor',
                      child: Text('Facteur de Puissance', style: Theme.of(context).textTheme.bodySmall),
                    ),
                    DropdownMenuItem(
                      value: 'frequency',
                      child: Text('Fréquence (Hz)', style: Theme.of(context).textTheme.bodySmall),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        _selectedMetric = value;
                      });
                    }
                  },
                ),
              ),
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
          border: Border.all(color: iconColor.withValues(alpha: 0.25), width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
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
                child: Text(title,
                    style: const TextStyle(
                        color: Color(0xFF8899AA), fontSize: 11)),
              ),
            ]),
            const SizedBox(height: 12),
            Text(value,
                style: TextStyle(
                    color: valueColor ?? Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold)),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(subtitle,
                  style: const TextStyle(
                      color: Color(0xFF8899AA), fontSize: 11)),
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
        border: Border.all(
            color: teal.withValues(alpha: 0.3), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title row
          Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: teal.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.auto_awesome_rounded,
                  color: kTeal, size: 20),
            ),
            const SizedBox(width: 12),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Pr\u00e9dictions IA',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16)),
                Text('R\u00e9gression lin\u00e9aire sur l\'historique collect\u00e9',
                    style: TextStyle(
                        color: Color(0xFF8899AA), fontSize: 11)),
              ],
            ),
            const Spacer(),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: teal.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text('Confiance $confPct%',
                  style: const TextStyle(
                      color: kTeal, fontSize: 11)),
            ),
          ]),
          const SizedBox(height: 20),

          // Cost row
          Row(children: [
            Expanded(
              child: predCard(
                icon: Icons.bolt_rounded,
                iconColor: orange,
                title: 'COÛT PROCHAIN JOUR',
                value:
                    '${p.nextDayCost.toStringAsFixed(2)} MAD',
                subtitle:
                    '≈ ${p.nextDayEnergyMwh.toStringAsFixed(2)} mWh',
                valueColor: orange,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: predCard(
                icon: Icons.calendar_month_rounded,
                iconColor: teal,
                title: 'COÛT FIN DU MOIS',
                value:
                    '${p.monthEndCost.toStringAsFixed(2)} MAD',
                subtitle:
                    '${p.monthToDateCost.toStringAsFixed(2)} MAD déjà · ${p.daysRemainingInMonth}j restants',
                valueColor: teal,
              ),
            ),
          ]),
          const SizedBox(height: 14),

          // Power factor row
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: pfColor.withValues(alpha: 0.4), width: 1.2),
            ),
            child: Row(children: [
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
                          ? '⚠  Alerte FP — chute pr\u00e9vue dans ${p.minutesUntilPfDrop?.toStringAsFixed(1) ?? '<1'} min'
                          : 'Facteur de puissance stable',
                      style: TextStyle(
                          color: pfColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 13),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'FP dans 10 min: ${p.predictedPf10min.toStringAsFixed(3)}'
                      '   ·   Tendance: ${p.pfTrend}',
                      style: const TextStyle(
                          color: Color(0xFF8899AA), fontSize: 11),
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
                    fontSize: 26),
              ),
            ]),
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
              'Évolution ${_getMetricLabel()}',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 300,
              child: _filteredData.isEmpty
                  ? Center(
                      child: Text(
                        'Aucune donnée pour cette plage de dates',
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
                          ? const Legend(isVisible: true, position: LegendPosition.bottom)
                          : const Legend(isVisible: false),
                      series: _selectedUnit == _allUnitsKey
                          ? <CartesianSeries>[
                              for (final u in _allUnitsList)
                                LineSeries<EnergyData, DateTime>(
                                  name: _labelFor(u),
                                  dataSource: _allUnitsFiltered[u] ?? [],
                                  xValueMapper: (data, _) => data.timestamp,
                                  yValueMapper: (data, _) => _getMetricValue(data),
                                  color: _unitColors[u]!,
                                  width: 2,
                                ),
                            ]
                          : <CartesianSeries>[
                              LineSeries<EnergyData, DateTime>(
                                dataSource: _filteredData,
                                xValueMapper: (data, _) => data.timestamp,
                                yValueMapper: (data, _) => _getMetricValue(data),
                                color: _getMetricColor(),
                                width: 2.5,
                              ),
                            ],
                      tooltipBehavior: TooltipBehavior(
                        enable: true,
                        borderColor: AppTheme.primaryNavy,
                        color: AppTheme.primaryNavy.withValues(alpha: 0.9),
                        textStyle: const TextStyle(color: Colors.white, fontSize: 12),
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
              'Statistiques',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: _buildStatItem(
                    'Minimum',
                    min.toStringAsFixed(2),
                    _getMetricUnit(),
                    _getMetricColor(),
                  ),
                ),
                Container(width: 1, height: 60, color: Colors.grey[200]),
                Expanded(
                  child: _buildStatItem(
                    'Maximum',
                    max.toStringAsFixed(2),
                    _getMetricUnit(),
                    _getMetricColor(),
                  ),
                ),
                Container(width: 1, height: 60, color: Colors.grey[200]),
                Expanded(
                  child: _buildStatItem(
                    'Moyenne',
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AppTheme.darkGray.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 8),
          Row(
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
              'Dernières Mesures',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 300,
              child: _filteredData.isEmpty
                  ? Center(
                      child: Text(
                        'Aucune donnée pour cette plage de dates',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppTheme.darkGray,
                        ),
                      ),
                    )
                  : ListView.separated(
                      itemCount: _filteredData.length,
                      separatorBuilder: (context, index) => Divider(
                        color: Colors.grey[200],
                        height: 1,
                      ),
                      itemBuilder: (context, index) {
                        final data = _filteredData[_filteredData.length - 1 - index];
                        final rowColor = _selectedUnit == _allUnitsKey
                            ? (_unitColors[data.unitId] ?? kTeal)
                            : _getMetricColor();
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 0),
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
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
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
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            child: Text(
                              _getMetricValue(data).toStringAsFixed(1),
                              style: Theme.of(context).textTheme.labelSmall?.copyWith(
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

  double _getMetricValue(EnergyData data) {
    switch (_selectedMetric) {
      case 'power':
        return data.power;
      case 'voltage':
        return data.voltage;
      case 'current':
        return data.current;
      case 'energy':
        return data.energy;
      case 'powerFactor':
        return data.powerFactor;
      case 'frequency':
        return data.frequency;
      default:
        return data.power;
    }
  }

  String _getMetricLabel() {
    switch (_selectedMetric) {
      case 'power':
        return 'Puissance';
      case 'voltage':
        return 'Tension';
      case 'current':
        return 'Courant';
      case 'energy':
        return 'Énergie';
      case 'powerFactor':
        return 'Facteur de Puissance';
      case 'frequency':
        return 'Fréquence';
      default:
        return 'Puissance';
    }
  }

  String _getMetricUnit() {
    switch (_selectedMetric) {
      case 'power':
        return 'W';
      case 'voltage':
        return 'V';
      case 'current':
        return 'A';
      case 'energy':
        return 'mWh';
      case 'powerFactor':
        return '';
      case 'frequency':
        return 'Hz';
      default:
        return 'W';
    }
  }

  String _getYAxisFormat() {
    switch (_selectedMetric) {
      case 'powerFactor':
        return '{value}';
      case 'energy':
        return '{value} mWh';
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
              'Statistiques par Unité — ${_getMetricLabel()}',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
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
        Row(children: [
          Icon(_deviceIcon[unit]!, color: color, size: 16),
          const SizedBox(width: 6),
          Text(
            _labelFor(unit),
            style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 13),
          ),
          const SizedBox(width: 6),
          Text(
            '(${data.length} pts)',
            style: TextStyle(color: _c.textSec, fontSize: 11),
          ),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: _buildStatItem('Min', minVal.toStringAsFixed(2), _getMetricUnit(), color)),
          Container(width: 1, height: 60, color: Colors.grey[200]),
          Expanded(child: _buildStatItem('Max', maxVal.toStringAsFixed(2), _getMetricUnit(), color)),
          Container(width: 1, height: 60, color: Colors.grey[200]),
          Expanded(child: _buildStatItem('Moy', avg.toStringAsFixed(2), _getMetricUnit(), color)),
        ]),
        if (unit != _allUnitsList.last) Divider(color: Colors.grey[200], height: 24),
      ],
    );
  }
}