import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../main.dart' show kTeal, kOrange, alertLogNotifier, roleNotifier;
import '../models/alert_entry.dart';
import '../l10n/app_strings.dart';

class MaintenanceScreen extends StatefulWidget {
  const MaintenanceScreen({super.key});

  @override
  State<MaintenanceScreen> createState() => _MaintenanceScreenState();
}

class _MaintenanceScreenState extends State<MaintenanceScreen> {
  AppColors get _c => AppColors.of(context);
  String _selectedUnit = 'KOFERT_Unit_1';

  static const _units = ['KOFERT_Unit_1', 'KOFERT_Unit_2', 'KOFERT_Unit_3'];
  static const _unitLabels = {
    'KOFERT_Unit_1': 'Unit 1 – Lampe',
    'KOFERT_Unit_2': 'Unit 2 – Ventilateur',
    'KOFERT_Unit_3': 'Unit 3 – Pompe',
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _c.bg,
      floatingActionButton: ValueListenableBuilder<String>(
        valueListenable: roleNotifier,
        builder: (_, role, child) =>
            (role == 'viewer' || role == 'observer')
            ? const SizedBox.shrink()
            : FloatingActionButton.extended(
                onPressed: _showAddEntryDialog,
                backgroundColor: kTeal,
                foregroundColor: Colors.black87,
                icon: const Icon(Icons.add),
                label: Text(AppStrings.t('add_entry')),
              ),
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(28, 28, 28, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header row ──────────────────────────────────────
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: kTeal.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.build_circle, color: kTeal, size: 24),
                ),
                const SizedBox(width: 14),
                Text(
                  AppStrings.t('maintenance'),
                  style: TextStyle(
                      color: _c.textPri,
                      fontSize: 22,
                      fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 24),
                // Unit filter
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  decoration: BoxDecoration(
                    color: _c.card,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedUnit,
                      dropdownColor: _c.card,
                      style: TextStyle(color: _c.textPri, fontSize: 13),
                      icon:
                          Icon(Icons.expand_more, color: _c.textSec, size: 18),
                      items: _units
                          .map((u) => DropdownMenuItem(
                                value: u,
                                child: Text(_unitLabels[u]!),
                              ))
                          .toList(),
                      onChanged: (v) {
                        if (v != null) setState(() => _selectedUnit = v);
                      },
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            // ── Log list ────────────────────────────────────────
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('maintenance_logs')
                    .where('unitId', isEqualTo: _selectedUnit)
                    .orderBy('timestamp', descending: true)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                        child: CircularProgressIndicator(color: kTeal));
                  }
                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.build_circle_outlined,
                              size: 56, color: _c.textSec),
                          const SizedBox(height: 14),
                          Text(AppStrings.t('no_logs'),
                              style:
                                  TextStyle(color: _c.textSec, fontSize: 14)),
                        ],
                      ),
                    );
                  }
                  final docs = snapshot.data!.docs;
                  return ListView.builder(
                    itemCount: docs.length,
                    itemBuilder: (ctx, i) {
                      final d = docs[i].data() as Map<String, dynamic>;
                      final ts = (d['timestamp'] as Timestamp?)?.toDate() ??
                          DateTime.now();
                      final type = d['type'] as String? ?? 'inspection';
                      final tech = d['technicianName'] as String? ?? '';
                      final desc = d['description'] as String? ?? '';
                      final typeColor = type == 'repair'
                          ? const Color(0xFFE74C3C)
                          : type == 'calibration'
                              ? kOrange
                              : kTeal;
                      final typeIcon = type == 'repair'
                          ? Icons.build
                          : type == 'calibration'
                              ? Icons.tune
                              : Icons.search;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: _c.card,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                              color: typeColor.withValues(alpha: 0.25)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                color: typeColor.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(typeIcon,
                                  color: typeColor, size: 20),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 10, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: typeColor.withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(20),
                                        ),
                                        child: Text(
                                          AppStrings.t(type),
                                          style: TextStyle(
                                              color: typeColor,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600),
                                        ),
                                      ),
                                      const Spacer(),
                                      Text(
                                        DateFormat('dd/MM/yyyy HH:mm')
                                            .format(ts),
                                        style: TextStyle(
                                            color: _c.textSec, fontSize: 12),
                                      ),
                                    ],
                                  ),
                                  if (desc.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    Text(desc,
                                        style: TextStyle(
                                            color: _c.textPri, fontSize: 13)),
                                  ],
                                  if (tech.isNotEmpty) ...[
                                    const SizedBox(height: 6),
                                    Row(children: [
                                      Icon(Icons.person_outline,
                                          size: 13, color: _c.textSec),
                                      const SizedBox(width: 4),
                                      Text(tech,
                                          style: TextStyle(
                                              color: _c.textSec,
                                              fontSize: 12)),
                                    ]),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddEntryDialog() {
    final descCtrl = TextEditingController();
    final techCtrl = TextEditingController();
    String selectedType = 'inspection';
    String selectedUnit = _selectedUnit;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          backgroundColor: _c.card,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(Icons.build_circle, color: kTeal, size: 20),
              const SizedBox(width: 10),
              Text(AppStrings.t('add_entry'),
                  style: TextStyle(color: _c.textPri, fontSize: 16)),
            ],
          ),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Unit selector
                Text('Unité',
                    style: TextStyle(color: _c.textSec, fontSize: 12)),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: _c.cardAlt,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: _c.divider.withValues(alpha: 0.3)),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: selectedUnit,
                      isExpanded: true,
                      dropdownColor: _c.card,
                      style: TextStyle(color: _c.textPri, fontSize: 13),
                      items: _units
                          .map((u) => DropdownMenuItem(
                                value: u,
                                child: Text(_unitLabels[u]!),
                              ))
                          .toList(),
                      onChanged: (v) {
                        if (v != null) setDlgState(() => selectedUnit = v);
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                // Type chips
                Text(AppStrings.t('log_type'),
                    style: TextStyle(color: _c.textSec, fontSize: 12)),
                const SizedBox(height: 6),
                Row(
                  children:
                      ['inspection', 'repair', 'calibration'].map((t) {
                    final isSelected = selectedType == t;
                    final col = t == 'repair'
                        ? const Color(0xFFE74C3C)
                        : t == 'calibration'
                            ? kOrange
                            : kTeal;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: GestureDetector(
                        onTap: () =>
                            setDlgState(() => selectedType = t),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? col.withValues(alpha: 0.2)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: isSelected
                                  ? col
                                  : _c.divider.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Text(
                            AppStrings.t(t),
                            style: TextStyle(
                              color: isSelected ? col : _c.textSec,
                              fontSize: 12,
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 14),
                // Technician name
                TextField(
                  controller: techCtrl,
                  style: TextStyle(color: _c.textPri),
                  decoration: InputDecoration(
                    labelText: AppStrings.t('log_tech'),
                    labelStyle:
                        TextStyle(color: _c.textSec, fontSize: 13),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide:
                          BorderSide(color: _c.divider.withValues(alpha: 0.3)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: kTeal),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // Description
                TextField(
                  controller: descCtrl,
                  style: TextStyle(color: _c.textPri),
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: AppStrings.t('log_description'),
                    labelStyle:
                        TextStyle(color: _c.textSec, fontSize: 13),
                    alignLabelWithHint: true,
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide:
                          BorderSide(color: _c.divider.withValues(alpha: 0.3)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: kTeal),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(AppStrings.t('close'),
                  style: TextStyle(color: _c.textSec)),
            ),
            ElevatedButton(
              onPressed: () async {
                final user = FirebaseAuth.instance.currentUser;
                final techName = techCtrl.text.trim().isEmpty
                    ? (user?.displayName ?? 'Anonyme')
                    : techCtrl.text.trim();
                Navigator.pop(ctx);
                try {
                  await FirebaseFirestore.instance
                      .collection('maintenance_logs')
                      .add({
                    'unitId': selectedUnit,
                    'type': selectedType,
                    'technicianName': techName,
                    'description': descCtrl.text.trim(),
                    'timestamp': FieldValue.serverTimestamp(),
                    'createdBy': user?.uid ?? '',
                  });
                  // Push a notification into the Alerts tab
                  final typeColor = selectedType == 'repair'
                      ? const Color(0xFFE74C3C)
                      : selectedType == 'calibration'
                          ? kOrange
                          : kTeal;
                  final typeLabel = selectedType == 'repair'
                      ? 'Réparation'
                      : selectedType == 'calibration'
                          ? 'Calibration'
                          : 'Inspection';
                  alertLogNotifier.value = [
                    ...alertLogNotifier.value,
                    AlertEntry(
                      title: 'Maintenance – $typeLabel',
                      detail: descCtrl.text.trim().isEmpty
                          ? 'Par $techName'
                          : descCtrl.text.trim(),
                      color: typeColor,
                      time: DateTime.now(),
                      unitId: selectedUnit,
                    ),
                  ];
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Journal ajouté ✓'),
                        backgroundColor: Color(0xFF2ECC71),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Erreur: $e')),
                    );
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: kTeal,
                foregroundColor: Colors.black87,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: Text(AppStrings.t('save')),
            ),
          ],
        ),
      ),
    );
  }
}
