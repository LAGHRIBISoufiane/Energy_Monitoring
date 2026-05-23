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
        setS(() => error = 'Entrez un nom ou un #ID');
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
          // Name prefix search — title-case for typical storage format
          final name = raw[0].toUpperCase() + raw.substring(1).toLowerCase();
          final q1 = await FirebaseFirestore.instance
              .collection('users')
              .where('firstName', isGreaterThanOrEqualTo: name)
              .where('firstName', isLessThanOrEqualTo: '$name\uf8ff')
              .limit(5)
              .get();
          final q2 = await FirebaseFirestore.instance
              .collection('users')
              .where('lastName', isGreaterThanOrEqualTo: name)
              .where('lastName', isLessThanOrEqualTo: '$name\uf8ff')
              .limit(5)
              .get();
          final seen = <String>{};
          for (final d in [...q1.docs, ...q2.docs]) {
            if (!seen.add(d.id)) continue;
            final r = toRecord(d.id, d.data());
            if (r != null) found.add(r);
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
                  hintText: 'Nom, #ID ou UID Firebase',
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
                  leading: CircleAvatar(
                    radius: 18,
                    backgroundColor: kTeal.withValues(alpha: 0.2),
                    child: Text(
                      u.name.isNotEmpty ? u.name[0].toUpperCase() : '?',
                      style: const TextStyle(color: kTeal, fontSize: 13,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
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
      setState(() => _openDm = selected);
    }
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
        _UserListView(onSelectUser: (u) => setState(() => _openDm = u)),
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

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('users').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: kTeal));
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(
              child: Text('No other users found.',
                  style: TextStyle(color: c.textSec)));
        }

        final users = snapshot.data!.docs
            .where((d) => d.id != myUid)
            .map((d) {
          final data = d.data() as Map<String, dynamic>;
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
                  : email.isNotEmpty ? email : d.id;
          return UserRecord(
            uid: d.id,
            name: displayName,
            customId: data['customId'] as String? ?? '',
            email:    email,
          );
        }).toList();

        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: users.length,
          itemBuilder: (_, i) {
            final user = users[i];
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
                      CircleAvatar(
                        backgroundColor: kTeal.withValues(alpha: 0.2),
                        child: Text(
                          user.name.isEmpty
                              ? '?'
                              : user.name[0].toUpperCase(),
                          style: TextStyle(
                              color: kTeal,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
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
                  title: Text(user.name,
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
                  onTap: () => onSelectUser(user.copyWith(presenceStatus: status)),
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
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: kTeal.withValues(alpha: 0.2),
                      child: Text(
                        widget.peer.name.isEmpty
                            ? '?'
                            : widget.peer.name[0].toUpperCase(),
                        style: const TextStyle(
                            color: kTeal, fontWeight: FontWeight.bold),
                      ),
                    ),
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

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('users').snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(
              child: CircularProgressIndicator(color: kTeal));
        }

        final docs = snapshot.data!.docs
            .where((d) => d.id != myUid)
            .toList();

        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          itemCount: docs.isEmpty ? 1 : docs.length,
          itemBuilder: (context, index) {
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
                      Text('Aucun utilisateur trouvé',
                          style: TextStyle(
                              color: colors.textSec, fontSize: 14)),
                    ],
                  ),
                ),
              );
            }

            final doc = docs[index];
            final data = doc.data() as Map<String, dynamic>;
            final firstName = (data['firstName'] as String? ?? '').trim();
            final lastName  = (data['lastName']  as String? ?? '').trim();
            final fsDisplayName = (data['displayName'] as String? ?? '').trim();
            final name = '$firstName $lastName'.trim().isNotEmpty
                ? '$firstName $lastName'.trim()
                : fsDisplayName;
            final email = data['email'] as String? ?? '';
            final displayName = name.isNotEmpty
                ? name
                : email.contains('@')
                    ? email.split('@').first
                    : email.isNotEmpty ? email : doc.id;
            final avatarBase64 = data['avatarImageBase64'] as String?;
            final avatarColorIdx = (data['avatarColorIdx'] as int?) ?? 0;
            const avatarColors = [
              Color(0xFF4ECDC4), Color(0xFFF5A623), Color(0xFFE74C3C),
              Color(0xFF9B59B6), Color(0xFF3498DB), Color(0xFF2ECC71),
              Color(0xFFFF6B8A), Color(0xFF1ABC9C),
            ];
            final avatarColor =
                avatarColors[avatarColorIdx.clamp(0, avatarColors.length - 1)];
            final initials = displayName.isEmpty
                ? '?'
                : displayName.split(' ').map((p) => p.isEmpty ? '' : p[0]).take(2).join().toUpperCase();

            return StreamBuilder<Map<String, dynamic>?>(
              stream: PresenceService.instance.watchPresence(doc.id),
              builder: (context, presSnap) {
                final presence = presSnap.data;
                final status =
                    (presence?['status'] as String?) ?? 'offline';
                final isOnline = status == 'online';
                final isDnd = status == 'dnd';

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
                      // Avatar
                      Stack(
                        alignment: Alignment.bottomRight,
                        children: [
                          CircleAvatar(
                            radius: 22,
                            backgroundColor: avatarColor,
                            backgroundImage: avatarBase64 != null
                                ? MemoryImage(_safeDecode(avatarBase64) ?? Uint8List(0))
                                : null,
                            child: avatarBase64 == null
                                ? Text(initials,
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13))
                                : null,
                          ),
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
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              displayName,
                              style: TextStyle(
                                  color: colors.textPri,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14),
                            ),

                          ],
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
  }

  static Uint8List? _safeDecode(String b64) {
    try {
      return base64Decode(b64);
    } catch (_) {
      return null;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared Message Bubble
// ─────────────────────────────────────────────────────────────────────────────
class _MessageBubble extends StatelessWidget {
  final ChatMessage msg;
  final bool isMine;
  const _MessageBubble({required this.msg, required this.isMine});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
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
            CircleAvatar(
              radius: 16,
              backgroundColor: kTeal.withValues(alpha: 0.2),
              child: Text(
                msg.senderName.isEmpty
                    ? '?'
                    : msg.senderName[0].toUpperCase(),
                style: const TextStyle(
                    color: kTeal, fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ),
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
                    Row(children: [
                      Text(msg.senderName,
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
                    ]),
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
