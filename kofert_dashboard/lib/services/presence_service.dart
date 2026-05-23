import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

/// Manages user online/offline/DND presence via Firebase Realtime Database.
/// Call [initialize] once after login; call [setStatus] to change the mode.
class PresenceService {
  PresenceService._();
  static final instance = PresenceService._();

  final _db = FirebaseDatabase.instance;
  StreamSubscription? _connectedSub;

  /// Sets up the presence tracking for the currently-logged-in user.
  /// Registers an onDisconnect handler so the user appears offline
  /// automatically if they close the tab.
  void initialize() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final presenceRef = _db.ref('users/$uid/presence');
    final connectedRef = _db.ref('.info/connected');

    _connectedSub?.cancel();
    _connectedSub = connectedRef.onValue.listen((event) {
      if (event.snapshot.value == true) {
        // User came online — register disconnect hook first, then mark online.
        presenceRef.onDisconnect().update({
          'status': 'offline',
          'lastSeen': ServerValue.timestamp,
        });
        presenceRef.update({
          'status': 'online',
          'lastSeen': ServerValue.timestamp,
        });
      }
    });
  }

  /// Explicitly set the current user's status ('online' | 'offline' | 'dnd').
  Future<void> setStatus(String status) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await _db.ref('users/$uid/presence').update({
      'status': status,
      'lastSeen': ServerValue.timestamp,
    });
  }

  /// Stream of presence data for a specific user uid.
  Stream<Map<String, dynamic>> watchPresence(String uid) {
    return _db.ref('users/$uid/presence').onValue.map((event) {
      if (event.snapshot.value == null) return {'status': 'offline'};
      return Map<String, dynamic>.from(
          event.snapshot.value as Map<dynamic, dynamic>);
    });
  }

  void dispose() {
    _connectedSub?.cancel();
  }
}
