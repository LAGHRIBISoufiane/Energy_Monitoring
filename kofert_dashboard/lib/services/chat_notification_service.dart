import 'dart:async';
// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Listens for incoming global and private chat messages while the app shell is
/// mounted, then surfaces them through SnackBars and optional browser alerts.
class ChatNotificationService {
  ChatNotificationService._();

  static final instance = ChatNotificationService._();

  StreamSubscription<QuerySnapshot>? _globalSub;
  StreamSubscription<QuerySnapshot>? _contactsSub;
  final Map<String, StreamSubscription<QuerySnapshot>> _dmSubs = {};
  final Set<String> _seenGlobalIds = {};
  final Set<String> _seenDmIds = {};
  final Set<String> _currentDmChatIds = {};
  final Set<String> _initializedDmChatIds = {};
  bool _globalInitialLoadDone = false;
  DateTime _startedAt = DateTime.now();

  VoidCallback? _onOpenMessages;
  ValueListenable<bool>? _browserNotifications;
  ValueNotifier<int>? _unreadCount;
  bool Function()? _isMessagesOpen;
  GlobalKey<ScaffoldMessengerState>? _messengerKey;

  void initialize({
    required GlobalKey<ScaffoldMessengerState> messengerKey,
    required VoidCallback onOpenMessages,
    required ValueListenable<bool> browserNotifications,
    required ValueNotifier<int> unreadCount,
    bool Function()? isMessagesOpen,
  }) {
    dispose();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    _startedAt = DateTime.now();
    _onOpenMessages = onOpenMessages;
    _browserNotifications = browserNotifications;
    _unreadCount = unreadCount;
    _isMessagesOpen = isMessagesOpen;
    _messengerKey = messengerKey;
    _listenGlobal(uid);
    _listenContacts(uid);
  }

  void dispose() {
    _globalSub?.cancel();
    _contactsSub?.cancel();
    for (final sub in _dmSubs.values) {
      sub.cancel();
    }
    _globalSub = null;
    _contactsSub = null;
    _dmSubs.clear();
    _seenGlobalIds.clear();
    _seenDmIds.clear();
    _currentDmChatIds.clear();
    _initializedDmChatIds.clear();
    _globalInitialLoadDone = false;
    _onOpenMessages = null;
    _browserNotifications = null;
    _unreadCount = null;
    _isMessagesOpen = null;
    _messengerKey = null;
  }

  void _listenGlobal(String uid) {
    _globalSub = FirebaseFirestore.instance
        .collection('global_chat')
        .orderBy('timestamp', descending: true)
        .limit(25)
        .snapshots()
        .listen((snap) {
          if (!_globalInitialLoadDone) {
            for (final doc in snap.docs) {
              _seenGlobalIds.add(doc.id);
            }
            _globalInitialLoadDone = true;
            return;
          }

          for (final change in snap.docChanges) {
            if (change.type != DocumentChangeType.added) continue;
            if (!_seenGlobalIds.add(change.doc.id)) continue;

            final data = change.doc.data();
            if (data == null) continue;
            if ((data['senderId'] as String? ?? '') == uid) {
              continue;
            }
            if (!_isNewEnough(data['timestamp'])) continue;

            final sender = _senderLabel(data);
            final text = (data['text'] as String? ?? '').trim();
            _notify(
              title: 'Nouveau message global',
              detail: '$sender: ${_shorten(text)}',
            );
          }
        });
  }

  void _listenContacts(String uid) {
    _contactsSub = FirebaseFirestore.instance
        .collection('contacts')
        .doc(uid)
        .collection('list')
        .snapshots()
        .listen((snap) {
          final wantedChatIds = <String>{};

          for (final doc in snap.docs) {
            final data = doc.data();
            final peerUid = (data['uid'] as String? ?? doc.id).trim();
            if (peerUid.isEmpty || peerUid == uid) continue;

            final chatId = _chatId(uid, peerUid);
            wantedChatIds.add(chatId);
            if (_dmSubs.containsKey(chatId)) continue;

            final peerName = _contactLabel(data, peerUid);
            _listenDm(uid, peerName, chatId);
          }

          for (final chatId in _currentDmChatIds.difference(wantedChatIds)) {
            _dmSubs.remove(chatId)?.cancel();
            _initializedDmChatIds.remove(chatId);
          }
          _currentDmChatIds
            ..clear()
            ..addAll(wantedChatIds);
        });
  }

