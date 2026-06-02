import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../theme/app_colors.dart';
import '../main.dart' show kTeal, kOrange, roleNotifier;
import '../l10n/app_strings.dart';

class UserLogsScreen extends StatefulWidget {
  const UserLogsScreen({super.key});

  @override
  State<UserLogsScreen> createState() => _UserLogsScreenState();
}

class _UserLogsScreenState extends State<UserLogsScreen> {
  AppColors get _c => AppColors.of(context);

  static const _pageSize = 50;
  final _db = FirebaseFirestore.instance;

  String _actionFilter = 'all';
  String _searchQuery  = '';
  final _searchCtrl    = TextEditingController();
  bool  _loading       = true;
  List<Map<String, dynamic>> _logs = [];
  DocumentSnapshot? _lastDoc;
  bool _hasMore = true;
  Timer? _refreshTimer;

  static const _actionIcons = <String, IconData>{
    'login':           Icons.login_rounded,
    'logout':          Icons.logout_rounded,
    'settings_change': Icons.settings_rounded,
    'role_change':     Icons.admin_panel_settings_rounded,
    'alert_created':   Icons.notifications_active_rounded,
    'maintenance':     Icons.build_circle_rounded,
    'report_sent':     Icons.send_rounded,
    'data_export':     Icons.download_rounded,
    'other':           Icons.info_outline_rounded,
  };

  static const _actionColors = <String, Color>{
    'login':           Color(0xFF2ECC71),
    'logout':          Color(0xFF95A5A6),
    'settings_change': Color(0xFFF5A623),
    'role_change':     Color(0xFFE74C3C),
    'alert_created':   Color(0xFFE74C3C),
    'maintenance':     Color(0xFF4ECDC4),
    'report_sent':     Color(0xFF3498DB),
    'data_export':     Color(0xFF9B59B6),
    'other':           Color(0xFF7F8C8D),
  };

