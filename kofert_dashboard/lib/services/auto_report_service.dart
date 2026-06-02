import 'dart:async';
import 'dart:convert';
// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'energy_repository.dart';

/// Singleton that fires a periodic energy report email when the user has
/// enabled auto-reports in Settings.
///
/// Runs a 1-hour timer; sends at most once per 24 h (daily) or per 7 days
/// (weekly). Completely silent on failure — will retry on the next tick.
class AutoReportService {
  AutoReportService._();
  static final instance = AutoReportService._();

  // ── EmailJS credentials (same as HistoricalScreen) ─────────────────────────
  static const _emailjsServiceId  = 'service_1tovyp1';
  static const _emailjsTemplateId = 'template_9cy6uou';
  static const _emailjsPublicKey  = 'mD7lZMFFUPuDZlNRf';

  Timer? _timer;

  /// Call once from [_MainScreenState.initState] after the user is signed in.
  void initialize() {
    _timer?.cancel();
    _checkAndSendIfDue(); // immediate check on app start
    _timer = Timer.periodic(
      const Duration(hours: 1),
      (_) => _checkAndSendIfDue(),
    );
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _checkAndSendIfDue() async {
    final prefs = await SharedPreferences.getInstance();

    if (!(prefs.getBool('autoReportEnabled') ?? false)) return;

    // Collect all registered user emails from Firestore.
    final snap = await FirebaseFirestore.instance.collection('users').get();
    final emails = <String>{
      for (final d in snap.docs)
        if (((d.data()['email'] as String?) ?? '').contains('@'))
          d.data()['email'] as String,
    };
    // Also include the currently signed-in user in case their doc is missing.
    final me = FirebaseAuth.instance.currentUser?.email ?? '';
    if (me.contains('@')) emails.add(me);
    if (emails.isEmpty) return;

    final frequency = prefs.getString('autoReportFrequency') ?? 'daily';
    final lastSentMs = prefs.getInt('autoReportLastSentMs') ?? 0;
    final lastSent = DateTime.fromMillisecondsSinceEpoch(lastSentMs);
    final now = DateTime.now();

    final isDue = frequency == 'daily'
        ? now.difference(lastSent).inHours >= 24
        : now.difference(lastSent).inDays >= 7;
    if (!isDue) return;

    final unit = prefs.getString('selectedUnit') ?? 'KOFERT_Unit_1';
    final cutoff = frequency == 'daily'
        ? now.subtract(const Duration(hours: 24))
        : now.subtract(const Duration(days: 7));

    try {
      // Fetch up to 2016 points (covers ~7 days at 5-min intervals).
      final allData =
          await EnergyRepository.instance.getHistoricalData(unit, limit: 2016);
      final data =
          allData.where((d) => d.timestamp.isAfter(cutoff)).toList();
      if (data.isEmpty) return;

      final avgPower =
          data.map((e) => e.power).reduce((a, b) => a + b) / data.length;
      final avgPf =
          data.map((e) => e.powerFactor).reduce((a, b) => a + b) / data.length;
      // Energy is a cumulative counter. Correct total = max - min (counter advance).
      final totalEnergy = data.isNotEmpty
          ? (data.map((e) => e.energy).reduce((a, b) => a > b ? a : b) -
             data.map((e) => e.energy).reduce((a, b) => a < b ? a : b)).clamp(0, double.infinity)
          : 0.0;
      final tariff = prefs.getDouble('tariffRate') ?? 1.15;
      // mWh → kWh (÷1 000 000), then × tariff (MAD/kWh)
      final estimatedCost = (totalEnergy / 1000000.0) * tariff;

      final fmt         = DateFormat('dd/MM/yyyy');
      final timeFmt      = DateFormat('dd/MM/yyyy HH:mm');
      final periodLabel  = frequency == 'daily'
          ? 'Rapport Quotidien (24h)'
          : 'Rapport Hebdomadaire (7j)';
      final unitLabel    = '$unit — $periodLabel';
      final subject      = '$periodLabel — $unit (${fmt.format(cutoff)} → ${fmt.format(now)})';
      final avgVoltage   = data.map((e) => e.voltage).reduce((a, b) => a + b) / data.length;
      final avgCurrent   = data.map((e) => e.current).reduce((a, b) => a + b) / data.length;

      final message = '''
<div style="font-family:Arial,Helvetica,sans-serif;max-width:620px">
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
  <!-- Content -->
  <table style="width:100%;border-collapse:collapse;font-size:13px;border:1px solid #c5d9f5;border-top:none">
  <tr style="background:#f8f9fa">
    <td style="padding:10px 14px;border:1px solid #e0e0e0;color:#888;width:44%">Unité</td>
    <td style="padding:10px 14px;border:1px solid #e0e0e0;font-weight:600">$unitLabel</td>
  </tr>
  <tr>
    <td style="padding:10px 14px;border:1px solid #e0e0e0;color:#888">Période</td>
    <td style="padding:10px 14px;border:1px solid #e0e0e0">${fmt.format(cutoff)} → ${fmt.format(now)}</td>
  </tr>
  <tr style="background:#f8f9fa">
    <td style="padding:10px 14px;border:1px solid #e0e0e0;color:#888">Nombre de mesures</td>
    <td style="padding:10px 14px;border:1px solid #e0e0e0">${data.length}</td>
  </tr>
  <tr>
    <td style="padding:10px 14px;border:1px solid #e0e0e0;color:#888">Tension moyenne</td>
    <td style="padding:10px 14px;border:1px solid #e0e0e0">${avgVoltage.toStringAsFixed(2)} V</td>
  </tr>
  <tr style="background:#f8f9fa">
    <td style="padding:10px 14px;border:1px solid #e0e0e0;color:#888">Courant moyen</td>
    <td style="padding:10px 14px;border:1px solid #e0e0e0">${avgCurrent.toStringAsFixed(3)} A</td>
  </tr>
  <tr>
    <td style="padding:10px 14px;border:1px solid #e0e0e0;color:#888">Puissance moyenne</td>
    <td style="padding:10px 14px;border:1px solid #e0e0e0;font-weight:600;color:#1a73e8">${avgPower.toStringAsFixed(2)} W</td>
  </tr>
  <tr style="background:#f8f9fa">
    <td style="padding:10px 14px;border:1px solid #e0e0e0;color:#888">Facteur de puissance moyen</td>
    <td style="padding:10px 14px;border:1px solid #e0e0e0">${avgPf.toStringAsFixed(3)}</td>
  </tr>
  <tr>
    <td style="padding:10px 14px;border:1px solid #e0e0e0;color:#888">Énergie totale</td>
    <td style="padding:10px 14px;border:1px solid #e0e0e0;font-weight:600;color:#27ae60">${totalEnergy >= 1000000 ? (totalEnergy / 1000000).toStringAsFixed(2) + ' kWh' : totalEnergy >= 1000 ? (totalEnergy / 1000).toStringAsFixed(2) + ' Wh' : totalEnergy.toStringAsFixed(2) + ' mWh'}</td>
  </tr>
  <tr style="background:#f8f9fa">
    <td style="padding:10px 14px;border:1px solid #e0e0e0;color:#888">Coût estimé</td>
    <td style="padding:10px 14px;border:1px solid #e0e0e0;font-weight:600;color:#e67e22">${estimatedCost.toStringAsFixed(2)} MAD</td>
  </tr>
  </table>
  <!-- Footer -->
  <div style="background:#e8f0fe;border:1px solid #c5d9f5;border-top:none;border-radius:0 0 8px 8px;padding:12px 16px;font-size:11px;color:#444;text-align:center">
    Ce rapport a été généré automatiquement. Consultez le tableau de bord pour plus de détails.<br>
    <a href="https://ocp-energy-monitor.web.app" style="color:#0D47A1">ocp-energy-monitor.web.app</a>
  </div>
</div>''';

      // Send to every registered user; track success if at least one succeeds.
      bool anySent = false;
      for (final toEmail in emails) {
        try {
          final response = await http.post(
            Uri.parse('https://api.emailjs.com/api/v1.0/email/send'),
            headers: {
              'Content-Type': 'application/json',
              'origin': html.window.location.href,
            },
            body: jsonEncode({
              'service_id':  _emailjsServiceId,
              'template_id': _emailjsTemplateId,
              'user_id':     _emailjsPublicKey,
              'template_params': {
                'name':     unitLabel,
                'time':     timeFmt.format(now),
                'to_email': toEmail,
                'subject':  subject,
                'message':  message,
              },
            }),
          );
          if (response.statusCode == 200) anySent = true;
        } catch (_) {
          // Per-address failure is silent; continue to next recipient.
        }
      }

      if (anySent) {
        // Record timestamp so the next check knows not to re-send immediately.
        await prefs.setInt(
            'autoReportLastSentMs', now.millisecondsSinceEpoch);
      }
    } catch (_) {
      // Silent fail — will retry on next hourly tick.
    }
  }
}
