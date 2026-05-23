import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../models/alert_entry.dart';
import '../l10n/app_strings.dart';
import '../main.dart' show alertLogNotifier;

class AlertHistoryScreen extends StatefulWidget {
  const AlertHistoryScreen({super.key});

  @override
  State<AlertHistoryScreen> createState() => _AlertHistoryScreenState();
}

class _AlertHistoryScreenState extends State<AlertHistoryScreen> {
  AppColors get _c => AppColors.of(context);
  @override
  void initState() {
    super.initState();
    alertLogNotifier.addListener(_rebuild);
  }

  @override
  void dispose() {
    alertLogNotifier.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final alerts = List<AlertEntry>.from(alertLogNotifier.value.reversed);
    return Scaffold(
      backgroundColor: _c.bg,
      body: Column(
        children: [
          // ── Header ───────────────────────────────────────────────────────
          Container(
            color: _c.card,
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            child: Row(
              children: [
                const Icon(Icons.notifications_outlined,
                    color: Color(0xFFFFFFFF), size: 20),
                const SizedBox(width: 10),
                Text(AppStrings.t('alert_history'),
                    style: const TextStyle(
                        color: Color(0xFFFFFFFF),
                        fontWeight: FontWeight.bold,
                        fontSize: 18)),
                const Spacer(),
                Text('${alerts.length} entrée(s)',
                    style: TextStyle(color: _c.textSec, fontSize: 13)),
                const SizedBox(width: 12),
                if (alerts.isNotEmpty)
                  TextButton.icon(
                    icon: const Icon(Icons.delete_sweep_outlined, size: 16),
                    label: Text(AppStrings.t('clear_all')),
                    style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFFE74C3C)),
                    onPressed: () =>
                        setState(() => alertLogNotifier.value = []),
                  ),
              ],
            ),
          ),

          // ── Body ─────────────────────────────────────────────────────────
          Expanded(
            child: alerts.isEmpty
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
                    itemCount: alerts.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 4),
                    itemBuilder: (context, i) => _AlertRow(entry: alerts[i]),
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