import 'dart:async';
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../main.dart' show kTeal;

class VerifyEmailScreen extends StatefulWidget {
  const VerifyEmailScreen({super.key});

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  AppColors get _c => AppColors.of(context);
  Timer? _checkTimer;
  Timer? _cooldownTimer;
  bool _resendCooldown = false;
  int _cooldownSeconds = 0;
  String? _message;
  bool _isError = false;
  bool _isChecking = false;

  @override
  void initState() {
    super.initState();
    // Auto-check every 4 seconds
    _checkTimer =
        Timer.periodic(const Duration(seconds: 4), (_) => _silentCheck());
  }

  Future<void> _silentCheck() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      await user.reload();
      final verified =
          FirebaseAuth.instance.currentUser?.emailVerified ?? false;
      if (verified) {
        // Force token refresh so idTokenChanges() fires → StreamBuilder re-routes
        await user.getIdToken(true);
      }
    } catch (_) {}
  }

  Future<void> _manualCheck() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    setState(() => _isChecking = true);
    try {
      await user.reload();
      final verified =
          FirebaseAuth.instance.currentUser?.emailVerified ?? false;
      if (verified) {
        // Force token refresh → idTokenChanges() fires → StreamBuilder re-routes
        await FirebaseAuth.instance.currentUser!.getIdToken(true);
        // The StreamBuilder in main.dart will automatically route to MainScreen
      } else {
        setState(() {
          _isChecking = false;
          _isError = false;
          _message =
              "Email pas encore vérifié. Cliquez sur le lien dans l'email.";
        });
      }
    } catch (e) {
      setState(() {
        _isChecking = false;
        _isError = true;
        _message = 'Erreur: $e';
      });
    }
  }

  Future<void> _resendEmail() async {
    if (_resendCooldown) return;
    try {
      await FirebaseAuth.instance.currentUser?.sendEmailVerification();
      setState(() {
        _isError = false;
        _message = 'Email de vérification renvoyé.';
        _resendCooldown = true;
        _cooldownSeconds = 60;
      });
      _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (_cooldownSeconds <= 1) {
          t.cancel();
          if (mounted) {
            setState(() {
              _resendCooldown = false;
              _cooldownSeconds = 0;
            });
          }
        } else {
          if (mounted) setState(() => _cooldownSeconds--);
        }
      });
    } on FirebaseAuthException catch (e) {
      setState(() {
        _isError = true;
        _message = e.message ?? "Erreur lors de l'envoi.";
      });
    }
  }

  @override
  void dispose() {
    _checkTimer?.cancel();
    _cooldownTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final email =
        FirebaseAuth.instance.currentUser?.email ?? '';
    return Scaffold(
      backgroundColor: _c.bg,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Container(
            margin: const EdgeInsets.all(24),
            padding: const EdgeInsets.all(40),
            decoration: BoxDecoration(
              color: _c.card,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white10),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Icon
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: kTeal.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                      Icons.mark_email_unread_outlined,
                      color: kTeal,
                      size: 40),
                ),
                const SizedBox(height: 24),

                // Title
                Text(
                  'Vérifiez votre email',
                  style: TextStyle(
                      color: _c.textPri,
                      fontWeight: FontWeight.bold,
                      fontSize: 24),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),

                // Subtitle
                Text(
                  'Un lien de vérification a été envoyé à',
                  style: TextStyle(color: _c.textSec, fontSize: 14),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  email,
                  style: const TextStyle(
                      color: kTeal,
                      fontSize: 14,
                      fontWeight: FontWeight.w600),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  "Cliquez sur le lien dans l'email pour activer votre compte.",
                  style: TextStyle(color: _c.textSec, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 28),

                // Message banner
                if (_message != null) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 11),
                    decoration: BoxDecoration(
                      color: (_isError
                              ? const Color(0xFFE74C3C)
                              : kTeal)
                          .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: (_isError
                                ? const Color(0xFFE74C3C)
                                : kTeal)
                            .withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _isError
                              ? Icons.error_outline_rounded
                              : Icons.check_circle_outline_rounded,
                          color: _isError
                              ? const Color(0xFFE74C3C)
                              : kTeal,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _message!,
                            style: TextStyle(
                              color: _isError
                                  ? const Color(0xFFE74C3C)
                                  : kTeal,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Manual check button
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _isChecking ? null : _manualCheck,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kTeal,
                      foregroundColor: Colors.black87,
                      disabledBackgroundColor: kTeal.withValues(alpha: 0.5),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _isChecking
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2.5, color: Colors.black54),
                          )
                        : const Text("J'ai vérifié mon email",
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 14)),
                  ),
                ),
                const SizedBox(height: 12),

                // Resend button
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: OutlinedButton(
                    onPressed: _resendCooldown ? null : _resendEmail,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: kTeal,
                      disabledForegroundColor: _c.textSec,
                      side: BorderSide(
                          color: _resendCooldown
                              ? Colors.white12
                              : kTeal.withValues(alpha: 0.5)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(
                      _resendCooldown
                          ? 'Renvoyer dans ${_cooldownSeconds}s'
                          : "Renvoyer l'email",
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Sign out
                TextButton.icon(
                  onPressed: () => FirebaseAuth.instance.signOut(),
                  icon: const Icon(Icons.logout_rounded, size: 16),
                  label: const Text('Se déconnecter'),
                  style: TextButton.styleFrom(foregroundColor: _c.textSec),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
