import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme/app_colors.dart';
import '../models/alert_entry.dart';
import '../l10n/app_strings.dart';
import '../main.dart' show alertLogNotifier;
import '../services/firestore_log_service.dart';

class AlertHistoryScreen extends StatefulWidget {
  const AlertHistoryScreen({super.key});

  @override
  State<AlertHistoryScreen> createState() => _AlertHistoryScreenState();
}

class _AlertHistoryScreenState extends State<AlertHistoryScreen> {
  AppColors get _c => AppColors.of(context);

  // Persisted alerts fetched from Firestore (GetAlertHistory).
  List<AlertEntry> _persistedAlerts = [];
  bool _loadingFirestore = false;

  @override
  void initState() {
    super.initState();
    alertLogNotifier.addListener(_rebuild);
    _loadFromFirestore();
  }

  @override
  void dispose() {
    alertLogNotifier.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  /// Fetch persisted alerts from the Firestore `alerts` collection.
  /// Converts each document back to an [AlertEntry] for unified display.
  Future<void> _loadFromFirestore() async {
    if (!mounted) return;
    setState(() => _loadingFirestore = true);
    final raw = await FirestoreLogService.instance.getAlerts(limit: 200);
    if (!mounted) return;
    final entries = raw.map((m) {
      final ts = (m['timestamp'] as Timestamp?)?.toDate().toLocal() ??
          DateTime.now();
      final colorValue = (m['colorValue'] as int?) ?? 0xFFE74C3C;
      return AlertEntry(
        title: (m['title'] as String?) ?? '',
        detail: (m['detail'] as String?) ?? '',
        color: Color(colorValue),
        time: ts,
        unitId: (m['unitId'] as String?) ?? '',
      );
    }).toList();
    setState(() {
      _persistedAlerts = entries;
      _loadingFirestore = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Merge in-memory session alerts with Firestore persisted alerts.
    // Deduplicate by (title + unitId + rounded-minute timestamp).
    final sessionAlerts = List<AlertEntry>.from(alertLogNotifier.value);
    final seen = <String>{};
    final merged = <AlertEntry>[];
    for (final e in [...sessionAlerts, ..._persistedAlerts]) {
      final key =
          '${e.title}|${e.unitId}|${e.time.year}-${e.time.month}-${e.time.day}-${e.time.hour}-${e.time.minute}';
      if (seen.add(key)) merged.add(e);
    }
    merged.sort((a, b) => b.time.compareTo(a.time));

    return Scaffold(
      backgroundColor: _c.bg,
      body: Column(
        children: [
          // ── Header ───────────────────────────────────────────────────────
          Container(
            color: _c.card,
            padding: const EdgeInsets.fromLTRB(16, 16, 8, 12),
            child: Row(
              children: [
                const Icon(Icons.notifications_outlined,
                    color: Color(0xFFFFFFFF), size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(AppStrings.t('alert_history'),
                      style: const TextStyle(
                          color: Color(0xFFFFFFFF),
                          fontWeight: FontWeight.bold,
                          fontSize: 17),
                      overflow: TextOverflow.ellipsis),
                ),
                Text('${merged.length}',
                    style: TextStyle(color: _c.textSec, fontSize: 13)),
                if (_loadingFirestore)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else
                  IconButton(
                    icon: const Icon(Icons.refresh, size: 18),
                    color: _c.textSec,
                    tooltip: 'Rafraîchir',
                    padding: const EdgeInsets.all(6),
                    constraints: const BoxConstraints(),
                    onPressed: _loadFromFirestore,
                  ),
                if (sessionAlerts.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                    color: const Color(0xFFE74C3C),
                    tooltip: AppStrings.t('clear_all'),
                    padding: const EdgeInsets.all(6),
                    constraints: const BoxConstraints(),
                    onPressed: () =>
                        setState(() => alertLogNotifier.value = []),
                  ),
              ],
            ),
          ),

          // ── Body ─────────────────────────────────────────────────────────
          Expanded(
            child: merged.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle_outline,
                            color: _c.textSec, size: 52),
                        const SizedBox(height: 16),
                        Text(AppStrings.t('no_alerts'),
                            style: TextStyle(
                                color: _c.textSec, fontSize: 15)),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: merged.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 4),
                    itemBuilder: (context, i) => _AlertRow(entry: merged[i]),
                  ),
          ),
        ],
      ),
    );
  }
}

class _AlertRow extends StatelessWidget {
  final AlertEntry entry;
  const _AlertRow({required this.entry});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final t = entry.time;
    final dateStr =
        '${t.day.toString().padLeft(2, '0')}/${t.month.toString().padLeft(2, '0')} '
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';
    return Container(
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(10),
        border: Border(
          left: BorderSide(color: entry.color, width: 3),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.title,
                    style: TextStyle(
                        color: entry.color,
                        fontWeight: FontWeight.w600,
                        fontSize: 13)),
                const SizedBox(height: 2),
                Text(entry.detail,
                    style:
                        TextStyle(color: c.textSec, fontSize: 12)),
                const SizedBox(height: 2),
                Text(entry.unitId,
                    style: TextStyle(
                        color: c.textSec, fontSize: 10)),
              ],
            ),
          ),
          Text(dateStr,
              style:
                  TextStyle(color: c.textSec, fontSize: 11)),
        ],
      ),
    );
  }
}