  void _listenDm(String uid, String peerName, String chatId) {
    _dmSubs[chatId] = FirebaseFirestore.instance
        .collection('dm_chats')
        .doc(chatId)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .limit(25)
        .snapshots()
        .listen((snap) {
          if (!_initializedDmChatIds.contains(chatId)) {
            for (final doc in snap.docs) {
              _seenDmIds.add('$chatId/${doc.id}');
            }
            _initializedDmChatIds.add(chatId);
            return;
          }

          for (final change in snap.docChanges) {
            if (change.type != DocumentChangeType.added) continue;
            final messageKey = '$chatId/${change.doc.id}';
            if (!_seenDmIds.add(messageKey)) continue;

            final data = change.doc.data();
            if (data == null) continue;
            if ((data['senderId'] as String? ?? '') == uid) {
              continue;
            }
            if (!_isNewEnough(data['timestamp'])) continue;

            final sender = _senderLabel(data, fallback: peerName);
            final text = (data['text'] as String? ?? '').trim();
            _notify(
              title: 'Nouveau message direct',
              detail: '$sender: ${_shorten(text)}',
            );
          }
        });
  }

  void _notify({required String title, required String detail}) {
    _fireBrowserNotification(title, detail);

    if (_isMessagesOpen?.call() != true) {
      _unreadCount?.value = (_unreadCount?.value ?? 0) + 1;
    }

    final messenger = _messengerKey?.currentState;
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF252535),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 6),
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          content: Row(
            children: [
              const Icon(
                Icons.chat_bubble_rounded,
                color: Color(0xFF4ECDC4),
                size: 18,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      detail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          action: _onOpenMessages == null
              ? null
              : SnackBarAction(
                  label: 'Voir',
                  textColor: const Color(0xFF4ECDC4),
                  onPressed: _onOpenMessages!,
                ),
        ),
      );
  }

  void _fireBrowserNotification(String title, String detail) {
    if (_browserNotifications?.value != true) return;
    try {
      if (html.Notification.supported &&
          html.Notification.permission == 'granted') {
        html.Notification(title, body: detail);
      } else if (html.Notification.supported &&
          html.Notification.permission != 'denied') {
        html.Notification.requestPermission();
      }
    } catch (_) {}
  }

  bool _isNewEnough(Object? timestamp) {
    if (timestamp is! Timestamp) return true;
    final messageTime = timestamp.toDate();
    return !messageTime.isBefore(
      _startedAt.subtract(const Duration(seconds: 2)),
    );
  }

  String _chatId(String a, String b) {
    final ids = [a, b]..sort();
    return ids.join('_');
  }

  String _senderLabel(
    Map<String, dynamic> data, {
    String fallback = 'Utilisateur',
  }) {
    final senderName = (data['senderName'] as String? ?? '').trim();
    if (senderName.isNotEmpty) return senderName;
    final senderEmail = (data['senderEmail'] as String? ?? '').trim();
    if (senderEmail.contains('@')) return senderEmail.split('@').first;
    return fallback;
  }

  String _contactLabel(Map<String, dynamic>? data, String fallback) {
    final name = (data?['name'] as String? ?? '').trim();
    if (name.isNotEmpty) return name;
    final email = (data?['email'] as String? ?? '').trim();
    if (email.contains('@')) return email.split('@').first;
    return fallback;
  }

  String _shorten(String text) {
    if (text.isEmpty) return 'Message';
    const maxLen = 90;
    if (text.length <= maxLen) return text;
    return '${text.substring(0, maxLen - 1)}...';
  }
}
