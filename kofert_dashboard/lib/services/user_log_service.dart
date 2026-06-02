import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../main.dart' show roleNotifier;

/// Writes a single entry to the `user_logs` Firestore collection.
/// Call this from any screen on significant user actions.
///
/// Actions: login, logout, settings_change, role_change,
///          alert_created, maintenance, report_sent, data_export, other
class UserLogService {
  UserLogService._();
  static final instance = UserLogService._();

  final _db = FirebaseFirestore.instance;

  Future<void> log({
    required String action,
    String detail = '',
  }) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      await _db.collection('user_logs').add({
        'userId':    user?.uid ?? 'unknown',
        'userEmail': user?.email ?? 'unknown',
        'userName':  user?.displayName ?? '',
        'userRole':  roleNotifier.value,
        'action':    action,
        'detail':    detail,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }
}