  @override
  void initState() {
    super.initState();
    _loadLogs();
    // Auto-refresh every 30 seconds
    _refreshTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted) _loadLogs(reset: true);
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadLogs({bool reset = false}) async {
    if (reset) {
      setState(() { _logs.clear(); _lastDoc = null; _hasMore = true; });
    }
    if (!_hasMore) return;
    setState(() => _loading = true);
    try {
      Query q = _db
          .collection('user_logs')
          .orderBy('timestamp', descending: true)
          .limit(_pageSize);
      if (_actionFilter != 'all') {
        q = q.where('action', isEqualTo: _actionFilter);
      }
      if (_lastDoc != null) q = q.startAfterDocument(_lastDoc!);
      final snap = await q.get();
      final newDocs = snap.docs.map((d) => {'id': d.id, ...d.data() as Map<String, dynamic>}).toList();
      if (!mounted) return;
      setState(() {
        _logs = reset ? newDocs : [..._logs, ...newDocs];
        _lastDoc = snap.docs.isNotEmpty ? snap.docs.last : _lastDoc;
        _hasMore = snap.docs.length == _pageSize;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _filtered {
    final q = _searchQuery.toLowerCase();
    if (q.isEmpty) return _logs;
    return _logs.where((l) {
      final user   = (l['userEmail'] as String? ?? '').toLowerCase();
      final name   = (l['userName']  as String? ?? '').toLowerCase();
      final detail = (l['detail']    as String? ?? '').toLowerCase();
      return user.contains(q) || name.contains(q) || detail.contains(q);
    }).toList();
  }

  String _fmtTime(dynamic ts) {
    if (ts == null) return '—';
    final dt = ts is Timestamp ? ts.toDate().toLocal() : DateTime.now();
    return DateFormat('dd/MM/yyyy HH:mm:ss').format(dt);
  }

  IconData _iconFor(String action) =>
      _actionIcons[action] ?? _actionIcons['other']!;
  Color _colorFor(String action) =>
      _actionColors[action] ?? _actionColors['other']!;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: roleNotifier,
      builder: (_, role, __) {
        if (role != 'admin' && role != 'moderator') {
          return Scaffold(
            backgroundColor: _c.bg,
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.lock_outline_rounded, size: 64, color: _c.textSec),
                  const SizedBox(height: 16),
                  Text(AppStrings.t('access_denied'),
                      style: TextStyle(color: _c.textSec, fontSize: 16)),
                ],
              ),
            ),
          );
        }
        return Scaffold(
          backgroundColor: _c.bg,
          body: LayoutBuilder(
            builder: (context, bc) {
              final mobile = bc.maxWidth < 600;
              final hPad = mobile ? 14.0 : 28.0;
              return Padding(
                padding: EdgeInsets.fromLTRB(hPad, mobile ? 16 : 28, hPad, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Header ─────────────────────────────────────────
                    Row(
                      children: [
                        Icon(Icons.manage_history_rounded, color: kTeal, size: mobile ? 22 : 26),
                        const SizedBox(width: 10),
                        Text(AppStrings.t('user_logs'),
                            style: TextStyle(
                                color: _c.textPri,
                                fontSize: mobile ? 18 : 22,
                                fontWeight: FontWeight.bold)),
                        const Spacer(),
                        IconButton(
                          tooltip: AppStrings.t('refresh'),
                          icon: Icon(Icons.refresh_rounded, color: _c.textSec),
                          onPressed: () => _loadLogs(reset: true),
                        ),
                      ],
                    ),
                    SizedBox(height: mobile ? 14 : 20),

                    // ── Search + filter row ─────────────────────────────
                    if (mobile) ...[
                      // Stack search above filter on narrow screens
                      TextField(
                        controller: _searchCtrl,
                        style: TextStyle(color: _c.textPri, fontSize: 13),
                        decoration: InputDecoration(
                          hintText: AppStrings.t('search_logs'),
                          hintStyle: TextStyle(color: _c.textSec, fontSize: 13),
                          prefixIcon: Icon(Icons.search, color: _c.textSec, size: 18),
                          filled: true,
                          fillColor: _c.card,
                          contentPadding: const EdgeInsets.symmetric(vertical: 10),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        onChanged: (v) => setState(() => _searchQuery = v),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: _c.card,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            isExpanded: true,
                            value: _actionFilter,
                            dropdownColor: _c.dropdownBg,
                            style: TextStyle(color: _c.textPri, fontSize: 13),
                            items: [
                              'all', 'login', 'logout', 'settings_change',
                              'role_change', 'alert_created', 'maintenance',
                              'report_sent', 'data_export', 'other',
                            ].map((a) => DropdownMenuItem(
                              value: a,
                              child: Text(AppStrings.t('log_action_$a')),
                            )).toList(),
                            onChanged: (v) {
                              if (v == null) return;
                              setState(() => _actionFilter = v);
                              _loadLogs(reset: true);
                            },
                          ),
                        ),
                      ),
                    ] else ...[
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _searchCtrl,
                              style: TextStyle(color: _c.textPri, fontSize: 13),
                              decoration: InputDecoration(
                                hintText: AppStrings.t('search_logs'),
                                hintStyle: TextStyle(color: _c.textSec, fontSize: 13),
                                prefixIcon: Icon(Icons.search, color: _c.textSec, size: 18),
                                filled: true,
                                fillColor: _c.card,
                                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                              onChanged: (v) => setState(() => _searchQuery = v),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: _c.card,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: _actionFilter,
                                dropdownColor: _c.dropdownBg,
                                style: TextStyle(color: _c.textPri, fontSize: 13),
                                items: [
                                  'all', 'login', 'logout', 'settings_change',
                                  'role_change', 'alert_created', 'maintenance',
                                  'report_sent', 'data_export', 'other',
                                ].map((a) => DropdownMenuItem(
                                  value: a,
                                  child: Text(AppStrings.t('log_action_$a')),
                                )).toList(),
                                onChanged: (v) {
                                  if (v == null) return;
                                  setState(() => _actionFilter = v);
                                  _loadLogs(reset: true);
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 16),

                    // ── Stats row (wraps on mobile) ──────────────────────
                    _StatsRow(logs: _filtered, mobile: mobile),
                    const SizedBox(height: 16),

                    // ── Table header (desktop only) ──────────────────────
                    if (!mobile) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: _c.card,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                        ),
                        child: Row(
                          children: [
                            const SizedBox(width: 36),
                            Expanded(flex: 3, child: Text(AppStrings.t('log_user'),
                                style: TextStyle(color: _c.textSec, fontSize: 12, fontWeight: FontWeight.w600))),
                            Expanded(flex: 2, child: Text(AppStrings.t('log_action'),
                                style: TextStyle(color: _c.textSec, fontSize: 12, fontWeight: FontWeight.w600))),
                            Expanded(flex: 4, child: Text(AppStrings.t('log_detail'),
                                style: TextStyle(color: _c.textSec, fontSize: 12, fontWeight: FontWeight.w600))),
                            Expanded(flex: 2, child: Text(AppStrings.t('log_time'),
                                style: TextStyle(color: _c.textSec, fontSize: 12, fontWeight: FontWeight.w600))),
                          ],
                        ),
                      ),
                      Divider(height: 1, color: _c.divider),
                    ],

                    // ── List ────────────────────────────────────────────
                    Expanded(
                      child: _loading && _logs.isEmpty
                          ? Center(child: CircularProgressIndicator(color: kTeal))
                          : _filtered.isEmpty
                              ? Center(child: Text(AppStrings.t('no_logs_found'),
                                  style: TextStyle(color: _c.textSec)))
                              : ListView.separated(
                                  itemCount: _filtered.length + (_hasMore ? 1 : 0),
                                  separatorBuilder: (_, __) =>
                                      Divider(height: 1, color: _c.divider),
                                  itemBuilder: (ctx, i) {
                                    if (i == _filtered.length) {
                                      return Padding(
                                        padding: const EdgeInsets.all(16),
                                        child: Center(
                                          child: TextButton(
                                            onPressed: _loadLogs,
                                            child: Text(AppStrings.t('load_more'),
                                                style: TextStyle(color: kTeal)),
                                          ),
                                        ),
                                      );
                                    }
                                    final log = _filtered[i];
                                    final action = log['action'] as String? ?? 'other';
                                    final color = _colorFor(action);
                                    final icon  = _iconFor(action);

                                    if (mobile) {
                                      // ── Mobile: card layout ──────────
                                      return Container(
                                        color: _c.card,
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 14, vertical: 12),
                                        child: Row(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Container(
                                              width: 32, height: 32,
                                              decoration: BoxDecoration(
                                                color: color.withValues(alpha: 0.15),
                                                shape: BoxShape.circle,
                                              ),
                                              child: Icon(icon, size: 16, color: color),
                                            ),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Row(
                                                    children: [
                                                      Expanded(
                                                        child: Column(
                                                          crossAxisAlignment: CrossAxisAlignment.start,
                                                          mainAxisSize: MainAxisSize.min,
                                                          children: [
                                                            if ((log['userName'] as String? ?? '').isNotEmpty)
                                                              Text(
                                                                log['userName'] as String,
                                                                style: TextStyle(color: _c.textPri, fontSize: 13, fontWeight: FontWeight.w600),
                                                                overflow: TextOverflow.ellipsis,
                                                              ),
                                                            Text(
                                                              log['userEmail'] as String? ?? '—',
                                                              style: TextStyle(
                                                                color: (log['userName'] as String? ?? '').isNotEmpty ? _c.textSec : _c.textPri,
                                                                fontSize: (log['userName'] as String? ?? '').isNotEmpty ? 11 : 13,
                                                                fontWeight: (log['userName'] as String? ?? '').isNotEmpty ? FontWeight.normal : FontWeight.w600,
                                                              ),
                                                              overflow: TextOverflow.ellipsis,
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                      const SizedBox(width: 6),
                                                      Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                        decoration: BoxDecoration(
                                                          color: color.withValues(alpha: 0.15),
                                                          borderRadius: BorderRadius.circular(20),
                                                        ),
                                                        child: Text(AppStrings.t('log_action_$action'),
                                                            style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600)),
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Text(log['userRole'] as String? ?? '',
                                                      style: TextStyle(color: _c.textSec, fontSize: 11)),
                                                  if ((log['detail'] as String? ?? '').isNotEmpty) ...[
                                                    const SizedBox(height: 4),
                                                    Text(log['detail'] as String? ?? '',
                                                        style: TextStyle(color: _c.textSec, fontSize: 12),
                                                        maxLines: 2,
                                                        overflow: TextOverflow.ellipsis),
                                                  ],
                                                  const SizedBox(height: 4),
                                                  Text(_fmtTime(log['timestamp']),
                                                      style: TextStyle(color: _c.textSec, fontSize: 10)),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    }

                                    // ── Desktop: table row ───────────
                                    return Container(
                                      color: _c.card,
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 16, vertical: 12),
                                      child: Row(
                                        children: [
                                          Container(
                                            width: 28, height: 28,
                                            decoration: BoxDecoration(
                                              color: color.withValues(alpha: 0.15),
                                              shape: BoxShape.circle,
                                            ),
                                            child: Icon(icon, size: 15, color: color),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            flex: 3,
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                if ((log['userName'] as String? ?? '').isNotEmpty)
                                                  Text(log['userName'] as String,
                                                      style: TextStyle(color: _c.textPri, fontSize: 13, fontWeight: FontWeight.w600),
                                                      overflow: TextOverflow.ellipsis),
                                                Text(log['userEmail'] as String? ?? '—',
                                                    style: TextStyle(
                                                      color: (log['userName'] as String? ?? '').isNotEmpty ? _c.textSec : _c.textPri,
                                                      fontSize: 12,
                                                    ),
                                                    overflow: TextOverflow.ellipsis),
                                                Text(log['userRole'] as String? ?? '',
                                                    style: TextStyle(color: _c.textSec, fontSize: 11)),
                                              ],
                                            ),
                                          ),
                                          Expanded(
                                            flex: 2,
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                              decoration: BoxDecoration(
                                                color: color.withValues(alpha: 0.15),
                                                borderRadius: BorderRadius.circular(20),
                                              ),
                                              child: Text(AppStrings.t('log_action_$action'),
                                                  style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
                                                  textAlign: TextAlign.center,
                                                  overflow: TextOverflow.ellipsis),
                                            ),
                                          ),
                                          Expanded(
                                            flex: 4,
                                            child: Text(log['detail'] as String? ?? '—',
                                                style: TextStyle(color: _c.textSec, fontSize: 12),
                                                overflow: TextOverflow.ellipsis,
                                                maxLines: 2),
                                          ),
                                          Expanded(
                                            flex: 2,
                                            child: Text(_fmtTime(log['timestamp']),
                                                style: TextStyle(color: _c.textSec, fontSize: 11)),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}

// ── Stats summary row ─────────────────────────────────────────────────────────
class _StatsRow extends StatelessWidget {
  final List<Map<String, dynamic>> logs;
  final bool mobile;
  const _StatsRow({required this.logs, this.mobile = false});

  @override
  Widget build(BuildContext context) {
    final logins   = logs.where((l) => l['action'] == 'login').length;
    final logouts  = logs.where((l) => l['action'] == 'logout').length;
    final changes  = logs.where((l) => l['action'] == 'settings_change' || l['action'] == 'role_change').length;
    final alerts   = logs.where((l) => l['action'] == 'alert_created').length;
    final chips = [
      _StatChip(label: AppStrings.t('log_action_login'),  value: logins,  color: const Color(0xFF2ECC71), icon: Icons.login_rounded),
      _StatChip(label: AppStrings.t('log_action_logout'), value: logouts, color: const Color(0xFF95A5A6), icon: Icons.logout_rounded),
      _StatChip(label: AppStrings.t('log_changes'),       value: changes, color: kOrange,                icon: Icons.edit_rounded),
      _StatChip(label: AppStrings.t('log_action_alert_created'), value: alerts, color: const Color(0xFFE74C3C), icon: Icons.notifications_active_rounded),
      _StatChip(label: AppStrings.t('log_total'),         value: logs.length, color: kTeal,             icon: Icons.list_alt_rounded),
    ];
    if (mobile) {
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: chips,
      );
    }
    return Row(
      children: chips
          .expand((c) => [c, const SizedBox(width: 10)])
          .toList()
          ..removeLast(),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final int value;
  final Color color;
  final IconData icon;
  const _StatChip({required this.label, required this.value, required this.color, required this.icon});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('$value', style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 15)),
              Text(label, style: TextStyle(color: c.textSec, fontSize: 10)),
            ],
          ),
        ],
      ),
    );
  }
}
