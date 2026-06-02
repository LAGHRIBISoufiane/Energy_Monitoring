import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme/app_colors.dart';
import '../main.dart' show kTeal, kOrange;
import '../models/chat_message.dart';
import '../services/presence_service.dart';
import '../widgets/user_avatar.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ChatScreen – two tabs: Global Chat  |  Direct Messages
// ─────────────────────────────────────────────────────────────────────────────
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen>
    with SingleTickerProviderStateMixin {
  AppColors get _c => AppColors.of(context);
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _c.bg,
      body: Column(
        children: [
          // ── Header ─────────────────────────────────────────────────────────
          Container(
            color: _c.card,
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Messages',
                    style: TextStyle(
                        color: _c.textPri,
                        fontWeight: FontWeight.bold,
                        fontSize: 20)),
                const SizedBox(height: 12),
                TabBar(
                  controller: _tabs,
                  labelColor: kTeal,
                  unselectedLabelColor: _c.textSec,
                  indicatorColor: kTeal,
                  indicatorWeight: 2,
                  tabs: const [
                    Tab(text: 'Global Chat'),
                    Tab(text: 'Messages Directs'),
                    Tab(icon: Icon(Icons.people_alt_rounded, size: 16), text: 'En ligne'),
                  ],
                ),
              ],
            ),
          ),
          // ── Tabs ────────────────────────────────────────────────────────────
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: const [
                _GlobalChatTab(),
                _DirectMessagesTab(),
                _OnlineUsersTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Global Chat Tab
// ─────────────────────────────────────────────────────────────────────────────
class _GlobalChatTab extends StatefulWidget {
  const _GlobalChatTab();

  @override
  State<_GlobalChatTab> createState() => _GlobalChatTabState();
}

class _GlobalChatTabState extends State<_GlobalChatTab> {
  AppColors get _c => AppColors.of(context);
  final _msgCtrl = TextEditingController();
  final _scroll = ScrollController();
  bool _isSending = false;

  User? get _me => FirebaseAuth.instance.currentUser;

  @override
  void dispose() {
    _msgCtrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<String> _getMyName() async {
    final uid = _me?.uid;
    if (uid == null) return 'Anonyme';
    final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    final email = _me?.email ?? '';
    final emailName = email.contains('@') ? email.split('@').first : email;
    final fallback = _me?.displayName ?? (emailName.isNotEmpty ? emailName : 'Anonyme');
    if (!doc.exists) return fallback;
    final d = doc.data()!;
    final first = d['firstName'] as String? ?? '';
    final last  = d['lastName']  as String? ?? '';
    return '$first $last'.trim().isEmpty ? fallback : '$first $last'.trim();
  }

  Future<void> _sendMessage() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty || _isSending) return;
    setState(() => _isSending = true);

    try {
      final name     = await _getMyName();
      await FirebaseFirestore.instance.collection('global_chat').add({
        'senderId':    _me!.uid,
        'senderName':  name,
        'senderEmail': _me?.email ?? '',
        'text':        text,
        'timestamp':   FieldValue.serverTimestamp(),
      });
      _msgCtrl.clear();
      // Scroll to bottom after a brief delay
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.animateTo(
            _scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          );
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'),
                backgroundColor: const Color(0xFFE74C3C)));
      }
    }
    if (mounted) setState(() => _isSending = false);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('global_chat')
                .orderBy('timestamp', descending: false)
                .limitToLast(200)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                    child: CircularProgressIndicator(color: kTeal));
              }
              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return Center(
                  child: Text('No messages yet.\nBe the first to say hello!',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: _c.textSec, fontSize: 14)),
                );
              }
              final msgs = snapshot.data!.docs
                  .map((d) => ChatMessage.fromDoc(d))
                  .toList();
              return ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                itemCount: msgs.length,
                itemBuilder: (_, i) =>
                    _MessageBubble(msg: msgs[i], isMine: msgs[i].senderId == _me?.uid),
              );
            },
          ),
        ),
        _buildInputBar(),
      ],
    );
  }

  Widget _buildInputBar() {
    return Container(
      color: _c.card,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      child: Row(children: [
        Expanded(
          child: TextField(
            controller: _msgCtrl,
            minLines: 1,
            maxLines: 4,
            textInputAction: TextInputAction.newline,
            onSubmitted: (_) => _sendMessage(),
            style: TextStyle(color: _c.textPri, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Write a message…',
              hintStyle: TextStyle(color: _c.textSec, fontSize: 13),
              filled: true,
              fillColor: _c.inputFill,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none),
            ),
          ),
        ),
        const SizedBox(width: 10),
        GestureDetector(
          onTap: _isSending ? null : _sendMessage,
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
                color: kTeal,
                shape: BoxShape.circle),
            child: _isSending
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.black87))
                : const Icon(Icons.send_rounded,
                    color: Colors.black87, size: 20),
          ),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Direct Messages Tab
