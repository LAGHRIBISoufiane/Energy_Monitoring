import 'dart:convert';
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../main.dart' show kTeal, kOrange, alertLogNotifier, roleNotifier;
import '../models/alert_entry.dart';
import '../l10n/app_strings.dart';
import '../services/alert_notification_service.dart';

class MaintenanceScreen extends StatefulWidget {
  const MaintenanceScreen({super.key});

  @override
  State<MaintenanceScreen> createState() => _MaintenanceScreenState();
}

class _MaintenanceScreenState extends State<MaintenanceScreen> {
  AppColors get _c => AppColors.of(context);
  String _selectedUnit = 'KOFERT_Unit_1';
  String _statusFilter = 'all'; // 'all', 'pending', 'resolved'

  static const _units = ['KOFERT_Unit_1', 'KOFERT_Unit_2', 'KOFERT_Unit_3'];
  static const _unitLabels = {
    'KOFERT_Unit_1': 'Unit 1 – Lampe',
    'KOFERT_Unit_2': 'Unit 2 – Ventilateur',
    'KOFERT_Unit_3': 'Unit 3 – Pompe',
  };
  static const _resolvedGreen = Color(0xFF2ECC71);

  @override
  void initState() {
    super.initState();
  }

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
            const SizedBox(height: 24),            // ── Status filter chips ─────────────────────────────
            Row(
              children: [
                _filterChip('all', AppStrings.t('filter_all'),
                    Icons.list_alt_outlined),
                const SizedBox(width: 8),
                _filterChip('pending', AppStrings.t('filter_pending'),
                    Icons.pending_actions_outlined),
                const SizedBox(width: 8),
                _filterChip('resolved', AppStrings.t('filter_resolved'),
                    Icons.check_circle_outline),
              ],
            ),
            const SizedBox(height: 16),            // ── Log list ────────────────────────────────────────
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
                  if (snapshot.hasError) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.error_outline,
                              color: kOrange, size: 48),
                          const SizedBox(height: 12),
                          Text(
                            'Erreur de chargement des logs.\n${snapshot.error}',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: _c.textSec, fontSize: 13),
                          ),
                        ],
                      ),
                    );
                  }
                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    return _buildEmpty();
                  }
                  // Client-side status filter
                  final docs = snapshot.data!.docs.where((doc) {
                    final d = doc.data() as Map<String, dynamic>;
                    final isResolved = d['resolved'] as bool? ?? false;
                    if (_statusFilter == 'pending') return !isResolved;
                    if (_statusFilter == 'resolved') return isResolved;
                    return true;
                  }).toList();
                  if (docs.isEmpty) return _buildEmpty();

                  return ListView.builder(
                    itemCount: docs.length,
                    itemBuilder: (ctx, i) {
                      final doc = docs[i];
                      final d = doc.data() as Map<String, dynamic>;
                      final ts = ((d['timestamp'] as Timestamp?)?.toDate() ??
                          DateTime.now()).toLocal();
                      final type = d['type'] as String? ?? 'inspection';
                      final tech = d['technicianName'] as String? ?? '';
                      final desc = d['description'] as String? ?? '';
                      final isResolved = d['resolved'] as bool? ?? false;
                      final resolvedBy = d['resolvedBy'] as String? ?? '';
                      final resolvedAt =
                          (d['resolvedAt'] as Timestamp?)?.toDate().toLocal();
                      final assignedToName = d['assignedToName'] as String? ?? '';
                      final assignedToUid  = d['assignedToUid']  as String? ?? '';
                      final assignedToAll  = d['assignedToAll']  as bool? ?? false;
                      final currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';
                      final isAssignedToMe = assignedToUid.isNotEmpty && assignedToUid == currentUid;
                      final resolutionProblem  = d['resolutionProblem']  as String? ?? '';
                      final resolutionSolution = d['resolutionSolution'] as String? ?? '';
                      final hasReport = isResolved &&
                          (resolutionProblem.isNotEmpty || resolutionSolution.isNotEmpty);
                      final creationAttachB64  = d['attachmentBase64']        as String?;
                      final creationAttachName = d['attachmentName']           as String?;
                      final resolvedAttachB64  = d['resolvedAttachmentBase64'] as String?;
                      final resolvedAttachName = d['resolvedAttachmentName']   as String?;
                      // can the current user see the creation attachment?
                      final createdByUid = d['createdBy'] as String? ?? '';
                      final currentRole  = roleNotifier.value;
                      final isAdminOrMod = currentRole == 'admin' || currentRole == 'moderator';
                      final canSeeCreation = creationAttachB64 != null &&
                          (assignedToAll ||
                           assignedToUid == currentUid ||
                           createdByUid   == currentUid ||
                           isAdminOrMod);
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
                            color: isResolved
                                ? _resolvedGreen.withValues(alpha: 0.4)
                                : typeColor.withValues(alpha: 0.25),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                color: (isResolved ? _resolvedGreen : typeColor)
                                    .withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                isResolved ? Icons.check_circle : typeIcon,
                                color: isResolved ? _resolvedGreen : typeColor,
                                size: 20,
                              ),
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
                                      const SizedBox(width: 8),
                                      // Status badge
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 10, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: isResolved
                                              ? _resolvedGreen.withValues(alpha: 0.15)
                                              : kOrange.withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(20),
                                        ),
                                        child: Text(
                                          isResolved
                                              ? AppStrings.t('resolved')
                                              : AppStrings.t('pending'),
                                          style: TextStyle(
                                              color: isResolved
                                                  ? _resolvedGreen
                                                  : kOrange,
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
                                  if (canSeeCreation) ...[  // creation attachment download
                                    const SizedBox(height: 6),
                                    GestureDetector(
                                      onTap: () => _downloadAttachment(
                                          creationAttachB64!, creationAttachName ?? 'fichier'),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: kTeal.withValues(alpha: 0.08),
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(color: kTeal.withValues(alpha: 0.35)),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.attach_file, size: 13, color: kTeal),
                                            const SizedBox(width: 4),
                                            Flexible(
                                              child: Text(
                                                creationAttachName ?? 'Pièce jointe',
                                                style: TextStyle(color: kTeal, fontSize: 11),
                                                overflow: TextOverflow.ellipsis,
                                                maxLines: 1,
                                              ),
                                            ),
                                            const SizedBox(width: 4),
                                            Icon(Icons.download, size: 13, color: kTeal),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                  if (assignedToAll || assignedToName.isNotEmpty) ...[
                                    const SizedBox(height: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: kTeal.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                            color: kTeal.withValues(alpha: 0.35)),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            assignedToAll
                                                ? Icons.groups_outlined
                                                : Icons.person_pin_circle_outlined,
                                            size: 13, color: kTeal),
                                          const SizedBox(width: 4),
                                          Flexible(
                                            child: Text(
                                              assignedToAll
                                                  ? '${AppStrings.t('assigned_to')}: Tous les utilisateurs'
                                                  : '${AppStrings.t('assigned_to')}: $assignedToName',
                                              style: TextStyle(
                                                  color: kTeal, fontSize: 11),
                                              overflow: TextOverflow.ellipsis,
                                              maxLines: 1,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                        // ── Resolved info ──────────────────────────
                        if (isResolved && resolvedBy.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: _resolvedGreen.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.verified,
                                    color: _resolvedGreen, size: 15),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    '${AppStrings.t('resolved_by')} $resolvedBy'
                                    '${resolvedAt != null ? '  •  ${DateFormat('dd/MM/yyyy HH:mm').format(resolvedAt)}' : ''}',
                                    style: const TextStyle(
                                        color: _resolvedGreen, fontSize: 12),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (resolvedAttachB64 != null) ...[  // resolution attachment download
                            const SizedBox(height: 6),
                            GestureDetector(
                              onTap: () => _downloadAttachment(
                                  resolvedAttachB64, resolvedAttachName ?? 'rapport'),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: _resolvedGreen.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                      color: _resolvedGreen.withValues(alpha: 0.4)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.attach_file,
                                        size: 14, color: _resolvedGreen),
                                    const SizedBox(width: 4),
                                    Flexible(
                                      child: Text(
                                        resolvedAttachName ?? 'Rapport joint',
                                        style: const TextStyle(
                                            color: _resolvedGreen, fontSize: 12),
                                        overflow: TextOverflow.ellipsis,
                                        maxLines: 1,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    const Icon(Icons.download,
                                        size: 14, color: _resolvedGreen),
                                  ],
                                ),
                              ),
                            ),
                          ],
                          if (hasReport) ...[
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              children: [
                                TextButton.icon(
                                  onPressed: () => _showReportDialog(d),
                                  icon: const Icon(
                                      Icons.description_outlined,
                                      size: 15),
                                  label: const Text('Voir le rapport',
                                      style: TextStyle(fontSize: 12)),
                                  style: TextButton.styleFrom(
                                    foregroundColor: kTeal,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 4),
                                  ),
                                ),
                                TextButton.icon(
                                  onPressed: () => _downloadReportAsPdf(d),
                                  icon: const Icon(
                                      Icons.picture_as_pdf_outlined,
                                      size: 15),
                                  label: const Text('Télécharger PDF',
                                      style: TextStyle(fontSize: 12)),
                                  style: TextButton.styleFrom(
                                    foregroundColor:
                                        const Color(0xFFE74C3C),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 4),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ]
                        // ── Resolve action button ───────────────────
                        else if (!isResolved) ...[
                          ValueListenableBuilder<String>(
                            valueListenable: roleNotifier,
                            builder: (_, role, __) {
                              // Observers/viewers can only validate if they are assigned
                              final canAct = (role != 'viewer' && role != 'observer') || isAssignedToMe;
                              if (!canAct) return const SizedBox.shrink();
                              return Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton.icon(
                                    onPressed: () => _showResolveDialog(
                                      doc.id,
                                      d['unitId'] as String? ?? _selectedUnit,
                                      desc,
                                      type,
                                    ),
                                    icon: const Icon(
                                        Icons.check_circle_outline, size: 16),
                                    label: Text(
                                        isAssignedToMe
                                            ? AppStrings.t('validate_repair')
                                            : AppStrings.t('mark_resolved'),
                                        style:
                                            const TextStyle(fontSize: 13)),
                                    style: TextButton.styleFrom(
                                      foregroundColor: _resolvedGreen,
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 14, vertical: 6),
                                      shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(20),
                                        side: BorderSide(
                                            color: _resolvedGreen
                                                .withValues(alpha: 0.5)),
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
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

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.build_circle_outlined, size: 56, color: _c.textSec),
          const SizedBox(height: 14),
          Text(AppStrings.t('no_logs'),
              style: TextStyle(color: _c.textSec, fontSize: 14)),
        ],
      ),
    );
  }

  Widget _filterChip(String value, String label, IconData icon) {
    final isActive = _statusFilter == value;
    final color = value == 'resolved'
        ? _resolvedGreen
        : value == 'pending'
            ? kOrange
            : kTeal;
    return GestureDetector(
      onTap: () => setState(() => _statusFilter = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: isActive ? color.withValues(alpha: 0.15) : _c.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: isActive ? color : _c.divider.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: isActive ? color : _c.textSec),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: isActive ? color : _c.textSec,
                fontSize: 12,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showResolveDialog(
      String docId, String unitId, String desc, String type) async {
    final problemCtrl  = TextEditingController(text: desc);
    final solutionCtrl = TextEditingController();
    String? attachmentBase64;
    String? attachmentName;
    bool isPicking = false;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          backgroundColor: _c.card,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
          insetPadding: const EdgeInsets.symmetric(
              horizontal: 16, vertical: 24),
          title: Row(
            children: [
              const Icon(Icons.check_circle_outline,
                  color: _resolvedGreen, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(AppStrings.t('resolve_title'),
                    style: TextStyle(color: _c.textPri, fontSize: 16))),
            ],
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Décrivez le problème/solution, ou joignez une pièce jointe.',
                    style: TextStyle(color: _c.textSec, fontSize: 12),
                  ),
                  const SizedBox(height: 14),
                  // ── Problem field ──────────────────────────────
                  Text('Résumé du problème (optionnel si pièce jointe)',
                      style: TextStyle(
                          color: _c.textSec,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: problemCtrl,
                    style: TextStyle(color: _c.textPri),
                    maxLines: 3,
                    decoration: InputDecoration(
                      hintText: 'Décrivez le problème rencontré...',
                      hintStyle: TextStyle(
                          color: _c.textSec.withValues(alpha: 0.5)),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(
                            color: _c.divider.withValues(alpha: 0.3)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide:
                            const BorderSide(color: _resolvedGreen),
                      ),
                      contentPadding: const EdgeInsets.all(12),
                    ),
                  ),
                  const SizedBox(height: 14),
                  // ── Solution field ─────────────────────────────
                  Text('Solution appliquée (optionnel si pièce jointe)',
                      style: TextStyle(
                          color: _c.textSec,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: solutionCtrl,
                    style: TextStyle(color: _c.textPri),
                    maxLines: 4,
                    decoration: InputDecoration(
                      hintText:
                          'Décrivez la solution et les étapes effectuées...',
                      hintStyle: TextStyle(
                          color: _c.textSec.withValues(alpha: 0.5)),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(
                            color: _c.divider.withValues(alpha: 0.3)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide:
                            const BorderSide(color: _resolvedGreen),
                      ),
                      contentPadding: const EdgeInsets.all(12),
                    ),
                  ),
                  const SizedBox(height: 14),
                  // ── Attachment picker ──────────────────────────
                  Text('Pièce jointe (optionnelle)',
                      style: TextStyle(
                          color: _c.textSec,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  GestureDetector(
                    onTap: isPicking
                        ? null
                        : () async {
                            isPicking = true;
                            setDlg(() {});
                            final input =
                                html.FileUploadInputElement()
                                  ..accept =
                                      '.pdf,.png,.jpg,.jpeg';
                            input.click();
                            await input.onChange.first;
                            if (input.files == null ||
                                input.files!.isEmpty) {
                              isPicking = false;
                              setDlg(() {});
                              return;
                            }
                            final file = input.files!.first;
                            if (file.size > 500 * 1024) {
                              isPicking = false;
                              setDlg(() {});
                              if (ctx.mounted) {
                                ScaffoldMessenger.of(context)
                                    .showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                        'Fichier trop volumineux (max 500 KB)'),
                                  ),
                                );
                              }
                              return;
                            }
                            final reader = html.FileReader();
                            reader.readAsDataUrl(file);
                            await reader.onLoad.first;
                            attachmentBase64 =
                                reader.result as String;
                            attachmentName = file.name;
                            isPicking = false;
                            setDlg(() {});
                          },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: _c.cardAlt,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: attachmentBase64 != null
                              ? _resolvedGreen
                                  .withValues(alpha: 0.5)
                              : _c.divider.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(children: [
                        Icon(
                          attachmentBase64 != null
                              ? Icons.attach_file
                              : Icons.upload_file_outlined,
                          color: attachmentBase64 != null
                              ? _resolvedGreen
                              : _c.textSec,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            isPicking
                                ? 'Chargement...'
                                : (attachmentName ??
                                    'Joindre un fichier (PDF, image — max 500 KB)'),
                            style: TextStyle(
                              color: attachmentBase64 != null
                                  ? _c.textPri
                                  : _c.textSec,
                              fontSize: 13,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (attachmentBase64 != null)
                          GestureDetector(
                            onTap: () => setDlg(() {
                              attachmentBase64 = null;
                              attachmentName = null;
                            }),
                            child: Icon(Icons.close,
                                size: 16, color: _c.textSec),
                          ),
                      ]),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(AppStrings.t('close'),
                  style: TextStyle(color: _c.textSec)),
            ),
            ElevatedButton.icon(
              onPressed: () {
                final hasText = problemCtrl.text.trim().isNotEmpty ||
                    solutionCtrl.text.trim().isNotEmpty;
                if (!hasText && attachmentBase64 == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                          'Remplissez le problème/solution ou joignez un fichier.'),
                    ),
                  );
                  return;
                }
                Navigator.pop(ctx, true);
              },
              icon: const Icon(Icons.check, size: 16),
              label: Text(AppStrings.t('confirm_resolve')),
              style: ElevatedButton.styleFrom(
                backgroundColor: _resolvedGreen,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;

    try {
      final user = FirebaseAuth.instance.currentUser;
      final resolverName =
          user?.displayName ?? user?.email ?? 'Anonyme';
      await FirebaseFirestore.instance
          .collection('maintenance_logs')
          .doc(docId)
          .update({
        'resolved': true,
        'resolvedAt': FieldValue.serverTimestamp(),
        'resolvedBy': resolverName,
        'resolvedByUid': user?.uid ?? '',
        'resolutionProblem':  problemCtrl.text.trim(),
        'resolutionSolution': solutionCtrl.text.trim(),
        if (attachmentBase64 != null) 'resolvedAttachmentBase64': attachmentBase64,
        if (attachmentName  != null) 'resolvedAttachmentName':  attachmentName,
      });
      // Broadcast resolve notification to all users via Firestore + email
      final resolveTitle = AppStrings.t('resolve_notify');
      final resolveDetail = '${AppStrings.t(type)} — ${_unitLabels[unitId] ?? unitId}';
      FirebaseFirestore.instance.collection('alerts').add({
        'title': resolveTitle,
        'detail': resolveDetail,
        'unitId': unitId,
        'type': 'maintenance_resolved',
        'resolvedByUid': user?.uid ?? '',
        'timestamp': FieldValue.serverTimestamp(),
      }).ignore();
      AlertNotificationService.instance.sendMaintenanceResolvedToAll(
        taskType:           type,
        unitId:             unitId,
        description:        desc,
        resolvedByName:     resolverName,
        resolutionProblem:  problemCtrl.text.trim(),
        resolutionSolution: solutionCtrl.text.trim(),
      );
      // Push notification to Alerts tab (local — for the resolver)
      alertLogNotifier.value = [
        ...alertLogNotifier.value,
        AlertEntry(
          title: AppStrings.t('resolve_notify'),
          detail: desc.isNotEmpty ? desc : AppStrings.t(type),
          color: _resolvedGreen,
          time: DateTime.now(),
          unitId: unitId,
        ),
      ];
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(children: [
              const Icon(Icons.check_circle, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Text('${AppStrings.t('resolved')} ✓'),
            ]),
            backgroundColor: _resolvedGreen,
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
  }

  /// Trigger a browser download of a base64-encoded file attachment.
  void _downloadAttachment(String base64Data, String fileName) {
    try {
      // Strip data URI prefix if present (e.g. "data:application/pdf;base64,")
      final raw = base64Data.contains(',') ? base64Data.split(',').last : base64Data;
      // Determine MIME type from prefix for correct Blob type
      String mime = 'application/octet-stream';
      if (base64Data.startsWith('data:') && base64Data.contains(';')) {
        mime = base64Data.substring(5, base64Data.indexOf(';'));
      }
      final bytes = base64Decode(raw);
      final blob  = html.Blob([bytes], mime);
      final url   = html.Url.createObjectUrlFromBlob(blob);
      final anchor = html.AnchorElement(href: url)
        ..setAttribute('download', fileName)
        ..style.display = 'none';
      html.document.body!.append(anchor);
      anchor.click();
      anchor.remove();
      html.Url.revokeObjectUrl(url);
    } catch (e) {
      debugPrint('Download error: $e');
    }
  }

  void _showReportDialog(Map<String, dynamic> d) {
    final unitId     = d['unitId']          as String? ?? '';
    final type       = d['type']            as String? ?? '';
    final tech       = d['technicianName']  as String? ?? '';
    final resolvedBy = d['resolvedBy']      as String? ?? '';
    final resolvedAt = (d['resolvedAt'] as Timestamp?)?.toDate().toLocal();
    final problem    = d['resolutionProblem']  as String? ?? '';
    final solution   = d['resolutionSolution'] as String? ?? '';
    final attachB64  = d['attachmentBase64']   as String? ?? '';
    final attachName = d['attachmentName']     as String? ?? '';
    final dateStr    = resolvedAt != null
        ? DateFormat('dd/MM/yyyy HH:mm').format(resolvedAt)
        : '';
    final unitLabel  = _unitLabels[unitId] ?? unitId;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _c.card,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
        contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
        title: Row(
          children: [
            const Icon(Icons.description, color: kTeal, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text('Rapport de maintenance',
                  style: TextStyle(
                      color: _c.textPri, fontSize: 16)),
            ),
            IconButton(
              icon: Icon(Icons.close, color: _c.textSec, size: 18),
              onPressed: () => Navigator.pop(ctx),
            ),
          ],
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Meta info ─────────────────────────────────────
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: kTeal.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    children: [
                      _reportMetaRow('Unité', unitLabel),
                      _reportMetaRow('Type', AppStrings.t(type)),
                      _reportMetaRow('Technicien', tech),
                      _reportMetaRow('Résolu par', resolvedBy),
                      _reportMetaRow('Date', dateStr),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                // ── Problem ───────────────────────────────────────
                Text('Problème rencontré',
                    style: TextStyle(
                        color: _c.textSec,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: kOrange.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: kOrange.withValues(alpha: 0.2)),
                  ),
                  child: Text(
                    problem.isEmpty ? '—' : problem,
                    style: TextStyle(
                        color: _c.textPri, fontSize: 13),
                  ),
                ),
                const SizedBox(height: 14),
                // ── Solution ──────────────────────────────────────
                Text('Solution appliquée',
                    style: TextStyle(
                        color: _c.textSec,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _resolvedGreen.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: _resolvedGreen.withValues(alpha: 0.2)),
                  ),
                  child: Text(
                    solution.isEmpty ? '—' : solution,
                    style: TextStyle(
                        color: _c.textPri, fontSize: 13),
                  ),
                ),
                // ── Attachment ────────────────────────────────────
                if (attachB64.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text('Pièce jointe',
                      style: TextStyle(
                          color: _c.textSec,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  GestureDetector(
                    onTap: () {
                      html.AnchorElement(href: attachB64)
                        ..setAttribute('download',
                            attachName.isEmpty ? 'rapport' : attachName)
                        ..click();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: _c.cardAlt,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: kTeal.withValues(alpha: 0.35)),
                      ),
                      child: Row(children: [
                        const Icon(Icons.attach_file,
                            color: kTeal, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            attachName.isEmpty
                                ? 'Pièce jointe'
                                : attachName,
                            style: const TextStyle(
                                color: kTeal, fontSize: 13),
                          ),
                        ),
                        const Icon(Icons.download_outlined,
                            color: kTeal, size: 16),
                      ]),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () => _downloadReportAsPdf(d),
            icon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
            label: const Text('Télécharger PDF'),
            style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFE74C3C)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            style: ElevatedButton.styleFrom(
              backgroundColor: kTeal,
              foregroundColor: Colors.black87,
            ),
            child: Text(AppStrings.t('close')),
          ),
        ],
      ),
    );
  }

  void _downloadReportAsPdf(Map<String, dynamic> d) {
    final unitId     = d['unitId']          as String? ?? '';
    final type       = d['type']            as String? ?? '';
    final tech       = d['technicianName']  as String? ?? '';
    final resolvedBy = d['resolvedBy']      as String? ?? '';
    final resolvedAt = (d['resolvedAt'] as Timestamp?)?.toDate().toLocal();
    final problem    = d['resolutionProblem']  as String? ?? '';
    final solution   = d['resolutionSolution'] as String? ?? '';
    final attachB64  = d['attachmentBase64']   as String? ?? '';
    final attachName = d['attachmentName']     as String? ?? '';
    final dateStr    = resolvedAt != null
        ? DateFormat('dd/MM/yyyy HH:mm').format(resolvedAt)
        : '';
    final unitLabel  = _unitLabels[unitId] ?? unitId;

    final attachHtml = attachB64.isNotEmpty
        ? '<h2>Pièce jointe</h2>'
          '<p><a href="$attachB64" download="$attachName">'
          'Télécharger : $attachName</a></p>'
        : '';

    final content = '''
<!DOCTYPE html>
<html lang="fr">
<head>
  <meta charset="UTF-8">
  <title>Rapport de Maintenance – $unitLabel</title>
  <style>
    body { font-family: Arial, sans-serif; max-width: 720px;
           margin: 40px auto; color: #222; }
    h1   { color: #0D47A1; font-size: 22px;
           border-bottom: 2px solid #0D47A1; padding-bottom: 10px; }
    h2   { color: #1a3a5c; font-size: 15px; margin-top: 24px; }
    table.meta { width: 100%; border-collapse: collapse;
                 background: #f5f5f5; border-radius: 8px;
                 margin: 16px 0; font-size: 13px; }
    table.meta td { padding: 8px 12px; }
    table.meta td:first-child { color: #666; width: 180px; }
    .section { background: #fafafa; border: 1px solid #e0e0e0;
               border-radius: 8px; padding: 16px; margin: 8px 0;
               font-size: 13px; white-space: pre-wrap; }
    @media print { body { margin: 20px; } }
  </style>
</head>
<body>
<h1>Rapport de Maintenance – KOFERT JFC3</h1>
<table class="meta">
  <tr><td>Unité</td><td><strong>$unitLabel</strong></td></tr>
  <tr><td>Type</td><td><strong>${AppStrings.t(type)}</strong></td></tr>
  <tr><td>Technicien</td><td>$tech</td></tr>
  <tr><td>Résolu par</td><td><strong>$resolvedBy</strong></td></tr>
  <tr><td>Date de résolution</td><td>$dateStr</td></tr>
</table>
<h2>Problème rencontré</h2>
<div class="section">${problem.isEmpty ? '—' : problem}</div>
<h2>Solution appliquée</h2>
<div class="section">${solution.isEmpty ? '—' : solution}</div>
$attachHtml
<script>window.addEventListener('load', function() { window.print(); });</script>
</body>
</html>''';

    final blob = html.Blob([content], 'text/html');
    final url  = html.Url.createObjectUrlFromBlob(blob);
    html.window.open(url, '_blank');
    Future.delayed(
      const Duration(seconds: 10),
      () => html.Url.revokeObjectUrl(url),
    );
  }

  Widget _reportMetaRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(label,
                style: TextStyle(color: _c.textSec, fontSize: 12)),
          ),
          Expanded(
            child: Text(value,
                style: TextStyle(
                    color: _c.textPri,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  void _showAddEntryDialog() {
    final descCtrl = TextEditingController();
    String selectedType = 'inspection';
    String selectedUnit = _selectedUnit;
    String? assignedUid;
    String? assignedName;
    bool assignToAll = false;
    String? attachmentBase64;
    String? attachmentName;
    bool isPicking = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          backgroundColor: _c.card,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
          insetPadding: const EdgeInsets.symmetric(
              horizontal: 16, vertical: 24),
          title: Row(
            children: [
              Icon(Icons.build_circle, color: kTeal, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(AppStrings.t('add_entry'),
                    style: TextStyle(color: _c.textPri, fontSize: 16))),
            ],
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                // Unit selector
                Text(AppStrings.t('unit_label'),
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
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children:
                      ['inspection', 'repair', 'calibration'].map((t) {
                    final isSelected = selectedType == t;
                    final col = t == 'repair'
                        ? const Color(0xFFE74C3C)
                        : t == 'calibration'
                            ? kOrange
                            : kTeal;
                    return GestureDetector(
                      onTap: () => setDlgState(() => selectedType = t),
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
                    );
                  }).toList(),
                ),
                const SizedBox(height: 14),
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
                const SizedBox(height: 12),
                // ── File attachment ───────────────────────────
                GestureDetector(
                  onTap: isPicking ? null : () async {
                    setDlgState(() => isPicking = true);
                    final input = html.FileUploadInputElement()
                      ..accept = '.pdf,.png,.jpg,.jpeg';
                    input.click();
                    await input.onChange.first;
                    if (input.files == null || input.files!.isEmpty) {
                      setDlgState(() => isPicking = false);
                      return;
                    }
                    final file = input.files!.first;
                    if (file.size > 500 * 1024) {
                      setDlgState(() => isPicking = false);
                      if (mounted) {
                        ScaffoldMessenger.of(this.context).showSnackBar(
                          const SnackBar(
                              content: Text(
                                  'Fichier trop volumineux (max 500 KB)')),
                        );
                      }
                      return;
                    }
                    final reader = html.FileReader();
                    reader.readAsDataUrl(file);
                    await reader.onLoad.first;
                    setDlgState(() {
                      attachmentBase64 = reader.result as String;
                      attachmentName = file.name;
                      isPicking = false;
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: _c.cardAlt,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: attachmentBase64 != null
                              ? _resolvedGreen.withValues(alpha: 0.5)
                              : _c.divider.withValues(alpha: 0.3)),
                    ),
                    child: Row(children: [
                      Icon(
                        attachmentBase64 != null
                            ? Icons.attach_file
                            : Icons.upload_file_outlined,
                        color: attachmentBase64 != null
                            ? _resolvedGreen
                            : _c.textSec,
                        size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          isPicking
                              ? 'Chargement...'
                              : (attachmentName ??
                                  'Joindre un fichier (PDF, image — max 500 KB)'),
                          style: TextStyle(
                            color: attachmentBase64 != null
                                ? _c.textPri
                                : _c.textSec,
                            fontSize: 13,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (attachmentBase64 != null)
                        GestureDetector(
                          onTap: () => setDlgState(() {
                            attachmentBase64 = null;
                            attachmentName = null;
                          }),
                          child: Icon(Icons.close,
                              size: 16, color: _c.textSec),
                        ),
                    ]),
                  ),
                ),
                const SizedBox(height: 12),
                // ── Assign to all toggle ──────────────────────
                Row(
                  children: [
                    Expanded(
                      child: Text(AppStrings.t('assign_to'),
                          style:
                              TextStyle(color: _c.textSec, fontSize: 12)),
                    ),
                    GestureDetector(
                      onTap: () => setDlgState(() {
                        assignToAll = !assignToAll;
                        if (assignToAll) {
                          assignedUid = null;
                          assignedName = null;
                        }
                      }),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: assignToAll
                              ? kTeal.withValues(alpha: 0.15)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: assignToAll
                                ? kTeal
                                : _c.divider.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.groups_outlined,
                                size: 14,
                                color: assignToAll ? kTeal : _c.textSec),
                            const SizedBox(width: 4),
                            Text(
                              'Tous les utilisateurs',
                              style: TextStyle(
                                  color:
                                      assignToAll ? kTeal : _c.textSec,
                                  fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                // Assignee picker
                if (!assignToAll)
                GestureDetector(
                  onTap: () async {
                    final picked = await _pickAssignee(ctx);
                    if (picked != null) {
                      setDlgState(() {
                        assignedUid = picked['uid'];
                        assignedName = picked['name'];
                      });
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: _c.cardAlt,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: assignedUid != null
                              ? kTeal.withValues(alpha: 0.5)
                              : _c.divider.withValues(alpha: 0.3)),
                    ),
                    child: Row(children: [
                      Icon(Icons.person_search,
                          color: assignedUid != null ? kTeal : _c.textSec,
                          size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          assignedName ?? AppStrings.t('no_assignee'),
                          style: TextStyle(
                            color: assignedUid != null
                                ? _c.textPri
                                : _c.textSec,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      if (assignedUid != null)
                        GestureDetector(
                          onTap: () => setDlgState(() {
                            assignedUid = null;
                            assignedName = null;
                          }),
                          child: Icon(Icons.close,
                              size: 16, color: _c.textSec),
                        ),
                    ]),
                  ),
                ),
              ],
            ),
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
                final techName = user?.displayName ?? user?.email ?? 'Anonyme';
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
                    'resolved': false,
                    'assignedToAll': assignToAll,
                    if (!assignToAll && assignedUid != null) ...{
                      'assignedToUid': assignedUid!,
                      'assignedToName': assignedName ?? '',
                    },
                    if (attachmentBase64 != null)
                      'attachmentBase64': attachmentBase64!,
                    if (attachmentName != null)
                      'attachmentName': attachmentName!,
                  });
                  // Push a notification into the Alerts tab
                  final typeColor = selectedType == 'repair'
                      ? const Color(0xFFE74C3C)
                      : selectedType == 'calibration'
                          ? kOrange
                          : kTeal;
                  alertLogNotifier.value = [
                    ...alertLogNotifier.value,
                    AlertEntry(
                      title: 'Maintenance – ${AppStrings.t(selectedType)}',
                      detail: descCtrl.text.trim().isEmpty
                          ? 'Par $techName'
                          : descCtrl.text.trim(),
                      color: typeColor,
                      time: DateTime.now(),
                      unitId: selectedUnit,
                    ),
                    // Alert for the assigned user
                    if (assignedUid != null)
                      AlertEntry(
                        title: AppStrings.t('maintenance_assigned'),
                        detail: descCtrl.text.trim().isEmpty
                            ? AppStrings.t(selectedType)
                            : descCtrl.text.trim(),
                        color: kTeal,
                        time: DateTime.now(),
                        unitId: selectedUnit,
                      ),
                  ];
                  // Email the assigned user(s)
                  if (assignToAll) {
                    AlertNotificationService.instance
                        .sendMaintenanceAssignedToAll(
                      taskType:       selectedType,
                      unitId:         selectedUnit,
                      description:    descCtrl.text.trim(),
                      assignedByName: techName,
                    );
                  } else if (assignedUid != null) {
                    AlertNotificationService.instance
                        .sendMaintenanceAssignedEmail(
                      assignedUid:    assignedUid!,
                      taskType:       selectedType,
                      unitId:         selectedUnit,
                      description:    descCtrl.text.trim(),
                      assignedByName: techName,
                    );
                  }
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(AppStrings.t('log_added')),
                        backgroundColor: const Color(0xFF2ECC71),
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

  /// Opens a dialog to pick a user from Firestore as assignee.
  Future<Map<String, String>?> _pickAssignee(BuildContext ctx) async {
    late QuerySnapshot<Map<String, dynamic>> snap;
    try {
      snap = await FirebaseFirestore.instance.collection('users').get();
    } catch (_) {
      return null;
    }
    if (!ctx.mounted) return null;
    return showDialog<Map<String, String>>(
      context: ctx,
      builder: (dlgCtx) {
        final searchCtrl = TextEditingController();
        return StatefulBuilder(builder: (dlgCtx, setS) {
          final query = searchCtrl.text.toLowerCase();
          final filtered = snap.docs.where((doc) {
            final d = doc.data();
            final name =
                '${d['firstName'] ?? ''} ${d['lastName'] ?? ''}'.trim().toLowerCase();
            final email = (d['email'] as String? ?? '').toLowerCase();
            return query.isEmpty ||
                name.contains(query) ||
                email.contains(query);
          }).toList();
          return AlertDialog(
            backgroundColor: _c.card,
            title: Text(AppStrings.t('assign_to'),
                style: TextStyle(color: _c.textPri)),
            content: SizedBox(
              width: 380,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(
                  controller: searchCtrl,
                  style: TextStyle(color: _c.textPri),
                  onChanged: (_) => setS(() {}),
                  decoration: InputDecoration(
                    hintText: AppStrings.t('search'),
                    hintStyle: TextStyle(color: _c.textSec),
                    prefixIcon:
                        Icon(Icons.search, color: _c.textSec),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(
                          color: _c.divider.withValues(alpha: 0.3)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: kTeal),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 300),
                  child: ListView(
                    shrinkWrap: true,
                    children: filtered.map((doc) {
                      final d = doc.data();
                      final name =
                          '${d['firstName'] ?? ''} ${d['lastName'] ?? ''}'
                              .trim();
                      final email =
                          d['email'] as String? ?? doc.id;
                      final displayName =
                          name.isEmpty ? email : name;
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor:
                              kTeal.withValues(alpha: 0.2),
                          child: Text(
                            displayName[0].toUpperCase(),
                            style: const TextStyle(
                                color: kTeal, fontSize: 14),
                          ),
                        ),
                        title: Text(displayName,
                            style: TextStyle(
                                color: _c.textPri, fontSize: 13)),
                        subtitle: Text(email,
                            style: TextStyle(
                                color: _c.textSec, fontSize: 11)),
                        onTap: () => Navigator.pop(
                            dlgCtx,
                            {'uid': doc.id, 'name': displayName}),
                      );
                    }).toList(),
                  ),
                ),
              ]),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dlgCtx),
                child: Text(AppStrings.t('close'),
                    style: TextStyle(color: _c.textSec)),
              ),
            ],
          );
        });
      },
    );
  }
}
