import 'dart:async';
import 'dart:convert';
// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Handles two alert notification responsibilities:
///
/// 1. **On alert fire** – sends an email to every registered user.
///    Throttled to one email per unique alert [title] per 5 minutes to
///    prevent inbox flooding during sustained fault conditions.
///
/// 2. **On login** – checks Firestore for alerts that fired while the user
///    was offline and shows a SnackBar with a "View" action.
class AlertNotificationService {
  AlertNotificationService._();
  static final instance = AlertNotificationService._();

  static const _serviceId  = 'service_1tovyp1';
  static const _templateId = 'template_9cy6uou';
  static const _publicKey  = 'mD7lZMFFUPuDZlNRf';

  static const _throttleMs = 5 * 60 * 1000; // 5 minutes per alert type

  // ── Alert-email broadcast ─────────────────────────────────────────────────

  /// Called from [_logAlert] in DashboardScreen after every unique alert.
  /// Fire-and-forget — never throws.
  Future<void> sendAlertToAllUsers({
    required String title,
    required String detail,
    required String unitId,
  }) async {
    try {
      // Throttle: skip if the same alert type was emailed within 5 min.
      final prefs  = await SharedPreferences.getInstance();
      final key    = 'alertEmailSent_$title';
      final lastMs = prefs.getInt(key) ?? 0;
      final now    = DateTime.now();
      if (now.millisecondsSinceEpoch - lastMs < _throttleMs) return;
      await prefs.setInt(key, now.millisecondsSinceEpoch);

      // Collect emails from every user doc.
      final snap = await FirebaseFirestore.instance.collection('users').get();
      final emails = {
        for (final d in snap.docs)
          if (((d.data()['email'] as String?) ?? '').contains('@'))
            (d.data()['email'] as String),
      };
      // Also include the currently signed-in user (covers admin with no doc).
      final me = FirebaseAuth.instance.currentUser?.email ?? '';
      if (me.contains('@')) emails.add(me);
      if (emails.isEmpty) return;

      final unitLabel = _unitLabel(unitId);
      final timeFmt   = DateFormat('dd/MM/yyyy HH:mm:ss');
      final subject   = '⚠️ Alerte KOFERT: $title — $unitId';
      final message   = _buildAlertHtml(
          title: title, detail: detail, unitLabel: unitLabel, now: now);

      // Send to all addresses; failures per-address are silently swallowed.
      for (final email in emails) {
        unawaited(_sendEmail(
          toEmail:   email,
          subject:   subject,
          unitLabel: 'KOFERT Energy — Alerte',
          time:      timeFmt.format(now),
          message:   message,
        ));
      }
    } catch (_) {}
  }

  // ── Maintenance: assigned-user email ─────────────────────────────────────