// ─────────────────────────────────────────────────────────────────────────────
class _DirectMessagesTab extends StatefulWidget {
  const _DirectMessagesTab();

  @override
  State<_DirectMessagesTab> createState() => _DirectMessagesTabState();
}

class _DirectMessagesTabState extends State<_DirectMessagesTab> {
  UserRecord? _openDm;

  Future<void> _addByCustomId() async {
    final c = AppColors.of(context);
    final ctrl = TextEditingController();
    String? error;
    List<UserRecord> results = [];
    bool isSearching = false;

    Future<void> doSearch(StateSetter setS) async {
      final raw = ctrl.text.trim();
      if (raw.isEmpty) {
        setS(() => error = 'Entrez un nom, email ou #ID');
        return;
      }
      setS(() { isSearching = true; error = null; results = []; });

      final myUid = FirebaseAuth.instance.currentUser?.uid;

      // Helper: convert a Firestore doc into a UserRecord, or null if it's self.
      UserRecord? toRecord(String id, Map<String, dynamic> data) {
        if (id == myUid) return null;
        final first = data['firstName'] as String? ?? '';
        final last  = data['lastName']  as String? ?? '';
        final fsDisplayName = data['displayName'] as String? ?? '';
        final email = data['email'] as String? ?? '';
        final fullName = '$first $last'.trim().isNotEmpty
            ? '$first $last'.trim()
            : fsDisplayName;
        final displayName = fullName.isNotEmpty
            ? fullName
            : email.contains('@')
                ? email.split('@').first
                : email.isNotEmpty ? email : id;
        return UserRecord(
          uid: id,
          name: displayName,
          customId: data['customId'] as String? ?? '',
          email: email,
        );
      }

      final List<UserRecord> found = [];
      try {
        if (raw.startsWith('#')) {
          // Exact custom ID search
          final id = raw.substring(1).toUpperCase();
          final q = await FirebaseFirestore.instance
              .collection('users')
              .where('customId', isEqualTo: id)
              .limit(1)
              .get();
          for (final d in q.docs) {
            final r = toRecord(d.id, d.data());
            if (r != null) found.add(r);
          }
        } else if (raw.contains('@')) {
          // Email search
          final q = await FirebaseFirestore.instance
              .collection('users')
              .where('email', isEqualTo: raw.toLowerCase())
              .limit(3)
              .get();
          for (final d in q.docs) {
            final r = toRecord(d.id, d.data());
            if (r != null) found.add(r);
          }
        } else if (raw.length >= 20 &&
                   !raw.contains(' ') &&
                   RegExp(r'^[A-Za-z0-9]+$').hasMatch(raw)) {
          // Looks like a Firebase UID — direct document lookup
          final doc = await FirebaseFirestore.instance
              .collection('users')
              .doc(raw)
              .get();
          if (doc.exists) {
            final r = toRecord(doc.id, doc.data()!);
            if (r != null) found.add(r);
          }
        } else {
          // Full-name / first-name / last-name / displayName search.
          // Firestore range queries are case-sensitive, so we try several
          // capitalisation variants of each token to maximise hit rate.
          List<String> variants(String token) {
            if (token.isEmpty) return [];
            return {
              token,
              token.toLowerCase(),
              token.toUpperCase(),
              token[0].toUpperCase() + token.substring(1).toLowerCase(),
            }.toList();
          }

          final parts = raw.trim().split(RegExp(r'\s+'));
          final seen  = <String>{};

          Future<void> rangeQuery(String field, String prefix) async {
            for (final v in variants(prefix)) {
              final q = await FirebaseFirestore.instance
                  .collection('users')
                  .where(field, isGreaterThanOrEqualTo: v)
                  .where(field, isLessThanOrEqualTo: '$v\uf8ff')
                  .limit(5)
                  .get();
              for (final d in q.docs) {
                if (!seen.add(d.id)) continue;
                final r = toRecord(d.id, d.data());
                if (r != null) found.add(r);
              }
            }
          }

          if (parts.length >= 2) {
            // "Firstname Lastname" — search each part against its field
            await Future.wait([
              rangeQuery('firstName', parts[0]),
              rangeQuery('lastName',  parts[1]),
              rangeQuery('displayName', raw),
            ]);
            // Also cross-check: firstName = parts[0] AND lastName = parts[1]
            // already captured above; additionally try reversed order
            await Future.wait([
              rangeQuery('firstName', parts[1]),
              rangeQuery('lastName',  parts[0]),
            ]);
          } else {
            // Single token — try all name fields
            await Future.wait([
              rangeQuery('firstName',   raw),
              rangeQuery('lastName',    raw),
              rangeQuery('displayName', raw),
            ]);
          }
        }
      } catch (_) {}

      setS(() {
        isSearching = false;
        results = found;
        if (found.isEmpty) error = 'Utilisateur introuvable';
      });
    }

    final UserRecord? selected = await showDialog<UserRecord>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          backgroundColor: c.card,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(children: [
            Icon(Icons.person_search_rounded, color: kTeal),
            const SizedBox(width: 10),
            Text('Ajouter un utilisateur',
                style: TextStyle(color: c.textPri, fontWeight: FontWeight.bold)),
          ]),
          content: SizedBox(
            width: 340,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: ctrl,
                autofocus: true,
                style: TextStyle(color: c.textPri),
                decoration: InputDecoration(
                  hintText: 'Add by Email, UID or by FullName',
                  hintStyle: TextStyle(color: c.textSec),
                  prefixIcon: Icon(Icons.search_rounded, color: c.textSec, size: 20),
                  filled: true,
                  fillColor: c.bg,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: c.divider),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: kTeal),
                  ),
                  errorText: error,
                ),
                onChanged: (_) {
                  if (error != null || results.isNotEmpty) {
                    setS(() { error = null; results = []; });
                  }
                },
                onSubmitted: (_) => doSearch(setS),
              ),
              if (isSearching) ...[const SizedBox(height: 16),
                const Center(child: SizedBox(height: 22, width: 22,
                    child: CircularProgressIndicator(strokeWidth: 2, color: kTeal))),
              ],
              if (results.isNotEmpty) ...[const SizedBox(height: 10),
                ...results.map((u) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: UserAvatar(uid: u.uid, fallbackName: u.name, radius: 18),
                  title: Text(u.name,
                      style: TextStyle(color: c.textPri, fontSize: 14)),
                  trailing: Icon(Icons.arrow_forward_ios_rounded,
                      size: 14, color: c.textSec),
                  onTap: () => Navigator.pop(ctx, u),
                )),
              ],
            ]),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Annuler', style: TextStyle(color: c.textSec)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: kTeal),
              onPressed: isSearching ? null : () => doSearch(setS),
              child: const Text('Rechercher',
                  style: TextStyle(color: Colors.black87)),
            ),
          ],
        ),
      ),
    );
    ctrl.dispose();
    if (selected != null && mounted) {
      await _saveContact(selected);
      if (mounted) setState(() => _openDm = selected);
    }
  }

  // Save a contact entry for both sides (mutual) so they appear in each
  // other's contacts list and Online tab.
  Future<void> _saveContact(UserRecord u) async {
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    if (myUid == null) return;
    try {
      final meDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(myUid)
          .get();
      String myName = FirebaseAuth.instance.currentUser?.displayName ?? '';
      final String myEmail =
          FirebaseAuth.instance.currentUser?.email ?? '';
      if (meDoc.exists) {
        final d = meDoc.data()!;
        final first = d['firstName'] as String? ?? '';
        final last  = d['lastName']  as String? ?? '';
        if ('$first $last'.trim().isNotEmpty) myName = '$first $last'.trim();
      }
      final batch = FirebaseFirestore.instance.batch();
      // Save other user into my contacts
      batch.set(
        FirebaseFirestore.instance
            .collection('contacts')
            .doc(myUid)
            .collection('list')
            .doc(u.uid),
        {
          'uid':      u.uid,
          'name':     u.name,
          'email':    u.email,
          'customId': u.customId,
          'addedAt':  FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      // Save me into the other user's contacts (mutual)
      batch.set(
        FirebaseFirestore.instance
            .collection('contacts')
            .doc(u.uid)
            .collection('list')
            .doc(myUid),
        {
          'uid':      myUid,
          'name':     myName,
          'email':    myEmail,
          'customId': '',
          'addedAt':  FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      await batch.commit();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_openDm != null) {
      return _DmChatView(
        peer: _openDm!,
        onBack: () => setState(() => _openDm = null),
      );
    }
    return Stack(
      children: [
        _UserListView(onSelectUser: (u) async {
          await _saveContact(u);
          if (mounted) setState(() => _openDm = u);
        }),
        Positioned(
          right: 20,
          bottom: 20,
          child: FloatingActionButton.small(
            heroTag: 'dm_add',
            backgroundColor: kTeal,
            tooltip: 'Ajouter par ID',
            onPressed: _addByCustomId,
            child: const Icon(Icons.person_add_rounded, color: Colors.black87),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// User List View
// ─────────────────────────────────────────────────────────────────────────────
class _UserListView extends StatelessWidget {
  final void Function(UserRecord) onSelectUser;
  const _UserListView({required this.onSelectUser});

  Color _statusColor(String status) {
    switch (status) {
      case 'online':  return kTeal;
      case 'dnd':     return kOrange;
      default:        return Colors.grey;
    }
  }

  IconData _statusIcon(String status) {
    switch (status) {
      case 'online':  return Icons.circle;
      case 'dnd':     return Icons.remove_circle;
      default:        return Icons.circle_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final myUid = FirebaseAuth.instance.currentUser?.uid;

    if (myUid == null) {
      return Center(child: Text('Non connecté', style: TextStyle(color: c.textSec)));
    }

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('contacts')
          .doc(myUid)
          .collection('list')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: kTeal));
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.person_add_rounded,
                    color: c.textSec.withValues(alpha: 0.3), size: 48),
                const SizedBox(height: 12),
                Text('Aucun contact.', style: TextStyle(color: c.textSec)),
                const SizedBox(height: 6),
                Text("Utilisez le bouton + pour ajouter quelqu'un.",
                    style: TextStyle(color: c.textSec, fontSize: 12)),
              ],
            ),
          );
        }

        final users = snapshot.data!.docs.map((d) {
          final data = d.data() as Map<String, dynamic>;
          final name     = data['name']     as String? ?? '';
          final email    = data['email']    as String? ?? '';
          final customId = data['customId'] as String? ?? '';
          return UserRecord(uid: d.id, name: name, email: email, customId: customId);
        }).toList();

        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: users.length,
          itemBuilder: (_, i) {
            final user = users[i];
            return StreamBuilder<DocumentSnapshot>(
              // Live-stream the user's profile so name updates instantly
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(user.uid)
                  .snapshots(),
              builder: (context, userSnap) {
                // Resolve the latest display name from the users doc
                String liveName = user.name;
                if (userSnap.hasData && userSnap.data!.exists) {
                  final d = userSnap.data!.data() as Map<String, dynamic>;
                  final first = d['firstName'] as String? ?? '';
                  final last  = d['lastName']  as String? ?? '';
                  final dn    = d['displayName'] as String? ?? '';
                  final full  = '$first $last'.trim();
                  liveName = full.isNotEmpty ? full : dn.isNotEmpty ? dn : user.name;
                }
                final liveUser = user.copyWith(name: liveName);
                return StreamBuilder<Map<String, dynamic>>(
                  stream: PresenceService.instance.watchPresence(user.uid),
                  builder: (context, presSnap) {
                    final status =
                        presSnap.data?['status'] as String? ?? 'offline';
                    return ListTile(
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                      leading: Stack(
                        children: [
                          UserAvatar(uid: liveUser.uid, fallbackName: liveUser.name),
                          Positioned(
                            right: 0,
                            bottom: 0,
                            child: Icon(
                              _statusIcon(status),
                              color: _statusColor(status),
                              size: 13,
                            ),
                          ),
                        ],
                      ),
                      title: Text(liveUser.name,
                          style: TextStyle(
                              color: c.textPri, fontWeight: FontWeight.w600)),
                      subtitle: Text(
                        status == 'online'
                            ? 'Online'
                            : status == 'dnd'
                                ? 'Do Not Disturb'
                                : 'Offline',
                        style: TextStyle(
                            color: _statusColor(status),
                            fontSize: 11,
                            fontWeight: FontWeight.w500),
                      ),
                      onTap: () => onSelectUser(liveUser.copyWith(presenceStatus: status)),
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DM Chat View
// ─────────────────────────────────────────────────────────────────────────────
class _DmChatView extends StatefulWidget {
  final UserRecord peer;
  final VoidCallback onBack;
  const _DmChatView({required this.peer, required this.onBack});

  @override
  State<_DmChatView> createState() => _DmChatViewState();
}

class _DmChatViewState extends State<_DmChatView> {
  AppColors get _c => AppColors.of(context);
  final _msgCtrl = TextEditingController();
  final _scroll  = ScrollController();
  bool _isSending = false;

  User? get _me => FirebaseAuth.instance.currentUser;

  String get _chatId {
    final ids = [_me!.uid, widget.peer.uid]..sort();
    return ids.join('_');
  }

  Future<String> _getMyName() async {
    final uid = _me?.uid;
    if (uid == null) return 'Anonyme';
    final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    final email = _me?.email ?? '';
    final emailName = email.contains('@') ? email.split('@').first : email;
    final fallback = _me?.displayName ?? (emailName.isNotEmpty ? emailName : 'Anonyme');
    if (!doc.exists) return fallback;
    final d = doc.data()!;
    final first = d['firstName'] as String? ?? '';
    final last  = d['lastName']  as String? ?? '';
    return '$first $last'.trim().isEmpty ? fallback : '$first $last'.trim();
  }

  Future<void> _send() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty || _isSending) return;
    setState(() => _isSending = true);
    try {
      final name     = await _getMyName();
      await FirebaseFirestore.instance
          .collection('dm_chats')
          .doc(_chatId)
          .collection('messages')
          .add({
        'senderId':    _me!.uid,
        'senderName':  name,
        'senderEmail': _me?.email ?? '',
        'text':        text,
        'timestamp':   FieldValue.serverTimestamp(),
      });
      _msgCtrl.clear();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.animateTo(_scroll.position.maxScrollExtent,
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut);
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'),
                backgroundColor: const Color(0xFFE74C3C)));
      }
    }
    if (mounted) setState(() => _isSending = false);
  }

  @override
  void dispose() {
    _msgCtrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Back bar
        Container(
          color: _c.card,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(children: [
            IconButton(
              icon: Icon(Icons.arrow_back_rounded, color: _c.textPri),
              onPressed: widget.onBack,
            ),
            StreamBuilder<Map<String, dynamic>>(
              stream: PresenceService.instance.watchPresence(widget.peer.uid),
              builder: (context, snap) {
                final status = snap.data?['status'] as String? ?? 'offline';
                final color = status == 'online' ? kTeal
                    : status == 'dnd' ? kOrange : Colors.grey;
                return Row(children: [
                  Stack(children: [
                    UserAvatar(uid: widget.peer.uid, fallbackName: widget.peer.name, radius: 18),
                    Positioned(
                      right: 0, bottom: 0,
                      child: Icon(
                        status == 'online' ? Icons.circle
                            : status == 'dnd'
                                ? Icons.remove_circle
                                : Icons.circle_outlined,
                        color: color, size: 12),
                    ),
                  ]),
                  const SizedBox(width: 12),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(widget.peer.name,
                        style: TextStyle(
                            color: _c.textPri,
                            fontWeight: FontWeight.bold,
                            fontSize: 15)),
                    Text(
                      status == 'online' ? 'Online'
                          : status == 'dnd' ? 'Do Not Disturb' : 'Offline',
                      style: TextStyle(color: color, fontSize: 11),
                    ),
                  ]),
                ]);
              },
            ),
          ]),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('dm_chats')
                .doc(_chatId)
                .collection('messages')
                .orderBy('timestamp', descending: false)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                    child: CircularProgressIndicator(color: kTeal));
              }
              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return Center(
                  child: Text('No messages yet.\nStart the conversation!',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: _c.textSec, fontSize: 14)),
                );
              }
              final msgs = snapshot.data!.docs
                  .map((d) => ChatMessage.fromDoc(d))
                  .toList();
              return ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                itemCount: msgs.length,
                itemBuilder: (_, i) => _MessageBubble(
                    msg: msgs[i], isMine: msgs[i].senderId == _me?.uid),
              );
            },
          ),
        ),
        _buildInputBar(),
      ],
    );
  }

  Widget _buildInputBar() {
    return Container(
      color: _c.card,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      child: Row(children: [
        Expanded(
          child: TextField(
            controller: _msgCtrl,
            minLines: 1,
            maxLines: 4,
            onSubmitted: (_) => _send(),
            style: TextStyle(color: _c.textPri, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Message ${widget.peer.name}…',
              hintStyle: TextStyle(color: _c.textSec, fontSize: 13),
              filled: true,
              fillColor: _c.inputFill,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none),
            ),
          ),
        ),
        const SizedBox(width: 10),
        GestureDetector(
          onTap: _isSending ? null : _send,
          child: Container(
            width: 44,
            height: 44,
            decoration:
                const BoxDecoration(color: kTeal, shape: BoxShape.circle),
            child: _isSending
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.black87))
                : const Icon(Icons.send_rounded,
                    color: Colors.black87, size: 20),
          ),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Online Users Tab
// ─────────────────────────────────────────────────────────────────────────────
class _OnlineUsersTab extends StatelessWidget {
  const _OnlineUsersTab();

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final myUid = FirebaseAuth.instance.currentUser?.uid;

    if (myUid == null) {
      return Center(
          child: Text('Non connecté', style: TextStyle(color: colors.textSec)));
    }

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('contacts')
          .doc(myUid)
          .collection('list')
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(
              child: CircularProgressIndicator(color: kTeal));
        }

        final docs = snapshot.data!.docs;

        if (docs.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.only(top: 60),
              child: Column(
                children: [
                  Icon(Icons.people_outline_rounded,
                      color: colors.textSec.withValues(alpha: 0.3),
                      size: 48),
                  const SizedBox(height: 12),
                  Text('Aucun contact ajouté',
                      style: TextStyle(color: colors.textSec, fontSize: 14)),
                  const SizedBox(height: 6),
                  Text(
                    'Utilisez l\'onglet "Messages Directs"\npour ajouter des contacts.',
                    style: TextStyle(color: colors.textSec, fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final doc  = docs[index];
            final data = doc.data() as Map<String, dynamic>;
            final nameSnapshot  = (data['name']  as String? ?? '').trim();
            final email = (data['email'] as String? ?? '').trim();
            final fallbackName = nameSnapshot.isNotEmpty
                ? nameSnapshot
                : email.contains('@')
                    ? email.split('@').first
                    : email.isNotEmpty ? email : doc.id;

            return StreamBuilder<DocumentSnapshot>(
              // Live-stream the user's profile so name updates instantly
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(doc.id)
                  .snapshots(),
              builder: (context, userSnap) {
                String displayName = fallbackName;
                if (userSnap.hasData && userSnap.data!.exists) {
                  final d = userSnap.data!.data() as Map<String, dynamic>;
                  final first = d['firstName'] as String? ?? '';
                  final last  = d['lastName']  as String? ?? '';
                  final dn    = d['displayName'] as String? ?? '';
                  final full  = '$first $last'.trim();
                  displayName = full.isNotEmpty ? full : dn.isNotEmpty ? dn : fallbackName;
                }

                return StreamBuilder<Map<String, dynamic>?>(
                  stream: PresenceService.instance.watchPresence(doc.id),
                  builder: (context, presSnap) {
                    final status =
                        (presSnap.data?['status'] as String?) ?? 'offline';
                    final isOnline = status == 'online';
                    final isDnd    = status == 'dnd';

                    final statusColor = isOnline
                        ? kTeal
                        : isDnd
                            ? kOrange
                            : Colors.grey;
                    final statusLabel = isOnline
                        ? 'En ligne'
                        : isDnd
                            ? 'Ne pas déranger'
                            : 'Hors ligne';

                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: colors.card,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isOnline
                              ? kTeal.withValues(alpha: 0.3)
                              : colors.divider.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Row(
                        children: [
                          Stack(
                            alignment: Alignment.bottomRight,
                            children: [
                              UserAvatar(uid: doc.id, fallbackName: displayName, radius: 22),
                              Container(
                                width: 12,
                                height: 12,
                                decoration: BoxDecoration(
                                  color: statusColor,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                      color: colors.bg, width: 1.5),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Text(
                              displayName,
                              style: TextStyle(
                                  color: colors.textPri,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color: statusColor.withValues(alpha: 0.4)),
                            ),
                            child: Text(statusLabel,
                                style: TextStyle(
                                    color: statusColor,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600)),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

}

// ─────────────────────────────────────────────────────────────────────────────
// Shared Message Bubble
// ─────────────────────────────────────────────────────────────────────────────
class _MessageBubble extends StatefulWidget {
  final ChatMessage msg;
  final bool isMine;
  const _MessageBubble({required this.msg, required this.isMine});

  @override
  State<_MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<_MessageBubble> {
  // Static cache shared across all bubbles — one Firestore fetch per unique sender per session
  static final Map<String, String> _nameCache = {};

  Future<String> _resolveName() async {
    if (widget.isMine) return widget.msg.senderName; // own name not shown
    final uid = widget.msg.senderId;
    if (_nameCache.containsKey(uid)) return _nameCache[uid]!;
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      if (doc.exists) {
        final d = doc.data()!;
        final first = d['firstName'] as String? ?? '';
        final last  = d['lastName']  as String? ?? '';
        final dn    = d['displayName'] as String? ?? '';
        final full  = '$first $last'.trim();
        final name  = full.isNotEmpty ? full : dn.isNotEmpty ? dn : widget.msg.senderName;
        _nameCache[uid] = name;
        return name;
      }
    } catch (_) {}
    return widget.msg.senderName;
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final msg = widget.msg;
    final isMine = widget.isMine;
    final time =
        '${msg.timestamp.hour.toString().padLeft(2, '0')}:${msg.timestamp.minute.toString().padLeft(2, '0')}';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment:
            isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMine) ...[
            UserAvatar(uid: msg.senderId, fallbackName: msg.senderName, radius: 16),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isMine
                    ? kTeal.withValues(alpha: 0.85)
                    : c.card,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isMine ? 16 : 4),
                  bottomRight: Radius.circular(isMine ? 4 : 16),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!isMine) ...[
                    FutureBuilder<String>(
                      future: _resolveName(),
                      builder: (context, snap) {
                        final liveName = snap.data ?? msg.senderName;
                        return Row(children: [
                          Text(liveName,
                              style: TextStyle(
                                  color: kTeal,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold)),
                          if (msg.senderEmail.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            Text(msg.senderEmail,
                                style: TextStyle(
                                    color: c.textSec, fontSize: 10)),
                          ],
                        ]);
                      },
                    ),
                    const SizedBox(height: 3),
                  ],
                  Text(msg.text,
                      style: TextStyle(
                          color: isMine ? Colors.black87 : c.textPri,
                          fontSize: 14)),
                  const SizedBox(height: 4),
                  Text(time,
                      style: TextStyle(
                          color: isMine
                              ? Colors.black45
                              : c.textSec.withValues(alpha: 0.5),
                          fontSize: 10)),
                ],
              ),
            ),
          ),
          if (isMine) const SizedBox(width: 8),
        ],
      ),
    );
  }
}
