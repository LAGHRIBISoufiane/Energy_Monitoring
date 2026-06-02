import 'dart:math';
import 'dart:convert';
// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme/app_colors.dart';
import '../main.dart' show kTeal, kOrange, roleNotifier;
import '../services/presence_service.dart';
import '../services/user_log_service.dart';
import '../l10n/app_strings.dart';
import '../widgets/user_avatar.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  AppColors get _c => AppColors.of(context);
  bool get _isMobile => MediaQuery.sizeOf(context).width < 700;

  final _displayNameCtrl = TextEditingController();
  final _customIdCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _newPwCtrl = TextEditingController();
  final _confirmPwCtrl = TextEditingController();
  final _currentPwCtrl = TextEditingController();

  bool _pwVisible = false;
  bool _confirmVisible = false;
  bool _currentPwVisible = false;
  bool _isLoading = false;
  bool _isSaving = false;

  // Avatar color
  Color _avatarColor = kTeal;
  String? _avatarImageBase64; // uploaded image (base64)
  bool _isUploadingImage = false;
  static const _avatarColors = [
    Color(0xFF4ECDC4), Color(0xFFF5A623), Color(0xFFE74C3C),
    Color(0xFF9B59B6), Color(0xFF3498DB), Color(0xFF2ECC71),
    Color(0xFFFF6B8A), Color(0xFF1ABC9C),
  ];

  // Presence status
  String _presenceStatus = 'online';

  // User role
  String _role = 'viewer';

  // Firestore profile data
  String? _firstName;
  String? _lastName;
  String? _customId;
  String? _poste;

  @override
  void initState() {
    super.initState();
    _loadProfile().then((_) => _checkPendingInvitations());
  }

  @override
  void dispose() {
    _displayNameCtrl.dispose();
    _customIdCtrl.dispose();
    _emailCtrl.dispose();
    _newPwCtrl.dispose();
    _confirmPwCtrl.dispose();
    _currentPwCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    setState(() => _isLoading = true);
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    _emailCtrl.text = user.email ?? '';

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (doc.exists) {
        final d = doc.data()!;
        _firstName = d['firstName'] as String? ?? '';
        _lastName  = d['lastName']  as String? ?? '';
        final existingCustomId = d['customId'] as String?;
        if (existingCustomId == null) {
          _customId = _generateId();
          // Auto-persist so others can find this user by ID immediately
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .set({'customId': _customId}, SetOptions(merge: true));
        } else {
          _customId = existingCustomId;
        }
        _poste     = d['poste']     as String? ?? '';
        // Avatar color index
        final colorIdx = (d['avatarColorIdx'] as int?) ?? 0;
        _avatarColor = _avatarColors[colorIdx.clamp(0, _avatarColors.length - 1)];
        // Avatar image
        _avatarImageBase64 = d['avatarImageBase64'] as String?;
        // Presence
        _presenceStatus = d['presenceStatus'] as String? ?? 'online';
        // Always enforce admin role for the designated admin account.
        // Set _role and roleNotifier FIRST so the UI is correct even if the
        // Firestore write is blocked (bootstrapping chicken-and-egg).
        if (user.email?.toLowerCase() == 'soufianelaghri1@gmail.com') {
          _role = 'admin';
          roleNotifier.value = 'admin';
          if ((d['role'] as String?) != 'admin') {
            try {
              await FirebaseFirestore.instance
                  .collection('users')
                  .doc(user.uid)
                  .set({'role': 'admin'}, SetOptions(merge: true));
            } catch (_) {} // OK if blocked — client role already set
          }
        } else {
          _role = d['role'] as String? ?? 'viewer';
          // Keep roleNotifier in sync with fresh data from profile load
          roleNotifier.value = _role;
        }

        _displayNameCtrl.text =
            '${_firstName!} ${_lastName!}'.trim().isEmpty
                ? (user.displayName ?? '')
                : '${_firstName!} ${_lastName!}'.trim();
        _customIdCtrl.text = _customId!;
      } else {
        _displayNameCtrl.text = user.displayName ?? '';
        _customId = _generateId();
        _customIdCtrl.text = _customId!;
        // Auto-persist so others can find this user by ID immediately
        // Default role to 'viewer' so Firestore security rules work correctly
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .set({'customId': _customId, 'email': user.email, 'role': 'viewer'}, SetOptions(merge: true));
      }
    } catch (_) {
      _displayNameCtrl.text = user.displayName ?? '';
      _customIdCtrl.text = _generateId();
    }

    if (mounted) setState(() => _isLoading = false);
  }

  String _generateId() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rng = Random.secure();
    return List.generate(8, (_) => chars[rng.nextInt(chars.length)]).join();
  }

  Future<void> _showManageUsersDialog() async {
    final snap = await FirebaseFirestore.instance.collection('users').get();
    if (!mounted) return;
    final docs = snap.docs;
    final currentUserUid = FirebaseAuth.instance.currentUser?.uid;
    final isModerator = _role == 'moderator';
    // Moderator cannot assign or demote to admin
    final assignableRoles = isModerator
        ? ['moderator', 'operator', 'observer', 'viewer']
        : ['admin', 'moderator', 'operator', 'observer', 'viewer'];

    final originalRoles = <String, String>{
      for (final d in docs) d.id: (d.data()['role'] as String?) ?? 'viewer',
    };
    final roleMap = Map<String, String>.from(originalRoles);
    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text(AppStrings.t('manage_users')),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: docs.map((d) {
                final data = d.data();
                final name = '${data['firstName'] ?? ''} ${data['lastName'] ?? ''}'.trim();
                final email = data['email'] as String? ?? d.id;
                final isCurrentUser = d.id == currentUserUid;
                final targetRole = roleMap[d.id] ?? 'viewer';
                // Moderator cannot change the role of an admin
                final canEdit = !isCurrentUser &&
                    !(isModerator && targetRole == 'admin');
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          UserAvatar(uid: d.id, fallbackName: name.isEmpty ? email : name, radius: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name.isEmpty ? email : name,
                                  style: TextStyle(
                                      color: _c.textPri, fontWeight: FontWeight.w600, fontSize: 14),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(email,
                                    style: TextStyle(color: _c.textSec, fontSize: 12),
                                    overflow: TextOverflow.ellipsis),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(Icons.shield_outlined,
                              size: 14, color: _roleColor(targetRole)),
                          const SizedBox(width: 6),
                          Expanded(
                            child: canEdit
                                ? DropdownButtonHideUnderline(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: _roleColor(targetRole)
                                            .withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                            color: _roleColor(targetRole)
                                                .withValues(alpha: 0.35)),
                                      ),
                                      child: DropdownButton<String>(
                                        value: assignableRoles.contains(targetRole)
                                            ? targetRole
                                            : assignableRoles.last,
                                        isDense: true,
                                        isExpanded: true,
                                        dropdownColor: _c.card,
                                        style: TextStyle(
                                            color: _roleColor(targetRole),
                                            fontSize: 12),
                                        icon: Icon(Icons.expand_more,
                                            color: _roleColor(targetRole),
                                            size: 16),
                                        items: assignableRoles
                                            .map((r) => DropdownMenuItem(
                                                  value: r,
                                                  child: Text(AppStrings.t('role_$r'),
                                                      style: TextStyle(
                                                          fontSize: 12,
                                                          color: _roleColor(r))),
                                                ))
                                            .toList(),
                                        onChanged: (newRole) {
                                          if (newRole == null) return;
                                          setS(() => roleMap[d.id] = newRole);
                                        },
                                      ),
                                    ),
                                  )
                                : Text(
                                    AppStrings.t('role_$targetRole'),
                                    style: TextStyle(
                                        color: _roleColor(targetRole),
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12),
                                  ),
                          ),
                        ],
                      ),
                      const Divider(height: 16),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler'),
            ),
            ElevatedButton(
              onPressed: () async {
                final navigator = Navigator.of(ctx);
                // Only write roles that actually changed to avoid
                // Firestore permission errors (e.g. moderator re-writing
                // an admin's existing role).
                final changed = roleMap.entries
                    .where((e) => e.value != originalRoles[e.key])
                    .toList();
                if (changed.isEmpty) {
                  navigator.pop();
                  return;
                }
                try {
                  final batch = FirebaseFirestore.instance.batch();
                  for (final entry in changed) {
                    batch.update(
                      FirebaseFirestore.instance.collection('users').doc(entry.key),
                      {'role': entry.value},
                    );
                  }
                  await batch.commit();
                  // Log each role change
                  for (final entry in changed) {
                    final targetData = docs.firstWhere((d) => d.id == entry.key).data();
                    final targetEmail = targetData['email'] as String? ?? entry.key;
                    final oldRole = originalRoles[entry.key] ?? 'viewer';
                    UserLogService.instance.log(
                      action: 'role_change',
                      detail: '$targetEmail: ${AppStrings.t('role_$oldRole')} → ${AppStrings.t('role_${entry.value}')}',
                    );
                  }
                  if (mounted) navigator.pop();
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Erreur: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              },
              child: const Text('Sauvegarder'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showInviteUserDialog() async {
    final emailCtrl = TextEditingController();
    String selectedRole = 'observer';
    final isModerator = _role == 'moderator';
    final assignableRoles = isModerator
        ? ['moderator', 'operator', 'observer', 'viewer']
        : ['admin', 'moderator', 'operator', 'observer', 'viewer'];

    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text(AppStrings.t('invite_user')),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(AppStrings.t('invite_by_email'),
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                const SizedBox(height: 8),
                TextField(
                  controller: emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    hintText: 'user@example.com',
                    prefixIcon: const Icon(Icons.email_outlined),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                  ),
                ),
                const SizedBox(height: 16),
                Text(AppStrings.t('invite_role'),
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: selectedRole,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                  ),
                  items: assignableRoles.map((r) => DropdownMenuItem(
                    value: r,
                    child: Text(AppStrings.t('role_$r')),
                  )).toList(),
                  onChanged: (v) {
                    if (v != null) setS(() => selectedRole = v);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler'),
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.send_outlined, size: 16),
              label: Text(AppStrings.t('invite_user')),
              onPressed: () async {
                final email = emailCtrl.text.trim().toLowerCase();
                if (email.isEmpty || !email.contains('@')) {
                  _snack('Email invalide', isError: true);
                  return;
                }
                final inviter = FirebaseAuth.instance.currentUser;
                final inviterName = inviter?.displayName ?? inviter?.email ?? 'Unknown';
                try {
                  await FirebaseFirestore.instance.collection('invitations').add({
                    'email': email,
                    'role': selectedRole,
                    'invitedBy': inviter?.uid,
                    'inviterName': inviterName,
                    'status': 'pending',
                    'createdAt': FieldValue.serverTimestamp(),
                  });
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (mounted) _snack(AppStrings.t('invitation_sent'));
                } catch (e) {
                  _snack('Erreur: $e', isError: true);
                }
              },
            ),
          ],
        ),
      ),
    );
    emailCtrl.dispose();
  }

  Future<void> _checkPendingInvitations() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.email == null) return;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('invitations')
          .where('email', isEqualTo: user.email!.toLowerCase())
          .where('status', isEqualTo: 'pending')
          .get();
      for (final doc in snap.docs) {
        if (!mounted) return;
        final data = doc.data();
        final role = data['role'] as String? ?? 'viewer';
        final inviterName = data['inviterName'] as String? ?? 'Un administrateur';
        final accept = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (dialogCtx) => AlertDialog(
            title: Text(AppStrings.t('invitation_received')),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${AppStrings.t('invited_by')}: $inviterName'),
                const SizedBox(height: 6),
                Text('${AppStrings.t('invited_as')}: ${AppStrings.t('role_$role')}',
                    style: TextStyle(
                        color: _roleColor(role), fontWeight: FontWeight.bold)),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx, false),
                child: Text(AppStrings.t('decline_invitation'),
                    style: const TextStyle(color: Colors.red)),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(dialogCtx, true),
                child: Text(AppStrings.t('accept_invitation')),
              ),
            ],
          ),
        );
        if (accept == true) {
          final oldRole = _role;
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .set({'role': role}, SetOptions(merge: true));
          await doc.reference.update({'status': 'accepted'});
          UserLogService.instance.log(
            action: 'role_change',
            detail: '${user.email}: ${AppStrings.t('role_$oldRole')} → ${AppStrings.t('role_$role')} (invitation)',
          );
          if (mounted) setState(() => _role = role);
          _snack('Rôle mis à jour: ${AppStrings.t('role_$role')}');
        } else {
          await doc.reference.update({'status': 'declined'});
        }
      }
    } catch (_) {}
  }

  Color _roleColor(String role) {
    switch (role) {
      case 'admin':     return kTeal;
      case 'moderator': return const Color(0xFF9B59B6);
      case 'operator':  return kOrange;
      case 'observer':  return const Color(0xFF5B8DB8);
      default:          return Colors.grey;
    }
  }

  Future<void> _pickImage() async {
    final input = html.FileUploadInputElement()..accept = 'image/*';
    input.click();
    await input.onChange.first;
    if (input.files == null || input.files!.isEmpty) return;
    final file = input.files!.first;
    if (file.size > 2 * 1024 * 1024) {
      _snack('Image too large (max 2 MB)', isError: true);
      return;
    }
    setState(() => _isUploadingImage = true);
    final reader = html.FileReader();
    reader.readAsDataUrl(file);
    await reader.onLoad.first;
    final result = reader.result as String;
    // result = "data:image/jpeg;base64,XXX"
    final base64 = result.contains(',') ? result.split(',').last : result;
    setState(() {
      _avatarImageBase64 = base64;
      _isUploadingImage = false;
    });
  }

  Future<void> _removeImage() async {
    setState(() => _avatarImageBase64 = null);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      await FirebaseFirestore.instance.collection('users').doc(uid).update(
          {'avatarImageBase64': FieldValue.delete()});
    }
  }

  Future<void> _saveProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final parts = _displayNameCtrl.text.trim().split(' ');
    final newFirst = parts.isNotEmpty ? parts.first : '';
    final newLast  = parts.length > 1 ? parts.sublist(1).join(' ') : '';
    // customId is fixed once assigned — never allow it to change
    final newId    = _customId ?? _customIdCtrl.text.trim().toUpperCase();

    if (newId.length < 4) {
      _snack('ID must be at least 4 characters', isError: true);
      return;
    }

    setState(() => _isSaving = true);
    try {
      final colorIdx = _avatarColors.indexOf(_avatarColor);

      final Map<String, dynamic> updateData = {
        'firstName': newFirst,
        'lastName':  newLast,
        'displayName': '$newFirst $newLast'.trim(),
        'customId':  newId,
        'poste':     _poste ?? '',
        'email':     user.email,
        'avatarColorIdx': colorIdx < 0 ? 0 : colorIdx,
        'presenceStatus': _presenceStatus,
      };
      if (_avatarImageBase64 != null) {
        updateData['avatarImageBase64'] = _avatarImageBase64!;
      }

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .set(updateData, SetOptions(merge: true));

      await user.updateDisplayName('$newFirst $newLast'.trim());
      _customId = newId;
      UserAvatar.invalidateCache(user.uid);

      _snack('Profile saved successfully');
    } catch (e) {
      _snack('Error saving profile: $e', isError: true);
    }
    if (mounted) setState(() => _isSaving = false);
  }

  Future<void> _changePassword() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final newPw  = _newPwCtrl.text;
    final confPw = _confirmPwCtrl.text;
    final currPw = _currentPwCtrl.text;

    if (currPw.isEmpty || newPw.isEmpty || confPw.isEmpty) {
      _snack('Fill all password fields', isError: true);
      return;
    }
    if (newPw != confPw) {
      _snack('Passwords do not match', isError: true);
      return;
    }
    if (!_isPasswordStrong(newPw)) {
      _snack('Password does not meet security requirements', isError: true);
      return;
    }
    setState(() => _isSaving = true);
    try {
      // Re-authenticate first
      final cred = EmailAuthProvider.credential(
          email: user.email!, password: currPw);
      await user.reauthenticateWithCredential(cred);
      await user.updatePassword(newPw);
      _currentPwCtrl.clear();
      _newPwCtrl.clear();
      _confirmPwCtrl.clear();
      _snack('Password changed successfully');
    } on FirebaseAuthException catch (e) {
      _snack(e.message ?? 'Auth error', isError: true);
    } catch (e) {
      _snack('Error: $e', isError: true);
    }
    if (mounted) setState(() => _isSaving = false);
  }

  bool _isPasswordStrong(String pw) =>
      pw.length >= 8 &&
      pw.contains(RegExp(r'[A-Z]')) &&
      pw.contains(RegExp(r'[a-z]')) &&
      pw.contains(RegExp(r'[0-9]')) &&
      pw.contains(RegExp(r'[!@#\$%^&*(),.?":{}|<>_\-]'));

  void _snack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? const Color(0xFFE74C3C) : kTeal.withValues(alpha: 0.9),
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<void> _changePresence(String status) async {
    // Optimistic update — UI changes immediately regardless of network
    if (mounted) setState(() => _presenceStatus = status);
    try {
      await PresenceService.instance.setStatus(status);
      await FirebaseFirestore.instance
          .collection('users')
          .doc(FirebaseAuth.instance.currentUser?.uid)
          .set({'presenceStatus': status}, SetOptions(merge: true));
    } catch (_) {}
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isMobile = _isMobile;
    return Scaffold(
      backgroundColor: _c.bg,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: kTeal))
          : SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                  isMobile ? 16 : 32, isMobile ? 16 : 32, isMobile ? 16 : 32, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(),
                  SizedBox(height: isMobile ? 16 : 32),
                  if (isMobile) ...[  
                    _buildAvatarCard(),
                    const SizedBox(height: 16),
                    _buildInfoCard(),
                  ] else
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 1, child: _buildAvatarCard()),
                        const SizedBox(width: 24),
                        Expanded(flex: 2, child: _buildInfoCard()),
                      ],
                    ),
                  const SizedBox(height: 24),
                  _buildPasswordCard(),
                ],
              ),
            ),
    );
  }

  Widget _buildHeader() {
    final isMobile = _isMobile;
    final badges = <Widget>[
      _presenceBadge('online',  Icons.circle,               kTeal,       'En ligne',        showLabel: !isMobile),
      const SizedBox(width: 8),
      _presenceBadge('dnd',     Icons.remove_circle_outline, kOrange,    'Ne pas déranger', showLabel: !isMobile),
      const SizedBox(width: 8),
      _presenceBadge('offline', Icons.circle_outlined,       Colors.grey, 'Hors ligne',      showLabel: !isMobile),
    ];
    if (isMobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Mon Profil',
              style: TextStyle(
                  color: _c.textPri, fontWeight: FontWeight.bold, fontSize: 20)),
          const SizedBox(height: 10),
          Row(mainAxisSize: MainAxisSize.min, children: badges),
        ],
      );
    }
    return Row(
      children: [
        Text('Mon Profil',
            style: TextStyle(
                color: _c.textPri, fontWeight: FontWeight.bold, fontSize: 22)),
        const Spacer(),
        ...badges,
      ],
    );
  }

  Widget _presenceBadge(
      String status, IconData icon, Color color, String label,
      {bool showLabel = true}) {
    final active = _presenceStatus == status;
    return GestureDetector(
      onTap: () => _changePresence(status),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: EdgeInsets.symmetric(horizontal: showLabel ? 14 : 8, vertical: 8),
        decoration: BoxDecoration(
          color: active ? color.withValues(alpha: 0.18) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: active ? color : _c.divider.withValues(alpha: 0.3)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: active ? color : _c.textSec, size: 14),
          if (showLabel) ...[  
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    color: active ? color : _c.textSec,
                    fontSize: 12,
                    fontWeight:
                        active ? FontWeight.bold : FontWeight.normal)),
          ],
        ]),
      ),
    );
  }

  Widget _buildAvatarCard() {
    final user = FirebaseAuth.instance.currentUser;
    final initials = _displayNameCtrl.text.trim().isEmpty
        ? (user?.email ?? '?').substring(0, 1).toUpperCase()
        : _displayNameCtrl.text
            .trim()
            .split(' ')
            .map((p) => p.isEmpty ? '' : p[0].toUpperCase())
            .take(2)
            .join();

    // Decoded avatar image (if any)
    final imageBytes = _avatarImageBase64 != null
        ? (() {
            try { return base64Decode(_avatarImageBase64!); }
            catch (_) { return null; }
          })()
        : null;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
          color: _c.card, borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: [
          // Avatar circle with edit overlay
          Stack(
            alignment: Alignment.bottomRight,
            children: [
              CircleAvatar(
                radius: 52,
                backgroundColor: _avatarColor,
                backgroundImage:
                    imageBytes != null ? MemoryImage(imageBytes) : null,
                child: imageBytes == null
                    ? Text(initials,
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 28))
                    : null,
              ),
              // Edit button overlay
              GestureDetector(
                onTap: _isUploadingImage ? null : _pickImage,
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: kTeal,
                    shape: BoxShape.circle,
                    border: Border.all(color: _c.bg, width: 2),
                  ),
                  child: _isUploadingImage
                      ? const Padding(
                          padding: EdgeInsets.all(5),
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.black54))
                      : const Icon(Icons.camera_alt_rounded,
                          color: Colors.black87, size: 16),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Upload / Remove buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton.icon(
                onPressed: _isUploadingImage ? null : _pickImage,
                icon: const Icon(Icons.upload_rounded, size: 14),
                label: Text(imageBytes != null
                    ? 'Changer la photo'
                    : 'Télécharger une photo',
                    style: const TextStyle(fontSize: 12)),
                style: TextButton.styleFrom(foregroundColor: kTeal),
              ),
              if (imageBytes != null) ...[
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: _removeImage,
                  icon: const Icon(Icons.delete_outline_rounded, size: 14),
                  label: const Text('Supprimer',
                      style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFFE74C3C)),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Text(_displayNameCtrl.text.trim().isEmpty
              ? user?.email ?? ''
              : _displayNameCtrl.text.trim(),
              style: TextStyle(
                  color: _c.textPri,
                  fontWeight: FontWeight.bold,
                  fontSize: 15),
              textAlign: TextAlign.center),
          const SizedBox(height: 4),
          const SizedBox(height: 6),
          // Firebase UID — shown for easy lookup in Firebase console
          Builder(builder: (_) {
            final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
            if (uid.isEmpty) return const SizedBox.shrink();
            return GestureDetector(
              onTap: () => Clipboard.setData(ClipboardData(text: uid))
                  .then((_) => _snack('Firebase UID copied')),
              child: Tooltip(
                message: 'Tap to copy Firebase UID',
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.fingerprint, size: 13,
                        color: Colors.grey.withValues(alpha: 0.6)),
                    const SizedBox(width: 4),
                    Text(
                      uid.length > 16
                          ? '${uid.substring(0, 8)}…${uid.substring(uid.length - 6)}'
                          : uid,
                      style: TextStyle(
                          color: Colors.grey.withValues(alpha: 0.6),
                          fontSize: 10,
                          fontFamily: 'monospace'),
                    ),
                  ],
                ),
              ),
            );
          }),
          const SizedBox(height: 20),
          // Color picker (only shown when no image)
          if (imageBytes == null) ...[
            Text('Couleur de l\'avatar',
                style: TextStyle(color: _c.textSec, fontSize: 12)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: _avatarColors.map((color) {
                final selected = _avatarColor == color;
                return GestureDetector(
                  onTap: () => setState(() => _avatarColor = color),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: selected ? 32 : 28,
                    height: selected ? 32 : 28,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: selected
                              ? Colors.white
                              : Colors.transparent,
                          width: 2.5),
                      boxShadow: selected
                          ? [
                              BoxShadow(
                                  color: color.withValues(alpha: 0.5),
                                  blurRadius: 8)
                            ]
                          : null,
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
          color: _c.card, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Profile Information'),
          const SizedBox(height: 20),
          // Display name
          _fieldLabel('Display Name'),
          _textField(_displayNameCtrl,
              hint: 'Jean Dupont',
              icon: Icons.person_outline,
              onChanged: (_) => setState(() {})),
          const SizedBox(height: 16),
          // Email (read-only)
          _fieldLabel('Email address'),
          _textField(_emailCtrl,
              hint: 'your@email.com',
              icon: Icons.email_outlined,
              readOnly: true),
          const SizedBox(height: 16),
          // Firebase UID (read-only, copyable)
          _fieldLabel(AppStrings.t('firebase_uid')),
          Builder(builder: (_) {
            final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
            final uidCtrl = TextEditingController(text: uid);
            return Row(
              children: [
                Expanded(
                  child: _textField(uidCtrl,
                      hint: 'Firebase UID',
                      icon: Icons.fingerprint_outlined,
                      readOnly: true),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.copy_outlined, size: 18),
                  tooltip: 'Copy UID',
                  color: kTeal,
                  onPressed: () => Clipboard.setData(ClipboardData(text: uid))
                      .then((_) => _snack('Firebase UID copied')),
                ),
              ],
            );
          }),
          const SizedBox(height: 20),
          // Role badge
          _fieldLabel(AppStrings.t('your_role')),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: _roleColor(_role).withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _roleColor(_role)),
                ),
                child: Text(
                  AppStrings.t('role_$_role'),
                  style: TextStyle(
                    color: _roleColor(_role),
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
              if (_role == 'admin' || _role == 'moderator') ...[
                OutlinedButton.icon(
                  onPressed: _showManageUsersDialog,
                  icon: const Icon(Icons.manage_accounts_outlined, size: 16),
                  label: Text(AppStrings.t('manage_users')),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: kTeal,
                    side: BorderSide(color: kTeal),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20)),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _showInviteUserDialog,
                  icon: const Icon(Icons.person_add_outlined, size: 16),
                  label: Text(AppStrings.t('invite_user')),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF9B59B6),
                    side: const BorderSide(color: Color(0xFF9B59B6)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20)),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: _isSaving ? null : _saveProfile,
              icon: _isSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.black54))
                  : const Icon(Icons.save_outlined, size: 18),
              label: const Text('Save Changes',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: kTeal,
                foregroundColor: Colors.black87,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPasswordCard() {
    final isMobile = _isMobile;
    final leftCol = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel('Current Password'),
        _pwField(_currentPwCtrl, _currentPwVisible,
            () => setState(() => _currentPwVisible = !_currentPwVisible)),
        const SizedBox(height: 16),
        _fieldLabel('New Password'),
        _pwField(_newPwCtrl, _pwVisible,
            () => setState(() => _pwVisible = !_pwVisible)),
        const SizedBox(height: 8),
        _buildPwRules(_newPwCtrl.text),
      ],
    );
    final rightCol = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!isMobile) const SizedBox(height: 40),
        _fieldLabel('Confirm New Password'),
        _pwField(_confirmPwCtrl, _confirmVisible,
            () => setState(() => _confirmVisible = !_confirmVisible)),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton.icon(
            onPressed: _isSaving ? null : _changePassword,
            icon: const Icon(Icons.lock_reset_outlined, size: 18),
            label: const Text('Update Password',
                style: TextStyle(fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: kOrange,
              foregroundColor: Colors.black87,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
      ],
    );
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
          color: _c.card, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Change Password'),
          const SizedBox(height: 20),
          if (isMobile) ...[  
            leftCol,
            const SizedBox(height: 16),
            rightCol,
          ] else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: leftCol),
                const SizedBox(width: 24),
                Expanded(child: rightCol),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildPwRules(String pw) {
    Widget rule(bool ok, String text) => Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(children: [
            Icon(ok ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                size: 14,
                color: ok ? kTeal : _c.textSec.withValues(alpha: 0.5)),
            const SizedBox(width: 6),
            Text(text,
                style: TextStyle(
                    fontSize: 12,
                    color: ok ? kTeal : _c.textSec.withValues(alpha: 0.6))),
          ]),
        );

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      rule(pw.length >= 8, 'At least 8 characters'),
      rule(pw.contains(RegExp(r'[A-Z]')), 'At least one uppercase letter'),
      rule(pw.contains(RegExp(r'[a-z]')), 'At least one lowercase letter'),
      rule(pw.contains(RegExp(r'[0-9]')), 'At least one number'),
      rule(pw.contains(RegExp(r'[!@#\$%^&*(),.?":{}|<>_\-]')),
          'At least one special character'),
    ]);
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  Widget _sectionTitle(String title) => Text(title,
      style: TextStyle(
          color: _c.textPri, fontWeight: FontWeight.bold, fontSize: 16));

  Widget _fieldLabel(String label) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(label,
            style: TextStyle(
                color: _c.textSec, fontSize: 12, fontWeight: FontWeight.w500)),
      );

  Widget _textField(
    TextEditingController ctrl, {
    required String hint,
    required IconData icon,
    bool readOnly = false,
    void Function(String)? onChanged,
    List<TextInputFormatter>? inputFormatters,
  }) =>
      TextField(
        controller: ctrl,
        readOnly: readOnly,
        onChanged: onChanged,
        inputFormatters: inputFormatters,
        style: TextStyle(color: _c.textPri, fontSize: 14),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: _c.textSec, fontSize: 13),
          prefixIcon: Icon(icon, color: _c.textSec, size: 18),
          filled: true,
          fillColor: _c.inputFill,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: _c.divider)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: _c.divider)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: kTeal, width: 1.5)),
        ),
      );

  Widget _pwField(TextEditingController ctrl, bool visible, VoidCallback toggle) {
    return TextField(
      controller: ctrl,
      obscureText: !visible,
      onChanged: (_) => setState(() {}),
      style: TextStyle(color: _c.textPri, fontSize: 14),
      decoration: InputDecoration(
        hintText: '••••••••',
        hintStyle: TextStyle(color: _c.textSec, fontSize: 13),
        prefixIcon: Icon(Icons.lock_outline_rounded, color: _c.textSec, size: 18),
        suffixIcon: IconButton(
          onPressed: toggle,
          icon: Icon(
              visible ? Icons.visibility_off_outlined : Icons.visibility_outlined,
              color: _c.textSec, size: 18),
        ),
        filled: true,
        fillColor: _c.inputFill,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: _c.divider)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: _c.divider)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: kTeal, width: 1.5)),
      ),
    );
  }
}