  /// Sends an assignment email to a single user (looked up by UID).
  /// Fire-and-forget — never throws.
  Future<void> sendMaintenanceAssignedEmail({
    required String assignedUid,
    required String taskType,
    required String unitId,
    required String description,
    required String assignedByName,
  }) async {
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(assignedUid)
          .get();
      final email = ((userDoc.data()?['email'] as String?) ?? '').trim();
      if (!email.contains('@')) return;

      final unitLabel = _unitLabel(unitId);
      final now       = DateTime.now();
      final timeFmt   = DateFormat('dd/MM/yyyy HH:mm:ss');
      final typeLabel = _taskTypeLabel(taskType);
      final subject   = '🔧 Tâche de maintenance assignée — KOFERT';
      final message   = _buildMaintenanceAssignedHtml(
        taskType:       typeLabel,
        unitLabel:      unitLabel,
        description:    description,
        assignedByName: assignedByName,
        now:            now,
      );
      unawaited(_sendEmail(
        toEmail:   email,
        subject:   subject,
        unitLabel: 'KOFERT Energy — Maintenance',
        time:      timeFmt.format(now),
        message:   message,
      ));
    } catch (_) {}
  }

  // ── Maintenance: assign-to-all broadcast ─────────────────────────────────

  /// Sends an assignment email to every registered user.
  /// Fire-and-forget — never throws.
  Future<void> sendMaintenanceAssignedToAll({
    required String taskType,
    required String unitId,
    required String description,
    required String assignedByName,
  }) async {
    try {
      final snap   = await FirebaseFirestore.instance.collection('users').get();
      final emails = <String>{
        for (final d in snap.docs)
          if (((d.data()['email'] as String?) ?? '').contains('@'))
            d.data()['email'] as String,
      };
      final me = FirebaseAuth.instance.currentUser?.email ?? '';
      if (me.contains('@')) emails.add(me);
      if (emails.isEmpty) return;

      final unitLabel = _unitLabel(unitId);
      final now       = DateTime.now();
      final timeFmt   = DateFormat('dd/MM/yyyy HH:mm:ss');
      final typeLabel = _taskTypeLabel(taskType);
      final subject   = '🔧 Tâche de maintenance assignée — KOFERT';
      final message   = _buildMaintenanceAssignedHtml(
        taskType:       typeLabel,
        unitLabel:      unitLabel,
        description:    description,
        assignedByName: assignedByName,
        now:            now,
      );
      for (final email in emails) {
        unawaited(_sendEmail(
          toEmail:   email,
          subject:   subject,
          unitLabel: 'KOFERT Energy — Maintenance',
          time:      timeFmt.format(now),
          message:   message,
        ));
      }
    } catch (_) {}
  }

  // ── Maintenance: resolved broadcast ──────────────────────────────────────

  /// Sends a resolved-task email to every registered user.
  /// No throttle — resolution is a deliberate user action.
  Future<void> sendMaintenanceResolvedToAll({
    required String taskType,
    required String unitId,
    required String description,
    required String resolvedByName,
    String resolutionProblem  = '',
    String resolutionSolution = '',
  }) async {
    try {
      final snap   = await FirebaseFirestore.instance.collection('users').get();
      final emails = <String>{
        for (final d in snap.docs)
          if (((d.data()['email'] as String?) ?? '').contains('@'))
            d.data()['email'] as String,
      };
      final me = FirebaseAuth.instance.currentUser?.email ?? '';
      if (me.contains('@')) emails.add(me);
      if (emails.isEmpty) return;

      final unitLabel = _unitLabel(unitId);
      final now       = DateTime.now();
      final timeFmt   = DateFormat('dd/MM/yyyy HH:mm:ss');
      final typeLabel = _taskTypeLabel(taskType);
      final subject   = '✅ Tâche résolue — KOFERT Energy Monitor';
      final message   = _buildMaintenanceResolvedHtml(
        taskType:           typeLabel,
        unitLabel:          unitLabel,
        description:        description,
        resolvedByName:     resolvedByName,
        resolutionProblem:  resolutionProblem,
        resolutionSolution: resolutionSolution,
        now:                now,
      );
      for (final email in emails) {
        unawaited(_sendEmail(
          toEmail:   email,
          subject:   subject,
          unitLabel: 'KOFERT Energy — Maintenance',
          time:      timeFmt.format(now),
          message:   message,
        ));
      }
    } catch (_) {}
  }

  // ── Missed-alert notification on login ────────────────────────────────────

  /// Call this from [_MainScreenState] after the first frame has rendered.
  /// Shows a dismissable SnackBar if alerts fired since the last session.
  /// [onViewAlerts] is called when the user taps "Voir".
  Future<void> checkMissedOnLogin(
    BuildContext context, {
    VoidCallback? onViewAlerts,
  }) async {
    try {
      final prefs      = await SharedPreferences.getInstance();
      final lastCheckMs = prefs.getInt('lastAlertCheckAtMs') ?? 0;
      final now         = DateTime.now();

      // Update the stored timestamp immediately so a crash doesn't re-show.
      await prefs.setInt('lastAlertCheckAtMs', now.millisecondsSinceEpoch);

      // First-ever login — nothing to compare against.
      if (lastCheckMs == 0) return;

      final lastCheck = DateTime.fromMillisecondsSinceEpoch(lastCheckMs);
      // Only show missed alerts if the user was away for at least 2 minutes.
      if (now.difference(lastCheck).inMinutes < 2) return;

      final snap = await FirebaseFirestore.instance
          .collection('alerts')
          .where('timestamp', isGreaterThan: Timestamp.fromDate(lastCheck))
          .orderBy('timestamp', descending: true)
          .limit(50)
          .get();

      if (snap.docs.isEmpty) return;
      if (!context.mounted) return;

      final count      = snap.docs.length;
      final firstTitle =
          (snap.docs.first.data()['title'] as String?) ?? 'Alerte';
      final sinceLabel = DateFormat('dd/MM HH:mm').format(lastCheck);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFFE74C3C),
          duration: const Duration(seconds: 10),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          content: Row(
            children: [
              const Icon(Icons.notifications_active,
                  color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      count == 1
                          ? '1 alerte manquée: $firstTitle'
                          : '$count alertes manquées',
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13),
                    ),
                    Text(
                      'Depuis $sinceLabel',
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
          action: onViewAlerts != null
              ? SnackBarAction(
                  label: 'Voir',
                  textColor: Colors.white,
                  onPressed: onViewAlerts,
                )
              : null,
        ),
      );
    } catch (_) {}
  }

  // ── Internal helpers ──────────────────────────────────────────────────────

  String _taskTypeLabel(String type) {
    switch (type) {
      case 'repair':      return 'Réparation';
      case 'calibration': return 'Calibration';
      default:            return 'Inspection';
    }
  }

  String _buildMaintenanceAssignedHtml({
    required String taskType,
    required String unitLabel,
    required String description,
    required String assignedByName,
    required DateTime now,
  }) {
    final timeFmt = DateFormat('dd/MM/yyyy HH:mm:ss');
    final desc = description.isEmpty ? '—' : description;
    return '''
<div style="font-family:Arial,Helvetica,sans-serif;max-width:600px">
  <!-- Header -->
  <table cellpadding="0" cellspacing="0" width="100%" style="background:#1565C0;border-radius:8px 8px 0 0">
    <tr>
      <td style="padding:18px 20px;vertical-align:middle;width:44px">
        <span style="font-size:22px;line-height:1">&#128296;</span>
      </td>
      <td style="padding:18px 4px 18px 0;vertical-align:middle">
        <div style="color:#fff;font-size:17px;font-weight:700;letter-spacing:0.2px">Tâche de Maintenance Assignée</div>
        <div style="color:rgba(255,255,255,.75);font-size:11px;margin-top:3px">Service Maintenance · KOFERT Energy Monitor</div>
      </td>
      <td align="right" style="padding:18px 20px 18px 0;vertical-align:middle">
        <div style="color:rgba(255,255,255,.5);font-size:10px;white-space:nowrap">&#9889; KOFERT JFC3</div>
      </td>
    </tr>
  </table>
  <!-- Content -->
  <table style="width:100%;border-collapse:collapse;font-size:13px;border:1px solid #c5d9f5;border-top:none">
    <tr style="background:#f0f6ff">
      <td style="padding:12px 16px;border:1px solid #c5d9f5;color:#888;width:40%">Type</td>
      <td style="padding:12px 16px;border:1px solid #c5d9f5;font-weight:600;color:#1565C0">$taskType</td>
    </tr>
    <tr>
      <td style="padding:12px 16px;border:1px solid #c5d9f5;color:#888">Unité</td>
      <td style="padding:12px 16px;border:1px solid #c5d9f5">$unitLabel</td>
    </tr>
    <tr style="background:#f0f6ff">
      <td style="padding:12px 16px;border:1px solid #c5d9f5;color:#888">Description</td>
      <td style="padding:12px 16px;border:1px solid #c5d9f5">$desc</td>
    </tr>
    <tr>
      <td style="padding:12px 16px;border:1px solid #c5d9f5;color:#888">Assigné par</td>
      <td style="padding:12px 16px;border:1px solid #c5d9f5;font-weight:600">$assignedByName</td>
    </tr>
    <tr style="background:#f0f6ff">
      <td style="padding:12px 16px;border:1px solid #c5d9f5;color:#888">Date &amp; heure</td>
      <td style="padding:12px 16px;border:1px solid #c5d9f5">${timeFmt.format(now)}</td>
    </tr>
  </table>
  <!-- Footer -->
  <div style="background:#eef4ff;border:1px solid #c5d9f5;border-top:none;border-radius:0 0 8px 8px;padding:12px 16px;font-size:11px;color:#444;text-align:center">
    Vous avez été assigné(e) à cette tâche de maintenance. Connectez-vous pour la consulter et la valider.<br>
    <a href="https://ocp-energy-monitor.web.app" style="color:#1565C0">ocp-energy-monitor.web.app</a>
  </div>
</div>''';
  }

  String _buildMaintenanceResolvedHtml({
    required String taskType,
    required String unitLabel,
    required String description,
    required String resolvedByName,
    required DateTime now,
    String resolutionProblem  = '',
    String resolutionSolution = '',
  }) {
    final timeFmt  = DateFormat('dd/MM/yyyy HH:mm:ss');
    final desc     = description.isEmpty        ? '—' : description;
    final problem  = resolutionProblem.isEmpty  ? '—' : resolutionProblem;
    final solution = resolutionSolution.isEmpty ? '—' : resolutionSolution;

    final hasReport = resolutionProblem.isNotEmpty || resolutionSolution.isNotEmpty;
    final reportSection = hasReport ? '''
  <!-- Report section -->
  <div style="margin-top:0;border:1px solid #b8e6bc;border-top:none;padding:0">
    <div style="background:#d4edda;padding:8px 16px;font-size:11px;font-weight:700;
                color:#155724;letter-spacing:0.5px;text-transform:uppercase">Rapport de résolution</div>
    <table style="width:100%;border-collapse:collapse;font-size:13px">
      <tr>
        <td style="padding:10px 16px;border:1px solid #b8e6bc;border-left:3px solid #e67e22;
                   background:#fff8f0;color:#666;width:40%;vertical-align:top">Problème rencontré</td>
        <td style="padding:10px 16px;border:1px solid #b8e6bc;background:#fff8f0;
                   vertical-align:top;white-space:pre-wrap">$problem</td>
      </tr>
      <tr>
        <td style="padding:10px 16px;border:1px solid #b8e6bc;border-left:3px solid #2E7D32;
                   background:#f0fff4;color:#666;vertical-align:top">Solution appliquée</td>
        <td style="padding:10px 16px;border:1px solid #b8e6bc;background:#f0fff4;
                   vertical-align:top;white-space:pre-wrap">$solution</td>
      </tr>
    </table>
  </div>''' : '';

    return '''
<div style="font-family:Arial,Helvetica,sans-serif;max-width:600px">
  <!-- Header -->
  <table cellpadding="0" cellspacing="0" width="100%" style="background:#2E7D32;border-radius:8px 8px 0 0">
    <tr>
      <td style="padding:18px 20px;vertical-align:middle;width:44px">
        <span style="font-size:22px;line-height:1">&#9989;</span>
      </td>
      <td style="padding:18px 4px 18px 0;vertical-align:middle">
        <div style="color:#fff;font-size:17px;font-weight:700;letter-spacing:0.2px">Tâche de Maintenance Résolue</div>
        <div style="color:rgba(255,255,255,.75);font-size:11px;margin-top:3px">Service Maintenance · KOFERT Energy Monitor</div>
      </td>
      <td align="right" style="padding:18px 20px 18px 0;vertical-align:middle">
        <div style="color:rgba(255,255,255,.5);font-size:10px;white-space:nowrap">&#9889; KOFERT JFC3</div>
      </td>
    </tr>
  </table>
  <!-- Meta table -->
  <table style="width:100%;border-collapse:collapse;font-size:13px;border:1px solid #b8e6bc;border-top:none">
    <tr style="background:#f0fff4">
      <td style="padding:12px 16px;border:1px solid #b8e6bc;color:#888;width:40%">Type</td>
      <td style="padding:12px 16px;border:1px solid #b8e6bc;font-weight:600;color:#2E7D32">$taskType</td>
    </tr>
    <tr>
      <td style="padding:12px 16px;border:1px solid #b8e6bc;color:#888">Unité</td>
      <td style="padding:12px 16px;border:1px solid #b8e6bc">$unitLabel</td>
    </tr>
    <tr style="background:#f0fff4">
      <td style="padding:12px 16px;border:1px solid #b8e6bc;color:#888">Description</td>
      <td style="padding:12px 16px;border:1px solid #b8e6bc">$desc</td>
    </tr>
    <tr>
      <td style="padding:12px 16px;border:1px solid #b8e6bc;color:#888">Résolu par</td>
      <td style="padding:12px 16px;border:1px solid #b8e6bc;font-weight:600">$resolvedByName</td>
    </tr>
    <tr style="background:#f0fff4">
      <td style="padding:12px 16px;border:1px solid #b8e6bc;color:#888">Date &amp; heure</td>
      <td style="padding:12px 16px;border:1px solid #b8e6bc">${timeFmt.format(now)}</td>
    </tr>
  </table>
$reportSection
  <!-- Footer -->
  <div style="background:#e8f5e9;border:1px solid #b8e6bc;border-top:none;border-radius:0 0 8px 8px;
              padding:12px 16px;font-size:11px;color:#2e5d30;text-align:center">
    &#127881; La tâche de maintenance a été clôturée avec succès. Consultez l'historique complet sur<br>
    <a href="https://ocp-energy-monitor.web.app" style="color:#2E7D32">ocp-energy-monitor.web.app</a>
  </div>
</div>''';
  }

  String _unitLabel(String unitId) {
    switch (unitId) {
      case 'KOFERT_Unit_1': return 'Lampe (220V AC)';
      case 'KOFERT_Unit_2': return 'Ventilateur (5V DC)';
      case 'KOFERT_Unit_3': return 'Pompe (5V DC)';
      default: return unitId;
    }
  }

  String _buildAlertHtml({
    required String title,
    required String detail,
    required String unitLabel,
    required DateTime now,
  }) {
    final timeFmt = DateFormat('dd/MM/yyyy HH:mm:ss');
    return '''
<div style="font-family:Arial,Helvetica,sans-serif;max-width:600px">
  <!-- Header -->
  <table cellpadding="0" cellspacing="0" width="100%" style="background:#C62828;border-radius:8px 8px 0 0">
    <tr>
      <td style="padding:18px 20px;vertical-align:middle;width:44px">
        <span style="font-size:22px;line-height:1">&#9888;&#65039;</span>
      </td>
      <td style="padding:18px 4px 18px 0;vertical-align:middle">
        <div style="color:#fff;font-size:17px;font-weight:700;letter-spacing:0.2px">Alerte Détectée</div>
        <div style="color:rgba(255,255,255,.75);font-size:11px;margin-top:3px">Surveillance temps réel · KOFERT Energy Monitor</div>
      </td>
      <td align="right" style="padding:18px 20px 18px 0;vertical-align:middle">
        <div style="color:rgba(255,255,255,.5);font-size:10px;white-space:nowrap">&#9889; KOFERT JFC3</div>
      </td>
    </tr>
  </table>
  <!-- Content -->
  <table style="width:100%;border-collapse:collapse;font-size:13px;border:1px solid #fcc;border-top:none">
    <tr style="background:#fff5f5">
      <td style="padding:12px 16px;border:1px solid #fcc;color:#888;width:40%">Type d'alerte</td>
      <td style="padding:12px 16px;border:1px solid #fcc;font-weight:600;color:#C62828">$title</td>
    </tr>
    <tr>
      <td style="padding:12px 16px;border:1px solid #fcc;color:#888">Valeur mesurée</td>
      <td style="padding:12px 16px;border:1px solid #fcc;font-weight:600">$detail</td>
    </tr>
    <tr style="background:#fff5f5">
      <td style="padding:12px 16px;border:1px solid #fcc;color:#888">Unité</td>
      <td style="padding:12px 16px;border:1px solid #fcc">$unitLabel</td>
    </tr>
    <tr>
      <td style="padding:12px 16px;border:1px solid #fcc;color:#888">Date &amp; heure</td>
      <td style="padding:12px 16px;border:1px solid #fcc">${timeFmt.format(now)}</td>
    </tr>
  </table>
  <!-- Action callout -->
  <div style="background:#ffebee;border:1px solid #fcc;border-top:none;padding:11px 14px;font-size:12px;color:#7b1d1d">
    &#128680; Agissez rapidement pour éviter tout dysfonctionnement ou risque de panne.
  </div>
  <!-- Footer -->
  <div style="background:#fff5f5;border:1px solid #fcc;border-top:none;border-radius:0 0 8px 8px;padding:10px 14px;font-size:11px;color:#888;text-align:center">
    Consultez les détails et l'historique des alertes sur<br>
    <a href="https://ocp-energy-monitor.web.app" style="color:#C62828">ocp-energy-monitor.web.app</a>
  </div>
</div>''';
  }

  Future<void> _sendEmail({
    required String toEmail,
    required String subject,
    required String unitLabel,
    required String time,
    required String message,
  }) async {
    try {
      await http.post(
        Uri.parse('https://api.emailjs.com/api/v1.0/email/send'),
        headers: {
          'Content-Type': 'application/json',
          'origin': html.window.location.href,
        },
        body: jsonEncode({
          'service_id':  _serviceId,
          'template_id': _templateId,
          'user_id':     _publicKey,
          'template_params': {
            'name':     unitLabel,
            'time':     time,
            'to_email': toEmail,
            'subject':  subject,
            'message':  message,
          },
        }),
      );
    } catch (_) {}
  }
}
